// ReSharper disable CppClangTidyModernizeUseDesignatedInitializers
#pragma once
#include "Lexer/KeywordTable.h"

SWC_BEGIN_NAMESPACE()

enum class SubTokenIdentifierId : uint16_t
{
    Invalid = 0,

    // Control flow
    If,
    Else,
    Elif,
    For,
    While,
    Switch,
    Defer,
    Foreach,
    Where,
    Verify,
    Break,
    Fallthrough,
    Unreachable,
    Return,
    Case,
    Continue,
    Default,

    // Logical operators
    And,
    Or,
    OrElse,

    // Range/iteration
    To,
    Until,
    In,
    As,
    Is,
    Do,

    // Module/error handling
    Using,
    With,
    Cast,
    DRef,
    RetVal,
    Try,
    TryCatch,
    Catch,
    Assume,
    Throw,
    Discard,

    // Literals
    True,
    False,
    Null,
    Undefined,

    // Access modifiers
    Public,
    Internal,
    Private,

    // Type definitions
    Enum,
    Struct,
    Union,
    Impl,
    Interface,
    Func,
    Mtd,
    Namespace,
    Alias,
    Attr,
    Var,
    Let,
    Const,
    MoveRef,

    // Reserved
    Not,

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

    // CVarArgs keyword
    CVarArgs,

    // Native types
    Any,
    Void,
    Rune,
    F32,
    F64,
    S8,
    S16,
    S32,
    S64,
    U8,
    U16,
    U32,
    U64,
    Bool,
    String,
    CString,
    TypeInfo,
};

enum class KeywordFlagsEnum : uint32_t
{
    Zero = 0,
};

using KeywordFlags = Flags<KeywordFlagsEnum>;

