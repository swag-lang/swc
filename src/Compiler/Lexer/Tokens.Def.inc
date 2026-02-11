// TRIVIA

SWC_TOKEN_DEF(Invalid, "",  TokenIdKindE::Zero)

SWC_TOKEN_DEF(Whitespace, "",  TokenIdKindE::Trivia)
SWC_TOKEN_DEF(EndOfFile, "",  TokenIdKindE::Trivia)

SWC_TOKEN_DEF(CommentLine, "",  TokenIdKindE::Trivia)
SWC_TOKEN_DEF(CommentBlock, "",  TokenIdKindE::Trivia)

// LITERALS

SWC_TOKEN_DEF(StringLine, "",  TokenIdKindE::Literal)
SWC_TOKEN_DEF(StringRaw, "",  TokenIdKindE::Literal)
SWC_TOKEN_DEF(StringMultiLine, "",  TokenIdKindE::Literal)

SWC_TOKEN_DEF(Character, "",  TokenIdKindE::Literal)

SWC_TOKEN_DEF(NumberHex, "",  TokenIdKindE::Literal)
SWC_TOKEN_DEF(NumberBin, "",  TokenIdKindE::Literal)
SWC_TOKEN_DEF(NumberInteger, "",  TokenIdKindE::Literal)
SWC_TOKEN_DEF(NumberFloat, "",  TokenIdKindE::Literal)

// IDENTIFIERS

SWC_TOKEN_DEF(Identifier, "",  TokenIdKindE::Zero)
SWC_TOKEN_DEF(SharpIdentifier, "",  TokenIdKindE::Compiler)

SWC_TOKEN_DEF(KwdMe, "me",  TokenIdKindE::Keyword)

SWC_TOKEN_DEF(KwdSkip, "skip",  TokenIdKindE::Zero)
SWC_TOKEN_DEF(KwdSkipFmt, "skipfmt",  TokenIdKindE::Zero)
SWC_TOKEN_DEF(KwdExport, "export",  TokenIdKindE::Zero)
SWC_TOKEN_DEF(KwdGenerated, "generated",  TokenIdKindE::Zero)
SWC_TOKEN_DEF(KwdLocation, "location",  TokenIdKindE::Zero)
SWC_TOKEN_DEF(KwdVersion, "version",  TokenIdKindE::Zero)

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
SWC_TOKEN_DEF(SymTilde, "~", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymEqual, "=", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymEqualEqual, "==", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymEqualGreater, "=>", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymColon, ":", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymBang, "!", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymBangEqual, "!=", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymMinus, "-", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymMinusEqual, "-=", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymMinusGreater, "->", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymMinusMinus, "--", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymPlus, "+", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymPlusEqual, "+=", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymPlusPlus, "++", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymAsterisk, "*", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymAsteriskEqual, "*=", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymSlash, "/", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymSlashEqual, "/=", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymAmpersand, "&", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymAmpersandEqual, "&=", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymAmpersandAmpersand, "&&", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymPipe, "|", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymPipeEqual, "|=", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymPipePipe, "||", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymCircumflex, "^", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymCircumflexEqual, "^=", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymPercent, "%", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymPercentEqual, "%=", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymDot, ".", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymDotDot, "..", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymDotDotDot, "...", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymLess, "<", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymLessEqual, "<=", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymLessEqualGreater, "<=>", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymLowerLower, "<<", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymLowerLowerEqual, "<<=", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymGreater, ">", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymGreaterEqual, ">=", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymGreaterGreater, ">>", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymGreaterGreaterEqual, ">>=", TokenIdKindE::Symbol)
SWC_TOKEN_DEF(SymAttrStart, "#[", TokenIdKindE::Symbol)

// CONTROL FLOW KEYWORDS

SWC_TOKEN_DEF(KwdIf, "if",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdElse, "else",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdElseIf, "elif",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdFor, "for",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdWhile, "while",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdSwitch, "switch",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdDefer, "defer",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdForeach, "foreach",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdWhere, "where",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdVerify, "verify",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdBreak, "break",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdFallThrough, "fallthrough",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdUnreachable, "unreachable",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdReturn, "return",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdCase, "case",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdContinue, "continue",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdDefault, "default",  TokenIdKindE::Keyword | TokenIdKindE::Logic)

SWC_TOKEN_DEF(KwdAnd, "and",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdOr, "or",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdOrElse, "orelse",  TokenIdKindE::Keyword | TokenIdKindE::Logic)

SWC_TOKEN_DEF(KwdTo, "to",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdUntil, "until",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdIn, "in",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdAs, "as",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdIs, "is",  TokenIdKindE::Keyword | TokenIdKindE::Logic)
SWC_TOKEN_DEF(KwdDo, "do",  TokenIdKindE::Keyword | TokenIdKindE::Logic)

