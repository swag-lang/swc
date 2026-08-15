#global public

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
}

internal func codeLanguage(fileName: string)->CodeLanguage
{
    let extension = Path.lowercaseExtension(fileName)
    switch extension.toString()
    {
    case ".c", ".h":                                  return .C
    case ".cc", ".cpp", ".cxx", ".hh", ".hpp", ".hxx", ".inl", ".ipp": return .Cpp
    case ".cs":                                         return .CSharp
    case ".java":                                       return .Java
    case ".js", ".jsx", ".mjs", ".cjs":             return .JavaScript
    case ".ts", ".tsx", ".mts", ".cts":             return .TypeScript
    case ".go":                                         return .Go
    case ".rs":                                         return .Rust
    case ".py", ".pyw", ".pyi":                      return .Python
    case ".rb", ".rake", ".gemspec":                 return .Ruby
    case ".sh", ".bash", ".zsh", ".fish":           return .Shell
    case ".ps1", ".psm1", ".psd1":                  return .PowerShell
    case ".php", ".phtml":                            return .Php
    case ".lua":                                        return .Lua
    case ".sql":                                        return .Sql
    case ".json", ".jsonc", ".json5":                return .Json
    case ".xml", ".xsd", ".xsl", ".xslt", ".csproj", ".vcxproj", ".props", ".targets": return .Xml
    case ".css", ".scss", ".sass", ".less":         return .Css
    case ".yaml", ".yml":                             return .Yaml
    case ".toml":                                       return .Toml
    case ".ini", ".cfg", ".conf", ".properties":   return .Config
    case ".kt", ".kts":                               return .Kotlin
    case ".swift":                                      return .Swift
    case ".dart":                                       return .Dart
    case ".r":                                          return .R
    case ".pl", ".pm":                                return .Perl
    case ".vb":                                         return .VisualBasic
    case ".glsl", ".vert", ".frag", ".geom", ".comp", ".hlsl", ".fx": return .Shader
    case ".cmake":                                      return .CMake
    case ".bat", ".cmd":                              return .Batch
    }

    return .C
}

