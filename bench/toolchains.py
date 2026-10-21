"""Locate every toolchain and describe how each one builds or runs a benchmark.

Nothing here is hard-coded to one machine: every root is discovered, and every
discovery can be overridden with an environment variable so a second machine only
needs to export what it keeps somewhere unusual. A missing toolchain is reported by
name and skipped, never guessed at.

Every compilation follows one rule, whatever the language: **a warm toolchain and a
clean project**. Before its samples, each recipe is built once outside the clock. Every
timed sample then starts with the project's outputs removed and the toolchain's own
caches restored to the state that warm-up left: Swag's machine-code cache of its runtime,
Go's build cache of the standard library, Zig's global cache of compiler_rt. That is the
state of a developer who has built something before and now builds this project from
scratch, and it is the same for every sample, so samples can be compared at all.
"""
import glob
import os
import shutil
import subprocess

BENCH = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(BENCH, "src")
OUT = os.path.join(BENCH, "out")

TASKS = ["wordfreq", "csvagg", "sha256", "dijkstra", "raytrace", "leven", "chacha",
         "nbody", "fannkuch", "binarytrees", "lz77", "sort"]
NEEDS_MAP = {"wordfreq", "csvagg"}

# The Swag runtimes the campaign exists to measure, and the frozen reference that measures
# their progress: each one is sampled next to its reference counterpart in every round.
SWAG_AOT = ["swag-release", "swag-devmode"]
SWAG_JIT = ["swc-jit-release", "swc-jit-devmode"]
TRACKED = SWAG_AOT + SWAG_JIT
REFERENCE_OF = {"swag-release": "ref-release", "swag-devmode": "ref-devmode",
                "swc-jit-release": "ref-jit-release", "swc-jit-devmode": "ref-jit-devmode"}
REFERENCES = list(REFERENCE_OF.values())
CFG_OF = {"swag-release": "release", "swag-devmode": "devmode", "ref-release": "release",
          "ref-devmode": "devmode", "swc-jit-release": "release", "swc-jit-devmode": "devmode",
          "ref-jit-release": "release", "ref-jit-devmode": "devmode"}
ROLE_OF = {rt: ("reference" if rt.startswith("ref-") else "subject") for rt in CFG_OF}

AOT_CONTROLS = ["cpp-clang-cl", "cpp-msvc", "rust", "zig", "d-ldc", "odin", "go", "swift",
                "csharp-aot", "csharp-jit", "java-hotspot"]
JIT_CONTROLS = ["node20", "luajit2.1", "lua5.4", "python3.12", "php", "php-jit", "ruby"]
# Execution families: a JIT is compared with JITs and interpreters, native code with
# native code. C# CoreCLR and Java HotSpot are built ahead of time into bytecode and run
# on a JIT, so they build with the native recipes and run in the JIT family.
RUN_GROUPS = {
    "native": ("swag-release", "swag-devmode", "cpp-clang-cl", "cpp-msvc", "rust",
               "zig", "d-ldc", "odin", "go", "swift", "csharp-aot"),
    "jit": ("swc-jit-release", "swc-jit-devmode", "csharp-jit", "java-hotspot",
            "node20", "luajit2.1", "php-jit", "lua5.4", "python3.12", "php", "ruby"),
}


def _first(pattern):
    hits = sorted(glob.glob(pattern))
    return hits[-1] if hits else None


def _env(name, fallback):
    v = os.environ.get(name)
    return v if v and os.path.exists(v) else fallback


def worktree():
    """The repository root: bench/ sits directly under it."""
    return os.path.dirname(BENCH)


