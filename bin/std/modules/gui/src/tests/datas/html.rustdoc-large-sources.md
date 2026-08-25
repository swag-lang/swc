# Large Rustdoc fixture sources

These files are unmodified copies from the documentation installed by the Rust
1.97.1 toolchain (`rustc 1.97.1 (8bab26f4f 2026-07-14)`). They preserve a real
8.15 MB source page whose single highlighted code block expands to more than
400,000 DOM nodes. That scale is intentional: it protects the HTML viewer from
quadratic selector matching and unbounded paint/hit-test scans which small
fixtures cannot expose.

| Local file | Installed Rust distribution file | SHA-256 |
| --- | --- | --- |
| `html.rustdoc-large.html` | `share/doc/rust/html/src/core/stdarch/crates/core_arch/src/arm_shared/neon/generated.rs.html` | `15445503c601f0b5dd87ad620684f050924d99721085264f2a556fa8b4eac2e5` |
| `html.rustdoc-large.normalize.css` | `share/doc/rust/html/static.files/normalize-9960930a.css` | `42cad0035fb96a13167af4024ed8e0b39a155a2c42140742a3950301ba855e62` |
| `html.rustdoc-large.rustdoc.css` | `share/doc/rust/html/static.files/rustdoc-17e0aaed.css` | `264dc5a58dbfaf73bca6f1b5767413c775d1150c07855f6b399e8672ae3d9597` |
| `html.rustdoc-large.noscript.css` | `share/doc/rust/html/static.files/noscript-f7c3ffd8.css` | `6a2a5f394a2da0eb7d2b7ec97383f47635cb024342a2fadfe159633001bcdf44` |

The Rust Standard Library source and rustdoc assets are distributed under
Apache-2.0 OR MIT; this fixture uses the MIT option. `normalize.css` is also
distributed under MIT. See `html.rustdoc-large-license-mit.txt` and the
upstream notices preserved in `html.rustdoc-large-copyright.txt`.

Copyright in the Rust Standard Library is retained by its contributors,
including The Rust Project Developers. The rustdoc stylesheet is Copyright
2015 The Rust Developers. `normalize.css` is Copyright Nicolas Gallagher and
Jonathan Neal.
