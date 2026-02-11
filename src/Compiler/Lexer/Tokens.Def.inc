// TRIVIA

SWC_TOKEN_DEF(Invalid, "",  TokenIdFlagsE::Zero)

SWC_TOKEN_DEF(Whitespace, "",  TokenIdFlagsE::Trivia)
SWC_TOKEN_DEF(EndOfFile, "",  TokenIdFlagsE::Trivia)

SWC_TOKEN_DEF(CommentLine, "",  TokenIdFlagsE::Trivia)
SWC_TOKEN_DEF(CommentBlock, "",  TokenIdFlagsE::Trivia)

// LITERALS

SWC_TOKEN_DEF(StringLine, "",  TokenIdFlagsE::Literal)
SWC_TOKEN_DEF(StringRaw, "",  TokenIdFlagsE::Literal)
SWC_TOKEN_DEF(StringMultiLine, "",  TokenIdFlagsE::Literal)

SWC_TOKEN_DEF(Character, "",  TokenIdFlagsE::Literal)

SWC_TOKEN_DEF(NumberHex, "",  TokenIdFlagsE::Literal)
SWC_TOKEN_DEF(NumberBin, "",  TokenIdFlagsE::Literal)
SWC_TOKEN_DEF(NumberInteger, "",  TokenIdFlagsE::Literal)
SWC_TOKEN_DEF(NumberFloat, "",  TokenIdFlagsE::Literal)

// IDENTIFIERS

SWC_TOKEN_DEF(Identifier, "",  TokenIdFlagsE::Zero)
SWC_TOKEN_DEF(SharpIdentifier, "",  TokenIdFlagsE::Compiler)

SWC_TOKEN_DEF(KwdMe, "me",  TokenIdFlagsE::Keyword)

SWC_TOKEN_DEF(KwdSkip, "skip",  TokenIdFlagsE::Zero)
SWC_TOKEN_DEF(KwdSkipFmt, "skipfmt",  TokenIdFlagsE::Zero)
SWC_TOKEN_DEF(KwdExport, "export",  TokenIdFlagsE::Zero)
SWC_TOKEN_DEF(KwdGenerated, "generated",  TokenIdFlagsE::Zero)
SWC_TOKEN_DEF(KwdLocation, "location",  TokenIdFlagsE::Zero)
SWC_TOKEN_DEF(KwdVersion, "version",  TokenIdFlagsE::Zero)

// SYMBOLS

SWC_TOKEN_DEF(SymSingleQuote, "'",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymBackSlash, "\\",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymLeftParen, "(",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymRightParen, ")",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymLeftBracket, "[",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymRightBracket, "]",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymLeftCurly, "{",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymRightCurly, "}",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymSemiColon, ";",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymComma, ",",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymAt, "@",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymQuestion, "?",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymTilde, "~",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymEqual, "=",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymEqualEqual, "==",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymEqualGreater, "=>",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymColon, ":",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymBang, "!",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymBangEqual, "!=",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymMinus, "-",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymMinusEqual, "-=",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymMinusGreater, "->",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymMinusMinus, "--",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymPlus, "+",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymPlusEqual, "+=",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymPlusPlus, "++",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymAsterisk, "*",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymAsteriskEqual, "*=",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymSlash, "/",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymSlashEqual, "/=",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymAmpersand, "&",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymAmpersandEqual, "&=",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymAmpersandAmpersand, "&&",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymPipe, "|",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymPipeEqual, "|=",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymPipePipe, "||",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymCircumflex, "^",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymCircumflexEqual, "^=",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymPercent, "%",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymPercentEqual, "%=",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymDot, ".",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymDotDot, "..",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymDotDotDot, "...",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymLess, "<",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymLessEqual, "<=",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymLessEqualGreater, "<=>",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymLowerLower, "<<",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymLowerLowerEqual, "<<=",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymGreater, ">",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymGreaterEqual, ">=",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymGreaterGreater, ">>",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymGreaterGreaterEqual, ">>=",  TokenIdFlagsE::Symbol)
SWC_TOKEN_DEF(SymAttrStart, "#[",  TokenIdFlagsE::Symbol)

// CONTROL FLOW KEYWORDS

