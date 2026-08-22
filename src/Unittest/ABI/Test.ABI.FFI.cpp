#include "pch.h"
#include "Support/Report/Assert.h"

#if SWC_HAS_UNITTEST

#include "Backend/ABI/ABICall.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/JIT/JIT.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Runtime.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Support/Core/SmallVector.h"
#include "Unittest/Unittest.h"
#include "Unittest/UnittestSource.h"

SWC_BEGIN_NAMESPACE();
#ifdef _M_X64

namespace
{
    SymbolVariable* makeStructField(TaskContext& ctx, TypeRef typeRef)
    {
        SymbolVariable* field = Symbol::make<SymbolVariable>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        field->setTypeRef(typeRef);
        return field;
    }

    TypeRef makeStructType(TaskContext& ctx, std::span<const TypeRef> fieldTypes)
    {
        SymbolStruct* symStruct = Symbol::make<SymbolStruct>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        for (const auto fieldType : fieldTypes)
            symStruct->addField(makeStructField(ctx, fieldType));
        SWC_ASSERT(symStruct->computeLayout(ctx) == Result::Continue);

        const TypeRef structTypeRef = ctx.typeMgr().addType(TypeInfo::makeStruct(symStruct));
        symStruct->setTypeRef(structTypeRef);
        return structTypeRef;
    }

    Result callCaseTyped(TaskContext& ctx, void* targetFn, std::span<const JITArgument> args, TypeRef retTypeRef, void* outRetValue)
    {
        const Result jitResult = JIT::emitAndCall(ctx, targetFn, args, {.typeRef = retTypeRef, .valuePtr = outRetValue});
        if (jitResult != Result::Continue)
            return jitResult;
        return Result::Continue;
    }
}

// An addressed narrow integer may need a register home slot when another argument travels on the
// stack. Loading the ABI-sized home must not widen the source memory access past the integer itself.
SWC_TEST_BEGIN(ABI_AddressedNarrowIntegerHomeUsesNarrowLoad)
{
    constexpr MicroReg narrowAddress = MicroReg::virtualIntReg(100);
    const std::array   args          = {
        ABICall::PreparedArg{.srcReg = narrowAddress, .isSigned = true, .isAddressed = true, .numBits = 32},
        ABICall::PreparedArg{.srcReg = MicroReg::virtualIntReg(101), .numBits = 64},
        ABICall::PreparedArg{.srcReg = MicroReg::virtualIntReg(102), .numBits = 64},
        ABICall::PreparedArg{.srcReg = MicroReg::virtualIntReg(103), .numBits = 64},
        ABICall::PreparedArg{.srcReg = MicroReg::virtualIntReg(104), .numBits = 64},
    };

    MicroBuilder builder(ctx);
    ABICall::prepareArgs(builder, CallConvKind::Swag, args);

    for (const MicroInstr& inst : builder.instructions().view())
    {
        if (inst.op != MicroInstrOpcode::LoadSignedExtRegMem)
            continue;

        const MicroInstrOperand* ops = inst.ops(builder.operands());
        if (ops[1].reg == narrowAddress && ops[2].opBits == MicroOpBits::B64 && ops[3].opBits == MicroOpBits::B32)
            return Result::Continue;
    }

    return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ABI_SwagSimdArgsUseExtendedRegistersThenWideStackSlots)
{
    const CallConv&                         swag       = CallConv::swag();
    const std::array<ABICall::ArgLayout, 8> argLayouts = {{{128, true}, {128, true}, {128, true}, {128, true}, {128, true}, {128, true}, {128, true}, {128, true}}};

    if (!swag.canPassArgInRegister(4, true, 128) || !swag.canPassArgInRegister(5, true, 128))
        return Result::Error;
    if (swag.canPassArgInRegister(6, true, 128))
        return Result::Error;
    if (ABICall::callArgStackOffset(swag, argLayouts, 6) != swag.stackShadowSpace)
        return Result::Error;
    if (ABICall::callArgStackOffset(swag, argLayouts, 7) != swag.stackShadowSpace + 16)
        return Result::Error;

    const uint32_t expectedFrameBaseSize = swag.stackShadowSpace + 32;
    const uint32_t expectedAdjust        = expectedFrameBaseSize + (swag.stackAlignment + sizeof(void*) - expectedFrameBaseSize % swag.stackAlignment) % swag.stackAlignment;
    if (ABICall::computeCallStackAdjust(CallConvKind::Swag, argLayouts) != expectedAdjust)
        return Result::Error;
}
SWC_TEST_END()