def discover():
    home = os.path.expanduser("~")
    programs = os.path.join(os.environ.get("LOCALAPPDATA") or os.path.join(home, "AppData", "Local"), "Programs")
    vs = _env("BENCH_VS_ROOT", _first(r"C:\Program Files\Microsoft Visual Studio\*\*"))
    swift_root = _env("BENCH_SWIFT_ROOT", os.path.join(home, r"AppData\Local\Programs\Swift"))
    swift_tc = _first(os.path.join(swift_root, "Toolchains", "*", "usr", "bin", "swiftc.exe"))
    swift_rt = _first(os.path.join(swift_root, "Runtimes", "*", "usr", "bin"))
    swift_sdk = _first(os.path.join(swift_root, "Platforms", "*", "Windows.platform",
                                    "Developer", "SDKs", "Windows.sdk"))
    java_home = os.environ.get("JAVA_HOME") or os.path.join(programs, "Java")
    javac = _env("BENCH_JAVAC", shutil.which("javac") or os.path.join(java_home, "bin", "javac.exe"))
    java = _env("BENCH_JAVA", os.path.join(os.path.dirname(javac), "java.exe"))
    php = _env("BENCH_PHP", shutil.which("php") or os.path.join(programs, "PHP", "php.exe"))

    return {
        "vs": vs,
        "vcvars": os.path.join(vs, "VC", "Auxiliary", "Build", "vcvars64.bat") if vs else None,
        "clang_cl": os.path.join(vs, "VC", "Tools", "Llvm", "x64", "bin", "clang-cl.exe") if vs else None,
        "vswhere": r"C:\Program Files (x86)\Microsoft Visual Studio\Installer",
        "rustc": _env("BENCH_RUSTC", os.path.join(home, r".cargo\bin\rustc.exe")),
        "zig": _env("BENCH_ZIG", shutil.which("zig") or os.path.join(programs, "Zig", "zig.exe")),
        "ldc2": _env("BENCH_LDC2", shutil.which("ldc2") or os.path.join(programs, "LDC", "bin", "ldc2.exe")),
        "odin": _env("BENCH_ODIN", shutil.which("odin") or os.path.join(programs, "Odin", "odin.exe")),
        "go": _env("BENCH_GO", shutil.which("go") or
                   _first(os.path.join(programs, "Go", "bin", "go.exe")) or
                   r"C:\Program Files\Go\bin\go.exe"),
        "javac": javac,
        "java": java,
        "php": php,
        "php_opcache": _env("BENCH_PHP_OPCACHE", os.path.join(os.path.dirname(php), "ext", "php_opcache.dll")),
        "ruby": _env("BENCH_RUBY", shutil.which("ruby") or os.path.join(programs, "Ruby", "bin", "ruby.exe")),
        "dotnet": _env("BENCH_DOTNET", r"C:\Program Files\dotnet\dotnet.exe"),
        "swiftc": _env("BENCH_SWIFTC", swift_tc),
        "swift_rt": swift_rt,
        "swift_sdk": swift_sdk,
        "node": _env("BENCH_NODE", r"C:\Program Files\nodejs\node.exe"),
        "lua": _env("BENCH_LUA", os.path.join(home, r"AppData\Local\Programs\Lua\bin\lua.exe")),
        "luajit": _env("BENCH_LUAJIT", os.path.join(home, r"AppData\Local\Programs\LuaJIT\bin\luajit.exe")),
        "py": _env("BENCH_PY", os.path.join(home, r"AppData\Local\Programs\Python\Launcher\py.exe")),
    }


def swc_path(explicit=None):
    """The compiler under test; by default, this checkout's own binary."""
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
    # Every toolchain's temporary files, and the caches some keep there (Swift's module
    # cache), belong to the campaign rather than to whatever else uses the user's TEMP.
    temp = os.path.join(OUT, "temp", "toolchains")
    os.makedirs(temp, exist_ok=True)
    env["TEMP"] = env["TMP"] = temp
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


def rm(path):
    if os.path.isdir(path):
        shutil.rmtree(path, ignore_errors=True)
    elif os.path.exists(path):
        try:
            os.unlink(path)
        except OSError:
            pass


