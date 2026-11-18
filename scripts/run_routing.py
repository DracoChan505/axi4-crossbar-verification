#!/usr/bin/env python3
"""Local decoder and round-robin arbiter checks; warnings fail the build."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ALIAS = Path('/tmp') / ('axi-routing-' + hashlib.sha256(str(ROOT).encode()).hexdigest()[:12])
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
SOURCES = ['rtl/axi_address_decode.sv', 'rtl/axi_rr_arbiter.sv', 'dv/tests/routing/routing_tb.sv']
LOGS = ROOT / 'logs/routing'
LOGS.mkdir(parents=True, exist_ok=True)
results = []
for ports, width in [(4, 32), (3, 32), (1, 32), (4, 64)]:
    tag = f'p{ports}_a{width}'
    build = ALIAS / 'project/build' / ('routing_' + tag)
    command = [str(TOOL / 'bin/verilator'), '--binary', '--timing', '--assert',
               '--top-module', 'routing_tb', '--timescale', '1ns/1ps', '-j', '4',
               '--Mdir', str(build), f'-GPORTS={ports}', f'-GADDR_WIDTH={width}',
               *[str(ALIAS / 'project' / path) for path in SOURCES]]
    with (LOGS / f'{tag}_build.log').open('w') as stream:
        stream.write(json.dumps(command) + '\n')
        stream.flush()
        run = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT, env=ENV, timeout=180)
    if run.returncode:
        print((LOGS / f'{tag}_build.log').read_text())
        raise SystemExit(run.returncode)
    for seed in (7, 41, 2026):
        log = LOGS / f'{tag}_s{seed}.log'
        command = [str(build / 'Vrouting_tb'), f'+SEED={seed}']
        run = subprocess.run(command, capture_output=True, text=True, env=ENV, timeout=30)
        output = run.stdout + run.stderr
        log.write_text(json.dumps(command) + '\n' + output)
        passed = run.returncode == 0 and 'ROUTING_PASS ' in output and '$finish' in output and '%Error' not in output
        results.append(dict(config=tag, seed=seed, passed=passed, log=str(log)))
        print(json.dumps(results[-1]), flush=True)
    if ports == 4 and width == 32:
        log = LOGS / f'{tag}_bad_withdraw.log'
        run = subprocess.run([str(build / 'Vrouting_tb'), '+BAD_WITHDRAW'], capture_output=True, text=True, env=ENV, timeout=30)
        output = run.stdout + run.stderr
        log.write_text(output)
        passed = run.returncode != 0 and 'ARBITER_REQUEST_WITHDRAWN' in output and 'MISSING_EXPECTED_ASSERTION' not in output
        results.append(dict(config=tag, negative='withdraw_locked_request', passed=passed, log=str(log)))
        print(json.dumps(results[-1]), flush=True)
report = dict(date='2026-11-15', source_sha256=hashlib.sha256(b''.join((ROOT / p).read_bytes() for p in SOURCES)).hexdigest(),
              tool=subprocess.check_output([str(TOOL / 'bin/verilator'), '--version'], text=True, env=ENV).strip(), results=results)
(ROOT / 'docs/routing-results.json').write_text(json.dumps(report, indent=2) + '\n')
raise SystemExit(0 if all(row['passed'] for row in results) else 1)
