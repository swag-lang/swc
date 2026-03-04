#include "pch.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/Passes/Pass.Peephole.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isFloatArgReg(const CallConv& conv, const MicroReg reg)
    {
        if (!reg.isFloat())
            return false;

        for (const MicroReg argReg : conv.floatArgRegs)
        {
            if (argReg == reg)
                return true;
        }

        return false;
    }

    bool isRegCallArgument(const CallConv& conv, const MicroReg reg)
    {
        if (!reg.isValid() || reg.isNoBase())
            return false;

        if (reg.isInt())
            return conv.isIntArgReg(reg);
        if (reg.isFloat())
            return isFloatArgReg(conv, reg);

        return false;
    }

    bool isRegPersistentAcrossCalls(const MicroPassContext& context, const MicroReg reg)
    {
        if (!reg.isValid() || reg.isNoBase())
            return false;

        const CallConv& conv = CallConv::get(context.callConvKind);
        if (reg.isInt())
            return conv.isIntPersistentReg(reg);
        if (reg.isFloat())
            return conv.isFloatPersistentReg(reg);
        return false;
    }
}

bool MicroPeepholePass::isCopyDeadAfterInstruction(MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, const MicroReg reg) const
{
    SWC_ASSERT(context_ != nullptr);
    SWC_ASSERT(operands_ != nullptr);

    for (; scanIt != endIt; ++scanIt)
    {
        const MicroInstr&                    scanInst = *scanIt;
        const MicroInstrUseDef               useDef   = scanInst.collectUseDef(*operands_, context_->encoder);
        SmallVector<MicroInstrRegOperandRef> refs;
        scanInst.collectRegOperands(*operands_, refs, context_->encoder);

        bool hasUse = false;
        bool hasDef = false;
        for (const MicroInstrRegOperandRef& ref : refs)
        {
            if (!ref.reg || *(ref.reg) != reg)
                continue;

            hasUse |= ref.use;
            hasDef |= ref.def;
        }

        if (hasUse)
            return false;

        if (hasDef)
            return true;

        if (scanInst.op == MicroInstrOpcode::Ret)
        {
            const CallConv& functionConv = CallConv::get(context_->callConvKind);
            if (functionConv.intReturn == reg || functionConv.floatReturn == reg)
                return false;
            return true;
        }

        if (useDef.isCall)
        {
            const CallConv& callConv = CallConv::get(useDef.callConv);
            if (isRegCallArgument(callConv, reg))
                return false;

            if (!isRegPersistentAcrossCalls(*context_, reg))
                return true;

            continue;
        }

        if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
            return false;
    }

    return true;
}

bool MicroPeepholePass::isTempDeadForAddressFold(MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, const MicroReg reg) const
{
    SWC_ASSERT(context_ != nullptr);
    SWC_ASSERT(operands_ != nullptr);

    for (; scanIt != endIt; ++scanIt)
    {
        const MicroInstr&                    scanInst = *scanIt;
        const MicroInstrUseDef               useDef   = scanInst.collectUseDef(*operands_, context_->encoder);
        SmallVector<MicroInstrRegOperandRef> refs;
        scanInst.collectRegOperands(*operands_, refs, context_->encoder);

        bool hasUse = false;
        bool hasDef = false;
        for (const MicroInstrRegOperandRef& ref : refs)
        {
            if (!ref.reg || *(ref.reg) != reg)
                continue;

            hasUse |= ref.use;
            hasDef |= ref.def;
        }

        if (hasUse)
            return false;

        if (hasDef)
            return true;

        if (scanInst.op == MicroInstrOpcode::Ret)
            return true;

        if (useDef.isCall)
        {
            if (!isRegPersistentAcrossCalls(*context_, reg))
                return true;
            return false;
        }

        if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
            return false;
    }

    return true;
}

bool MicroPeepholePass::isRegUnusedAfterInstruction(MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, const MicroReg reg) const
{
    SWC_ASSERT(context_ != nullptr);
    SWC_ASSERT(operands_ != nullptr);

    if (!reg.isValid() || reg.isNoBase())
        return true;

    const CallConv& functionConv = CallConv::get(context_->callConvKind);
    for (; scanIt != endIt; ++scanIt)
    {
        const MicroInstr&                    scanInst = *scanIt;
        const MicroInstrUseDef               useDef   = scanInst.collectUseDef(*operands_, context_->encoder);
        SmallVector<MicroInstrRegOperandRef> refs;
        scanInst.collectRegOperands(*operands_, refs, context_->encoder);

        for (const MicroInstrRegOperandRef& ref : refs)
        {
            if (!ref.use || !ref.reg || *(ref.reg) != reg)
                continue;

            return false;
        }

        if (useDef.isCall)
        {
            const CallConv& callConv = CallConv::get(useDef.callConv);
            if (isRegCallArgument(callConv, reg))
                return false;
        }

        if (scanInst.op == MicroInstrOpcode::Ret)
        {
            if (functionConv.intReturn == reg || functionConv.floatReturn == reg)
                return false;
        }
    }

    return true;
}

bool MicroPeepholePass::areFlagsDeadAfterInstruction(MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt) const
{
    SWC_ASSERT(context_ != nullptr);
    SWC_ASSERT(operands_ != nullptr);

    ++scanIt;
    for (; scanIt != endIt; ++scanIt)
    {
        const MicroInstr&      scanInst = *scanIt;
        const MicroInstrUseDef useDef   = scanInst.collectUseDef(*operands_, context_->encoder);

        if (MicroInstrInfo::usesCpuFlags(scanInst))
            return false;

        if (MicroInstrInfo::definesCpuFlags(scanInst))
            return true;

        if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
            return true;
    }

    return true;
}

SWC_END_NAMESPACE();
