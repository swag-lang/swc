"""Compare final microcode from compile-only copies of the benchmark sources."""
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time

ROOT = next(p for p in Path(__file__).resolve().parents if (p / 'swc.sln').is_file())
sys.path.insert(0, str(ROOT / 'bench'))
import toolchains as tc
import winproc

OUT = ROOT / '.tmp/compile-perf/capture'
OUT.mkdir(parents=True, exist_ok=True)
SOURCE = OUT / 'src'
SOURCE.mkdir(exist_ok=True)
for source in (ROOT / 'bench/src/swagnat').glob('*.swg'):
    (SOURCE / source.name).write_text('#global #[Swag.PrintMicro("pre-emit")]\n' + source.read_text(encoding='utf-8'), encoding='utf-8')

def normalize(output):
    output = re.sub(r'\x1b\[[0-9;]*m', '', output)
    blocks = {}
    for chunk in output.split('[micro]')[1:]:
        name = re.search(r'  function\s*: (.*)', chunk)[1].strip()
        location = re.search(r'  location\s*: (.*)', chunk)[1].strip()
        expected = int(re.search(r'instr: \d+ -> (\d+)', chunk)[1])
        listing = [line.rstrip() for line in chunk.splitlines() if re.match(r'^\d+ \d+(?:\s|$)', line)]
        if len(listing) != expected:
            raise RuntimeError(f'{name}: captured {len(listing)}, expected {expected}')
        # These bracketed values are relocatable process addresses; the symbolic
        # target and all actual immediates remain in the instruction listing.
        listing = [re.sub(r'<0x[0-9A-Fa-f]+>', '<address>', line) for line in listing]
        listing = [re.sub(r' +', ' ', line.split(' | ', 1)[0]).rstrip() + (' | ' + line.split(' | ', 1)[1] if ' | ' in line else '') for line in listing]
        key = name + ' @ ' + location
        blocks.setdefault(key, []).append('\n'.join(listing))
    result = {k: sorted(v) for k, v in sorted(blocks.items())}
    relocations = {}
    def relocation_name(match):
        value = match[0]
        if value not in relocations:
            relocations[value] = f'<relocation-{len(relocations)}>'
        return relocations[value]
    for key, codes in result.items():
        result[key] = [re.sub(r'global_(?:zero|init)\+0x[0-9A-Fa-f]+|(?<=reloc = constant = )0x[0-9A-Fa-f]+', relocation_name, code) for code in codes]
    return result

records = []
for task in tc.TASKS:
    pair = {}
    for tag in ['baseline', 'candidate']:
        folder = OUT / tag / task
        folder.mkdir(parents=True, exist_ok=True)
        command = [str(ROOT / 'bin' / ('swc.' + tag + '.exe')), 'build', '--build-cfg', 'release', '--num-cores', '6', '--rebuild', '-n', task, '-od', str(folder), '-wd', str(folder)]
        for source in tc.swag_files(task, 'swagnat'):
            command += ['-f', str(SOURCE / Path(source).name)]
        while True:
            admission = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(ROOT / '.agents/skills/modify-swag-codebase/scripts/check-machine-load.ps1')], capture_output=True, text=True)
            if admission.returncode == 0:
                break
            if admission.returncode != 2:
                raise RuntimeError(admission.stdout + admission.stderr)
            print('Waiting for machine headroom', flush=True)
            time.sleep(10)
        result = winproc.run(command, cwd=str(ROOT), env=dict(os.environ))
        output = result['stdout'] + result['stderr']
        (OUT / (task + '-' + tag + '.txt')).write_text(output, encoding='utf-8')
        if result['exit']:
            raise RuntimeError(output)
        pair[tag] = normalize(output)
        if not pair[tag]:
            raise RuntimeError('No microcode captured')
        (OUT / (task + '-' + tag + '.json')).write_text(json.dumps(pair[tag], indent=2), encoding='utf-8')
    equal = pair['baseline'] == pair['candidate']
    hashes = {tag: {name: [hashlib.sha256(code.encode()).hexdigest() for code in codes] for name, codes in blocks.items()} for tag, blocks in pair.items()}
    records.append({'task': task, 'equal': equal, 'functions': len(pair['baseline']), 'hashes': hashes})
    (OUT / 'comparison.json').write_text(json.dumps(records, indent=2), encoding='utf-8')
    if not equal:
        a = json.dumps(pair['baseline'], indent=2).splitlines()
        b = json.dumps(pair['candidate'], indent=2).splitlines()
        (OUT / (task + '.diff')).write_text('\n'.join(difflib.unified_diff(a, b)), encoding='utf-8')
    print(task, 'identical' if equal else 'DIFF', len(pair['baseline']), 'functions', flush=True)

if not all(record['equal'] for record in records):
    raise SystemExit(1)
