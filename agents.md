## Hard Rules

- After any change, always run a full compile and full test; if either fails, fix it.

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

- Write tests using the existing test framework and patterns.
- Do not add comments.
- Test files must contain only compilable test code.
- Do not modify existing tests unless explicitly requested.