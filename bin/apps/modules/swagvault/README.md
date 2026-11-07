# Swag Vault

Swag Vault creates encrypted container files and mounts them through WinFsp on Windows or libfuse3 on Linux.
Its source, ordinary tests, and privileged integration harness share the applications workspace.

## Build, run, and test

Run these commands from the repository root with its compiler:

```text
tools\apps.bat dm build swagvault
tools\apps.bat dm run swagvault
tools\apps.bat dm test swagvault
tools\apps.bat dm smoke swagvault
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
The helper stages the runtime in a temporary directory under an identity unique to that helper.
It keeps the driver available until the application exits, then unregisters its own runtime.
Other Swag Vault processes and drivers awaiting deletion therefore have separate identities.
An already installed WinFsp runtime can also be used.

Each mount uses a unique WinFsp UNC name alongside its drive letter, so Windows can resolve
file and directory handles through `GetFinalPathNameByHandleW`, as Python's `os.path.realpath`
does. Windows classifies the drive as a network drive; WinFsp serves its files locally from the
encrypted container without a network server. Restart the application and remount existing
volumes after updating from a version that used local DOS-device mounts.

## Linux mounts

Install the distribution's FUSE 3 runtime and `fusermount3`, with access to `/dev/fuse`.
Vault dynamically loads `libfuse3.so.4` or `libfuse3.so.3`; no driver installer or elevated Vault
process is required. Automatic destinations are private directories under the user's application
data directory, in `swag/vault/mounts`. An existing destination must be empty, owned by the mounting
user, and not writable by another user. Only directories created by Vault are removed on unmount.

Containers keep the same encrypted format and case-insensitive name lookup on both hosts. Linux exposes the mounting user's uid/gid,
files as 0600 and directories as 0700. The persisted read-only attribute removes owner write access.
Creation projects permissions into this private namespace; subsequent `chmod` can change only that
read-only attribute. Other mode changes and ownership changes fail explicitly. Windows security
descriptors are preserved. Symlinks, hard links, extended attributes and special files are not
represented by this container format. Backslashes in Linux names are rejected because the shared
namespace treats them as path separators. Stored timestamps retain 100-nanosecond precision.

A writable container holds an exclusive advisory inode lock; read-only opens hold shared locks.
Other Vault operations therefore cannot resize, rekey or write the same container while it is
mounted. Unmount stops requests, joins the FUSE worker, commits pending metadata and closes the
container. A read-only mount opens the container without host write access as well.

Automatic unmount observes login1 session-lock and sleep signals through `libsystemd.so.0`, with
an inhibitor that delays sleep while the GUI thread commits and unmounts protected volumes.
Queued lock transitions are retained between timer ticks. Idle time comes from XScreenSaver on
X11 (`libX11.so.6` and `libXss.so.1`), or login1 idle hints. These desktop services must be available
and publish the relevant signals/hints; an unavailable idle clock does not invent an idle interval.
The sleep delay remains subject to the session manager's configured inhibitor timeout.

The Linux mount acceptance test is explicitly selected with `--tag vault.fuse.integration
--test-tag integration.filesystem.fuse`. It uses generated scratch containers and verifies real
kernel mounts, open-but-unlinked files, synchronization, read-only remounts and cleanup. Ordinary
callback tests do not require FUSE access. The session protocol test uses the private login1 peer
in `src/tests/datas/login1.peer.py`, selected with `--tag vault.session.integration --test-tag
integration.session`; it never locks or suspends the host session.

## Privileged integration

```text
tools\vault.bat dm
```

This explicit tool builds the `vault.integration` variant in the Release program configuration,
creates temporary containers, mounts a real unused drive letter, and checks filesystem operations,
reopening, and visibility from an independent ordinary process. It can request Windows elevation.
Ordinary application tests reject the elevation path and do not mount a drive.

The harness removes its sandbox and writes `integration-result.txt` beside the integration
executable. The tool prints that report and rebuilds the ordinary application before returning.
Use a normal terminal for this command; the helper owns the elevation request.

The `vault.integration` executable also accepts `--integration-access-benchmark` to create,
measure, and remove a passwordless temporary mount. `--integration-preview-mount <manifest>`
creates a passwordless 512 MiB container and keeps its drive mounted. The manifest receives the
drive letter, sandbox directory, and container path on separate lines. Create a file named `stop`
in that sandbox directory to unmount and remove the test container. Keep the bundled WinFsp DLL
and driver beside the executable. These modes are for isolated performance diagnosis; the
ordinary application build has neither entry point.

WinFsp — Windows File System Proxy, Copyright (C) Bill Zissimopoulos —
[WinFsp repository](https://github.com/winfsp/winfsp). See [THIRDPARTY.md](THIRDPARTY.md) for
the bundled version, provenance, and licence text, and [repository tools](../../../../tools/README.md)
for the shared command contract.
