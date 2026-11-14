"""Single entry point for benchmark tooling on Windows and Linux."""
from pathlib import Path
import runpy
import sys

SCRIPTS = Path(__file__).resolve().parent / 'scripts'
COMMANDS = {'setup': 'compiler_setup', 'smoke': 'smoke', 'campaign': 'campaign',
            'measure': 'driver', 'report': 'mkpage', 'codegen': 'codegen',
            'reference': 'reference', 'compile': 'compile', 'microdiff': 'microdiff'}
if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
    print('Usage: python bench/bench.py <%s> [options]' % '|'.join(COMMANDS))
    raise SystemExit(0 if len(sys.argv) < 2 or sys.argv[1] in ('-h', '--help') else 2)
command = COMMANDS[sys.argv.pop(1)]
sys.path.insert(0, str(SCRIPTS))
runpy.run_path(str(SCRIPTS / (command + '.py')), run_name='__main__')
