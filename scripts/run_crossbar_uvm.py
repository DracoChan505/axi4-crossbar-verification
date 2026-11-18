#!/usr/bin/env python3
"""Run existing UVM Master/Slave components around the write Crossbar."""
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
p.add_argument('--inject-memory-fault', action='store_true')
args = p.parse_args()
ALIAS = Path('/tmp') / ('axi-system-uvm-' + hashlib.sha256(str(ROOT).encode()).hexdigest()[:12])
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
UVM = ALIAS / 'local/third_party/1800.2-2020.3.2'
PROJECT = ALIAS / 'project'
ENV = dict(os.environ, LC_ALL='C', LANG='C', VERILATOR_ROOT=str(TOOL / 'share/verilator'))
tag = f'uvm_crossbar_d{args.data_width}'
BUILD = PROJECT / 'build' / tag
LOGS = ROOT / 'logs' / tag
LOGS.mkdir(parents=True, exist_ok=True)
SOURCES = ['dv/interfaces/axi_write_if.sv', 'dv/master/axi_master_pkg.sv', 'dv/slave/axi_slave_pkg.sv',
           *[str(f.relative_to(ROOT)) for f in sorted((ROOT / 'rtl').glob('*.sv'))],
           'dv/checkers/axi_write_checker.sv', 'dv/tests/crossbar_uvm/crossbar_uvm_pkg.sv', 'dv/tests/crossbar_uvm/top.sv']
files = sorted(set([ROOT / f for f in SOURCES] + list((ROOT/'dv/master').glob('*.svh')) +
                   list((ROOT/'dv/slave').glob('*.svh')) + [ROOT/'dv/interfaces/axi_widths.svh', Path(__file__).resolve()]))
digest = hashlib.sha256(b''.join(str(f.relative_to(ROOT)).encode()+b'\0'+f.read_bytes() for f in files)).hexdigest()
if args.action == 'build':
    BUILD.mkdir(parents=True, exist_ok=True)
    command = [str(TOOL/'bin/verilator'), '--binary', '--timing', '--assert', '--vpi', '--language', '1800-2017',
               '-Wno-fatal', '--top-module', 'top', '-j', '4', '--Mdir', str(BUILD),
               f'+define+AXI_DATA_W={args.data_width}', '+define+AXI_ID_W=2', '+define+AXI_MASTER_ID_W=2', '+define+AXI_SLAVE_ID_W=4',
               *[f'+incdir+{f}' for f in [UVM/'src', PROJECT/'dv/interfaces', PROJECT/'dv/master', PROJECT/'dv/slave']],
               '-CFLAGS', '-DUVM_NO_MALLOC -I'+str(UVM/'src/dpi'), str(UVM/'src/uvm_pkg.sv'),
               *[str(PROJECT/f) for f in SOURCES], str(UVM/'src/dpi/uvm_dpi.cc')]
    started = time.monotonic()
    with (LOGS/'build.log').open('w') as out:
        out.write(json.dumps(command)+'\n')
        out.flush()
        result = subprocess.run(command, stdout=out, stderr=subprocess.STDOUT, env=ENV, timeout=900)
    print(json.dumps(dict(build_exit=result.returncode, seconds=round(time.monotonic()-started,2), log=str(LOGS/'build.log'))), flush=True)
    if result.returncode:
        print((LOGS/'build.log').read_text()[-9000:])
    else:
        (BUILD/'source.sha256').write_text(digest)
    raise SystemExit(result.returncode)
if not (BUILD/'source.sha256').exists() or (BUILD/'source.sha256').read_text() != digest:
    raise RuntimeError('Build missing or stale; rebuild this configuration first')
results = []
for seed in ([7,41,2026] if args.action == 'regress' else [args.seed]):
    command = [str(BUILD/'Vtop'), f'+SEED={seed}', f'+verilator+seed+{seed}']
    if args.inject_memory_fault:
        command.append('+INJECT_MEMORY_FAULT')
    run = subprocess.run(command, capture_output=True, text=True, env=ENV, timeout=120)
    output = run.stdout + run.stderr
    suffix = '_memory_fault' if args.inject_memory_fault else ''
    log = LOGS/f'seed{seed}{suffix}.log'
    log.write_text(json.dumps(command)+'\n'+output)
    counts = {key:int(value) for key,value in re.findall(r'UVM_(ERROR|FATAL)\s*:\s*(\d+)',output)}
    errors = re.findall(r'^UVM_(?:ERROR|FATAL)\s+[^\n]*?\[([^\]]+)\]', output, re.MULTILINE)
    passed = run.returncode == 0 and counts == {'ERROR':0,'FATAL':0} and not errors and '[CHECK_PASS]' in output and '[SYS_WITNESS]' in output and '$finish' in output and 'WATCHDOG' not in output and '%Error' not in output
    if args.inject_memory_fault:
        passed = run.returncode == 0 and counts == {'ERROR':1,'FATAL':0} and errors == ['SYS_MEMORY'] and '[CHECK_PASS]' in output and '$finish' in output and 'WATCHDOG' not in output
    results.append(dict(seed=seed, expected_memory_fault=args.inject_memory_fault, passed=passed, exit=run.returncode, counts=counts, error_ids=errors, log=str(log)))
    print(json.dumps(results[-1]), flush=True)
    if not passed:
        print(output[-6000:], flush=True)
report = dict(date='2026-11-15', data_width=args.data_width, master_id_width=2, slave_id_width=4,
              source_sha256=digest, uvm='2020.3.2', results=results)
name = ('results' + ('_memory_fault' if args.inject_memory_fault else '') + '.json') if args.action == 'regress' else f'seed{args.seed}{suffix}_result.json'
(LOGS/name).write_text(json.dumps(report,indent=2)+'\n')
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
