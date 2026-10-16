"""Prepare an external Release compiler with sanitizer phase counters.

Build the normal Release compiler first. This script only prepares files; run the
emitted batch from the checkout root after the repository machine-load check.
"""

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]


def replace_once(source, old, new):
    if source.count(old) != 1:
        raise RuntimeError(f"profiling anchor changed: {old!r}")
    return source.replace(old, new, 1)


def compile_record(filename):
    lines = (ROOT / ".tmp/x64/release/swc.tlog/CL.command.1.tlog").read_text(encoding="utf-16").splitlines()
    for index, line in enumerate(lines):
        if line.startswith("^") and line.replace("\\", "/").upper().endswith("/" + filename.upper()):
            record = []
            for command in lines[index + 1:]:
                if command.startswith("^"):
                    break
                record.append(command)
            return "\n".join(record)
    raise RuntimeError(f"build Release first: no compile record for {filename}")


def instrument_engine():
    source = (ROOT / "src/Backend/Sanitizer/Sanitizer.cpp").read_text(encoding="utf-8")
    source = replace_once(source, '#include "pch.h"', '#include "pch.h"\n#include "safety-profile.h"')
    anchor = "bool Sanitizer::run(std::span<SanitizerCheck* const> checks)\n{"
    source = replace_once(source, anchor, anchor + "\n    SafetyProfile::Scope profile;")
    anchor = "    while (!worklist.empty())"
    source = replace_once(source, anchor, "    profile.begin(1);\n" + anchor)
    anchor = "    // Apply the checks only on the converged states"
    observer = """
    profile.begin(3);
    profile.local.steps = steps;
    profile.local.states = inState_.size();
    profile.local.capped = !converged_;
    uint64_t payload = inState_.capacity() * sizeof(SanitizerState);
    for (const SanitizerState& state : inState_)
        payload += state.regs.size() * (sizeof(uint32_t) + sizeof(SanitizerRegInfo)) + state.stack.size() * (sizeof(int64_t) + sizeof(SanitizerValue));
    profile.local.maxConvergedPayload = payload;
    profile.begin(2);
"""
    source = replace_once(source, anchor, observer + anchor)
    anchor = "    return reported_;\n}\n\nvoid Sanitizer::computeChainLiveness()"
    source = replace_once(source, anchor, "    profile.local.checkSteps = checkSteps;\n" + anchor)
    anchor = "void Sanitizer::walkChain(uint32_t head, SanitizerState cur, const std::span<const EnabledCheck> checks, SmallVector<uint32_t, 32>* worklist, uint64_t& steps)\n{"
    source = replace_once(source, anchor, anchor + "\n    auto& profile = *SafetyProfile::active;")
    anchor = "                if (interests & enabled.interests)\n                    enabled.check->run(*this, cur, inst, def, ops);"
    replacement = """                if (interests & enabled.interests)
                {
                    ++profile.checkCalls;
                    enabled.check->run(*this, cur, inst, def, ops);
                }"""
    return replace_once(source, anchor, replacement)


def instrument_pass():
    source = (ROOT / "src/Backend/Micro/Passes/Pass.Sanity.cpp").read_text(encoding="utf-8")
    source = replace_once(source, '#include "pch.h"', '#include "pch.h"\n#include "safety-profile.h"')
    anchor = "    Sanitizer sanitizer(context);"
    return replace_once(source, anchor, "    SafetyProfile::PassScope passProfile;\n" + anchor)


def instrument_main():
    source = (ROOT / "src/main.cpp").read_text(encoding="utf-8")
    source = replace_once(source, '#include "pch.h"', '#include "pch.h"\n#include "safety-profile.h"')
    anchor = "int main(const int argc, char* argv[])\n{"
    return replace_once(source, anchor, anchor + "\n    SafetyProfile::Reporter profileReport;")


