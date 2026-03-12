# Agents Guide

## Hard Rules

- After any change:
    1. Compile a **DevMode** build.
    2. Run `test_dm.bat`.
    3. If either step fails, fix the issue before proceeding.

- When `test_dm.bat` completes successfully (no crashes or errors):
    1. Compile `swc` in **Release** mode.
    2. Run:
       ```
       tools/all_dm.bat
       tools/all.bat
       ```
    3. Ensure no regressions occur.

- When modifying **code generation**, run `all_dm.bat` **10 consecutive times** to detect nondeterministic behavior.

- If a new feature is added, create appropriate tests in the most relevant `bin/tests` folder and file.

- **C++ unit tests**
    - Backend only
    - Must be placed in `backend/unittest`.

- Individual tests must not run longer than **40 seconds**.
  (Compilation time is excluded from this limit.)

---

## Coding Rules

- Comment what you are doing when this is really usefull. Do not over comment. Make it pro.

- Always fix the **root cause** of problems. Do not introduce hacks or workarounds.

- Avoid excessive use of **lambdas**. Favor clarity and readability.

- For functions returning values via parameters:
    - Place the **output parameter first**, after global parameters (e.g., managers).

- Use `auto` when it:
    - Improves readability
    - Avoids repeating complex types
    - Reduces redundancy

  Use explicit types when they better communicate intent.

- Do not add defensive code. Prefere `SWC_ASSERT` if possible.

- Declare **local variables and reference parameters as `const`** when they are not modified
  (`const` placed on the left side of the type).