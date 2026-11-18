#!/usr/bin/env python3
"""Compile and self-check the per-ingress write tracker on local Verilator."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
LOCAL = ROOT.parent / 'local-uvm'
TOOL = LOCAL / 'tools/verilator-5.052'
ALIAS = Path('/tmp') / ('axi-tracker-' + hashlib.sha256(str(ROOT).encode()).hexdigest()[:12])
ALIAS.mkdir(exist_ok=True)
for name, target in [('project', ROOT), ('local', LOCAL)]:
    link = ALIAS / name
    if link.is_symlink():
        assert link.resolve() == target.resolve()
    elif link.exists():
        raise RuntimeError('Alias path occupied')
    else:
        link.symlink_to(target, target_is_directory=True)
ENV = dict(os.environ, LC_ALL="C", LANG="C", VERILATOR_ROOT=str(ALIAS / 'local/tools/verilator-5.052/share/verilator'))
SOURCES = ['rtl/axi_write_tracker.sv', 'dv/tests/tracker/tracker_tb.sv']
LOGS = ROOT / 'logs/tracker'
LOGS.mkdir(parents=True, exist_ok=True)
results = []
for capacity, ids, targets in [(1, 2, 5), (2, 2, 5), (4, 3, 5), (2, 1, 1)]:
    tag = f'c{capacity}_i{ids}_t{targets}'
    build = ALIAS / 'project/build' / ('tracker_' + tag)
    command = [str(ALIAS / 'local/tools/verilator-5.052/bin/verilator'),
               '--binary', '--timing', '--assert', '--top-module', 'tracker_tb',
               '--timescale', '1ns/1ps', '-j', '4', '--Mdir', str(build),
               f'-GCAPACITY={capacity}', f'-GID_WIDTH={ids}', f'-GTARGETS={targets}',
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
        command = [str(build / 'Vtracker_tb'), f'+SEED={seed}']
        run = subprocess.run(command, capture_output=True, text=True, env=ENV, timeout=30)
        output = run.stdout + run.stderr
        log.write_text(json.dumps(command) + '\n' + output)
        passed = run.returncode == 0 and 'TRACKER_PASS ' in output and '$finish' in output and '%Error' not in output
        results.append(dict(config=tag, seed=seed, passed=passed, log=str(log)))
        print(json.dumps(results[-1]), flush=True)
    if capacity == 2 and ids == 2:
        log = LOGS / f'{tag}_bad_completion.log'
        run = subprocess.run([str(build / 'Vtracker_tb'), '+BAD_COMPLETION'], capture_output=True, text=True, env=ENV, timeout=30)
        output = run.stdout + run.stderr
        log.write_text(output)
        passed = run.returncode != 0 and 'TRACKER_UNKNOWN_COMPLETION' in output and 'MISSING_EXPECTED_ASSERTION' not in output
        results.append(dict(config=tag, negative='unknown_completion', passed=passed, log=str(log)))
        print(json.dumps(results[-1]), flush=True)
report = dict(date='2026-11-15', source_sha256=hashlib.sha256(b''.join((ROOT / p).read_bytes() for p in SOURCES)).hexdigest(),
              tool=subprocess.check_output([str(TOOL / 'bin/verilator'), '--version'], text=True, env=ENV).strip(), results=results)
(ROOT / 'docs/tracker-results.json').write_text(json.dumps(report, indent=2) + '\n')
raise SystemExit(0 if all(row['passed'] for row in results) else 1)
