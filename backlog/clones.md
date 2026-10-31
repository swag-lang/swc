# Application clones

This file tracks independent implementations of Swag applications used to assess
portability, implementation tradeoffs and whole-application behavior. Reference
application work remains in its owning app backlog. Clone sources live under
[`bench/clone/`](../bench/clone/README.md); generated binaries, profiles and
machine-specific measurements stay outside the checkout.

## Current clone state

| Clone | Source | Current state |
| --- | --- | --- |
| Swag Capture in Rust | [`bench/clone/capture-rust/`](../bench/clone/capture-rust/README.md) | Experimental Windows x64 Release port; substantial feature coverage, but visual and behavioral parity is unverified. |

No other application clone is currently tracked here.

### Swag Capture in Rust

The port began from Swag checkout `dec813751c`. It is a native Rust/egui
application, not a wrapper around Swag libraries. Its Release package links the
CRT statically and was inspected with only Windows system DLL imports. The
executable includes Rust dependencies, fonts, translations, icons and resources;
it is therefore a whole-application size comparison, not an application-code-only
measurement. PE size and relocation evidence remains in
[`compiler.optimization.136`](compiler.optimization.md).

The Rust icon atlas embeds the original SVG and rasterizes it once at 4x into a
768 × 480 GPU texture on first paint. This is not a pre-rasterized bitmap bundled
inside the theme. Icon quality, first-use cost, GPU memory and DPI behavior have
not been compared directly with Swag's atlas path; there is no evidence that one
application's icons are visibly inferior. See `std.gui.060` for Swag's atlas and
startup measurements.

Implemented areas include the annotation canvas and common forms, selection and
grouping, undo/redo, image effects, clipboard images, desktop-area capture, the
command lens, an inspector, a capture library, English/French strings, Encre/Papier
palettes, imported Swag Capture settings, and SCC load/save for recognized records.
The library smoke and native capture lifecycle scenarios have working harnesses.

Known gaps are advanced annotation properties and complete SCC compatibility,
exact rasterizer/theme parity, some library operations, global hotkeys, tray
integration and pinned captures. SCC preservation of unknown fields is limited to
recognized records. The Rust library and export renderers differ from Swag's.
These limits and the build/run commands are documented in the clone README.

No equivalent-workload performance result is established. Both available Rust
reports set `parity_verified` to false. A large-capture UI-update run reported a
general median of 0.312 ms and p95 of 0.518 ms, but recorded zero drag frames;
those values do not measure annotation movement and must not be compared to Swag's
frame trace. The attempt to add primary-button movement sampling also produced
zero drag frames when no controlled gesture was present. No valid Rust-versus-Swag
drag timing result exists.

The comparison profile used an isolated copy of a 2,823 × 2,866 capture with 25
forms and a copied Swag settings file. Those user files and the generated reports
are outside the checkout and are not fixtures. Recreate an isolated profile from
locally available test data before continuing; never rewrite the user's originals.
The profile and reports are under
`%LOCALAPPDATA%/swc-agent-builds/capture-rust-20261030/drag-comparison-20261031`.
Two Rust smoke reports on this document recorded process working sets of about
510 MiB and 310 MiB; these are unpaired end-of-run snapshots, not a stable memory
comparison with Swag.

### clones.001 — Establish behavior parity for the Rust Capture port

- Next: resume from the known feature gaps in `bench/clone/capture-rust/README.md`,
  validate the library and capture workflows, and produce a controlled pointer-drag
  trace with nonzero samples plus repeated matched memory samples in both applications
  on the same isolated SCC file.
- Done when: the supported Swag Capture workflows and annotation rendering have
  explicit parity tests across both themes, library and capture lifecycles are stable,
  and any remaining unsupported behavior is documented before equivalent runtime
  measurements are reported.
- Evidence: current reports have `parity_verified: false`; the large-capture Rust
  report has `drag_frames: 0`, so its UI-update percentiles do not characterize a drag.
- Related: std.gui.060
