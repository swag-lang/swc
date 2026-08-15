#global internal

using Core, Pixel, Gui

enum TextCodeLanguage
{
    None
    Cpp
    CSharp
    Java
    JavaScript
    TypeScript
    Python
    Rust
    Go
    Json
    Markup
    Css
    Sql
    Shell
    PowerShell
    Lua
    Ruby
    Php
    Assembly
    Batch
    Config
}

func textCodeLanguage(fileName: string)->TextCodeLanguage
{
    var extension = String.from(Path.extension(fileName) orelse "")
    extension = extension.toLower()
    switch extension.toString()
    {
    case ".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp": return .Cpp
    case ".cs": return .CSharp
    case ".java": return .Java
    case ".js", ".jsx": return .JavaScript
    case ".ts", ".tsx": return .TypeScript
    case ".py": return .Python
    case ".rs": return .Rust
    case ".go": return .Go
    case ".json": return .Json
    case ".xml", ".svg": return .Markup
    case ".css": return .Css
    case ".sql": return .Sql
    case ".bash", ".sh": return .Shell
    case ".ps1": return .PowerShell
    case ".lua": return .Lua
    case ".rb": return .Ruby
    case ".php": return .Php
    case ".asm": return .Assembly
    case ".bat": return .Batch
    case ".cfg", ".cmake", ".conf", ".ini", ".toml", ".yaml", ".yml": return .Config
    }
    return .None
}

struct TextCodeLexer
{
    enum Style: RichEditStyleRef
    {
        Default
        Comment
        Keyword
        Control
        Type
        String
        Numeric
        Function
        Preprocessor
        Property
    }

    language: TextCodeLanguage
    mapWords: HashTable'(string, Style)
}

impl TextCodeLexer
{
    func create(language: TextCodeLanguage)->TextCodeLexer
    {
        var result: retval
        result.language = language
        return result
    }

    private mtd addWords(words: string, style: Style)
    {
        for word in Tokenize.split(words, ' 'u8) do
            .mapWords.add(word, style)
    }

    private mtd setupWords()
    {
        .addWords("if else for while switch case default break continue return try catch throw do", .Control)
        .addWords("true false null nil none undefined this self super", .Keyword)

        switch .language
        {
        case .None: return
        case .Cpp:
            .addWords("alignas alignof asm auto class concept const constexpr consteval constinit decltype delete enum explicit export extern friend inline namespace new noexcept operator private protected public requires sizeof static struct template thread_local typedef typename union using virtual volatile", .Keyword)
            .addWords("bool char char8_t char16_t char32_t double float int long short signed unsigned void wchar_t", .Type)
        case .CSharp:
            .addWords("abstract as async await base checked class const delegate enum event explicit extern finally fixed foreach get implicit in interface internal is lock namespace new operator out override params private protected public readonly record ref sealed set sizeof stackalloc static struct switch this throw typeof unchecked unsafe using virtual volatile yield", .Keyword)
            .addWords("bool byte char decimal double dynamic float int long object sbyte short string uint ulong ushort void", .Type)
        case .Java:
            .addWords("abstract assert byte catch class const extends final finally import instanceof interface native new package private protected public static strictfp super synchronized throws transient volatile", .Keyword)
            .addWords("boolean byte char double float int long short void", .Type)
        case .JavaScript, .TypeScript:
            .addWords("async await class const debugger delete export extends finally function get import in instanceof let new of set static switch throw typeof var void with yield", .Keyword)
            if .language == .TypeScript do
                .addWords("abstract any as asserts bigint boolean declare enum implements infer interface keyof never number object private protected public readonly satisfies string symbol type unknown", .Type)
        case .Python:
            .addWords("and as assert async await class def del elif except finally from global import is lambda nonlocal not or pass raise try with yield", .Keyword)
        case .Rust:
            .addWords("as async await const crate dyn enum extern fn impl let loop match mod move mut pub ref static struct trait type unsafe use where", .Keyword)
            .addWords("bool char f32 f64 i8 i16 i32 i64 i128 isize str u8 u16 u32 u64 u128 usize", .Type)
        case .Go:
            .addWords("break case chan const defer fallthrough func go goto import interface map package range select struct type var", .Keyword)
            .addWords("bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr", .Type)
        case .Css: .addWords("important inherit initial revert unset", .Keyword)
        case .Sql: .addWords("alter as asc begin by create delete desc distinct drop end exists from full group having inner insert into join left limit on order outer right select set table union update values where", .Keyword)
        case .Shell: .addWords("case done elif esac export fi function in local readonly select then time until", .Keyword)
        case .PowerShell: .addWords("begin class data dynamicparam end filter foreach from function in param process switch trap using workflow", .Keyword)
        case .Lua: .addWords("and do elseif end function goto local not or repeat then until", .Keyword)
        case .Ruby: .addWords("alias begin class def defined do elsif end ensure module next redo rescue retry then undef unless until when yield", .Keyword)
        case .Php: .addWords("abstract callable class clone const declare echo elseif empty enddeclare endfor endforeach endif endswitch endwhile eval exit extends final finally function global goto implements include include_once instanceof interface namespace new private protected public require require_once static trait unset use var yield", .Keyword)
        case .Assembly: .addWords("section segment global extern proc endp", .Keyword)
        case .Batch: .addWords("call echo else endlocal for goto if in not pause rem set setlocal shift start", .Keyword)
        }
    }

