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
    struct FFINormalizedType
    {
        bool    isVoid  = true;
        bool    isFloat = false;
        uint8_t numBits = 0;
    };

    struct FFIPackedArg
    {
        uint64_t value     = 0;
        bool     isFloat   = false;
        uint8_t  numBits   = 0;
    };

    Result normalizeType(TaskContext& ctx, TypeRef typeRef, FFINormalizedType& outType)
    {
        if (!typeRef.isValid())
            return Result::Error;

        const auto expanded = ctx.typeMgr().get(typeRef).unwrap(ctx, typeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        if (!expanded.isValid())
            return Result::Error;

        const auto& ty = ctx.typeMgr().get(expanded);
        if (ty.isVoid())
        {
            outType = {.isVoid = true, .isFloat = false, .numBits = 0};
            return Result::Continue;
        }

        if (ty.isBool())
        {
            outType = {.isVoid = false, .isFloat = false, .numBits = 8};
            return Result::Continue;
        }

        if (ty.isCharRune())
        {
            outType = {.isVoid = false, .isFloat = false, .numBits = 32};
            return Result::Continue;
        }

        if (ty.isInt() && ty.payloadIntBits() <= 64 && ty.payloadIntBits() != 0)
        {
            outType = {.isVoid = false, .isFloat = false, .numBits = static_cast<uint8_t>(ty.payloadIntBits())};
            return Result::Continue;
        }

        if (ty.isFloat() && (ty.payloadFloatBits() == 32 || ty.payloadFloatBits() == 64))
        {
            outType = {.isVoid = false, .isFloat = true, .numBits = static_cast<uint8_t>(ty.payloadFloatBits())};
            return Result::Continue;
        }

        if (ty.isPointerLike() || ty.isNull())
        {
            outType = {.isVoid = false, .isFloat = false, .numBits = 64};
            return Result::Continue;
        }

        return Result::Error;
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

    Result packArgValue(const FFINormalizedType& argType, const void* valuePtr, FFIPackedArg& outArg)
    {
        if (!valuePtr)
            return Result::Error;

        outArg.isFloat = argType.isFloat;
        outArg.numBits = argType.numBits;

        if (argType.isFloat)
        {
            if (argType.numBits == 32)
            {
                const auto value = *static_cast<const float*>(valuePtr);
                std::memcpy(&outArg.value, &value, sizeof(float));
                return Result::Continue;
            }

            if (argType.numBits == 64)
            {
                const auto value = *static_cast<const double*>(valuePtr);
                std::memcpy(&outArg.value, &value, sizeof(double));
                return Result::Continue;
            }

            return Result::Error;
        }

        switch (argType.numBits)
        {
            case 8:
                outArg.value = *static_cast<const uint8_t*>(valuePtr);
                return Result::Continue;
            case 16:
                outArg.value = *static_cast<const uint16_t*>(valuePtr);
                return Result::Continue;
            case 32:
                outArg.value = *static_cast<const uint32_t*>(valuePtr);
                return Result::Continue;
            case 64:
                std::memcpy(&outArg.value, valuePtr, sizeof(uint64_t));
                return Result::Continue;
            default: return Result::Error;
        }
    }

    uint32_t computeStackAdjust(const CallConv& conv, uint32_t numArgs)
    {
        const uint32_t numStackArgs  = numArgs > 4 ? numArgs - 4 : 0;
        const uint32_t stackArgsSize = numStackArgs * sizeof(uint64_t);
        const uint32_t frameBaseSize = conv.stackShadowSpace + stackArgsSize;
        const uint32_t alignPad      = (8u - (frameBaseSize & 0xFu)) & 0xFu;
        return frameBaseSize + alignPad;
    }

    void emitPackedArgs(const CallConv& conv, MicroInstrBuilder& builder, std::span<const FFIPackedArg> packedArgs, MicroReg regBase, MicroReg regTmp)
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
            const bool  isRegArg = i < 4;

            if (isRegArg)
            {
                if (arg.isFloat)
                    builder.encodeLoadRegMem(conv.floatArgRegs[i], regBase, argAddr, argBits, EncodeFlagsE::Zero);
                else
                    builder.encodeLoadRegMem(conv.intArgRegs[i], regBase, argAddr, argBits, EncodeFlagsE::Zero);
                continue;
            }

            const auto stackOffset = conv.stackShadowSpace + static_cast<uint64_t>(i - 4) * sizeof(uint64_t);
            if (arg.isFloat)
            {
                builder.encodeLoadRegMem(conv.floatReturn, regBase, argAddr, argBits, EncodeFlagsE::Zero);
                builder.encodeLoadMemReg(conv.stackPointer, stackOffset, conv.floatReturn, argBits, EncodeFlagsE::Zero);
            }
            else
            {
                builder.encodeLoadRegMem(regTmp, regBase, argAddr, argBits, EncodeFlagsE::Zero);
                builder.encodeLoadMemReg(conv.stackPointer, stackOffset, regTmp, argBits, EncodeFlagsE::Zero);
            }
        }
    }
}

