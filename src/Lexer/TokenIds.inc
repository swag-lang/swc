SWC_TOKEN_DEF(Invalid,                   SWC_ARITY_NONE)
SWC_TOKEN_DEF(Blank,                     SWC_ARITY_NONE)
SWC_TOKEN_DEF(EndOfLine,                 SWC_ARITY_NONE)
SWC_TOKEN_DEF(EndOfFile,                 SWC_ARITY_NONE)

// Comments
SWC_TOKEN_DEF(CommentLine,               SWC_ARITY_NONE)
SWC_TOKEN_DEF(CommentMultiLine,          SWC_ARITY_NONE)

// String literal
SWC_TOKEN_DEF(StringLine,                SWC_ARITY_NONE)
SWC_TOKEN_DEF(StringRaw,                 SWC_ARITY_NONE)
SWC_TOKEN_DEF(StringMultiLine,           SWC_ARITY_NONE)

// Character literal
SWC_TOKEN_DEF(Character,                 SWC_ARITY_NONE)

// Number literal
SWC_TOKEN_DEF(NumberHexadecimal,         SWC_ARITY_NONE)
SWC_TOKEN_DEF(NumberBinary,              SWC_ARITY_NONE)
SWC_TOKEN_DEF(NumberInteger,             SWC_ARITY_NONE)
SWC_TOKEN_DEF(NumberFloat,               SWC_ARITY_NONE)

// Identifier
SWC_TOKEN_DEF(Identifier,                SWC_ARITY_NONE)

// Operators
SWC_TOKEN_DEF(OpQuote,                   SWC_ARITY_NONE)
SWC_TOKEN_DEF(OpBackSlash,               SWC_ARITY_NONE)
SWC_TOKEN_DEF(OpLeftParen,               SWC_ARITY_NONE)
SWC_TOKEN_DEF(OpRightParen,              SWC_ARITY_NONE)
SWC_TOKEN_DEF(OpLeftSquare,              SWC_ARITY_NONE)
SWC_TOKEN_DEF(OpRightSquare,             SWC_ARITY_NONE)
SWC_TOKEN_DEF(OpLeftCurly,               SWC_ARITY_NONE)
SWC_TOKEN_DEF(OpRightCurly,              SWC_ARITY_NONE)
SWC_TOKEN_DEF(OpSemiColon,               SWC_ARITY_NONE)
SWC_TOKEN_DEF(OpComma,                   SWC_ARITY_NONE)
SWC_TOKEN_DEF(OpAt,                      SWC_ARITY_NONE)
SWC_TOKEN_DEF(OpQuestion,                SWC_ARITY_NONE)
SWC_TOKEN_DEF(OpTilde,                   SWC_ARITY_ONE)   // ~x
SWC_TOKEN_DEF(OpEqual,                   SWC_ARITY_TWO)   // a = b
SWC_TOKEN_DEF(OpEqualEqual,              SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpEqualGreater,            SWC_ARITY_TWO)   // a => b (arrow-like)
SWC_TOKEN_DEF(OpColon,                   SWC_ARITY_NONE)
SWC_TOKEN_DEF(OpExclamation,             SWC_ARITY_ONE)   // !x
SWC_TOKEN_DEF(OpExclamationEqual,        SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpMinus,                   SWC_ARITY_MANY)  // unary/binary
SWC_TOKEN_DEF(OpMinusEqual,              SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpMinusGreater,            SWC_ARITY_TWO)   // a -> b
SWC_TOKEN_DEF(OpMinusMinus,              SWC_ARITY_ONE)   // --x / x--
SWC_TOKEN_DEF(OpPlus,                    SWC_ARITY_MANY)  // unary/binary
SWC_TOKEN_DEF(OpPlusEqual,               SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpPlusPlus,                SWC_ARITY_ONE)   // ++x / x++
SWC_TOKEN_DEF(OpAsterisk,                SWC_ARITY_MANY)  // *a, a*b
SWC_TOKEN_DEF(OpAsteriskEqual,           SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpSlash,                   SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpSlashEqual,              SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpAmpersand,               SWC_ARITY_MANY)  // &a, a&b
SWC_TOKEN_DEF(OpAmpersandEqual,          SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpAmpersandAmpersand,      SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpVertical,                SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpVerticalEqual,           SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpVerticalVertical,        SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpCircumflex,              SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpCircumflexEqual,         SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpPercent,                 SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpPercentEqual,            SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpDot,                     SWC_ARITY_TWO)   // a.b
SWC_TOKEN_DEF(OpDotDot,                  SWC_ARITY_TWO)   // a..b
SWC_TOKEN_DEF(OpDotDotDot,               SWC_ARITY_MANY)  // ...
SWC_TOKEN_DEF(OpLower,                   SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpLowerEqual,              SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpLowerEqualGreater,       SWC_ARITY_TWO)   // <=> (spaceship)
SWC_TOKEN_DEF(OpLowerLower,              SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpLowerLowerEqual,         SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpGreater,                 SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpGreaterEqual,            SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpGreaterGreater,          SWC_ARITY_TWO)
SWC_TOKEN_DEF(OpGreaterGreaterEqual,     SWC_ARITY_TWO)

