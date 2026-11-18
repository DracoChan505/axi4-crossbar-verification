#!/usr/bin/env python3
"""Local integrated AW/W checks; B completion notifications remain modeled."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
ALIAS = Path('/tmp') / ('axi-wpath-' + hashlib.sha256(str(ROOT).encode()).hexdigest()[:12])
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
SOURCES = ['rtl/axi_address_decode.sv', 'rtl/axi_rr_arbiter.sv', 'rtl/axi_write_tracker.sv', 'rtl/axi_record_fifo.sv', 'rtl/axi_write_frontend.sv', 'rtl/axi_write_data_path.sv', 'dv/tests/wpath/wpath_tb.sv']
LOGS = ROOT / 'logs/wpath'
LOGS.mkdir(parents=True, exist_ok=True)
results = []
for inputs, slaves, width, data, ilim, olim in [(4, 4, 32, 32, 2, 4), (3, 2, 32, 32, 3, 3), (1, 1, 32, 32, 1, 1), (4, 4, 64, 64, 2, 4)]:
    tag = f'i{inputs}_s{slaves}_a{width}_d{data}_c{ilim}_{olim}'
    build = ALIAS / 'project/build' / ('wpath_' + tag)
    command = [str(TOOL / 'bin/verilator'), '--binary', '--timing', '--assert',
               '--top-module', 'wpath_tb', '--timescale', '1ns/1ps', '-j', '4',
               '--Mdir', str(build), f'-GINPUTS={inputs}', f'-GSLAVES={slaves}', f'-GADDR_WIDTH={width}',
               f'-GDATA_WIDTH={data}', f'-GINPUT_LIMIT={ilim}', f'-GOUTPUT_LIMIT={olim}',
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
        command = [str(build / 'Vwpath_tb'), f'+SEED={seed}']
        run = subprocess.run(command, capture_output=True, text=True, env=ENV, timeout=30)
        output = run.stdout + run.stderr
        log.write_text(json.dumps(command) + '\n' + output)
        passed = run.returncode == 0 and 'WPATH_PASS ' in output and '$finish' in output and '%Error' not in output
        results.append(dict(config=tag, seed=seed, passed=passed, log=str(log)))
        print(json.dumps(results[-1]), flush=True)
    if inputs == 4 and width == 32:
        for fault in ('BAD_EARLY_LAST', 'BAD_MISSING_LAST'):
            log = LOGS / f'{tag}_{fault}.log'
            command = [str(build / 'Vwpath_tb'), '+' + fault, '+SEED=7']
            run = subprocess.run(command, capture_output=True, text=True, env=ENV, timeout=30)
            output = run.stdout + run.stderr
            log.write_text(json.dumps(command) + '\n' + output)
            passed = run.returncode != 0 and 'WDATA_INPUT_LAST' in output and 'WPATH_PASS' not in output and 'MISSING_EXPECTED_ASSERTION' not in output
            results.append(dict(config=tag, negative=fault, passed=passed, log=str(log)))
            print(json.dumps(results[-1]), flush=True)
report = dict(date='2026-11-15', source_sha256=hashlib.sha256(b''.join((ROOT / p).read_bytes() for p in SOURCES)).hexdigest(),
              tool=subprocess.check_output([str(TOOL / 'bin/verilator'), '--version'], text=True, env=ENV).strip(), results=results)
(ROOT / 'docs/wpath-results.json').write_text(json.dumps(report, indent=2) + '\n')
raise SystemExit(0 if all(row['passed'] for row in results) else 1)
