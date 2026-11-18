#!/usr/bin/env python3
"""Standalone DECERR endpoint capacity, burst, backpressure and reset checks."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ALIAS = Path('/tmp') / ('axi-decerr-' + hashlib.sha256(str(ROOT).encode()).hexdigest()[:12])
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
ENV = dict(os.environ, LC_ALL='C', LANG='C', VERILATOR_ROOT=str(TOOL / 'share/verilator'))
SOURCES = ['rtl/axi_record_fifo.sv', 'rtl/axi_write_decerr.sv', 'dv/tests/crossbar_write/decerr_tb.sv']
LOGS = ROOT / 'logs/decerr'
LOGS.mkdir(parents=True, exist_ok=True)
results = []
for capacity in (1, 3, 4):
    build = ALIAS / 'project/build' / f'decerr_c{capacity}'
    command = [str(TOOL / 'bin/verilator'), '--binary', '--timing', '--assert',
               '--top-module', 'decerr_tb', '--timescale', '1ns/1ps', '-j', '4',
               '--Mdir', str(build), f'-GCAPACITY={capacity}',
               *[str(ALIAS / 'project' / p) for p in SOURCES]]
    with (LOGS / f'c{capacity}_build.log').open('w') as stream:
        stream.write(json.dumps(command) + '\n')
        stream.flush()
        run = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, env=ENV, timeout=180)
    if run.returncode:
        print((LOGS / f'c{capacity}_build.log').read_text())
        raise SystemExit(run.returncode)
    for negative in ([False, True] if capacity == 4 else [False]):
        command = [str(build / 'Vdecerr_tb')] + (['+BAD_LAST'] if negative else [])
        run = subprocess.run(command, capture_output=True, text=True, env=ENV, timeout=30)
        output = run.stdout + run.stderr
        log = LOGS / f'c{capacity}_{"bad_last" if negative else "normal"}.log'
        log.write_text(json.dumps(command) + '\n' + output)
        if negative:
            passed = run.returncode != 0 and 'DECERR_WLAST' in output and 'MISSING_EXPECTED_ASSERTION' not in output
        else:
            passed = run.returncode == 0 and 'DECERR_PASS' in output and '$finish' in output and '%Error' not in output
        results.append(dict(capacity=capacity, negative=negative, passed=passed, log=str(log)))
        print(json.dumps(results[-1]), flush=True)
report = dict(date='2026-11-15', source_sha256=hashlib.sha256(b''.join((ROOT / p).read_bytes() for p in SOURCES)).hexdigest(), results=results)
(ROOT / 'docs/decerr-results.json').write_text(json.dumps(report, indent=2) + '\n')
raise SystemExit(0 if all(r['passed'] for r in results) else 1)