namespace
{
    struct FFIStructPair32
    {
        uint32_t a;
        uint32_t b;
    };

    struct FFIStructTriple64
    {
        uint64_t a;
        uint64_t b;
        uint64_t c;
    };

    bool ffiNativeReturnTrue()
    {
        return true;
    }

    uint8_t ffiNativeAddU8(uint8_t a, uint8_t b)
    {
        return static_cast<uint8_t>(a + b);
    }

    int32_t ffiNativeAddI32(int32_t a, int32_t b)
    {
        return a + b;
    }

    float ffiNativeAddF32(float a, float b)
    {
        return a + b;
    }

    double ffiNativeAddF64(double a, double b)
    {
        return a + b;
    }

    double ffiNativeSum5F64(double a, double b, double c, double d, double e)
    {
        return a + b + c + d + e;
    }

    uint64_t ffiNativeMixArgs(uint8_t a, uint16_t b, uint32_t c, uint64_t d)
    {
        return static_cast<uint64_t>(a) + static_cast<uint64_t>(b) + static_cast<uint64_t>(c) + d;
    }

    int64_t ffiNativeStackArgs(int64_t a, int64_t b, int64_t c, int64_t d, int64_t e, int64_t f)
    {
        return a + b + c + d + e + f;
    }

    bool ffiNativeConsumePtr(const void* ptr)
    {
        return ptr != nullptr;
    }

    uint64_t ffiNativeStructPair32Sum(FFIStructPair32 value)
    {
        return static_cast<uint64_t>(value.a) + value.b;
    }

    uint64_t ffiNativeStructPair32Stack(uint64_t a, uint64_t b, uint64_t c, uint64_t d, FFIStructPair32 value)
    {
        return a + b + c + d + value.a + value.b;
    }

    uint64_t ffiNativeStructTriple64Mutate(FFIStructTriple64 value)
    {
        volatile uint64_t* valueA = &value.a;
        *valueA                   = *valueA + 5;
        return value.a + value.b + value.c;
    }

    FFIStructPair32 ffiNativeReturnStructPair32(uint32_t a, uint32_t b)
    {
        return {.a = a, .b = b};
    }

    FFIStructTriple64 ffiNativeReturnStructTriple64(uint64_t seed)
    {
        return {.a = seed + 1, .b = seed + 2, .c = seed + 3};
    }

}