def main():
    if len(sys.argv) != 2 or not Path(sys.argv[1]).is_absolute():
        raise SystemExit("usage: python make-profile.py <absolute directory outside every checkout>")
    scratch = Path(sys.argv[1]).resolve()
    if any((parent / ".git").exists() for parent in (scratch, *scratch.parents)):
        raise SystemExit("profiling output must be outside every checkout")
    scratch.mkdir(parents=True, exist_ok=True)
    shutil.copy2(Path(__file__).with_name("safety-profile.h"), scratch / "safety-profile.h")
    response_files = []
    objects = []
    for original, contents in [("Sanitizer.cpp", instrument_engine()), ("Pass.Sanity.cpp", instrument_pass()), ("main.cpp", instrument_main())]:
        stem = Path(original).stem + ".Profile"
        copied_source = scratch / (stem + ".cpp")
        copied_source.write_text(contents, encoding="utf-8")
        obj = scratch / (stem + ".obj")
        command = compile_record(original)
        command = re.sub(r'/(?:Yu|Yc|Fp|Fo|Fd)"[^"]*"', "", command, flags=re.I)
        command = re.sub(r"/Z[i7](?=\s|$)", "", command, flags=re.I)
        command = re.sub(r'(?i)(?:"[^"\n]*' + re.escape(original) + r'"|[^\s"]*' + re.escape(original) + ")", "", command)
        command += f'\n/Zi /FS /I"{ROOT / "src"}" /I"{ROOT / "src/Support/Memory/mimalloc/include"}" /I"{scratch}" /Fo"{obj}" /Fd"{scratch / "profile-compiler.pdb"}" "{copied_source}"\n'
        rsp = scratch / (original + ".rsp")
        rsp.write_text(command, encoding="utf-16")
        response_files.append(rsp)
        objects.append((Path(original).with_suffix(".obj").name, obj))

    destination = scratch / "profile-candidate"
    destination.mkdir(exist_ok=True)
    lines = (ROOT / ".tmp/x64/release/swc.tlog/link.command.1.tlog").read_text(encoding="utf-16").splitlines()
    command = "\n".join(line for line in lines if line.strip() and not line.startswith("^"))
    for option, suffix in [("OUT", "swc.exe"), ("PDB", "swc.pdb"), ("LTCGOUT", "swc.iobj"), ("IMPLIB", "swc.lib")]:
        command = re.sub(r"/" + option + r':"[^"\n]*"', lambda _: f'/{option}:"{destination / suffix}"', command, flags=re.I)
    for original, obj in objects:
        command, count = re.subn(r'(?i)(?:"[^"\n]*[/\\]' + re.escape(original) + r'"|[^\s"]*[/\\]' + re.escape(original) + ")", lambda _: f'"{obj}"', command)
        if count != 1:
            raise RuntimeError(f"expected one link input for {original}, found {count}")
    command += f'\n/DEBUG:FULL /CGTHREADS:6 /MAP:"{destination / "swc.map"}"\n'
    link_rsp = scratch / "profile-candidate.rsp"
    link_rsp.write_text(command, encoding="utf-16")

    vswhere = Path(os.environ["ProgramFiles(x86)"]) / "Microsoft Visual Studio/Installer/vswhere.exe"
    installation = subprocess.check_output([str(vswhere), "-latest", "-products", "*", "-version", "[18.0,19.0)", "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64", "-property", "installationPath"], text=True).strip()
    if not installation:
        raise RuntimeError("Visual Studio 18 C++ tools were not found")
    vcvars = Path(installation) / "VC/Auxiliary/Build/vcvars64.bat"
    batch = f'@echo off\ncall "{vcvars}" >nul\n'
    for rsp in response_files:
        batch += f'cl @"{rsp}"\nif errorlevel 1 exit /b %errorlevel%\n'
    batch += f'link @"{link_rsp}"\n'
    (scratch / "build-instrumented.bat").write_text(batch, encoding="utf-8")
    shutil.copytree(ROOT / "bin/runtime", destination / "runtime", dirs_exist_ok=True)
    print(f"Prepared {scratch / 'build-instrumented.bat'}; run it from {ROOT} after load admission.")


if __name__ == "__main__":
    main()