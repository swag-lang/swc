#include "pch.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/Passes/MicroPeepholePass.Private.h"

SWC_BEGIN_NAMESPACE();

namespace PeepholePass
{
    namespace
    {
        bool isRegPersistentAcrossCalls(const MicroPassContext& context, MicroReg reg)
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

    bool isCopyDeadAfterInstruction(const MicroPassContext& context, MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, MicroReg reg)
    {
        for (; scanIt != endIt; ++scanIt)
        {
            const MicroInstr&                    scanInst = *scanIt;
            const MicroInstrUseDef               useDef   = scanInst.collectUseDef(*SWC_CHECK_NOT_NULL(context.operands), context.encoder);
            SmallVector<MicroInstrRegOperandRef> refs;
            scanInst.collectRegOperands(*SWC_CHECK_NOT_NULL(context.operands), refs, context.encoder);

            bool hasUse = false;
            bool hasDef = false;
            for (const MicroInstrRegOperandRef& ref : refs)
            {
                if (!ref.reg || *SWC_CHECK_NOT_NULL(ref.reg) != reg)
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

            if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                return false;
        }

        return true;
    }

    bool isTempDeadForAddressFold(const MicroPassContext& context, MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt, MicroReg reg)
    {
        for (; scanIt != endIt; ++scanIt)
        {
            const MicroInstr&                    scanInst = *scanIt;
            const MicroInstrUseDef               useDef   = scanInst.collectUseDef(*SWC_CHECK_NOT_NULL(context.operands), context.encoder);
            SmallVector<MicroInstrRegOperandRef> refs;
            scanInst.collectRegOperands(*SWC_CHECK_NOT_NULL(context.operands), refs, context.encoder);

            bool hasUse = false;
            bool hasDef = false;
            for (const MicroInstrRegOperandRef& ref : refs)
            {
                if (!ref.reg || *SWC_CHECK_NOT_NULL(ref.reg) != reg)
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
                if (!isRegPersistentAcrossCalls(context, reg))
                    return true;
                return false;
            }

            if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                return false;
        }

        return true;
    }

    bool areFlagsDeadAfterInstruction(const MicroPassContext& context, MicroStorage::Iterator scanIt, const MicroStorage::Iterator& endIt)
    {
        ++scanIt;
        for (; scanIt != endIt; ++scanIt)
        {
            const MicroInstr&      scanInst = *scanIt;
            const MicroInstrUseDef useDef   = scanInst.collectUseDef(*SWC_CHECK_NOT_NULL(context.operands), context.encoder);

            if (MicroInstrInfo::usesCpuFlags(scanInst))
                return false;

            if (MicroInstrInfo::definesCpuFlags(scanInst))
                return true;

            if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
                return true;
        }

        return true;
    }

}

SWC_END_NAMESPACE();