class WarmState:
    """A cache folder restored to one snapshot before every timed sample.

    `capture` keeps what the warm-up left in the live folder; `restore` puts exactly that
    back. Both happen outside the clock. A state `owned` by one recipe starts empty before
    that recipe's warm-up; a shared one keeps what earlier warm-ups left. `capture_on_warm`
    is false for a cache whose content is fixed in advance (Go's standard library only).
    """

    def __init__(self, base, owned=True, capture_on_warm=True):
        self.live = os.path.join(base, "live")
        self.snapshot = os.path.join(base, "snapshot")
        self.owned = owned
        self.capture_on_warm = capture_on_warm

    def reset(self):
        rm(self.live)
        rm(self.snapshot)
        os.makedirs(self.live, exist_ok=True)

    def capture(self):
        rm(self.snapshot)
        shutil.copytree(self.live, self.snapshot)

    def restore(self):
        """Make the live folder equal to the snapshot, writing only what differs.

        Copying a whole cache before every sample made the antivirus scan hundreds of fresh
        files while the next sample ran, which the interference check rightly read as a
        visitor. A sample adds a few entries and rewrites fewer, so only those are undone.
        """
        if not os.path.isdir(self.snapshot):
            rm(self.live)
            os.makedirs(self.live, exist_ok=True)
            return
        wanted = {}
        for folder, _, files in os.walk(self.snapshot):
            rel = os.path.relpath(folder, self.snapshot)
            for name in files:
                wanted[os.path.normcase(os.path.join(rel, name))] = os.path.join(folder, name)
        for folder, dirs, files in os.walk(self.live, topdown=False):
            rel = os.path.relpath(folder, self.live)
            for name in files:
                if os.path.normcase(os.path.join(rel, name)) not in wanted:
                    rm(os.path.join(folder, name))
            if rel != "." and not os.listdir(folder):
                os.rmdir(folder)
        for rel, source in wanted.items():
            target = os.path.join(self.live, rel)
            try:
                same = os.stat(target)
                original = os.stat(source)
                if same.st_size == original.st_size and same.st_mtime_ns == original.st_mtime_ns:
                    continue
            except OSError:
                os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copy2(source, target)


def swc_worker_args(cores):
    return ["--num-cores", str(cores)] if cores else []


def swag_files(task, flavour):
    """The checkout's Swag sources of one task (`swagnat` builds, `swag` runs on the JIT)."""
    files = [os.path.join(SRC, flavour, "common.swg")]
    if task in NEEDS_MAP:
        files.append(os.path.join(SRC, flavour, "bytemap.swg"))
    return files + [os.path.join(SRC, flavour, task + ".swg")]


def swag_dependency_api_files(cfg):
    """The Win32 API the last campaign published for the compiler under test."""
    path = os.path.join(OUT, "installs", "subject", "deps", cfg, "kernel32.swg")
    if not os.path.isfile(path):
        raise RuntimeError("no published Win32 API under %s; run `py -3 bench/driver.py --quick "
                           "--tasks sort --no-reference` once to prepare it" % os.path.dirname(path))
    return [path]


# --------------------------------------------------------------------- recipes
#
# A build recipe is a dict:
#   cmd, cwd, exe       the timed command and the artifact it must produce
#   clean, mkdir        project outputs removed / created before every sample
#   env                 overrides on top of the campaign environment
#   state               a WarmState restored before every sample, or None
#   warm                callable(env) run once, outside the clock, before the samples
#   artifact_glob       for bytecode outputs made of several files
def _recipe(cmd, exe, cwd, clean, mkdir=(), env=None, state=None, warm=None, artifact_glob=None):
    return {"cmd": cmd, "exe": exe, "cwd": cwd, "clean": list(clean), "mkdir": list(mkdir),
            "env": env or {}, "state": state, "warm": warm, "artifact_glob": artifact_glob}


def swag_build(install, cfg, files, name, cores, out_name=None):
    """A Swag build from one installation, timed from its restored machine-code cache."""
    wd = os.path.join(OUT, out_name or ("swag_" + name))
    state = WarmState(os.path.join(install.work, "cache", name))
    cmd = [install.swc, "build", *swc_worker_args(cores), "--build-cfg", cfg,
           "-n", name, "-od", wd, "-wd", wd]
    if install.has_api(cfg):
        cmd += ["--import-api-file", install.api_file(cfg)]
    for f in files:
        cmd += ["-f", f]
    return _recipe(cmd, os.path.join(wd, name + ".exe"), BENCH, [wd],
                   env={"TEMP": state.live, "TMP": state.live, "SWAG_PATH": install.root},
                   state=state)