// Control flow
SWC_TOKEN_DEF(KwdIf,                     SWC_ARITY_MANY)  // cond + then (+ else)
SWC_TOKEN_DEF(KwdElse,                   SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdElif,                   SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdFor,                    SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdWhile,                  SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdSwitch,                 SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdDefer,                  SWC_ARITY_ONE)   // body
SWC_TOKEN_DEF(KwdForeach,                SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdWhere,                  SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdVerify,                 SWC_ARITY_ONE)
SWC_TOKEN_DEF(KwdBreak,                  SWC_ARITY_NONE)
SWC_TOKEN_DEF(KwdFallthrough,            SWC_ARITY_NONE)
SWC_TOKEN_DEF(KwdUnreachable,            SWC_ARITY_NONE)
SWC_TOKEN_DEF(KwdReturn,                 SWC_ARITY_MANY)  // () or (expr)
SWC_TOKEN_DEF(KwdCase,                   SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdContinue,               SWC_ARITY_NONE)
SWC_TOKEN_DEF(KwdDefault,                SWC_ARITY_MANY)

// Logical keyword ops
SWC_TOKEN_DEF(KwdAnd,                    SWC_ARITY_TWO)
SWC_TOKEN_DEF(KwdOr,                     SWC_ARITY_TWO)
SWC_TOKEN_DEF(KwdOrElse,                 SWC_ARITY_TWO)

// Range/iteration
SWC_TOKEN_DEF(KwdTo,                     SWC_ARITY_TWO)
SWC_TOKEN_DEF(KwdUntil,                  SWC_ARITY_TWO)
SWC_TOKEN_DEF(KwdIn,                     SWC_ARITY_TWO)
SWC_TOKEN_DEF(KwdAs,                     SWC_ARITY_TWO)
SWC_TOKEN_DEF(KwdIs,                     SWC_ARITY_TWO)
SWC_TOKEN_DEF(KwdDo,                     SWC_ARITY_MANY)

// Module/error handling
SWC_TOKEN_DEF(KwdUsing,                  SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdWith,                   SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdCast,                   SWC_ARITY_TWO)   // (expr, type)
SWC_TOKEN_DEF(KwdDRef,                   SWC_ARITY_ONE)
SWC_TOKEN_DEF(KwdRetVal,                 SWC_ARITY_ONE)
SWC_TOKEN_DEF(KwdTry,                    SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdTryCatch,               SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdCatch,                  SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdAssume,                 SWC_ARITY_ONE)
SWC_TOKEN_DEF(KwdThrow,                  SWC_ARITY_ONE)
SWC_TOKEN_DEF(KwdDiscard,                SWC_ARITY_ONE)

// Literals
SWC_TOKEN_DEF(KwdTrue,                   SWC_ARITY_NONE)
SWC_TOKEN_DEF(KwdFalse,                  SWC_ARITY_NONE)
SWC_TOKEN_DEF(KwdNull,                   SWC_ARITY_NONE)
SWC_TOKEN_DEF(KwdUndefined,              SWC_ARITY_NONE)

