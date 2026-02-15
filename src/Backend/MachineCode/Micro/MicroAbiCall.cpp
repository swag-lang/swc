#include "pch.h"
#include "Backend/MachineCode/Micro/MicroAbiCall.h"
#include "Backend/Runtime.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_CALL_PUSH_SIZE = sizeof(void*);

    uint32_t computeCallStackAdjust(const CallConv& conv, uint32_t numArgs)
    {
        const uint32_t numRegArgs    = conv.numArgRegisterSlots();
        const uint32_t stackSlotSize = conv.stackSlotSize();
        const uint32_t numStackArgs  = numArgs > numRegArgs ? numArgs - numRegArgs : 0;
        const uint32_t stackArgsSize = numStackArgs * stackSlotSize;
        const uint32_t frameBaseSize = conv.stackShadowSpace + stackArgsSize;
        const uint32_t stackAlign    = conv.stackAlignment ? conv.stackAlignment : 16;
        const uint32_t alignPad      = (stackAlign + K_CALL_PUSH_SIZE - (frameBaseSize % stackAlign)) % stackAlign;
        return frameBaseSize + alignPad;
    }

    void emitCallArgs(MicroInstrBuilder& builder, const CallConv& conv, std::span<const MicroABICall::Arg> args, MicroReg regBase, MicroReg regTmp)
    {
        if (args.empty())
            return;

        const uint32_t numRegArgs    = conv.numArgRegisterSlots();
        const uint32_t stackSlotSize = conv.stackSlotSize();
        const uint32_t numArgs       = static_cast<uint32_t>(args.size());
        builder.encodeLoadRegImm(regBase, reinterpret_cast<uint64_t>(args.data()), MicroOpBits::B64, EncodeFlagsE::Zero);
        for (uint32_t i = 0; i < numArgs; ++i)
        {
            const auto& arg      = args[i];
            const auto  argAddr  = static_cast<uint64_t>(i) * sizeof(MicroABICall::Arg);
            const auto  argBits  = arg.isFloat ? microOpBitsFromBitWidth(arg.numBits) : MicroOpBits::B64;
            const bool  isRegArg = i < numRegArgs;

            if (isRegArg)
            {
                if (arg.isFloat)
                    builder.encodeLoadRegMem(conv.floatArgRegs[i], regBase, argAddr, argBits, EncodeFlagsE::Zero);
                else
                    builder.encodeLoadRegMem(conv.intArgRegs[i], regBase, argAddr, argBits, EncodeFlagsE::Zero);
                continue;
            }

            const uint64_t stackOffset = conv.stackShadowSpace + static_cast<uint64_t>(i - numRegArgs) * stackSlotSize;
            builder.encodeLoadRegMem(regTmp, regBase, argAddr, argBits, EncodeFlagsE::Zero);
            builder.encodeLoadMemReg(conv.stackPointer, stackOffset, regTmp, argBits, EncodeFlagsE::Zero);
        }
    }

    MicroOpBits preparedArgBits(const MicroABICall::PreparedArg& arg)
    {
        if (arg.isFloat)
        {
            const MicroOpBits bits = microOpBitsFromBitWidth(arg.numBits);
            SWC_ASSERT(bits != MicroOpBits::Zero);
            return bits;
        }

        return MicroOpBits::B64;
    }
}

