"""Build and checksum one task per available toolchain, without sampling or history."""
import argparse
import json
import os
from pathlib import Path
import re

import installs
import process
import toolchains as tc

CHECKS = dict(zip(tc.TASKS, [130489,24828641,2503168387,4431000,56061776,67441,
                            633277775,169096566666,8629030,674478,622942003053,599499929]))


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--swc')
    ap.add_argument('--task', choices=tc.TASKS, default='sort')
    ap.add_argument('--toolchains', help='comma-separated ids; default all available')
    args = ap.parse_args()
    tc.prepare_sources()
    t = tc.discover()
    env = tc.build_env(t)
    roles = {}
    if args.swc:
        roles['subject'] = installs.snapshot_subject(args.swc)
        error = roles['subject'].publish_dependencies(env, 3)
        if error:
            raise SystemExit(error)
    shared = {'zig': tc.zig_global_cache()}
    if t.get('go'):
        shared['go'] = tc.go_std_cache(t, env, [tc.go_files(args.task)])
    recipes = tc.make_recipes(t, env, roles, 3, shared)
    runtimes = tc.make_runtimes(t, roles, 3)
    launch = tc.make_launchers(t)
    gone = set(tc.missing(t))
    selected = args.toolchains.split(',') if args.toolchains else sorted((recipes.keys() | runtimes.keys()) - gone)
    results = {}
    for name in selected:
        if name in gone:
            results[name] = {'status': 'missing'}
            continue
        if name not in recipes and name not in runtimes:
            ap.error('unknown toolchain: ' + name)
        overrides = {}
        if name in recipes:
            recipe = recipes[name](args.task, 'smoke_' + name.replace('-', '_'))
            for path in recipe['clean']:
                tc.rm(path)
            for path in recipe['mkdir']:
                os.makedirs(path, exist_ok=True)
            if recipe['state']:
                recipe['state'].restore()
            overrides = recipe['env']
            build = process.run(recipe['cmd'], cwd=recipe['cwd'], env=env | overrides)
            if build['exit'] or not Path(recipe['exe']).exists():
                results[name] = {'status': 'build-failed', 'output': build['stdout'] + build['stderr']}
                print(name, 'build-failed', flush=True)
                continue
            cmd = launch[name](recipe['exe'])
        else:
            cmd, overrides = runtimes[name](args.task)
        r = process.run(cmd, cwd=tc.BENCH, env=env | overrides)
        m = re.search(r'CHECK=(-?\d+)', r['stdout'])
        valid = r['exit'] == 0 and m and int(m[1]) == CHECKS[args.task]
        results[name] = {'status': 'ok' if valid else 'checksum-failed',
                         'output': r['stdout'] + r['stderr']}
        print(name, results[name]['status'], flush=True)
    out = Path(tc.OUT) / 'smoke.json'
    out.write_text(json.dumps({'task': args.task, 'timing_claim': False, 'results': results}, indent=2) + '\n')
    print('Setup validation:', out)
    return int(any(r['status'] != 'ok' for r in results.values()))


if __name__ == '__main__':
    raise SystemExit(main())