def go_std_cache(t, env, sources):
    """A Go build cache holding the standard-library packages `sources` import, and nothing
    else: restored before every sample, it leaves the program itself to compile and link."""
    base = os.path.join(OUT, "cache", "go")
    state = WarmState(base, owned=False, capture_on_warm=False)
    state.reset()
    go_env = env | {"GOCACHE": state.live, "GOTOOLCHAIN": "local", "GOFLAGS": ""}
    packages = set()
    for files in sources:
        done = subprocess.run([t["go"], "list", "-deps", "-f", "{{if .Standard}}{{.ImportPath}}{{end}}", *files],
                              env=go_env, capture_output=True, text=True, cwd=OUT)
        if done.returncode != 0:
            raise RuntimeError("go list failed: " + (done.stdout + done.stderr)[-600:])
        packages.update(p for p in done.stdout.split() if p)
    done = subprocess.run([t["go"], "build", *sorted(packages)], env=go_env, capture_output=True,
                          text=True, cwd=OUT)
    if done.returncode != 0:
        raise RuntimeError("go build of the standard packages failed: " + (done.stdout + done.stderr)[-600:])
    state.capture()
    return state


def systems_recipe(t, language, source, name, helpers=(), shared=None):
    """A clean project build for the toolchains driven by file arguments."""
    wd = os.path.join(OUT, name)
    exe = os.path.join(wd, name + ".exe")
    env, state, glob_ = {}, None, None
    if language == "zig":
        # The local cache is the project's and goes with it; the global cache holds
        # compiler_rt and the libc bindings, toolchain state like a Rust sysroot.
        state = shared["zig"]
        cmd = [t["zig"], "build-exe", source, "-O", "ReleaseFast",
               "-target", "x86_64-windows-msvc", "-lc",
               "-femit-bin=" + exe, "--cache-dir", os.path.join(wd, "cache"),
               "--global-cache-dir", state.live]
    elif language == "d-ldc":
        cmd = [t["ldc2"], "-O3", "-release", "-boundscheck=off",
               "-I=" + os.path.join(SRC, "d"), "-of=" + exe,
               "-od=" + wd, source, *helpers]
    elif language == "odin":
        cmd = [t["odin"], "build", source, "-file", "-o:speed", "-out:" + exe]
    elif language == "go":
        state = shared["go"]
        cmd = [t["go"], "build", "-o", exe, source, *helpers]
        env = {"GOCACHE": state.live, "GOTOOLCHAIN": "local", "GOFLAGS": ""}
    elif language == "java-hotspot":
        cmd = [t["javac"], "-encoding", "UTF-8", "-d", wd, source]
        exe = os.path.join(wd, "Bench.class")
        glob_ = os.path.join(wd, "*.class")
    else:
        raise ValueError("unknown native toolchain: " + language)
    return _recipe(cmd, exe, wd, [wd], mkdir=[wd], env=env, state=state, artifact_glob=glob_)


def zig_global_cache():
    """The Zig global cache, warmed by the first Zig build of the campaign."""
    state = WarmState(os.path.join(OUT, "cache", "zig-global"), owned=False, capture_on_warm=True)
    state.reset()
    return state


