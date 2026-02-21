# Agents Guide

## Hard Rules

- After any change, always run a full build and full test; if either fails, fix it.
- Once everything is working, run 'all_dm.bat' script to ensure no regression.
- If you add a new feature, add new tests in `Sema/` that cover it:
    - Verify expected successful behavior.
    - Verify expected failures by asserting the correct errors are raised.
- Do not add standard library includes in source files; they are already provided (or must be) via the precompiled
  header `pch.h`.
- When designing code, avoid excessive use of lambdas. Prioritize clarity and readability.
- When designing a function which returns something by argument, place that output parameter first, right after global
  parameters (e.g. managers).
- Do not overuse "auto". When it's clearer, use the real type.

## Refactoring Compliance Rules

- All modified or touched code must be brought into compliance with this document.
- When explicitly requested to refactor, existing code must be updated to fully respect all rules defined here.
- Backward compatibility is not required unless explicitly stated.

## Source Code Comment Rules

- Use standardized visual separators if relevant.
    - Big section separators (never inside functions) must use:
      ````cpp
      // ============================================================================
      ````
    - Medium/smaller separators (never inside functions) must use:
      ````cpp
      // ----------------------------------------------------------------------------
      ````
    - To separate blocks of code inside functions, use:
      ````cpp
      ///////////////////////////////////////////
      ````
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

- Run all tests:

  ````bash
  all_dm.bat
  `````

- Run all semantic tests:

    ````bash
    swc_devmode sema --verify --runtime -d C:\Perso\swag-lang\swc\bin\tests\sema
    `````

* Run a specific semantic test:

  ```bash
  swc_devmode sema --verify --runtime -d C:\Perso\swag-lang\swc\bin\tests\sema -ff <filename>
  ```

## Test Authoring Rules

* Only one `swc-expected-error` is possible per `#test` block (what follows will be skipped).
* Write tests using the existing test framework and patterns.
* Write new tests in existing test files if relevant; create new files if tests are different.
* Do not add comments.
* Test files must contain only compilable test code.
