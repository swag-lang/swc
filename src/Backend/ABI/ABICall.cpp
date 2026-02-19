#include "pch.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/Runtime.h"
#include "Compiler/Sema/Symbol/Symbol.h"
#include "Main/CompilerInstance.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    constexpr uint32_t K_CALL_PUSH_SIZE = sizeof(void*);

    struct PreparedCallStackAdjust
    {
        uint32_t before  = 0;
        uint32_t restore = 0;
    };

    void emitCallArgs(MicroBuilder& builder, const CallConv& conv, std::span<const ABICall::Arg> args, MicroReg regBase, MicroReg regTmp)
    {
        // JIT bridge path: pack arguments in memory and expand them into ABI locations.
        if (args.empty())
            return;

        const uint32_t numRegArgs = conv.numArgRegisterSlots();
        const uint32_t numArgs    = static_cast<uint32_t>(args.size());
        builder.emitLoadRegPtrImm(regBase, reinterpret_cast<uint64_t>(args.data()));
        for (uint32_t i = 0; i < numArgs; ++i)
        {
            const ABICall::Arg& arg      = args[i];
            const uint64_t      argAddr  = static_cast<uint64_t>(i) * sizeof(ABICall::Arg);
            const MicroOpBits   argBits  = arg.isFloat ? microOpBitsFromBitWidth(arg.numBits) : MicroOpBits::B64;
            const bool          isRegArg = i < numRegArgs;

            if (isRegArg)
            {
                if (arg.isFloat)
                    builder.emitLoadRegMem(conv.floatArgRegs[i], regBase, argAddr, argBits);
                else
                    builder.emitLoadRegMem(conv.intArgRegs[i], regBase, argAddr, argBits);
                continue;
            }

            const uint64_t stackOffset = ABICall::callArgStackOffset(conv, i);
            builder.emitLoadRegMem(regTmp, regBase, argAddr, argBits);
            builder.emitLoadMemReg(conv.stackPointer, stackOffset, regTmp, argBits);
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

    void emitReturnWriteBack(MicroBuilder& builder, const CallConv& conv, const ABICall::Return& ret, MicroReg regBase)
    {
        if (ret.isVoid || ret.isIndirect)
            return;

        SWC_ASSERT(ret.valuePtr != nullptr);
        const MicroOpBits retBits = ret.numBits ? microOpBitsFromBitWidth(ret.numBits) : MicroOpBits::B64;
        builder.emitLoadRegPtrImm(regBase, reinterpret_cast<uint64_t>(ret.valuePtr));
        if (ret.isFloat)
            builder.emitLoadMemReg(regBase, 0, conv.floatReturn, retBits);
        else
            builder.emitLoadMemReg(regBase, 0, conv.intReturn, retBits);
    }

    PreparedCallStackAdjust computePreparedCallStackAdjust(CallConvKind callConvKind, const ABICall::PreparedCall& preparedCall)
    {
        // This will avoid to double-adjust the stack when prepareArgs already reserved call space.
        PreparedCallStackAdjust result;
        if (preparedCall.stackAlreadyAdjusted)
        {
            result.restore = preparedCall.stackAdjust;
            return result;
        }

        result.before  = ABICall::computeCallStackAdjust(callConvKind, preparedCall.numPreparedArgs);
        result.restore = result.before;
        return result;
    }

    void emitCallStackAdjust(MicroBuilder& builder, const CallConv& conv, uint32_t stackAdjust, MicroOp op)
    {
        if (stackAdjust)
            builder.emitOpBinaryRegImm(conv.stackPointer, stackAdjust, op, MicroOpBits::B64);
    }

    void emitReturnWriteBackIfNeeded(MicroBuilder& builder, const CallConv& conv, const ABICall::Return& ret)
    {
        if (ret.isVoid || ret.isIndirect)
            return;

        MicroReg regBase = MicroReg::invalid();
        MicroReg regTmp  = MicroReg::invalid();
        SWC_ASSERT(conv.tryPickIntScratchRegs(regBase, regTmp));
        emitReturnWriteBack(builder, conv, ret, regBase);
    }
}

uint32_t ABICall::argumentIndexForFunctionParameter(TaskContext& ctx, CallConvKind callConvKind, TypeRef returnTypeRef, uint32_t parameterIndex)
{
    const CallConv&                        callConv      = CallConv::get(callConvKind);
    const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(ctx, callConv, returnTypeRef, ABITypeNormalize::Usage::Return);
    if (normalizedRet.isIndirect)
        return parameterIndex + 1;
    return parameterIndex;
}

uint64_t ABICall::callArgStackOffset(const CallConv& conv, uint32_t argIndex)
{
    // Register arguments also get home slots so the same offset rule works for all args.
    const uint32_t stackSlotSize = conv.stackSlotSize();
    const uint32_t numRegArgs    = conv.numArgRegisterSlots();
    if (argIndex < numRegArgs)
        return static_cast<uint64_t>(argIndex) * stackSlotSize;

    return conv.stackShadowSpace + static_cast<uint64_t>(argIndex - numRegArgs) * stackSlotSize;
}

uint64_t ABICall::incomingArgStackOffset(const CallConv& conv, uint32_t argIndex)
{
    // Callee incoming frame adds return address above the ABI argument area.
    return sizeof(void*) + callArgStackOffset(conv, argIndex);
}

uint32_t ABICall::computeCallStackAdjust(CallConvKind callConvKind, uint32_t numArgs)
{
    // Reserve shadow space + stack args, then restore call-site alignment before CALL pushes RIP.
    const CallConv& conv          = CallConv::get(callConvKind);
    const uint32_t  numRegArgs    = conv.numArgRegisterSlots();
    const uint32_t  stackSlotSize = conv.stackSlotSize();
    const uint32_t  numStackArgs  = numArgs > numRegArgs ? numArgs - numRegArgs : 0;
    const uint32_t  stackArgsSize = numStackArgs * stackSlotSize;
    const uint32_t  frameBaseSize = conv.stackShadowSpace + stackArgsSize;
    const uint32_t  stackAlign    = conv.stackAlignment ? conv.stackAlignment : 16;
    const uint32_t  alignPad      = (stackAlign + K_CALL_PUSH_SIZE - (frameBaseSize % stackAlign)) % stackAlign;
    return frameBaseSize + alignPad;
}

ABICall::PreparedCall ABICall::prepareArgs(MicroBuilder& builder, CallConvKind callConvKind, std::span<const PreparedArg> args)
{
    // Move lowered argument values into the concrete ABI argument registers/stack slots.
    PreparedCall    preparedCall;
    const CallConv& conv            = CallConv::get(callConvKind);
    const uint32_t  numPreparedArgs = static_cast<uint32_t>(args.size());
    preparedCall.numPreparedArgs    = numPreparedArgs;
    if (args.empty())
        return preparedCall;

    const uint32_t numRegArgs  = conv.numArgRegisterSlots();
    const uint32_t stackAdjust = computeCallStackAdjust(callConvKind, numPreparedArgs);
    preparedCall.stackAdjust   = stackAdjust;
    const bool hasStackArgs    = numPreparedArgs > numRegArgs;

    if (hasStackArgs)
    {
        MicroReg regBase = MicroReg::invalid();
        MicroReg regTmp  = MicroReg::invalid();
        SWC_ASSERT(conv.tryPickIntScratchRegs(regBase, regTmp));

        const uint32_t       numRegArgsUsed = std::min(numPreparedArgs, numRegArgs);
        SmallVector<uint8_t> regArgsUseHomeSlot;
        regArgsUseHomeSlot.resize(numRegArgsUsed, 0);

        if (stackAdjust)
            builder.emitOpBinaryRegImm(conv.stackPointer, stackAdjust, MicroOp::Subtract, MicroOpBits::B64);

        for (uint32_t i = 0; i < numPreparedArgs; ++i)
        {
            const PreparedArg& arg      = args[i];
            const MicroOpBits  argBits  = preparedArgBits(arg);
            const bool         isRegArg = i < numRegArgs;

            if (isRegArg)
            {
                // Float values, addressed values, and non-virtual int values are staged through home slots for uniformity.
                const bool useHomeSlot = arg.isFloat || arg.isAddressed || !arg.srcReg.isVirtualInt();
                regArgsUseHomeSlot[i]  = useHomeSlot ? 1 : 0;

                if (!useHomeSlot)
                {
                    SWC_ASSERT(i < conv.intArgRegs.size());
                    builder.addVirtualRegForbiddenPhysRegs(arg.srcReg, conv.intArgRegs);
                    continue;
                }
            }

            const uint64_t stackOffset = callArgStackOffset(conv, i);

            switch (arg.kind)
            {
                case PreparedArgKind::Direct:
                    if (arg.isAddressed)
                    {
                        builder.emitLoadRegMem(regTmp, arg.srcReg, 0, argBits);
                        builder.emitLoadMemReg(conv.stackPointer, stackOffset, regTmp, argBits);
                    }
                    else
                    {
                        builder.emitLoadMemReg(conv.stackPointer, stackOffset, arg.srcReg, argBits);
                    }
                    break;

                case PreparedArgKind::InterfaceObject:
                    SWC_ASSERT(!arg.isFloat);
                    builder.emitLoadRegMem(regTmp, arg.srcReg, offsetof(Runtime::Interface, obj), MicroOpBits::B64);
                    builder.emitLoadMemReg(conv.stackPointer, stackOffset, regTmp, MicroOpBits::B64);
                    break;

                default:
                    SWC_UNREACHABLE();
            }
        }

        for (uint32_t i = 0; i < numRegArgsUsed; ++i)
        {
            const PreparedArg& arg = args[i];

            if (regArgsUseHomeSlot[i])
            {
                const MicroOpBits argBits    = preparedArgBits(arg);
                const uint64_t    homeOffset = callArgStackOffset(conv, i);
                if (arg.isFloat)
                {
                    SWC_ASSERT(i < conv.floatArgRegs.size());
                    builder.emitLoadRegMem(conv.floatArgRegs[i], conv.stackPointer, homeOffset, argBits);
                }
                else
                {
                    SWC_ASSERT(i < conv.intArgRegs.size());
                    builder.emitLoadRegMem(conv.intArgRegs[i], conv.stackPointer, homeOffset, argBits);
                }
                continue;
            }

            SWC_ASSERT(!arg.isFloat);
            SWC_ASSERT(i < conv.intArgRegs.size());
            switch (arg.kind)
            {
                case PreparedArgKind::Direct:
                    builder.emitLoadRegReg(conv.intArgRegs[i], arg.srcReg, MicroOpBits::B64);
                    break;

                case PreparedArgKind::InterfaceObject:
                    builder.emitLoadRegMem(conv.intArgRegs[i], arg.srcReg, offsetof(Runtime::Interface, obj), MicroOpBits::B64);
                    break;

                default:
                    SWC_UNREACHABLE();
            }
        }

        preparedCall.stackAlreadyAdjusted = stackAdjust != 0;
        return preparedCall;
    }

    for (uint32_t i = 0; i < numPreparedArgs; ++i)
    {
        const PreparedArg& arg = args[i];

        if (arg.srcReg.isVirtual())
        {
            if (arg.isFloat)
            {
                if (arg.srcReg.isVirtualFloat())
                    builder.addVirtualRegForbiddenPhysRegs(arg.srcReg, conv.floatArgRegs);
            }
            else
            {
                if (arg.srcReg.isVirtualInt())
                    builder.addVirtualRegForbiddenPhysRegs(arg.srcReg, conv.intArgRegs);
            }
        }

        switch (arg.kind)
        {
            case PreparedArgKind::Direct:
            {
                const MicroOpBits argBits = preparedArgBits(arg);
                if (arg.isFloat)
                {
                    SWC_ASSERT(i < conv.floatArgRegs.size());
                    if (arg.isAddressed)
                        builder.emitLoadRegMem(conv.floatArgRegs[i], arg.srcReg, 0, argBits);
                    else
                        builder.emitLoadRegReg(conv.floatArgRegs[i], arg.srcReg, argBits);
                }
                else
                {
                    SWC_ASSERT(i < conv.intArgRegs.size());
                    if (arg.isAddressed)
                        builder.emitLoadRegMem(conv.intArgRegs[i], arg.srcReg, 0, argBits);
                    else
                        builder.emitLoadRegReg(conv.intArgRegs[i], arg.srcReg, argBits);
                }
                break;
            }

            case PreparedArgKind::InterfaceObject:
            {
                SWC_ASSERT(!arg.isFloat);
                SWC_ASSERT(i < conv.intArgRegs.size());
                builder.emitLoadRegMem(conv.intArgRegs[i], arg.srcReg, offsetof(Runtime::Interface, obj), MicroOpBits::B64);
                break;
            }

            default:
                SWC_UNREACHABLE();
        }
    }

    return preparedCall;
}

ABICall::PreparedCall ABICall::prepareArgs(MicroBuilder& builder, CallConvKind callConvKind, std::span<const PreparedArg> args, const ABITypeNormalize::NormalizedType& ret)
{
    if (!ret.isIndirect)
        return prepareArgs(builder, callConvKind, args);

    // Indirect returns consume a hidden first argument pointing to return storage.
    const CallConv& conv = CallConv::get(callConvKind);
    SWC_ASSERT(!conv.intArgRegs.empty());
    SWC_ASSERT(ret.indirectSize != 0);

    void* indirectRetStorage = builder.ctx().compiler().allocateArray<uint8_t>(ret.indirectSize);

    MicroReg hiddenRetArgSrcReg = MicroReg::invalid();
    MicroReg hiddenRetArgTmpReg = MicroReg::invalid();
    SWC_ASSERT(conv.tryPickIntScratchRegs(hiddenRetArgSrcReg, hiddenRetArgTmpReg));
    builder.emitLoadRegPtrImm(hiddenRetArgSrcReg, reinterpret_cast<uint64_t>(indirectRetStorage));

    SmallVector<PreparedArg> preparedArgsWithHiddenRetArg;
    preparedArgsWithHiddenRetArg.reserve(args.size() + 1);

    PreparedArg hiddenRetArg;
    hiddenRetArg.srcReg  = hiddenRetArgSrcReg;
    hiddenRetArg.kind    = PreparedArgKind::Direct;
    hiddenRetArg.isFloat = false;
    hiddenRetArg.numBits = 64;
    preparedArgsWithHiddenRetArg.push_back(hiddenRetArg);

    for (const PreparedArg& arg : args)
        preparedArgsWithHiddenRetArg.push_back(arg);

    return prepareArgs(builder, callConvKind, preparedArgsWithHiddenRetArg);
}

void ABICall::storeValueToReturnBuffer(MicroBuilder& builder, CallConvKind callConvKind, MicroReg outputStorageReg, MicroReg valueReg, bool valueIsLValue, const ABITypeNormalize::NormalizedType& ret)
{
    if (ret.isVoid)
        return;

    materializeValueToReturnRegs(builder, callConvKind, valueReg, valueIsLValue, ret);
    storeReturnRegsToReturnBuffer(builder, callConvKind, outputStorageReg, ret);
}

void ABICall::storeReturnRegsToReturnBuffer(MicroBuilder& builder, CallConvKind callConvKind, MicroReg outputStorageReg, const ABITypeNormalize::NormalizedType& ret)
{
    if (ret.isVoid)
        return;

    SWC_ASSERT(!ret.isIndirect);

    const CallConv&   conv    = CallConv::get(callConvKind);
    const MicroOpBits retBits = ret.numBits ? microOpBitsFromBitWidth(ret.numBits) : MicroOpBits::B64;

    if (ret.isFloat)
        builder.emitLoadMemReg(outputStorageReg, 0, conv.floatReturn, retBits);
    else
        builder.emitLoadMemReg(outputStorageReg, 0, conv.intReturn, retBits);
}

void ABICall::materializeValueToReturnRegs(MicroBuilder& builder, CallConvKind callConvKind, MicroReg valueReg, bool valueIsLValue, const ABITypeNormalize::NormalizedType& ret)
{
    if (ret.isVoid)
        return;

    SWC_ASSERT(!ret.isIndirect);

    const CallConv&   conv    = CallConv::get(callConvKind);
    const MicroOpBits retBits = ret.numBits ? microOpBitsFromBitWidth(ret.numBits) : MicroOpBits::B64;
    SWC_ASSERT(retBits != MicroOpBits::Zero);

    if (ret.isFloat)
    {
        if (valueIsLValue)
            builder.emitLoadRegMem(conv.floatReturn, valueReg, 0, retBits);
        else
            builder.emitLoadRegReg(conv.floatReturn, valueReg, retBits);
        return;
    }

    if (valueIsLValue)
        builder.emitLoadRegMem(conv.intReturn, valueReg, 0, retBits);
    else
        builder.emitLoadRegReg(conv.intReturn, valueReg, retBits);
}

void ABICall::materializeReturnToReg(MicroBuilder& builder, MicroReg dstReg, CallConvKind callConvKind, const ABITypeNormalize::NormalizedType& ret)
{
    if (ret.isVoid)
        return;

    const CallConv& conv = CallConv::get(callConvKind);
    if (ret.isIndirect)
    {
        // For indirect returns, the return register carries the storage pointer.
        builder.emitLoadRegReg(dstReg, conv.intReturn, MicroOpBits::B64);
        return;
    }

    const MicroOpBits retBits = ret.numBits ? microOpBitsFromBitWidth(ret.numBits) : MicroOpBits::B64;
    SWC_ASSERT(retBits != MicroOpBits::Zero);

    if (ret.isFloat)
        builder.emitLoadRegReg(dstReg, conv.floatReturn, retBits);
    else
        builder.emitLoadRegReg(dstReg, conv.intReturn, retBits);
}

void ABICall::callAddress(MicroBuilder& builder, CallConvKind callConvKind, uint64_t targetAddress, std::span<const Arg> args, const Return& ret)
{
    // Fully self-contained call helper for runtime/JIT address calls.
    const CallConv& conv        = CallConv::get(callConvKind);
    const uint32_t  numArgs     = static_cast<uint32_t>(args.size());
    const uint32_t  stackAdjust = computeCallStackAdjust(callConvKind, numArgs);

    MicroReg regBase = MicroReg::invalid();
    MicroReg regTmp  = MicroReg::invalid();
    SWC_ASSERT(conv.tryPickIntScratchRegs(regBase, regTmp));

    emitCallStackAdjust(builder, conv, stackAdjust, MicroOp::Subtract);
    emitCallArgs(builder, conv, args, regBase, regTmp);
    builder.emitLoadRegPtrImm(regTmp, targetAddress);
    builder.emitCallReg(regTmp, callConvKind);
    emitReturnWriteBack(builder, conv, ret, regBase);
    emitCallStackAdjust(builder, conv, stackAdjust, MicroOp::Add);
}

void ABICall::callLocal(MicroBuilder& builder, CallConvKind callConvKind, Symbol* targetSymbol, MicroReg targetReg, const PreparedCall& preparedCall, const Return& ret)
{
    SWC_ASSERT(targetSymbol != nullptr);

    const PreparedCallStackAdjust stackAdjust = computePreparedCallStackAdjust(callConvKind, preparedCall);

    const CallConv& conv = CallConv::get(callConvKind);
    if (!targetReg.isValid())
        targetReg = conv.intReturn;

    // The temporary target register must not alias ABI argument registers.
    SWC_ASSERT(targetReg.isInt() || targetReg.isVirtualInt());
    if (targetReg.isVirtualInt())
        builder.addVirtualRegForbiddenPhysRegs(targetReg, conv.intArgRegs);

    emitCallStackAdjust(builder, conv, stackAdjust.before, MicroOp::Subtract);
    builder.emitLoadRegPtrImm(targetReg, 0, ConstantRef::invalid(), targetSymbol);
    builder.emitCallReg(targetReg, callConvKind);
    emitReturnWriteBackIfNeeded(builder, conv, ret);
    emitCallStackAdjust(builder, conv, stackAdjust.restore, MicroOp::Add);
}

void ABICall::callLocal(MicroBuilder& builder, CallConvKind callConvKind, Symbol* targetSymbol, const PreparedCall& preparedCall, const Return& ret)
{
    callLocal(builder, callConvKind, targetSymbol, MicroReg::invalid(), preparedCall, ret);
}

void ABICall::callExtern(MicroBuilder& builder, CallConvKind callConvKind, Symbol* targetSymbol, MicroReg targetReg, const PreparedCall& preparedCall, const Return& ret)
{
    SWC_ASSERT(targetSymbol != nullptr);

    const PreparedCallStackAdjust stackAdjust = computePreparedCallStackAdjust(callConvKind, preparedCall);

    const CallConv& conv = CallConv::get(callConvKind);
    if (!targetReg.isValid())
        targetReg = conv.intReturn;

    // The temporary target register must not alias ABI argument registers.
    SWC_ASSERT(targetReg.isInt() || targetReg.isVirtualInt());
    if (targetReg.isVirtualInt())
        builder.addVirtualRegForbiddenPhysRegs(targetReg, conv.intArgRegs);

    emitCallStackAdjust(builder, conv, stackAdjust.before, MicroOp::Subtract);
    builder.emitLoadRegPtrImm(targetReg, 0, ConstantRef::invalid(), targetSymbol);
    builder.emitCallReg(targetReg, callConvKind);
    emitReturnWriteBackIfNeeded(builder, conv, ret);
    emitCallStackAdjust(builder, conv, stackAdjust.restore, MicroOp::Add);
}

void ABICall::callExtern(MicroBuilder& builder, CallConvKind callConvKind, Symbol* targetSymbol, const PreparedCall& preparedCall, const Return& ret)
{
    callExtern(builder, callConvKind, targetSymbol, MicroReg::invalid(), preparedCall, ret);
}

void ABICall::callExtern(MicroBuilder& builder, CallConvKind callConvKind, Symbol* targetSymbol, MicroReg targetReg, const PreparedCall& preparedCall)
{
    callExtern(builder, callConvKind, targetSymbol, targetReg, preparedCall, Return{});
}

void ABICall::callExtern(MicroBuilder& builder, CallConvKind callConvKind, Symbol* targetSymbol, const PreparedCall& preparedCall)
{
    callExtern(builder, callConvKind, targetSymbol, MicroReg::invalid(), preparedCall, Return{});
}

void ABICall::callReg(MicroBuilder& builder, CallConvKind callConvKind, MicroReg targetReg, const PreparedCall& preparedCall, const Return& ret)
{
    const PreparedCallStackAdjust stackAdjust = computePreparedCallStackAdjust(callConvKind, preparedCall);

    const CallConv& conv = CallConv::get(callConvKind);
    emitCallStackAdjust(builder, conv, stackAdjust.before, MicroOp::Subtract);
    builder.emitCallReg(targetReg, callConvKind);
    emitReturnWriteBackIfNeeded(builder, conv, ret);
    emitCallStackAdjust(builder, conv, stackAdjust.restore, MicroOp::Add);
}

void ABICall::callReg(MicroBuilder& builder, CallConvKind callConvKind, MicroReg targetReg, const PreparedCall& preparedCall)
{
    callReg(builder, callConvKind, targetReg, preparedCall, Return{});
}

void ABICall::callLocal(MicroBuilder& builder, CallConvKind callConvKind, Symbol* targetSymbol, MicroReg targetReg, const PreparedCall& preparedCall)
{
    callLocal(builder, callConvKind, targetSymbol, targetReg, preparedCall, Return{});
}

void ABICall::callLocal(MicroBuilder& builder, CallConvKind callConvKind, Symbol* targetSymbol, const PreparedCall& preparedCall)
{
    callLocal(builder, callConvKind, targetSymbol, MicroReg::invalid(), preparedCall, Return{});
}

SWC_END_NAMESPACE();

