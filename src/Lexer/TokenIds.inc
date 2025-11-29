// TRIVIA

SWC_TOKEN_DEF(Invalid, "",  Zero)

SWC_TOKEN_DEF(Whitespace, "",  Trivia)
SWC_TOKEN_DEF(EndOfFile, "",  Trivia)

SWC_TOKEN_DEF(CommentLine, "",  Trivia)
SWC_TOKEN_DEF(CommentBlock, "",  Trivia)

// LITERALS

SWC_TOKEN_DEF(StringLine, "",  Literal)
SWC_TOKEN_DEF(StringRaw, "",  Literal)
SWC_TOKEN_DEF(StringMultiLine, "",  Literal)

SWC_TOKEN_DEF(Character, "",  Literal)

SWC_TOKEN_DEF(NumberHex, "",  Literal)
SWC_TOKEN_DEF(NumberBin, "",  Literal)
SWC_TOKEN_DEF(NumberInteger, "",  Literal)
SWC_TOKEN_DEF(NumberFloat, "",  Literal)

// IDENTIFIERS

SWC_TOKEN_DEF(Identifier, "",  Zero)
SWC_TOKEN_DEF(SharpIdentifier, "",  Compiler)

SWC_TOKEN_DEF(KwdMe, "me",  Keyword)

SWC_TOKEN_DEF(KwdSkip, "skip",  Zero)
SWC_TOKEN_DEF(KwdSkipFmt, "skipfmt",  Zero)
SWC_TOKEN_DEF(KwdExport, "export",  Zero)
SWC_TOKEN_DEF(KwdGenerated, "generated",  Zero)
SWC_TOKEN_DEF(KwdLocation, "location",  Zero)
SWC_TOKEN_DEF(KwdVersion, "version",  Zero)

// SYMBOLS

SWC_TOKEN_DEF(SymSingleQuote, "'", Symbol)
SWC_TOKEN_DEF(SymBackSlash, "\\", Symbol)
SWC_TOKEN_DEF(SymLeftParen, "(", Symbol)
SWC_TOKEN_DEF(SymRightParen, ")", Symbol)
SWC_TOKEN_DEF(SymLeftBracket, "[", Symbol)
SWC_TOKEN_DEF(SymRightBracket, "]", Symbol)
SWC_TOKEN_DEF(SymLeftCurly, "{", Symbol)
SWC_TOKEN_DEF(SymRightCurly, "}", Symbol)
SWC_TOKEN_DEF(SymSemiColon, ";", Symbol)
SWC_TOKEN_DEF(SymComma, ",", Symbol)
SWC_TOKEN_DEF(SymAt, "@", Symbol)
SWC_TOKEN_DEF(SymQuestion, "?", Symbol)
SWC_TOKEN_DEF(SymTilde, "~", Symbol)
SWC_TOKEN_DEF(SymEqual, "=", Symbol)
SWC_TOKEN_DEF(SymEqualEqual, "==", Symbol)
SWC_TOKEN_DEF(SymEqualGreater, "=>", Symbol)
SWC_TOKEN_DEF(SymColon, ":", Symbol)
SWC_TOKEN_DEF(SymBang, "!", Symbol)
SWC_TOKEN_DEF(SymBangEqual, "!=", Symbol)
SWC_TOKEN_DEF(SymMinus, "-", Symbol)
SWC_TOKEN_DEF(SymMinusEqual, "-=", Symbol)
SWC_TOKEN_DEF(SymMinusGreater, "->", Symbol)
SWC_TOKEN_DEF(SymMinusMinus, "--", Symbol)
SWC_TOKEN_DEF(SymPlus, "+", Symbol)
SWC_TOKEN_DEF(SymPlusEqual, "+=", Symbol)
SWC_TOKEN_DEF(SymPlusPlus, "++", Symbol)
SWC_TOKEN_DEF(SymAsterisk, "*", Symbol)
SWC_TOKEN_DEF(SymAsteriskEqual, "*=", Symbol)
SWC_TOKEN_DEF(SymSlash, "/", Symbol)
SWC_TOKEN_DEF(SymSlashEqual, "/=", Symbol)
SWC_TOKEN_DEF(SymAmpersand, "&", Symbol)
SWC_TOKEN_DEF(SymAmpersandEqual, "&=", Symbol)
SWC_TOKEN_DEF(SymAmpersandAmpersand, "&&", Symbol)
SWC_TOKEN_DEF(SymPipe, "|", Symbol)
SWC_TOKEN_DEF(SymPipeEqual, "|=", Symbol)
SWC_TOKEN_DEF(SymPipePipe, "||", Symbol)
SWC_TOKEN_DEF(SymCircumflex, "^", Symbol)
SWC_TOKEN_DEF(SymCircumflexEqual, "^=", Symbol)
SWC_TOKEN_DEF(SymPercent, "%", Symbol)
SWC_TOKEN_DEF(SymPercentEqual, "%=", Symbol)
SWC_TOKEN_DEF(SymDot, ".", Symbol)
SWC_TOKEN_DEF(SymDotDot, "..", Symbol)
SWC_TOKEN_DEF(SymDotDotDot, "...", Symbol)
SWC_TOKEN_DEF(SymLess, "<", Symbol)
SWC_TOKEN_DEF(SymLessEqual, "<=", Symbol)
SWC_TOKEN_DEF(SymLessEqualGreater, "<=>", Symbol)
SWC_TOKEN_DEF(SymLessLower, "<<", Symbol)
SWC_TOKEN_DEF(SymLessLowerEqual, "<<=", Symbol)
SWC_TOKEN_DEF(SymGreater, ">", Symbol)
SWC_TOKEN_DEF(SymGreaterEqual, ">=", Symbol)
SWC_TOKEN_DEF(SymGreaterGreater, ">>", Symbol)
SWC_TOKEN_DEF(SymGreaterGreaterEqual, ">>=", Symbol)
SWC_TOKEN_DEF(SymAttrStart, "#[", Symbol)

