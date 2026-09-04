// TRIVIA

SWC_TOKEN_DEF(Invalid, "", TokenIdKindE::Zero)

SWC_TOKEN_DEF(Whitespace, "", TokenIdKindE::Trivia)
SWC_TOKEN_DEF(EndOfFile, "", TokenIdKindE::Trivia)

SWC_TOKEN_DEF(CommentLine, "", TokenIdKindE::Trivia)
SWC_TOKEN_DEF(CommentBlock, "", TokenIdKindE::Trivia)

// LITERALS

SWC_TOKEN_DEF(StringLine, "", TokenIdKindE::Literal)
SWC_TOKEN_DEF(StringMultiLine, "", TokenIdKindE::Literal)

SWC_TOKEN_DEF(Character, "", TokenIdKindE::Literal)

SWC_TOKEN_DEF(NumberHex, "", TokenIdKindE::Literal)
SWC_TOKEN_DEF(NumberBin, "", TokenIdKindE::Literal)
SWC_TOKEN_DEF(NumberInteger, "", TokenIdKindE::Literal)
SWC_TOKEN_DEF(NumberFloat, "", TokenIdKindE::Literal)

// IDENTIFIERS

SWC_TOKEN_DEF(Identifier, "", TokenIdKindE::Zero)
SWC_TOKEN_DEF(SharpIdentifier, "", TokenIdKindE::Compiler)

SWC_TOKEN_DEF(KwdMe, "me", TokenIdKindE::Keyword)

SWC_TOKEN_DEF(KwdExport, "export", TokenIdKindE::Zero)
SWC_TOKEN_DEF(KwdLocation, "location", TokenIdKindE::Zero)
SWC_TOKEN_DEF(KwdLink, "link", TokenIdKindE::Zero)
SWC_TOKEN_DEF(KwdVersion, "version", TokenIdKindE::Zero)

// SYMBOLS

