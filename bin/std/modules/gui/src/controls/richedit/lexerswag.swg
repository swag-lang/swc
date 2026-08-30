#global public

using Core, Pixel

// Provides syntax highlighting for Swag source code.
struct RichEditLexerSwag
{
    public
    {
        #[Swag.Incomplete]
        // Identifies a syntax style emitted by the Swag lexer.
        enum Style: RichEditStyleRef
        {
            Default          // Selects default.
            Comment          // Selects comment.
            Keyword          // Selects keyword.
            Control          // Selects control.
            Intrinsic        // Selects intrinsic.
            Builtin          // Compiler builtin functions such as `Swag.sqrt` and `Swag.memcpy`.
            Function         // Selects function.
            Preprocessor     // Selects preprocessor.
            CharEscape       // Selects char escape.
            Type             // Selects type.
            Class            // Selects class.
            String           // Selects string.
            Character        // Selects character.
            Numeric          // Selects numeric.
            Error            // Selects error.
            Namespace        // Selects the built-in `Swag` namespace.
        }
    }

    #[Swag.Incomplete]
    // Identifies the lexical state carried between lines.
    enum State: s32
    {
        Default               // Selects default.
        LineComment           // Selects line comment.
        Comment               // Selects comment.
        Keyword               // Selects keyword.
        Declaration           // Selects declaration.
        Control               // Selects control.
        Intrinsic             // Selects intrinsic.
        Namespace             // Built-in `Swag` namespace.
        Builtin               // Compiler builtin function.
        Compiler              // Selects compiler.
        CompilerFunction      // Selects compiler function.
        CompilerGlobal        // Selects compiler global.
        CompilerStatement     // Selects compiler statement.
        Modifier              // Selects modifier.
        FunctionCall          // Selects function call.
        FunctionSpecOp        // Selects function spec op.
        Type                  // Selects type.
        StorageModifier       // Selects storage modifier.
        UserType              // Selects user type.
        Constant              // Selects constant.
        String                // Selects string.
        RawString             // Selects raw string.
        Character             // Selects character.
        Numeric               // Selects numeric.
        NumericHex            // Selects numeric hex.
        NumericBin            // Selects numeric bin.
        NumericFrac           // Selects numeric frac.
        Attribute             // Selects attribute.
        Error                 // Selects error.
    }

    mapStyles: [State] Style

    mapWords: HashTable'(string, State)
}

