#pragma once

SWC_BEGIN_NAMESPACE();

class SourceFile;

enum class TokenId : uint16_t
{
    Invalid,
    Blank,
    EndOfLine,
    EndOfFile,

    // Comments
    CommentLine,
    CommentMultiLine,

    // String literal
    StringLine,
    StringRaw,
    StringMultiLine,

    // Character literal
    Character,

    // Number literal
    NumberHexadecimal,
    NumberBinary,
    NumberInteger,
    NumberFloat,

    // Identifier
    Identifier,

    // Operators
    OpQuote,
    OpBackSlash,
    OpLeftParen,
    OpRightParen,
    OpLeftSquare,
    OpRightSquare,
    OpLeftCurly,
    OpRightCurly,
    OpSemiColon,
    OpComma,
    OpAt,
    OpQuestion,
    OpTilde,
    OpEqual,
    OpEqualEqual,
    OpEqualGreater,
    OpColon,
    OpExclamation,
    OpExclamationEqual,
    OpMinus,
    OpMinusEqual,
    OpMinusGreater,
    OpMinusMinus,
    OpPlus,
    OpPlusEqual,
    OpPlusPlus,
    OpAsterisk,
    OpAsteriskEqual,
    OpSlash,
    OpSlashEqual,
    OpAmpersand,
    OpAmpersandEqual,
    OpAmpersandAmpersand,
    OpVertical,
    OpVerticalEqual,
    OpVerticalVertical,
    OpCircumflex,
    OpCircumflexEqual,
    OpPercent,
    OpPercentEqual,
    OpDot,
    OpDotDot,
    OpDotDotDot,
    OpLower,
    OpLowerEqual,
    OpLowerEqualGreater,
    OpLowerLower,
    OpLowerLowerEqual,
    OpGreater,
    OpGreaterEqual,
    OpGreaterGreater,
    OpGreaterGreaterEqual,

    // Control flow
    KwdIf,
    KwdElse,
    KwdElif,
    KwdFor,
    KwdWhile,
    KwdSwitch,
    KwdDefer,
    KwdForeach,
    KwdWhere,
    KwdVerify,
    KwdBreak,
    KwdFallthrough,
    KwdUnreachable,
    KwdReturn,
    KwdCase,
    KwdContinue,
    KwdDefault,

    // Logical operators
    KwdAnd,
    KwdOr,
    KwdOrElse,

    // Range/iteration
    KwdTo,
    KwdUntil,
    KwdIn,
    KwdAs,
    KwdIs,
    KwdDo,

    // Module/error handling
    KwdUsing,
    KwdWith,
    KwdCast,
    KwdDRef,
    KwdRetVal,
    KwdTry,
    KwdTryCatch,
    KwdCatch,
    KwdAssume,
    KwdThrow,
    KwdDiscard,

    // Literals
    KwdTrue,
    KwdFalse,
    KwdNull,
    KwdUndefined,

    // Access modifiers
    KwdPublic,
    KwdInternal,
    KwdPrivate,

    // Type definitions
    KwdEnum,
    KwdStruct,
    KwdUnion,
    KwdImpl,
    KwdInterface,
    KwdFunc,
    KwdMtd,
    KwdNamespace,
    KwdAlias,
    KwdAttr,
    KwdVar,
    KwdLet,
    KwdConst,
    KwdMoveRef,

    // Reserved
    KwdNot,

    // Compiler directives
    CompilerGlobal,
    CompilerRun,
    CompilerAst,
    CompilerFuncTest,
    CompilerFuncInit,
    CompilerFuncDrop,
    CompilerFuncMain,
    CompilerFuncPreMain,
    CompilerFuncMessage,
    CompilerDependencies,
    CompilerInclude,
    CompilerLoad,
    CompilerAssert,
    CompilerPrint,
    CompilerError,
    CompilerWarning,
    CompilerForeignLib,
    CompilerImport,
    CompilerInject,
    CompilerMacro,
    CompilerIf,
    CompilerElse,
    CompilerElseIf,
    CompilerCode,
    CompilerScope,
    CompilerUp,
    CompilerType,

    // Modifiers
    ModifierPromote,
    ModifierWrap,
    ModifierNoDrop,
    ModifierMove,
    ModifierMoveRaw,
    ModifierReverse,
    ModifierRef,
    ModifierConstRef,
    ModifierNullable,
    ModifierErr,
    ModifierNoErr,
    ModifierBit,
    ModifierUnConst,

