"""Exercise campaign process lifetimes without compiling the compiler or measuring tasks."""
import contextlib
import io
import json
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import campaign


@unittest.skipUnless(sys.platform == "win32", "running executable locks are a Windows contract")
class CampaignProcessTests(unittest.TestCase):
    def test_build_and_measure_leave_the_live_launcher_untouched_and_clean_up(self):
        with tempfile.TemporaryDirectory(prefix="swc campaign process ") as directory:
            scratch = Path(directory)
            root = scratch / "checkout"
            binary = root / "bin" / "swc.exe"
            runtime = binary.parent / "runtime"
            runtime.mkdir(parents=True)
            (runtime / "api.swg").write_text("runtime from this checkout", encoding="utf-8")
            shutil.copy2(sys.executable, binary)
            original = binary.read_bytes()

            # Python stands in for both the running launcher image and the build program.
            # The latter really opens its requested output in a separate process: writing
            # the launcher's path fails with the same Windows image lock as a linker.
            vs = scratch / "Visual Studio"
            msbuild = vs / "MSBuild" / "Current" / "Bin" / "amd64" / "MSBuild.exe"
            msbuild.parent.mkdir(parents=True)
            shutil.copy2(sys.executable, msbuild)
            (root / "swc.sln").write_text(textwrap.dedent("""
                import json, os, shutil, sys
                from pathlib import Path
                root = Path(__file__).parent
                props = dict(arg[3:].split("=", 1) for arg in sys.argv[1:] if arg.startswith("-p:"))
                output = Path(props.get("OutDir", root / "bin"))
                intermediate = Path(props.get("IntDir", root / ".tmp"))
                output.mkdir(parents=True, exist_ok=True)
                intermediate.mkdir(parents=True, exist_ok=True)
                (intermediate / "compiler.obj").write_bytes(b"private intermediate")
                shutil.copyfile(sys.executable, output / "swc.exe")
                (root / "build.json").write_text(json.dumps({"args": sys.argv[1:], "props": props}))
                if os.environ.get("CAMPAIGN_TEST_FAILURE") == "build":
                    print("build child diagnostic", file=sys.stderr)
                    sys.exit(7)
                """), encoding="utf-8")

            bench = root / "bench"
            bench.mkdir()
            (bench / "driver.py").write_text(textwrap.dedent("""
                import json, os, subprocess, sys
                from pathlib import Path
                swc = Path(sys.argv[sys.argv.index("--swc") + 1])
                child = subprocess.run([str(swc), "-S", "-c", "print('fresh compiler')"],
                                       capture_output=True, text=True, check=True)
                Path("driver.json").write_text(json.dumps({
                    "swc": str(swc), "resource_root": os.environ["SWAG_PATH"],
                    "runtime": (swc.parent / "runtime" / "api.swg").read_text(),
                    "output": child.stdout.strip(), "args": sys.argv[1:]}))
                if os.environ.get("CAMPAIGN_TEST_FAILURE") == "driver":
                    sys.exit(9)
                """), encoding="utf-8")

            local = scratch / "local app data"
            env = {"LOCALAPPDATA": str(local), "PYTHONHOME": sys.base_prefix,
                   "PATH": os.path.dirname(sys.executable) + os.pathsep + os.environ.get("PATH", "")}
            with (
                mock.patch.dict(os.environ, env),
                mock.patch.object(campaign, "ROOT", str(root)),
                mock.patch.object(campaign.tc, "BENCH", str(bench)),
                mock.patch.object(campaign.tc, "discover", return_value={"vs": str(vs)}),
                mock.patch.object(sys, "argv", ["campaign.py", "--quick", "--swc-cores", "6"]),
            ):
                launcher = subprocess.Popen(
                    [str(binary), "-S", "-c", "import sys; print('ready', flush=True); sys.stdin.readline()"],
                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
                try:
                    self.assertEqual(launcher.stdout.readline().strip(), "ready")
                    with self.assertRaises(PermissionError):
                        with binary.open("ab"):
                            pass
                    for failure in ("", "build", "driver"):
                        with self.subTest(failure=failure or "success"):
                            os.environ["CAMPAIGN_TEST_FAILURE"] = failure
                            (bench / "driver.json").unlink(missing_ok=True)
                            errors = io.StringIO()
                            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(errors):
                                if failure:
                                    with self.assertRaisesRegex(SystemExit, "Release build failed|driver.py failed"):
                                        campaign.main()
                                else:
                                    self.assertEqual(campaign.main(), 0)
                            self.assertIsNone(launcher.poll())
                            self.assertEqual(binary.read_bytes(), original)
                            self.assertEqual(list((local / "swc-bench-builds").iterdir()), [])

                            built = json.loads((root / "build.json").read_text())
                            props = built["props"]
                            self.assertIn("-m:6", built["args"])
                            self.assertEqual(props["SwcCompileJobs"], "6")
                            self.assertEqual(props["SwcOutputDir"], props["OutDir"])
                            for name in ("OutDir", "IntDir"):
                                Path(props[name]).relative_to(local / "swc-bench-builds")
                            if failure == "build":
                                self.assertIn("build child diagnostic", errors.getvalue())
                                self.assertFalse((bench / "driver.json").exists())
                            else:
                                measured = json.loads((bench / "driver.json").read_text())
                                self.assertEqual(Path(measured["swc"]), Path(props["OutDir"]) / "swc.exe")
                                self.assertEqual(measured["runtime"], "runtime from this checkout")
                                self.assertEqual(Path(measured["resource_root"]), root / "bin")
                                self.assertEqual(measured["output"], "fresh compiler")
                                self.assertIn("--swc-cores", measured["args"])
                finally:
                    launcher.stdin.close()
                    try:
                        launcher.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        launcher.kill()
                        launcher.wait()
                    launcher.stdout.close()


if __name__ == "__main__":
    unittest.main()
