# Swag

Visual Studio Code syntax highlighting and dark theme for the Swag programming language.

# Screenshot

![Syntax Highlighting](images/syntax.png)

# Features

 - Syntax highlighting
 - Theme 'Swag Dark', which uses the same token colors as the generated documentation,
   so code reads the same in the editor and on the language reference
 - Build, rebuild, and format tasks using `swc` from PATH

Run `npm ci` and then `npm test` in this directory to check task discovery, compiler arguments,
and syntax highlighting against the compiler token catalog using the TextMate tokenizer.