    // Compiler info
    CompilerBuildCfg,
    CompilerOs,
    CompilerArch,
    CompilerCpu,
    CompilerBackend,
    CompilerModule,
    CompilerFile,
    CompilerLine,
    CompilerScopeName,
    CompilerCurLocation,
    CompilerCallerLocation,
    CompilerCallerFunction,
    CompilerBuildVersion,
    CompilerBuildRevision,
    CompilerBuildNum,
    CompilerSwagOs,

    // Compiler introspection
    CompilerDefined,
    CompilerOffsetOf,
    CompilerAlignOf,
    CompilerSizeOf,
    CompilerTypeOf,
    CompilerStringOf,
    CompilerNameOf,
    CompilerIsConstExpr,
    CompilerLocation,
    CompilerDeclType,
    CompilerHasTag,
    CompilerGetTag,
    CompilerRunes,
    CompilerSafety,

    // Intrinsics - string/type
    IntrinsicStringCmp,
    IntrinsicTypeCmp,
    IntrinsicIs,
    IntrinsicAs,
    IntrinsicGetContext,
    IntrinsicSetContext,
    IntrinsicCompiler,
    IntrinsicPrint,
    IntrinsicCompilerError,
    IntrinsicCompilerWarning,
    IntrinsicBcBreakpoint,
    IntrinsicAssert,
    IntrinsicPanic,

    // Intrinsics - lifecycle
    IntrinsicInit,
    IntrinsicDrop,
    IntrinsicPostMove,
    IntrinsicPostCopy,

    // Intrinsics - type info
    IntrinsicKindOf,
    IntrinsicCountOf,
    IntrinsicDataOf,

    // Intrinsics - constructors
    IntrinsicMakeSlice,
    IntrinsicMakeString,
    IntrinsicMakeAny,
    IntrinsicMakeInterface,
    IntrinsicMakeCallback,
    IntrinsicTableOf,
    IntrinsicDbgAlloc,
    IntrinsicSysAlloc,

    // Intrinsics - runtime
    IntrinsicGetErr,
    IntrinsicArguments,
    IntrinsicIsByteCode,
    IntrinsicIndex,
    IntrinsicRtFlags,
    IntrinsicGetProcessInfos,
    IntrinsicModules,
    IntrinsicGvtd,

    // Intrinsics - bit operations
    IntrinsicByteSwap,
    IntrinsicBitCountNz,
    IntrinsicBitCountTz,
    IntrinsicBitCountLz,
    IntrinsicRol,
    IntrinsicRor,

    // Intrinsics - math
    IntrinsicMin,
    IntrinsicMax,
    IntrinsicSqrt,
    IntrinsicSin,
    IntrinsicCos,
    IntrinsicTan,
    IntrinsicSinh,
    IntrinsicCosh,
    IntrinsicTanh,
    IntrinsicASin,
    IntrinsicACos,
    IntrinsicATan,
    IntrinsicATan2,
    IntrinsicLog,
    IntrinsicLog2,
    IntrinsicLog10,
    IntrinsicFloor,
    IntrinsicCeil,
    IntrinsicTrunc,
    IntrinsicRound,
    IntrinsicAbs,
    IntrinsicExp,
    IntrinsicExp2,
    IntrinsicPow,

    // Intrinsics - memory
    IntrinsicAlloc,
    IntrinsicRealloc,
    IntrinsicFree,
    IntrinsicMemCpy,
    IntrinsicMemMove,
    IntrinsicMemSet,
    IntrinsicMemCmp,
    IntrinsicMulAdd,
    IntrinsicStrLen,
    IntrinsicStrCmp,

    // Intrinsics - atomic
    IntrinsicAtomicAdd,
    IntrinsicAtomicAnd,
    IntrinsicAtomicOr,
    IntrinsicAtomicXor,
    IntrinsicAtomicXchg,
    IntrinsicAtomicCmpXchg,

    // Intrinsics - varargs
    IntrinsicCVaStart,
    IntrinsicCVaEnd,
    IntrinsicCVaArg,

    // Native types
    TypeAny,
    TypeVoid,
    TypeRune,
    TypeF32,
    TypeF64,
    TypeS8,
    TypeS16,
    TypeS32,
    TypeS64,
    TypeU8,
    TypeU16,
    TypeU32,
    TypeU64,
    TypeBool,
    TypeString,
    TypeCString,
    TypeTypeInfo,
    TypeCVarArgs,
};

#pragma pack(push, 1)
struct Token
{
    uint32_t start = 0;
    uint32_t len   = 0;

    TokenId id = TokenId::Invalid;

    std::string_view toString(const SourceFile* file) const;
};
#pragma pack(pop)

SWC_END_NAMESPACE();