SWC_TOKEN_DEF(KwdIf, "if",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdElse, "else",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdElseIf, "elif",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdFor, "for",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdWhile, "while",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdSwitch, "switch",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdDefer, "defer",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdForeach, "foreach",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdWhere, "where",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdVerify, "verify",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdBreak, "break",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdFallThrough, "fallthrough",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdUnreachable, "unreachable",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdReturn, "return",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdCase, "case",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdContinue, "continue",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdDefault, "default",  TokenIdFlagsE::KeywordLogic)

SWC_TOKEN_DEF(KwdAnd, "and",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdOr, "or",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdOrElse, "orelse",  TokenIdFlagsE::KeywordLogic)

SWC_TOKEN_DEF(KwdTo, "to",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdUntil, "until",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdIn, "in",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdAs, "as",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdIs, "is",  TokenIdFlagsE::KeywordLogic)
SWC_TOKEN_DEF(KwdDo, "do",  TokenIdFlagsE::KeywordLogic)

// MODULE / ERROR HANDLING

SWC_TOKEN_DEF(KwdUsing, "using",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdWith, "with",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdCast, "cast",  TokenIdFlagsE::Keyword) 
SWC_TOKEN_DEF(KwdDRef, "dref",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdRetVal, "retval",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdTry, "try",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdTryCatch, "trycatch",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdCatch, "catch",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdAssume, "assume",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdThrow, "throw",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdDiscard, "discard",  TokenIdFlagsE::Keyword)

// LITERAL KEYWORDS

SWC_TOKEN_DEF(KwdTrue, "true",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdFalse, "false",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdNull, "null",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdUndefined, "undefined",  TokenIdFlagsE::Keyword)

// ACCESS MODIFIERS

SWC_TOKEN_DEF(KwdPublic, "public",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdInternal, "internal",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdPrivate, "private",  TokenIdFlagsE::Keyword)

// TYPE DEFINITIONS

SWC_TOKEN_DEF(KwdEnum, "enum",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdStruct, "struct",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdUnion, "union",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdImpl, "impl",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdInterface, "interface",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdFunc, "func",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdMtd, "mtd",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdNamespace, "namespace",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdAlias, "alias",  TokenIdFlagsE::Keyword) 
SWC_TOKEN_DEF(KwdAttr, "attr",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdVar, "var",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdLet, "let",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdConst, "const",  TokenIdFlagsE::Keyword)
SWC_TOKEN_DEF(KwdMoveRef, "moveref",  TokenIdFlagsE::Keyword)

// RESERVED

SWC_TOKEN_DEF(KwdNot, "not",  TokenIdFlagsE::Reserved)

// COMPILER FUNC

SWC_TOKEN_DEF(CompilerGlobal, "#global",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerRun, "#run",  TokenIdFlagsE::CompilerFunc)
SWC_TOKEN_DEF(CompilerAst, "#ast",  TokenIdFlagsE::CompilerFunc)
SWC_TOKEN_DEF(CompilerFuncTest, "#test",  TokenIdFlagsE::CompilerFunc)
SWC_TOKEN_DEF(CompilerFuncInit, "#init",  TokenIdFlagsE::CompilerFunc)
SWC_TOKEN_DEF(CompilerFuncDrop, "#drop",  TokenIdFlagsE::CompilerFunc)
SWC_TOKEN_DEF(CompilerFuncMain, "#main",  TokenIdFlagsE::CompilerFunc)
SWC_TOKEN_DEF(CompilerFuncPreMain, "#premain",  TokenIdFlagsE::CompilerFunc)
SWC_TOKEN_DEF(CompilerFuncMessage, "#message",  TokenIdFlagsE::CompilerFunc)
SWC_TOKEN_DEF(CompilerDependencies, "#dependencies",  TokenIdFlagsE::CompilerFunc)
SWC_TOKEN_DEF(CompilerInclude, "#include",  TokenIdFlagsE::CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerLoad, "#load",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerAssert, "#assert",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerPrint, "#print",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerError, "#error",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerWarning, "#warning",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerForeignLib, "#foreignlib",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerImport, "#import",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerInject, "#inject",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerMacro, "#macro",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerIf, "#if",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerElse, "#else",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerElseIf, "#elif",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerCode, "#code",  TokenIdFlagsE::CompilerIntrinsic)
SWC_TOKEN_DEF(CompilerScope, "#scope",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerUp, "#up",  TokenIdFlagsE::CompilerIntrinsic)
SWC_TOKEN_DEF(CompilerType, "#type",  TokenIdFlagsE::CompilerIntrinsic)

