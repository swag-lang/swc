// ReSharper disable CppClangTidyModernizeUseDesignatedInitializers
#pragma once
#include "Lexer/KeywordTable.h"
#include "Lexer/Token.h"

SWC_BEGIN_NAMESPACE();

enum class KeywordFlags : uint32_t
{
    Zero = 0,
};
SWC_ENABLE_BITMASK(KeywordFlags);

constexpr std::array<KeywordInfo, 249> K_KEYWORDS = {{
    // Control flow
    {"if", TokenId::KwdIf, KeywordFlags::Zero},
    {"else", TokenId::KwdElse, KeywordFlags::Zero},
    {"elif", TokenId::KwdElif, KeywordFlags::Zero},
    {"for", TokenId::KwdFor, KeywordFlags::Zero},
    {"while", TokenId::KwdWhile, KeywordFlags::Zero},
    {"switch", TokenId::KwdSwitch, KeywordFlags::Zero},
    {"defer", TokenId::KwdDefer, KeywordFlags::Zero},
    {"foreach", TokenId::KwdForeach, KeywordFlags::Zero},
    {"where", TokenId::KwdWhere, KeywordFlags::Zero},
    {"verify", TokenId::KwdVerify, KeywordFlags::Zero},
    {"break", TokenId::KwdBreak, KeywordFlags::Zero},
    {"fallthrough", TokenId::KwdFallthrough, KeywordFlags::Zero},
    {"unreachable", TokenId::KwdUnreachable, KeywordFlags::Zero},
    {"return", TokenId::KwdReturn, KeywordFlags::Zero},
    {"case", TokenId::KwdCase, KeywordFlags::Zero},
    {"continue", TokenId::KwdContinue, KeywordFlags::Zero},
    {"default", TokenId::KwdDefault, KeywordFlags::Zero},

    // Logical operators
    {"and", TokenId::KwdAnd, KeywordFlags::Zero},
    {"or", TokenId::KwdOr, KeywordFlags::Zero},
    {"orelse", TokenId::KwdOrElse, KeywordFlags::Zero},

    // Range/iteration
    {"to", TokenId::KwdTo, KeywordFlags::Zero},
    {"until", TokenId::KwdUntil, KeywordFlags::Zero},
    {"in", TokenId::KwdIn, KeywordFlags::Zero},
    {"as", TokenId::KwdAs, KeywordFlags::Zero},
    {"is", TokenId::KwdIs, KeywordFlags::Zero},
    {"do", TokenId::KwdDo, KeywordFlags::Zero},

    // Module/error handling
    {"using", TokenId::KwdUsing, KeywordFlags::Zero},
    {"with", TokenId::KwdWith, KeywordFlags::Zero},
    {"cast", TokenId::KwdCast, KeywordFlags::Zero},
    {"dref", TokenId::KwdDRef, KeywordFlags::Zero},
    {"retval", TokenId::KwdRetVal, KeywordFlags::Zero},
    {"try", TokenId::KwdTry, KeywordFlags::Zero},
    {"trycatch", TokenId::KwdTryCatch, KeywordFlags::Zero},
    {"catch", TokenId::KwdCatch, KeywordFlags::Zero},
    {"assume", TokenId::KwdAssume, KeywordFlags::Zero},
    {"throw", TokenId::KwdThrow, KeywordFlags::Zero},
    {"discard", TokenId::KwdDiscard, KeywordFlags::Zero},

    // Literals
    {"true", TokenId::KwdTrue, KeywordFlags::Zero},
    {"false", TokenId::KwdFalse, KeywordFlags::Zero},
    {"null", TokenId::KwdNull, KeywordFlags::Zero},
    {"undefined", TokenId::KwdUndefined, KeywordFlags::Zero},

    // Access modifiers
    {"public", TokenId::KwdPublic, KeywordFlags::Zero},
    {"internal", TokenId::KwdInternal, KeywordFlags::Zero},
    {"private", TokenId::KwdPrivate, KeywordFlags::Zero},

    // Type definitions
    {"enum", TokenId::KwdEnum, KeywordFlags::Zero},
    {"struct", TokenId::KwdStruct, KeywordFlags::Zero},
    {"union", TokenId::KwdUnion, KeywordFlags::Zero},
    {"impl", TokenId::KwdImpl, KeywordFlags::Zero},
    {"interface", TokenId::KwdInterface, KeywordFlags::Zero},
    {"func", TokenId::KwdFunc, KeywordFlags::Zero},
    {"mtd", TokenId::KwdMtd, KeywordFlags::Zero},
    {"namespace", TokenId::KwdNamespace, KeywordFlags::Zero},
    {"alias", TokenId::KwdAlias, KeywordFlags::Zero},
    {"attr", TokenId::KwdAttr, KeywordFlags::Zero},
    {"var", TokenId::KwdVar, KeywordFlags::Zero},
    {"let", TokenId::KwdLet, KeywordFlags::Zero},
    {"const", TokenId::KwdConst, KeywordFlags::Zero},
    {"moveref", TokenId::KwdMoveRef, KeywordFlags::Zero},

    // Reserved
    {"not", TokenId::KwdNot, KeywordFlags::Zero},

    // Compiler directives
    {"#global", TokenId::CompilerGlobal, KeywordFlags::Zero},
    {"#run", TokenId::CompilerRun, KeywordFlags::Zero},
    {"#ast", TokenId::CompilerAst, KeywordFlags::Zero},
    {"#test", TokenId::CompilerFuncTest, KeywordFlags::Zero},
    {"#init", TokenId::CompilerFuncInit, KeywordFlags::Zero},
    {"#drop", TokenId::CompilerFuncDrop, KeywordFlags::Zero},
    {"#main", TokenId::CompilerFuncMain, KeywordFlags::Zero},
    {"#premain", TokenId::CompilerFuncPreMain, KeywordFlags::Zero},
    {"#message", TokenId::CompilerFuncMessage, KeywordFlags::Zero},
    {"#dependencies", TokenId::CompilerDependencies, KeywordFlags::Zero},
    {"#include", TokenId::CompilerInclude, KeywordFlags::Zero},
    {"#load", TokenId::CompilerLoad, KeywordFlags::Zero},
    {"#assert", TokenId::CompilerAssert, KeywordFlags::Zero},
    {"#print", TokenId::CompilerPrint, KeywordFlags::Zero},
    {"#error", TokenId::CompilerError, KeywordFlags::Zero},
    {"#warning", TokenId::CompilerWarning, KeywordFlags::Zero},
    {"#foreignlib", TokenId::CompilerForeignLib, KeywordFlags::Zero},
    {"#import", TokenId::CompilerImport, KeywordFlags::Zero},
    {"#inject", TokenId::CompilerInject, KeywordFlags::Zero},
    {"#macro", TokenId::CompilerMacro, KeywordFlags::Zero},
    {"#if", TokenId::CompilerIf, KeywordFlags::Zero},
    {"#else", TokenId::CompilerElse, KeywordFlags::Zero},
    {"#elif", TokenId::CompilerElseIf, KeywordFlags::Zero},
    {"#code", TokenId::CompilerCode, KeywordFlags::Zero},
    {"#scope", TokenId::CompilerScope, KeywordFlags::Zero},
    {"#up", TokenId::CompilerUp, KeywordFlags::Zero},
    {"#type", TokenId::CompilerType, KeywordFlags::Zero},

    // Modifiers
    {"#prom", TokenId::ModifierPromote, KeywordFlags::Zero},
    {"#wrap", TokenId::ModifierWrap, KeywordFlags::Zero},
    {"#nodrop", TokenId::ModifierNoDrop, KeywordFlags::Zero},
    {"#move", TokenId::ModifierMove, KeywordFlags::Zero},
    {"#moveraw", TokenId::ModifierMoveRaw, KeywordFlags::Zero},
    {"#reverse", TokenId::ModifierReverse, KeywordFlags::Zero},
    {"#ref", TokenId::ModifierRef, KeywordFlags::Zero},
    {"#constref", TokenId::ModifierConstRef, KeywordFlags::Zero},
    {"#null", TokenId::ModifierNullable, KeywordFlags::Zero},
    {"#err", TokenId::ModifierErr, KeywordFlags::Zero},
    {"#noerr", TokenId::ModifierNoErr, KeywordFlags::Zero},
    {"#bit", TokenId::ModifierBit, KeywordFlags::Zero},
    {"#unconst", TokenId::ModifierUnConst, KeywordFlags::Zero},

    // Compiler info
    {"#cfg", TokenId::CompilerBuildCfg, KeywordFlags::Zero},
    {"#os", TokenId::CompilerOs, KeywordFlags::Zero},
    {"#arch", TokenId::CompilerArch, KeywordFlags::Zero},
    {"#cpu", TokenId::CompilerCpu, KeywordFlags::Zero},
    {"#backend", TokenId::CompilerBackend, KeywordFlags::Zero},
    {"#module", TokenId::CompilerModule, KeywordFlags::Zero},
    {"#file", TokenId::CompilerFile, KeywordFlags::Zero},
    {"#line", TokenId::CompilerLine, KeywordFlags::Zero},
    {"#scopename", TokenId::CompilerScopeName, KeywordFlags::Zero},
    {"#curlocation", TokenId::CompilerCurLocation, KeywordFlags::Zero},
    {"#callerlocation", TokenId::CompilerCallerLocation, KeywordFlags::Zero},
    {"#callerfunction", TokenId::CompilerCallerFunction, KeywordFlags::Zero},
    {"#swagversion", TokenId::CompilerBuildVersion, KeywordFlags::Zero},
    {"#swagrevision", TokenId::CompilerBuildRevision, KeywordFlags::Zero},
    {"#swagbuildnum", TokenId::CompilerBuildNum, KeywordFlags::Zero},
    {"#swagos", TokenId::CompilerSwagOs, KeywordFlags::Zero},

    // Compiler introspection
    {"#defined", TokenId::CompilerDefined, KeywordFlags::Zero},
    {"#offsetof", TokenId::CompilerOffsetOf, KeywordFlags::Zero},
    {"#alignof", TokenId::CompilerAlignOf, KeywordFlags::Zero},
    {"#sizeof", TokenId::CompilerSizeOf, KeywordFlags::Zero},
    {"#typeof", TokenId::CompilerTypeOf, KeywordFlags::Zero},
    {"#stringof", TokenId::CompilerStringOf, KeywordFlags::Zero},
    {"#nameof", TokenId::CompilerNameOf, KeywordFlags::Zero},
    {"#isconstexpr", TokenId::CompilerIsConstExpr, KeywordFlags::Zero},
    {"#location", TokenId::CompilerLocation, KeywordFlags::Zero},
    {"#decltype", TokenId::CompilerDeclType, KeywordFlags::Zero},
    {"#hastag", TokenId::CompilerHasTag, KeywordFlags::Zero},
    {"#gettag", TokenId::CompilerGetTag, KeywordFlags::Zero},
    {"#runes", TokenId::CompilerRunes, KeywordFlags::Zero},
    {"#safety", TokenId::CompilerSafety, KeywordFlags::Zero},

    // Intrinsics - string/type
    {"@stringcmp", TokenId::IntrinsicStringCmp, KeywordFlags::Zero},
    {"@typecmp", TokenId::IntrinsicTypeCmp, KeywordFlags::Zero},
    {"@is", TokenId::IntrinsicIs, KeywordFlags::Zero},
    {"@as", TokenId::IntrinsicAs, KeywordFlags::Zero},
    {"@getcontext", TokenId::IntrinsicGetContext, KeywordFlags::Zero},
    {"@setcontext", TokenId::IntrinsicSetContext, KeywordFlags::Zero},
    {"@compiler", TokenId::IntrinsicCompiler, KeywordFlags::Zero},
    {"@print", TokenId::IntrinsicPrint, KeywordFlags::Zero},
    {"@compilererror", TokenId::IntrinsicCompilerError, KeywordFlags::Zero},
    {"@compilerwarning", TokenId::IntrinsicCompilerWarning, KeywordFlags::Zero},
    {"@breakpoint", TokenId::IntrinsicBcBreakpoint, KeywordFlags::Zero},
    {"@assert", TokenId::IntrinsicAssert, KeywordFlags::Zero},
    {"@panic", TokenId::IntrinsicPanic, KeywordFlags::Zero},

    // Intrinsics - lifecycle
    {"@init", TokenId::IntrinsicInit, KeywordFlags::Zero},
    {"@drop", TokenId::IntrinsicDrop, KeywordFlags::Zero},
    {"@postmove", TokenId::IntrinsicPostMove, KeywordFlags::Zero},
    {"@postcopy", TokenId::IntrinsicPostCopy, KeywordFlags::Zero},

    // Intrinsics - type info
    {"@kindof", TokenId::IntrinsicKindOf, KeywordFlags::Zero},
    {"@countof", TokenId::IntrinsicCountOf, KeywordFlags::Zero},
    {"@dataof", TokenId::IntrinsicDataOf, KeywordFlags::Zero},

    // Intrinsics - constructors
    {"@mkslice", TokenId::IntrinsicMakeSlice, KeywordFlags::Zero},
    {"@mkstring", TokenId::IntrinsicMakeString, KeywordFlags::Zero},
    {"@mkany", TokenId::IntrinsicMakeAny, KeywordFlags::Zero},
    {"@mkinterface", TokenId::IntrinsicMakeInterface, KeywordFlags::Zero},
    {"@mkcallback", TokenId::IntrinsicMakeCallback, KeywordFlags::Zero},
    {"@tableof", TokenId::IntrinsicTableOf, KeywordFlags::Zero},
    {"@dbgalloc", TokenId::IntrinsicDbgAlloc, KeywordFlags::Zero},
    {"@sysalloc", TokenId::IntrinsicSysAlloc, KeywordFlags::Zero},

    // Intrinsics - runtime
    {"@err", TokenId::IntrinsicGetErr, KeywordFlags::Zero},
    {"@args", TokenId::IntrinsicArguments, KeywordFlags::Zero},
    {"@bytecode", TokenId::IntrinsicIsByteCode, KeywordFlags::Zero},
    {"@index", TokenId::IntrinsicIndex, KeywordFlags::Zero},
    {"@rtflags", TokenId::IntrinsicRtFlags, KeywordFlags::Zero},
    {"@pinfos", TokenId::IntrinsicGetProcessInfos, KeywordFlags::Zero},
    {"@modules", TokenId::IntrinsicModules, KeywordFlags::Zero},
    {"@gvtd", TokenId::IntrinsicGvtd, KeywordFlags::Zero},

    // Intrinsics - bit operations
    {"@byteswap", TokenId::IntrinsicByteSwap, KeywordFlags::Zero},
    {"@bitcountnz", TokenId::IntrinsicBitCountNz, KeywordFlags::Zero},
    {"@bitcounttz", TokenId::IntrinsicBitCountTz, KeywordFlags::Zero},
    {"@bitcountlz", TokenId::IntrinsicBitCountLz, KeywordFlags::Zero},
    {"@rol", TokenId::IntrinsicRol, KeywordFlags::Zero},
    {"@ror", TokenId::IntrinsicRor, KeywordFlags::Zero},

    // Intrinsics - math
    {"@min", TokenId::IntrinsicMin, KeywordFlags::Zero},
    {"@max", TokenId::IntrinsicMax, KeywordFlags::Zero},
    {"@sqrt", TokenId::IntrinsicSqrt, KeywordFlags::Zero},
    {"@sin", TokenId::IntrinsicSin, KeywordFlags::Zero},
    {"@cos", TokenId::IntrinsicCos, KeywordFlags::Zero},
    {"@tan", TokenId::IntrinsicTan, KeywordFlags::Zero},
    {"@sinh", TokenId::IntrinsicSinh, KeywordFlags::Zero},
    {"@cosh", TokenId::IntrinsicCosh, KeywordFlags::Zero},
    {"@tanh", TokenId::IntrinsicTanh, KeywordFlags::Zero},
    {"@asin", TokenId::IntrinsicASin, KeywordFlags::Zero},
    {"@acos", TokenId::IntrinsicACos, KeywordFlags::Zero},
    {"@atan", TokenId::IntrinsicATan, KeywordFlags::Zero},
    {"@atan2", TokenId::IntrinsicATan2, KeywordFlags::Zero},
    {"@log", TokenId::IntrinsicLog, KeywordFlags::Zero},
    {"@log2", TokenId::IntrinsicLog2, KeywordFlags::Zero},
    {"@log10", TokenId::IntrinsicLog10, KeywordFlags::Zero},
    {"@floor", TokenId::IntrinsicFloor, KeywordFlags::Zero},
    {"@ceil", TokenId::IntrinsicCeil, KeywordFlags::Zero},
    {"@trunc", TokenId::IntrinsicTrunc, KeywordFlags::Zero},
    {"@round", TokenId::IntrinsicRound, KeywordFlags::Zero},
    {"@abs", TokenId::IntrinsicAbs, KeywordFlags::Zero},
    {"@exp", TokenId::IntrinsicExp, KeywordFlags::Zero},
    {"@exp2", TokenId::IntrinsicExp2, KeywordFlags::Zero},
    {"@pow", TokenId::IntrinsicPow, KeywordFlags::Zero},

    // Intrinsics - memory
    {"@alloc", TokenId::IntrinsicAlloc, KeywordFlags::Zero},
    {"@realloc", TokenId::IntrinsicRealloc, KeywordFlags::Zero},
    {"@free", TokenId::IntrinsicFree, KeywordFlags::Zero},
    {"@memcpy", TokenId::IntrinsicMemCpy, KeywordFlags::Zero},
    {"@memmove", TokenId::IntrinsicMemMove, KeywordFlags::Zero},
    {"@memset", TokenId::IntrinsicMemSet, KeywordFlags::Zero},
    {"@memcmp", TokenId::IntrinsicMemCmp, KeywordFlags::Zero},
    {"@muladd", TokenId::IntrinsicMulAdd, KeywordFlags::Zero},
    {"@strlen", TokenId::IntrinsicStrLen, KeywordFlags::Zero},
    {"@strcmp", TokenId::IntrinsicStrCmp, KeywordFlags::Zero},

    // Intrinsics - atomic
    {"@atomadd", TokenId::IntrinsicAtomicAdd, KeywordFlags::Zero},
    {"@atomand", TokenId::IntrinsicAtomicAnd, KeywordFlags::Zero},
    {"@atomor", TokenId::IntrinsicAtomicOr, KeywordFlags::Zero},
    {"@atomxor", TokenId::IntrinsicAtomicXor, KeywordFlags::Zero},
    {"@atomxchg", TokenId::IntrinsicAtomicXchg, KeywordFlags::Zero},
    {"@atomcmpxchg", TokenId::IntrinsicAtomicCmpXchg, KeywordFlags::Zero},

    // Intrinsics - varargs
    {"@cvastart", TokenId::IntrinsicCVaStart, KeywordFlags::Zero},
    {"@cvaend", TokenId::IntrinsicCVaEnd, KeywordFlags::Zero},
    {"@cvaarg", TokenId::IntrinsicCVaArg, KeywordFlags::Zero},

    // Native types
    {"any", TokenId::TypeAny, KeywordFlags::Zero},
    {"void", TokenId::TypeVoid, KeywordFlags::Zero},
    {"rune", TokenId::TypeRune, KeywordFlags::Zero},
    {"f32", TokenId::TypeF32, KeywordFlags::Zero},
    {"f64", TokenId::TypeF64, KeywordFlags::Zero},
    {"s8", TokenId::TypeS8, KeywordFlags::Zero},
    {"s16", TokenId::TypeS16, KeywordFlags::Zero},
    {"s32", TokenId::TypeS32, KeywordFlags::Zero},
    {"s64", TokenId::TypeS64, KeywordFlags::Zero},
    {"u8", TokenId::TypeU8, KeywordFlags::Zero},
    {"u16", TokenId::TypeU16, KeywordFlags::Zero},
    {"u32", TokenId::TypeU32, KeywordFlags::Zero},
    {"u64", TokenId::TypeU64, KeywordFlags::Zero},
    {"bool", TokenId::TypeBool, KeywordFlags::Zero},
    {"string", TokenId::TypeString, KeywordFlags::Zero},
    {"cstring", TokenId::TypeCString, KeywordFlags::Zero},
    {"typeinfo", TokenId::TypeTypeInfo, KeywordFlags::Zero},
    {"cvarargs", TokenId::TypeCVarArgs, KeywordFlags::Zero},
}};

constexpr KeywordTable<1024> KEYWORD_TABLE{K_KEYWORDS};

SWC_END_NAMESPACE();