def make_recipes(t, env, installs, cores=0, shared=None):
    """(id -> callable(task, name) -> recipe) for everything that builds an executable."""
    cl = resolve(env, "cl")

    def swag(rt):
        install = installs.get(ROLE_OF[rt])
        cfg = CFG_OF[rt]

        def make(task, name):
            return swag_build(install, cfg, install.task_files(task, "swagnat"), name, cores)
        return make if install else None

    def cpp(compiler):
        def make(task, name):
            objdir = os.path.join(OUT, "obj_" + name)
            exe = os.path.join(OUT, name + ".exe")
            return _recipe([compiler, "/nologo", "/O2", "/EHsc", "/std:c++20",
                            "/Fo:" + objdir + os.sep, os.path.join(SRC, "cpp", task + ".cpp"),
                            "/Fe:" + exe], exe, BENCH, [objdir, exe], mkdir=[objdir])
        return make

    def rust(task, name):
        exe = os.path.join(OUT, name + ".exe")
        return _recipe([t["rustc"], "--edition", "2021", "-C", "opt-level=3",
                        "-C", "codegen-units=1", "-C", "panic=abort",
                        os.path.join(SRC, "rust", task + ".rs"), "-o", exe], exe, BENCH,
                       [exe, os.path.join(OUT, name + ".pdb")])

    def swift(task, name):
        exe = os.path.join(OUT, name + ".exe")
        return _recipe([t["swiftc"], "-O", "-wmo", os.path.join(SRC, "swift", task, "main.swift"), "-o", exe],
                       exe, BENCH, [exe])

    def csharp(kind):
        def make(task, name):
            proj = os.path.join(SRC, "cs", kind, task)
            if kind == "aot":
                cmd = [t["dotnet"], "publish", "-c", "Release", "--nologo", "-nodeReuse:false"]
                exe = os.path.join(proj, "bin", "Release", "net9.0", "win-x64", "publish", task + "_csaot.exe")
            else:
                cmd = [t["dotnet"], "build", "-c", "Release", "--nologo", "-nodeReuse:false"]
                exe = os.path.join(proj, "bin", "Release", "net9.0", task + "_csjit.dll")
            return _recipe(cmd, exe, proj, [os.path.join(proj, "bin"), os.path.join(proj, "obj", "Release")])
        return make

    recipes = {
        "cpp-clang-cl": cpp(t["clang_cl"]),
        "cpp-msvc": cpp(cl),
        "rust": rust,
        "zig": lambda task, name: systems_recipe(t, "zig", os.path.join(SRC, "zig", task + ".zig"), name,
                                                 shared=shared),
        "d-ldc": lambda task, name: systems_recipe(
            t, "d-ldc", os.path.join(SRC, "d", task + ".d"), name,
            [os.path.join(SRC, "d", "common.d")] + ([os.path.join(SRC, "d", "bytemap.d")] if task in NEEDS_MAP else [])),
        "odin": lambda task, name: systems_recipe(t, "odin", os.path.join(SRC, "odin", task + ".odin"), name),
        "go": lambda task, name: systems_recipe(t, "go", os.path.join(SRC, "go", task + ".go"), name,
                                                go_files(task)[1:], shared=shared),
        "java-hotspot": lambda task, name: systems_recipe(
            t, "java-hotspot", os.path.join(SRC, "java", task, "Bench.java"), name),
        "swift": swift,
        "csharp-aot": csharp("aot"),
        "csharp-jit": csharp("jit"),
    }
    for rt in SWAG_AOT + ["ref-release", "ref-devmode"]:
        make = swag(rt)
        if make:
            recipes[rt] = make
    return recipes


def go_files(task):
    """The Go sources of one task, the task file first."""
    return ([os.path.join(SRC, "go", task + ".go"), os.path.join(SRC, "go", "common.go")] +
            ([os.path.join(SRC, "go", "bytemap.go")] if task in NEEDS_MAP else []))


def make_launchers(t):
    """id -> callable(exe) -> command line, for the toolchains that produced an artifact."""
    native = ["cpp-clang-cl", "cpp-msvc", "rust", "zig", "d-ldc", "odin", "go", "swift", "csharp-aot",
              *SWAG_AOT, "ref-release", "ref-devmode"]
    return {k: (lambda e: [e]) for k in native} | {
        "csharp-jit": lambda e: [t["dotnet"], e],
        "java-hotspot": lambda e: [t["java"], "-cp", os.path.dirname(e), "Bench"]}


def php_command(t, source, jit=False):
    # Ignore the user's php.ini so profilers and local extensions cannot change a run.
    cmd = [t["php"], "-n", "-d", "memory_limit=-1",
           "-d", "auto_prepend_file=" + os.path.join(SRC, "php", "common.php")]
    if jit:
        cmd += ["-d", "zend_extension=" + t["php_opcache"],
                "-d", "opcache.enable_cli=1", "-d", "opcache.jit_buffer_size=64M",
                "-d", "opcache.jit=tracing"]
    return cmd + [source] + (["--require-jit"] if jit else [])


def swag_jit(install, cfg, files, cores):
    """A Swag JIT run: the kernel is compiled before the program starts its own timer."""
    cmd = [install.swc, "sema", *swc_worker_args(cores), "--build-cfg", cfg]
    if install.has_api(cfg):
        cmd += ["--import-api-file", install.api_file(cfg)]
    for f in files:
        cmd += ["-f", f]
    return cmd