// MODIFIERS

SWC_TOKEN_DEF(ModifierPromote, "#prom",  TokenIdFlagsE::Modifier)
SWC_TOKEN_DEF(ModifierWrap, "#wrap",  TokenIdFlagsE::Modifier)
SWC_TOKEN_DEF(ModifierNoDrop, "#nodrop",  TokenIdFlagsE::Modifier)
SWC_TOKEN_DEF(ModifierMove, "#move",  TokenIdFlagsE::Modifier)
SWC_TOKEN_DEF(ModifierMoveRaw, "#moveraw",  TokenIdFlagsE::Modifier)
SWC_TOKEN_DEF(ModifierReverse, "#reverse",  TokenIdFlagsE::Modifier)
SWC_TOKEN_DEF(ModifierRef, "#ref",  TokenIdFlagsE::Modifier)
SWC_TOKEN_DEF(ModifierConstRef, "#constref",  TokenIdFlagsE::Modifier)
SWC_TOKEN_DEF(ModifierNullable, "#null",  TokenIdFlagsE::Modifier)
SWC_TOKEN_DEF(ModifierErr, "#err",  TokenIdFlagsE::Modifier)
SWC_TOKEN_DEF(ModifierNoErr, "#noerr",  TokenIdFlagsE::Modifier)
SWC_TOKEN_DEF(ModifierBit, "#bit",  TokenIdFlagsE::Modifier)
SWC_TOKEN_DEF(ModifierUnConst, "#unconst",  TokenIdFlagsE::Modifier)

// COMPILER IDENTIFIERS

SWC_TOKEN_DEF(CompilerAlias0, "#alias0",  TokenIdFlagsE::CompilerAlias)
SWC_TOKEN_DEF(CompilerAlias1, "#alias1",  TokenIdFlagsE::CompilerAlias)
SWC_TOKEN_DEF(CompilerAlias2, "#alias2",  TokenIdFlagsE::CompilerAlias)
SWC_TOKEN_DEF(CompilerAlias3, "#alias3",  TokenIdFlagsE::CompilerAlias)
SWC_TOKEN_DEF(CompilerAlias4, "#alias4",  TokenIdFlagsE::CompilerAlias)
SWC_TOKEN_DEF(CompilerAlias5, "#alias5",  TokenIdFlagsE::CompilerAlias)
SWC_TOKEN_DEF(CompilerAlias6, "#alias6",  TokenIdFlagsE::CompilerAlias)
SWC_TOKEN_DEF(CompilerAlias7, "#alias7",  TokenIdFlagsE::CompilerAlias)
SWC_TOKEN_DEF(CompilerAlias8, "#alias8",  TokenIdFlagsE::CompilerAlias)
SWC_TOKEN_DEF(CompilerAlias9, "#alias9",  TokenIdFlagsE::CompilerAlias)
SWC_TOKEN_DEF(CompilerUniq0, "#uniq0",  TokenIdFlagsE::CompilerUniq)
SWC_TOKEN_DEF(CompilerUniq1, "#uniq1",  TokenIdFlagsE::CompilerUniq)
SWC_TOKEN_DEF(CompilerUniq2, "#uniq2",  TokenIdFlagsE::CompilerUniq)
SWC_TOKEN_DEF(CompilerUniq3, "#uniq3",  TokenIdFlagsE::CompilerUniq)
SWC_TOKEN_DEF(CompilerUniq4, "#uniq4",  TokenIdFlagsE::CompilerUniq)
SWC_TOKEN_DEF(CompilerUniq5, "#uniq5",  TokenIdFlagsE::CompilerUniq)
SWC_TOKEN_DEF(CompilerUniq6, "#uniq6",  TokenIdFlagsE::CompilerUniq)
SWC_TOKEN_DEF(CompilerUniq7, "#uniq7",  TokenIdFlagsE::CompilerUniq)
SWC_TOKEN_DEF(CompilerUniq8, "#uniq8",  TokenIdFlagsE::CompilerUniq)
SWC_TOKEN_DEF(CompilerUniq9, "#uniq9",  TokenIdFlagsE::CompilerUniq)

// COMPILER INFO