SWC_TEST_BEGIN(FFI_CallNativeNoArgBool)
{
    const TypeManager& typeMgr = ctx.typeMgr();
    bool               result  = false;
    SWC_RESULT(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeReturnTrue), std::span<const JITArgument>{}, typeMgr.typeBool(), &result));
    if (!result)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeU8)
{
    const TypeManager& typeMgr = ctx.typeMgr();

    constexpr uint8_t a = 19;
    constexpr uint8_t b = 23;

    const SmallVector<JITArgument> args = {
        {.typeRef = typeMgr.typeU8(), .valuePtr = &a},
        {.typeRef = typeMgr.typeU8(), .valuePtr = &b},
    };

    uint8_t result = 0;
    SWC_RESULT(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeAddU8), args, typeMgr.typeU8(), &result));
    if (result != 42)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeI32)
{
    const TypeManager& typeMgr = ctx.typeMgr();

    constexpr int32_t a = -1200;
    constexpr int32_t b = -137;

    const SmallVector<JITArgument> args = {
        {.typeRef = typeMgr.typeS32(), .valuePtr = &a},
        {.typeRef = typeMgr.typeS32(), .valuePtr = &b},
    };

    int32_t result = 0;
    SWC_RESULT(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeAddI32), args, typeMgr.typeS32(), &result));
    if (result != -1337)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeF32)
{
    const TypeManager& typeMgr = ctx.typeMgr();

    constexpr float a = 0.5f;
    constexpr float b = 1.25f;

    const SmallVector<JITArgument> args = {
        {.typeRef = typeMgr.typeF32(), .valuePtr = &a},
        {.typeRef = typeMgr.typeF32(), .valuePtr = &b},
    };

    float result = 0;
    SWC_RESULT(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeAddF32), args, typeMgr.typeF32(), &result));
    if (result != 1.75f)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeF64)
{
    const TypeManager& typeMgr = ctx.typeMgr();

    constexpr double a = 1.5;
    constexpr double b = 2.5;

    const SmallVector<JITArgument> args = {
        {.typeRef = typeMgr.typeF64(), .valuePtr = &a},
        {.typeRef = typeMgr.typeF64(), .valuePtr = &b},
    };

    double result = 0;
    SWC_RESULT(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeAddF64), args, typeMgr.typeF64(), &result));
    if (result != 4.0)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeF64StackArg)
{
    const TypeManager& typeMgr = ctx.typeMgr();

    constexpr double a = 1.0;
    constexpr double b = 2.0;
    constexpr double c = 3.0;
    constexpr double d = 4.0;
    constexpr double e = 5.0;

    const SmallVector<JITArgument> args = {
        {.typeRef = typeMgr.typeF64(), .valuePtr = &a},
        {.typeRef = typeMgr.typeF64(), .valuePtr = &b},
        {.typeRef = typeMgr.typeF64(), .valuePtr = &c},
        {.typeRef = typeMgr.typeF64(), .valuePtr = &d},
        {.typeRef = typeMgr.typeF64(), .valuePtr = &e},
    };

    double result = 0;
    SWC_RESULT(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeSum5F64), args, typeMgr.typeF64(), &result));
    if (result != 15.0)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeMixedArgs)
{
    const TypeManager& typeMgr = ctx.typeMgr();

    constexpr uint8_t  a = 1;
    constexpr uint16_t b = 2;
    constexpr uint32_t c = 70000;
    constexpr uint64_t d = 0;

    const SmallVector<JITArgument> args = {
        {.typeRef = typeMgr.typeU8(), .valuePtr = &a},
        {.typeRef = typeMgr.typeU16(), .valuePtr = &b},
        {.typeRef = typeMgr.typeU32(), .valuePtr = &c},
        {.typeRef = typeMgr.typeU64(), .valuePtr = &d},
    };

    uint64_t result = 0;
    SWC_RESULT(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeMixArgs), args, typeMgr.typeU64(), &result));
    if (result != 70003ULL)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeStackArgs)
{
    const TypeManager& typeMgr = ctx.typeMgr();

    constexpr int64_t a = 1;
    constexpr int64_t b = 2;
    constexpr int64_t c = 3;
    constexpr int64_t d = 4;
    constexpr int64_t e = 5;
    constexpr int64_t f = 6;

    const SmallVector<JITArgument> args = {
        {.typeRef = typeMgr.typeS64(), .valuePtr = &a},
        {.typeRef = typeMgr.typeS64(), .valuePtr = &b},
        {.typeRef = typeMgr.typeS64(), .valuePtr = &c},
        {.typeRef = typeMgr.typeS64(), .valuePtr = &d},
        {.typeRef = typeMgr.typeS64(), .valuePtr = &e},
        {.typeRef = typeMgr.typeS64(), .valuePtr = &f},
    };

    int64_t result = 0;
    SWC_RESULT(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeStackArgs), args, typeMgr.typeS64(), &result));
    if (result != 21)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativePointerArg)
{
    const TypeManager& typeMgr = ctx.typeMgr();

    const void* ptr = reinterpret_cast<void*>(0x10);

    const SmallVector<JITArgument> args = {
        {.typeRef = typeMgr.typeConstValuePtrVoid(), .valuePtr = static_cast<const void*>(&ptr)},
    };

    bool result = false;
    SWC_RESULT(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeConsumePtr), args, typeMgr.typeBool(), &result));
    if (!result)
        return Result::Error;
}
SWC_TEST_END()

