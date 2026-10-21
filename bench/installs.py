"""Self-contained Swag installations: the compiler under test and the frozen reference.

A campaign never measures `bin/swc.exe` in place. Other sessions rebuild that binary, edit
`bin/runtime` and `bin/std`, and share its machine-code cache, and any of those during a
sweep changes what is measured without changing what is recorded. So the campaign first
copies the compiler, its runtime, its standard library sources and the Swag task sources
into one folder, an installation, and measures that copy. The compiler finds its runtime
and standard library beside itself, so the copy is complete.

The reference is an installation frozen once and kept outside the checkout. Every campaign
measures it next to the compiler under test, sample for sample, and Swag's progress is the
ratio between the two inside the same minutes. That is what makes two campaigns days apart
comparable without correcting one by the other: the machine moves both members of a pair.

Each installation owns its temporary folder, which is where swc keeps its machine-code
cache. A build is timed from a cache restored to the same warm snapshot before every
sample: the state of a developer who built the project once before, identical for every
sample, and untouched by anything else on the machine.
"""
import datetime
import hashlib
import io
import json
import os
import shutil
import subprocess
import tarfile

import toolchains as tc

REFERENCE_MANIFEST = os.path.join(tc.BENCH, "reference.json")
INSTALLS = os.path.join(tc.OUT, "installs")
# Task sources each installation carries, so a reference keeps compiling the programs it
# was frozen with even after the current sources move to a newer syntax.
SOURCE_FOLDERS = ("swag", "swagnat", "hello")


def reference_store():
    """Where frozen references live: outside the checkout, so a clean cannot delete them."""
    root = os.environ.get("BENCH_REFERENCE_ROOT")
    if root:
        return root
    local = os.environ.get("LOCALAPPDATA") or os.path.join(os.path.expanduser("~"), "AppData", "Local")
    return os.path.join(local, "SwagBench", "references")


def sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            digest.update(block)
    return digest.hexdigest()


def tree_hash(root):
    """One digest over the frozen files under `root`, in a stable order.

    What a campaign produces inside an installation is left out: the published
    dependencies, the build outputs kept in dot folders, and the manifest itself.
    """
    digest = hashlib.sha256()
    for folder, dirs, files in os.walk(root):
        top = os.path.normcase(folder) == os.path.normcase(root)
        dirs[:] = sorted(d for d in dirs if not d.startswith(".") and not (top and d == "deps"))
        for name in sorted(files):
            if top and name == "reference.json":
                continue
            path = os.path.join(folder, name)
            digest.update(os.path.relpath(path, root).replace(os.sep, "/").encode("utf-8") + b"\0")
            digest.update(sha256(path).encode("ascii"))
    return digest.hexdigest()


def _copy_sources(src, dst):
    """Copy a source tree, leaving out the build outputs and caches kept in dot folders."""
    def ignore(folder, names):
        return [n for n in names if n.startswith(".") and os.path.isdir(os.path.join(folder, n))]
    shutil.copytree(src, dst, ignore=ignore, dirs_exist_ok=True)


class Install:
    """One Swag installation: compiler, runtime, standard library and task sources."""

    def __init__(self, role, root, meta, src=None, swc=None):
        self.role = role
        self.root = root
        self.meta = meta
        self.swc = swc or os.path.join(root, "swc.exe")
        self.std = os.path.join(root, "std")
        self.src = src or os.path.join(root, "src")
        self.work = os.path.join(INSTALLS, "work", role)

    def temp(self, *parts):
        path = os.path.join(self.work, "temp", *parts)
        os.makedirs(path, exist_ok=True)
        return path

    def env(self, base, temp):
        """`base` with this installation's library path and a private temporary folder."""
        return base | {"TEMP": temp, "TMP": temp, "SWAG_PATH": self.root}

    def api_file(self, cfg):
        return os.path.join(self.root, "deps", cfg, "kernel32.swg")

    def has_api(self, cfg):
        return os.path.isfile(self.api_file(cfg))

    def publish_dependencies(self, env, cores=0):
        """Publish the Win32 module this installation's programs import, outside every clock.

        Only the published `kernel32.swg` interface reaches the timed commands, through
        `--import-api-file`: the benchmark uses only the performance counter, as the Zig
        port declares only those entry points. Returns an error text or None.
        """
        for cfg in ("release", "devmode"):
            cmd = [self.swc, "build", *tc.swc_worker_args(cores), "--workspace", self.std,
                   "--workspace-module", "win32", "--build-cfg", cfg]
            temp = self.temp("deps")
            done = subprocess.run(cmd, cwd=self.root, env=self.env(env, temp), capture_output=True,
                                  text=True, encoding="utf-8", errors="replace")
            if done.returncode != 0:
                return "win32/%s: exit %d\n%s" % (cfg, done.returncode, (done.stdout + done.stderr)[-2000:])
            published = os.path.join(self.std, ".output", "win32", "export", cfg, "x86_64", "kernel32.swg")
            if not os.path.isfile(published):
                return "win32/%s published no kernel32.swg under %s" % (cfg, os.path.dirname(published))
            os.makedirs(os.path.dirname(self.api_file(cfg)), exist_ok=True)
            shutil.copyfile(published, self.api_file(cfg))
        return None

    def task_files(self, task, flavour):
        files = [os.path.join(self.src, flavour, "common.swg")]
        if task in tc.NEEDS_MAP:
            files.append(os.path.join(self.src, flavour, "bytemap.swg"))
        files.append(os.path.join(self.src, flavour, task + ".swg"))
        return files

    def has_task(self, task):
        return all(os.path.isfile(f) for f in self.task_files(task, "swagnat") + self.task_files(task, "swag"))