SWC_TOKEN_DEF(CompilerBuildCfg, "#cfg",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerOs, "#os",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerArch, "#arch",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerCpu, "#cpu",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerBackend, "#backend",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerModule, "#module",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerFile, "#file",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerLine, "#line",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerScopeName, "#scopename",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerCurLocation, "#curlocation",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerCallerLocation, "#callerlocation",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerCallerFunction, "#callerfunction",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerSwcVersion, "#swcversion",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerSwcRevision, "#swcrevision",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerSwcBuildNum, "#swcbuildnum",  TokenIdFlagsE::Compiler)
SWC_TOKEN_DEF(CompilerSwagOs, "#swagos",  TokenIdFlagsE::Compiler)

// COMPILER INTROSPECTION

SWC_TOKEN_DEF(CompilerDefined, "#defined",  TokenIdFlagsE::CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerOffsetOf, "#offsetof",  TokenIdFlagsE::CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerAlignOf, "#alignof",  TokenIdFlagsE::CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerSizeOf, "#sizeof",  TokenIdFlagsE::CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerTypeOf, "#typeof",  TokenIdFlagsE::CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerKindOf, "#kindof",  TokenIdFlagsE::CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerStringOf, "#stringof",  TokenIdFlagsE::CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerNameOf, "#nameof",  TokenIdFlagsE::CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerFullNameOf, "#fullnameof",  TokenIdFlagsE::CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerIsConstExpr, "#isconstexpr",  TokenIdFlagsE::CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerLocation, "#location",  TokenIdFlagsE::CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerDeclType, "#decltype",  TokenIdFlagsE::CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerHasTag, "#hastag",  TokenIdFlagsE::CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerGetTag, "#gettag",  TokenIdFlagsE::CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerRunes, "#runes",  TokenIdFlagsE::CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerSafety, "#safety",  TokenIdFlagsE::CompilerIntrinsicReturn)

// INTRINSICS - STRING/TYPE

SWC_TOKEN_DEF(IntrinsicStringCmp, "@stringcmp",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicTypeCmp, "@typecmp",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicIs, "@is",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicAs, "@as",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicGetContext, "@getcontext",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicCompiler, "@compiler",  TokenIdFlagsE::IntrinsicReturn)

SWC_TOKEN_DEF(IntrinsicSetContext, "@setcontext",  TokenIdFlagsE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicPrint, "@print",  TokenIdFlagsE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicCompilerError, "@compilererror",  TokenIdFlagsE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicCompilerWarning, "@compilerwarning",  TokenIdFlagsE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicBcBreakpoint, "@breakpoint",  TokenIdFlagsE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicAssert, "@assert",  TokenIdFlagsE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicPanic, "@panic",  TokenIdFlagsE::Intrinsic)

// INTRINSICS - LIFECYCLE

SWC_TOKEN_DEF(IntrinsicInit, "@init",  TokenIdFlagsE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicDrop, "@drop",  TokenIdFlagsE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicPostMove, "@postmove",  TokenIdFlagsE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicPostCopy, "@postcopy",  TokenIdFlagsE::Intrinsic)

// INTRINSICS - TYPE INFO

SWC_TOKEN_DEF(IntrinsicKindOf, "@kindof",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicCountOf, "@countof",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicDataOf, "@dataof",  TokenIdFlagsE::IntrinsicReturn)

// INTRINSICS - CONSTRUCTORS

SWC_TOKEN_DEF(IntrinsicMakeSlice, "@mkslice",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicMakeString, "@mkstring",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicMakeAny, "@mkany",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicMakeInterface, "@mkinterface",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicMakeCallback, "@mkcallback",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicTableOf, "@tableof",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicDbgAlloc, "@dbgalloc",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicSysAlloc, "@sysalloc",  TokenIdFlagsE::IntrinsicReturn)

// INTRINSICS - RUNTIME

SWC_TOKEN_DEF(IntrinsicErr, "@err",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicArgs, "@args",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicByteCode, "@bytecode",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicIndex, "@index",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicRtFlags, "@rtflags",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicProcessInfos, "@pinfos",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicModules, "@modules",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicGvtd, "@gvtd",  TokenIdFlagsE::IntrinsicReturn)

// INTRINSICS - BIT OPERATIONS

SWC_TOKEN_DEF(IntrinsicByteSwap, "@byteswap",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicBitCountNz, "@bitcountnz",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicBitCountTz, "@bitcounttz",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicBitCountLz, "@bitcountlz",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicRol, "@rol",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicRor, "@ror",  TokenIdFlagsE::IntrinsicReturn)

// INTRINSICS - MATH