// CONTROL FLOW KEYWORDS

SWC_TOKEN_DEF(KwdIf, "if",  KeywordLogic)
SWC_TOKEN_DEF(KwdElse, "else",  KeywordLogic)
SWC_TOKEN_DEF(KwdElseIf, "elif",  KeywordLogic)
SWC_TOKEN_DEF(KwdFor, "for",  KeywordLogic)
SWC_TOKEN_DEF(KwdWhile, "while",  KeywordLogic)
SWC_TOKEN_DEF(KwdSwitch, "switch",  KeywordLogic)
SWC_TOKEN_DEF(KwdDefer, "defer",  KeywordHasMode)
SWC_TOKEN_DEF(KwdForeach, "foreach",  KeywordHasMode)
SWC_TOKEN_DEF(KwdWhere, "where",  KeywordHasMode)
SWC_TOKEN_DEF(KwdVerify, "verify",  KeywordHasMode)
SWC_TOKEN_DEF(KwdBreak, "break",  KeywordLogic)
SWC_TOKEN_DEF(KwdFallThrough, "fallthrough",  KeywordLogic)
SWC_TOKEN_DEF(KwdUnreachable, "unreachable",  KeywordLogic)
SWC_TOKEN_DEF(KwdReturn, "return",  KeywordLogic)
SWC_TOKEN_DEF(KwdCase, "case",  KeywordLogic)
SWC_TOKEN_DEF(KwdContinue, "continue",  KeywordLogic)
SWC_TOKEN_DEF(KwdDefault, "default",  KeywordLogic)

SWC_TOKEN_DEF(KwdAnd, "and",  KeywordLogic)
SWC_TOKEN_DEF(KwdOr, "or",  KeywordLogic)
SWC_TOKEN_DEF(KwdOrElse, "orelse",  KeywordLogic)

SWC_TOKEN_DEF(KwdTo, "to",  KeywordLogic)
SWC_TOKEN_DEF(KwdUntil, "until",  KeywordLogic)
SWC_TOKEN_DEF(KwdIn, "in",  KeywordLogic)
SWC_TOKEN_DEF(KwdAs, "as",  KeywordLogic)
SWC_TOKEN_DEF(KwdIs, "is",  KeywordLogic)
SWC_TOKEN_DEF(KwdDo, "do",  KeywordLogic)

// MODULE / ERROR HANDLING

