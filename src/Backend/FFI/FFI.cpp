#include "pch.h"
#include "Backend/FFI/FFI.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITExecMemory.h"
#include "Backend/MachineCode/CallConv.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/TaskContext.h"
#include <cstring>

SWC_BEGIN_NAMESPACE();

namespace Backend
{
    namespace
    {
        struct FFINormalizedType
        {
            bool    isVoid  = true;
            bool    isFloat = false;
            uint8_t numBits = 0;
        };

        struct FFIArgSlot
        {
            uint64_t value = 0;
        };

        struct FFIArgPlan
        {
            bool     isFloat   = false;
            uint8_t  numBits   = 0;
            uint32_t slotIndex = 0;
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
    }

    Result FFI::callFFI(TaskContext& ctx, void* targetFn, std::span<const FFIArgument> args, const FFIReturn& ret)
    {
        if (!targetFn)
            return Result::Error;

        constexpr auto callConvKind = CallConvKind::Host;
        const auto& conv = CallConv::get(callConvKind);

        FFINormalizedType retType;
        RESULT_VERIFY(normalizeType(ctx, ret.typeRef, retType));
        if (!retType.isVoid && !ret.valuePtr)
            return Result::Error;

        uint64_t intRetTemp = 0;

        std::vector<FFIArgSlot> argSlots(args.size());
        std::vector<FFIArgPlan> plans;
        plans.reserve(args.size());

        for (uint32_t i = 0; i < args.size(); ++i)
        {
            const auto& arg = args[i];
            if (!arg.valuePtr)
                return Result::Error;

            FFINormalizedType argType;
            RESULT_VERIFY(normalizeType(ctx, arg.typeRef, argType));
            if (argType.isVoid)
                return Result::Error;

            auto& slot = argSlots[i].value;
            if (argType.isFloat)
            {
                if (argType.numBits == 32)
                {
                    const auto value = *static_cast<const float*>(arg.valuePtr);
                    std::memcpy(&slot, &value, sizeof(float));
                }
                else if (argType.numBits == 64)
                {
                    const auto value = *static_cast<const double*>(arg.valuePtr);
                    std::memcpy(&slot, &value, sizeof(double));
                }
                else
                {
                    return Result::Error;
                }
            }
            else
            {
                switch (argType.numBits)
                {
                    case 8: slot = *static_cast<const uint8_t*>(arg.valuePtr); break;
                    case 16: slot = *static_cast<const uint16_t*>(arg.valuePtr); break;
                    case 32: slot = *static_cast<const uint32_t*>(arg.valuePtr); break;
                    case 64: std::memcpy(&slot, arg.valuePtr, sizeof(uint64_t)); break;
                    default: return Result::Error;
                }
            }

            plans.push_back({.isFloat = argType.isFloat, .numBits = argType.numBits, .slotIndex = i});
        }

        const uint32_t numStackArgs  = args.size() > 4 ? static_cast<uint32_t>(args.size() - 4) : 0;
        const uint32_t stackArgsSize = numStackArgs * sizeof(uint64_t);
        const uint32_t frameBaseSize = conv.stackShadowSpace + stackArgsSize;
        const uint32_t stackAdjust   = frameBaseSize + ((8u - (frameBaseSize & 0xFu)) & 0xFu);

        constexpr auto regTarget = MicroReg::intReg(0);
        constexpr auto regBase   = MicroReg::intReg(10);
        constexpr auto regTmp    = MicroReg::intReg(11);

        MicroInstrBuilder builder(ctx);
        if (stackAdjust)
            builder.encodeOpBinaryRegImm(conv.stackPointer, stackAdjust, MicroOp::Subtract, MicroOpBits::B64, EncodeFlagsE::Zero);

        if (!argSlots.empty())
        {
            builder.encodeLoadRegImm(regBase, reinterpret_cast<uint64_t>(argSlots.data()), MicroOpBits::B64, EncodeFlagsE::Zero);
            for (uint32_t i = 0; i < plans.size(); ++i)
            {
                const auto& plan     = plans[i];
                const auto  slotAddr = static_cast<uint64_t>(plan.slotIndex) * sizeof(FFIArgSlot);
                const bool  isRegArg = i < 4;

                if (isRegArg)
                {
                    if (plan.isFloat)
                    {
                        builder.encodeLoadRegMem(conv.floatArgRegs[i], regBase, slotAddr, opBitsFor(plan.numBits), EncodeFlagsE::Zero);
                    }
                    else
                    {
                        builder.encodeLoadRegMem(conv.intArgRegs[i], regBase, slotAddr, MicroOpBits::B64, EncodeFlagsE::Zero);
                    }
                }
                else
                {
                    const auto stackOffset = conv.stackShadowSpace + static_cast<uint64_t>(i - 4) * sizeof(uint64_t);
                    if (plan.isFloat)
                    {
                        builder.encodeLoadRegMem(conv.floatReturn, regBase, slotAddr, opBitsFor(plan.numBits), EncodeFlagsE::Zero);
                        builder.encodeLoadMemReg(conv.stackPointer, stackOffset, conv.floatReturn, opBitsFor(plan.numBits), EncodeFlagsE::Zero);
                    }
                    else
                    {
                        builder.encodeLoadRegMem(regTmp, regBase, slotAddr, MicroOpBits::B64, EncodeFlagsE::Zero);
                        builder.encodeLoadMemReg(conv.stackPointer, stackOffset, regTmp, MicroOpBits::B64, EncodeFlagsE::Zero);
                    }
                }
            }
        }

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
}

SWC_END_NAMESPACE();