uint32_t MicroABICall::prepareArgs(MicroInstrBuilder& builder, CallConvKind callConvKind, std::span<const PreparedArg> args)
{
    const auto& conv            = CallConv::get(callConvKind);
    const auto  numPreparedArgs = static_cast<uint32_t>(args.size());
    if (args.empty())
        return 0;

    const uint32_t numRegArgs    = conv.numArgRegisterSlots();
    const uint32_t stackSlotSize = conv.stackSlotSize();

    MicroReg regBase = MicroReg::invalid();
    MicroReg regTmp  = MicroReg::invalid();
    SWC_ASSERT(conv.tryPickIntScratchRegs(regBase, regTmp));

    for (uint32_t i = 0; i < numPreparedArgs; ++i)
    {
        const auto& arg      = args[i];
        const bool  isRegArg = i < numRegArgs;

        switch (arg.kind)
        {
            case PreparedArgKind::Direct:
            {
                const MicroOpBits argBits = preparedArgBits(arg);
                if (isRegArg)
                {
                    if (arg.isFloat)
                    {
                        SWC_ASSERT(i < conv.floatArgRegs.size());
                        builder.encodeLoadRegReg(conv.floatArgRegs[i], arg.srcReg, argBits, EncodeFlagsE::Zero);
                    }
                    else
                    {
                        SWC_ASSERT(i < conv.intArgRegs.size());
                        builder.encodeLoadRegReg(conv.intArgRegs[i], arg.srcReg, argBits, EncodeFlagsE::Zero);
                    }
                }
                else
                {
                    const uint64_t stackOffset = conv.stackShadowSpace + static_cast<uint64_t>(i - numRegArgs) * stackSlotSize;
                    builder.encodeLoadMemReg(conv.stackPointer, stackOffset, arg.srcReg, argBits, EncodeFlagsE::Zero);
                }
                break;
            }

            case PreparedArgKind::InterfaceObject:
            {
                SWC_ASSERT(!arg.isFloat);
                if (isRegArg)
                {
                    SWC_ASSERT(i < conv.intArgRegs.size());
                    builder.encodeLoadRegMem(conv.intArgRegs[i], arg.srcReg, offsetof(Runtime::Interface, obj), MicroOpBits::B64, EncodeFlagsE::Zero);
                }
                else
                {
                    const uint64_t stackOffset = conv.stackShadowSpace + static_cast<uint64_t>(i - numRegArgs) * stackSlotSize;
                    builder.encodeLoadRegMem(regTmp, arg.srcReg, offsetof(Runtime::Interface, obj), MicroOpBits::B64, EncodeFlagsE::Zero);
                    builder.encodeLoadMemReg(conv.stackPointer, stackOffset, regTmp, MicroOpBits::B64, EncodeFlagsE::Zero);
                }
                break;
            }

            default:
                SWC_UNREACHABLE();
        }
    }

    return numPreparedArgs;
}

void MicroABICall::callByAddress(MicroInstrBuilder& builder, CallConvKind callConvKind, uint64_t targetAddress, std::span<const Arg> args, const Return& ret)
{
    const auto& conv        = CallConv::get(callConvKind);
    const auto  numArgs     = static_cast<uint32_t>(args.size());
    const auto  stackAdjust = computeCallStackAdjust(conv, numArgs);

    MicroReg regBase = MicroReg::invalid();
    MicroReg regTmp  = MicroReg::invalid();
    SWC_ASSERT(conv.tryPickIntScratchRegs(regBase, regTmp));

    if (stackAdjust)
        builder.encodeOpBinaryRegImm(conv.stackPointer, stackAdjust, MicroOp::Subtract, MicroOpBits::B64, EncodeFlagsE::Zero);

    emitCallArgs(builder, conv, args, regBase, regTmp);
    builder.encodeLoadRegImm(regTmp, targetAddress, MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeCallReg(regTmp, callConvKind, EncodeFlagsE::Zero);

    if (!ret.isVoid && !ret.isIndirect)
    {
        SWC_ASSERT(ret.valuePtr != nullptr);
        const auto retBits = ret.numBits ? microOpBitsFromBitWidth(ret.numBits) : MicroOpBits::B64;
        builder.encodeLoadRegImm(regBase, reinterpret_cast<uint64_t>(ret.valuePtr), MicroOpBits::B64, EncodeFlagsE::Zero);
        if (ret.isFloat)
            builder.encodeLoadMemReg(regBase, 0, conv.floatReturn, retBits, EncodeFlagsE::Zero);
        else
            builder.encodeLoadMemReg(regBase, 0, conv.intReturn, retBits, EncodeFlagsE::Zero);
    }

    if (stackAdjust)
        builder.encodeOpBinaryRegImm(conv.stackPointer, stackAdjust, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
}

void MicroABICall::callByReg(MicroInstrBuilder& builder, CallConvKind callConvKind, MicroReg targetReg, uint32_t numPreparedArgs)
{
    const auto& conv        = CallConv::get(callConvKind);
    const auto  stackAdjust = computeCallStackAdjust(conv, numPreparedArgs);

    if (stackAdjust)
        builder.encodeOpBinaryRegImm(conv.stackPointer, stackAdjust, MicroOp::Subtract, MicroOpBits::B64, EncodeFlagsE::Zero);

    builder.encodeCallReg(targetReg, callConvKind, EncodeFlagsE::Zero);

    if (stackAdjust)
        builder.encodeOpBinaryRegImm(conv.stackPointer, stackAdjust, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
}

SWC_END_NAMESPACE();