def make_runtimes(t, installs, cores=0):
    """id -> callable(task) -> (command line, env overrides), for what compiles at launch."""
    def jit(rt):
        install = installs.get(ROLE_OF[rt])
        if not install:
            return None
        temp = install.temp("jit")
        overrides = {"TEMP": temp, "TMP": temp, "SWAG_PATH": install.root}
        return lambda task: (swag_jit(install, CFG_OF[rt], install.task_files(task, "swag"), cores), overrides)

    plain = {
        "node20": lambda task: [t["node"], os.path.join(SRC, "js", task + ".js")],
        "luajit2.1": lambda task: [t["luajit"], os.path.join(SRC, "lua", task + ".lua")],
        "lua5.4": lambda task: [t["lua"], os.path.join(SRC, "lua", task + ".lua")],
        "python3.12": lambda task: [t["py"], "-3", os.path.join(SRC, "py", task + ".py")],
        "php": lambda task: php_command(t, os.path.join(SRC, "php", task + ".php")),
        "php-jit": lambda task: php_command(t, os.path.join(SRC, "php", task + ".php"), True),
        "ruby": lambda task: [t["ruby"], "--disable-gems", os.path.join(SRC, "ruby", task + ".rb")],
    }
    runtimes = {k: (lambda task, f=f: (f(task), {})) for k, f in plain.items()}
    for rt in SWAG_JIT + ["ref-jit-release", "ref-jit-devmode"]:
        make = jit(rt)
        if make:
            runtimes[rt] = make
    return runtimes


def make_hello_builds(t, env, installs, cores=0, shared=None):
    cl = resolve(env, "cl")
    hello = os.path.join(SRC, "hello")

    def cpp(compiler, name):
        def make():
            wd = os.path.join(OUT, "hello_" + name)
            exe = os.path.join(wd, "hello_cpp.exe")
            return _recipe([compiler, "/nologo", "/O2", "/EHsc", "/std:c++20",
                            "/Fo:" + wd + os.sep, os.path.join(hello, "hello.cpp"), "/Fe:" + exe],
                           exe, BENCH, [wd], mkdir=[wd])
        return make

    def dotnet(kind, verb, exe):
        folder = os.path.join(hello, kind)
        return lambda: _recipe([t["dotnet"], verb, "-c", "Release", "--nologo", "-nodeReuse:false"],
                               os.path.join(folder, *exe), folder,
                               [os.path.join(folder, "bin"), os.path.join(folder, "obj", "Release")])

    builds = {
        "zig": lambda: systems_recipe(t, "zig", os.path.join(hello, "hello.zig"), "hello_zig", shared=shared),
        "d-ldc": lambda: systems_recipe(t, "d-ldc", os.path.join(hello, "hello.d"), "hello_d-ldc"),
        "odin": lambda: systems_recipe(t, "odin", os.path.join(hello, "hello.odin"), "hello_odin"),
        "go": lambda: systems_recipe(t, "go", os.path.join(hello, "hello.go"), "hello_go", shared=shared),
        "java-hotspot": lambda: systems_recipe(t, "java-hotspot", os.path.join(hello, "java", "Bench.java"),
                                               "hello_java-hotspot"),
        "cpp-clang-cl": cpp(t["clang_cl"], "clang"),
        "cpp-msvc": cpp(cl, "msvc"),
        "rust": lambda: _recipe([t["rustc"], "--edition", "2021", "-C", "opt-level=3", "-C", "codegen-units=1",
                                 "-C", "panic=abort", os.path.join(hello, "hello.rs"),
                                 "-o", os.path.join(OUT, "hello_rust.exe")],
                                os.path.join(OUT, "hello_rust.exe"), BENCH,
                                [os.path.join(OUT, "hello_rust.exe"), os.path.join(OUT, "hello_rust.pdb")]),
        "swift": lambda: _recipe([t["swiftc"], "-O", "-wmo", os.path.join(hello, "swifthello", "main.swift"),
                                  "-o", os.path.join(OUT, "hello_swift.exe")],
                                 os.path.join(OUT, "hello_swift.exe"), BENCH, [os.path.join(OUT, "hello_swift.exe")]),
        "csharp-aot": dotnet("csaot", "publish", ("bin", "Release", "net9.0", "win-x64", "publish", "hello_csaot.exe")),
        "csharp-jit": dotnet("csjit", "build", ("bin", "Release", "net9.0", "hello_csjit.dll")),
    }
    for rt in SWAG_AOT + ["ref-release", "ref-devmode"]:
        install = installs.get(ROLE_OF[rt])
        if install:
            builds[rt] = (lambda install=install, rt=rt: swag_build(
                install, CFG_OF[rt], [os.path.join(install.src, "hello", "hello.swg")],
                "hello_" + rt.replace("-", "_"), cores))
    return builds


