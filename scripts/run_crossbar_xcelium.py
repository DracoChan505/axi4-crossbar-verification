#!/usr/bin/env python3
"""Xcelium/xrun build & regress script for crossbar_uvm7 (reset scenarios).
Tested against xrun 24.03 (UVM built-in, no -uvmhome needed).
Run on the remote server:
  python3 scripts/run_crossbar_xcelium.py build
  python3 scripts/run_crossbar_xcelium.py regress
  python3 scripts/run_crossbar_xcelium.py test --scenario 0 --seed 7
"""
import argparse
import json
import os
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
XRUN = os.environ.get("XRUN", "xrun")  # on PATH in Xcelium installations

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('action', choices=['build', 'test', 'regress'])
p.add_argument('--data-width', type=int, choices=[32, 64], default=32)
p.add_argument('--seed',     type=int, default=7)
p.add_argument('--scenario', type=int, default=0,
               help='0=AW/AR 1=W-mid 2=R-mid 3=B-bp 4=R-bp 5=mixed')
args = p.parse_args()

tag   = f'xcel_d{args.data_width}'
BUILD = ROOT / 'build' / tag
LOGS  = ROOT / 'logs' / tag
LOGS.mkdir(parents=True, exist_ok=True)

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
    ROOT / 'dv/interfaces',
    ROOT / 'dv/master',
    ROOT / 'dv/slave',
    ROOT / 'dv/master_read',
    ROOT / 'dv/slave_read',
]

SCENARIO_NAMES = {
    0: 'AW_AR_in_flight', 1: 'W_mid_burst',  2: 'R_mid_burst',
    3: 'B_backpressure',  4: 'R_backpressure', 5: 'mixed_outstanding',
}

# Common xrun flags shared between compile and run
COMMON = [
    XRUN,
    '-sv', '-uvm',                    # xrun 24.03 bundles UVM, no -uvmhome
    '-define', f'AXI_DATA_W={args.data_width}',
    '-define', 'AXI_ID_W=2',
    '-define', 'AXI_MASTER_ID_W=2',
    '-define', 'AXI_SLAVE_ID_W=4',
    '-top', 'top7',
    '-xmlibdirname', str(BUILD),
    '-timescale', '1ns/1ps',
    '-nowarn', 'CUVWSP',
    '-nowarn', 'COVERM',
    *sum([['-incdir', str(d)] for d in INCDIRS], []),
    *[str(ROOT / f) for f in SOURCES],
]

def build():
    BUILD.mkdir(parents=True, exist_ok=True)
    cmd = COMMON + ['-compile', '-elaborate']
    log = LOGS / 'build.log'
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
    cmd = COMMON + [
        '-run',
        f'+SEED={seed}',
        f'+SCENARIO={scenario}',
        '+UVM_TESTNAME=crossbar_uvm7_test',
        '+UVM_NO_RELNOTES',
    ]
    log = LOGS / f'sc{scenario}_seed{seed}.log'
    run = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                         cwd=ROOT, timeout=360)
    output = run.stdout.decode('utf-8', errors='replace') + run.stderr.decode('utf-8', errors='replace')
    log.write_text(' '.join(str(x) for x in cmd) + '\n' + output)

    counts  = {k: int(v) for k, v in re.findall(r'UVM_(ERROR|FATAL)\s*:\s*(\d+)', output)}
    errors  = re.findall(r'^UVM_(?:ERROR|FATAL)\s+[^\n]*?\[([^\]]+)\]', output, re.MULTILINE)
    snapshot = re.search(r'\[RESET_SNAPSHOT\](.+)', output)
    witness  = re.search(r'\[RESET_WITNESS\](.+)', output)
    passed = (run.returncode == 0 and
              counts == {'ERROR': 0, 'FATAL': 0} and
              not errors and
              '[RESET_PASS]' in output and
              '[RESET_WITNESS]' in output and
              '[RESET_SNAPSHOT]' in output and
              'WATCHDOG' not in output)
    r = dict(scenario=scenario, scenario_name=SCENARIO_NAMES.get(scenario, '?'),
             seed=seed, passed=passed, exit=run.returncode,
             counts=counts, error_ids=errors,
             snapshot=snapshot.group(1).strip() if snapshot else None,
             witness=witness.group(1).strip() if witness else None)
    print(json.dumps(r))
    if not passed:
        print(output[-4000:])
    return r

if args.action == 'build':
    build()

results = ([run_one(args.scenario, args.seed)] if args.action == 'test'
           else [run_one(sc, seed) for sc in range(6) for seed in [7, 41, 2026]])

fname = 'results.json' if args.action == 'regress' else f'sc{args.scenario}_seed{args.seed}.json'
(LOGS / fname).write_text(json.dumps(results, indent=2) + '\n')
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
