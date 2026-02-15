#include "pch.h"
#include "Backend/CodeGen/ABI/ABICall.h"
#include "Backend/CodeGen/Micro/MicroInstrHelpers.h"
#include "Backend/Runtime.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_CALL_PUSH_SIZE = sizeof(void*);

    void emitCallArgs(MicroInstrBuilder& builder, const CallConv& conv, std::span<const ABICall::Arg> args, MicroReg regBase, MicroReg regTmp)
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
            const auto  argAddr  = static_cast<uint64_t>(i) * sizeof(ABICall::Arg);
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

    MicroOpBits preparedArgBits(const ABICall::PreparedArg& arg)
    {
        if (arg.isFloat)
        {
            const MicroOpBits bits = microOpBitsFromBitWidth(arg.numBits);
            SWC_ASSERT(bits != MicroOpBits::Zero);
            return bits;
        }

        return MicroOpBits::B64;
    }

    void emitReturnWriteBack(MicroInstrBuilder& builder, const CallConv& conv, const ABICall::Return& ret, MicroReg regBase)
    {
        if (ret.isVoid || ret.isIndirect)
            return;

        SWC_ASSERT(ret.valuePtr != nullptr);
        const auto retBits = ret.numBits ? microOpBitsFromBitWidth(ret.numBits) : MicroOpBits::B64;
        builder.encodeLoadRegImm(regBase, reinterpret_cast<uint64_t>(ret.valuePtr), MicroOpBits::B64, EncodeFlagsE::Zero);
        if (ret.isFloat)
            builder.encodeLoadMemReg(regBase, 0, conv.floatReturn, retBits, EncodeFlagsE::Zero);
        else
            builder.encodeLoadMemReg(regBase, 0, conv.intReturn, retBits, EncodeFlagsE::Zero);
    }
}

uint32_t ABICall::computeCallStackAdjust(CallConvKind callConvKind, uint32_t numArgs)
{
    const auto&    conv          = CallConv::get(callConvKind);
    const uint32_t numRegArgs    = conv.numArgRegisterSlots();
    const uint32_t stackSlotSize = conv.stackSlotSize();
    const uint32_t numStackArgs  = numArgs > numRegArgs ? numArgs - numRegArgs : 0;
    const uint32_t stackArgsSize = numStackArgs * stackSlotSize;
    const uint32_t frameBaseSize = conv.stackShadowSpace + stackArgsSize;
    const uint32_t stackAlign    = conv.stackAlignment ? conv.stackAlignment : 16;
    const uint32_t alignPad      = (stackAlign + K_CALL_PUSH_SIZE - (frameBaseSize % stackAlign)) % stackAlign;
    return frameBaseSize + alignPad;
}

uint32_t ABICall::prepareArgs(MicroInstrBuilder& builder, CallConvKind callConvKind, std::span<const PreparedArg> args)
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

uint32_t ABICall::prepareArgs(MicroInstrBuilder& builder, CallConvKind callConvKind, std::span<const PreparedArg> args, const ABITypeNormalize::NormalizedType& ret)
{
    if (!ret.isIndirect)
        return prepareArgs(builder, callConvKind, args);

    const auto& conv = CallConv::get(callConvKind);
    SWC_ASSERT(!conv.intArgRegs.empty());
    SWC_ASSERT(ret.indirectSize != 0);

    void* indirectRetStorage = builder.ctx().compiler().allocateArray<uint8_t>(ret.indirectSize);

    MicroReg hiddenRetArgSrcReg = MicroReg::invalid();
    MicroReg hiddenRetArgTmpReg = MicroReg::invalid();
    SWC_ASSERT(conv.tryPickIntScratchRegs(hiddenRetArgSrcReg, hiddenRetArgTmpReg));
    builder.encodeLoadRegImm(hiddenRetArgSrcReg, reinterpret_cast<uint64_t>(indirectRetStorage), MicroOpBits::B64, EncodeFlagsE::Zero);

    SmallVector<PreparedArg> preparedArgsWithHiddenRetArg;
    preparedArgsWithHiddenRetArg.reserve(args.size() + 1);

    PreparedArg hiddenRetArg;
    hiddenRetArg.srcReg  = hiddenRetArgSrcReg;
    hiddenRetArg.kind    = PreparedArgKind::Direct;
    hiddenRetArg.isFloat = false;
    hiddenRetArg.numBits = 64;
    preparedArgsWithHiddenRetArg.push_back(hiddenRetArg);

    for (const auto& arg : args)
        preparedArgsWithHiddenRetArg.push_back(arg);

    return prepareArgs(builder, callConvKind, preparedArgsWithHiddenRetArg);
}

