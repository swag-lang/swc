# Third-Party Components

## WinFsp 2.2.26215 (2026 Beta 4)

WinFsp - Windows File System Proxy, Copyright (C) Bill Zissimopoulos

- Project: <https://github.com/winfsp/winfsp>
- Website: <https://winfsp.dev/>
- License: GNU GPLv3 with the FLOSS exception, reproduced in `vendor/winfsp/LICENSE.txt`
- Unmodified official package: `winfsp-2.2.26215.msi`
- SHA-256: `2ECB5C89405488A95BBD8A01875E02C48534FD37BBDFD84488F7590464D65944`

The package is signed by NAVIMATICS LLC. Its x64 driver is signed by Microsoft Windows Hardware
Compatibility Publisher. sVaultDrive extracts it to the user's temporary directory, registers it
under an sVaultDrive-specific side-by-side identity while a volume is mounted, then unregisters it
and removes the temporary files during a normal unmount.
