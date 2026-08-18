"""Locate every toolchain and describe how each one builds or runs a benchmark.

Nothing here is hard-coded to one machine: every root is discovered, and every
discovery can be overridden with an environment variable so a second machine only
needs to export what it keeps somewhere unusual. A missing toolchain is reported by
name and skipped, never guessed at.
"""
import glob
import json
import os
import subprocess

BENCH = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(BENCH, "src")
OUT = os.path.join(BENCH, "out")

TASKS = ["wordfreq", "csvagg", "sha256", "dijkstra", "raytrace", "leven", "chacha"]
NEEDS_MAP = {"wordfreq", "csvagg"}

def _first(pattern):
    hits = sorted(glob.glob(pattern))
    return hits[-1] if hits else None


def _env(name, fallback):
    v = os.environ.get(name)
    return v if v and os.path.exists(v) else fallback


def worktree():
    """The repository root: bench/ sits directly under it, and so does the compiler a
    campaign builds and then measures."""
    return os.path.dirname(BENCH)


def discover():
    home = os.path.expanduser("~")
    vs = _env("BENCH_VS_ROOT", _first(r"C:\Program Files\Microsoft Visual Studio\*\*"))
    swift_root = _env("BENCH_SWIFT_ROOT", os.path.join(home, r"AppData\Local\Programs\Swift"))
    swift_tc = _first(os.path.join(swift_root, "Toolchains", "*", "usr", "bin", "swiftc.exe"))
    swift_rt = _first(os.path.join(swift_root, "Runtimes", "*", "usr", "bin"))
    swift_sdk = _first(os.path.join(swift_root, "Platforms", "*", "Windows.platform",
                                    "Developer", "SDKs", "Windows.sdk"))

    t = {
        "vs": vs,
        "vcvars": os.path.join(vs, "VC", "Auxiliary", "Build", "vcvars64.bat") if vs else None,
        "clang_cl": os.path.join(vs, "VC", "Tools", "Llvm", "x64", "bin", "clang-cl.exe") if vs else None,
        "vswhere": r"C:\Program Files (x86)\Microsoft Visual Studio\Installer",
        "rustc": _env("BENCH_RUSTC", os.path.join(home, r".cargo\bin\rustc.exe")),
        "dotnet": _env("BENCH_DOTNET", r"C:\Program Files\dotnet\dotnet.exe"),
        "swiftc": _env("BENCH_SWIFTC", swift_tc),
        "swift_rt": swift_rt,
        "swift_sdk": swift_sdk,
        "node": _env("BENCH_NODE", r"C:\Program Files\nodejs\node.exe"),
        "lua": _env("BENCH_LUA", os.path.join(home, r"AppData\Local\Programs\Lua\bin\lua.exe")),
        "luajit": _env("BENCH_LUAJIT", os.path.join(home, r"AppData\Local\Programs\LuaJIT\bin\luajit.exe")),
        "py": _env("BENCH_PY", os.path.join(home, r"AppData\Local\Programs\Python\Launcher\py.exe")),
    }
    return t


def swc_path(explicit=None):
    """The compiler under test. A campaign rebuilds it first, so the default is this
    checkout's own binary."""
    if explicit:
        return explicit
    env = os.environ.get("BENCH_SWC")
    if env:
        return env
    return os.path.join(worktree(), "bin", "swc.exe")


