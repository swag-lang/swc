// ReSharper disable CppClangTidyModernizeUseDesignatedInitializers
#pragma once
#include "Lexer/KeywordTable.h"
#include "Lexer/Token.h"

SWC_BEGIN_NAMESPACE();

enum class KeywordFlagsEnum : uint32_t
{
    Zero = 0,
};

using KeywordFlags = Flags<KeywordFlagsEnum>;

constexpr std::array<KeywordInfo, 249> K_KEYWORDS = {{
    // Control flow
    {"if", TokenId::KwdIf, KeywordFlagsEnum::Zero},
    {"else", TokenId::KwdElse, KeywordFlagsEnum::Zero},
    {"elif", TokenId::KwdElif, KeywordFlagsEnum::Zero},
    {"for", TokenId::KwdFor, KeywordFlagsEnum::Zero},
    {"while", TokenId::KwdWhile, KeywordFlagsEnum::Zero},
    {"switch", TokenId::KwdSwitch, KeywordFlagsEnum::Zero},
    {"defer", TokenId::KwdDefer, KeywordFlagsEnum::Zero},
    {"foreach", TokenId::KwdForeach, KeywordFlagsEnum::Zero},
    {"where", TokenId::KwdWhere, KeywordFlagsEnum::Zero},
    {"verify", TokenId::KwdVerify, KeywordFlagsEnum::Zero},
    {"break", TokenId::KwdBreak, KeywordFlagsEnum::Zero},
    {"fallthrough", TokenId::KwdFallthrough, KeywordFlagsEnum::Zero},
    {"unreachable", TokenId::KwdUnreachable, KeywordFlagsEnum::Zero},
    {"return", TokenId::KwdReturn, KeywordFlagsEnum::Zero},
    {"case", TokenId::KwdCase, KeywordFlagsEnum::Zero},
    {"continue", TokenId::KwdContinue, KeywordFlagsEnum::Zero},
    {"default", TokenId::KwdDefault, KeywordFlagsEnum::Zero},

    // Logical operators
    {"and", TokenId::KwdAnd, KeywordFlagsEnum::Zero},
    {"or", TokenId::KwdOr, KeywordFlagsEnum::Zero},
    {"orelse", TokenId::KwdOrElse, KeywordFlagsEnum::Zero},

    // Range/iteration
    {"to", TokenId::KwdTo, KeywordFlagsEnum::Zero},
    {"until", TokenId::KwdUntil, KeywordFlagsEnum::Zero},
    {"in", TokenId::KwdIn, KeywordFlagsEnum::Zero},
    {"as", TokenId::KwdAs, KeywordFlagsEnum::Zero},
    {"is", TokenId::KwdIs, KeywordFlagsEnum::Zero},
    {"do", TokenId::KwdDo, KeywordFlagsEnum::Zero},

    // Module/error handling
    {"using", TokenId::KwdUsing, KeywordFlagsEnum::Zero},
    {"with", TokenId::KwdWith, KeywordFlagsEnum::Zero},
    {"cast", TokenId::KwdCast, KeywordFlagsEnum::Zero},
    {"dref", TokenId::KwdDRef, KeywordFlagsEnum::Zero},
    {"retval", TokenId::KwdRetVal, KeywordFlagsEnum::Zero},
    {"try", TokenId::KwdTry, KeywordFlagsEnum::Zero},
    {"trycatch", TokenId::KwdTryCatch, KeywordFlagsEnum::Zero},
    {"catch", TokenId::KwdCatch, KeywordFlagsEnum::Zero},
    {"assume", TokenId::KwdAssume, KeywordFlagsEnum::Zero},
    {"throw", TokenId::KwdThrow, KeywordFlagsEnum::Zero},
    {"discard", TokenId::KwdDiscard, KeywordFlagsEnum::Zero},

    // Literals
    {"true", TokenId::KwdTrue, KeywordFlagsEnum::Zero},
    {"false", TokenId::KwdFalse, KeywordFlagsEnum::Zero},
    {"null", TokenId::KwdNull, KeywordFlagsEnum::Zero},
    {"undefined", TokenId::KwdUndefined, KeywordFlagsEnum::Zero},

    // Access modifiers
    {"public", TokenId::KwdPublic, KeywordFlagsEnum::Zero},
    {"internal", TokenId::KwdInternal, KeywordFlagsEnum::Zero},
    {"private", TokenId::KwdPrivate, KeywordFlagsEnum::Zero},

    // Type definitions
    {"enum", TokenId::KwdEnum, KeywordFlagsEnum::Zero},
    {"struct", TokenId::KwdStruct, KeywordFlagsEnum::Zero},
    {"union", TokenId::KwdUnion, KeywordFlagsEnum::Zero},
    {"impl", TokenId::KwdImpl, KeywordFlagsEnum::Zero},
    {"interface", TokenId::KwdInterface, KeywordFlagsEnum::Zero},
    {"func", TokenId::KwdFunc, KeywordFlagsEnum::Zero},
    {"mtd", TokenId::KwdMtd, KeywordFlagsEnum::Zero},
    {"namespace", TokenId::KwdNamespace, KeywordFlagsEnum::Zero},
    {"alias", TokenId::KwdAlias, KeywordFlagsEnum::Zero},
    {"attr", TokenId::KwdAttr, KeywordFlagsEnum::Zero},
    {"var", TokenId::KwdVar, KeywordFlagsEnum::Zero},
    {"let", TokenId::KwdLet, KeywordFlagsEnum::Zero},
    {"const", TokenId::KwdConst, KeywordFlagsEnum::Zero},
    {"moveref", TokenId::KwdMoveRef, KeywordFlagsEnum::Zero},

    // Reserved
    {"not", TokenId::KwdNot, KeywordFlagsEnum::Zero},

    // Compiler directives
    {"#global", TokenId::CompilerGlobal, KeywordFlagsEnum::Zero},
    {"#run", TokenId::CompilerRun, KeywordFlagsEnum::Zero},
    {"#ast", TokenId::CompilerAst, KeywordFlagsEnum::Zero},
    {"#test", TokenId::CompilerFuncTest, KeywordFlagsEnum::Zero},
    {"#init", TokenId::CompilerFuncInit, KeywordFlagsEnum::Zero},
    {"#drop", TokenId::CompilerFuncDrop, KeywordFlagsEnum::Zero},
    {"#main", TokenId::CompilerFuncMain, KeywordFlagsEnum::Zero},
    {"#premain", TokenId::CompilerFuncPreMain, KeywordFlagsEnum::Zero},
    {"#message", TokenId::CompilerFuncMessage, KeywordFlagsEnum::Zero},
    {"#dependencies", TokenId::CompilerDependencies, KeywordFlagsEnum::Zero},
    {"#include", TokenId::CompilerInclude, KeywordFlagsEnum::Zero},
    {"#load", TokenId::CompilerLoad, KeywordFlagsEnum::Zero},
    {"#assert", TokenId::CompilerAssert, KeywordFlagsEnum::Zero},
    {"#print", TokenId::CompilerPrint, KeywordFlagsEnum::Zero},
    {"#error", TokenId::CompilerError, KeywordFlagsEnum::Zero},
    {"#warning", TokenId::CompilerWarning, KeywordFlagsEnum::Zero},
    {"#foreignlib", TokenId::CompilerForeignLib, KeywordFlagsEnum::Zero},
    {"#import", TokenId::CompilerImport, KeywordFlagsEnum::Zero},
    {"#inject", TokenId::CompilerInject, KeywordFlagsEnum::Zero},
    {"#macro", TokenId::CompilerMacro, KeywordFlagsEnum::Zero},
    {"#if", TokenId::CompilerIf, KeywordFlagsEnum::Zero},
    {"#else", TokenId::CompilerElse, KeywordFlagsEnum::Zero},
    {"#elif", TokenId::CompilerElseIf, KeywordFlagsEnum::Zero},
    {"#code", TokenId::CompilerCode, KeywordFlagsEnum::Zero},
    {"#scope", TokenId::CompilerScope, KeywordFlagsEnum::Zero},
    {"#up", TokenId::CompilerUp, KeywordFlagsEnum::Zero},
    {"#type", TokenId::CompilerType, KeywordFlagsEnum::Zero},

    // Modifiers
    {"#prom", TokenId::ModifierPromote, KeywordFlagsEnum::Zero},
    {"#wrap", TokenId::ModifierWrap, KeywordFlagsEnum::Zero},
    {"#nodrop", TokenId::ModifierNoDrop, KeywordFlagsEnum::Zero},
    {"#move", TokenId::ModifierMove, KeywordFlagsEnum::Zero},
    {"#moveraw", TokenId::ModifierMoveRaw, KeywordFlagsEnum::Zero},
    {"#reverse", TokenId::ModifierReverse, KeywordFlagsEnum::Zero},
    {"#ref", TokenId::ModifierRef, KeywordFlagsEnum::Zero},
    {"#constref", TokenId::ModifierConstRef, KeywordFlagsEnum::Zero},
    {"#null", TokenId::ModifierNullable, KeywordFlagsEnum::Zero},
    {"#err", TokenId::ModifierErr, KeywordFlagsEnum::Zero},
    {"#noerr", TokenId::ModifierNoErr, KeywordFlagsEnum::Zero},
    {"#bit", TokenId::ModifierBit, KeywordFlagsEnum::Zero},
    {"#unconst", TokenId::ModifierUnConst, KeywordFlagsEnum::Zero},

    // Compiler info
    {"#cfg", TokenId::CompilerBuildCfg, KeywordFlagsEnum::Zero},
    {"#os", TokenId::CompilerOs, KeywordFlagsEnum::Zero},
    {"#arch", TokenId::CompilerArch, KeywordFlagsEnum::Zero},
    {"#cpu", TokenId::CompilerCpu, KeywordFlagsEnum::Zero},
    {"#backend", TokenId::CompilerBackend, KeywordFlagsEnum::Zero},
    {"#module", TokenId::CompilerModule, KeywordFlagsEnum::Zero},
    {"#file", TokenId::CompilerFile, KeywordFlagsEnum::Zero},
    {"#line", TokenId::CompilerLine, KeywordFlagsEnum::Zero},
    {"#scopename", TokenId::CompilerScopeName, KeywordFlagsEnum::Zero},
    {"#curlocation", TokenId::CompilerCurLocation, KeywordFlagsEnum::Zero},
    {"#callerlocation", TokenId::CompilerCallerLocation, KeywordFlagsEnum::Zero},
    {"#callerfunction", TokenId::CompilerCallerFunction, KeywordFlagsEnum::Zero},
    {"#swagversion", TokenId::CompilerBuildVersion, KeywordFlagsEnum::Zero},
    {"#swagrevision", TokenId::CompilerBuildRevision, KeywordFlagsEnum::Zero},
    {"#swagbuildnum", TokenId::CompilerBuildNum, KeywordFlagsEnum::Zero},
    {"#swagos", TokenId::CompilerSwagOs, KeywordFlagsEnum::Zero},

    // Compiler introspection
    {"#defined", TokenId::CompilerDefined, KeywordFlagsEnum::Zero},
    {"#offsetof", TokenId::CompilerOffsetOf, KeywordFlagsEnum::Zero},
    {"#alignof", TokenId::CompilerAlignOf, KeywordFlagsEnum::Zero},
    {"#sizeof", TokenId::CompilerSizeOf, KeywordFlagsEnum::Zero},
    {"#typeof", TokenId::CompilerTypeOf, KeywordFlagsEnum::Zero},
    {"#stringof", TokenId::CompilerStringOf, KeywordFlagsEnum::Zero},
    {"#nameof", TokenId::CompilerNameOf, KeywordFlagsEnum::Zero},
    {"#isconstexpr", TokenId::CompilerIsConstExpr, KeywordFlagsEnum::Zero},
    {"#location", TokenId::CompilerLocation, KeywordFlagsEnum::Zero},
    {"#decltype", TokenId::CompilerDeclType, KeywordFlagsEnum::Zero},
    {"#hastag", TokenId::CompilerHasTag, KeywordFlagsEnum::Zero},
    {"#gettag", TokenId::CompilerGetTag, KeywordFlagsEnum::Zero},
    {"#runes", TokenId::CompilerRunes, KeywordFlagsEnum::Zero},
    {"#safety", TokenId::CompilerSafety, KeywordFlagsEnum::Zero},

    // Intrinsics - string/type
    {"@stringcmp", TokenId::IntrinsicStringCmp, KeywordFlagsEnum::Zero},
    {"@typecmp", TokenId::IntrinsicTypeCmp, KeywordFlagsEnum::Zero},
    {"@is", TokenId::IntrinsicIs, KeywordFlagsEnum::Zero},
    {"@as", TokenId::IntrinsicAs, KeywordFlagsEnum::Zero},
    {"@getcontext", TokenId::IntrinsicGetContext, KeywordFlagsEnum::Zero},
    {"@setcontext", TokenId::IntrinsicSetContext, KeywordFlagsEnum::Zero},
    {"@compiler", TokenId::IntrinsicCompiler, KeywordFlagsEnum::Zero},
    {"@print", TokenId::IntrinsicPrint, KeywordFlagsEnum::Zero},
    {"@compilererror", TokenId::IntrinsicCompilerError, KeywordFlagsEnum::Zero},
    {"@compilerwarning", TokenId::IntrinsicCompilerWarning, KeywordFlagsEnum::Zero},
    {"@breakpoint", TokenId::IntrinsicBcBreakpoint, KeywordFlagsEnum::Zero},
    {"@assert", TokenId::IntrinsicAssert, KeywordFlagsEnum::Zero},
    {"@panic", TokenId::IntrinsicPanic, KeywordFlagsEnum::Zero},

    // Intrinsics - lifecycle
    {"@init", TokenId::IntrinsicInit, KeywordFlagsEnum::Zero},
    {"@drop", TokenId::IntrinsicDrop, KeywordFlagsEnum::Zero},
    {"@postmove", TokenId::IntrinsicPostMove, KeywordFlagsEnum::Zero},
    {"@postcopy", TokenId::IntrinsicPostCopy, KeywordFlagsEnum::Zero},

    // Intrinsics - type info
    {"@kindof", TokenId::IntrinsicKindOf, KeywordFlagsEnum::Zero},
    {"@countof", TokenId::IntrinsicCountOf, KeywordFlagsEnum::Zero},
    {"@dataof", TokenId::IntrinsicDataOf, KeywordFlagsEnum::Zero},

    // Intrinsics - constructors
    {"@mkslice", TokenId::IntrinsicMakeSlice, KeywordFlagsEnum::Zero},
    {"@mkstring", TokenId::IntrinsicMakeString, KeywordFlagsEnum::Zero},
    {"@mkany", TokenId::IntrinsicMakeAny, KeywordFlagsEnum::Zero},
    {"@mkinterface", TokenId::IntrinsicMakeInterface, KeywordFlagsEnum::Zero},
    {"@mkcallback", TokenId::IntrinsicMakeCallback, KeywordFlagsEnum::Zero},
    {"@tableof", TokenId::IntrinsicTableOf, KeywordFlagsEnum::Zero},
    {"@dbgalloc", TokenId::IntrinsicDbgAlloc, KeywordFlagsEnum::Zero},
    {"@sysalloc", TokenId::IntrinsicSysAlloc, KeywordFlagsEnum::Zero},

    // Intrinsics - runtime
    {"@err", TokenId::IntrinsicGetErr, KeywordFlagsEnum::Zero},
    {"@args", TokenId::IntrinsicArguments, KeywordFlagsEnum::Zero},
    {"@bytecode", TokenId::IntrinsicIsByteCode, KeywordFlagsEnum::Zero},
    {"@index", TokenId::IntrinsicIndex, KeywordFlagsEnum::Zero},
    {"@rtflags", TokenId::IntrinsicRtFlags, KeywordFlagsEnum::Zero},
    {"@pinfos", TokenId::IntrinsicGetProcessInfos, KeywordFlagsEnum::Zero},
    {"@modules", TokenId::IntrinsicModules, KeywordFlagsEnum::Zero},
    {"@gvtd", TokenId::IntrinsicGvtd, KeywordFlagsEnum::Zero},

    // Intrinsics - bit operations
    {"@byteswap", TokenId::IntrinsicByteSwap, KeywordFlagsEnum::Zero},
    {"@bitcountnz", TokenId::IntrinsicBitCountNz, KeywordFlagsEnum::Zero},
    {"@bitcounttz", TokenId::IntrinsicBitCountTz, KeywordFlagsEnum::Zero},
    {"@bitcountlz", TokenId::IntrinsicBitCountLz, KeywordFlagsEnum::Zero},
    {"@rol", TokenId::IntrinsicRol, KeywordFlagsEnum::Zero},
    {"@ror", TokenId::IntrinsicRor, KeywordFlagsEnum::Zero},

    // Intrinsics - math
    {"@min", TokenId::IntrinsicMin, KeywordFlagsEnum::Zero},
    {"@max", TokenId::IntrinsicMax, KeywordFlagsEnum::Zero},
    {"@sqrt", TokenId::IntrinsicSqrt, KeywordFlagsEnum::Zero},
    {"@sin", TokenId::IntrinsicSin, KeywordFlagsEnum::Zero},
    {"@cos", TokenId::IntrinsicCos, KeywordFlagsEnum::Zero},
    {"@tan", TokenId::IntrinsicTan, KeywordFlagsEnum::Zero},
    {"@sinh", TokenId::IntrinsicSinh, KeywordFlagsEnum::Zero},
    {"@cosh", TokenId::IntrinsicCosh, KeywordFlagsEnum::Zero},
    {"@tanh", TokenId::IntrinsicTanh, KeywordFlagsEnum::Zero},
    {"@asin", TokenId::IntrinsicASin, KeywordFlagsEnum::Zero},
    {"@acos", TokenId::IntrinsicACos, KeywordFlagsEnum::Zero},
    {"@atan", TokenId::IntrinsicATan, KeywordFlagsEnum::Zero},
    {"@atan2", TokenId::IntrinsicATan2, KeywordFlagsEnum::Zero},
    {"@log", TokenId::IntrinsicLog, KeywordFlagsEnum::Zero},
    {"@log2", TokenId::IntrinsicLog2, KeywordFlagsEnum::Zero},
    {"@log10", TokenId::IntrinsicLog10, KeywordFlagsEnum::Zero},
    {"@floor", TokenId::IntrinsicFloor, KeywordFlagsEnum::Zero},
    {"@ceil", TokenId::IntrinsicCeil, KeywordFlagsEnum::Zero},
    {"@trunc", TokenId::IntrinsicTrunc, KeywordFlagsEnum::Zero},
    {"@round", TokenId::IntrinsicRound, KeywordFlagsEnum::Zero},
    {"@abs", TokenId::IntrinsicAbs, KeywordFlagsEnum::Zero},
    {"@exp", TokenId::IntrinsicExp, KeywordFlagsEnum::Zero},
    {"@exp2", TokenId::IntrinsicExp2, KeywordFlagsEnum::Zero},
    {"@pow", TokenId::IntrinsicPow, KeywordFlagsEnum::Zero},

    // Intrinsics - memory
    {"@alloc", TokenId::IntrinsicAlloc, KeywordFlagsEnum::Zero},
    {"@realloc", TokenId::IntrinsicRealloc, KeywordFlagsEnum::Zero},
    {"@free", TokenId::IntrinsicFree, KeywordFlagsEnum::Zero},
    {"@memcpy", TokenId::IntrinsicMemCpy, KeywordFlagsEnum::Zero},
    {"@memmove", TokenId::IntrinsicMemMove, KeywordFlagsEnum::Zero},
    {"@memset", TokenId::IntrinsicMemSet, KeywordFlagsEnum::Zero},
    {"@memcmp", TokenId::IntrinsicMemCmp, KeywordFlagsEnum::Zero},
    {"@muladd", TokenId::IntrinsicMulAdd, KeywordFlagsEnum::Zero},
    {"@strlen", TokenId::IntrinsicStrLen, KeywordFlagsEnum::Zero},
    {"@strcmp", TokenId::IntrinsicStrCmp, KeywordFlagsEnum::Zero},

    // Intrinsics - atomic
    {"@atomadd", TokenId::IntrinsicAtomicAdd, KeywordFlagsEnum::Zero},
    {"@atomand", TokenId::IntrinsicAtomicAnd, KeywordFlagsEnum::Zero},
    {"@atomor", TokenId::IntrinsicAtomicOr, KeywordFlagsEnum::Zero},
    {"@atomxor", TokenId::IntrinsicAtomicXor, KeywordFlagsEnum::Zero},
    {"@atomxchg", TokenId::IntrinsicAtomicXchg, KeywordFlagsEnum::Zero},
    {"@atomcmpxchg", TokenId::IntrinsicAtomicCmpXchg, KeywordFlagsEnum::Zero},

    // Intrinsics - varargs
    {"@cvastart", TokenId::IntrinsicCVaStart, KeywordFlagsEnum::Zero},
    {"@cvaend", TokenId::IntrinsicCVaEnd, KeywordFlagsEnum::Zero},
    {"@cvaarg", TokenId::IntrinsicCVaArg, KeywordFlagsEnum::Zero},

    // Native types
    {"any", TokenId::TypeAny, KeywordFlagsEnum::Zero},
    {"void", TokenId::TypeVoid, KeywordFlagsEnum::Zero},
    {"rune", TokenId::TypeRune, KeywordFlagsEnum::Zero},
    {"f32", TokenId::TypeF32, KeywordFlagsEnum::Zero},
    {"f64", TokenId::TypeF64, KeywordFlagsEnum::Zero},
    {"s8", TokenId::TypeS8, KeywordFlagsEnum::Zero},
    {"s16", TokenId::TypeS16, KeywordFlagsEnum::Zero},
    {"s32", TokenId::TypeS32, KeywordFlagsEnum::Zero},
    {"s64", TokenId::TypeS64, KeywordFlagsEnum::Zero},
    {"u8", TokenId::TypeU8, KeywordFlagsEnum::Zero},
    {"u16", TokenId::TypeU16, KeywordFlagsEnum::Zero},
    {"u32", TokenId::TypeU32, KeywordFlagsEnum::Zero},
    {"u64", TokenId::TypeU64, KeywordFlagsEnum::Zero},
    {"bool", TokenId::TypeBool, KeywordFlagsEnum::Zero},
    {"string", TokenId::TypeString, KeywordFlagsEnum::Zero},
    {"cstring", TokenId::TypeCString, KeywordFlagsEnum::Zero},
    {"typeinfo", TokenId::TypeTypeInfo, KeywordFlagsEnum::Zero},
    {"cvarargs", TokenId::TypeCVarArgs, KeywordFlagsEnum::Zero},
}};

constexpr KeywordTable<1024> KEYWORD_TABLE{K_KEYWORDS};

SWC_END_NAMESPACE();