SWC_TOKEN_DEF(KwdUsing, "using",  Keyword)
SWC_TOKEN_DEF(KwdWith, "with",  Keyword)
SWC_TOKEN_DEF(KwdCast, "cast",  Keyword) 
SWC_TOKEN_DEF(KwdDRef, "dref",  Keyword)
SWC_TOKEN_DEF(KwdRetVal, "retval",  Keyword)
SWC_TOKEN_DEF(KwdTry, "try",  Keyword)
SWC_TOKEN_DEF(KwdTryCatch, "trycatch",  Keyword)
SWC_TOKEN_DEF(KwdCatch, "catch",  Keyword)
SWC_TOKEN_DEF(KwdAssume, "assume",  Keyword)
SWC_TOKEN_DEF(KwdThrow, "throw",  Keyword)
SWC_TOKEN_DEF(KwdDiscard, "discard",  Keyword)

// LITERAL KEYWORDS

SWC_TOKEN_DEF(KwdTrue, "true",  Keyword)
SWC_TOKEN_DEF(KwdFalse, "false",  Keyword)
SWC_TOKEN_DEF(KwdNull, "null",  Keyword)
SWC_TOKEN_DEF(KwdUndefined, "undefined",  Keyword)

// ACCESS MODIFIERS

SWC_TOKEN_DEF(KwdPublic, "public",  Keyword)
SWC_TOKEN_DEF(KwdInternal, "internal",  Keyword)
SWC_TOKEN_DEF(KwdPrivate, "private",  Keyword)

// TYPE DEFINITIONS

SWC_TOKEN_DEF(KwdEnum, "enum",  Keyword)
SWC_TOKEN_DEF(KwdStruct, "struct",  Keyword)
SWC_TOKEN_DEF(KwdUnion, "union",  Keyword)
SWC_TOKEN_DEF(KwdImpl, "impl",  Keyword)
SWC_TOKEN_DEF(KwdInterface, "interface",  Keyword)
SWC_TOKEN_DEF(KwdFunc, "func",  Keyword)
SWC_TOKEN_DEF(KwdMtd, "mtd",  Keyword)
SWC_TOKEN_DEF(KwdNamespace, "namespace",  Keyword)
SWC_TOKEN_DEF(KwdAlias, "alias",  Keyword) 
SWC_TOKEN_DEF(KwdAttr, "attr",  Keyword)
SWC_TOKEN_DEF(KwdVar, "var",  Keyword)
SWC_TOKEN_DEF(KwdLet, "let",  Keyword)
SWC_TOKEN_DEF(KwdConst, "const",  Keyword)
SWC_TOKEN_DEF(KwdMoveRef, "moveref",  Keyword)

// RESERVED

SWC_TOKEN_DEF(KwdNot, "not",  Reserved)

// COMPILER FUNC

SWC_TOKEN_DEF(CompilerGlobal, "#global",  Compiler)
SWC_TOKEN_DEF(CompilerRun, "#run",  CompilerFunc)
SWC_TOKEN_DEF(CompilerAst, "#ast",  CompilerFunc)
SWC_TOKEN_DEF(CompilerFuncTest, "#test",  CompilerFunc)
SWC_TOKEN_DEF(CompilerFuncInit, "#init",  CompilerFunc)
SWC_TOKEN_DEF(CompilerFuncDrop, "#drop",  CompilerFunc)
SWC_TOKEN_DEF(CompilerFuncMain, "#main",  CompilerFunc)
SWC_TOKEN_DEF(CompilerFuncPreMain, "#premain",  CompilerFunc)
SWC_TOKEN_DEF(CompilerFuncMessage, "#message",  CompilerFunc)
SWC_TOKEN_DEF(CompilerDependencies, "#dependencies",  CompilerFunc)
SWC_TOKEN_DEF(CompilerInclude, "#include",  CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerLoad, "#load",  Compiler)
SWC_TOKEN_DEF(CompilerAssert, "#assert",  Compiler)
SWC_TOKEN_DEF(CompilerPrint, "#print",  Compiler)
SWC_TOKEN_DEF(CompilerError, "#error",  Compiler)
SWC_TOKEN_DEF(CompilerWarning, "#warning",  Compiler)
SWC_TOKEN_DEF(CompilerForeignLib, "#foreignlib",  Compiler)
SWC_TOKEN_DEF(CompilerImport, "#import",  Compiler)
SWC_TOKEN_DEF(CompilerInject, "#inject",  Compiler)
SWC_TOKEN_DEF(CompilerMacro, "#macro",  Compiler)
SWC_TOKEN_DEF(CompilerIf, "#if",  Compiler)
SWC_TOKEN_DEF(CompilerElse, "#else",  Compiler)
SWC_TOKEN_DEF(CompilerElseIf, "#elif",  Compiler)
SWC_TOKEN_DEF(CompilerCode, "#code",  CompilerIntrinsic)
SWC_TOKEN_DEF(CompilerScope, "#scope",  Compiler)
SWC_TOKEN_DEF(CompilerUp, "#up",  CompilerIntrinsic)
SWC_TOKEN_DEF(CompilerType, "#type",  CompilerIntrinsic)