// MODULE / ERROR HANDLING

SWC_TOKEN_DEF(KwdUsing, "using",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdWith, "with",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdCast, "cast",  TokenIdKindE::Keyword) 
SWC_TOKEN_DEF(KwdDRef, "dref",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdRetVal, "retval",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdTry, "try",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdTryCatch, "trycatch",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdCatch, "catch",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdAssume, "assume",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdThrow, "throw",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdDiscard, "discard",  TokenIdKindE::Keyword)

// LITERAL KEYWORDS

SWC_TOKEN_DEF(KwdTrue, "true",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdFalse, "false",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdNull, "null",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdUndefined, "undefined",  TokenIdKindE::Keyword)

// ACCESS MODIFIERS

SWC_TOKEN_DEF(KwdPublic, "public",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdInternal, "internal",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdPrivate, "private",  TokenIdKindE::Keyword)

// TYPE DEFINITIONS

SWC_TOKEN_DEF(KwdEnum, "enum",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdStruct, "struct",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdUnion, "union",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdImpl, "impl",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdInterface, "interface",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdFunc, "func",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdMtd, "mtd",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdNamespace, "namespace",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdAlias, "alias",  TokenIdKindE::Keyword) 
SWC_TOKEN_DEF(KwdAttr, "attr",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdVar, "var",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdLet, "let",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdConst, "const",  TokenIdKindE::Keyword)
SWC_TOKEN_DEF(KwdMoveRef, "moveref",  TokenIdKindE::Keyword)

// RESERVED

SWC_TOKEN_DEF(KwdNot, "not",  TokenIdKindE::Reserved)

// COMPILER FUNC