    private func syntaxColor(argb: u32, ground: Color)->Color
    {
        var result = Color.fromArgb(argb)
        result.ensureContrast(ground, 4.5)
        return result
    }
}

impl IRichEditLexer for TextCodeLexer
{
    mtd impl setup(ed: *RichEditCtrl)
    {
        discard ed
        .setupWords()
    }

    mtd impl setupTheme(ed: *RichEditCtrl)
    {
        using TextCodeLexer.Style
        let ground = ed.themeColors().richEdit_Bk
        ed.styles[cast(u64) Comment].colFg      = syntaxColor(0xFF6A9955, ground)
        ed.styles[cast(u64) Keyword].colFg      = syntaxColor(0xFF569CD6, ground)
        ed.styles[cast(u64) Control].colFg      = syntaxColor(0xFFD8A0DF, ground)
        ed.styles[cast(u64) Type].colFg         = syntaxColor(0xFF4EC9B0, ground)
        ed.styles[cast(u64) String].colFg       = syntaxColor(0xFFCE9178, ground)
        ed.styles[cast(u64) Numeric].colFg      = syntaxColor(0xFFB5CEA8, ground)
        ed.styles[cast(u64) Function].colFg     = syntaxColor(0xFFFFB454, ground)
        ed.styles[cast(u64) Preprocessor].colFg = syntaxColor(0xFFC586C0, ground)
        ed.styles[cast(u64) Property].colFg     = syntaxColor(0xFF9CDCFE, ground)
    }

    mtd impl insertRune(ed: *RichEditCtrl, ch: rune)->bool
    {
        discard ed
        discard ch
        return false
    }