def make_hello_runs(t, installs, cores=0):
    """id -> (command, env overrides, output marker, warm state or None)."""
    hello = os.path.join(SRC, "hello")
    runs = {
        "node20": ([t["node"], os.path.join(hello, "hello.js")], {}),
        "luajit2.1": ([t["luajit"], os.path.join(hello, "hello.lua")], {}),
        "lua5.4": ([t["lua"], os.path.join(hello, "hello.lua")], {}),
        "python3.12": ([t["py"], "-3", os.path.join(hello, "hello.py")], {}),
        "php": (php_command(t, os.path.join(hello, "hello.php")), {}),
        "php-jit": (php_command(t, os.path.join(hello, "hello.php"), True), {}),
        "ruby": ([t["ruby"], "--disable-gems", os.path.join(hello, "hello.rb")], {}),
    }
    out = {k: {"cmd": cmd, "env": env, "marker": "hi", "state": None} for k, (cmd, env) in runs.items()}
    for rt in SWAG_JIT + ["ref-jit-release", "ref-jit-devmode"]:
        install = installs.get(ROLE_OF[rt])
        if not install:
            continue
        # Time to first output includes compiling hello, so the machine-code cache is part
        # of what is timed and is restored like a build's.
        state = WarmState(os.path.join(install.work, "cache", "hello_run_" + CFG_OF[rt]))
        out[rt] = {"cmd": [install.swc, "sema", *swc_worker_args(cores), "--build-cfg", CFG_OF[rt],
                           "-f", os.path.join(install.src, "hello", "run.swg")],
                   "env": {"TEMP": state.live, "TMP": state.live, "SWAG_PATH": install.root},
                   "marker": "hello, world\n", "state": state}
    return out


# ------------------------------------------------------------ compiler workloads
# The twelve tasks and the hello world price a compiler on a small program. None of them
# contains what an edit-build loop costs: a real module, a warm no-op, one touched file,
# the documentation, a formatting pass. These do, on the standard library each
# installation carries, so the compiler under test and the reference each build their own
# library and nothing the campaign touches belongs to the checkout.
COMPILER_WORKLOADS = ["core_rebuild", "core_noop", "core_touch", "doc_std", "format_tree"]

# One leaf of core whose write time the touched-file workload bumps. Its content never
# changes: the compiler decides staleness from write times, exactly as after a save.
TOUCHED_FILE = os.path.join("modules", "core", "src", "text", "utf8.swg")

# The trees formatted by format_tree, inside each installation.
FORMAT_TREES = ["runtime", "std", "src"]


def _mirror_sources(src, dst):
    """Copy Swag sources and formatter configuration, preserving the tree's layout."""
    for folder, dirs, files in os.walk(src):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        rel = os.path.relpath(folder, src)
        for name in files:
            if name.endswith((".swg", ".swgs")) or name == ".swc-format":
                target = os.path.join(dst, rel, name)
                os.makedirs(os.path.dirname(target), exist_ok=True)
                shutil.copyfile(os.path.join(folder, name), target)


