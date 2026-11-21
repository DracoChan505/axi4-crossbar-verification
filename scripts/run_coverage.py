#!/usr/bin/env python3
"""
Build with --coverage, run all 18 UVM7 tests, merge, report line + toggle %.
Usage:
  python3 scripts/run_coverage.py build
  python3 scripts/run_coverage.py regress
  python3 scripts/run_coverage.py report      # just re-run report on existing data
"""
import argparse, hashlib, json, os, re, subprocess, sys, time
from pathlib import Path

ROOT  = Path(__file__).resolve().parents[1]
ALIAS = Path('/tmp') / ('axi-system-uvm7-' + hashlib.sha256(str(ROOT).encode()).hexdigest()[:12])
ALIAS.mkdir(exist_ok=True)
for name, target in [('project', ROOT), ('local', ROOT.parent / 'local-uvm')]:
    lk = ALIAS / name
    if not lk.exists():
        lk.symlink_to(target, target_is_directory=True)

TOOL = ALIAS / 'local/tools/verilator-5.052'
UVM  = ALIAS / 'local/third_party/1800.2-2020.3.2'
PROJ = ALIAS / 'project'
ENV  = dict(os.environ, LC_ALL='C', LANG='C',
            VERILATOR_ROOT=str(TOOL / 'share/verilator'))

COV_TAG  = 'uvm7_cov_d32'
BUILD    = PROJ / 'build' / COV_TAG
COV_DIR  = ROOT / 'coverage' / COV_TAG
LOGS     = ROOT / 'logs'    / COV_TAG
BUILD.mkdir(parents=True, exist_ok=True)
COV_DIR.mkdir(parents=True, exist_ok=True)
LOGS.mkdir(parents=True, exist_ok=True)

SOURCES = [
    'dv/interfaces/axi_write_if.sv',
    'dv/interfaces/axi_read_if.sv',
    'dv/interfaces/axi_reset_if.sv',
    'dv/master/axi_master_pkg.sv',
    'dv/slave/axi_slave_pkg.sv',
    'dv/master_read/axi_master_read_pkg.sv',
    'dv/slave_read/axi_slave_read_pkg.sv',
    *[str(f.relative_to(ROOT)) for f in sorted((ROOT / 'rtl').glob('*.sv'))],
    'dv/tests/crossbar_uvm7/crossbar_uvm7_pkg.sv',
    'dv/tests/crossbar_uvm7/top7.sv',
]

p = argparse.ArgumentParser()
p.add_argument('action', choices=['build', 'regress', 'report'])
args = p.parse_args()

# ── BUILD ────────────────────────────────────────────────────────────────────
if args.action == 'build':
    cmd = [
        str(TOOL / 'bin/verilator'), '--binary', '--timing', '--assert',
        '--vpi', '--language', '1800-2017', '-Wno-fatal',
        '--coverage',                   # ← enables line + toggle coverage
        '--top-module', 'top7', '-j', '4', '--Mdir', str(BUILD),
        '+define+AXI_DATA_W=32',
        '+define+AXI_ID_W=2', '+define+AXI_MASTER_ID_W=2', '+define+AXI_SLAVE_ID_W=4',
        *[f'+incdir+{d}' for d in [
            UVM / 'src', PROJ / 'dv/interfaces', PROJ / 'dv/master',
            PROJ / 'dv/slave', PROJ / 'dv/master_read', PROJ / 'dv/slave_read',
        ]],
        '-CFLAGS', '-DUVM_NO_MALLOC -I' + str(UVM / 'src/dpi'),
        str(UVM / 'src/uvm_pkg.sv'),
        *[str(PROJ / f) for f in SOURCES],
        str(UVM / 'src/dpi/uvm_dpi.cc'),
    ]
    print('Building with coverage...')
    t0 = time.monotonic()
    with (LOGS / 'build.log').open('w') as out:
        out.write(json.dumps(cmd) + '\n')
        r = subprocess.run(cmd, stdout=out, stderr=subprocess.STDOUT, env=ENV, timeout=900)
    print(f'Build {"OK" if r.returncode==0 else "FAILED"} in {time.monotonic()-t0:.1f}s')
    if r.returncode:
        print((LOGS / 'build.log').read_text()[-6000:])
    sys.exit(r.returncode)

