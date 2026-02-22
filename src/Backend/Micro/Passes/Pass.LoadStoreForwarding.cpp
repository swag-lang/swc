#include "pch.h"
#include "Backend/Micro/Passes/Pass.LoadStoreForwarding.h"
#include "Backend/Micro/MicroInstrInfo.h"

// Forwards recent store values into matching following loads.
// Example: store [rbp+8], r1; load r2, [rbp+8] -> mov r2, r1.
// Example: store [rbp+8], 5;  load r2, [rbp+8] -> load r2, 5.
// This removes redundant memory traffic when aliasing is provably safe.

SWC_BEGIN_NAMESPACE();

namespace
{
    bool containsDef(std::span<const MicroReg> defs, MicroReg reg)
    {
        for (const MicroReg defReg : defs)
        {
            if (defReg == reg)
                return true;
        }

        return false;
    }

    bool writesMemory(const MicroInstr& inst)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadMemReg:
            case MicroInstrOpcode::LoadMemImm:
            case MicroInstrOpcode::LoadAmcMemReg:
            case MicroInstrOpcode::LoadAmcMemImm:
            case MicroInstrOpcode::OpUnaryMem:
            case MicroInstrOpcode::OpBinaryMemReg:
            case MicroInstrOpcode::OpBinaryMemImm:
            case MicroInstrOpcode::Push:
            case MicroInstrOpcode::Pop:
                return true;
            default:
                return false;
        }
    }

    bool isSameMemoryAddress(const MicroInstrOperand* storeOps, const MicroInstrOperand* loadOps)
    {
        return storeOps[0].reg == loadOps[1].reg &&
               storeOps[3].valueU64 == loadOps[3].valueU64 &&
               storeOps[2].opBits == loadOps[2].opBits;
    }

    bool isSameMemoryAddressForImmediateStore(const MicroInstrOperand* storeOps, const MicroInstrOperand* loadOps)
    {
        return storeOps[0].reg == loadOps[1].reg &&
               storeOps[2].valueU64 == loadOps[3].valueU64 &&
               storeOps[1].opBits == loadOps[2].opBits;
    }

    bool canCrossInstruction(const MicroPassContext& context, const MicroInstr& store, const MicroInstrOperand* storeOps, const MicroInstr& scanInst)
    {
        const MicroInstrUseDef useDef = scanInst.collectUseDef(*SWC_CHECK_NOT_NULL(context.operands), context.encoder);
        if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
            return false;
        if (writesMemory(scanInst))
            return false;

        const MicroReg storeBaseReg = storeOps[0].reg;
        if (containsDef(useDef.defs, storeBaseReg))
            return false;

        if (store.op == MicroInstrOpcode::LoadMemReg)
        {
            const MicroReg storeValueReg = storeOps[1].reg;
            if (containsDef(useDef.defs, storeValueReg))
                return false;
        }

        return true;
    }
}

bool MicroLoadStoreForwardingPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    bool                 changed  = false;
    MicroStorage&        storage  = *SWC_CHECK_NOT_NULL(context.instructions);
    MicroOperandStorage& operands = *SWC_CHECK_NOT_NULL(context.operands);

    for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
    {
        MicroInstr& first = *it;
        if (first.op != MicroInstrOpcode::LoadMemReg && first.op != MicroInstrOpcode::LoadMemImm)
            continue;

        const MicroInstrOperand* firstOps = first.ops(operands);
        if (!firstOps)
            continue;

        for (auto scanIt = std::next(it); scanIt != storage.view().end(); ++scanIt)
        {
            MicroInstr& scanInst = *scanIt;
            if (scanInst.op == MicroInstrOpcode::LoadRegMem)
            {
                MicroInstrOperand* scanOps = scanInst.ops(operands);
                if (!scanOps)
                    break;

                if (first.op == MicroInstrOpcode::LoadMemReg && isSameMemoryAddress(firstOps, scanOps))
                {
                    scanInst.op          = MicroInstrOpcode::LoadRegReg;
                    scanInst.numOperands = 3;
                    scanOps[1].reg       = firstOps[1].reg;
                    scanOps[2].opBits    = firstOps[2].opBits;
                    changed              = true;
                    break;
                }

                if (first.op == MicroInstrOpcode::LoadMemImm && isSameMemoryAddressForImmediateStore(firstOps, scanOps))
                {
                    scanInst.op            = MicroInstrOpcode::LoadRegImm;
                    scanInst.numOperands   = 3;
                    scanOps[1].opBits      = firstOps[1].opBits;
                    scanOps[2].valueU64    = firstOps[3].valueU64;
                    changed                = true;
                    break;
                }
            }

            if (!canCrossInstruction(context, first, firstOps, scanInst))
                break;
        }
    }

    return changed;
}

SWC_END_NAMESPACE();