// Access modifiers
SWC_TOKEN_DEF(KwdPublic,                 SWC_ARITY_ONE)
SWC_TOKEN_DEF(KwdInternal,               SWC_ARITY_ONE)
SWC_TOKEN_DEF(KwdPrivate,                SWC_ARITY_ONE)

// Type definitions
SWC_TOKEN_DEF(KwdEnum,                   SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdStruct,                 SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdUnion,                  SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdImpl,                   SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdInterface,              SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdFunc,                   SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdMtd,                    SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdNamespace,              SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdAlias,                  SWC_ARITY_TWO)   // name, target
SWC_TOKEN_DEF(KwdAttr,                   SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdVar,                    SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdLet,                    SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdConst,                  SWC_ARITY_MANY)
SWC_TOKEN_DEF(KwdMoveRef,                SWC_ARITY_ONE)

// Reserved
SWC_TOKEN_DEF(KwdNot,                    SWC_ARITY_ONE)

// Compiler directives
SWC_TOKEN_DEF(CompilerGlobal,            SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerRun,               SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerAst,               SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerFuncTest,          SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerFuncInit,          SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerFuncDrop,          SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerFuncMain,          SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerFuncPreMain,       SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerFuncMessage,       SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerDependencies,      SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerInclude,           SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerLoad,              SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerAssert,            SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerPrint,             SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerError,             SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerWarning,           SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerForeignLib,        SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerImport,            SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerInject,            SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerMacro,             SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerIf,                SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerElse,              SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerElseIf,            SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerCode,              SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerScope,             SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerUp,                SWC_ARITY_MANY)
SWC_TOKEN_DEF(CompilerType,              SWC_ARITY_MANY)

// Modifiers
SWC_TOKEN_DEF(ModifierPromote,           SWC_ARITY_ONE)
SWC_TOKEN_DEF(ModifierWrap,              SWC_ARITY_ONE)
SWC_TOKEN_DEF(ModifierNoDrop,            SWC_ARITY_ONE)
SWC_TOKEN_DEF(ModifierMove,              SWC_ARITY_ONE)
SWC_TOKEN_DEF(ModifierMoveRaw,           SWC_ARITY_ONE)
SWC_TOKEN_DEF(ModifierReverse,           SWC_ARITY_ONE)
SWC_TOKEN_DEF(ModifierRef,               SWC_ARITY_ONE)
SWC_TOKEN_DEF(ModifierConstRef,          SWC_ARITY_ONE)
SWC_TOKEN_DEF(ModifierNullable,          SWC_ARITY_ONE)
SWC_TOKEN_DEF(ModifierErr,               SWC_ARITY_ONE)
SWC_TOKEN_DEF(ModifierNoErr,             SWC_ARITY_ONE)
SWC_TOKEN_DEF(ModifierBit,               SWC_ARITY_ONE)
SWC_TOKEN_DEF(ModifierUnConst,           SWC_ARITY_ONE)

// Compiler info
SWC_TOKEN_DEF(CompilerBuildCfg,          SWC_ARITY_NONE)
SWC_TOKEN_DEF(CompilerOs,                SWC_ARITY_NONE)
SWC_TOKEN_DEF(CompilerArch,              SWC_ARITY_NONE)
SWC_TOKEN_DEF(CompilerCpu,               SWC_ARITY_NONE)
SWC_TOKEN_DEF(CompilerBackend,           SWC_ARITY_NONE)
SWC_TOKEN_DEF(CompilerModule,            SWC_ARITY_NONE)
SWC_TOKEN_DEF(CompilerFile,              SWC_ARITY_NONE)
SWC_TOKEN_DEF(CompilerLine,              SWC_ARITY_NONE)
SWC_TOKEN_DEF(CompilerScopeName,         SWC_ARITY_NONE)
SWC_TOKEN_DEF(CompilerCurLocation,       SWC_ARITY_NONE)
SWC_TOKEN_DEF(CompilerCallerLocation,    SWC_ARITY_NONE)
SWC_TOKEN_DEF(CompilerCallerFunction,    SWC_ARITY_NONE)
SWC_TOKEN_DEF(CompilerBuildVersion,      SWC_ARITY_NONE)
SWC_TOKEN_DEF(CompilerBuildRevision,     SWC_ARITY_NONE)
SWC_TOKEN_DEF(CompilerBuildNum,          SWC_ARITY_NONE)
SWC_TOKEN_DEF(CompilerSwagOs,            SWC_ARITY_NONE)

