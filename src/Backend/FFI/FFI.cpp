#include "pch.h"
#include "Backend/FFI/FFI.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITExecMemory.h"
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct FFIEmitRegs
    {
        MicroReg base = MicroReg::invalid();
        MicroReg tmp  = MicroReg::invalid();
    };

    struct FFINormalizedType
    {
        bool    isVoid  = true;
        bool    isFloat = false;
        uint8_t numBits = 0;
    };

    struct FFIPackedArg
    {
        uint64_t value   = 0;
        bool     isFloat = false;
        uint8_t  numBits = 0;
    };

    FFINormalizedType makeNormalizedType(bool isVoid, bool isFloat, uint8_t numBits)
    {
        return FFINormalizedType{.isVoid = isVoid, .isFloat = isFloat, .numBits = numBits};
    }

    FFINormalizedType normalizeType(TaskContext& ctx, TypeRef typeRef)
    {
        SWC_ASSERT(typeRef.isValid());

        const TypeRef expanded = ctx.typeMgr().get(typeRef).unwrap(ctx, typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        SWC_ASSERT(expanded.isValid());

        const TypeInfo& ty = ctx.typeMgr().get(expanded);
        if (ty.isVoid())
            return makeNormalizedType(true, false, 0);

        if (ty.isBool())
            return makeNormalizedType(false, false, 8);

        if (ty.isCharRune())
            return makeNormalizedType(false, false, 32);

        if (ty.isInt() && ty.payloadIntBits() <= 64 && ty.payloadIntBits() != 0)
            return makeNormalizedType(false, false, static_cast<uint8_t>(ty.payloadIntBits()));

        if (ty.isFloat() && (ty.payloadFloatBits() == 32 || ty.payloadFloatBits() == 64))
            return makeNormalizedType(false, true, static_cast<uint8_t>(ty.payloadFloatBits()));

        if (ty.isPointerLike() || ty.isNull())
            return makeNormalizedType(false, false, 64);

        SWC_ASSERT(false);
        return makeNormalizedType(true, false, 0);
    }

    MicroOpBits opBitsFor(uint8_t numBits)
    {
        switch (numBits)
        {
            case 8: return MicroOpBits::B8;
            case 16: return MicroOpBits::B16;
            case 32: return MicroOpBits::B32;
            case 64: return MicroOpBits::B64;
            default: return MicroOpBits::Zero;
        }
    }

    FFIPackedArg packArgValue(const FFINormalizedType& argType, const void* valuePtr)
    {
        SWC_ASSERT(valuePtr != nullptr);

        FFIPackedArg outArg;
        outArg.isFloat = argType.isFloat;
        outArg.numBits = argType.numBits;

        if (argType.isFloat)
        {
            if (argType.numBits == 32)
            {
                const auto value = *static_cast<const float*>(valuePtr);
                std::memcpy(&outArg.value, &value, sizeof(float));
                return outArg;
            }

            if (argType.numBits == 64)
            {
                const auto value = *static_cast<const double*>(valuePtr);
                std::memcpy(&outArg.value, &value, sizeof(double));
                return outArg;
            }

            SWC_ASSERT(false);
            return outArg;
        }

        switch (argType.numBits)
        {
            case 8:
                outArg.value = *static_cast<const uint8_t*>(valuePtr);
                return outArg;
            case 16:
                outArg.value = *static_cast<const uint16_t*>(valuePtr);
                return outArg;
            case 32:
                outArg.value = *static_cast<const uint32_t*>(valuePtr);
                return outArg;
            case 64:
                std::memcpy(&outArg.value, valuePtr, sizeof(uint64_t));
                return outArg;
            default:
                SWC_ASSERT(false);
                return outArg;
        }
    }

    uint32_t computeStackAdjust(const CallConv& conv, uint32_t numArgs, uint32_t numRegArgs, uint32_t stackSlotSize)
    {
        const uint32_t     numStackArgs   = numArgs > numRegArgs ? numArgs - numRegArgs : 0;
        const uint32_t     stackArgsSize  = numStackArgs * stackSlotSize;
        const uint32_t     frameBaseSize  = conv.stackShadowSpace + stackArgsSize;
        const uint32_t     stackAlignment = conv.stackAlignment ? conv.stackAlignment : 16;
        constexpr uint32_t callPushSize   = sizeof(void*);
        const uint32_t     alignPad       = (stackAlignment + callPushSize - (frameBaseSize % stackAlignment)) % stackAlignment;
        return frameBaseSize + alignPad;
    }

    void emitPackedArgs(const CallConv& conv, MicroInstrBuilder& builder, std::span<const FFIPackedArg> packedArgs, uint32_t numRegArgs, uint32_t stackSlotSize, MicroReg regBase, MicroReg regTmp)
    {
        if (packedArgs.empty())
            return;

        const auto numPackedArgs = static_cast<uint32_t>(packedArgs.size());
        builder.encodeLoadRegImm(regBase, reinterpret_cast<uint64_t>(packedArgs.data()), MicroOpBits::B64, EncodeFlagsE::Zero);
        for (uint32_t i = 0; i < numPackedArgs; ++i)
        {
            const auto& arg      = packedArgs[i];
            const auto  argAddr  = static_cast<uint64_t>(i) * sizeof(FFIPackedArg);
            const auto  argBits  = arg.isFloat ? opBitsFor(arg.numBits) : MicroOpBits::B64;
            const bool  isRegArg = i < numRegArgs;

            if (isRegArg)
            {
                if (arg.isFloat)
                    builder.encodeLoadRegMem(conv.floatArgRegs[i], regBase, argAddr, argBits, EncodeFlagsE::Zero);
                else
                    builder.encodeLoadRegMem(conv.intArgRegs[i], regBase, argAddr, argBits, EncodeFlagsE::Zero);
                continue;
            }

            const auto stackOffset = conv.stackShadowSpace + static_cast<uint64_t>(i - numRegArgs) * stackSlotSize;
            builder.encodeLoadRegMem(regTmp, regBase, argAddr, argBits, EncodeFlagsE::Zero);
            builder.encodeLoadMemReg(conv.stackPointer, stackOffset, regTmp, argBits, EncodeFlagsE::Zero);
        }
    }
}

