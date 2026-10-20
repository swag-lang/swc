r"""Compare binary parse reuse with source parsing on real generated APIs.

Prepare the devmode standard-library artifacts (gui and its dependencies), then:
    py -3 bench/parsecache.py --scratch C:\path\outside-checkout --reps 9

Uses the checkout-local Release compiler, six workers, fresh output directories,
private caches, load admission before every invocation, and alternating A/B order.
Dependency production is outside the timer. Does not update benchmark history.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import statistics
import subprocess
import time

import winproc


ROOT = Path(__file__).resolve().parents[1]
MODULES = {
    "runtime": [],
    "core": ["win32", "xinput", "core"],
    "pixel": ["win32", "xinput", "core", "gdi32", "ogl", "truetype", "pixel"],
    "gui": ["win32", "xinput", "core", "gdi32", "ogl", "truetype", "pixel", "gui"],
}
SOURCES = {
    "runtime": '#main { Swag.print(42) }\n',
    "core": """using Core
#main
{
    var values: Array's32
    values.add(20)
    values.add(22)
    Swag.print(values[0] + values[1])
}
""",
    "pixel": """#main
{
    let color = Pixel.Color.fromRgb(20, 22, 0)
    Swag.print(cast(s32, color.r) + cast(s32, color.g))
}
""",
    "gui": """#main
{
    var options: Gui.ApplicationOptions
    options.showClipRect = true
    Swag.print(41 + cast(s32, options.showClipRect))
}
""",
}


def admit():
    script = ROOT / ".agents/skills/modify-swag-codebase/scripts/check-machine-load.ps1"
    while True:
        result = subprocess.run(
            ["powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script)],
            capture_output=True, text=True)
        if result.returncode == 0:
            return
        if "wait" not in result.stdout:
            raise RuntimeError(result.stdout + result.stderr)
        print("Waiting for machine headroom", flush=True)
        time.sleep(15)


def api_files(module):
    output = ROOT / "bin/std/.output" / module
    files = sorted(path for path in output.rglob("*.swg")
                   if path.parent.name == "x86_64" and path.parent.parent.name == "devmode")
    if not files:
        raise RuntimeError(f"Build the devmode {module} dependency before measuring")
    return files


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--scratch", required=True, type=Path)
    parser.add_argument("--reps", type=int, default=9)
    parser.add_argument("--only", nargs="+", choices=MODULES, default=list(MODULES))
    parser.add_argument("--kind", choices=["syntax", "sema", "build"], default="build")
    args = parser.parse_args()
    scratch = args.scratch.resolve()
    if scratch.is_relative_to(ROOT) or args.reps < 1:
        parser.error("Use a scratch directory outside the checkout and at least one pair")
    scratch.mkdir(parents=True, exist_ok=True)
    run_root = scratch / time.strftime("parsecache-%Y%m%d-%H%M%S")
    run_root.mkdir()
    temp = run_root / "temp"
    temp.mkdir()
    env = dict(os.environ, TEMP=str(temp), TMP=str(temp))
    # Standalone consumers load the standard modules' shared libraries at startup.
    # Keep these dependencies outside each fresh consumer output directory.
    libraries = sorted((ROOT / "bin/std/.output").glob("*/shared-library/devmode/x86_64"))
    for key in list(env):
        if key.upper() == "PATH" and key != "PATH":
            env["PATH"] = env.pop(key)
    env["PATH"] = os.pathsep.join(map(str, libraries)) + os.pathsep + env.get("PATH", "")
    compiler = ROOT / "bin/swc.exe"
    cache = temp / "swag/parse"
    runtime_files = list((ROOT / "bin/runtime").glob("*.swg"))
    data = {
        "compiler": str(compiler),
        "compiler_sha256": hashlib.sha256(compiler.read_bytes()).hexdigest(),
        "kind": args.kind,
        "workers": 6,
        "runtime_files": len(runtime_files),
        "runtime_bytes": sum(path.stat().st_size for path in runtime_files),
        "cases": {},
    }

    def snapshot():
        return {str(path): path.stat().st_mtime_ns for path in cache.glob("*.bin")}

    def measure(name, label, bypass=False):
        source = run_root / (name + ".swg")
        output = run_root / label
        command = [str(compiler), args.kind, "-f", str(source), "--num-cores", "6"]
        if args.kind == "syntax":
            for module in MODULES[name]:
                for path in api_files(module):
                    command += ["--import-api-file", str(path)]
        else:
            command += ["-bc", "devmode"]
            for module in MODULES[name]:
                command += ["--import-api-module", module]
        if args.kind == "build":
            command += ["-n", "consumer", "-od", str(output), "-wd", str(output)]
        if bypass:
            command.append("--no-parse-cache")
        else:
            command.append("--parse-cache")
        admit()
        result = winproc.run(command, cwd=str(run_root), env=env, pin=True)
        (run_root / (label + ".log")).write_text(
            result["stdout"] + result["stderr"], encoding="utf-8")
        if result["exit"] != 0:
            raise RuntimeError(f"{label}: compilation failed; see {run_root / (label + '.log')}")
        # Execute each pilot artifact separately, outside the timed compilation.
        if args.kind == "build" and label.endswith(("-populate", "-reuse")):
            admit()
            native = winproc.run([str(output / "consumer.exe")], cwd=str(run_root), env=env, pin=True)
            if native["exit"] != 0 or native["stdout"].strip() != "42":
                raise RuntimeError(f"{label}: expected native output 42: {native}")
        print(label, round(result["wall_ms"], 2), "ms,", round(result["cpu_ms"], 2), "CPU ms", flush=True)
        return {key: value for key, value in result.items() if key not in ["stdout", "stderr"]}

    for name in args.only:
        (run_root / (name + ".swg")).write_text(SOURCES[name], encoding="utf-8")
        files = [path for module in MODULES[name] for path in api_files(module)]
        item = data["cases"][name] = {
            "api_files": len(files), "api_bytes": sum(path.stat().st_size for path in files),
            "off": [], "warm": [],
        }
        item["populate"] = measure(name, name + "-populate")
        before = snapshot()
        if not before:
            raise RuntimeError("No binary archives were produced; use the Release compiler")
        item["reuse"] = measure(name, name + "-reuse")
        if snapshot() != before:
            raise RuntimeError("A warm read rewrote or added archives")
        for index in range(args.reps):
            for mode in (["off", "warm"] if index % 2 == 0 else ["warm", "off"]):
                item[mode].append(measure(name, f"{name}-{index}-{mode}", bypass=mode == "off"))
        for metric in ["wall_ms", "cpu_ms"]:
            ratios = [warm[metric] / off[metric] for off, warm in zip(item["off"], item["warm"])
                      if off[metric] > 0]
            ratio = statistics.median(ratios) if len(ratios) == len(item["off"]) else None
            item["paired_" + metric + "_ratio"] = ratio
        print(name, "paired wall ratio", item["paired_wall_ms_ratio"],
              "paired CPU ratio", item["paired_cpu_ms_ratio"], flush=True)
        (run_root / "measurements.json").write_text(json.dumps(data, indent=2), encoding="utf-8")
    print("Results:", run_root / "measurements.json", flush=True)


if __name__ == "__main__":
    main()