def make_compiler_workloads(install, cores=0, admit=None, tag=None):
    """(id -> workload) for the edit-build loop of one installation.

    A workload is a timed command plus an untimed `prepare` that puts the tree in the
    state the command is meant to find. Its `env` gives the installation a private
    temporary folder, so its machine-code cache is its own.
    """
    tag = tag or install.role
    compiler_args = swc_worker_args(cores)
    build_core = [install.swc, "build", "--workspace", install.std, "--workspace-module", "core",
                  "--build-cfg", "devmode"] + compiler_args
    touched = os.path.join(install.std, TOUCHED_FILE)
    doc_out = os.path.join(OUT, "doc_" + tag)
    format_out = os.path.join(OUT, "format_" + tag)
    temp = install.temp("loop")
    env = {"TEMP": temp, "TMP": temp, "SWAG_PATH": install.root}

    def warm(run_env):
        if admit:
            admit()
        result = subprocess.run(build_core, cwd=install.root, env=run_env, capture_output=True, text=True)
        if result.returncode:
            raise RuntimeError("warm core build failed (exit %d):\n%s" %
                               (result.returncode, (result.stdout + result.stderr)[-1200:]))

    def touch(run_env):
        warm(run_env)
        os.utime(touched, None)

    def clear_doc(run_env):
        rm(doc_out)
        os.makedirs(doc_out, exist_ok=True)

    def mirror(run_env):
        rm(format_out)
        os.makedirs(format_out, exist_ok=True)
        config = os.path.join(worktree(), ".swc-format")
        if os.path.isfile(config):
            shutil.copyfile(config, os.path.join(format_out, ".swc-format"))
        for tree in FORMAT_TREES:
            _mirror_sources(os.path.join(install.root, tree), os.path.join(format_out, tree))

    return {
        "core_rebuild": {"cmd": build_core + ["--rebuild"], "cwd": install.root, "env": env, "prepare": None,
                         "what": "std/core, every file, from nothing"},
        "core_noop": {"cmd": build_core, "cwd": install.root, "env": env, "prepare": warm,
                      "what": "std/core again, nothing changed"},
        "core_touch": {"cmd": build_core, "cwd": install.root, "env": env, "prepare": touch,
                       "what": "std/core after one file was saved"},
        "doc_std": {"cmd": [install.swc, "doc", "--workspace", install.std, "--doc-output-dir", doc_out,
                            "--rebuild"] + compiler_args,
                    "cwd": install.root, "env": env, "prepare": clear_doc,
                    "what": "the documentation of the whole standard library"},
        "format_tree": {"cmd": [install.swc, "format", "-d", format_out] + compiler_args,
                        "cwd": install.root, "env": env, "prepare": mirror,
                        "what": "the installation's runtime, library and task sources, formatted"},
    }


# ------------------------------------------------------------------- versions
def version_commands(t):
    """id -> command whose first output line names the toolchain's version."""
    return {
        "cpp-msvc": ["cl"], "cpp-clang-cl": [t["clang_cl"], "--version"],
        "rust": [t["rustc"], "--version"], "zig": [t["zig"], "version"],
        "d-ldc": [t["ldc2"], "--version"], "odin": [t["odin"], "version"],
        "go": [t["go"], "version"], "swift": [t["swiftc"], "--version"],
        "csharp-aot": [t["dotnet"], "--version"], "csharp-jit": [t["dotnet"], "--version"],
        "java-hotspot": [t["java"], "-version"], "node20": [t["node"], "--version"],
        "luajit2.1": [t["luajit"], "-v"], "lua5.4": [t["lua"], "-v"],
        "python3.12": [t["py"], "-3", "--version"], "php": [t["php"], "-n", "-v"],
        "php-jit": [t["php"], "-n", "-v"], "ruby": [t["ruby"], "-v"],
    }


def missing(t):
    """Toolchains that could not be located, by benchmark id."""
    need = {
        "cpp-msvc": t["vcvars"], "cpp-clang-cl": t["clang_cl"], "rust": t["rustc"],
        "zig": t["zig"], "d-ldc": t["ldc2"], "odin": t["odin"],
        "go": t["go"], "java-hotspot": t["javac"],
        "php": t["php"], "php-jit": t["php_opcache"], "ruby": t["ruby"],
        "swift": t["swiftc"], "csharp-aot": t["dotnet"], "csharp-jit": t["dotnet"],
        "node20": t["node"], "luajit2.1": t["luajit"], "lua5.4": t["lua"], "python3.12": t["py"],
    }
    gone = {k for k, v in need.items() if not v or not os.path.exists(v)}
    if not t["java"] or not os.path.isfile(t["java"]):
        gone.add("java-hotspot")
    if "php" in gone:
        gone.add("php-jit")
    return sorted(gone)