def beside(swc, role):
    """An installation that is simply a compiler with its runtime and library beside it."""
    swc = os.path.abspath(swc)
    return Install(role, os.path.dirname(swc), {"swc_sha256": sha256(swc), "source": swc},
                   src=tc.SRC, swc=swc)


def _populate(root, swc, checkout, bench_src):
    os.makedirs(root, exist_ok=True)
    shutil.copy2(swc, os.path.join(root, "swc.exe"))
    _copy_sources(os.path.join(checkout, "bin", "runtime"), os.path.join(root, "runtime"))
    _copy_sources(os.path.join(checkout, "bin", "std"), os.path.join(root, "std"))
    for folder in SOURCE_FOLDERS:
        _copy_sources(os.path.join(bench_src, folder), os.path.join(root, "src", folder))


def snapshot_subject(swc):
    """Copy the compiler under test and everything it reads into a private installation."""
    root = os.path.join(INSTALLS, "subject")
    shutil.rmtree(root, ignore_errors=True)
    _populate(root, swc, tc.worktree(), tc.SRC)
    return Install("subject", root, {"swc_sha256": sha256(os.path.join(root, "swc.exe")),
                                     "source": swc})


def _git(args):
    done = subprocess.run(["git"] + args, cwd=tc.worktree(), capture_output=True, text=True)
    return done.stdout.strip() if done.returncode == 0 else ""


def _export_commit(commit, target):
    """The runtime, standard library and task sources exactly as `commit` has them."""
    paths = ["bin/runtime", "bin/std"] + ["bench/src/" + f for f in SOURCE_FOLDERS]
    archive = subprocess.run(["git", "archive", "--format=tar", commit, *paths], cwd=tc.worktree(),
                             capture_output=True)
    if archive.returncode != 0:
        raise SystemExit("git archive failed: " + archive.stderr.decode("utf-8", "replace"))
    with tarfile.open(fileobj=io.BytesIO(archive.stdout)) as tar:
        tar.extractall(target)


def freeze_reference(name, swc=None, force=False):
    """Freeze the checkout's compiler as the reference `name`, and record it in the manifest.

    The runtime, the standard library and the task sources come from the HEAD commit, not
    from the working tree, so other sessions' uncommitted edits cannot leak into a reference
    and the reference can be rebuilt from its commit. The compiler is the binary built from
    that commit; the compiler sources must therefore be unmodified.
    """
    swc = swc or os.path.join(tc.worktree(), "bin", "swc.exe")
    dirty = bool(_git(["status", "--porcelain", "--untracked-files=no", "--", "src"]))
    if dirty and not force:
        raise SystemExit("the compiler sources are modified, so the binary does not match its commit "
                         "(pass --force to freeze anyway)")
    root = os.path.join(reference_store(), name)
    if os.path.exists(root):
        raise SystemExit("reference %s already exists at %s; references are never overwritten" % (name, root))
    commit = _git(["rev-parse", "HEAD"])
    export = os.path.join(INSTALLS, "export")
    shutil.rmtree(export, ignore_errors=True)
    _export_commit(commit, export)
    _populate(root, swc, export, os.path.join(export, "bench", "src"))
    shutil.rmtree(export, ignore_errors=True)
    manifest = {
        "name": name,
        "commit": _git(["rev-parse", "--short=10", "HEAD"]),
        "subject": _git(["log", "-1", "--format=%s"]),
        "dirty": dirty,
        "frozen": datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds"),
        "swc_sha256": sha256(os.path.join(root, "swc.exe")),
        "tree_sha256": tree_hash(root),
    }
    with open(os.path.join(root, "reference.json"), "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2)
    with open(REFERENCE_MANIFEST, "w", encoding="utf-8", newline="\r\n") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    return manifest


def load_reference(verify=True):
    """The reference the manifest names, verified byte for byte, or (None, reason)."""
    if not os.path.isfile(REFERENCE_MANIFEST):
        return None, "no reference has been frozen (bench/reference.json is missing)"
    with open(REFERENCE_MANIFEST, encoding="utf-8") as f:
        manifest = json.load(f)
    root = os.path.join(reference_store(), manifest["name"])
    swc = os.path.join(root, "swc.exe")
    if not os.path.isfile(swc):
        return None, ("reference %s is not on this machine (expected under %s); rebuild it from commit "
                      "%s and freeze it under the same name" % (manifest["name"], root, manifest["commit"]))
    if verify:
        if sha256(swc) != manifest["swc_sha256"]:
            return None, "reference %s compiler does not match its manifest" % manifest["name"]
        if tree_hash(root) != manifest["tree_sha256"]:
            return None, "reference %s files do not match its manifest" % manifest["name"]
    return Install("reference", root, manifest), None