internal func codeLanguageName(language: CodeLanguage)->string
{
    switch language
    {
    case .C:          return "C"
    case .Cpp:        return "C++"
    case .CSharp:     return "C#"
    case .Java:       return "Java"
    case .JavaScript: return "JavaScript"
    case .TypeScript: return "TypeScript"
    case .Go:         return "Go"
    case .Rust:       return "Rust"
    case .Python:     return "Python"
    case .Ruby:       return "Ruby"
    case .Shell:      return "Shell"
    case .PowerShell: return "PowerShell"
    case .Php:        return "PHP"
    case .Lua:        return "Lua"
    case .Sql:        return "SQL"
    case .Json:       return "JSON"
    case .Xml:        return "XML"
    case .Css:        return "CSS"
    case .Yaml:       return "YAML"
    case .Toml:       return "TOML"
    case .Config:     return "Configuration"
    case .Kotlin:     return "Kotlin"
    case .Swift:      return "Swift"
    case .Dart:       return "Dart"
    case .R:          return "R"
    case .Perl:       return "Perl"
    case .VisualBasic:return "Visual Basic"
    case .Shader:     return "Shader"
    case .CMake:      return "CMake"
    case .Batch:      return "Batch"
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
        case .C, .Cpp, .Shader:
            .addWords(["auto", "break", "case", "char", "const", "continue", "default", "do", "double", "else", "enum", "extern", "float", "for", "goto", "if", "inline", "int", "long", "register", "restrict", "return", "short", "signed", "sizeof", "static", "struct", "switch", "typedef", "union", "unsigned", "void", "volatile", "while", "bool", "class", "namespace", "new", "delete", "public", "private", "protected", "template", "typename", "using", "virtual", "override", "constexpr", "nullptr", "this", "throw", "try", "catch"])
        case .CSharp:
            .addWords(["abstract", "as", "async", "await", "base", "bool", "break", "case", "catch", "class", "const", "continue", "decimal", "default", "delegate", "do", "else", "enum", "event", "explicit", "extern", "false", "finally", "fixed", "for", "foreach", "get", "if", "implicit", "in", "interface", "internal", "is", "lock", "namespace", "new", "null", "operator", "out", "override", "params", "private", "protected", "public", "readonly", "record", "ref", "return", "sealed", "set", "static", "string", "struct", "switch", "this", "throw", "true", "try", "typeof", "using", "var", "virtual", "void", "while", "yield"])
        case .Java, .Kotlin:
            .addWords(["abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class", "const", "continue", "default", "do", "double", "else", "enum", "extends", "false", "final", "finally", "float", "for", "fun", "if", "implements", "import", "in", "instanceof", "int", "interface", "internal", "is", "long", "native", "new", "null", "object", "open", "override", "package", "private", "protected", "public", "return", "sealed", "short", "static", "super", "synchronized", "this", "throw", "throws", "transient", "true", "try", "val", "var", "void", "volatile", "when", "while"])
        case .JavaScript, .TypeScript:
            .addWords(["async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for", "from", "function", "get", "if", "implements", "import", "in", "instanceof", "interface", "let", "new", "null", "of", "private", "protected", "public", "return", "set", "static", "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "var", "void", "while", "with", "yield"])
        case .Go:
            .addWords(["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "false", "for", "func", "go", "goto", "if", "import", "interface", "map", "nil", "package", "range", "return", "select", "struct", "switch", "true", "type", "var"])
        case .Rust:
            .addWords(["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while"])
        case .Python:
            .addWords(["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except", "False", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "None", "nonlocal", "not", "or", "pass", "raise", "return", "True", "try", "while", "with", "yield"])
        case .Ruby:
            .addWords(["alias", "and", "begin", "break", "case", "class", "def", "defined", "do", "else", "elsif", "end", "ensure", "false", "for", "if", "in", "module", "next", "nil", "not", "or", "redo", "rescue", "retry", "return", "self", "super", "then", "true", "undef", "unless", "until", "when", "while", "yield"])
        case .Shell, .PowerShell, .Batch:
            .addWords(["begin", "break", "case", "catch", "continue", "do", "done", "elif", "else", "end", "esac", "exit", "fi", "finally", "for", "foreach", "function", "if", "in", "param", "return", "select", "switch", "then", "throw", "trap", "try", "until", "while"])
        case .Php:
            .addWords(["abstract", "and", "array", "as", "break", "callable", "case", "catch", "class", "clone", "const", "continue", "declare", "default", "do", "echo", "else", "elseif", "empty", "endfor", "endforeach", "endif", "endswitch", "endwhile", "enum", "extends", "false", "final", "finally", "fn", "for", "foreach", "function", "global", "if", "implements", "include", "instanceof", "interface", "match", "namespace", "new", "null", "private", "protected", "public", "readonly", "require", "return", "static", "throw", "trait", "true", "try", "use", "var", "while", "yield"])
        case .Lua:
            .addWords(["and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"])
        case .Sql:
            .addWords(["add", "alter", "and", "as", "asc", "begin", "between", "by", "case", "column", "commit", "constraint", "create", "database", "default", "delete", "desc", "distinct", "drop", "else", "end", "exists", "false", "foreign", "from", "full", "group", "having", "in", "index", "inner", "insert", "into", "is", "join", "key", "left", "like", "limit", "not", "null", "on", "or", "order", "outer", "primary", "references", "right", "rollback", "select", "set", "table", "then", "true", "union", "unique", "update", "values", "view", "when", "where", "with"])
        case .Json:
            .addWords(["false", "null", "true"])
        case .Css:
            .addWords(["@charset", "@container", "@font-face", "@import", "@keyframes", "@layer", "@media", "@namespace", "@page", "@supports", "important"])
        case .Yaml, .Toml, .Config:
            .addWords(["false", "inf", "nan", "null", "off", "on", "true", "yes", "no"])
        case .Swift:
            .addWords(["as", "associatedtype", "break", "case", "catch", "class", "continue", "default", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate", "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let", "nil", "open", "operator", "private", "protocol", "public", "repeat", "rethrows", "return", "self", "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias", "var", "where", "while"])
        case .Dart:
            .addWords(["abstract", "as", "assert", "async", "await", "break", "case", "catch", "class", "const", "continue", "default", "deferred", "do", "dynamic", "else", "enum", "export", "extends", "extension", "external", "factory", "false", "final", "finally", "for", "function", "get", "hide", "if", "implements", "import", "in", "interface", "is", "late", "library", "mixin", "new", "null", "on", "operator", "part", "required", "return", "set", "show", "static", "super", "switch", "sync", "this", "throw", "true", "try", "typedef", "var", "void", "while", "with", "yield"])
        case .R:
            .addWords(["break", "else", "FALSE", "for", "function", "if", "Inf", "NA", "NaN", "next", "NULL", "repeat", "return", "TRUE", "while"])
        case .Perl:
            .addWords(["continue", "do", "else", "elsif", "for", "foreach", "given", "goto", "if", "last", "local", "my", "next", "no", "package", "redo", "require", "return", "state", "sub", "unless", "until", "use", "when", "while"])
        case .VisualBasic:
            .addWords(["as", "async", "await", "boolean", "byref", "byval", "case", "catch", "class", "const", "continue", "dim", "do", "each", "else", "elseif", "end", "enum", "false", "finally", "for", "function", "get", "handles", "if", "implements", "imports", "in", "inherits", "interface", "module", "new", "nothing", "of", "private", "property", "protected", "public", "return", "select", "set", "shared", "static", "structure", "sub", "then", "throw", "true", "try", "while", "with"])
        case .CMake:
            .addWords(["break", "cmake_minimum_required", "continue", "else", "elseif", "endforeach", "endfunction", "endif", "endmacro", "endwhile", "find_package", "foreach", "function", "if", "include", "macro", "project", "return", "set", "target_compile_definitions", "target_include_directories", "target_link_libraries", "while"])
        case .Xml:
            return
        }
    }

    mtd isHashComment()->bool
    {
        switch .language
        {
        case .Python, .Ruby, .Shell, .PowerShell, .Perl, .R, .Yaml, .Toml, .Config, .CMake: return true
        default: return false
        }
    }

    mtd isDashComment()->bool => .language == .Sql or .language == .Lua

    mtd isSlashComment()->bool
    {
        switch .language
        {
        case .Python, .Ruby, .Shell, .PowerShell, .Perl, .R, .Sql, .Lua, .Yaml, .Toml, .Config, .CMake, .Batch, .VisualBasic, .Xml: return false
        default: return true
        }
    }

    mtd isCaseInsensitive()->bool => .language == .Sql or .language == .VisualBasic or .language == .Batch
    mtd hasBlockComment()->bool => .isSlashComment() or .language == .Sql or .language == .Css
    mtd hasBacktickString()->bool => .language == .JavaScript or .language == .TypeScript or .language == .Shell or .language == .PowerShell
    mtd hasPreprocessor()->bool => .language == .C or .language == .Cpp or .language == .CSharp or .language == .Shader
    mtd hasDataKeys()->bool => .language == .Json or .language == .Yaml or .language == .Toml or .language == .Config or .language == .Css
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

private func codeIdentifierStart(value: rune)->bool => Unicode.isLetter(value) or value == '_' or value == '$' or value == '@'
private func codeIdentifier(value: rune)->bool => Unicode.isLetterOrDigit(value) or value == '_' or value == '$' or value == '@'

internal impl IRichEditLexer for GenericCodeLexer
{
    mtd impl setup(ed: *RichEditCtrl)
    {
        discard ed
    }

    mtd impl setupTheme(ed: *RichEditCtrl)
    {
        let ground = ed.themeColors().richEdit_Bk
        var comment = Color.fromArgb(0xFF6A9955)
        var keyword = Color.fromArgb(0xFF569CD6)
        var type    = Color.fromArgb(0xFF4EC9B0)
        var stringColor = Color.fromArgb(0xFFCE9178)
        var number  = Color.fromArgb(0xFFB5CEA8)
        var function = Color.fromArgb(0xFFDCDCAA)
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

        if .language == .Xml
        {
            while seek < length
            {
                if state == .MarkupComment
                {
                    let first = seek
                    while seek < length and !codeMatches(line, seek, "-->") do seek += 1
                    if seek < length
                    {
                        seek += 3
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
                    if seek < length do seek += 1
                    codePaint(line, first, seek, .Keyword)

                    var scan = first
                    while scan < seek
                    {
                        if line.runeAt(scan) != '"' and line.runeAt(scan) != '\''
                        {
                            scan += 1
                            continue
                        }
                        let quote = line.runeAt(scan)
                        let stringFirst = scan
                        scan += 1
                        while scan < seek and line.runeAt(scan) != quote do scan += 1
                        if scan < seek do scan += 1
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
                    while seek < length and !codeMatches(line, seek, "*/") do seek += 1
                    if seek < length
                    {
                        seek += 2
                        state = .Default
                    }
                    codePaint(line, first, seek, .Comment)
                    continue
                }

                let value = line.runeAt(seek)
                if (.isHashComment() and value == '#') or (.isDashComment() and codeMatches(line, seek, "--")) or (.language == .VisualBasic and value == '\'') or (.language == .Batch and codeMatches(line, seek, "rem ")) or (.isSlashComment() and codeMatches(line, seek, "//"))
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
                    while seek < length and (Unicode.isLetterOrDigit(line.runeAt(seek)) or line.runeAt(seek) == '.' or line.runeAt(seek) == '_') do seek += 1
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
                    while seek < length and codeIdentifier(line.runeAt(seek)) do seek += 1
                    var word: String
                    for index in first until seek do
                        word += line.runeAt(index)
                    if .isCaseInsensitive() do word = word.toLower()
                    let found = .keywords.tryFind(word.toString())
                    if found do
                        codePaint(line, first, seek, .Keyword)
                    else
                    {
                        var next = seek
                        while next < length and Unicode.isSpace(line.runeAt(next)) do next += 1
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