// Compiler introspection
SWC_TOKEN_DEF(CompilerDefined,           SWC_ARITY_ONE)
SWC_TOKEN_DEF(CompilerOffsetOf,          SWC_ARITY_TWO)
SWC_TOKEN_DEF(CompilerAlignOf,           SWC_ARITY_ONE)
SWC_TOKEN_DEF(CompilerSizeOf,            SWC_ARITY_ONE)
SWC_TOKEN_DEF(CompilerTypeOf,            SWC_ARITY_ONE)
SWC_TOKEN_DEF(CompilerStringOf,          SWC_ARITY_ONE)
SWC_TOKEN_DEF(CompilerNameOf,            SWC_ARITY_ONE)
SWC_TOKEN_DEF(CompilerIsConstExpr,       SWC_ARITY_ONE)
SWC_TOKEN_DEF(CompilerLocation,          SWC_ARITY_NONE)
SWC_TOKEN_DEF(CompilerDeclType,          SWC_ARITY_ONE)
SWC_TOKEN_DEF(CompilerHasTag,            SWC_ARITY_TWO)
SWC_TOKEN_DEF(CompilerGetTag,            SWC_ARITY_TWO)
SWC_TOKEN_DEF(CompilerRunes,             SWC_ARITY_ONE)
SWC_TOKEN_DEF(CompilerSafety,            SWC_ARITY_NONE)

// Intrinsics - string/type
SWC_TOKEN_DEF(IntrinsicStringCmp,        SWC_ARITY_TWO)
SWC_TOKEN_DEF(IntrinsicTypeCmp,          SWC_ARITY_TWO)
SWC_TOKEN_DEF(IntrinsicIs,               SWC_ARITY_TWO)
SWC_TOKEN_DEF(IntrinsicAs,               SWC_ARITY_TWO)
SWC_TOKEN_DEF(IntrinsicGetContext,       SWC_ARITY_NONE)
SWC_TOKEN_DEF(IntrinsicSetContext,       SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicCompiler,         SWC_ARITY_NONE)
SWC_TOKEN_DEF(IntrinsicPrint,            SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicCompilerError,    SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicCompilerWarning,  SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicBcBreakpoint,     SWC_ARITY_NONE)
SWC_TOKEN_DEF(IntrinsicAssert,           SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicPanic,            SWC_ARITY_MANY)

// Intrinsics - lifecycle
SWC_TOKEN_DEF(IntrinsicInit,             SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicDrop,             SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicPostMove,         SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicPostCopy,         SWC_ARITY_ONE)

// Intrinsics - type info
SWC_TOKEN_DEF(IntrinsicKindOf,           SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicCountOf,          SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicDataOf,           SWC_ARITY_ONE)

// Intrinsics - constructors
SWC_TOKEN_DEF(IntrinsicMakeSlice,        SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicMakeString,       SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicMakeAny,          SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicMakeInterface,    SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicMakeCallback,     SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicTableOf,          SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicDbgAlloc,         SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicSysAlloc,         SWC_ARITY_MANY)

// Intrinsics - runtime
SWC_TOKEN_DEF(IntrinsicGetErr,           SWC_ARITY_NONE)
SWC_TOKEN_DEF(IntrinsicArguments,        SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicIsByteCode,       SWC_ARITY_NONE)
SWC_TOKEN_DEF(IntrinsicIndex,            SWC_ARITY_TWO)
SWC_TOKEN_DEF(IntrinsicRtFlags,          SWC_ARITY_NONE)
SWC_TOKEN_DEF(IntrinsicGetProcessInfos,  SWC_ARITY_NONE)
SWC_TOKEN_DEF(IntrinsicModules,          SWC_ARITY_NONE)
SWC_TOKEN_DEF(IntrinsicGvtd,             SWC_ARITY_NONE)

