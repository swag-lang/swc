"""Inspect the PE import tables without executing or loading the binary."""
import argparse
import hashlib
import json
import struct
from pathlib import Path


def inspect(path):
    data = Path(path).read_bytes()
    u16 = lambda at: struct.unpack_from('<H', data, at)[0]
    u32 = lambda at: struct.unpack_from('<I', data, at)[0]
    pe = u32(0x3C)
    if data[:2] != b'MZ' or data[pe:pe + 4] != b'PE\0\0':
        raise ValueError('The file is not a PE executable.')
    optional = pe + 24
    if u16(optional) != 0x20B:
        raise ValueError('The executable is not PE32+.')
    sections = []
    section_table = optional + u16(pe + 20)
    for i in range(u16(pe + 6)):
        at = section_table + i * 40
        sections.append((u32(at + 12), max(u32(at + 8), u32(at + 16)), u32(at + 20)))

    def offset(rva):
        for start, size, raw in sections:
            if start <= rva < start + size:
                return raw + rva - start
        raise ValueError(f'Unmapped RVA {rva:x}')

    def name(rva):
        at = offset(rva)
        return data[at:data.index(0, at)].decode('ascii')

    imports = []
    directory = optional + 112
    rva = u32(directory + 8)
    if rva:
        at = offset(rva)
        while any(data[at:at + 20]):
            imports.append(name(u32(at + 12)))
            at += 20
    delayed = []
    rva = u32(directory + 13 * 8)
    if rva:
        at = offset(rva)
        while any(data[at:at + 32]):
            if u32(at) & 1 == 0:
                raise ValueError('Unsupported absolute delay-import descriptor.')
            delayed.append(name(u32(at + 4)))
            at += 32
    system = {'advapi32.dll', 'bcrypt.dll', 'bcryptprimitives.dll', 'combase.dll', 'cfgmgr32.dll', 'comctl32.dll', 'comdlg32.dll',
              'crypt32.dll', 'dwmapi.dll', 'gdi32.dll', 'imm32.dll', 'iphlpapi.dll',
              'kernel32.dll', 'msimg32.dll', 'ntdll.dll', 'ole32.dll', 'oleaut32.dll',
              'opengl32.dll', 'powrprof.dll', 'propsys.dll', 'psapi.dll', 'rpcrt4.dll',
              'secur32.dll', 'setupapi.dll', 'shell32.dll', 'shlwapi.dll', 'user32.dll',
              'userenv.dll', 'usp10.dll', 'uxtheme.dll', 'version.dll', 'winmm.dll',
              'winspool.drv', 'ws2_32.dll', 'wtsapi32.dll', 'dwrite.dll', 'windowscodecs.dll'}
    external = [dll for dll in imports + delayed if dll.lower() not in system and not dll.lower().startswith(('api-ms-win-', 'ext-ms-win-'))]
    return {'path': str(Path(path).resolve()), 'size_bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest(), 'imports': imports,
            'delay_imports': delayed, 'non_system_imports': external,
            'single_executable_import_check': not external}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('executable')
    parser.add_argument('--output')
    args = parser.parse_args()
    result = inspect(args.executable)
    text = json.dumps(result, indent=2)
    print(text)
    if args.output:
        Path(args.output).write_text(text + '\n', encoding='utf-8')
    raise SystemExit(bool(result['non_system_imports']))