impl IRichEditLexer for RichEditLexerSwag
{
    mtd impl setup(ed: *RichEditCtrl)
    {
        using RichEditLexerSwag.Style
        .mapStyles[State.LineComment]       = Comment
        .mapStyles[State.Comment]           = Comment
        .mapStyles[State.Keyword]           = Keyword
        .mapStyles[State.Control]           = Control
        .mapStyles[State.Declaration]       = Keyword
        .mapStyles[State.Intrinsic]         = Intrinsic
        .mapStyles[State.Namespace]         = Namespace
        .mapStyles[State.Builtin]           = Builtin
        .mapStyles[State.CompilerFunction]  = Function
        .mapStyles[State.CompilerGlobal]    = Preprocessor
        .mapStyles[State.CompilerStatement] = Preprocessor
        .mapStyles[State.Compiler]          = CharEscape
        .mapStyles[State.Modifier]          = Keyword
        .mapStyles[State.FunctionSpecOp]    = Intrinsic
        .mapStyles[State.Type]              = Type
        .mapStyles[State.StorageModifier]   = Keyword
        .mapStyles[State.UserType]          = Class
        .mapStyles[State.FunctionCall]      = Function
        .mapStyles[State.Constant]          = Keyword
        .mapStyles[State.String]            = String
        .mapStyles[State.RawString]         = String
        .mapStyles[State.Character]         = Character
        .mapStyles[State.Numeric]           = Numeric
        .mapStyles[State.NumericFrac]       = Numeric
        .mapStyles[State.NumericHex]        = Numeric
        .mapStyles[State.NumericBin]        = Numeric
        .mapStyles[State.Attribute]         = Preprocessor
        .mapStyles[State.Error]             = Error

        .mapWords.add("if", State.Control)
        .mapWords.add("else", State.Control)
        .mapWords.add("elif", State.Control)
        .mapWords.add("for", State.Control)
        .mapWords.add("while", State.Control)
        .mapWords.add("switch", State.Control)
        .mapWords.add("defer", State.Control)
        .mapWords.add("do", State.Control)
        .mapWords.add("where", State.Control)
        .mapWords.add("break", State.Control)
        .mapWords.add("fallthrough", State.Control)
        .mapWords.add("unreachable", State.Control)
        .mapWords.add("return", State.Control)
        .mapWords.add("case", State.Control)
        .mapWords.add("continue", State.Control)
        .mapWords.add("default", State.Control)
        .mapWords.add("and", State.Control)
        .mapWords.add("or", State.Control)
        .mapWords.add("orelse", State.Control)
        .mapWords.add("to", State.Control)
        .mapWords.add("until", State.Control)
        .mapWords.add("in", State.Control)
        .mapWords.add("as", State.Control)
        .mapWords.add("is", State.Control)

        .mapWords.add("export", State.Keyword)
        .mapWords.add("generated", State.Keyword)
        .mapWords.add("location", State.Keyword)
        .mapWords.add("link", State.Keyword)
        .mapWords.add("version", State.Keyword)

        .mapWords.add("using", State.Keyword)
        .mapWords.add("with", State.Keyword)
        .mapWords.add("cast", State.Keyword)
        .mapWords.add("retval", State.Keyword)
        .mapWords.add("try", State.Keyword)
        .mapWords.add("catch", State.Keyword)
        .mapWords.add("expect", State.Keyword)
        .mapWords.add("fail", State.Keyword)
        .mapWords.add("discard", State.Keyword)

        .mapWords.add("enum", State.Declaration)
        .mapWords.add("struct", State.Declaration)
        .mapWords.add("union", State.Declaration)
        .mapWords.add("impl", State.Declaration)
        .mapWords.add("interface", State.Declaration)
        .mapWords.add("func", State.Declaration)
        .mapWords.add("mtd", State.Declaration)
        .mapWords.add("namespace", State.Declaration)
        .mapWords.add("alias", State.Declaration)
        .mapWords.add("attr", State.Declaration)

        .mapWords.add("let", State.Declaration)
        .mapWords.add("var", State.Declaration)
        .mapWords.add("const", State.Declaration)

        .mapWords.add("public", State.StorageModifier)
        .mapWords.add("private", State.StorageModifier)
        .mapWords.add("internal", State.StorageModifier)
        .mapWords.add("readonly", State.StorageModifier)

        .mapWords.add("true", State.Constant)
        .mapWords.add("false", State.Constant)
        .mapWords.add("null", State.Constant)
        .mapWords.add("undefined", State.Constant)

        .mapWords.add("not", State.Error)
        .mapWords.add("foreach", State.Error)

        .mapWords.add("#defined", State.Intrinsic)
        .mapWords.add("#offsetof", State.Intrinsic)
        .mapWords.add("#alignof", State.Intrinsic)
        .mapWords.add("#sizeof", State.Intrinsic)
        .mapWords.add("#typeof", State.Intrinsic)
        .mapWords.add("#kindof", State.Intrinsic)
        .mapWords.add("#stringof", State.Intrinsic)
        .mapWords.add("#nameof", State.Intrinsic)
        .mapWords.add("#fullnameof", State.Intrinsic)
        .mapWords.add("#isconstexpr", State.Intrinsic)
        .mapWords.add("#location", State.Intrinsic)
        .mapWords.add("#decltype", State.Intrinsic)
        .mapWords.add("#hastag", State.Intrinsic)
        .mapWords.add("#gettag", State.Intrinsic)
        .mapWords.add("#runes", State.Intrinsic)
        .mapWords.add("#safety", State.Intrinsic)
        .mapWords.add("#sanity", State.Intrinsic)
        .mapWords.add("Swag.isSet", State.Intrinsic)
        .mapWords.add("#include", State.Intrinsic)

        .mapWords.add("#uniq0", State.Intrinsic)
        .mapWords.add("#uniq1", State.Intrinsic)
        .mapWords.add("#uniq2", State.Intrinsic)
        .mapWords.add("#uniq3", State.Intrinsic)
        .mapWords.add("#uniq4", State.Intrinsic)
        .mapWords.add("#uniq5", State.Intrinsic)
        .mapWords.add("#uniq6", State.Intrinsic)
        .mapWords.add("#uniq7", State.Intrinsic)
        .mapWords.add("#uniq8", State.Intrinsic)
        .mapWords.add("#uniq9", State.Intrinsic)

        .mapWords.add("Swag.runtimeFlags", State.Intrinsic)
        .mapWords.add("Swag.args", State.Intrinsic)
        .mapWords.add("Swag.processInfos", State.Intrinsic)
        .mapWords.add("Swag.jit", State.Intrinsic)
        .mapWords.add("Swag.compiler", State.Intrinsic)
        .mapWords.add("Swag.modules", State.Intrinsic)
        .mapWords.add("Swag.gvtd", State.Intrinsic)
        .mapWords.add("Swag.index", State.Intrinsic)

        .mapWords.add("Swag.kindOf", State.Intrinsic)
        .mapWords.add("Swag.makeSlice", State.Intrinsic)
        .mapWords.add("Swag.makeString", State.Intrinsic)
        .mapWords.add("Swag.makeAny", State.Intrinsic)
        .mapWords.add("Swag.makeInterface", State.Intrinsic)
        .mapWords.add("Swag.stringCmp", State.Intrinsic)
        .mapWords.add("Swag.typeCmp", State.Intrinsic)
        .mapWords.add("Swag.typeIs", State.Intrinsic)
        .mapWords.add("Swag.typeAs", State.Intrinsic)
        .mapWords.add("Swag.getContext", State.Intrinsic)
        .mapWords.add("Swag.tableOf", State.Intrinsic)

        .mapWords.add("Swag.assert", State.Intrinsic)
        .mapWords.add("Swag.breakpoint", State.Intrinsic)
        .mapWords.add("Swag.init", State.Intrinsic)
        .mapWords.add("Swag.drop", State.Intrinsic)
        .mapWords.add("Swag.postCopy", State.Intrinsic)
        .mapWords.add("Swag.postMove", State.Intrinsic)
        .mapWords.add("Swag.compilerError", State.Intrinsic)
        .mapWords.add("Swag.compilerWarning", State.Intrinsic)
        .mapWords.add("Swag.panic", State.Intrinsic)
        .mapWords.add("Swag.safetyPanic", State.Intrinsic)
        .mapWords.add("Swag.print", State.Intrinsic)
        .mapWords.add("Swag.setContext", State.Intrinsic)

        .mapWords.add("opSlice", State.FunctionSpecOp)
        .mapWords.add("opBinary", State.FunctionSpecOp)
        .mapWords.add("opBinaryRight", State.FunctionSpecOp)
        .mapWords.add("opUnary", State.FunctionSpecOp)
        .mapWords.add("opAssign", State.FunctionSpecOp)
        .mapWords.add("opIndexAssign", State.FunctionSpecOp)
        .mapWords.add("opIndexSet", State.FunctionSpecOp)
        .mapWords.add("opCast", State.FunctionSpecOp)
        .mapWords.add("opCount", State.FunctionSpecOp)
        .mapWords.add("opData", State.FunctionSpecOp)
        .mapWords.add("opVisit", State.FunctionSpecOp)
        .mapWords.add("opInit", State.FunctionSpecOp)
        .mapWords.add("opReloc", State.FunctionSpecOp)
        .mapWords.add("opEquals", State.FunctionSpecOp)
        .mapWords.add("opCompare", State.FunctionSpecOp)
        .mapWords.add("opPostCopy", State.FunctionSpecOp)
        .mapWords.add("opPostMove", State.FunctionSpecOp)
        .mapWords.add("opDrop", State.FunctionSpecOp)
        .mapWords.add("opCount", State.FunctionSpecOp)
        .mapWords.add("opSet", State.FunctionSpecOp)
        .mapWords.add("opSetLiteral", State.FunctionSpecOp)
        .mapWords.add("opIndex", State.FunctionSpecOp)
        .mapWords.add("opIndexAssign", State.FunctionSpecOp)

        .mapWords.add("me", State.Type)

        .mapWords.add("any", State.Type)
        .mapWords.add("void", State.Type)
        .mapWords.add("rune", State.Type)
        .mapWords.add("f32", State.Type)
        .mapWords.add("f64", State.Type)
        .mapWords.add("s8", State.Type)
        .mapWords.add("s16", State.Type)
        .mapWords.add("s32", State.Type)
        .mapWords.add("s64", State.Type)
        .mapWords.add("u8", State.Type)
        .mapWords.add("u16", State.Type)
        .mapWords.add("u32", State.Type)
        .mapWords.add("u64", State.Type)
        .mapWords.add("bool", State.Type)
        .mapWords.add("string", State.Type)
        .mapWords.add("cstring", State.Type)
        .mapWords.add("typeinfo", State.Type)

        .mapWords.add("Swag.abs", State.Builtin)
        .mapWords.add("Swag.acos", State.Builtin)
        .mapWords.add("Swag.asin", State.Builtin)
        .mapWords.add("Swag.atan", State.Builtin)
        .mapWords.add("Swag.atan2", State.Builtin)
        .mapWords.add("Swag.atomadd", State.Builtin)
        .mapWords.add("Swag.atomand", State.Builtin)
        .mapWords.add("Swag.atomcmpxchg", State.Builtin)
        .mapWords.add("Swag.atomor", State.Builtin)
        .mapWords.add("Swag.atomxchg", State.Builtin)
        .mapWords.add("Swag.atomxor", State.Builtin)
        .mapWords.add("Swag.bitCountNz", State.Builtin)
        .mapWords.add("Swag.bitCountLz", State.Builtin)
        .mapWords.add("Swag.bitCountTz", State.Builtin)
        .mapWords.add("Swag.byteSwap", State.Builtin)
        .mapWords.add("Swag.ceil", State.Builtin)
        .mapWords.add("Swag.cos", State.Builtin)
        .mapWords.add("Swag.cosh", State.Builtin)
        .mapWords.add("Swag.exp", State.Builtin)
        .mapWords.add("Swag.exp2", State.Builtin)
        .mapWords.add("Swag.floor", State.Builtin)
        .mapWords.add("Swag.log", State.Builtin)
        .mapWords.add("Swag.log10", State.Builtin)
        .mapWords.add("Swag.log2", State.Builtin)
        .mapWords.add("Swag.max", State.Builtin)
        .mapWords.add("Swag.memcmp", State.Builtin)
        .mapWords.add("Swag.memcpy", State.Builtin)
        .mapWords.add("Swag.memmove", State.Builtin)
        .mapWords.add("Swag.memset", State.Builtin)
        .mapWords.add("Swag.min", State.Builtin)
        .mapWords.add("Swag.muladd", State.Builtin)
        .mapWords.add("Swag.pow", State.Builtin)
        .mapWords.add("Swag.rol", State.Builtin)
        .mapWords.add("Swag.ror", State.Builtin)
        .mapWords.add("Swag.round", State.Builtin)
        .mapWords.add("Swag.sin", State.Builtin)
        .mapWords.add("Swag.sinh", State.Builtin)
        .mapWords.add("Swag.sqrt", State.Builtin)
        .mapWords.add("Swag.tan", State.Builtin)
        .mapWords.add("Swag.tanh", State.Builtin)
        .mapWords.add("Swag.trunc", State.Builtin)
        .mapWords.add("Swag.vecalign", State.Builtin)
        .mapWords.add("Swag.vecall", State.Builtin)
        .mapWords.add("Swag.vecany", State.Builtin)
        .mapWords.add("Swag.vecavgr", State.Builtin)
        .mapWords.add("Swag.vecgather", State.Builtin)
        .mapWords.add("Swag.vecinterleavehi", State.Builtin)
        .mapWords.add("Swag.vecinterleavelo", State.Builtin)
        .mapWords.add("Swag.vecmadd", State.Builtin)
        .mapWords.add("Swag.vecmaddubs", State.Builtin)
        .mapWords.add("Swag.vecmask", State.Builtin)
        .mapWords.add("Swag.vecmulhi", State.Builtin)
        .mapWords.add("Swag.vecpackss", State.Builtin)
        .mapWords.add("Swag.vecpackus", State.Builtin)
        .mapWords.add("Swag.vecperm", State.Builtin)
        .mapWords.add("Swag.vecreduceadd", State.Builtin)
        .mapWords.add("Swag.vecreduceand", State.Builtin)
        .mapWords.add("Swag.vecreducemax", State.Builtin)
        .mapWords.add("Swag.vecreducemin", State.Builtin)
        .mapWords.add("Swag.vecreduceor", State.Builtin)
        .mapWords.add("Swag.vecreducexor", State.Builtin)
        .mapWords.add("Swag.vecsad", State.Builtin)
        .mapWords.add("Swag.vecsatadd", State.Builtin)
        .mapWords.add("Swag.vecsatsub", State.Builtin)
        .mapWords.add("Swag.vecselect", State.Builtin)
        .mapWords.add("Swag.vecshuffle", State.Builtin)
        .mapWords.add("Swag.vecshuffle2", State.Builtin)
        .mapWords.add("Swag.vecsplat", State.Builtin)
        .mapWords.add("Swag.vectruncs32", State.Builtin)
        .mapWords.add("Swag.vecwidenhi", State.Builtin)
        .mapWords.add("Swag.vecwidenlo", State.Builtin)

        .mapWords.add("#run", State.CompilerFunction)
        .mapWords.add("#test", State.CompilerFunction)
        .mapWords.add("#init", State.CompilerFunction)
        .mapWords.add("#drop", State.CompilerFunction)
        .mapWords.add("#premain", State.CompilerFunction)
        .mapWords.add("#main", State.CompilerFunction)
        .mapWords.add("#message", State.CompilerFunction)
        .mapWords.add("#ast", State.CompilerFunction)

        .mapWords.add("#global", State.CompilerGlobal)
        .mapWords.add("#load", State.CompilerStatement)
        .mapWords.add("#foreignlib", State.CompilerStatement)
        .mapWords.add("#assert", State.CompilerStatement)
        .mapWords.add("#print", State.CompilerStatement)
        .mapWords.add("#error", State.CompilerStatement)
        .mapWords.add("#warning", State.CompilerStatement)
        .mapWords.add("#import", State.CompilerStatement)
        .mapWords.add("#inject", State.CompilerStatement)
        .mapWords.add("#static", State.CompilerStatement)
        .mapWords.add("else", State.CompilerStatement)
        .mapWords.add("elif", State.CompilerStatement)
        .mapWords.add("#scope", State.CompilerStatement)

        .mapWords.add("#cfg", State.Compiler)
        .mapWords.add("#command", State.Compiler)
        .mapWords.add("#os", State.Compiler)
        .mapWords.add("#arch", State.Compiler)
        .mapWords.add("#cpu", State.Compiler)
        .mapWords.add("#me", State.Compiler)
        .mapWords.add("#module", State.Compiler)
        .mapWords.add("#file", State.Compiler)
        .mapWords.add("#line", State.Compiler)
        .mapWords.add("#scopename", State.Compiler)
        .mapWords.add("#curlocation", State.Compiler)
        .mapWords.add("#callerlocation", State.Compiler)
        .mapWords.add("#swcversion", State.Compiler)
        .mapWords.add("#swcrevision", State.Compiler)
        .mapWords.add("#swcbuildnum", State.Compiler)
        .mapWords.add("#swagos", State.Compiler)

        .mapWords.add("#code", State.Intrinsic)
        .mapWords.add("#type", State.Intrinsic)

        .mapWords.add("#prom", State.Modifier)
        .mapWords.add("#wrap", State.Modifier)
        .mapWords.add("#nodrop", State.Modifier)
        .mapWords.add("#move", State.Modifier)
        .mapWords.add("#relocate", State.Modifier)
        .mapWords.add("#fwd", State.Modifier)
        .mapWords.add("#null", State.Modifier)
        .mapWords.add("#complete", State.Modifier)
        .mapWords.add("#fail", State.Modifier)
        .mapWords.add("#nofail", State.Modifier)
        .mapWords.add("#bit", State.Modifier)
        .mapWords.add("#unconst", State.Modifier)
        .mapWords.add("#raw", State.Modifier)
    }

