#global internal

using Core, Pixel, Gui

internal enum CodeLanguage
{
    C
    Cpp
    CSharp
    Java
    JavaScript
    TypeScript
    Go
    Rust
    Python
    Ruby
    Shell
    PowerShell
    Php
    Lua
    Sql
    Json
    Xml
    Css
    Yaml
    Toml
    Config
    Kotlin
    Swift
    Dart
    R
    Perl
    VisualBasic
    Shader
    CMake
    Batch
    Html
    Assembly
    Zig
    Nim
    Haskell
    Scala
    Groovy
    Elixir
    Erlang
    Clojure
    Julia
    Fortran
    Pascal
    D
    ObjectiveC
    Matlab
    Tcl
    Awk
    Vim
    Latex
    Protobuf
    GraphQl
    Gradle
    Makefile
    Dockerfile
    Nix
}

internal struct CodeShebang
{
    found:    bool
    language: CodeLanguage
}

// Reads the interpreter named by an extensionless script without retaining the file.
internal func codeShebang(fileName: string)->CodeShebang
{
    var stream = catch File.openRead(fileName) as openError
    if openError != null do
        return {}
    defer stream.close()

    let head = catch stream.readUtf8Chunk(512) as readError
    if readError != null or !head.startsWith("#!") do
        return {}
    let lines = Tokenize.split(head.toString(), '\n'u8, maxSplit: 1)
    let line  = String.from(lines[0])
    let lower = line.toLower()
    if Utf8.contains(lower.toString(), "python") do
        return {true, .Python}
    if Utf8.contains(lower.toString(), "ruby") do
        return {true, .Ruby}
    if Utf8.contains(lower.toString(), "perl") do
        return {true, .Perl}
    if Utf8.contains(lower.toString(), "pwsh") or Utf8.contains(lower.toString(), "powershell") do
        return {true, .PowerShell}
    if Utf8.contains(lower.toString(), "deno") do
        return {true, .TypeScript}
    if Utf8.contains(lower.toString(), "node") or Utf8.contains(lower.toString(), "bun") do
        return {true, .JavaScript}
    return {true, .Shell}
}

private func codeLooksLikeObjectiveC(fileName: string)->bool
{
    var stream = catch File.openRead(fileName) as openError
    if openError != null do
        return false
    defer stream.close()

    let head = catch stream.readUtf8Chunk(4 * 1024) as readError
    if readError != null do
        return false
    const Markers: [5] string = ["#import", "@interface", "@implementation", "@protocol", "@property"]
    for marker in Markers where Utf8.contains(head.toString(), marker) do
        return true
    return false
}

