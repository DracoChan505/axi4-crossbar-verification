#!/usr/bin/env python3
"""Build and verify the first Slave increment using the existing local UVM toolchain."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
CASES = [
    "smoke", "w_first", "unaligned", "sparse", "max_burst", "delay",
    "b_stall", "reject", "outside", "reset_partial", "clear",
    "neg_wlast", "neg_strb", "neg_boundary",
]
AUDIT_CASES = [
    "capacity", "same_id", "byte_matrix", "reset_idle", "reset_aw",
    "reset_bdelay", "reset_bvalid", "clear_busy", "clear_reset",
    "offset_window", "delay_one", "integration", "invalid_cfg",
    "reorder", "reorder_same_id", "b_lock", "ordered_delay",
    "periodic_backpressure", "random_backpressure", "reset_policies",
    "integration_stress", "invalid_stall",
]
CASES += AUDIT_CASES
EXPECTED_FATAL = {
    "invalid_cfg": "SLAVE_CONFIG",
    "invalid_stall": "SLAVE_CONFIG",
    "neg_wlast": "SLAVE_WLAST",
    "neg_strb": "SLAVE_WSTRB",
    "neg_boundary": "SLAVE_BOUNDARY",
}


def execute(command, log, env, timeout):
    started = time.monotonic()
    with log.open("w") as stream:
        stream.write("COMMAND " + json.dumps(command) + "\n")
        stream.flush()
        process = subprocess.Popen(
            command, cwd=log.parent, env=env, stdout=stream,
            stderr=subprocess.STDOUT, start_new_session=True,
        )
        try:
            code = process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
            code = 124
    return code, round(time.monotonic() - started, 2)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["build", "test", "regress"])
    parser.add_argument("--case", choices=CASES, default="smoke")
    parser.add_argument("--data-width", type=int, choices=[32, 64], default=32)
    parser.add_argument("--id-width", type=int, choices=[2, 4], default=4)
    parser.add_argument("--capacity", type=int, choices=[1, 2, 4], default=4)
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()

    local = Path(os.environ.get("AXI_LOCAL_UVM", ROOT.parent / "local-uvm")).resolve()
    alias = Path("/tmp") / ("axi-slave-" + hashlib.sha256(str(ROOT).encode()).hexdigest()[:12])
    alias.mkdir(exist_ok=True)
    for name, target in [("project", ROOT), ("local", local)]:
        link = alias / name
        if link.is_symlink():
            if link.resolve() != target.resolve():
                raise RuntimeError("Existing alias points to a different directory")
        elif link.exists():
            raise RuntimeError("Alias is occupied")
        else:
            link.symlink_to(target, target_is_directory=True)

    project = alias / "project"
    tool = alias / "local/tools/verilator-5.052"
    uvm = alias / "local/third_party/1800.2-2020.3.2"
    tag = f"slave_d{args.data_width}_i{args.id_width}"
    build = project / "build" / tag
    logs = ROOT / "logs" / tag
    logs.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, LC_ALL="C", LANG="C", VERILATOR_ROOT=str(tool / "share/verilator"))
    sources = [
        "dv/interfaces/axi_write_if.sv", "dv/master/axi_master_pkg.sv", "dv/slave/axi_slave_pkg.sv",
        "dv/checkers/axi_write_checker.sv", "dv/tests/slave/slave_test_pkg.sv",
        "dv/tests/slave/top.sv",
    ]
    files = sorted(set(
        [ROOT / source for source in sources]
        + list((ROOT / "dv/slave").glob("*.svh"))
        + list((ROOT / "dv/master").glob("*.svh"))
        + list((ROOT / "dv/tests/slave").glob("*.svh"))
        + [ROOT / "dv/interfaces/axi_widths.svh", Path(__file__).resolve()]
    ))
    digest = hashlib.sha256(b"".join(
        str(path.relative_to(ROOT)).encode() + b"\0" + path.read_bytes() for path in files
    )).hexdigest()

    if args.action == "build":
        build.mkdir(parents=True, exist_ok=True)
        command = [
            str(tool / "bin/verilator"), "--binary", "--timing", "--assert", "--vpi",
            "--language", "1800-2017", "-Wno-fatal", "--top-module", "top", "-j", "4",
            "--Mdir", str(build), f"+define+AXI_DATA_W={args.data_width}",
            f"+define+AXI_ID_W={args.id_width}",
            *[f"+incdir+{path}" for path in [uvm / "src", project / "dv/interfaces", project / "dv/slave", project / "dv/master", project / "dv/tests/slave"]],
            "-CFLAGS", "-DUVM_NO_MALLOC -I" + str(uvm / "src/dpi"),
            str(uvm / "src/uvm_pkg.sv"), *[str(project / source) for source in sources],
            str(uvm / "src/dpi/uvm_dpi.cc"),
        ]
        code, elapsed = execute(command, logs / "build.log", env, 900)
        print(json.dumps({"build_exit": code, "seconds": elapsed, "log": str(logs / "build.log")}), flush=True)
        if code:
            print((logs / "build.log").read_text()[-7000:])
            return 1
        (build / "source.sha256").write_text(digest)
        return 0

    if not (build / "Vtop").exists() or (build / "source.sha256").read_text() != digest:
        raise RuntimeError("Build missing or stale; run build with these width options first")
    results = []
    for case in CASES if args.action == "regress" else [args.case]:
        log = logs / f"{case}_s{args.seed}_c{args.capacity}.log"
        test_name = "slave_acceptance_test" if case in AUDIT_CASES else "slave_stage1_test"
        command = [str(build / "Vtop"), f"+CASE={case}", f"+TEST={test_name}",
                   f"+CAPACITY={args.capacity}", f"+SLAVE_SEED={args.seed}", f"+verilator+seed+{args.seed}"]
        code, elapsed = execute(command, log, env, 60)
        output = log.read_text()
        counts = {key: int(value) for key, value in re.findall(r"UVM_(ERROR|FATAL)\s*:\s*(\d+)", output)}
        fatal_ids = re.findall(r"^UVM_FATAL\s+[^\n]*?\[([^\]]+)\]", output, re.MULTILINE)
        error_ids = re.findall(r"^UVM_ERROR\s+[^\n]*?\[([^\]]+)\]", output, re.MULTILINE)
        finished = not error_ids and "$finish" in output and "WATCHDOG" not in output
        if case in EXPECTED_FATAL:
            passed = (code == 0 and finished and counts == {"ERROR": 0, "FATAL": 1}
                      and fatal_ids == [EXPECTED_FATAL[case]] and "[CHECK_PASS]" not in output)
        else:
            passed = (code == 0 and finished and counts == {"ERROR": 0, "FATAL": 0}
                      and not fatal_ids and f"[CHECK_PASS] case={case} " in output)
        row = dict(case=case, passed=passed, exit=code, seconds=elapsed, counts=counts, error_ids=error_ids,
                   expected_fatal=EXPECTED_FATAL.get(case), fatal_ids=fatal_ids, log=str(log))
        results.append(row)
        print(json.dumps(row), flush=True)
        if not passed:
            print(output[-5000:], flush=True)
    report = dict(stage="slave_response_and_backpressure", source_sha256=digest,
                  data_width=args.data_width, id_width=args.id_width, seed=args.seed, capacity=args.capacity,
                  uvm="2020.3.2", results=results)
    report["verilator"] = subprocess.check_output([str(tool / "bin/verilator"), "--version"], env=env, text=True).strip()
    name = "results.json" if args.action == "regress" else args.case + f"_s{args.seed}_c{args.capacity}_result.json"
    (logs / name).write_text(json.dumps(report, indent=2) + "\n")
    return 0 if all(row["passed"] for row in results) else 1


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(error, file=sys.stderr)
        sys.exit(1)
