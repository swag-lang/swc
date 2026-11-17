# Swag

Syntax highlighting, a dark theme, and build tasks for Swag in Visual Studio Code.

# Screenshot

![Syntax Highlighting](images/syntax.png)

# Features

 - Syntax highlighting from a TextMate grammar checked against the compiler token catalog
 - Theme 'Swag Dark', which uses the same token colors as the generated documentation,
   so code reads the same in the editor and on the language reference
 - Build, rebuild, and format tasks using `swc` from PATH, with a problem matcher for
   compiler diagnostics

The extension runs no compiler in the background: it has no language server, and the
compiler has no editor service. Diagnostics appear when a task runs.

## Setup

Use VS Code 1.82 or newer. The tasks launch `swc` from PATH; if PATH was changed while
VS Code was running, close all VS Code windows and start it again to pick up the new
environment.

Run `npm ci`, open this directory in VS Code, and launch the `Extension` configuration with
F5. In the development window, open a Swag module or an existing `.swg`/`.swgs` file.

## Validation

Run `npm test` for task discovery, extension activation, and the TextMate grammar.
