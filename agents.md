# Agents Guide

## Hard Rules

- Always fix the **root cause** of problems. Do not introduce hacks or workarounds.
- Follow the rules defined in `@coding-rules.md` when designing and writing code.

---

### Validation Workflow

- After any change in the compiler (c++ files):
    1. Compile a **DevMode** build.
    2. Run `tests.bat dm`.
    3. If either step fails, fix the issue before proceeding.
    4. Run `alltests.bat dm`
    5. Compile the **Release** build (`swc.exe`).
    6. Run `tests.bat`.
    7. If either release step fails, fix the issue before proceeding.
    8. Do not run `alltests.bat` in release mode as part of the default validation workflow.
	
- After any change in an example (bin/examples) without a c++ change:
    1. Compile a **DevMode** build.
    2. Run this example only, but in all configs : 'examples.bat dm test -m <example> -bc <config>'

---

### Testing

- Any new swag language feature must include **relevant tests**:
    - Place them in the appropriate `bin/unittests` folder.

- **C++ unit tests**:
    - Must be placed in `src/Unittest`

- Individual tests must not exceed **40 seconds** of runtime
  (compilation time excluded).

---

### Clean Workspace

- Remove any **temporary files or folders** created during debugging or investigation before finishing.
