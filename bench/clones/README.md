# Application clones

This directory contains independent application ports used for implementation,
feature-parity and whole-application measurements. Each clone has its own source
folder and README. Build outputs, user profiles, screenshots and machine-specific
reports belong outside the repository, normally under
`%LOCALAPPDATA%/swc-agent-builds/`.

The current clone is [Swag Capture in Rust](capture-rust/README.md). Its source,
Cargo manifest and lockfile are in `capture-rust/`; the shared PowerShell runner
is `capture-rust.ps1`. Add future clones as sibling folders and register their
purpose, state and open work in [the clone backlog](../../backlog/clones.md).

Do not check in a user's `settings.scc`, capture library, or screenshots made from
their captures. Recreate test profiles locally and keep only synthetic fixtures
that are suitable for the repository.
