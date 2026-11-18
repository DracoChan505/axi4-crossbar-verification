#!/usr/bin/env python3
"""Xcelium coverage run: code + functional coverage with imc merge.
xrun 24.03 coverage flags:
  -coverage b:t:f     block(=statement) : toggle : functional(covergroup)
  -covoverwrite       overwrite previous coverage in same cov_work dir
  -covworkdir <dir>   specify coverage work directory (NOT -covdir)
  -covtest <name>     name this coverage test run

Usage:
  python3 scripts/run_crossbar_xcelium_cov.py build
  python3 scripts/run_crossbar_xcelium_cov.py regress
  python3 scripts/run_crossbar_xcelium_cov.py report
"""
import argparse, json, os, re, subprocess, time, shutil, glob
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
XRUN  = os.environ.get("XRUN", "xrun")
IMC   = os.environ.get("IMC", "imc")

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('action', choices=['build', 'test', 'regress', 'report'])
p.add_argument('--data-width', type=int, choices=[32, 64], default=32)
p.add_argument('--seed',     type=int, default=7)
p.add_argument('--scenario', type=int, default=0)
args = p.parse_args()

tag   = f'xcov_d{args.data_width}'
BUILD = ROOT / 'build' / tag
COV   = ROOT / 'cov' / tag
LOGS  = ROOT / 'logs' / tag
LOGS.mkdir(parents=True, exist_ok=True)
COV.mkdir(parents=True, exist_ok=True)

SOURCES = [
    'dv/interfaces/axi_write_if.sv',
    'dv/interfaces/axi_read_if.sv',
    'dv/interfaces/axi_reset_if.sv',
    *[str(f.relative_to(ROOT)) for f in sorted((ROOT / 'rtl').glob('*.sv'))],
    'dv/master/axi_master_pkg.sv',
    'dv/slave/axi_slave_pkg.sv',
    'dv/master_read/axi_master_read_pkg.sv',
    'dv/slave_read/axi_slave_read_pkg.sv',
    'dv/tests/crossbar_uvm7/crossbar_uvm7_pkg.sv',
    'dv/tests/crossbar_uvm7/top7.sv',
]

INCDIRS = [
    ROOT / 'dv/interfaces', ROOT / 'dv/master', ROOT / 'dv/slave',
    ROOT / 'dv/master_read', ROOT / 'dv/slave_read',
]

SCENARIO_NAMES = {
    0: 'AW_AR_in_flight', 1: 'W_mid_burst', 2: 'R_mid_burst',
    3: 'B_backpressure', 4: 'R_backpressure', 5: 'mixed_outstanding',
}

COMMON = [
    XRUN, '-sv', '-uvm',
    '-define', f'AXI_DATA_W={args.data_width}',
    '-define', 'AXI_ID_W=2',
    '-define', 'AXI_MASTER_ID_W=2',
    '-define', 'AXI_SLAVE_ID_W=4',
    '-top', 'top7',
    '-xmlibdirname', str(BUILD),
    '-timescale', '1ns/1ps',
    '-nowarn', 'CUVWSP', '-nowarn', 'COVERM',
    *sum([['-incdir', str(d)] for d in INCDIRS], []),
    *[str(ROOT / f) for f in SOURCES],
]

# Coverage flags: block(=statement) + toggle + functional(covergroup)
COV_FLAGS = [
    '-coverage', 'b:t:f',
    '-covoverwrite',
]

def build():
    BUILD.mkdir(parents=True, exist_ok=True)
    cmd = COMMON + COV_FLAGS + ['-compile', '-elaborate']
    log = LOGS / 'cov_build.log'
    started = time.monotonic()
    with log.open('w') as out:
        out.write(' '.join(str(x) for x in cmd) + '\n')
        out.flush()
        result = subprocess.run(cmd, stdout=out, stderr=subprocess.STDOUT,
                               cwd=ROOT, timeout=600)
    elapsed = round(time.monotonic() - started, 2)
    print(json.dumps(dict(build_exit=result.returncode, seconds=elapsed, log=str(log))))
    if result.returncode:
        print(log.read_text()[-6000:])
    raise SystemExit(result.returncode)