SWC_TOKEN_DEF(IntrinsicMin, "@min",  TokenIdFlagsE::PureIntrinsic) 
SWC_TOKEN_DEF(IntrinsicMax, "@max",  TokenIdFlagsE::PureIntrinsic) 
SWC_TOKEN_DEF(IntrinsicSqrt, "@sqrt",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicSin, "@sin",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicCos, "@cos",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicTan, "@tan",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicSinh, "@sinh",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicCosh, "@cosh",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicTanh, "@tanh",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicASin, "@asin",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicACos, "@acos",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicATan, "@atan",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicATan2, "@atan2",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicLog, "@log",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicLog2, "@log2",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicLog10, "@log10",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicFloor, "@floor",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicCeil, "@ceil",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicTrunc, "@trunc",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicRound, "@round",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicAbs, "@abs",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicExp, "@exp",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicExp2, "@exp2",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicPow, "@pow",  TokenIdFlagsE::PureIntrinsic)
SWC_TOKEN_DEF(IntrinsicMulAdd, "@muladd",  TokenIdFlagsE::PureIntrinsic)

// INTRINSICS - MEMORY

SWC_TOKEN_DEF(IntrinsicFree, "@free",  TokenIdFlagsE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicMemCpy, "@memcpy",  TokenIdFlagsE::Intrinsic) 
SWC_TOKEN_DEF(IntrinsicMemMove, "@memmove",  TokenIdFlagsE::Intrinsic)
SWC_TOKEN_DEF(IntrinsicMemSet, "@memset",  TokenIdFlagsE::Intrinsic)

SWC_TOKEN_DEF(IntrinsicAlloc, "@alloc",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicRealloc, "@realloc",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicMemCmp, "@memcmp",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicStrLen, "@strlen",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicStrCmp, "@strcmp",  TokenIdFlagsE::IntrinsicReturn)

// INTRINSICS - ATOMIC

SWC_TOKEN_DEF(IntrinsicAtomicAdd, "@atomadd",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicAtomicAnd, "@atomand",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicAtomicOr, "@atomor",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicAtomicXor, "@atomxor",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicAtomicXchg, "@atomxchg",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicAtomicCmpXchg, "@atomcmpxchg",  TokenIdFlagsE::IntrinsicReturn)

// INTRINSICS - VARARGS

SWC_TOKEN_DEF(IntrinsicCVaStart, "@cvastart",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicCVaEnd, "@cvaend",  TokenIdFlagsE::IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicCVaArg, "@cvaarg",  TokenIdFlagsE::IntrinsicReturn)

// NATIVE TYPES

SWC_TOKEN_DEF(TypeAny, "any",  TokenIdFlagsE::Type)
SWC_TOKEN_DEF(TypeVoid, "void",  TokenIdFlagsE::Type)
SWC_TOKEN_DEF(TypeRune, "rune",  TokenIdFlagsE::Type)
SWC_TOKEN_DEF(TypeF32, "f32",  TokenIdFlagsE::Type)
SWC_TOKEN_DEF(TypeF64, "f64",  TokenIdFlagsE::Type)
SWC_TOKEN_DEF(TypeS8, "s8",  TokenIdFlagsE::Type)
SWC_TOKEN_DEF(TypeS16, "s16",  TokenIdFlagsE::Type)
SWC_TOKEN_DEF(TypeS32, "s32",  TokenIdFlagsE::Type)
SWC_TOKEN_DEF(TypeS64, "s64",  TokenIdFlagsE::Type)
SWC_TOKEN_DEF(TypeU8, "u8",  TokenIdFlagsE::Type)
SWC_TOKEN_DEF(TypeU16, "u16",  TokenIdFlagsE::Type)
SWC_TOKEN_DEF(TypeU32, "u32",  TokenIdFlagsE::Type)
SWC_TOKEN_DEF(TypeU64, "u64",  TokenIdFlagsE::Type)
SWC_TOKEN_DEF(TypeBool, "bool",  TokenIdFlagsE::Type)
SWC_TOKEN_DEF(TypeString, "string",  TokenIdFlagsE::Type)
SWC_TOKEN_DEF(TypeCString, "cstring",  TokenIdFlagsE::Type)
SWC_TOKEN_DEF(TypeTypeInfo, "typeinfo",  TokenIdFlagsE::Type)
SWC_TOKEN_DEF(TypeCVarArgs, "cvarargs",  TokenIdFlagsE::Type)