// MODIFIERS

SWC_TOKEN_DEF(ModifierPromote, "#prom",  Modifier)
SWC_TOKEN_DEF(ModifierWrap, "#wrap",  Modifier)
SWC_TOKEN_DEF(ModifierNoDrop, "#nodrop",  Modifier)
SWC_TOKEN_DEF(ModifierMove, "#move",  Modifier)
SWC_TOKEN_DEF(ModifierMoveRaw, "#moveraw",  Modifier)
SWC_TOKEN_DEF(ModifierReverse, "#reverse",  Modifier)
SWC_TOKEN_DEF(ModifierRef, "#ref",  Modifier)
SWC_TOKEN_DEF(ModifierConstRef, "#constref",  Modifier)
SWC_TOKEN_DEF(ModifierNullable, "#null",  Modifier)
SWC_TOKEN_DEF(ModifierErr, "#err",  Modifier)
SWC_TOKEN_DEF(ModifierNoErr, "#noerr",  Modifier)
SWC_TOKEN_DEF(ModifierBit, "#bit",  Modifier)
SWC_TOKEN_DEF(ModifierUnConst, "#unconst",  Modifier)

// COMPILER IDENTIFIERS

SWC_TOKEN_DEF(CompilerAlias0, "#alias0",  CompilerAlias)
SWC_TOKEN_DEF(CompilerAlias1, "#alias1",  CompilerAlias)
SWC_TOKEN_DEF(CompilerAlias2, "#alias2",  CompilerAlias)
SWC_TOKEN_DEF(CompilerAlias3, "#alias3",  CompilerAlias)
SWC_TOKEN_DEF(CompilerAlias4, "#alias4",  CompilerAlias)
SWC_TOKEN_DEF(CompilerAlias5, "#alias5",  CompilerAlias)
SWC_TOKEN_DEF(CompilerAlias6, "#alias6",  CompilerAlias)
SWC_TOKEN_DEF(CompilerAlias7, "#alias7",  CompilerAlias)
SWC_TOKEN_DEF(CompilerAlias8, "#alias8",  CompilerAlias)
SWC_TOKEN_DEF(CompilerAlias9, "#alias9",  CompilerAlias)
SWC_TOKEN_DEF(CompilerUniq0, "#uniq0",  CompilerUniq)
SWC_TOKEN_DEF(CompilerUniq1, "#uniq1",  CompilerUniq)
SWC_TOKEN_DEF(CompilerUniq2, "#uniq2",  CompilerUniq)
SWC_TOKEN_DEF(CompilerUniq3, "#uniq3",  CompilerUniq)
SWC_TOKEN_DEF(CompilerUniq4, "#uniq4",  CompilerUniq)
SWC_TOKEN_DEF(CompilerUniq5, "#uniq5",  CompilerUniq)
SWC_TOKEN_DEF(CompilerUniq6, "#uniq6",  CompilerUniq)
SWC_TOKEN_DEF(CompilerUniq7, "#uniq7",  CompilerUniq)
SWC_TOKEN_DEF(CompilerUniq8, "#uniq8",  CompilerUniq)
SWC_TOKEN_DEF(CompilerUniq9, "#uniq9",  CompilerUniq)

// COMPILER INFO

