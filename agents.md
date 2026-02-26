# Agents Guide

## Hard Rules

- After any change, always run a full build and full test; if either fails, fix it.
- Once everything is working, run 'tools/all_dm.bat' and 'tools/all.bat' scripts to ensure no regression.
- When doing a change in codegen, run it 10x times in a row, to detect non deterministic behavior.
- If you add a new feature, add new tests in `Sema/` that cover it:
    - Verify expected successful behavior.
    - Verify expected failures by asserting the correct errors are raised.
- Do not hack or make workarounds, always find the root cause of each problem.

## Coding Rules

- Do not add standard library includes in source files; they must be provided via the precompiled header `pch.h`. Exception for OsWin32.
- Avoid excessive use of lambdas. Prioritize clarity and readability.
- When designing a function which returns something by argument, place that output parameter first, right after global
  parameters (e.g. managers).
- Use auto for variable declarations when it makes the code clearer, reduces redundancy, or avoids repeating complex types. Use the explicit (real) type when it better communicates intent or improves readability.
- Do not put defensive code after asserts.
- Declare local variables and reference parameters as const whenever they are not modified (const on the left of the type).

## Formating code

- When you are done with coding, and everything is working fine (after the tests), run clang-format.exe only on modified c++ files.
- If nothing is modified, do not run it.
- After the formating, recompile but do not run tests again.

  ````bash
  C:\Program Files\JetBrains\JetBrains Rider 2025.3.1\lib\ReSharperHost\windows-x64\clang-format.exe
  ````

  If you can't find the executable there, look for new rider versions.

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

- MSBuild can be located at:
  `C:\Program Files\Microsoft Visual Studio\18\Insiders\MSBuild\Current\Bin\amd64\`
  `C:\Program Files\Microsoft Visual Studio\18\Enterprise\MSBuild\Current\Bin\amd64\`
- Default build configuration:
  `/p:Configuration=DevMode`
  `/p:Configuration=Release`
- Build output:
    - Directory: `C:\Perso\swag-lang\swc\bin`
    - Binary name (DevMode): `swc_devmode`
    - Binary name (Release): `swc`

## Test Instructions

- Run all tests:

  ````bash
  tools/all_dm.bat
  tools/all.bat
  `````

- Run all semantic tests:

    ````bash
    swc_devmode sema --verify --runtime -d C:\Perso\swag-lang\swc\bin\tests\sema
    swc sema --verify --runtime -d C:\Perso\swag-lang\swc\bin\tests\sema
    `````

* Run a specific semantic test:

  ```bash
  swc_devmode sema --verify --runtime -d C:\Perso\swag-lang\swc\bin\tests\sema -ff <filename>
  swc sema --verify --runtime -d C:\Perso\swag-lang\swc\bin\tests\sema -ff <filename>
  ```

## Test Authoring Rules

* Only one `swc-expected-error` is possible per `#test` block (what follows will be skipped).
* Write tests using the existing test framework and patterns.
* Write new tests in existing test files if relevant; create new files if tests are different.
* Do not add comments.
* Test files must contain only compilable test code.
