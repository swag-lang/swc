# Repository tools

All project-owned Windows batch entry points live in this directory. Run them from the
repository root. Scripts that accept `dm` use `bin/swc_devmode.exe`; otherwise they use
`bin/swc.exe`.

The names are verb-first and grouped by role:

- `test-*` executes tests;
- `build-*` builds several workspaces or configurations;
- `manage-*` forwards `build`, `run`, or `test` to one workspace;
- `run-*`, `generate-*`, `format-*`, `package-*`, `register-*`, and `accept-*` perform one
  explicit maintenance action;
- `_*.bat` files are internal helpers and are not entry points.

## Aggregate builds and tests

| Tool | Purpose |
| --- | --- |
| `build-all-configurations.bat` | Build every workspace in release, debug, and fast-debug |
| `test-all-workspaces.bat` | Run the complete test set once, in fast-debug by default |
| `test-all-configurations.bat` | Run the complete test set in all three configurations |
| `test-compiler-suites.bat` | Run every compiler-focused unit and source-test suite |

## Focused tests

| Tool | Purpose |
| --- | --- |
| `test-cpp-units.bat` | Internal C++ compiler tests |
| `test-lexer-suite.bat` | Lexer sources and expected diagnostics |
| `test-parser-suite.bat` | Parser sources and expected diagnostics |
| `test-semantic-suite.bat` | Semantic sources and expected diagnostics |
| `test-jit-suite.bat` | JIT execution tests |
| `test-native-suite.bat` | Native encoding, linking, and execution tests |
| `test-safety-suite.bat` | Runtime-safety tests |
| `test-sanity-suite.bat` | Static and lifecycle sanity tests |
| `test-workspace-suite.bat` | Multi-module workspace integration tests |
| `test-example-scripts.bat` | Standalone example scripts in deterministic test mode |
| `test-scrypt-integration.bat` | Privileged sCrypt/WinFsp end-to-end sandbox |

## Workspace and maintenance tools

| Tool | Purpose |
| --- | --- |
| `manage-standard-library.bat` | Build or test the standard library, optionally one module |
| `manage-examples-workspace.bat` | Build, run, or test examples, optionally one module |
| `manage-applications-workspace.bat` | Build, run, or test applications, optionally one module |
| `manage-reference-workspace.bat` | Build or test the executable language reference |
| `run-benchmark-campaign.bat` | Run or regenerate the cross-language performance campaign |
| `generate-web-documentation.bat` | Regenerate brand assets and the complete website |
| `format-source-tree.bat` | Format all Swag source workspaces |
| `accept-test-goldens.bat` | Promote reviewed `.actual` snapshots to goldens |
| `package-vscode-extension.bat` | Refresh extension images and build the VSIX package |
| `register-compiler-path.bat` | Register `bin/` in the current user's environment |

`src/Support/Memory/mimalloc/bin/bundle.bat` is intentionally not moved: it belongs to the
vendored mimalloc distribution and retains its upstream layout.
