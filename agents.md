## Hard Rules

- After any change, always run a full build and full test; if either fails, fix it.
- If you add a new feature, add new tests in Sema/ that cover it:
    - Verify expected successful behavior.
    - Verify expected failures by asserting the correct errors are raised.

    Add this section:

## Source Code Comment Rules

- Use standardized visual separators if relevant.
  * Big section separators (never inside functions) must use:
  ```cpp
  // ============================================================================
  ````
  The line must start with `// ` and extend with `=` up to column 80.

  * Medium/smaller separators must use:
  ```cpp
  // ----------------------------------------------------------------------------
  ```
  The line must start with `// ` and extend with `-` up to column 80.

- Do not use other decorative separator styles.
- Keep separator length consistent (80 columns total).

## Build Instructions (Windows only)

- MSBuild is located at:
  `C:\Program Files\Microsoft Visual Studio\18\Insiders\MSBuild\Current\Bin\amd64\`

- Default build configuration:
  `/p:Configuration=DevMode`

- Build output:
  - Directory: `C:\Perso\swag-lang\swc\bin`
  - Binary name (DevMode): `swc_devmode`

## Test Instructions

- Run all semantic tests:
  ```bash
  swc_devmode sema --verify --runtime -d C:\Perso\swag-lang\swc\bin\tests\sema
  ```

- Run a specific test:
  ```bash
  swc_devmode sema --verify --runtime -d C:\Perso\swag-lang\swc\bin\tests\sema -ff <filename>
  ```

## Test Authoring Rules

- Only one 'swc-expected-error' is possible per #test block (what follows will be skipped)
- Write tests using the existing test framework and patterns.
- Do not add comments.
- Test files must contain only compilable test code.
- Do not modify existing tests unless explicitly requested.