def build_env(t):
    """A x64 developer environment, plus the roots the other toolchains need."""
    raw = subprocess.run('"%s" >nul 2>&1 && set' % t["vcvars"], shell=True,
                         capture_output=True, text=True, encoding="utf-8", errors="replace")
    env = {}
    for line in raw.stdout.splitlines():
        if "=" in line and not line.startswith("="):
            k, v = line.split("=", 1)
            env[k] = v
    if "INCLUDE" not in env:
        raise RuntimeError("vcvars64 produced no developer environment:\n" + raw.stdout[-400:])

    for k in [k for k in list(env) if k.upper() == "PATH" and k != "PATH"]:
        env["PATH"] = env.pop(k)

    extra = [t["vswhere"]]
    if t["swift_rt"]:
        extra.append(t["swift_rt"])
    env["PATH"] = ";".join(extra) + ";" + env.get("PATH", "")
    if t["swift_sdk"]:
        env["SDKROOT"] = t["swift_sdk"]
    env["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1"
    env["DOTNET_NOLOGO"] = "1"
    # vcvars exports Platform=x64; MSBuild picks it up as a global property and then
    # fails to find a matching configuration in the C# projects.
    env.pop("Platform", None)
    return env


def resolve(env, exe):
    """CreateProcessW searches the parent PATH, so every tool needs an absolute path."""
    if os.path.isabs(exe):
        return exe
    for d in env["PATH"].split(";"):
        cand = os.path.join(d, exe if exe.lower().endswith(".exe") else exe + ".exe")
        if os.path.exists(cand):
            return cand
    raise RuntimeError("cannot resolve %s" % exe)


# --------------------------------------------------------------------- recipes
def swag_files(task, flavour):
    files = [os.path.join(SRC, flavour, "common.swg")]
    if task in NEEDS_MAP:
        files.append(os.path.join(SRC, flavour, "bytemap.swg"))
    files.append(os.path.join(SRC, flavour, task + ".swg"))
    return files


def make_recipes(t, env, swc):
    """(id -> callable(task, name) -> recipe) for everything that builds an executable."""
    cl = resolve(env, "cl")

    def swag(cfg):
        def make(task, name):
            wd = os.path.join(OUT, "swag_" + name)
            cmd = [swc, "build", "--build-cfg", cfg, "-n", name, "-od", wd, "-wd", wd]
            for f in swag_files(task, "swagnat"):
                cmd += ["-f", f]
            return {"cmd": cmd, "exe": os.path.join(wd, name + ".exe"), "clean": [wd], "cwd": BENCH}
        return make

    def cpp(compiler):
        def make(task, name):
            objdir = os.path.join(OUT, "obj_" + name)
            exe = os.path.join(OUT, name + ".exe")
            return {"cmd": [compiler, "/nologo", "/O2", "/EHsc", "/std:c++20",
                            "/Fo:" + objdir + os.sep, os.path.join(SRC, "cpp", task + ".cpp"),
                            "/Fe:" + exe],
                    "exe": exe, "clean": [objdir, exe], "mkdir": [objdir], "cwd": BENCH}
        return make

    def rust(task, name):
        exe = os.path.join(OUT, name + ".exe")
        return {"cmd": [t["rustc"], "--edition", "2021", "-C", "opt-level=3",
                        "-C", "codegen-units=1", "-C", "panic=abort",
                        os.path.join(SRC, "rust", task + ".rs"), "-o", exe],
                "exe": exe, "clean": [exe], "cwd": BENCH}

    def swift(task, name):
        exe = os.path.join(OUT, name + ".exe")
        return {"cmd": [t["swiftc"], "-O", "-wmo",
                        os.path.join(SRC, "swift", task, "main.swift"), "-o", exe],
                "exe": exe, "clean": [exe], "cwd": BENCH}

    def csharp(kind):
        def make(task, name):
            proj = os.path.join(SRC, "cs", kind, task)
            if kind == "aot":
                cmd = [t["dotnet"], "publish", "-c", "Release", "--nologo", "-nodeReuse:false"]
                exe = os.path.join(proj, "bin", "Release", "net9.0", "win-x64", "publish",
                                   task + "_csaot.exe")
            else:
                cmd = [t["dotnet"], "build", "-c", "Release", "--nologo", "-nodeReuse:false"]
                exe = os.path.join(proj, "bin", "Release", "net9.0", task + "_csjit.dll")
            return {"cmd": cmd, "exe": exe, "cwd": proj,
                    "clean": [os.path.join(proj, "bin"), os.path.join(proj, "obj", "Release")]}
        return make

    return {
        "swag-release":    swag("release"),
        "swag-fast-debug": swag("fast-debug"),
        "cpp-clang-cl":    cpp(t["clang_cl"]),
        "cpp-msvc":        cpp(cl),
        "rust":            rust,
        "swift":           swift,
        "csharp-aot":      csharp("aot"),
        "csharp-jit":      csharp("jit"),
    }


def make_launchers(t, dotnet_dll_runner):
    """id -> callable(exe) -> command line, for the toolchains that produced an exe."""
    return {k: (lambda e: [e]) for k in
            ["swag-release", "swag-fast-debug", "cpp-clang-cl", "cpp-msvc",
             "rust", "swift", "csharp-aot"]} | {
        "csharp-jit": lambda e: [dotnet_dll_runner, e]}


def make_runtimes(t, swc):
    """id -> callable(task) -> command line, for everything that compiles at launch."""
    def jit(cfg):
        def make(task):
            cmd = [swc, "sema", "--build-cfg", cfg]
            for f in swag_files(task, "swag"):
                cmd += ["-f", f]
            return cmd
        return make

    return {
        "swc-jit-release":    jit("release"),
        "swc-jit-fast-debug": jit("fast-debug"),
        "node20":             lambda task: [t["node"], os.path.join(SRC, "js", task + ".js")],
        "luajit2.1":          lambda task: [t["luajit"], os.path.join(SRC, "lua", task + ".lua")],
        "lua5.4":             lambda task: [t["lua"], os.path.join(SRC, "lua", task + ".lua")],
        "python3.12":         lambda task: [t["py"], "-3", os.path.join(SRC, "py", task + ".py")],
    }


def make_hello_builds(t, env, swc):
    cl = resolve(env, "cl")
    hello = os.path.join(SRC, "hello")
    return {
        "swag-release": lambda: {
            "cmd": [swc, "build", "--build-cfg", "release", "-n", "hello_swag",
                    "-od", os.path.join(OUT, "hellowd"), "-wd", os.path.join(OUT, "hellowd"),
                    "-f", os.path.join(hello, "hello.swg")],
            "exe": os.path.join(OUT, "hellowd", "hello_swag.exe"),
            "clean": [os.path.join(OUT, "hellowd")], "cwd": BENCH},
        "cpp-msvc": lambda: {
            "cmd": [cl, "/nologo", "/O2", "/EHsc", "/std:c++20",
                    "/Fo:" + os.path.join(OUT, "hobj") + os.sep,
                    os.path.join(hello, "hello.cpp"), "/Fe:" + os.path.join(OUT, "hello_cpp.exe")],
            "exe": os.path.join(OUT, "hello_cpp.exe"),
            "clean": [os.path.join(OUT, "hobj"), os.path.join(OUT, "hello_cpp.exe")],
            "mkdir": [os.path.join(OUT, "hobj")], "cwd": BENCH},
        "rust": lambda: {
            "cmd": [t["rustc"], "--edition", "2021", "-C", "opt-level=3", "-C", "codegen-units=1",
                    "-C", "panic=abort", os.path.join(hello, "hello.rs"),
                    "-o", os.path.join(OUT, "hello_rust.exe")],
            "exe": os.path.join(OUT, "hello_rust.exe"),
            "clean": [os.path.join(OUT, "hello_rust.exe")], "cwd": BENCH},
        "swift": lambda: {
            "cmd": [t["swiftc"], "-O", "-wmo", os.path.join(hello, "swifthello", "main.swift"),
                    "-o", os.path.join(OUT, "hello_swift.exe")],
            "exe": os.path.join(OUT, "hello_swift.exe"),
            "clean": [os.path.join(OUT, "hello_swift.exe")], "cwd": BENCH},
        "csharp-aot": lambda: {
            "cmd": [t["dotnet"], "publish", "-c", "Release", "--nologo", "-nodeReuse:false"],
            "exe": os.path.join(hello, "csaot", "bin", "Release", "net9.0", "win-x64",
                                "publish", "hello_csaot.exe"),
            "clean": [os.path.join(hello, "csaot", "bin"),
                      os.path.join(hello, "csaot", "obj", "Release")],
            "cwd": os.path.join(hello, "csaot")},
        "csharp-jit": lambda: {
            "cmd": [t["dotnet"], "build", "-c", "Release", "--nologo", "-nodeReuse:false"],
            "exe": os.path.join(hello, "csjit", "bin", "Release", "net9.0", "hello_csjit.dll"),
            "clean": [os.path.join(hello, "csjit", "bin"),
                      os.path.join(hello, "csjit", "obj", "Release")],
            "cwd": os.path.join(hello, "csjit")},
    }


def make_hello_runs(t, swc):
    hello = os.path.join(SRC, "hello")
    return {
        "swc-jit-release":    [swc, "sema", "--build-cfg", "release", "-f",
                               os.path.join(hello, "run.swg")],
        "swc-jit-fast-debug": [swc, "sema", "--build-cfg", "fast-debug", "-f",
                               os.path.join(hello, "run.swg")],
        "node20":             [t["node"], os.path.join(hello, "hello.js")],
        "luajit2.1":          [t["luajit"], os.path.join(hello, "hello.lua")],
        "lua5.4":             [t["lua"], os.path.join(hello, "hello.lua")],
        "python3.12":         [t["py"], "-3", os.path.join(hello, "hello.py")],
    }


def missing(t):
    """Toolchains that could not be located, by benchmark id."""
    need = {
        "cpp-msvc": t["vcvars"], "cpp-clang-cl": t["clang_cl"], "rust": t["rustc"],
        "swift": t["swiftc"], "csharp-aot": t["dotnet"], "csharp-jit": t["dotnet"],
        "node20": t["node"], "luajit2.1": t["luajit"], "lua5.4": t["lua"], "python3.12": t["py"],
    }
    return sorted(k for k, v in need.items() if not v or not os.path.exists(v))