# ── REGRESS ──────────────────────────────────────────────────────────────────
if args.action == 'regress':
    SIM = BUILD / 'Vtop7'
    if not SIM.exists():
        sys.exit('Binary missing – run: python3 scripts/run_coverage.py build')

    SCENARIO_NAMES = {
        0:'AW_AR_in_flight', 1:'W_mid_burst', 2:'R_mid_burst',
        3:'B_backpressure',  4:'R_backpressure', 5:'mixed_outstanding',
    }
    runs = [(sc, seed) for sc in range(6) for seed in [7, 41, 2026]]
    cov_files = []
    all_pass = True

    for scenario, seed in runs:
        tag = f'sc{scenario}_seed{seed}'
        cov_out = COV_DIR / f'{tag}.dat'
        cmd = [
            str(SIM),
            f'+SEED={seed}', f'+verilator+seed+{seed}',
            f'+SCENARIO={scenario}',
            f'+verilator+coverage+file+{cov_out}',   # ← per-test coverage file
        ]
        r = subprocess.run(cmd, capture_output=True, text=True, env=ENV, timeout=360)
        out = r.stdout + r.stderr
        (LOGS / f'{tag}.log').write_text(out)

        passed = (r.returncode == 0 and
                  'UVM_ERROR :    0' in out and 'UVM_FATAL :    0' in out and
                  '[RESET_PASS]' in out and '$finish' in out)
        status = '✅ PASS' if passed else '❌ FAIL'
        print(f'{status}  {tag}  ({SCENARIO_NAMES.get(scenario)})')
        if not passed:
            all_pass = False
        if cov_out.exists():
            cov_files.append(str(cov_out))

    print(f'\n{len(cov_files)}/18 coverage files generated')
    if not cov_files:
        sys.exit('No coverage data collected')

    # merge
    merged = COV_DIR / 'merged.dat'
    r = subprocess.run(
        [str(TOOL / 'bin/verilator_coverage'), '--write', str(merged)] + cov_files,
        capture_output=True, text=True, env=ENV)
    if r.returncode or not merged.exists():
        print('Merge failed:', r.stderr)
        sys.exit(1)
    print(f'Merged → {merged}')
    sys.exit(0 if all_pass else 1)

# ── REPORT ───────────────────────────────────────────────────────────────────
if args.action == 'report':
    merged = COV_DIR / 'merged.dat'
    if not merged.exists():
        # try falling back to individual files
        dats = list(COV_DIR.glob('sc*.dat'))
        if not dats:
            sys.exit(f'No coverage data at {COV_DIR}')
        print(f'No merged.dat – merging {len(dats)} files...')
        r = subprocess.run(
            [str(TOOL / 'bin/verilator_coverage'), '--write', str(merged)] + [str(d) for d in dats],
            capture_output=True, text=True, env=ENV)
        if r.returncode:
            print(r.stderr); sys.exit(1)

    # annotate (produces per-file hit/miss counts)
    annotate_dir = COV_DIR / 'annotated'
    annotate_dir.mkdir(exist_ok=True)
    r = subprocess.run(
        [str(TOOL / 'bin/verilator_coverage'),
         '--annotate', str(annotate_dir), str(merged)],
        capture_output=True, text=True, env=ENV)

    # parse annotated files for coverage %
    rtl_dir = ROOT / 'rtl'
    line_hit = line_total = 0
    tog_hit  = tog_total  = 0
    module_stats = {}

    for sv in sorted(rtl_dir.glob('*.sv')):
        ann = annotate_dir / sv.name
        if not ann.exists():
            continue
        lh = lt = th = tt = 0
        for line in ann.read_text(errors='ignore').splitlines():
            # Verilator 5.x annotated format:
            #   ' NNNNNN ...' leading space = covered line (count > 0)
            #   '%NNNNNN ...' % prefix      = uncovered line (count = 0)
            #   '~NNNNNN ...' ~ prefix      = toggle (hit if count > 0)
            if re.match(r'^ \d{6} ', line):
                lt += 1; lh += 1
            elif re.match(r'^%\d{6} ', line):
                lt += 1
            tm = re.match(r'^~(\d{6}) ', line)
            if tm:
                tt += 1
                if int(tm.group(1)) > 0:
                    th += 1
        if lt or tt:
            module_stats[sv.name] = dict(lh=lh, lt=lt, th=th, tt=tt)
            line_hit += lh; line_total += lt
            tog_hit  += th; tog_total  += tt

    if not module_stats:
        # fallback: parse verilator_coverage --rank output for summary numbers
        r2 = subprocess.run(
            [str(TOOL / 'bin/verilator_coverage'), '--rank', str(merged)],
            capture_output=True, text=True, env=ENV)
        print(r2.stdout or r2.stderr)
        sys.exit(0)

    print('\n' + '='*60)
    print('VERILATOR CODE COVERAGE REPORT')
    print('='*60)
    print(f'{"Module":<35} {"Line":>8} {"Toggle":>8}')
    print('-'*60)
    for name, s in sorted(module_stats.items()):
        lp = f"{100*s['lh']//s['lt']:3d}% ({s['lh']}/{s['lt']})" if s['lt'] else '  n/a'
        tp = f"{100*s['th']//s['tt']:3d}% ({s['th']}/{s['tt']})" if s['tt'] else '  n/a'
        print(f"{name:<35} {lp:>8} {tp:>8}")
    print('-'*60)
    lp_total = f"{100*line_hit//line_total:.1f}%" if line_total else "n/a"
    tp_total = f"{100*tog_hit//tog_total:.1f}%"  if tog_total  else "n/a"
    print(f'{"TOTAL":<35} {lp_total:>8} {tp_total:>8}')
    print('='*60)

    # save as JSON too
    out_json = COV_DIR / 'code_coverage.json'
    out_json.write_text(json.dumps(dict(
        line_coverage=dict(hit=line_hit, total=line_total,
                           pct=round(100*line_hit/line_total,1) if line_total else None),
        toggle_coverage=dict(hit=tog_hit, total=tog_total,
                             pct=round(100*tog_hit/tog_total,1) if tog_total else None),
        modules=module_stats,
    ), indent=2))
    print(f'\nFull data → {out_json}')