// A Swag function pointer stored into a native callback slot is called with the native
// convention, so the Swag convention must classify every argument shape the same way the
// native one does. Only the caller-side defensive copy of large aggregates may differ.
SWC_TEST_BEGIN(ABI_SwagStructArgPassingMatchesNative)
{
    const CallConv& swag = CallConv::swag();
    const CallConv& c    = CallConv::get(CallConvKind::C);

    for (const uint32_t size : {1u, 2u, 4u, 8u, 3u, 16u, 24u})
    {
        if (swag.classifyStructArgPassing(size) != c.classifyStructArgPassing(size))
            return Result::Error;
    }

    if (swag.classifyStructArgPassing(sizeof(FFIStructPair32)) != StructArgPassingKind::ByValue)
        return Result::Error;
    if (swag.classifyStructArgPassing(sizeof(FFIStructTriple64)) != StructArgPassingKind::ByReference)
        return Result::Error;
    if (swag.structArgPassing.passByReferenceNeedsCopy)
        return Result::Error;
    if (!c.structArgPassing.passByReferenceNeedsCopy)
        return Result::Error;
}
SWC_TEST_END()

namespace
{
    struct FFITinyPair8
    {
        uint8_t a;
        uint8_t b;
    };

    struct FFIPointL
    {
        int32_t x;
        int32_t y;
    };

    // Cover both interop directions through raw function pointers. F-078 exercises a native caller
    // entering Swag with small register aggregates; F-079 exercises Swag calling a native target
    // that mutates the indirect copy of a large by-value aggregate.
    Result runSwagStructByValueInterop(const TaskContext& ctx, std::string_view buildCfg)
    {
        static constexpr std::string_view SOURCE     = R"(#global private

struct Pair
{
    x: u32
    y: u32
}

struct Tiny
{
    a: u8
    b: u8
}

struct PtL
{
    x: s32
    y: s32
}

struct Triple
{
    a: u64
    b: u64
    c: u64
}

func probePairReg(a: u64, p: Pair, b: u64)->u64
{
    return a * 1000000 + cast(u64) p.x * 1000 + cast(u64) p.y + b
}

func probePairStack(a: u64, b: u64, c: u64, d: u64, p: Pair)->u64
{
    return a + b + c + d + cast(u64) p.x * 3 + cast(u64) p.y
}

func probeTinyReg(a: u64, t: Tiny)->u64
{
    return a + cast(u64) t.a * 100 + cast(u64) t.b
}

// The exact shape of IDropTarget.DragEnter/Drop: the aggregate rides the fourth register
// slot and a pointer argument follows on the stack.
func probeDragEnter(itf: u64, dataObj: u64, keyState: u32, pt: PtL, effect: *u32)->s32
{
    effect[] = cast(u32) (pt.x + pt.y) + keyState
    return cast(s32) (itf + dataObj) + pt.x * 1000 + pt.y
}

func probeLargeOutbound(target: func(Triple)->u64)->u64
{
    var value: Triple = {a: 10, b: 20, c: 30}
    let original = &value
    let result = target(value)
    return result * 100 + original.a
}

var GProbePairReg: func(u64, Pair, u64)->u64 = &probePairReg
var GProbePairStack: func(u64, u64, u64, u64, Pair)->u64 = &probePairStack
var GProbeTinyReg: func(u64, Tiny)->u64 = &probeTinyReg
var GProbeDragEnter: func(u64, u64, u32, PtL, *u32)->s32 = &probeDragEnter
var GProbeLargeOutbound: func(func(Triple)->u64)->u64 = &probeLargeOutbound
)";
        const fs::path                    sourcePath = Unittest::makeTestSourcePath("ABI", std::format("CallSwagStructByValueInterop_{}", buildCfg));

