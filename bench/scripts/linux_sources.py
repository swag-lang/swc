"""Prepare clock/import-only Linux adapters in build outputs, never in src/."""
from pathlib import Path
import re
import shutil


def replace_function(text, signature, body):
    start = text.index(signature)
    brace = text.index('{', start)
    depth, end = 1, brace + 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[:brace + 1] + '\n' + body + '\n' + text[end - 1:]


def prepare(original, destination):
    original, destination = Path(original).resolve(), Path(destination).resolve()
    if destination.is_relative_to(original) or original.is_relative_to(destination):
        raise ValueError("prepared sources must be separate from original sources")
    destination.mkdir(parents=True, exist_ok=True)
    for language in ['cpp', 'd', 'odin', 'go', 'zig', 'swift', 'rust', 'java',
                     'js', 'py', 'cs', 'swagnat', 'swag', 'hello']:
        target = destination / language
        # Remove only this adapter's generated subtree, so removed inputs cannot survive.
        if target.exists():
            shutil.rmtree(target)
        shutil.copytree(original / language, target)

    def rewrite(name, signature, body, replacements=()):
        path = destination / name
        text = path.read_text()
        for before, after in replacements:
            if before not in text:
                raise ValueError('platform adapter input changed: ' + name)
            text = text.replace(before, after)
        path.write_text(replace_function(text, signature, body), encoding='utf-8')

    rewrite('cpp/common.h', 'static inline double now()',
            '    return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();',
            [('#define WIN32_LEAN_AND_MEAN\n#include <windows.h>', '#include <chrono>')])
    rewrite('d/common.d', 'double now()',
            '    timespec value;\n    clock_gettime(CLOCK_MONOTONIC, &value);\n'
            '    return cast(double) value.tv_sec + cast(double) value.tv_nsec / 1e9;',
            [('import core.sys.windows.windows : LARGE_INTEGER, QueryPerformanceCounter, QueryPerformanceFrequency;',
              'import core.sys.posix.time : clock_gettime, CLOCK_MONOTONIC, timespec;')])
    rewrite('odin/common/common.odin', 'now :: proc()',
            '    return time.duration_seconds(time.tick_diff(time.Tick{}, time.tick_now()))',
            [('import "core:sys/windows"', 'import "core:time"')])

    path = destination / 'go/common.go'
    text = path.read_text().replace('"syscall"', '"time"').replace('\n\t"unsafe"', '')
    begin, end = text.index('var kernel32 ='), text.index('func now()')
    text = text[:begin] + 'var benchClock = time.Now()\n\n' + text[end:]
    path.write_text(replace_function(text, 'func now()', '    return time.Since(benchClock).Seconds()'))

    path = destination / 'zig/common.zig'
    text = re.sub(r'extern "kernel32"[^\n]+\n', '', path.read_text())
    text = 'const std = @import("std");\n' + text
    path.write_text(replace_function(text, 'pub fn now()',
                    '    return @as(f64, @floatFromInt(std.time.nanoTimestamp())) / 1e9;'))
    for path in (destination / 'swift').glob('*/main.swift'):
        rewrite(str(path.relative_to(destination)), 'func now()',
                '    return Double(DispatchTime.now().uptimeNanoseconds) / 1e9',
                [('import WinSDK\n', 'import Dispatch\n')])
    for language in ['swagnat', 'swag']:
        rewrite(language + '/common.swg', 'func now()',
                "    var value: timespec\n    discard clock_gettime(CLOCK_MONOTONIC, &value)\n"
                "    return cast(f64, value.tv_sec) + cast(f64, value.tv_nsec) / 1e9'f64")
    for folder in ['cs', 'hello']:
        for path in (destination / folder).rglob('*.csproj'):
            path.write_text(path.read_text().replace('win-x64', 'linux-x64'))
    return str(destination)