internal func codeLanguage(fileName: string)->CodeLanguage
{
    var baseName = String.from(Path.fileName(fileName) orelse "")
    baseName = baseName.toLower()
    switch baseName.toString()
    {
    case "makefile", "gnumakefile", "bsdmakefile": return .Makefile
    case "justfile":                               return .Makefile
    case "dockerfile", "containerfile":            return .Dockerfile
    case "cmakelists.txt":                         return .CMake
    case "rakefile", "gemfile", "vagrantfile", "podfile", "brewfile": return .Ruby
    case "jenkinsfile":                            return .Groovy
    case "meson.build", ".gitignore", ".gitattributes", ".gitmodules", ".editorconfig", ".clang-format", ".clang-tidy", ".prettierrc", ".eslintrc", ".npmrc", ".yarnrc", ".env": return .Config
    }

    let extension = Path.lowercaseExtension(fileName)
    switch extension.toString()
    {
    case ".c", ".h":                                                                   return .C
    case ".cc", ".cpp", ".cxx", ".hh", ".hpp", ".hxx", ".inl", ".ipp":                 return .Cpp
    case ".cs":                                                                        return .CSharp
    case ".java":                                                                      return .Java
    case ".js", ".jsx", ".mjs", ".cjs":                                                return .JavaScript
    case ".ts", ".tsx", ".mts", ".cts":                                                return .TypeScript
    case ".go":                                                                        return .Go
    case ".rs":                                                                        return .Rust
    case ".py", ".pyw", ".pyi":                                                        return .Python
    case ".rb", ".rake", ".gemspec":                                                   return .Ruby
    case ".sh", ".bash", ".zsh", ".fish":                                              return .Shell
    case ".ps1", ".psm1", ".psd1":                                                     return .PowerShell
    case ".php", ".phtml":                                                             return .Php
    case ".lua":                                                                       return .Lua
    case ".sql":                                                                       return .Sql
    case ".json", ".jsonc", ".json5":                                                  return .Json
    case ".xml", ".xsd", ".xsl", ".xslt", ".csproj", ".vcxproj", ".props", ".targets": return .Xml
    case ".css", ".scss", ".sass", ".less":                                            return .Css
    case ".yaml", ".yml":                                                              return .Yaml
    case ".toml":                                                                      return .Toml
    case ".ini", ".cfg", ".conf", ".properties":                                       return .Config
    case ".kt", ".kts":                                                                return .Kotlin
    case ".swift":                                                                     return .Swift
    case ".dart":                                                                      return .Dart
    case ".r":                                                                         return .R
    case ".pl", ".pm":                                                                 return .Perl
    case ".vb":                                                                        return .VisualBasic
    case ".glsl", ".vert", ".frag", ".geom", ".comp", ".hlsl", ".fx":                  return .Shader
    case ".cmake":                                                                     return .CMake
    case ".bat", ".cmd":                                                               return .Batch
    case ".htm", ".html", ".shtml", ".xht", ".xhtml":                                  return .Html
    case ".asm", ".s", ".incasm":                                                      return .Assembly
    case ".zig":                                                                       return .Zig
    case ".nim", ".nims", ".nimble":                                                   return .Nim
    case ".hs", ".lhs":                                                                return .Haskell
    case ".scala", ".sc":                                                              return .Scala
    case ".groovy", ".gvy", ".gy", ".gsh":                                             return .Groovy
    case ".ex", ".exs":                                                                return .Elixir
    case ".erl", ".hrl":                                                               return .Erlang
    case ".clj", ".cljs", ".cljc", ".edn":                                             return .Clojure
    case ".jl":                                                                        return .Julia
    case ".f", ".for", ".f77", ".f90", ".f95", ".f03", ".f08":                         return .Fortran
    case ".pas", ".pp", ".lpr":                                                        return .Pascal
    case ".d", ".di":                                                                  return .D
    case ".mm":                                                                        return .ObjectiveC
    case ".m":                                                                         return codeLooksLikeObjectiveC(fileName) ? .ObjectiveC : .Matlab
    case ".tcl", ".tk":                                                                return .Tcl
    case ".awk":                                                                       return .Awk
    case ".vim":                                                                       return .Vim
    case ".tex", ".sty", ".cls", ".bib":                                               return .Latex
    case ".proto":                                                                     return .Protobuf
    case ".graphql", ".gql":                                                           return .GraphQl
    case ".gradle":                                                                    return .Gradle
    case ".mk", ".mak", ".make":                                                       return .Makefile
    case ".dockerfile":                                                                return .Dockerfile
    case ".nix":                                                                       return .Nix
    }

    let shebang = codeShebang(fileName)
    return shebang.found ? shebang.language : .C
}

internal func codeLanguageName(language: CodeLanguage)->string
{
    switch language
    {
    case .C:           return "C"
    case .Cpp:         return "C++"
    case .CSharp:      return "C#"
    case .Java:        return "Java"
    case .JavaScript:  return "JavaScript"
    case .TypeScript:  return "TypeScript"
    case .Go:          return "Go"
    case .Rust:        return "Rust"
    case .Python:      return "Python"
    case .Ruby:        return "Ruby"
    case .Shell:       return "Shell"
    case .PowerShell:  return "PowerShell"
    case .Php:         return "PHP"
    case .Lua:         return "Lua"
    case .Sql:         return "SQL"
    case .Json:        return "JSON"
    case .Xml:         return "XML"
    case .Css:         return "CSS"
    case .Yaml:        return "YAML"
    case .Toml:        return "TOML"
    case .Config:      return "Configuration"
    case .Kotlin:      return "Kotlin"
    case .Swift:       return "Swift"
    case .Dart:        return "Dart"
    case .R:           return "R"
    case .Perl:        return "Perl"
    case .VisualBasic: return "Visual Basic"
    case .Shader:      return "Shader"
    case .CMake:       return "CMake"
    case .Batch:       return "Batch"
    case .Html:        return "HTML"
    case .Assembly:    return "Assembly"
    case .Zig:         return "Zig"
    case .Nim:         return "Nim"
    case .Haskell:     return "Haskell"
    case .Scala:       return "Scala"
    case .Groovy:      return "Groovy"
    case .Elixir:      return "Elixir"
    case .Erlang:      return "Erlang"
    case .Clojure:     return "Clojure"
    case .Julia:       return "Julia"
    case .Fortran:     return "Fortran"
    case .Pascal:      return "Pascal"
    case .D:           return "D"
    case .ObjectiveC:  return "Objective-C"
    case .Matlab:      return "MATLAB"
    case .Tcl:         return "Tcl"
    case .Awk:         return "Awk"
    case .Vim:         return "Vim script"
    case .Latex:       return "LaTeX"
    case .Protobuf:    return "Protocol Buffers"
    case .GraphQl:     return "GraphQL"
    case .Gradle:      return "Gradle"
    case .Makefile:    return "Makefile"
    case .Dockerfile:  return "Dockerfile"
    case .Nix:         return "Nix"
    }
}