    // Contrast every syntax color is guaranteed to reach against the editor's ground, which
    // is the WCAG ratio for body text: code is read for longer than any label of the
    // interface, so it does not get a lower bar.
    private const SyntaxContrast = 4.5'f32

    // Returns `argb` moved until it is readable on `ground`, keeping its hue.
    //
    // The hues below belong to the language, not to the theme: a reader who has learned that
    // green is a comment keeps that knowledge when the interface turns white. What the theme
    // decides is how far each hue has to travel to stay legible, and on a dark ground these
    // values already clear the bar, so the familiar palette is left exactly as it is.
    private func onGround(argb: u32, ground: Color)->Color
    {
        var result = Color.fromArgb(argb)
        result.ensureContrast(ground, SyntaxContrast)
        return result
    }

    mtd impl setupTheme(ed: *RichEditCtrl)
    {
        using RichEditLexerSwag.Style
        let ground = ed.themeColors().richEdit_Bk

        ed.styles[cast(u64) Comment].colFg      = onGround(0xFF7AA86A, ground)
        ed.styles[cast(u64) Keyword].colFg      = onGround(0xFF74AAE0, ground)
        ed.styles[cast(u64) Control].colFg      = onGround(0xFFC48FD0, ground)
        ed.styles[cast(u64) Intrinsic].colFg    = onGround(0xFFCBB45C, ground)
        ed.styles[cast(u64) Namespace].colFg    = onGround(0xFF94A3B8, ground)
        ed.styles[cast(u64) Builtin].colFg      = onGround(0xFFE8A06A, ground)
        ed.styles[cast(u64) Function].colFg     = onGround(0xFFE8A06A, ground)
        ed.styles[cast(u64) Preprocessor].colFg = onGround(0xFF9A9AA6, ground)
        ed.styles[cast(u64) CharEscape].colFg   = onGround(0xFFCBB45C, ground)
        ed.styles[cast(u64) Type].colFg         = onGround(0xFFE0B464, ground)
        ed.styles[cast(u64) Class].colFg        = onGround(0xFF56C2B3, ground)
        ed.styles[cast(u64) String].colFg       = onGround(0xFFE0937C, ground)
        ed.styles[cast(u64) Character].colFg    = onGround(0xFFE0937C, ground)
        ed.styles[cast(u64) Numeric].colFg      = onGround(0xFF9EC98F, ground)
        ed.styles[cast(u64) Error].colFg        = onGround(0xFFFF6666, ground)
    }