SWC_TOKEN_DEF(SymSingleQuote, "'", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymBackSlash, "\\", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymLeftParen, "(", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymRightParen, ")", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymLeftBracket, "[", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymRightBracket, "]", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymLeftCurly, "{", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymRightCurly, "}", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymSemiColon, ";", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymComma, ",", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymAt, "@", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymQuestion, "?", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymQuestionDot, "?.", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymTilde, "~", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymEqual, "=", TokenIdKindE::Symbol | TokenIdKindE::OpAssign)
SWC_TOKEN_DEF(SymEqualEqual, "==", TokenIdKindE::Symbol | TokenIdKindE::OpEquality)
SWC_TOKEN_DEF(SymEqualGreater, "=>", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymColon, ":", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymBang, "!", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymBangEqual, "!=", TokenIdKindE::Symbol | TokenIdKindE::OpEquality)
SWC_TOKEN_DEF(SymMinus, "-", TokenIdKindE::Symbol | TokenIdKindE::OpArithmetic)
SWC_TOKEN_DEF(SymMinusEqual, "-=", TokenIdKindE::Symbol | TokenIdKindE::OpAssign)
SWC_TOKEN_DEF(SymMinusGreater, "->", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymMinusMinus, "--", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymPlus, "+", TokenIdKindE::Symbol | TokenIdKindE::OpArithmetic)
SWC_TOKEN_DEF(SymPlusEqual, "+=", TokenIdKindE::Symbol | TokenIdKindE::OpAssign)
SWC_TOKEN_DEF(SymPlusPlus, "++", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymAsterisk, "*", TokenIdKindE::Symbol | TokenIdKindE::OpArithmetic)
SWC_TOKEN_DEF(SymAsteriskEqual, "*=", TokenIdKindE::Symbol | TokenIdKindE::OpAssign)
SWC_TOKEN_DEF(SymSlash, "/", TokenIdKindE::Symbol | TokenIdKindE::OpArithmetic)
SWC_TOKEN_DEF(SymSlashEqual, "/=", TokenIdKindE::Symbol | TokenIdKindE::OpAssign)
SWC_TOKEN_DEF(SymAmpersand, "&", TokenIdKindE::Symbol | TokenIdKindE::OpBitwise)
SWC_TOKEN_DEF(SymAmpersandEqual, "&=", TokenIdKindE::Symbol | TokenIdKindE::OpAssign)
SWC_TOKEN_DEF(SymAmpersandAmpersand, "&&", TokenIdKindE::Symbol | TokenIdKindE::OpLogical)
SWC_TOKEN_DEF(SymPipe, "|", TokenIdKindE::Symbol | TokenIdKindE::OpBitwise)
SWC_TOKEN_DEF(SymPipeEqual, "|=", TokenIdKindE::Symbol | TokenIdKindE::OpAssign)
SWC_TOKEN_DEF(SymPipePipe, "||", TokenIdKindE::Symbol | TokenIdKindE::OpLogical)
SWC_TOKEN_DEF(SymCircumflex, "^", TokenIdKindE::Symbol | TokenIdKindE::OpBitwise)
SWC_TOKEN_DEF(SymCircumflexEqual, "^=", TokenIdKindE::Symbol | TokenIdKindE::OpAssign)
SWC_TOKEN_DEF(SymPercent, "%", TokenIdKindE::Symbol | TokenIdKindE::OpArithmetic)
SWC_TOKEN_DEF(SymPercentEqual, "%=", TokenIdKindE::Symbol | TokenIdKindE::OpAssign)
SWC_TOKEN_DEF(SymDot, ".", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymDotDot, "..", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymDotDotDot, "...", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymLess, "<", TokenIdKindE::Symbol | TokenIdKindE::OpOrdering)
SWC_TOKEN_DEF(SymLessEqual, "<=", TokenIdKindE::Symbol | TokenIdKindE::OpOrdering)
SWC_TOKEN_DEF(SymLessEqualGreater, "<=>", TokenIdKindE::Symbol | TokenIdKindE::OpOrdering)
SWC_TOKEN_DEF(SymLowerLower, "<<", TokenIdKindE::Symbol | TokenIdKindE::OpBitwise)
SWC_TOKEN_DEF(SymLowerLowerEqual, "<<=", TokenIdKindE::Symbol | TokenIdKindE::OpAssign)
SWC_TOKEN_DEF(SymGreater, ">", TokenIdKindE::Symbol | TokenIdKindE::OpOrdering)
SWC_TOKEN_DEF(SymGreaterEqual, ">=", TokenIdKindE::Symbol | TokenIdKindE::OpOrdering)
SWC_TOKEN_DEF(SymGreaterGreater, ">>", TokenIdKindE::Symbol | TokenIdKindE::OpBitwise)
SWC_TOKEN_DEF(SymGreaterGreaterEqual, ">>=", TokenIdKindE::Symbol | TokenIdKindE::OpAssign)
SWC_TOKEN_DEF(SymAttrStart, "#[", TokenIdKindE::Symbol)

// CONTROL FLOW KEYWORDS

SWC_TOKEN_DEF(KwdIf, "if", TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdElse, "else", TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdElseIf, "elif", TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdFor, "for", TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdWhile, "while", TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdSwitch, "switch", TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdDefer, "defer", TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdWhere, "where", TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdBreak, "break", TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdFallThrough, "fallthrough", TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdUnreachable, "unreachable", TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdReturn, "return", TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdCase, "case", TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdContinue, "continue", TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdDefault, "default", TokenIdKindE::Keyword | TokenIdKindE::Logic)

SWC_TOKEN_DEF(KwdAnd, "and", TokenIdKindE::Keyword | TokenIdKindE::Logic | TokenIdKindE::OpLogical)
SWC_TOKEN_DEF(KwdOr, "or", TokenIdKindE::Keyword | TokenIdKindE::Logic | TokenIdKindE::OpLogical)
SWC_TOKEN_DEF(KwdOrElse, "orelse", TokenIdKindE::Keyword | TokenIdKindE::Logic)

SWC_TOKEN_DEF(KwdTo, "to", TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdUntil, "until", TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdIn, "in", TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdAs, "as", TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdIs, "is", TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdDo, "do", TokenIdKindE::Keyword | TokenIdKindE::Logic)

// MODULE / ERROR HANDLING

SWC_TOKEN_DEF(KwdUsing, "using", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdWith, "with", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdCast, "cast", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdRetVal, "retval", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdTry, "try", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdCatch, "catch", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdExpect, "expect", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdFail, "fail", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdDiscard, "discard", TokenIdKindE::Keyword)