constexpr std::array<KeywordInfo, 249> K_KEYWORDS = {{
    // Control flow
    {"if", SubTokenIdentifierId::If, KeywordFlagsEnum::Zero},
    {"else", SubTokenIdentifierId::Else, KeywordFlagsEnum::Zero},
    {"elif", SubTokenIdentifierId::Elif, KeywordFlagsEnum::Zero},
    {"for", SubTokenIdentifierId::For, KeywordFlagsEnum::Zero},
    {"while", SubTokenIdentifierId::While, KeywordFlagsEnum::Zero},
    {"switch", SubTokenIdentifierId::Switch, KeywordFlagsEnum::Zero},
    {"defer", SubTokenIdentifierId::Defer, KeywordFlagsEnum::Zero},
    {"foreach", SubTokenIdentifierId::Foreach, KeywordFlagsEnum::Zero},
    {"where", SubTokenIdentifierId::Where, KeywordFlagsEnum::Zero},
    {"verify", SubTokenIdentifierId::Verify, KeywordFlagsEnum::Zero},
    {"break", SubTokenIdentifierId::Break, KeywordFlagsEnum::Zero},
    {"fallthrough", SubTokenIdentifierId::Fallthrough, KeywordFlagsEnum::Zero},
    {"unreachable", SubTokenIdentifierId::Unreachable, KeywordFlagsEnum::Zero},
    {"return", SubTokenIdentifierId::Return, KeywordFlagsEnum::Zero},
    {"case", SubTokenIdentifierId::Case, KeywordFlagsEnum::Zero},
    {"continue", SubTokenIdentifierId::Continue, KeywordFlagsEnum::Zero},
    {"default", SubTokenIdentifierId::Default, KeywordFlagsEnum::Zero},

    // Logical operators
    {"and", SubTokenIdentifierId::And, KeywordFlagsEnum::Zero},
    {"or", SubTokenIdentifierId::Or, KeywordFlagsEnum::Zero},
    {"orelse", SubTokenIdentifierId::OrElse, KeywordFlagsEnum::Zero},

    // Range/iteration
    {"to", SubTokenIdentifierId::To, KeywordFlagsEnum::Zero},
    {"until", SubTokenIdentifierId::Until, KeywordFlagsEnum::Zero},
    {"in", SubTokenIdentifierId::In, KeywordFlagsEnum::Zero},
    {"as", SubTokenIdentifierId::As, KeywordFlagsEnum::Zero},
    {"is", SubTokenIdentifierId::Is, KeywordFlagsEnum::Zero},
    {"do", SubTokenIdentifierId::Do, KeywordFlagsEnum::Zero},

    // Module/error handling
    {"using", SubTokenIdentifierId::Using, KeywordFlagsEnum::Zero},
    {"with", SubTokenIdentifierId::With, KeywordFlagsEnum::Zero},
    {"cast", SubTokenIdentifierId::Cast, KeywordFlagsEnum::Zero},
    {"dref", SubTokenIdentifierId::DRef, KeywordFlagsEnum::Zero},
    {"retval", SubTokenIdentifierId::RetVal, KeywordFlagsEnum::Zero},
    {"try", SubTokenIdentifierId::Try, KeywordFlagsEnum::Zero},
    {"trycatch", SubTokenIdentifierId::TryCatch, KeywordFlagsEnum::Zero},
    {"catch", SubTokenIdentifierId::Catch, KeywordFlagsEnum::Zero},
    {"assume", SubTokenIdentifierId::Assume, KeywordFlagsEnum::Zero},
    {"throw", SubTokenIdentifierId::Throw, KeywordFlagsEnum::Zero},
    {"discard", SubTokenIdentifierId::Discard, KeywordFlagsEnum::Zero},

    // Literals
    {"true", SubTokenIdentifierId::True, KeywordFlagsEnum::Zero},
    {"false", SubTokenIdentifierId::False, KeywordFlagsEnum::Zero},
    {"null", SubTokenIdentifierId::Null, KeywordFlagsEnum::Zero},
    {"undefined", SubTokenIdentifierId::Undefined, KeywordFlagsEnum::Zero},

    // Access modifiers
    {"public", SubTokenIdentifierId::Public, KeywordFlagsEnum::Zero},
    {"internal", SubTokenIdentifierId::Internal, KeywordFlagsEnum::Zero},
    {"private", SubTokenIdentifierId::Private, KeywordFlagsEnum::Zero},

    // Type definitions
    {"enum", SubTokenIdentifierId::Enum, KeywordFlagsEnum::Zero},
    {"struct", SubTokenIdentifierId::Struct, KeywordFlagsEnum::Zero},
    {"union", SubTokenIdentifierId::Union, KeywordFlagsEnum::Zero},
    {"impl", SubTokenIdentifierId::Impl, KeywordFlagsEnum::Zero},
    {"interface", SubTokenIdentifierId::Interface, KeywordFlagsEnum::Zero},
    {"func", SubTokenIdentifierId::Func, KeywordFlagsEnum::Zero},
    {"mtd", SubTokenIdentifierId::Mtd, KeywordFlagsEnum::Zero},
    {"namespace", SubTokenIdentifierId::Namespace, KeywordFlagsEnum::Zero},
    {"alias", SubTokenIdentifierId::Alias, KeywordFlagsEnum::Zero},
    {"attr", SubTokenIdentifierId::Attr, KeywordFlagsEnum::Zero},
    {"var", SubTokenIdentifierId::Var, KeywordFlagsEnum::Zero},
    {"let", SubTokenIdentifierId::Let, KeywordFlagsEnum::Zero},
    {"const", SubTokenIdentifierId::Const, KeywordFlagsEnum::Zero},
    {"moveref", SubTokenIdentifierId::MoveRef, KeywordFlagsEnum::Zero},

    // Reserved
    {"not", SubTokenIdentifierId::Not, KeywordFlagsEnum::Zero},

    // Compiler directives
    {"#global", SubTokenIdentifierId::CompilerGlobal, KeywordFlagsEnum::Zero},
    {"#run", SubTokenIdentifierId::CompilerRun, KeywordFlagsEnum::Zero},
    {"#ast", SubTokenIdentifierId::CompilerAst, KeywordFlagsEnum::Zero},
    {"#test", SubTokenIdentifierId::CompilerFuncTest, KeywordFlagsEnum::Zero},
    {"#init", SubTokenIdentifierId::CompilerFuncInit, KeywordFlagsEnum::Zero},
    {"#drop", SubTokenIdentifierId::CompilerFuncDrop, KeywordFlagsEnum::Zero},
    {"#main", SubTokenIdentifierId::CompilerFuncMain, KeywordFlagsEnum::Zero},
    {"#premain", SubTokenIdentifierId::CompilerFuncPreMain, KeywordFlagsEnum::Zero},
    {"#message", SubTokenIdentifierId::CompilerFuncMessage, KeywordFlagsEnum::Zero},
    {"#dependencies", SubTokenIdentifierId::CompilerDependencies, KeywordFlagsEnum::Zero},
    {"#include", SubTokenIdentifierId::CompilerInclude, KeywordFlagsEnum::Zero},
    {"#load", SubTokenIdentifierId::CompilerLoad, KeywordFlagsEnum::Zero},
    {"#assert", SubTokenIdentifierId::CompilerAssert, KeywordFlagsEnum::Zero},
    {"#print", SubTokenIdentifierId::CompilerPrint, KeywordFlagsEnum::Zero},
    {"#error", SubTokenIdentifierId::CompilerError, KeywordFlagsEnum::Zero},
    {"#warning", SubTokenIdentifierId::CompilerWarning, KeywordFlagsEnum::Zero},
    {"#foreignlib", SubTokenIdentifierId::CompilerForeignLib, KeywordFlagsEnum::Zero},
    {"#import", SubTokenIdentifierId::CompilerImport, KeywordFlagsEnum::Zero},
    {"#inject", SubTokenIdentifierId::CompilerInject, KeywordFlagsEnum::Zero},
    {"#macro", SubTokenIdentifierId::CompilerMacro, KeywordFlagsEnum::Zero},
    {"#if", SubTokenIdentifierId::CompilerIf, KeywordFlagsEnum::Zero},
    {"#else", SubTokenIdentifierId::CompilerElse, KeywordFlagsEnum::Zero},
    {"#elif", SubTokenIdentifierId::CompilerElseIf, KeywordFlagsEnum::Zero},
    {"#code", SubTokenIdentifierId::CompilerCode, KeywordFlagsEnum::Zero},
    {"#scope", SubTokenIdentifierId::CompilerScope, KeywordFlagsEnum::Zero},
    {"#up", SubTokenIdentifierId::CompilerUp, KeywordFlagsEnum::Zero},
    {"#type", SubTokenIdentifierId::CompilerType, KeywordFlagsEnum::Zero},

    // Modifiers
    {"#prom", SubTokenIdentifierId::ModifierPromote, KeywordFlagsEnum::Zero},
    {"#wrap", SubTokenIdentifierId::ModifierWrap, KeywordFlagsEnum::Zero},
    {"#nodrop", SubTokenIdentifierId::ModifierNoDrop, KeywordFlagsEnum::Zero},
    {"#move", SubTokenIdentifierId::ModifierMove, KeywordFlagsEnum::Zero},
    {"#moveraw", SubTokenIdentifierId::ModifierMoveRaw, KeywordFlagsEnum::Zero},
    {"#reverse", SubTokenIdentifierId::ModifierReverse, KeywordFlagsEnum::Zero},
    {"#ref", SubTokenIdentifierId::ModifierRef, KeywordFlagsEnum::Zero},
    {"#constref", SubTokenIdentifierId::ModifierConstRef, KeywordFlagsEnum::Zero},
    {"#null", SubTokenIdentifierId::ModifierNullable, KeywordFlagsEnum::Zero},
    {"#err", SubTokenIdentifierId::ModifierErr, KeywordFlagsEnum::Zero},
    {"#noerr", SubTokenIdentifierId::ModifierNoErr, KeywordFlagsEnum::Zero},
    {"#bit", SubTokenIdentifierId::ModifierBit, KeywordFlagsEnum::Zero},
    {"#unconst", SubTokenIdentifierId::ModifierUnConst, KeywordFlagsEnum::Zero},

    // Compiler info
    {"#cfg", SubTokenIdentifierId::CompilerBuildCfg, KeywordFlagsEnum::Zero},
    {"#os", SubTokenIdentifierId::CompilerOs, KeywordFlagsEnum::Zero},
    {"#arch", SubTokenIdentifierId::CompilerArch, KeywordFlagsEnum::Zero},
    {"#cpu", SubTokenIdentifierId::CompilerCpu, KeywordFlagsEnum::Zero},
    {"#backend", SubTokenIdentifierId::CompilerBackend, KeywordFlagsEnum::Zero},
    {"#module", SubTokenIdentifierId::CompilerModule, KeywordFlagsEnum::Zero},
    {"#file", SubTokenIdentifierId::CompilerFile, KeywordFlagsEnum::Zero},
    {"#line", SubTokenIdentifierId::CompilerLine, KeywordFlagsEnum::Zero},
    {"#scopename", SubTokenIdentifierId::CompilerScopeName, KeywordFlagsEnum::Zero},
    {"#curlocation", SubTokenIdentifierId::CompilerCurLocation, KeywordFlagsEnum::Zero},
    {"#callerlocation", SubTokenIdentifierId::CompilerCallerLocation, KeywordFlagsEnum::Zero},
    {"#callerfunction", SubTokenIdentifierId::CompilerCallerFunction, KeywordFlagsEnum::Zero},
    {"#swagversion", SubTokenIdentifierId::CompilerBuildVersion, KeywordFlagsEnum::Zero},
    {"#swagrevision", SubTokenIdentifierId::CompilerBuildRevision, KeywordFlagsEnum::Zero},
    {"#swagbuildnum", SubTokenIdentifierId::CompilerBuildNum, KeywordFlagsEnum::Zero},
    {"#swagos", SubTokenIdentifierId::CompilerSwagOs, KeywordFlagsEnum::Zero},

    // Compiler introspection
    {"#defined", SubTokenIdentifierId::CompilerDefined, KeywordFlagsEnum::Zero},
    {"#offsetof", SubTokenIdentifierId::CompilerOffsetOf, KeywordFlagsEnum::Zero},
    {"#alignof", SubTokenIdentifierId::CompilerAlignOf, KeywordFlagsEnum::Zero},
    {"#sizeof", SubTokenIdentifierId::CompilerSizeOf, KeywordFlagsEnum::Zero},
    {"#typeof", SubTokenIdentifierId::CompilerTypeOf, KeywordFlagsEnum::Zero},
    {"#stringof", SubTokenIdentifierId::CompilerStringOf, KeywordFlagsEnum::Zero},
    {"#nameof", SubTokenIdentifierId::CompilerNameOf, KeywordFlagsEnum::Zero},
    {"#isconstexpr", SubTokenIdentifierId::CompilerIsConstExpr, KeywordFlagsEnum::Zero},
    {"#location", SubTokenIdentifierId::CompilerLocation, KeywordFlagsEnum::Zero},
    {"#decltype", SubTokenIdentifierId::CompilerDeclType, KeywordFlagsEnum::Zero},
    {"#hastag", SubTokenIdentifierId::CompilerHasTag, KeywordFlagsEnum::Zero},
    {"#gettag", SubTokenIdentifierId::CompilerGetTag, KeywordFlagsEnum::Zero},
    {"#runes", SubTokenIdentifierId::CompilerRunes, KeywordFlagsEnum::Zero},
    {"#safety", SubTokenIdentifierId::CompilerSafety, KeywordFlagsEnum::Zero},

    // Intrinsics - string/type
    {"@stringcmp", SubTokenIdentifierId::IntrinsicStringCmp, KeywordFlagsEnum::Zero},
    {"@typecmp", SubTokenIdentifierId::IntrinsicTypeCmp, KeywordFlagsEnum::Zero},
    {"@is", SubTokenIdentifierId::IntrinsicIs, KeywordFlagsEnum::Zero},
    {"@as", SubTokenIdentifierId::IntrinsicAs, KeywordFlagsEnum::Zero},
    {"@getcontext", SubTokenIdentifierId::IntrinsicGetContext, KeywordFlagsEnum::Zero},
    {"@setcontext", SubTokenIdentifierId::IntrinsicSetContext, KeywordFlagsEnum::Zero},
    {"@compiler", SubTokenIdentifierId::IntrinsicCompiler, KeywordFlagsEnum::Zero},
    {"@print", SubTokenIdentifierId::IntrinsicPrint, KeywordFlagsEnum::Zero},
    {"@compilererror", SubTokenIdentifierId::IntrinsicCompilerError, KeywordFlagsEnum::Zero},
    {"@compilerwarning", SubTokenIdentifierId::IntrinsicCompilerWarning, KeywordFlagsEnum::Zero},
    {"@breakpoint", SubTokenIdentifierId::IntrinsicBcBreakpoint, KeywordFlagsEnum::Zero},
    {"@assert", SubTokenIdentifierId::IntrinsicAssert, KeywordFlagsEnum::Zero},
    {"@panic", SubTokenIdentifierId::IntrinsicPanic, KeywordFlagsEnum::Zero},

    // Intrinsics - lifecycle
    {"@init", SubTokenIdentifierId::IntrinsicInit, KeywordFlagsEnum::Zero},
    {"@drop", SubTokenIdentifierId::IntrinsicDrop, KeywordFlagsEnum::Zero},
    {"@postmove", SubTokenIdentifierId::IntrinsicPostMove, KeywordFlagsEnum::Zero},
    {"@postcopy", SubTokenIdentifierId::IntrinsicPostCopy, KeywordFlagsEnum::Zero},

    // Intrinsics - type info
    {"@kindof", SubTokenIdentifierId::IntrinsicKindOf, KeywordFlagsEnum::Zero},
    {"@countof", SubTokenIdentifierId::IntrinsicCountOf, KeywordFlagsEnum::Zero},
    {"@dataof", SubTokenIdentifierId::IntrinsicDataOf, KeywordFlagsEnum::Zero},

    // Intrinsics - constructors
    {"@mkslice", SubTokenIdentifierId::IntrinsicMakeSlice, KeywordFlagsEnum::Zero},
    {"@mkstring", SubTokenIdentifierId::IntrinsicMakeString, KeywordFlagsEnum::Zero},
    {"@mkany", SubTokenIdentifierId::IntrinsicMakeAny, KeywordFlagsEnum::Zero},
    {"@mkinterface", SubTokenIdentifierId::IntrinsicMakeInterface, KeywordFlagsEnum::Zero},
    {"@mkcallback", SubTokenIdentifierId::IntrinsicMakeCallback, KeywordFlagsEnum::Zero},
    {"@tableof", SubTokenIdentifierId::IntrinsicTableOf, KeywordFlagsEnum::Zero},
    {"@dbgalloc", SubTokenIdentifierId::IntrinsicDbgAlloc, KeywordFlagsEnum::Zero},
    {"@sysalloc", SubTokenIdentifierId::IntrinsicSysAlloc, KeywordFlagsEnum::Zero},

    // Intrinsics - runtime
    {"@err", SubTokenIdentifierId::IntrinsicGetErr, KeywordFlagsEnum::Zero},
    {"@args", SubTokenIdentifierId::IntrinsicArguments, KeywordFlagsEnum::Zero},
    {"@bytecode", SubTokenIdentifierId::IntrinsicIsByteCode, KeywordFlagsEnum::Zero},
    {"@index", SubTokenIdentifierId::IntrinsicIndex, KeywordFlagsEnum::Zero},
    {"@rtflags", SubTokenIdentifierId::IntrinsicRtFlags, KeywordFlagsEnum::Zero},
    {"@pinfos", SubTokenIdentifierId::IntrinsicGetProcessInfos, KeywordFlagsEnum::Zero},
    {"@modules", SubTokenIdentifierId::IntrinsicModules, KeywordFlagsEnum::Zero},
    {"@gvtd", SubTokenIdentifierId::IntrinsicGvtd, KeywordFlagsEnum::Zero},

    // Intrinsics - bit operations
    {"@byteswap", SubTokenIdentifierId::IntrinsicByteSwap, KeywordFlagsEnum::Zero},
    {"@bitcountnz", SubTokenIdentifierId::IntrinsicBitCountNz, KeywordFlagsEnum::Zero},
    {"@bitcounttz", SubTokenIdentifierId::IntrinsicBitCountTz, KeywordFlagsEnum::Zero},
    {"@bitcountlz", SubTokenIdentifierId::IntrinsicBitCountLz, KeywordFlagsEnum::Zero},
    {"@rol", SubTokenIdentifierId::IntrinsicRol, KeywordFlagsEnum::Zero},
    {"@ror", SubTokenIdentifierId::IntrinsicRor, KeywordFlagsEnum::Zero},

    // Intrinsics - math
    {"@min", SubTokenIdentifierId::IntrinsicMin, KeywordFlagsEnum::Zero},
    {"@max", SubTokenIdentifierId::IntrinsicMax, KeywordFlagsEnum::Zero},
    {"@sqrt", SubTokenIdentifierId::IntrinsicSqrt, KeywordFlagsEnum::Zero},
    {"@sin", SubTokenIdentifierId::IntrinsicSin, KeywordFlagsEnum::Zero},
    {"@cos", SubTokenIdentifierId::IntrinsicCos, KeywordFlagsEnum::Zero},
    {"@tan", SubTokenIdentifierId::IntrinsicTan, KeywordFlagsEnum::Zero},
    {"@sinh", SubTokenIdentifierId::IntrinsicSinh, KeywordFlagsEnum::Zero},
    {"@cosh", SubTokenIdentifierId::IntrinsicCosh, KeywordFlagsEnum::Zero},
    {"@tanh", SubTokenIdentifierId::IntrinsicTanh, KeywordFlagsEnum::Zero},
    {"@asin", SubTokenIdentifierId::IntrinsicASin, KeywordFlagsEnum::Zero},
    {"@acos", SubTokenIdentifierId::IntrinsicACos, KeywordFlagsEnum::Zero},
    {"@atan", SubTokenIdentifierId::IntrinsicATan, KeywordFlagsEnum::Zero},
    {"@atan2", SubTokenIdentifierId::IntrinsicATan2, KeywordFlagsEnum::Zero},
    {"@log", SubTokenIdentifierId::IntrinsicLog, KeywordFlagsEnum::Zero},
    {"@log2", SubTokenIdentifierId::IntrinsicLog2, KeywordFlagsEnum::Zero},
    {"@log10", SubTokenIdentifierId::IntrinsicLog10, KeywordFlagsEnum::Zero},
    {"@floor", SubTokenIdentifierId::IntrinsicFloor, KeywordFlagsEnum::Zero},
    {"@ceil", SubTokenIdentifierId::IntrinsicCeil, KeywordFlagsEnum::Zero},
    {"@trunc", SubTokenIdentifierId::IntrinsicTrunc, KeywordFlagsEnum::Zero},
    {"@round", SubTokenIdentifierId::IntrinsicRound, KeywordFlagsEnum::Zero},
    {"@abs", SubTokenIdentifierId::IntrinsicAbs, KeywordFlagsEnum::Zero},
    {"@exp", SubTokenIdentifierId::IntrinsicExp, KeywordFlagsEnum::Zero},
    {"@exp2", SubTokenIdentifierId::IntrinsicExp2, KeywordFlagsEnum::Zero},
    {"@pow", SubTokenIdentifierId::IntrinsicPow, KeywordFlagsEnum::Zero},

    // Intrinsics - memory
    {"@alloc", SubTokenIdentifierId::IntrinsicAlloc, KeywordFlagsEnum::Zero},
    {"@realloc", SubTokenIdentifierId::IntrinsicRealloc, KeywordFlagsEnum::Zero},
    {"@free", SubTokenIdentifierId::IntrinsicFree, KeywordFlagsEnum::Zero},
    {"@memcpy", SubTokenIdentifierId::IntrinsicMemCpy, KeywordFlagsEnum::Zero},
    {"@memmove", SubTokenIdentifierId::IntrinsicMemMove, KeywordFlagsEnum::Zero},
    {"@memset", SubTokenIdentifierId::IntrinsicMemSet, KeywordFlagsEnum::Zero},
    {"@memcmp", SubTokenIdentifierId::IntrinsicMemCmp, KeywordFlagsEnum::Zero},
    {"@muladd", SubTokenIdentifierId::IntrinsicMulAdd, KeywordFlagsEnum::Zero},
    {"@strlen", SubTokenIdentifierId::IntrinsicStrLen, KeywordFlagsEnum::Zero},
    {"@strcmp", SubTokenIdentifierId::IntrinsicStrCmp, KeywordFlagsEnum::Zero},

    // Intrinsics - atomic
    {"@atomadd", SubTokenIdentifierId::IntrinsicAtomicAdd, KeywordFlagsEnum::Zero},
    {"@atomand", SubTokenIdentifierId::IntrinsicAtomicAnd, KeywordFlagsEnum::Zero},
    {"@atomor", SubTokenIdentifierId::IntrinsicAtomicOr, KeywordFlagsEnum::Zero},
    {"@atomxor", SubTokenIdentifierId::IntrinsicAtomicXor, KeywordFlagsEnum::Zero},
    {"@atomxchg", SubTokenIdentifierId::IntrinsicAtomicXchg, KeywordFlagsEnum::Zero},
    {"@atomcmpxchg", SubTokenIdentifierId::IntrinsicAtomicCmpXchg, KeywordFlagsEnum::Zero},

    // Intrinsics - varargs
    {"@cvastart", SubTokenIdentifierId::IntrinsicCVaStart, KeywordFlagsEnum::Zero},
    {"@cvaend", SubTokenIdentifierId::IntrinsicCVaEnd, KeywordFlagsEnum::Zero},
    {"@cvaarg", SubTokenIdentifierId::IntrinsicCVaArg, KeywordFlagsEnum::Zero},

    // CVarArgs keyword
    {"cvarargs", SubTokenIdentifierId::CVarArgs, KeywordFlagsEnum::Zero},

    // Native types
    {"any", SubTokenIdentifierId::Any, KeywordFlagsEnum::Zero},
    {"void", SubTokenIdentifierId::Void, KeywordFlagsEnum::Zero},
    {"rune", SubTokenIdentifierId::Rune, KeywordFlagsEnum::Zero},
    {"f32", SubTokenIdentifierId::F32, KeywordFlagsEnum::Zero},
    {"f64", SubTokenIdentifierId::F64, KeywordFlagsEnum::Zero},
    {"s8", SubTokenIdentifierId::S8, KeywordFlagsEnum::Zero},
    {"s16", SubTokenIdentifierId::S16, KeywordFlagsEnum::Zero},
    {"s32", SubTokenIdentifierId::S32, KeywordFlagsEnum::Zero},
    {"s64", SubTokenIdentifierId::S64, KeywordFlagsEnum::Zero},
    {"u8", SubTokenIdentifierId::U8, KeywordFlagsEnum::Zero},
    {"u16", SubTokenIdentifierId::U16, KeywordFlagsEnum::Zero},
    {"u32", SubTokenIdentifierId::U32, KeywordFlagsEnum::Zero},
    {"u64", SubTokenIdentifierId::U64, KeywordFlagsEnum::Zero},
    {"bool", SubTokenIdentifierId::Bool, KeywordFlagsEnum::Zero},
    {"string", SubTokenIdentifierId::String, KeywordFlagsEnum::Zero},
    {"cstring", SubTokenIdentifierId::CString, KeywordFlagsEnum::Zero},
    {"typeinfo", SubTokenIdentifierId::TypeInfo, KeywordFlagsEnum::Zero},
}};

constexpr KeywordTable<1024> KEYWORD_TABLE{K_KEYWORDS};

SWC_END_NAMESPACE()