SWC_TOKEN_DEF(CompilerBuildCfg, "#cfg",  Compiler)
SWC_TOKEN_DEF(CompilerOs, "#os",  Compiler)
SWC_TOKEN_DEF(CompilerArch, "#arch",  Compiler)
SWC_TOKEN_DEF(CompilerCpu, "#cpu",  Compiler)
SWC_TOKEN_DEF(CompilerBackend, "#backend",  Compiler)
SWC_TOKEN_DEF(CompilerModule, "#module",  Compiler)
SWC_TOKEN_DEF(CompilerFile, "#file",  Compiler)
SWC_TOKEN_DEF(CompilerLine, "#line",  Compiler)
SWC_TOKEN_DEF(CompilerScopeName, "#scopename",  Compiler)
SWC_TOKEN_DEF(CompilerCurLocation, "#curlocation",  Compiler)
SWC_TOKEN_DEF(CompilerCallerLocation, "#callerlocation",  Compiler)
SWC_TOKEN_DEF(CompilerCallerFunction, "#callerfunction",  Compiler)
SWC_TOKEN_DEF(CompilerBuildVersion, "#swagversion",  Compiler)
SWC_TOKEN_DEF(CompilerBuildRevision, "#swagrevision",  Compiler)
SWC_TOKEN_DEF(CompilerBuildNum, "#swagbuildnum",  Compiler)
SWC_TOKEN_DEF(CompilerSwagOs, "#swagos",  Compiler)

// COMPILER INTROSPECTION

SWC_TOKEN_DEF(CompilerDefined, "#defined",  CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerOffsetOf, "#offsetof",  CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerAlignOf, "#alignof",  CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerSizeOf, "#sizeof",  CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerTypeOf, "#typeof",  CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerStringOf, "#stringof",  CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerNameOf, "#nameof",  CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerIsConstExpr, "#isconstexpr",  CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerLocation, "#location",  CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerDeclType, "#decltype",  CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerHasTag, "#hastag",  CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerGetTag, "#gettag",  CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerRunes, "#runes",  CompilerIntrinsicReturn)
SWC_TOKEN_DEF(CompilerSafety, "#safety",  CompilerIntrinsicReturn)

// INTRINSICS - STRING/TYPE

SWC_TOKEN_DEF(IntrinsicStringCmp, "@stringcmp",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicTypeCmp, "@typecmp",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicIs, "@is",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicAs, "@as",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicGetContext, "@getcontext",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicCompiler, "@compiler",  IntrinsicReturn)

SWC_TOKEN_DEF(IntrinsicSetContext, "@setcontext",  Intrinsic)
SWC_TOKEN_DEF(IntrinsicPrint, "@print",  Intrinsic)
SWC_TOKEN_DEF(IntrinsicCompilerError, "@compilererror",  Intrinsic)
SWC_TOKEN_DEF(IntrinsicCompilerWarning, "@compilerwarning",  Intrinsic)
SWC_TOKEN_DEF(IntrinsicBcBreakpoint, "@breakpoint",  Intrinsic)
SWC_TOKEN_DEF(IntrinsicAssert, "@assert",  Intrinsic)
SWC_TOKEN_DEF(IntrinsicPanic, "@panic",  Intrinsic)

// INTRINSICS - LIFECYCLE

SWC_TOKEN_DEF(IntrinsicInit, "@init",  Intrinsic)
SWC_TOKEN_DEF(IntrinsicDrop, "@drop",  Intrinsic)
SWC_TOKEN_DEF(IntrinsicPostMove, "@postmove",  Intrinsic)
SWC_TOKEN_DEF(IntrinsicPostCopy, "@postcopy",  Intrinsic)

// INTRINSICS - TYPE INFO

SWC_TOKEN_DEF(IntrinsicKindOf, "@kindof",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicCountOf, "@countof",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicDataOf, "@dataof",  IntrinsicReturn)

// INTRINSICS - CONSTRUCTORS

SWC_TOKEN_DEF(IntrinsicMakeSlice, "@mkslice",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicMakeString, "@mkstring",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicMakeAny, "@mkany",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicMakeInterface, "@mkinterface",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicMakeCallback, "@mkcallback",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicTableOf, "@tableof",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicDbgAlloc, "@dbgalloc",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicSysAlloc, "@sysalloc",  IntrinsicReturn)

// INTRINSICS - RUNTIME