void ABICall::storeValueToReturnBuffer(MicroInstrBuilder& builder, CallConvKind callConvKind, MicroReg outputStorageReg, MicroReg valueReg, bool valueIsLValue, const ABITypeNormalize::NormalizedType& ret)
{
    if (ret.isVoid)
        return;

    const auto& conv = CallConv::get(callConvKind);
    if (ret.isIndirect)
    {
        SWC_ASSERT(ret.indirectSize != 0);
        MicroReg srcReg = MicroReg::invalid();
        MicroReg tmpReg = MicroReg::invalid();
        SWC_ASSERT(conv.tryPickIntScratchRegs(srcReg, tmpReg, std::span{&outputStorageReg, 1}));
        builder.encodeLoadRegReg(srcReg, valueReg, MicroOpBits::B64, EncodeFlagsE::Zero);
        MicroInstrHelpers::emitMemCopy(builder, outputStorageReg, srcReg, tmpReg, ret.indirectSize);
        return;
    }

    const MicroOpBits retBits = ret.numBits ? microOpBitsFromBitWidth(ret.numBits) : MicroOpBits::B64;
    SWC_ASSERT(retBits != MicroOpBits::Zero);

    if (ret.isFloat)
    {
        if (valueIsLValue)
            builder.encodeLoadRegMem(conv.floatReturn, valueReg, 0, retBits, EncodeFlagsE::Zero);
        else
            builder.encodeLoadRegReg(conv.floatReturn, valueReg, retBits, EncodeFlagsE::Zero);
        builder.encodeLoadMemReg(outputStorageReg, 0, conv.floatReturn, retBits, EncodeFlagsE::Zero);
        return;
    }

    if (valueIsLValue)
        builder.encodeLoadRegMem(conv.intReturn, valueReg, 0, retBits, EncodeFlagsE::Zero);
    else
        builder.encodeLoadRegReg(conv.intReturn, valueReg, retBits, EncodeFlagsE::Zero);
    builder.encodeLoadMemReg(outputStorageReg, 0, conv.intReturn, retBits, EncodeFlagsE::Zero);
}

void ABICall::materializeReturnToReg(MicroInstrBuilder& builder, MicroReg dstReg, CallConvKind callConvKind, const ABITypeNormalize::NormalizedType& ret)
{
    if (ret.isVoid)
        return;

    const auto& conv = CallConv::get(callConvKind);
    if (ret.isIndirect)
    {
        builder.encodeLoadRegReg(dstReg, conv.intReturn, MicroOpBits::B64, EncodeFlagsE::Zero);
        return;
    }

    const MicroOpBits retBits = ret.numBits ? microOpBitsFromBitWidth(ret.numBits) : MicroOpBits::B64;
    SWC_ASSERT(retBits != MicroOpBits::Zero);

    if (ret.isFloat)
        builder.encodeLoadRegReg(dstReg, conv.floatReturn, retBits, EncodeFlagsE::Zero);
    else
        builder.encodeLoadRegReg(dstReg, conv.intReturn, retBits, EncodeFlagsE::Zero);
}

void ABICall::callByAddress(MicroInstrBuilder& builder, CallConvKind callConvKind, uint64_t targetAddress, std::span<const Arg> args, const Return& ret)
{
    const auto& conv        = CallConv::get(callConvKind);
    const auto  numArgs     = static_cast<uint32_t>(args.size());
    const auto  stackAdjust = computeCallStackAdjust(callConvKind, numArgs);

    MicroReg regBase = MicroReg::invalid();
    MicroReg regTmp  = MicroReg::invalid();
    SWC_ASSERT(conv.tryPickIntScratchRegs(regBase, regTmp));

    if (stackAdjust)
        builder.encodeOpBinaryRegImm(conv.stackPointer, stackAdjust, MicroOp::Subtract, MicroOpBits::B64, EncodeFlagsE::Zero);

    emitCallArgs(builder, conv, args, regBase, regTmp);
    builder.encodeLoadRegImm(regTmp, targetAddress, MicroOpBits::B64, EncodeFlagsE::Zero);
    builder.encodeCallReg(regTmp, callConvKind, EncodeFlagsE::Zero);
    emitReturnWriteBack(builder, conv, ret, regBase);

    if (stackAdjust)
        builder.encodeOpBinaryRegImm(conv.stackPointer, stackAdjust, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
}

void ABICall::callByReg(MicroInstrBuilder& builder, CallConvKind callConvKind, MicroReg targetReg, uint32_t numPreparedArgs, const Return& ret)
{
    const auto& conv        = CallConv::get(callConvKind);
    const auto  stackAdjust = computeCallStackAdjust(callConvKind, numPreparedArgs);

    if (stackAdjust)
        builder.encodeOpBinaryRegImm(conv.stackPointer, stackAdjust, MicroOp::Subtract, MicroOpBits::B64, EncodeFlagsE::Zero);

    builder.encodeCallReg(targetReg, callConvKind, EncodeFlagsE::Zero);

    if (!ret.isVoid && !ret.isIndirect)
    {
        MicroReg regBase = MicroReg::invalid();
        MicroReg regTmp  = MicroReg::invalid();
        SWC_ASSERT(conv.tryPickIntScratchRegs(regBase, regTmp));
        emitReturnWriteBack(builder, conv, ret, regBase);
    }

    if (stackAdjust)
        builder.encodeOpBinaryRegImm(conv.stackPointer, stackAdjust, MicroOp::Add, MicroOpBits::B64, EncodeFlagsE::Zero);
}

void ABICall::callByReg(MicroInstrBuilder& builder, CallConvKind callConvKind, MicroReg targetReg, uint32_t numPreparedArgs)
{
    callByReg(builder, callConvKind, targetReg, numPreparedArgs, Return{});
}

SWC_END_NAMESPACE();