        CommandLine cmdLine;
        cmdLine.command     = CommandKind::Test;
        cmdLine.buildCfg    = Utf8(buildCfg);
        cmdLine.backendKind = Runtime::BuildCfgBackendKind::Executable;
        cmdLine.name        = std::format("abi_struct_by_value_interop_{}", buildCfg);
        cmdLine.files.insert(sourcePath);
        CommandLineParser::refreshBuildCfg(cmdLine);

        const uint64_t   errorsBefore = Stats::getNumErrors();
        CompilerInstance compiler(ctx.global(), cmdLine);
        Unittest::registerTestSource(compiler, sourcePath, SOURCE);
        Command::sema(compiler);
        if (Stats::getNumErrors() != errorsBefore)
        {
            std::println(stderr, "FFI interop [{}]: errors after sema", buildCfg);
            return Result::Error;
        }

        NativeBackendBuilder nativeBuilder(compiler, false);
        if (nativeBuilder.prepare() != Result::Continue || Stats::getNumErrors() != errorsBefore)
        {
            std::println(stderr, "FFI interop [{}]: native builder cannot prepare", buildCfg);
            return Result::Error;
        }

        TaskContext compilerCtx(compiler);

        const auto                   initTargets = compiler.nativeGlobalFunctionInitTargetsSnapshot();
        SmallVector<SymbolFunction*> probes;
        for (const std::string_view name : {"probePairReg", "probePairStack", "probeTinyReg", "probeDragEnter", "probeLargeOutbound"})
        {
            SymbolFunction* probe = nullptr;
            for (SymbolFunction* function : initTargets)
            {
                if (function && function->name(compilerCtx) == name)
                {
                    probe = function;
                    break;
                }
            }

            if (!probe)
            {
                std::println(stderr, "FFI interop [{}]: probe '{}' not found in {} init targets", buildCfg, name, initTargets.size());
                return Result::Error;
            }
            probes.push_back(probe);
        }

        while (true)
        {
            const Result jitBatchResult = SymbolFunction::jitBatch(compilerCtx, probes.span());
            if (jitBatchResult == Result::Continue)
                break;
            if (jitBatchResult == Result::Error)
            {
                std::println(stderr, "FFI interop [{}]: jitBatch returned error", buildCfg);
                return Result::Error;
            }

            Sema::waitDone(compilerCtx, compilerCtx.compiler().jobClientId());
            if (Stats::hasError() || compilerCtx.state().jitEmissionError)
            {
                std::println(stderr, "FFI interop [{}]: jitBatch wait reported an error", buildCfg);
                return Result::Error;
            }
        }

        const auto pairReg = reinterpret_cast<uint64_t (*)(uint64_t, FFIStructPair32, uint64_t)>(probes[0]->jitEntryAddress());
        if (!pairReg)
        {
            std::println(stderr, "FFI interop [{}]: probePairReg has no jit entry", buildCfg);
            return Result::Error;
        }
        if (const uint64_t got = pairReg(7, {.a = 18, .b = 24}, 3); got != 7018027ULL)
        {
            std::println(stderr, "FFI interop [{}]: probePairReg answered {}", buildCfg, got);
            return Result::Error;
        }