// LITERAL KEYWORDS

SWC_TOKEN_DEF(KwdTrue, "true", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdFalse, "false", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdNull, "null", TokenIdKindE::Keyword)

// ACCESS MODIFIERS

SWC_TOKEN_DEF(KwdPublic, "public", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdPrivate, "private", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdInternal, "internal", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdReadOnly, "readonly", TokenIdKindE::Keyword)

// TYPE DEFINITIONS

SWC_TOKEN_DEF(KwdEnum, "enum", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdStruct, "struct", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdUnion, "union", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdImpl, "impl", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdInterface, "interface", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdFunc, "func", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdMtd, "mtd", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdNamespace, "namespace", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdAlias, "alias", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdAttr, "attr", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdVar, "var", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdLet, "let", TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdConst, "const", TokenIdKindE::Keyword)

// RESERVED

SWC_TOKEN_DEF(KwdNot, "not", TokenIdKindE::Reserved)

// COMPILER FUNC

SWC_TOKEN_DEF(CompilerGlobal, "#global", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerRun, "#run", TokenIdKindE::Compiler | TokenIdKindE::Func)
SWC_TOKEN_DEF(CompilerAst, "#ast", TokenIdKindE::Compiler | TokenIdKindE::Func)
SWC_TOKEN_DEF(CompilerFuncTest, "#test", TokenIdKindE::Compiler | TokenIdKindE::Func)
SWC_TOKEN_DEF(CompilerFuncInit, "#init", TokenIdKindE::Compiler | TokenIdKindE::Func)
SWC_TOKEN_DEF(CompilerFuncDrop, "#drop", TokenIdKindE::Compiler | TokenIdKindE::Func)
SWC_TOKEN_DEF(CompilerFuncMain, "#main", TokenIdKindE::Compiler | TokenIdKindE::Func)
SWC_TOKEN_DEF(CompilerFuncPreMain, "#premain", TokenIdKindE::Compiler | TokenIdKindE::Func)
SWC_TOKEN_DEF(CompilerFuncMessage, "#message", TokenIdKindE::Compiler | TokenIdKindE::Func)
SWC_TOKEN_DEF(CompilerInclude, "#include", TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerLoad, "#load", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerAssert, "#assert", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerPrint, "#print", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerError, "#error", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerWarning, "#warning", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerForeignLib, "#foreignlib", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerImport, "#import", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerInject, "#inject", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerStatic, "#static", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerCode, "#code", TokenIdKindE::Compiler | TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(CompilerScope, "#scope", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerType, "#type", TokenIdKindE::Compiler | TokenIdKindE::Intrinsic)

// MODIFIERS

SWC_TOKEN_DEF(ModifierPromote, "#prom", TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierWrap, "#wrap", TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierNoDrop, "#nodrop", TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierMove, "#move", TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierRelocate, "#relocate", TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierFwd, "#fwd", TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierNullable, "#null", TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierComplete, "#complete", TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierFail, "#fail", TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierNoFail, "#nofail", TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierBit, "#bit", TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierUnConst, "#unconst", TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierRaw, "#raw", TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierSimd, "#simd", TokenIdKindE::Modifier)

// COMPILER IDENTIFIERS

SWC_TOKEN_DEF(CompilerUniq0, "#uniq0", TokenIdKindE::Compiler | TokenIdKindE::Uniq)
SWC_TOKEN_DEF(CompilerUniq1, "#uniq1", TokenIdKindE::Compiler | TokenIdKindE::Uniq)
SWC_TOKEN_DEF(CompilerUniq2, "#uniq2", TokenIdKindE::Compiler | TokenIdKindE::Uniq)
SWC_TOKEN_DEF(CompilerUniq3, "#uniq3", TokenIdKindE::Compiler | TokenIdKindE::Uniq)
SWC_TOKEN_DEF(CompilerUniq4, "#uniq4", TokenIdKindE::Compiler | TokenIdKindE::Uniq)
SWC_TOKEN_DEF(CompilerUniq5, "#uniq5", TokenIdKindE::Compiler | TokenIdKindE::Uniq)
SWC_TOKEN_DEF(CompilerUniq6, "#uniq6", TokenIdKindE::Compiler | TokenIdKindE::Uniq)
SWC_TOKEN_DEF(CompilerUniq7, "#uniq7", TokenIdKindE::Compiler | TokenIdKindE::Uniq)
SWC_TOKEN_DEF(CompilerUniq8, "#uniq8", TokenIdKindE::Compiler | TokenIdKindE::Uniq)
SWC_TOKEN_DEF(CompilerUniq9, "#uniq9", TokenIdKindE::Compiler | TokenIdKindE::Uniq)

// COMPILER INFO

SWC_TOKEN_DEF(CompilerBuildCfg, "#cfg", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerCommand, "#command", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerOs, "#os", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerArch, "#arch", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerCpu, "#cpu", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerModule, "#module", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerFile, "#file", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerLine, "#line", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerScopeName, "#scopename", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerCurLocation, "#curlocation", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerCallerLocation, "#callerlocation", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerSwcVersion, "#swcversion", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerSwcRevision, "#swcrevision", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerSwcBuildNum, "#swcbuildnum", TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerSwagOs, "#swagos", TokenIdKindE::Compiler)

// COMPILER INTROSPECTION

SWC_TOKEN_DEF(CompilerDefined, "#defined", TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerOffsetOf, "#offsetof", TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerAlignOf, "#alignof", TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerSizeOf, "#sizeof", TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerTypeOf, "#typeof", TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerKindOf, "#kindof", TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerStringOf, "#stringof", TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerNameOf, "#nameof", TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerFullNameOf, "#fullnameof", TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerIsConstExpr, "#isconstexpr", TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerLocation, "#location", TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerDeclType, "#decltype", TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerHasTag, "#hastag", TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerGetTag, "#gettag", TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerRunes, "#runes", TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerSafety, "#safety", TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerSanity, "#sanity", TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)

// INTRINSICS - STRING/TYPE

SWC_TOKEN_DEF(IntrinsicStringCmp, "Swag.stringCmp", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicTypeCmp, "Swag.typeCmp", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicIs, "Swag.typeIs", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicAs, "Swag.typeAs", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicGetContext, "Swag.getContext", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicCompiler, "Swag.compiler", TokenIdKindE::Intrinsic | TokenIdKindE::Return)

SWC_TOKEN_DEF(IntrinsicSetContext, "Swag.setContext", TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicPrint, "Swag.print", TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicCompilerError, "Swag.compilerError", TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicCompilerWarning, "Swag.compilerWarning", TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicBreakpoint, "Swag.breakpoint", TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicAssert, "Swag.assert", TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicPanic, "Swag.panic", TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicSafetyPanic, "Swag.safetyPanic", TokenIdKindE::Intrinsic)

// INTRINSICS - LIFECYCLE

SWC_TOKEN_DEF(IntrinsicInit, "Swag.init", TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicDrop, "Swag.drop", TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicPostMove, "Swag.postMove", TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicPostCopy, "Swag.postCopy", TokenIdKindE::Intrinsic)

// INTRINSICS - TYPE INFO

SWC_TOKEN_DEF(IntrinsicKindOf, "Swag.kindOf", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicCountOf, ".count", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicDataOf, ".buffer", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicIsSet, "Swag.isSet", TokenIdKindE::Intrinsic | TokenIdKindE::Return)

// INTRINSICS - CONSTRUCTORS

SWC_TOKEN_DEF(IntrinsicMakeSlice, "Swag.makeSlice", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicMakeString, "Swag.makeString", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicMakeAny, "Swag.makeAny", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicMakeInterface, "Swag.makeInterface", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicTableOf, "Swag.tableOf", TokenIdKindE::Intrinsic | TokenIdKindE::Return)

// INTRINSICS - RUNTIME

SWC_TOKEN_DEF(IntrinsicArgs, "Swag.args", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicJit, "Swag.jit", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicRtFlags, "Swag.runtimeFlags", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicProcessInfos, "Swag.processInfos", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicModules, "Swag.modules", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicGvtd, "Swag.gvtd", TokenIdKindE::Intrinsic | TokenIdKindE::Return)

// INTRINSICS - BIT OPERATIONS

SWC_TOKEN_DEF(IntrinsicByteSwap, "Swag.byteSwap", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicBitCountNz, "Swag.bitCountNz", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicBitCountTz, "Swag.bitCountTz", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicBitCountLz, "Swag.bitCountLz", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicRol, "Swag.rol", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicRor, "Swag.ror", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)

// INTRINSICS - MATH

SWC_TOKEN_DEF(IntrinsicMin, "Swag.min", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicMax, "Swag.max", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicSqrt, "Swag.sqrt", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicSin, "Swag.sin", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicCos, "Swag.cos", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicTan, "Swag.tan", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicSinh, "Swag.sinh", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicCosh, "Swag.cosh", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicTanh, "Swag.tanh", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicASin, "Swag.asin", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicACos, "Swag.acos", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicATan, "Swag.atan", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicATan2, "Swag.atan2", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicLog, "Swag.log", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicLog2, "Swag.log2", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicLog10, "Swag.log10", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicFloor, "Swag.floor", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicCeil, "Swag.ceil", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicTrunc, "Swag.trunc", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicRound, "Swag.round", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicAbs, "Swag.abs", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicExp, "Swag.exp", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicExp2, "Swag.exp2", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicPow, "Swag.pow", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicMulAdd, "Swag.muladd", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)

// INTRINSICS - MEMORY
//
SWC_TOKEN_DEF(IntrinsicMemCpy, "Swag.memcpy", TokenIdKindE::Intrinsic | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicMemMove, "Swag.memmove", TokenIdKindE::Intrinsic | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicMemSet, "Swag.memset", TokenIdKindE::Intrinsic | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicMemCmp, "Swag.memcmp", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)

// INTRINSICS - ATOMIC

SWC_TOKEN_DEF(IntrinsicAtomicAdd, "Swag.atomadd", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicAtomicAnd, "Swag.atomand", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicAtomicOr, "Swag.atomor", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicAtomicXor, "Swag.atomxor", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicAtomicXchg, "Swag.atomxchg", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicAtomicCmpXchg, "Swag.atomcmpxchg", TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicAtomicGet, "Swag.atomget", TokenIdKindE::Intrinsic | TokenIdKindE::Return)

// INTRINSICS - VECTOR

SWC_TOKEN_DEF(IntrinsicVecSplat, "Swag.vecsplat", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecSatAdd, "Swag.vecsatadd", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecSatSub, "Swag.vecsatsub", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecPackUS, "Swag.vecpackus", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecPackSS, "Swag.vecpackss", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecInterleaveLo, "Swag.vecinterleavelo", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecInterleaveHi, "Swag.vecinterleavehi", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecWidenLo, "Swag.vecwidenlo", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecWidenHi, "Swag.vecwidenhi", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecAvgR, "Swag.vecavgr", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecMadd, "Swag.vecmadd", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecMaddUBS, "Swag.vecmaddubs", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecSad, "Swag.vecsad", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecMulHi, "Swag.vecmulhi", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecReduceAdd, "Swag.vecreduceadd", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecReduceMin, "Swag.vecreducemin", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecReduceMax, "Swag.vecreducemax", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecReduceAnd, "Swag.vecreduceand", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecReduceOr, "Swag.vecreduceor", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecReduceXor, "Swag.vecreducexor", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecTruncS32, "Swag.vectruncs32", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecGather, "Swag.vecgather", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecPerm, "Swag.vecperm", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecShuffle, "Swag.vecshuffle", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecShuffle2, "Swag.vecshuffle2", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecAlign, "Swag.vecalign", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecSelect, "Swag.vecselect", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecMask, "Swag.vecmask", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecAny, "Swag.vecany", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)
SWC_TOKEN_DEF(IntrinsicVecAll, "Swag.vecall", TokenIdKindE::Intrinsic | TokenIdKindE::Return | TokenIdKindE::Portable)

// NATIVE TYPES

SWC_TOKEN_DEF(TypeAny, "any", TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeVoid, "void", TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeRune, "rune", TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeF32, "f32", TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeF64, "f64", TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeS8, "s8", TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeS16, "s16", TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeS32, "s32", TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeS64, "s64", TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeU8, "u8", TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeU16, "u16", TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeU32, "u32", TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeU64, "u64", TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeBool, "bool", TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeString, "string", TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeCString, "cstring", TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeTypeInfo, "typeinfo", TokenIdKindE::Type)