private enum GenericCodeState: s32
{
    Default
    BlockComment
    MarkupComment
}

internal struct GenericCodeLexer
{
    internal enum Style: RichEditStyleRef
    {
        Default
        Comment
        Keyword
        Type
        String
        Number
        Function
        Preprocessor
    }

    language: CodeLanguage
    keywords: HashTable'(string, bool)
}

private impl GenericCodeLexer
{
    mtd addWords(words: const [..] string)
    {
        for word in words do
            .keywords.add(word, true)
    }

    mtd configure(language: CodeLanguage)
    {
        .language = language
        switch language
        {
        case .C, .Cpp, .Shader:           .addWords(["auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long", "register", "restrict", "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned", "void", "volatile", "while", "bool", "class", "namespace", "new", "delete", "public", "private", "protected", "template", "typename", "using", "virtual", "override", "constexpr", "nullptr", "this", "throw", "try", "catch"])
        case .CSharp:                     .addWords(["abstract", "as", "async", "await", "base", "bool", "break", "case", "catch", "class", "const", "continue", "decimal", "default", "delegate", "do", "else", "enum", "event", "explicit", "extern", "false", "finally", "fixed", "for", "foreach", "get", "if", "implicit", "in", "interface", "internal", "is", "lock", "namespace", "new", "null", "operator", "out", "override", "params", "private", "protected", "public", "readonly", "record", "ref", "return", "sealed", "set", "static", "string", "struct", "switch", "this", "throw", "true", "try", "typeof", "using", "var", "virtual", "void", "while", "yield"])
        case .Java, .Kotlin:              .addWords(["abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class", "const", "continue", "default", "do", "double", "else", "enum", "extends", "false", "final", "finally", "float", "for", "fun", "if", "implements", "import", "in", "instanceof", "int", "interface", "internal", "is", "long", "native", "new", "null", "object", "open", "override", "package", "private", "protected", "public", "return", "sealed", "short", "static", "super", "synchronized", "this", "throw", "throws", "transient", "true", "try", "val", "var", "void", "volatile", "when", "while"])
        case .JavaScript, .TypeScript:    .addWords(["async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for", "from", "function", "get", "if", "implements", "import", "in", "instanceof", "interface", "let", "new", "null", "of", "private", "protected", "public", "return", "set", "static", "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "var", "void", "while", "with", "yield"])
        case .Go:                         .addWords(["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "false", "for", "func", "go", "goto", "if", "import", "interface", "map", "nil", "package", "range", "return", "select", "struct", "switch", "true", "type", "var"])
        case .Rust:                       .addWords(["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while"])
        case .Python:                     .addWords(["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except", "False", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "None", "nonlocal", "not", "or", "pass", "raise", "return", "True", "try", "while", "with", "yield"])
        case .Ruby:                       .addWords(["alias", "and", "begin", "break", "case", "class", "def", "defined", "do", "else", "elsif", "end", "ensure", "false", "for", "if", "in", "module", "next", "nil", "not", "or", "redo", "rescue", "retry", "return", "self", "super", "then", "true", "undef", "unless", "until", "when", "while", "yield"])
        case .Shell, .PowerShell, .Batch: .addWords(["begin", "break", "case", "catch", "continue", "do", "done", "elif", "else", "end", "esac", "exit", "fi", "finally", "for", "foreach", "function", "if", "in", "param", "return", "select", "switch", "then", "throw", "trap", "try", "until", "while"])
        case .Php:                        .addWords(["abstract", "and", "array", "as", "break", "callable", "case", "catch", "class", "clone", "const", "continue", "declare", "default", "do", "echo", "else", "elseif", "empty", "endfor", "endforeach", "endif", "endswitch", "endwhile", "enum", "extends", "false", "final", "finally", "fn", "for", "foreach", "function", "global", "if", "implements", "include", "instanceof", "interface", "match", "namespace", "new", "null", "private", "protected", "public", "readonly", "require", "return", "static", "throw", "trait", "true", "try", "use", "var", "while", "yield"])
        case .Lua:                        .addWords(["and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"])
        case .Sql:                        .addWords(["add", "alter", "and", "as", "asc", "begin", "between", "by", "case", "column", "commit", "constraint", "create", "database", "default", "delete", "desc", "distinct", "drop", "else", "end", "exists", "false", "foreign", "from", "full", "group", "having", "in", "index", "inner", "insert", "into", "is", "join", "key", "left", "like", "limit", "not", "null", "on", "or", "order", "outer", "primary", "references", "right", "rollback", "select", "set", "table", "then", "true", "union", "unique", "update", "values", "view", "when", "where", "with"])
        case .Json:                       .addWords(["false", "null", "true"])
        case .Css:                        .addWords(["@charset", "@container", "@font-face", "@import", "@keyframes", "@layer", "@media", "@namespace", "@page", "@supports", "important"])
        case .Yaml, .Toml, .Config:       .addWords(["false", "inf", "nan", "null", "off", "on", "true", "yes", "no"])
        case .Swift:                      .addWords(["as", "associatedtype", "break", "case", "catch", "class", "continue", "default", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate", "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let", "nil", "open", "operator", "private", "protocol", "public", "repeat", "rethrows", "return", "self", "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias", "var", "where", "while"])
        case .Dart:                       .addWords(["abstract", "as", "assert", "async", "await", "break", "case", "catch", "class", "const", "continue", "default", "deferred", "do", "dynamic", "else", "enum", "export", "extends", "extension", "external", "factory", "false", "final", "finally", "for", "function", "get", "hide", "if", "implements", "import", "in", "interface", "is", "late", "library", "mixin", "new", "null", "on", "operator", "part", "required", "return", "set", "show", "static", "super", "switch", "sync", "this", "throw", "true", "try", "typedef", "var", "void", "while", "with", "yield"])
        case .R:                          .addWords(["break", "else", "FALSE", "for", "function", "if", "Inf", "NA", "NaN", "next", "NULL", "repeat", "return", "TRUE", "while"])
        case .Perl:                       .addWords(["continue", "do", "else", "elsif", "for", "foreach", "given", "goto", "if", "last", "local", "my", "next", "no", "package", "redo", "require", "return", "state", "sub", "unless", "until", "use", "when", "while"])
        case .VisualBasic:                .addWords(["as", "async", "await", "boolean", "byref", "byval", "case", "catch", "class", "const", "continue", "dim", "do", "each", "else", "elseif", "end", "enum", "false", "finally", "for", "function", "get", "handles", "if", "implements", "imports", "in", "inherits", "interface", "module", "new", "nothing", "of", "private", "property", "protected", "public", "return", "select", "set", "shared", "static", "structure", "sub", "then", "throw", "true", "try", "while", "with"])
        case .CMake:                      .addWords(["break", "cmake_minimum_required", "continue", "else", "elseif", "endforeach", "endfunction", "endif", "endmacro", "endwhile", "find_package", "foreach", "function", "if", "include", "macro", "project", "return", "set", "target_compile_definitions", "target_include_directories", "target_link_libraries", "while"])
        case .Assembly:                   .addWords(["section", "segment", "global", "extern", "align", "bits", "byte", "word", "dword", "qword", "db", "dw", "dd", "dq", "mov", "lea", "push", "pop", "call", "ret", "jmp", "cmp", "test", "add", "sub", "mul", "imul", "div", "idiv", "and", "or", "xor", "not", "shl", "shr", "sal", "sar", "inc", "dec", "nop"])
        case .Zig:                        .addWords(["addrspace", "align", "allowzero", "and", "anyframe", "anytype", "asm", "async", "await", "break", "callconv", "catch", "comptime", "const", "continue", "defer", "else", "enum", "errdefer", "error", "export", "extern", "false", "fn", "for", "if", "inline", "linksection", "noalias", "nosuspend", "null", "opaque", "or", "orelse", "packed", "pub", "resume", "return", "struct", "suspend", "switch", "test", "threadlocal", "true", "try", "union", "unreachable", "usingnamespace", "var", "volatile", "while"])
        case .Nim:                        .addWords(["addr", "and", "as", "asm", "bind", "block", "break", "case", "cast", "concept", "const", "continue", "converter", "defer", "discard", "distinct", "div", "do", "elif", "else", "end", "enum", "except", "export", "finally", "for", "from", "func", "if", "import", "in", "include", "interface", "is", "isnot", "iterator", "let", "macro", "method", "mixin", "mod", "nil", "not", "notin", "object", "of", "or", "out", "proc", "ptr", "raise", "ref", "return", "shl", "shr", "static", "template", "try", "tuple", "type", "using", "var", "when", "while", "with", "without", "xor", "yield"])
        case .Haskell:                    .addWords(["as", "case", "class", "data", "default", "deriving", "do", "else", "family", "foreign", "hiding", "if", "import", "in", "infix", "infixl", "infixr", "instance", "let", "module", "newtype", "of", "pattern", "qualified", "role", "then", "type", "where"])
        case .Scala:                      .addWords(["abstract", "case", "catch", "class", "def", "do", "else", "enum", "export", "extends", "false", "final", "finally", "for", "forSome", "given", "if", "implicit", "import", "inline", "lazy", "match", "new", "null", "object", "opaque", "open", "override", "package", "private", "protected", "return", "sealed", "super", "then", "this", "throw", "trait", "transparent", "true", "try", "type", "using", "val", "var", "while", "with", "yield"])
        case .Groovy, .Gradle:            .addWords(["as", "assert", "break", "case", "catch", "class", "const", "continue", "def", "default", "do", "else", "enum", "extends", "false", "finally", "for", "goto", "if", "implements", "import", "in", "instanceof", "interface", "native", "new", "non-sealed", "null", "package", "permits", "private", "protected", "public", "record", "return", "sealed", "static", "strictfp", "super", "switch", "synchronized", "this", "throw", "throws", "trait", "transient", "true", "try", "var", "void", "volatile", "while"])
        case .Elixir:                     .addWords(["after", "alias", "and", "case", "catch", "cond", "def", "defdelegate", "defexception", "defguard", "defimpl", "defmacro", "defmodule", "defp", "defprotocol", "defstruct", "do", "else", "end", "false", "fn", "for", "if", "import", "in", "nil", "not", "or", "quote", "raise", "receive", "require", "rescue", "super", "throw", "true", "try", "unless", "unquote", "use", "when", "with"])
        case .Erlang:                     .addWords(["after", "and", "andalso", "band", "begin", "bnot", "bor", "bsl", "bsr", "bxor", "case", "catch", "cond", "div", "end", "fun", "if", "let", "not", "of", "or", "orelse", "receive", "rem", "try", "when", "xor"])
        case .Clojure:                    .addWords(["def", "defn", "defmacro", "defmethod", "defmulti", "defonce", "defprotocol", "defrecord", "deftype", "do", "doseq", "dotimes", "fn", "for", "if", "if-let", "if-not", "let", "letfn", "loop", "ns", "quote", "recur", "throw", "try", "var", "when", "when-let", "when-not", "while"])
        case .Julia:                      .addWords(["baremodule", "begin", "break", "catch", "const", "continue", "do", "else", "elseif", "end", "export", "false", "finally", "for", "function", "global", "if", "import", "let", "local", "macro", "module", "quote", "return", "struct", "true", "try", "using", "while"])
        case .Fortran:                    .addWords(["allocate", "assign", "associate", "backspace", "block", "call", "case", "class", "close", "common", "contains", "continue", "cycle", "data", "deallocate", "dimension", "do", "else", "elseif", "end", "enddo", "endif", "entry", "equivalence", "exit", "external", "forall", "format", "function", "goto", "if", "implicit", "import", "include", "inquire", "interface", "intrinsic", "module", "namelist", "none", "nullify", "only", "open", "operator", "optional", "parameter", "pause", "pointer", "print", "private", "procedure", "program", "public", "pure", "read", "recursive", "return", "rewind", "save", "select", "stop", "subroutine", "target", "then", "type", "use", "where", "while", "write"])
        case .Pascal:                     .addWords(["and", "array", "as", "asm", "begin", "case", "class", "const", "constructor", "destructor", "div", "do", "downto", "else", "end", "except", "exports", "file", "finalization", "finally", "for", "function", "goto", "if", "implementation", "in", "inherited", "initialization", "inline", "interface", "is", "label", "library", "mod", "nil", "not", "object", "of", "operator", "or", "out", "packed", "procedure", "program", "property", "raise", "record", "repeat", "resourcestring", "set", "shl", "shr", "then", "threadvar", "to", "try", "type", "unit", "until", "uses", "var", "while", "with", "xor"])
        case .D:                          .addWords(["abstract", "alias", "align", "asm", "assert", "auto", "body", "bool", "break", "byte", "case", "cast", "catch", "class", "const", "continue", "debug", "default", "delegate", "delete", "deprecated", "do", "else", "enum", "export", "extern", "false", "final", "finally", "for", "foreach", "foreach_reverse", "function", "goto", "if", "immutable", "import", "in", "inout", "interface", "invariant", "is", "lazy", "mixin", "module", "new", "nothrow", "null", "out", "override", "package", "pragma", "private", "protected", "public", "pure", "ref", "return", "scope", "shared", "static", "struct", "super", "switch", "synchronized", "template", "this", "throw", "traits", "true", "try", "typedef", "typeid", "typeof", "union", "unittest", "version", "void", "while", "with"])
        case .ObjectiveC:                 .addWords(["auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long", "register", "restrict", "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned", "void", "volatile", "while", "@autoreleasepool", "@catch", "@class", "@dynamic", "@encode", "@end", "@finally", "@implementation", "@interface", "@optional", "@package", "@private", "@property", "@protected", "@protocol", "@public", "@required", "@selector", "@synchronized", "@synthesize", "@throw", "@try"])
        case .Matlab:                     .addWords(["break", "case", "catch", "classdef", "continue", "else", "elseif", "end", "enumeration", "events", "for", "function", "global", "if", "methods", "otherwise", "parfor", "persistent", "properties", "return", "spmd", "switch", "try", "while"])
        case .Tcl:                        .addWords(["after", "append", "apply", "array", "break", "catch", "concat", "continue", "dict", "else", "elseif", "error", "eval", "expr", "for", "foreach", "format", "global", "if", "incr", "info", "lappend", "lassign", "lindex", "linsert", "list", "llength", "lmap", "proc", "rename", "return", "set", "source", "string", "switch", "unset", "upvar", "variable", "while"])
        case .Awk:                        .addWords(["BEGIN", "END", "break", "continue", "delete", "do", "else", "exit", "for", "function", "getline", "if", "in", "next", "nextfile", "print", "printf", "return", "while"])
        case .Vim:                        .addWords(["autocmd", "break", "call", "catch", "command", "continue", "else", "elseif", "endfor", "endfunction", "endif", "endtry", "endwhile", "execute", "finish", "for", "function", "if", "let", "return", "set", "silent", "throw", "try", "while"])
        case .Latex:                      .addWords(["\\begin", "\\chapter", "\\documentclass", "\\else", "\\end", "\\fi", "\\if", "\\include", "\\input", "\\label", "\\newcommand", "\\paragraph", "\\ref", "\\renewcommand", "\\section", "\\subsection", "\\subsubsection", "\\usepackage"])
        case .Protobuf:                   .addWords(["bool", "bytes", "double", "enum", "extend", "extensions", "fixed32", "fixed64", "float", "group", "import", "int32", "int64", "map", "message", "oneof", "option", "optional", "package", "public", "repeated", "required", "reserved", "returns", "rpc", "service", "sfixed32", "sfixed64", "sint32", "sint64", "stream", "string", "syntax", "to", "uint32", "uint64", "weak"])
        case .GraphQl:                    .addWords(["directive", "enum", "extend", "fragment", "implements", "input", "interface", "mutation", "null", "on", "query", "repeatable", "scalar", "schema", "subscription", "true", "type", "union"])
        case .Makefile:                   .addWords(["define", "else", "endef", "endif", "export", "if", "ifdef", "ifeq", "ifndef", "ifneq", "include", "override", "private", "sinclude", "undefine", "unexport", "vpath"])
        case .Dockerfile:                 .addWords(["add", "arg", "cmd", "copy", "entrypoint", "env", "expose", "from", "healthcheck", "label", "maintainer", "onbuild", "run", "shell", "stopsignal", "user", "volume", "workdir"])
        case .Nix:                        .addWords(["assert", "else", "false", "if", "in", "inherit", "let", "null", "or", "rec", "then", "true", "with"])
        case .Xml, .Html:                 return
        }
    }

    mtd isHashComment()->bool
    {
        switch .language
        {
        case .Python, .Ruby, .Shell, .PowerShell, .Perl, .R, .Yaml, .Toml, .Config, .CMake, .Nim, .Elixir, .Julia, .Tcl, .Awk, .GraphQl, .Makefile, .Dockerfile, .Nix: return true
        default: return false
        }
    }

    mtd isDashComment()->bool      => .language == .Sql or .language == .Lua or .language == .Haskell
    mtd isSemicolonComment()->bool => .language == .Assembly or .language == .Clojure
    mtd isPercentComment()->bool   => .language == .Erlang or .language == .Matlab or .language == .Latex
    mtd isBangComment()->bool      => .language == .Fortran
    mtd isQuoteComment()->bool     => .language == .Vim

    mtd isSlashComment()->bool
    {
        switch .language
        {
        case .Python, .Ruby, .Shell, .PowerShell, .Perl, .R, .Sql, .Lua, .Yaml, .Toml, .Config, .CMake, .Batch, .VisualBasic, .Xml, .Html, .Assembly, .Nim, .Haskell, .Elixir, .Erlang, .Clojure, .Julia, .Fortran, .Matlab, .Tcl, .Awk, .Vim, .Latex, .GraphQl, .Makefile, .Dockerfile, .Nix: return false
        default: return true
        }
    }

    mtd isCaseInsensitive()->bool => .language == .Sql or .language == .VisualBasic or .language == .Batch or .language == .Assembly or .language == .Fortran or .language == .Pascal or .language == .Matlab or .language == .Dockerfile
    mtd hasBlockComment()->bool   => .isSlashComment() or .language == .Sql or .language == .Css or .language == .Nix
    mtd hasBacktickString()->bool => .language == .JavaScript or .language == .TypeScript or .language == .Shell or .language == .PowerShell
    mtd hasPreprocessor()->bool   => .language == .C or .language == .Cpp or .language == .CSharp or .language == .Shader or .language == .ObjectiveC
    mtd hasDataKeys()->bool       => .language == .Json or .language == .Yaml or .language == .Toml or .language == .Config or .language == .Css or .language == .GraphQl
}

private func codePaint(line: *RichEditLine, first, last: u64, style: GenericCodeLexer.Style)
{
    for index in first until Math.min(last, line.length()) do
        line.setStyleAt(index, cast(RichEditStyleRef) style)
}

private func codeMatches(line: *RichEditLine, at: u64, text: string)->bool
{
    if at + @countof(text) > line.length() do
        return false
    for value, offset in text
    {
        if line.runeAt(at + offset) != value do
            return false
    }

    return true
}

private func codeIdentifierStart(value: rune)->bool => Unicode.isLetter(value) or value == '_' or value == '$' or value == '@' or value == '\\'
private func codeIdentifier(value: rune)->bool => Unicode.isLetterOrDigit(value) or value == '_' or value == '$' or value == '@' or value == '\\'

internal impl IRichEditLexer for GenericCodeLexer
{
    mtd impl setup(ed: *RichEditCtrl)
    {
        discard ed
    }

    mtd impl setupTheme(ed: *RichEditCtrl)
    {
        let ground       = ed.themeColors().richEdit_Bk
        var comment      = Color.fromArgb(0xFF6A9955)
        var keyword      = Color.fromArgb(0xFF569CD6)
        var type         = Color.fromArgb(0xFF4EC9B0)
        var stringColor  = Color.fromArgb(0xFFCE9178)
        var number       = Color.fromArgb(0xFFB5CEA8)
        var function     = Color.fromArgb(0xFFDCDCAA)
        var preprocessor = Color.fromArgb(0xFFC586C0)
        comment.ensureContrast(ground, 4.5)
        keyword.ensureContrast(ground, 4.5)
        type.ensureContrast(ground, 4.5)
        stringColor.ensureContrast(ground, 4.5)
        number.ensureContrast(ground, 4.5)
        function.ensureContrast(ground, 4.5)
        preprocessor.ensureContrast(ground, 4.5)
        ed.styles[cast(u64) Style.Comment].colFg      = comment
        ed.styles[cast(u64) Style.Keyword].colFg      = keyword
        ed.styles[cast(u64) Style.Type].colFg         = type
        ed.styles[cast(u64) Style.String].colFg       = stringColor
        ed.styles[cast(u64) Style.Number].colFg       = number
        ed.styles[cast(u64) Style.Function].colFg     = function
        ed.styles[cast(u64) Style.Preprocessor].colFg = preprocessor
    }

    mtd impl insertRune(ed: *RichEditCtrl, ch: rune)->bool
    {
        discard ed
        discard ch
        return false
    }

    mtd impl compute(linePrev: #null *RichEditLine, line: *RichEditLine, lineNext: #null *RichEditLine)
    {
        let length = line.length()
        codePaint(line, 0, length, .Default)
        var state = linePrev ? cast(GenericCodeState) linePrev!.lexerState() : GenericCodeState.Default
        var seek  = 0'u64

        if .language == .Xml or .language == .Html
        {
            while seek < length
            {
                if state == .MarkupComment
                {
                    let first = seek
                    while seek < length and !codeMatches(line, seek, "-->") do
                        seek += 1
                    if seek < length
                    {
                        seek  += 3
                        state = .Default
                    }

                    codePaint(line, first, seek, .Comment)
                    continue
                }

                if codeMatches(line, seek, "<!--")
                {
                    state = .MarkupComment
                    continue
                }

                if line.runeAt(seek) == '<'
                {
                    let first = seek
                    seek += 1
                    while seek < length and line.runeAt(seek) != '>' do
                        seek += 1
                    if seek < length do
                        seek += 1
                    codePaint(line, first, seek, .Keyword)

                    var scan = first
                    while scan < seek
                    {
                        if line.runeAt(scan) != '"' and line.runeAt(scan) != '\''
                        {
                            scan += 1
                            continue
                        }

                        let quote       = line.runeAt(scan)
                        let stringFirst = scan
                        scan += 1
                        while scan < seek and line.runeAt(scan) != quote do
                            scan += 1
                        if scan < seek do
                            scan += 1
                        codePaint(line, stringFirst, scan, .String)
                    }

                    continue
                }

                seek += 1
            }
        }
        else
        {
            while seek < length
            {
                if state == .BlockComment
                {
                    let first = seek
                    while seek < length and !codeMatches(line, seek, "*/") do
                        seek += 1
                    if seek < length
                    {
                        seek  += 2
                        state = .Default
                    }

                    codePaint(line, first, seek, .Comment)
                    continue
                }

                let value = line.runeAt(seek)
                if (.isHashComment() and value == '#') or (.isDashComment() and codeMatches(line, seek, "--")) or (.isSemicolonComment() and value == ';') or (.isPercentComment() and value == '%') or (.isBangComment() and value == '!') or (.isQuoteComment() and value == '"') or (.language == .VisualBasic and value == '\'') or (.language == .Batch and codeMatches(line, seek, "rem ")) or (.isSlashComment() and codeMatches(line, seek, "//"))
                {
                    codePaint(line, seek, length, .Comment)
                    seek = length
                    continue
                }

                if .hasBlockComment() and codeMatches(line, seek, "/*")
                {
                    state = .BlockComment
                    continue
                }

                if value == '"' or value == '\'' or (value == '`' and .hasBacktickString())
                {
                    let quote = value
                    let first = seek
                    seek += 1
                    while seek < length
                    {
                        if line.runeAt(seek) == '\\'
                        {
                            seek = Math.min(seek + 2, length)
                            continue
                        }

                        if line.runeAt(seek) == quote
                        {
                            seek += 1
                            break
                        }

                        seek += 1
                    }

                    codePaint(line, first, seek, .String)
                    continue
                }

                if Unicode.isNumber(value)
                {
                    let first = seek
                    seek += 1
                    while seek < length and (Unicode.isLetterOrDigit(line.runeAt(seek)) or line.runeAt(seek) == '.' or line.runeAt(seek) == '_') do
                        seek += 1
                    codePaint(line, first, seek, .Number)
                    continue
                }

                if value == '#' and .hasPreprocessor()
                {
                    codePaint(line, seek, length, .Preprocessor)
                    seek = length
                    continue
                }

                if codeIdentifierStart(value)
                {
                    let first = seek
                    seek += 1
                    while seek < length and codeIdentifier(line.runeAt(seek)) do
                        seek += 1
                    var word: String
                    for index in first until seek do
                        word += line.runeAt(index)
                    if .isCaseInsensitive() do
                        word = word.toLower()
                    let found = .keywords.tryFind(word.toString())
                    if found do
                        codePaint(line, first, seek, .Keyword)
                    else
                    {
                        var next = seek
                        while next < length and Unicode.isSpace(line.runeAt(next)) do
                            next += 1
                        if next < length and line.runeAt(next) == '(' do
                            codePaint(line, first, seek, .Function)
                        elif Latin1.isUpper(cast(u8) value) do
                            codePaint(line, first, seek, .Type)
                        elif next < length and (line.runeAt(next) == ':' or line.runeAt(next) == '=') and .hasDataKeys() do
                            codePaint(line, first, seek, .Type)
                    }

                    continue
                }

                seek += 1
            }
        }

        if line.setLexerState(cast(s32) state) and lineNext do
            lineNext!.markStyleDirty()
    }
}