// Intrinsics - bit operations
SWC_TOKEN_DEF(IntrinsicByteSwap,         SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicBitCountNz,       SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicBitCountTz,       SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicBitCountLz,       SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicRol,              SWC_ARITY_TWO)
SWC_TOKEN_DEF(IntrinsicRor,              SWC_ARITY_TWO)

// Intrinsics - math
SWC_TOKEN_DEF(IntrinsicMin,              SWC_ARITY_MANY) // often variadic
SWC_TOKEN_DEF(IntrinsicMax,              SWC_ARITY_MANY) // often variadic
SWC_TOKEN_DEF(IntrinsicSqrt,             SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicSin,              SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicCos,              SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicTan,              SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicSinh,             SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicCosh,             SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicTanh,             SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicASin,             SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicACos,             SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicATan,             SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicATan2,            SWC_ARITY_TWO)
SWC_TOKEN_DEF(IntrinsicLog,              SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicLog2,             SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicLog10,            SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicFloor,            SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicCeil,             SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicTrunc,            SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicRound,            SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicAbs,              SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicExp,              SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicExp2,             SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicPow,              SWC_ARITY_TWO)

// Intrinsics - memory
SWC_TOKEN_DEF(IntrinsicAlloc,            SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicRealloc,          SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicFree,             SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicMemCpy,           SWC_ARITY_MANY) // dst, src, size
SWC_TOKEN_DEF(IntrinsicMemMove,          SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicMemSet,           SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicMemCmp,           SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicMulAdd,           SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicStrLen,           SWC_ARITY_ONE)
SWC_TOKEN_DEF(IntrinsicStrCmp,           SWC_ARITY_TWO)

// Intrinsics - atomic
SWC_TOKEN_DEF(IntrinsicAtomicAdd,        SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicAtomicAnd,        SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicAtomicOr,         SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicAtomicXor,        SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicAtomicXchg,       SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicAtomicCmpXchg,    SWC_ARITY_MANY)

// Intrinsics - varargs
SWC_TOKEN_DEF(IntrinsicCVaStart,         SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicCVaEnd,           SWC_ARITY_MANY)
SWC_TOKEN_DEF(IntrinsicCVaArg,           SWC_ARITY_MANY)

// Native types
SWC_TOKEN_DEF(TypeAny,                   SWC_ARITY_NONE)
SWC_TOKEN_DEF(TypeVoid,                  SWC_ARITY_NONE)
SWC_TOKEN_DEF(TypeRune,                  SWC_ARITY_NONE)
SWC_TOKEN_DEF(TypeF32,                   SWC_ARITY_NONE)
SWC_TOKEN_DEF(TypeF64,                   SWC_ARITY_NONE)
SWC_TOKEN_DEF(TypeS8,                    SWC_ARITY_NONE)
SWC_TOKEN_DEF(TypeS16,                   SWC_ARITY_NONE)
SWC_TOKEN_DEF(TypeS32,                   SWC_ARITY_NONE)
SWC_TOKEN_DEF(TypeS64,                   SWC_ARITY_NONE)
SWC_TOKEN_DEF(TypeU8,                    SWC_ARITY_NONE)
SWC_TOKEN_DEF(TypeU16,                   SWC_ARITY_NONE)
SWC_TOKEN_DEF(TypeU32,                   SWC_ARITY_NONE)
SWC_TOKEN_DEF(TypeU64,                   SWC_ARITY_NONE)
SWC_TOKEN_DEF(TypeBool,                  SWC_ARITY_NONE)
SWC_TOKEN_DEF(TypeString,                SWC_ARITY_NONE)
SWC_TOKEN_DEF(TypeCString,               SWC_ARITY_NONE)
SWC_TOKEN_DEF(TypeTypeInfo,              SWC_ARITY_NONE)
SWC_TOKEN_DEF(TypeCVarArgs,              SWC_ARITY_NONE)