        const auto pairStack = reinterpret_cast<uint64_t (*)(uint64_t, uint64_t, uint64_t, uint64_t, FFIStructPair32)>(probes[1]->jitEntryAddress());
        if (!pairStack)
        {
            std::println(stderr, "FFI interop [{}]: probePairStack has no jit entry", buildCfg);
            return Result::Error;
        }
        if (const uint64_t got = pairStack(1, 2, 3, 4, {.a = 10, .b = 20}); got != 60ULL)
        {
            std::println(stderr, "FFI interop [{}]: probePairStack answered {}", buildCfg, got);
            return Result::Error;
        }

        const auto tinyReg = reinterpret_cast<uint64_t (*)(uint64_t, FFITinyPair8)>(probes[2]->jitEntryAddress());
        if (!tinyReg)
        {
            std::println(stderr, "FFI interop [{}]: probeTinyReg has no jit entry", buildCfg);
            return Result::Error;
        }
        if (const uint64_t got = tinyReg(5, {.a = 2, .b = 9}); got != 214ULL)
        {
            std::println(stderr, "FFI interop [{}]: probeTinyReg answered {}", buildCfg, got);
            return Result::Error;
        }

        const auto dragEnter = reinterpret_cast<int32_t (*)(uint64_t, uint64_t, uint32_t, FFIPointL, uint32_t*)>(probes[3]->jitEntryAddress());
        if (!dragEnter)
        {
            std::println(stderr, "FFI interop [{}]: probeDragEnter has no jit entry", buildCfg);
            return Result::Error;
        }

        uint32_t effect = 0;
        if (const int32_t got = dragEnter(1, 2, 5, {.x = 30, .y = 12}, &effect); got != 30015 || effect != 47)
        {
            std::println(stderr, "FFI interop [{}]: probeDragEnter answered {} with effect {}", buildCfg, got, effect);
            return Result::Error;
        }

        const auto largeOutbound = reinterpret_cast<uint64_t (*)(uint64_t (*)(FFIStructTriple64))>(probes[4]->jitEntryAddress());
        if (!largeOutbound)
        {
            std::println(stderr, "FFI interop [{}]: probeLargeOutbound has no jit entry", buildCfg);
            return Result::Error;
        }
        if (const uint64_t got = largeOutbound(&ffiNativeStructTriple64Mutate); got != 6510)
        {
            std::println(stderr, "FFI interop [{}]: probeLargeOutbound answered {}", buildCfg, got);
            return Result::Error;
        }

        return Result::Continue;
    }
}

