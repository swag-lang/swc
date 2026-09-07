# Swag Vault

Swag Vault creates encrypted container files and mounts them as Windows drives through WinFsp.
Its source, ordinary tests, and privileged integration harness share the applications workspace.

## Build, run, and test

Run these commands from the repository root with its compiler:

```text
bin\swc.exe --num-cores 6 tools\apps.swgs dm build swagvault --num-cores 6
bin\swc.exe --num-cores 6 tools\apps.swgs dm run swagvault --num-cores 6
bin\swc.exe --num-cores 6 tools\apps.swgs dm test swagvault --num-cores 6
bin\swc.exe --num-cores 6 tools\apps.swgs dm smoke swagvault --num-cores 6
```

`dm` selects the DevMode compiler. Add `-bc release` after the application name to select the
Release program configuration. The application tool builds and places runtime dependencies before
launching the program; use it when running from a checkout.

## Hidden volumes

Create a hidden filesystem inside an existing container's contiguous free space, with independent
password and key files. Choose its capacity and the minimum space to leave for ordinary files.
Hidden-volume protection is optional at mount: without it, ordinary writes can overwrite hidden
data. See [hidden-volume workflow, format, and limitations](hidden-volumes.md).

## Mounting and runtime files

The packaged application includes `winfsp-x64.dll`, `winfsp-x64.sys`, its shared Swag dependencies,
and the required licence notices. Keep those files beside the executable. Packaging copies the
unmodified WinFsp runtime from the repository's vendor inputs; mounting does not run an installer.

Launch Swag Vault normally. When the portable runtime is needed, the application requests elevation
for its separate driver helper so the mounted drive remains visible to the ordinary Windows session.
The helper stages the runtime in a temporary directory under a Swag Vault-specific identity and
cleans it up after its last mount closes. An already installed WinFsp runtime can also be used.

## Privileged integration

```text
bin\swc.exe --num-cores 6 tools\vault.swgs dm --num-cores 6
```

This explicit tool builds the `vault.integration` variant in the Release program configuration,
creates temporary containers, mounts a real unused drive letter, and checks filesystem operations,
reopening, and visibility from an independent ordinary process. It can request Windows elevation.
Ordinary application tests reject the elevation path and do not mount a drive.

The harness removes its sandbox and writes `integration-result.txt` beside the integration
executable. The tool prints that report and rebuilds the ordinary application before returning.
Use a normal terminal for this command; the helper owns the elevation request.

WinFsp — Windows File System Proxy, Copyright (C) Bill Zissimopoulos —
[WinFsp repository](https://github.com/winfsp/winfsp). See [THIRDPARTY.md](THIRDPARTY.md) for
the bundled version, provenance, and licence text, and [repository tools](../../../../tools/README.md)
for the shared command contract.