def run_one(scenario, seed):
    # Each run gets its own cov_work dir under COV
    test_name = f'sc{scenario}_seed{seed}'
    cov_work = COV / test_name / 'cov_work'
    if cov_work.exists():
        shutil.rmtree(cov_work.parent)
    cov_work.parent.mkdir(parents=True, exist_ok=True)

    cmd = COMMON + COV_FLAGS + [
        '-run',
        f'+SEED={seed}',
        f'+SCENARIO={scenario}',
        '+UVM_TESTNAME=crossbar_uvm7_test',
        '+UVM_NO_RELNOTES',
        '-covtest', test_name,
        '-covworkdir', str(cov_work.parent),
    ]
    log = LOGS / f'cov_{test_name}.log'
    run = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         cwd=ROOT, timeout=360)
    output = run.stdout.decode('utf-8', errors='replace') + run.stderr.decode('utf-8', errors='replace')
    log.write_text(' '.join(str(x) for x in cmd) + '\n' + output)

    counts = {k: int(v) for k, v in re.findall(r'UVM_(ERROR|FATAL)\s*:\s*(\d+)', output)}
    passed = (run.returncode == 0 and counts == {'ERROR': 0, 'FATAL': 0}
              and '[RESET_PASS]' in output and 'WATCHDOG' not in output)
    cov_exists = cov_work.exists()
    r = dict(scenario=scenario, scenario_name=SCENARIO_NAMES.get(scenario, '?'),
             seed=seed, passed=passed, exit=run.returncode, counts=counts,
             cov_dir=str(cov_work.parent), cov_data=cov_exists)
    print(json.dumps(r))
    if not passed:
        print(output[-4000:])
    return r

def report():
    """Merge all coverage dirs and generate report using imc."""
    # Find all cov_work directories
    cov_works = sorted(COV.glob('sc*/cov_work'))
    if not cov_works:
        print("No coverage dirs found. Run regress first.")
        raise SystemExit(1)

    print(f"Found {len(cov_works)} coverage databases:")
    for cw in cov_works:
        print(f"  {cw}")

    merged_dir = COV / 'merged'
    if merged_dir.exists():
        shutil.rmtree(merged_dir)
    merged_dir.mkdir(parents=True)

    # Create imc TCL script
    script_file = COV / 'imc_merge.tcl'
    with script_file.open('w') as f:
        f.write('# imc merge script\n')
        f.write(f'set_merge_mode -create\n')
        for i, cw in enumerate(cov_works):
            # imc uses -dir pointing to cov_work
            f.write(f'merge -dir {cw}\n')
        f.write(f'write -overwrite -out {merged_dir}/merged.cov\n')
        f.write('report -summary\n')
        f.write(f'write -overwrite -report {merged_dir}/coverage_summary.txt -format text\n')
        f.write('exit\n')

    print(f"\nMerging with imc...")
    result = subprocess.run([IMC, '-exec', str(script_file)],
                          capture_output=True, text=True, timeout=300,
                          cwd=str(COV))
    print("=== imc stdout ===")
    print(result.stdout[-6000:] if result.stdout else "(empty)")
    if result.stderr:
        print("=== imc stderr ===")
        print(result.stderr[-3000:])

    # Try to read summary
    summary_file = merged_dir / 'coverage_summary.txt'
    if summary_file.exists():
        print("\n=== Coverage Summary ===")
        print(summary_file.read_text())
    else:
        # Try alternate report location
        for f in merged_dir.glob('*'):
            print(f"  merged file: {f}")
        # Also check if report was printed to stdout
        if 'COVERAGE' in (result.stdout or ''):
            print("\n=== Coverage from stdout ===")
            for line in result.stdout.split('\n'):
                if 'COVER' in line or 'coverage' in line.lower() or '%' in line:
                    print(line)

if args.action == 'build':
    build()
elif args.action == 'test':
    r = run_one(args.scenario, args.seed)
    raise SystemExit(0 if r['passed'] else 1)
elif args.action == 'regress':
    results = [run_one(sc, seed) for sc in range(6) for seed in [7, 41, 2026]]
    fname = 'cov_results.json'
    (LOGS / fname).write_text(json.dumps(results, indent=2) + '\n')
    passed = sum(r['passed'] for r in results)
    cov_ok = sum(r['cov_data'] for r in results)
    print(f"\n=== Regression: {passed}/{len(results)} passed, {cov_ok}/{len(results)} have coverage ===")
    raise SystemExit(0 if all(r['passed'] for r in results) else 1)
elif args.action == 'report':
    report()