void FFI::callFFI(TaskContext& ctx, void* targetFn, std::span<const FFIArgument> args, const FFIReturn& ret)
{
    SWC_ASSERT(targetFn != nullptr);

    constexpr auto          callConvKind = CallConvKind::Host;
    const auto&             conv         = CallConv::get(callConvKind);
    const FFINormalizedType retType      = normalizeType(ctx, ret.typeRef);
    SWC_ASSERT(retType.isVoid || ret.valuePtr);

    uint64_t                  intRetTemp = 0;
    SmallVector<FFIPackedArg> packedArgs;
    packedArgs.resize(args.size());

    const auto numArgs = static_cast<uint32_t>(args.size());
    for (uint32_t i = 0; i < numArgs; ++i)
    {
        const auto&             arg     = args[i];
        const FFINormalizedType argType = normalizeType(ctx, arg.typeRef);
        SWC_ASSERT(!argType.isVoid);
        packedArgs[i] = packArgValue(argType, arg.valuePtr);
    }

    const uint32_t numRegArgs    = conv.numArgRegisterSlots();
    const uint32_t stackSlotSize = conv.stackSlotSize();
    const uint32_t stackAdjust   = computeStackAdjust(conv, numArgs, numRegArgs, stackSlotSize);
    FFIEmitRegs    regs;
    SWC_ASSERT(conv.tryPickIntScratchRegs(regs.base, regs.tmp));

    MicroInstrBuilder builder(ctx);
    if (stackAdjust)
        builder.encodeOpBinaryRegImm(conv.stackPointer, stackAdjust, MicroOp::Subtract, MicroOpBits::B64, EncodeFlagsE::Zero);

    emitPackedArgs(conv, builder, packedArgs, numRegArgs, stackSlotSize, regs.base, regs.tmp);

    builder.encodeLoadRegImm(regs.tmp, reinterpret_cast<uint64_t>(targetFn), MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeCallReg(regs.tmp, callConvKind, EncodeFlagsE::Zero);

    if (!retType.isVoid)
    {
        const bool useIntTemp = !retType.isFloat;
        void*      retPtr     = useIntTemp ? static_cast<void*>(&intRetTemp) : ret.valuePtr;
        builder.encodeLoadRegImm(regs.base, reinterpret_cast<uint64_t>(retPtr), MicroOpBits::B64, EncodeFlagsE::Zero);
        if (retType.isFloat)
            builder.encodeLoadMemReg(regs.base, 0, conv.floatReturn, opBitsFor(retType.numBits), EncodeFlagsE::Zero);
        else
            builder.encodeLoadMemReg(regs.base, 0, conv.intReturn, MicroOpBits::B64, EncodeFlagsE::Zero);
    }

    if (stackAdjust)
        builder.encodeOpBinaryRegImm(conv.stackPointer, stackAdjust, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeRet(EncodeFlagsE::Zero);

    JITExecMemory executableMemory;
    SWC_ASSERT(JIT::compile(ctx, builder, executableMemory) == Result::Continue);

    using FFIInvokerFn = void (*)();
    const auto invoker = executableMemory.entryPoint<FFIInvokerFn>();
    SWC_ASSERT(invoker != nullptr);

    invoker();

    if (!retType.isVoid && !retType.isFloat)
        std::memcpy(ret.valuePtr, &intRetTemp, retType.numBits / 8);
}

SWC_END_NAMESPACE();