SWC_TOKEN_DEF(CompilerGlobal, "#global",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerRun, "#run",  TokenIdKindE::Compiler | TokenIdKindE::Func)
SWC_TOKEN_DEF(CompilerAst, "#ast",  TokenIdKindE::Compiler | TokenIdKindE::Func)
SWC_TOKEN_DEF(CompilerFuncTest, "#test",  TokenIdKindE::Compiler | TokenIdKindE::Func)
SWC_TOKEN_DEF(CompilerFuncInit, "#init",  TokenIdKindE::Compiler | TokenIdKindE::Func)
SWC_TOKEN_DEF(CompilerFuncDrop, "#drop",  TokenIdKindE::Compiler | TokenIdKindE::Func)
SWC_TOKEN_DEF(CompilerFuncMain, "#main",  TokenIdKindE::Compiler | TokenIdKindE::Func)
SWC_TOKEN_DEF(CompilerFuncPreMain, "#premain",  TokenIdKindE::Compiler | TokenIdKindE::Func)
SWC_TOKEN_DEF(CompilerFuncMessage, "#message",  TokenIdKindE::Compiler | TokenIdKindE::Func)
SWC_TOKEN_DEF(CompilerDependencies, "#dependencies",  TokenIdKindE::Compiler | TokenIdKindE::Func)
SWC_TOKEN_DEF(CompilerInclude, "#include",  TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerLoad, "#load",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerAssert, "#assert",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerPrint, "#print",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerError, "#error",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerWarning, "#warning",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerForeignLib, "#foreignlib",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerImport, "#import",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerInject, "#inject",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerMacro, "#macro",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerIf, "#if",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerElse, "#else",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerElseIf, "#elif",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerCode, "#code",  TokenIdKindE::Compiler | TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(CompilerScope, "#scope",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerUp, "#up",  TokenIdKindE::Compiler | TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(CompilerType, "#type",  TokenIdKindE::Compiler | TokenIdKindE::Intrinsic)

// MODIFIERS

SWC_TOKEN_DEF(ModifierPromote, "#prom",  TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierWrap, "#wrap",  TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierNoDrop, "#nodrop",  TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierMove, "#move",  TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierMoveRaw, "#moveraw",  TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierReverse, "#reverse",  TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierRef, "#ref",  TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierConstRef, "#constref",  TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierNullable, "#null",  TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierErr, "#err",  TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierNoErr, "#noerr",  TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierBit, "#bit",  TokenIdKindE::Modifier)
SWC_TOKEN_DEF(ModifierUnConst, "#unconst",  TokenIdKindE::Modifier)

// COMPILER IDENTIFIERS

SWC_TOKEN_DEF(CompilerAlias0, "#alias0",  TokenIdKindE::Compiler | TokenIdKindE::Alias)
SWC_TOKEN_DEF(CompilerAlias1, "#alias1",  TokenIdKindE::Compiler | TokenIdKindE::Alias)
SWC_TOKEN_DEF(CompilerAlias2, "#alias2",  TokenIdKindE::Compiler | TokenIdKindE::Alias)
SWC_TOKEN_DEF(CompilerAlias3, "#alias3",  TokenIdKindE::Compiler | TokenIdKindE::Alias)
SWC_TOKEN_DEF(CompilerAlias4, "#alias4",  TokenIdKindE::Compiler | TokenIdKindE::Alias)
SWC_TOKEN_DEF(CompilerAlias5, "#alias5",  TokenIdKindE::Compiler | TokenIdKindE::Alias)
SWC_TOKEN_DEF(CompilerAlias6, "#alias6",  TokenIdKindE::Compiler | TokenIdKindE::Alias)
SWC_TOKEN_DEF(CompilerAlias7, "#alias7",  TokenIdKindE::Compiler | TokenIdKindE::Alias)
SWC_TOKEN_DEF(CompilerAlias8, "#alias8",  TokenIdKindE::Compiler | TokenIdKindE::Alias)
SWC_TOKEN_DEF(CompilerAlias9, "#alias9",  TokenIdKindE::Compiler | TokenIdKindE::Alias)
SWC_TOKEN_DEF(CompilerUniq0, "#uniq0",  TokenIdKindE::Compiler | TokenIdKindE::Uniq)
SWC_TOKEN_DEF(CompilerUniq1, "#uniq1",  TokenIdKindE::Compiler | TokenIdKindE::Uniq)
SWC_TOKEN_DEF(CompilerUniq2, "#uniq2",  TokenIdKindE::Compiler | TokenIdKindE::Uniq)
SWC_TOKEN_DEF(CompilerUniq3, "#uniq3",  TokenIdKindE::Compiler | TokenIdKindE::Uniq)
SWC_TOKEN_DEF(CompilerUniq4, "#uniq4",  TokenIdKindE::Compiler | TokenIdKindE::Uniq)
SWC_TOKEN_DEF(CompilerUniq5, "#uniq5",  TokenIdKindE::Compiler | TokenIdKindE::Uniq)
SWC_TOKEN_DEF(CompilerUniq6, "#uniq6",  TokenIdKindE::Compiler | TokenIdKindE::Uniq)
SWC_TOKEN_DEF(CompilerUniq7, "#uniq7",  TokenIdKindE::Compiler | TokenIdKindE::Uniq)
SWC_TOKEN_DEF(CompilerUniq8, "#uniq8",  TokenIdKindE::Compiler | TokenIdKindE::Uniq)
SWC_TOKEN_DEF(CompilerUniq9, "#uniq9",  TokenIdKindE::Compiler | TokenIdKindE::Uniq)

// COMPILER INFO

SWC_TOKEN_DEF(CompilerBuildCfg, "#cfg",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerOs, "#os",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerArch, "#arch",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerCpu, "#cpu",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerBackend, "#backend",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerModule, "#module",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerFile, "#file",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerLine, "#line",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerScopeName, "#scopename",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerCurLocation, "#curlocation",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerCallerLocation, "#callerlocation",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerCallerFunction, "#callerfunction",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerSwcVersion, "#swcversion",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerSwcRevision, "#swcrevision",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerSwcBuildNum, "#swcbuildnum",  TokenIdKindE::Compiler)
SWC_TOKEN_DEF(CompilerSwagOs, "#swagos",  TokenIdKindE::Compiler)

// COMPILER INTROSPECTION

SWC_TOKEN_DEF(CompilerDefined, "#defined",  TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerOffsetOf, "#offsetof",  TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerAlignOf, "#alignof",  TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerSizeOf, "#sizeof",  TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerTypeOf, "#typeof",  TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerKindOf, "#kindof",  TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerStringOf, "#stringof",  TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerNameOf, "#nameof",  TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerFullNameOf, "#fullnameof",  TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerIsConstExpr, "#isconstexpr",  TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerLocation, "#location",  TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerDeclType, "#decltype",  TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerHasTag, "#hastag",  TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerGetTag, "#gettag",  TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerRunes, "#runes",  TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(CompilerSafety, "#safety",  TokenIdKindE::Compiler | TokenIdKindE::Intrinsic | TokenIdKindE::Return)

// INTRINSICS - STRING/TYPE

SWC_TOKEN_DEF(IntrinsicStringCmp, "@stringcmp",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicTypeCmp, "@typecmp",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicIs, "@is",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicAs, "@as",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicGetContext, "@getcontext",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicCompiler, "@compiler",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)

SWC_TOKEN_DEF(IntrinsicSetContext, "@setcontext",  TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicPrint, "@print",  TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicCompilerError, "@compilererror",  TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicCompilerWarning, "@compilerwarning",  TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicBcBreakpoint, "@breakpoint",  TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicAssert, "@assert",  TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicPanic, "@panic",  TokenIdKindE::Intrinsic)

// INTRINSICS - LIFECYCLE

SWC_TOKEN_DEF(IntrinsicInit, "@init",  TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicDrop, "@drop",  TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicPostMove, "@postmove",  TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicPostCopy, "@postcopy",  TokenIdKindE::Intrinsic)

// INTRINSICS - TYPE INFO

SWC_TOKEN_DEF(IntrinsicKindOf, "@kindof",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicCountOf, "@countof",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicDataOf, "@dataof",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)

// INTRINSICS - CONSTRUCTORS

SWC_TOKEN_DEF(IntrinsicMakeSlice, "@mkslice",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicMakeString, "@mkstring",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicMakeAny, "@mkany",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicMakeInterface, "@mkinterface",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicMakeCallback, "@mkcallback",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicTableOf, "@tableof",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicDbgAlloc, "@dbgalloc",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicSysAlloc, "@sysalloc",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)

// INTRINSICS - RUNTIME

SWC_TOKEN_DEF(IntrinsicErr, "@err",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicArgs, "@args",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicByteCode, "@bytecode",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicIndex, "@index",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicRtFlags, "@rtflags",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicProcessInfos, "@pinfos",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicModules, "@modules",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicGvtd, "@gvtd",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)

// INTRINSICS - BIT OPERATIONS

SWC_TOKEN_DEF(IntrinsicByteSwap, "@byteswap",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicBitCountNz, "@bitcountnz",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicBitCountTz, "@bitcounttz",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicBitCountLz, "@bitcountlz",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicRol, "@rol",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicRor, "@ror",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)

// INTRINSICS - MATH

SWC_TOKEN_DEF(IntrinsicMin, "@min",  TokenIdKindE::Intrinsic | TokenIdKindE::Return) 
SWC_TOKEN_DEF(IntrinsicMax, "@max",  TokenIdKindE::Intrinsic | TokenIdKindE::Return) 
SWC_TOKEN_DEF(IntrinsicSqrt, "@sqrt",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicSin, "@sin",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicCos, "@cos",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicTan, "@tan",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicSinh, "@sinh",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicCosh, "@cosh",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicTanh, "@tanh",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicASin, "@asin",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicACos, "@acos",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicATan, "@atan",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicATan2, "@atan2",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicLog, "@log",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicLog2, "@log2",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicLog10, "@log10",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicFloor, "@floor",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicCeil, "@ceil",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicTrunc, "@trunc",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicRound, "@round",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicAbs, "@abs",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicExp, "@exp",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicExp2, "@exp2",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicPow, "@pow",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicMulAdd, "@muladd",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)

// INTRINSICS - MEMORY

SWC_TOKEN_DEF(IntrinsicFree, "@free",  TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicMemCpy, "@memcpy",  TokenIdKindE::Intrinsic) 
SWC_TOKEN_DEF(IntrinsicMemMove, "@memmove",  TokenIdKindE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicMemSet, "@memset",  TokenIdKindE::Intrinsic)

SWC_TOKEN_DEF(IntrinsicAlloc, "@alloc",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicRealloc, "@realloc",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicMemCmp, "@memcmp",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicStrLen, "@strlen",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicStrCmp, "@strcmp",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)

// INTRINSICS - ATOMIC

SWC_TOKEN_DEF(IntrinsicAtomicAdd, "@atomadd",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicAtomicAnd, "@atomand",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicAtomicOr, "@atomor",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicAtomicXor, "@atomxor",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicAtomicXchg, "@atomxchg",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicAtomicCmpXchg, "@atomcmpxchg",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)

// INTRINSICS - VARARGS

SWC_TOKEN_DEF(IntrinsicCVaStart, "@cvastart",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicCVaEnd, "@cvaend",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)
SWC_TOKEN_DEF(IntrinsicCVaArg, "@cvaarg",  TokenIdKindE::Intrinsic | TokenIdKindE::Return)

// NATIVE TYPES

SWC_TOKEN_DEF(TypeAny, "any",  TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeVoid, "void",  TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeRune, "rune",  TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeF32, "f32",  TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeF64, "f64",  TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeS8, "s8",  TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeS16, "s16",  TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeS32, "s32",  TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeS64, "s64",  TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeU8, "u8",  TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeU16, "u16",  TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeU32, "u32",  TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeU64, "u64",  TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeBool, "bool",  TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeString, "string",  TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeCString, "cstring",  TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeTypeInfo, "typeinfo",  TokenIdKindE::Type)
SWC_TOKEN_DEF(TypeCVarArgs, "cvarargs",  TokenIdKindE::Type)