Result FFI::callFFI(TaskContext& ctx, void* targetFn, std::span<const FFIArgument> args, const FFIReturn& ret)
{
    if (!targetFn)
        return Result::Error;

    constexpr auto  callConvKind = CallConvKind::Host;
    const auto&     conv         = CallConv::get(callConvKind);
    FFINormalizedType retType;
    RESULT_VERIFY(normalizeType(ctx, ret.typeRef, retType));
    if (!retType.isVoid && !ret.valuePtr)
        return Result::Error;

    uint64_t                 intRetTemp = 0;
    std::vector<FFIPackedArg> packedArgs;
    packedArgs.resize(args.size());

    const auto numArgs = static_cast<uint32_t>(args.size());
    for (uint32_t i = 0; i < numArgs; ++i)
    {
        const auto& arg = args[i];
        FFINormalizedType argType;
        RESULT_VERIFY(normalizeType(ctx, arg.typeRef, argType));
        if (argType.isVoid)
            return Result::Error;
        RESULT_VERIFY(packArgValue(argType, arg.valuePtr, packedArgs[i]));
    }

    const uint32_t stackAdjust = computeStackAdjust(conv, numArgs);

    constexpr auto regTarget = MicroReg::intReg(0);
    constexpr auto regBase   = MicroReg::intReg(10);
    constexpr auto regTmp    = MicroReg::intReg(11);

    MicroInstrBuilder builder(ctx);
    if (stackAdjust)
        builder.encodeOpBinaryRegImm(conv.stackPointer, stackAdjust, MicroOp::Subtract, MicroOpBits::B64, EncodeFlagsE::Zero);

    emitPackedArgs(conv, builder, packedArgs, regBase, regTmp);

    builder.encodeLoadRegImm(regTarget, reinterpret_cast<uint64_t>(targetFn), MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeCallReg(regTarget, callConvKind, EncodeFlagsE::Zero);

    if (!retType.isVoid)
    {
        const bool useIntTemp = !retType.isFloat;
        void*      retPtr     = useIntTemp ? static_cast<void*>(&intRetTemp) : ret.valuePtr;
        builder.encodeLoadRegImm(regBase, reinterpret_cast<uint64_t>(retPtr), MicroOpBits::B64, EncodeFlagsE::Zero);
        if (retType.isFloat)
            builder.encodeLoadMemReg(regBase, 0, conv.floatReturn, opBitsFor(retType.numBits), EncodeFlagsE::Zero);
        else
            builder.encodeLoadMemReg(regBase, 0, conv.intReturn, MicroOpBits::B64, EncodeFlagsE::Zero);
    }

    if (stackAdjust)
        builder.encodeOpBinaryRegImm(conv.stackPointer, stackAdjust, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeRet(EncodeFlagsE::Zero);

    JITExecMemory executableMemory;
    RESULT_VERIFY(JIT::compile(ctx, builder, executableMemory));

    using FFIInvokerFn = void (*)();
    const auto invoker = executableMemory.entryPoint<FFIInvokerFn>();
    if (!invoker)
        return Result::Error;

    invoker();

    if (!retType.isVoid && !retType.isFloat)
        std::memcpy(ret.valuePtr, &intRetTemp, retType.numBits / 8);

    return Result::Continue;
}

SWC_END_NAMESPACE();

