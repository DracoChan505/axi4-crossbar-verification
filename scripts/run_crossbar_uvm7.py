#!/usr/bin/env python3
"""UVM 7: in-flight reset scenarios (read+write concurrent, 6 scenarios × 3 seeds × 2 widths)."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('action', choices=['build', 'test', 'regress'])
p.add_argument('--data-width', type=int, choices=[32, 64], default=32)
p.add_argument('--seed', type=int, default=7)
p.add_argument('--scenario', type=int, default=0,
               help='0=AW/AR in-flight 1=W-mid-burst 2=R-mid-burst '
                    '3=B-backpressure 4=R-backpressure 5=mixed-outstanding')
args = p.parse_args()

ALIAS = Path('/tmp') / ('axi-system-uvm7-' + hashlib.sha256(str(ROOT).encode()).hexdigest()[:12])
ALIAS.mkdir(exist_ok=True)
for name, target in [('project', ROOT), ('local', ROOT.parent / 'local-uvm')]:
    link = ALIAS / name
    if link.is_symlink():
        assert link.resolve() == target.resolve()
    elif link.exists():
        raise RuntimeError('Alias path occupied')
    else:
        link.symlink_to(target, target_is_directory=True)

TOOL = ALIAS / 'local/tools/verilator-5.052'
UVM  = ALIAS / 'local/third_party/1800.2-2020.3.2'
PROJ = ALIAS / 'project'
ENV  = dict(os.environ, LC_ALL='C', LANG='C',
            VERILATOR_ROOT=str(TOOL / 'share/verilator'))

tag   = f'uvm7_d{args.data_width}'
BUILD = PROJ / 'build' / tag
LOGS  = ROOT / 'logs' / tag
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

all_files = sorted(set(
    [ROOT / f for f in SOURCES] +
    list((ROOT / 'dv/master').glob('*.svh')) +
    list((ROOT / 'dv/slave').glob('*.svh')) +
    list((ROOT / 'dv/master_read').glob('*.svh')) +
    list((ROOT / 'dv/slave_read').glob('*.svh')) +
    [ROOT / 'dv/interfaces/axi_widths.svh', Path(__file__).resolve()]
))
digest = hashlib.sha256(
    b''.join(str(f.relative_to(ROOT)).encode() + b'\0' + f.read_bytes()
             for f in all_files)
).hexdigest()

if args.action == 'build':
    BUILD.mkdir(parents=True, exist_ok=True)
    command = [
        str(TOOL / 'bin/verilator'), '--binary', '--timing', '--assert',
        '--vpi', '--language', '1800-2017', '-Wno-fatal',
        '--top-module', 'top7', '-j', '4', '--Mdir', str(BUILD),
        f'+define+AXI_DATA_W={args.data_width}',
        '+define+AXI_ID_W=2', '+define+AXI_MASTER_ID_W=2', '+define+AXI_SLAVE_ID_W=4',
        *[f'+incdir+{d}' for d in [
            UVM / 'src',
            PROJ / 'dv/interfaces',
            PROJ / 'dv/master',
            PROJ / 'dv/slave',
            PROJ / 'dv/master_read',
            PROJ / 'dv/slave_read',
        ]],
        '-CFLAGS', '-DUVM_NO_MALLOC -I' + str(UVM / 'src/dpi'),
        str(UVM / 'src/uvm_pkg.sv'),
        *[str(PROJ / f) for f in SOURCES],
        str(UVM / 'src/dpi/uvm_dpi.cc'),
    ]
    started = time.monotonic()
    with (LOGS / 'build.log').open('w') as out:
        out.write(json.dumps(command) + '\n')
        out.flush()
        result = subprocess.run(command, stdout=out, stderr=subprocess.STDOUT,
                                env=ENV, timeout=900)
    elapsed = round(time.monotonic() - started, 2)
    print(json.dumps(dict(build_exit=result.returncode, seconds=elapsed,
                          log=str(LOGS / 'build.log'))), flush=True)
    if result.returncode:
        print((LOGS / 'build.log').read_text()[-9000:])
    else:
        (BUILD / 'source.sha256').write_text(digest)
    raise SystemExit(result.returncode)

if not (BUILD / 'source.sha256').exists() or \
        (BUILD / 'source.sha256').read_text() != digest:
    raise RuntimeError('Build missing or stale; rebuild first')

SCENARIO_NAMES = {
    0: 'AW_AR_in_flight',
    1: 'W_mid_burst',
    2: 'R_mid_burst',
    3: 'B_backpressure',
    4: 'R_backpressure',
    5: 'mixed_outstanding',
}

results = []
if args.action == 'regress':
    runs = [(sc, seed) for sc in range(6) for seed in [7, 41, 2026]]
else:
    runs = [(args.scenario, args.seed)]

for scenario, seed in runs:
    logname = f'sc{scenario}_seed{seed}.log'
    command = [str(BUILD / 'Vtop7'),
               f'+SEED={seed}', f'+verilator+seed+{seed}',
               f'+SCENARIO={scenario}']
    run = subprocess.run(command, capture_output=True, text=True, env=ENV, timeout=360)
    output = run.stdout + run.stderr
    log = LOGS / logname
    log.write_text(json.dumps(command) + '\n' + output)
    counts = {k: int(v) for k, v in re.findall(r'UVM_(ERROR|FATAL)\s*:\s*(\d+)', output)}
    errors  = re.findall(r'^UVM_(?:ERROR|FATAL)\s+[^\n]*?\[([^\]]+)\]', output, re.MULTILINE)
    snapshot = re.search(r'\[RESET_SNAPSHOT\](.+)', output)
    witness  = re.search(r'\[RESET_WITNESS\](.+)', output)
    confirmed = snapshot is not None   # scenario was hit
    passed = (run.returncode == 0 and
              counts == {'ERROR': 0, 'FATAL': 0} and
              not errors and
              '[RESET_PASS]' in output and
              '[RESET_WITNESS]' in output and
              '[RESET_SNAPSHOT]' in output and
              confirmed and
              '$finish' in output and
              'WATCHDOG' not in output and
              '%Error' not in output)
    r = dict(scenario=scenario, scenario_name=SCENARIO_NAMES.get(scenario,'?'),
             seed=seed, passed=passed, exit=run.returncode,
             counts=counts, error_ids=errors,
             snapshot=snapshot.group(1).strip() if snapshot else None,
             witness=witness.group(1).strip() if witness else None,
             log=str(log))
    results.append(r)
    print(json.dumps({k: v for k, v in r.items() if k != 'log'}), flush=True)
    if not passed:
        print(output[-5000:], flush=True)

report = dict(date='2026-11-16', data_width=args.data_width,
              source_sha256=digest, uvm='2020.3.2', results=results)
name = 'results.json' if args.action == 'regress' else f'sc{args.scenario}_seed{args.seed}.json'
(LOGS / name).write_text(json.dumps(report, indent=2) + '\n')
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
