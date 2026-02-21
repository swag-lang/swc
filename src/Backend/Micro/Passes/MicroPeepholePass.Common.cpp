#include "pch.h"
#include "Backend/Micro/Passes/MicroPeepholePass.Private.h"
#include "Backend/Micro/MicroOptimization.h"

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

        bool usesCpuFlags(const MicroInstr& inst)
        {
            switch (inst.op)
            {
                case MicroInstrOpcode::JumpCond:
                case MicroInstrOpcode::JumpCondImm:
                case MicroInstrOpcode::SetCondReg:
                case MicroInstrOpcode::LoadCondRegReg:
                    return true;
                default:
                    return false;
            }
        }

        bool definesCpuFlags(const MicroInstr& inst)
        {
            switch (inst.op)
            {
                case MicroInstrOpcode::CmpRegReg:
                case MicroInstrOpcode::CmpRegZero:
                case MicroInstrOpcode::CmpRegImm:
                case MicroInstrOpcode::CmpMemReg:
                case MicroInstrOpcode::CmpMemImm:
                case MicroInstrOpcode::ClearReg:
                case MicroInstrOpcode::OpUnaryMem:
                case MicroInstrOpcode::OpUnaryReg:
                case MicroInstrOpcode::OpBinaryRegReg:
                case MicroInstrOpcode::OpBinaryRegImm:
                case MicroInstrOpcode::OpBinaryRegMem:
                case MicroInstrOpcode::OpBinaryMemReg:
                case MicroInstrOpcode::OpBinaryMemImm:
                    return true;
                default:
                    return false;
            }
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

            if (MicroOptimization::isLocalDataflowBarrier(scanInst, useDef))
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

            if (MicroOptimization::isLocalDataflowBarrier(scanInst, useDef))
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

            if (usesCpuFlags(scanInst))
                return false;

            if (definesCpuFlags(scanInst))
                return true;

            if (MicroOptimization::isLocalDataflowBarrier(scanInst, useDef))
                return true;
        }

        return true;
    }

    bool getMemBaseOffsetOperandIndices(uint8_t& outBaseIndex, uint8_t& outOffsetIndex, const MicroInstr& inst)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegMem:
                outBaseIndex   = 1;
                outOffsetIndex = 3;
                return true;
            case MicroInstrOpcode::LoadMemReg:
                outBaseIndex   = 0;
                outOffsetIndex = 3;
                return true;
            case MicroInstrOpcode::LoadMemImm:
                outBaseIndex   = 0;
                outOffsetIndex = 2;
                return true;
            case MicroInstrOpcode::LoadSignedExtRegMem:
                outBaseIndex   = 1;
                outOffsetIndex = 4;
                return true;
            case MicroInstrOpcode::LoadZeroExtRegMem:
                outBaseIndex   = 1;
                outOffsetIndex = 4;
                return true;
            case MicroInstrOpcode::LoadAddrRegMem:
                outBaseIndex   = 1;
                outOffsetIndex = 3;
                return true;
            case MicroInstrOpcode::CmpMemReg:
                outBaseIndex   = 0;
                outOffsetIndex = 3;
                return true;
            case MicroInstrOpcode::CmpMemImm:
                outBaseIndex   = 0;
                outOffsetIndex = 2;
                return true;
            case MicroInstrOpcode::OpUnaryMem:
                outBaseIndex   = 0;
                outOffsetIndex = 3;
                return true;
            case MicroInstrOpcode::OpBinaryRegMem:
                outBaseIndex   = 1;
                outOffsetIndex = 4;
                return true;
            case MicroInstrOpcode::OpBinaryMemReg:
                outBaseIndex   = 0;
                outOffsetIndex = 4;
                return true;
            case MicroInstrOpcode::OpBinaryMemImm:
                outBaseIndex   = 0;
                outOffsetIndex = 3;
                return true;
            default:
                return false;
        }
    }
}

SWC_END_NAMESPACE();