    mtd impl compute(linePrev: #null *RichEditLine, line: *RichEditLine, lineNext: #null *RichEditLine)
    {
        var seek         = 0'u64
        var blockComment = linePrev ? linePrev.lexerState() != 0 : false
        var inMarkupTag: bool

        #[Swag.Mixin]
        func current()->rune => seek < line.length() ? line.runeAt(seek) : 0

        #[Swag.Mixin]
        func next()->rune => seek + 1 < line.length() ? line.runeAt(seek + 1) : 0

        #[Swag.Mixin]
        mtd take(style: Style)
        {
            if seek >= line.length() do
                return
            line.setStyleAt(seek, cast(RichEditStyleRef) style)
            seek += 1
        }

        #[Swag.Mixin]
        mtd takeLine(style: Style)
        {
            while seek < line.length() do
                .take(style)
        }

        while seek < line.length()
        {
            let c = current()
            let n = next()

            if blockComment
            {
                .take(.Comment)
                if c == '*' and n == '/'
                {
                    .take(.Comment)
                    blockComment = false
                }
                continue
            }

            if c == '/' and n == '*'
            {
                blockComment = true
                .take(.Comment)
                .take(.Comment)
                continue
            }

            let hashComment      = c == '#' and (.language == .Python or .language == .Shell or .language == .Ruby or .language == .Config)
            let dashComment      = c == '-' and n == '-' and (.language == .Sql or .language == .Lua)
            let slashComment     = c == '/' and n == '/' and .language != .Json
            let semicolonComment = c == ';' and .language == .Assembly
            let batchComment     = seek == 0 and .language == .Batch and line.length() >= 3 and Unicode.toLower(line.runeAt(0)) == 'r' and Unicode.toLower(line.runeAt(1)) == 'e' and Unicode.toLower(line.runeAt(2)) == 'm'
            if hashComment or dashComment or slashComment or semicolonComment or batchComment
            {
                .takeLine(.Comment)
                continue
            }

            if c == '#' and (.language == .Cpp or .language == .CSharp)
            {
                .takeLine(.Preprocessor)
                continue
            }

            if c == '"' or c == '\'' or c == '`'
            {
                let quote = c
                let begin = seek
                .take(.String)
                while seek < line.length()
                {
                    let item = current()
                    .take(.String)
                    if item == '\\' and seek < line.length() do
                        .take(.String)
                    elif item == quote do
                        break
                }

                var look = seek
                while look < line.length() and Unicode.isSpace(line.runeAt(look)) do
                    look += 1
                if look < line.length() and line.runeAt(look) == ':' and (.language == .Json or .language == .Config)
                {
                    for i in begin until seek do
                        line.setStyleAt(i, cast(RichEditStyleRef) Style.Property)
                }
                continue
            }

            if Unicode.isNumber(c)
            {
                while Unicode.isLetterOrDigit(current()) or current() == '.' or current() == '_' do
                    .take(.Numeric)
                continue
            }

            if Unicode.isLetter(c) or c == '_' or c == '$'
            {
                var word: String
                let begin = seek
                while Unicode.isLetterOrDigit(current()) or current() == '_' or current() == '$'
                {
                    word += current()
                    seek += 1
                }

                var lookup = String.from(word.toString())
                if .language == .Sql or .language == .Batch do
                    lookup = lookup.toLower()
                var style = Style.Default
                let known = .mapWords.tryFind(lookup.toString())
                if known do
                    style = known.value
                elif .language == .Markup and begin and (line.runeAt(begin - 1) == '<' or (begin > 1 and line.runeAt(begin - 1) == '/' and line.runeAt(begin - 2) == '<')) do
                    style = .Type
                elif .language == .Markup and inMarkupTag do
                    style = .Property
                else
                {
                    var look = seek
                    while look < line.length() and Unicode.isSpace(line.runeAt(look)) do
                        look += 1
                    if look < line.length() and line.runeAt(look) == '(' do
                        style = .Function
                    elif look < line.length() and (line.runeAt(look) == ':' or line.runeAt(look) == '=') and (.language == .Config or .language == .Css) do
                        style = .Property
                }

                for i in begin until seek do
                    line.setStyleAt(i, cast(RichEditStyleRef) style)
                continue
            }

            if .language == .Markup and (c == '<' or c == '>' or c == '/' or c == '=')
            {
                if c == '<' do
                    inMarkupTag = true
                elif c == '>' do
                    inMarkupTag = false
                .take(.Preprocessor)
            }
            else do
                .take(.Default)
        }

        let endingState = blockComment ? 1 : 0
        if line.setLexerState(endingState)
        {
            if lineNext do
                lineNext.markStyleDirty()
        }
    }
}