    mtd impl insertRune(ed: *RichEditCtrl, ch: rune)->bool
    {
        // Smart return
        if ch == '\n'
        {
            let cp          = ed.selectionStart()
            let line        = ed.lines[cp.lineIndex]!
            var str: String = "\n"

            if cp.charPosInLine
            {
                var cpt = 0
                while cpt < line.chars.count and Unicode.isSpace(line.chars[cpt])
                {
                    str += line.chars[cpt]
                    cpt += 1
                }

                if cpt < line.chars.count and line.chars[cpt] == '{' do
                    str += '\t'rune
            }

            ed.pushUndo()
            ed.insertText(str)
            ed.popUndo()
            ed.ensureCaretIsVisible()
            return true
        }

        return false
    }

    mtd impl compute(linePrev: #null *RichEditLine, line: *RichEditLine, lineNext: #null *RichEditLine)
    {
        var seek                = 0'u64
        var currentState: State = linePrev ? cast(State) linePrev.lexerEndingState : State.Default
        var currentCptCmt       = linePrev ? linePrev.lexerCptCmt : 0

        #[Swag.Mixin]
        func getCur()->rune
        {
            if seek >= line.chars.count do
                return 0
            return line.chars[seek]
        }

        #[Swag.Mixin]
        func getNext()->rune
        {
            if !line.chars.count do
                return 0
            if seek >= line.chars.count - 1 do
                return 0
            return line.chars[seek + 1]
        }

        #[Swag.Mixin]
        mtd seekNext()
        {
            if seek >= line.chars.count do
                return
            line.styles[seek] = cast(RichEditStyleRef) .mapStyles[currentState]
            seek              += 1
        }

        for
        {
            var c  = getCur()
            let cn = getNext()
            if !c
            {
                switch currentState
                {
                case State.NumericFrac, State.Numeric, State.NumericHex, State.NumericBin: currentState = State.Default
                }

                break
            }

            switch currentState
            {
            case State.NumericFrac:
                if Unicode.isNumber(c) or c == '_'
                {
                    .seekNext()
                    continue
                }

                if c == 'e'
                {
                    .seekNext()
                    if cn == '+' or cn == '-' do
                        .seekNext()
                    currentState = State.Numeric
                    continue
                }

                currentState = State.Default

            case State.NumericHex:
                if Unicode.isNumber(c) or c == '_'
                {
                    .seekNext()
                    continue
                }

                if !Unicode.isLatin1(c) or !Latin1.isHexDigit(cast(u8) c)
                {
                    currentState = State.Default
                    .seekNext()
                    continue
                }

            case State.NumericBin:
                if Unicode.isNumber(c) or c == '_'
                {
                    .seekNext()
                    continue
                }

                if c != '0' and c != '1'
                {
                    currentState = State.Default
                    .seekNext()
                    if getCur() == '\'' do
                        .seekNext()
                    continue
                }

            case State.Numeric:
                if c == '.' and cn == '.'
                {
                    currentState = State.Default
                    .seekNext()
                    continue
                }

                if c == '.' or c == 'e' or c == 'E'
                {
                    currentState = State.NumericFrac
                    .seekNext()
                    continue
                }

                if !Unicode.isNumber(c) and c != '.'
                {
                    currentState = State.Default
                    .seekNext()
                    if getCur() == '\'' do
                        .seekNext()
                    continue
                }

            case State.String:
                if c == '\\'
                {
                    .seekNext()
                    .seekNext()
                    continue
                }

                if c == '"'
                {
                    .seekNext()
                    currentState = State.Default
                    if getCur() == '\'' do
                        .seekNext()
                    continue
                }

            case State.RawString:
                if c == '"' and cn == '@'
                {
                    .seekNext()
                    .seekNext()
                    currentState = State.Default
                    continue
                }

            case State.Character:
                if c == '\\'
                {
                    .seekNext()
                    .seekNext()
                    continue
                }

                if c == '\''
                {
                    .seekNext()
                    currentState = State.Default
                    continue
                }

            case State.Comment:
                if c == '*' and cn == '/'
                {
                    .seekNext()
                    .seekNext()
                    if currentCptCmt do
                        currentCptCmt -= 1
                    if !currentCptCmt do
                        currentState = State.Default
                    continue
                }

                if c == '/' and cn == '*'
                {
                    currentCptCmt += 1
                    .seekNext()
                    .seekNext()
                    continue
                }

            case State.Attribute:
                if c == 'S' and seek + 4 < line.chars.count and line.chars[seek + 1] == 'w' and line.chars[seek + 2] == 'a' and line.chars[seek + 3] == 'g' and line.chars[seek + 4] == '.' and
                   (seek == 0 or (!Unicode.isLetterOrDigit(line.chars[seek - 1]) and line.chars[seek - 1] != '_'))
                {
                    currentState = State.Namespace
                    for 4 do
                        .seekNext()
                    currentState = State.Default
                    .seekNext()
                    currentState = State.Attribute
                    continue
                }

                if c == ']'
                {
                    .seekNext()
                    currentState = State.Default
                    continue
                }

            case State.Default:
                if c == '#' and cn == '['
                {
                    currentState = State.Attribute
                    .seekNext()
                    .seekNext()
                    continue
                }

                if c == '@' and cn == '"'
                {
                    currentState = State.RawString
                    .seekNext()
                    .seekNext()
                    continue
                }

                if Unicode.isLetter(c) or c == '_' or c == '#'
                {
                    var word: String
                    let saveSeek = seek
                    while Unicode.isLetterOrDigit(c) or c == '_' or c == '#' or (word == "Swag" and c == '.')
                    {
                        word += c
                        seek += 1
                        c    = getCur()
                    }

                    let seekEnd = seek
                    seek = saveSeek
                    let isSwagNamespace = word.startsWith("Swag.")

                    if word == "opVisit" do
                        currentState = State.FunctionSpecOp
                    elif !word.isEmpty()
                    {
                        let res = .mapWords.tryFind(word.toString())
                        if res do
                            currentState = res.value
                        elif isSwagNamespace and word.count > 5 and Latin1.isUpper(word[5]) do
                            currentState = State.UserType
                        elif isSwagNamespace and word.count > 5 and c == '(' do
                            currentState = State.FunctionCall
                        elif Latin1.isUpper(word[0]) do
                            currentState = State.UserType
                        elif c == '(' and (Latin1.isLetter(word[0]) or word[0] == '_') do
                            currentState = State.FunctionCall
                        else do
                            currentState = State.Default
                    }

                    if isSwagNamespace
                    {
                        let memberState = currentState
                        currentState = State.Namespace
                        for 4 do
                            .seekNext()
                        currentState = State.Default
                        .seekNext()
                        currentState = memberState
                    }

                    while seek != seekEnd do
                        .seekNext()
                    currentState = State.Default
                    if c == '\'' do
                        .seekNext()
                    continue
                }

                if c == '"'
                {
                    currentState = State.String
                    .seekNext()
                    continue
                }

                if c == '\''
                {
                    currentState = State.Character
                    .seekNext()
                    continue
                }

                if Unicode.isNumber(c) and Unicode.toLower(cn) == 'b'
                {
                    currentState = State.NumericBin
                    .seekNext()
                    .seekNext()
                    continue
                }

                if Unicode.isNumber(c) and Unicode.toLower(cn) == 'x'
                {
                    currentState = State.NumericHex
                    .seekNext()
                    .seekNext()
                    continue
                }

                if Unicode.isNumber(c)
                {
                    currentState = State.Numeric
                    .seekNext()
                    continue
                }

                if c == '/' and cn == '*'
                {
                    currentCptCmt += 1
                    currentState  = State.Comment
                    .seekNext()
                    .seekNext()
                    continue
                }

                if c == '/' and cn == c
                {
                    currentState = State.LineComment
                    .seekNext()
                    .seekNext()
                    continue
                }
            }

            .seekNext()
        }

        if currentState == State.LineComment do
            currentState = State.Default

        if line.lexerEndingState != cast(s32) currentState
        {
            line.lexerEndingState = cast(s32) currentState
            if lineNext do
                lineNext.dirtyStyle = true
        }

        if line.lexerCptCmt != currentCptCmt
        {
            line.lexerCptCmt = currentCptCmt
            if lineNext do
                lineNext.dirtyStyle = true
        }
    }
}