SWC_TOKEN_DEF(IntrinsicErr, "@err",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicArgs, "@args",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicByteCode, "@bytecode",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicIndex, "@index",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicRtFlags, "@rtflags",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicProcessInfos, "@pinfos",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicModules, "@modules",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicGvtd, "@gvtd",  IntrinsicReturn)

// INTRINSICS - BIT OPERATIONS

SWC_TOKEN_DEF(IntrinsicByteSwap, "@byteswap",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicBitCountNz, "@bitcountnz",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicBitCountTz, "@bitcounttz",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicBitCountLz, "@bitcountlz",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicRol, "@rol",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicRor, "@ror",  IntrinsicReturn)

// INTRINSICS - MATH

SWC_TOKEN_DEF(IntrinsicMin, "@min",  IntrinsicReturn) 
SWC_TOKEN_DEF(IntrinsicMax, "@max",  IntrinsicReturn) 
SWC_TOKEN_DEF(IntrinsicSqrt, "@sqrt",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicSin, "@sin",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicCos, "@cos",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicTan, "@tan",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicSinh, "@sinh",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicCosh, "@cosh",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicTanh, "@tanh",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicASin, "@asin",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicACos, "@acos",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicATan, "@atan",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicATan2, "@atan2",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicLog, "@log",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicLog2, "@log2",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicLog10, "@log10",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicFloor, "@floor",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicCeil, "@ceil",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicTrunc, "@trunc",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicRound, "@round",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicAbs, "@abs",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicExp, "@exp",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicExp2, "@exp2",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicPow, "@pow",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicMulAdd, "@muladd",  IntrinsicReturn)

// INTRINSICS - MEMORY

SWC_TOKEN_DEF(IntrinsicFree, "@free",  Intrinsic)
SWC_TOKEN_DEF(IntrinsicMemCpy, "@memcpy",  Intrinsic) 
SWC_TOKEN_DEF(IntrinsicMemMove, "@memmove",  Intrinsic)
SWC_TOKEN_DEF(IntrinsicMemSet, "@memset",  Intrinsic)

SWC_TOKEN_DEF(IntrinsicAlloc, "@alloc",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicRealloc, "@realloc",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicMemCmp, "@memcmp",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicStrLen, "@strlen",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicStrCmp, "@strcmp",  IntrinsicReturn)

// INTRINSICS - ATOMIC

SWC_TOKEN_DEF(IntrinsicAtomicAdd, "@atomadd",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicAtomicAnd, "@atomand",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicAtomicOr, "@atomor",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicAtomicXor, "@atomxor",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicAtomicXchg, "@atomxchg",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicAtomicCmpXchg, "@atomcmpxchg",  IntrinsicReturn)

// INTRINSICS - VARARGS

SWC_TOKEN_DEF(IntrinsicCVaStart, "@cvastart",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicCVaEnd, "@cvaend",  IntrinsicReturn)
SWC_TOKEN_DEF(IntrinsicCVaArg, "@cvaarg",  IntrinsicReturn)

// NATIVE TYPES

SWC_TOKEN_DEF(TypeAny, "any",  Type)
SWC_TOKEN_DEF(TypeVoid, "void",  Type)
SWC_TOKEN_DEF(TypeRune, "rune",  Type)
SWC_TOKEN_DEF(TypeF32, "f32",  Type)
SWC_TOKEN_DEF(TypeF64, "f64",  Type)
SWC_TOKEN_DEF(TypeS8, "s8",  Type)
SWC_TOKEN_DEF(TypeS16, "s16",  Type)
SWC_TOKEN_DEF(TypeS32, "s32",  Type)
SWC_TOKEN_DEF(TypeS64, "s64",  Type)
SWC_TOKEN_DEF(TypeU8, "u8",  Type)
SWC_TOKEN_DEF(TypeU16, "u16",  Type)
SWC_TOKEN_DEF(TypeU32, "u32",  Type)
SWC_TOKEN_DEF(TypeU64, "u64",  Type)
SWC_TOKEN_DEF(TypeBool, "bool",  Type)
SWC_TOKEN_DEF(TypeString, "string",  Type)
SWC_TOKEN_DEF(TypeCString, "cstring",  Type)
SWC_TOKEN_DEF(TypeTypeInfo, "typeinfo",  Type)
SWC_TOKEN_DEF(TypeCVarArgs, "cvarargs",  Type)