SWC_TEST_BEGIN(FFI_CallSwagStructByValueInteropDebug)
{
    SWC_RESULT(runSwagStructByValueInterop(ctx, "debug"));
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallSwagStructByValueInteropFastDebug)
{
    SWC_RESULT(runSwagStructByValueInterop(ctx, "fast-debug"));
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallSwagStructByValueInteropRelease)
{
    SWC_RESULT(runSwagStructByValueInterop(ctx, "release"));
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeStructByValueRegister)
{
    if (CallConv::get(CallConvKind::C).classifyStructArgPassing(sizeof(FFIStructPair32)) != StructArgPassingKind::ByValue)
        return Result::Continue;

    const TypeManager& typeMgr = ctx.typeMgr();

    const std::array fieldTypes = {
        typeMgr.typeU32(),
        typeMgr.typeU32(),
    };
    const TypeRef structTypeRef = makeStructType(ctx, fieldTypes);

    constexpr FFIStructPair32      value = {.a = 18, .b = 24};
    const SmallVector<JITArgument> args  = {
        {.typeRef = structTypeRef, .valuePtr = &value},
    };

    uint64_t result = 0;
    SWC_RESULT(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeStructPair32Sum), args, typeMgr.typeU64(), &result));
    if (result != 42)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeStructByValueStack)
{
    if (CallConv::get(CallConvKind::C).classifyStructArgPassing(sizeof(FFIStructPair32)) != StructArgPassingKind::ByValue)
        return Result::Continue;

    const TypeManager& typeMgr = ctx.typeMgr();

    const std::array fieldTypes = {
        typeMgr.typeU32(),
        typeMgr.typeU32(),
    };
    const TypeRef structTypeRef = makeStructType(ctx, fieldTypes);

    constexpr uint64_t        a     = 1;
    constexpr uint64_t        b     = 2;
    constexpr uint64_t        c     = 3;
    constexpr uint64_t        d     = 4;
    constexpr FFIStructPair32 value = {.a = 10, .b = 20};

    const SmallVector<JITArgument> args = {
        {.typeRef = typeMgr.typeU64(), .valuePtr = &a},
        {.typeRef = typeMgr.typeU64(), .valuePtr = &b},
        {.typeRef = typeMgr.typeU64(), .valuePtr = &c},
        {.typeRef = typeMgr.typeU64(), .valuePtr = &d},
        {.typeRef = structTypeRef, .valuePtr = &value},
    };

    uint64_t result = 0;
    SWC_RESULT(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeStructPair32Stack), args, typeMgr.typeU64(), &result));
    if (result != 40)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeStructByReferenceCopy)
{
    if (CallConv::get(CallConvKind::C).classifyStructArgPassing(sizeof(FFIStructTriple64)) != StructArgPassingKind::ByReference)
        return Result::Continue;

    const TypeManager& typeMgr = ctx.typeMgr();

    const std::array fieldTypes = {
        typeMgr.typeU64(),
        typeMgr.typeU64(),
        typeMgr.typeU64(),
    };
    const TypeRef structTypeRef = makeStructType(ctx, fieldTypes);

    FFIStructTriple64              value = {.a = 10, .b = 20, .c = 30};
    const SmallVector<JITArgument> args  = {
        {.typeRef = structTypeRef, .valuePtr = &value},
    };

    uint64_t result = 0;
    SWC_RESULT(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeStructTriple64Mutate), args, typeMgr.typeU64(), &result));
    if (result != 65)
        return Result::Error;
    if (value.a != 10 || value.b != 20 || value.c != 30)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeStructReturnByValueRegister)
{
    if (CallConv::get(CallConvKind::C).classifyStructReturnPassing(sizeof(FFIStructPair32)) != StructArgPassingKind::ByValue)
        return Result::Continue;

    const TypeManager& typeMgr = ctx.typeMgr();

    const std::array fieldTypes = {
        typeMgr.typeU32(),
        typeMgr.typeU32(),
    };
    const TypeRef structTypeRef = makeStructType(ctx, fieldTypes);

    constexpr uint32_t             a    = 11;
    constexpr uint32_t             b    = 31;
    const SmallVector<JITArgument> args = {
        {.typeRef = typeMgr.typeU32(), .valuePtr = &a},
        {.typeRef = typeMgr.typeU32(), .valuePtr = &b},
    };

    FFIStructPair32 result = {};
    SWC_RESULT(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeReturnStructPair32), args, structTypeRef, &result));
    if (result.a != a || result.b != b)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(FFI_CallNativeStructReturnByReference)
{
    if (CallConv::get(CallConvKind::C).classifyStructReturnPassing(sizeof(FFIStructTriple64)) != StructArgPassingKind::ByReference)
        return Result::Continue;

    const TypeManager& typeMgr = ctx.typeMgr();

    const std::array fieldTypes = {
        typeMgr.typeU64(),
        typeMgr.typeU64(),
        typeMgr.typeU64(),
    };
    const TypeRef structTypeRef = makeStructType(ctx, fieldTypes);

    constexpr uint64_t             seed = 39;
    const SmallVector<JITArgument> args = {
        {.typeRef = typeMgr.typeU64(), .valuePtr = &seed},
    };

    FFIStructTriple64 result = {};
    SWC_RESULT(callCaseTyped(ctx, reinterpret_cast<void*>(&ffiNativeReturnStructTriple64), args, structTypeRef, &result));
    if (result.a != 40 || result.b != 41 || result.c != 42)
        return Result::Error;
}
SWC_TEST_END()

#endif
SWC_END_NAMESPACE();

#endif
