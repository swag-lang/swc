#include "pch.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.LoadStoreForwarding.h"

SWC_BEGIN_NAMESPACE();

bool MicroLoadStoreForwardingPass::promoteStackSlotLoads()
{
    SWC_ASSERT(context_ != nullptr);
    SWC_ASSERT(storage_ != nullptr);
    SWC_ASSERT(operands_ != nullptr);

    bool         updated = false;
    StackSlotMap slotValues;

    for (auto& inst : storage_->view())
    {
        MicroInstrOperand* const ops = inst.ops(*operands_);
        if (!ops)
        {
            slotValues.clear();
            continue;
        }

        const MicroInstrUseDef useDef = inst.collectUseDef(*operands_, context_->encoder);
        if (MicroInstrInfo::isLocalDataflowBarrier(inst, useDef))
        {
            slotValues.clear();
            continue;
        }

        if (inst.op == MicroInstrOpcode::LoadRegMem)
        {
            StackSlotKey slotKey;
            if (getStackSlotKey(slotKey, inst, ops))
            {
                const auto valueIt = slotValues.find(slotKey);
                if (valueIt != slotValues.end())
                {
                    const StackSlotValue& slotValue = valueIt->second;
                    if (slotValue.kind == StackSlotValueKind::Register &&
                        slotValue.reg.isValid() &&
                        ops[0].reg.isSameClass(slotValue.reg))
                    {
                        inst.op          = MicroInstrOpcode::LoadRegReg;
                        inst.numOperands = 3;
                        ops[1].reg       = slotValue.reg;
                        ops[2].opBits    = slotKey.opBits;
                        updated          = true;
                    }
                    else if (slotValue.kind == StackSlotValueKind::Immediate &&
                             ops[0].reg.isInt() &&
                             getNumBits(slotKey.opBits) <= 64)
                    {
                        inst.op          = MicroInstrOpcode::LoadRegImm;
                        inst.numOperands = 3;
                        ops[1].opBits    = slotKey.opBits;
                        ops[2].valueU64  = slotValue.immediate;
                        updated          = true;
                    }
                }
            }
        }

        bool clearAllSlots = false;
        for (const MicroReg defReg : useDef.defs)
        {
            if (MicroPassHelpers::isStackBaseRegister(*context_, defReg))
            {
                clearAllSlots = true;
                break;
            }
        }

        if (clearAllSlots)
        {
            slotValues.clear();
        }
        else
        {
            for (const MicroReg defReg : useDef.defs)
                invalidateSlotsUsingRegister(slotValues, defReg);
        }

        if (!MicroInstrInfo::isMemoryWriteInstruction(inst))
            continue;

        StackSlotKey slotKey;
        if (!getStackSlotKey(slotKey, inst, ops))
        {
            slotValues.clear();
            continue;
        }

        invalidateOverlappingSlots(slotValues, slotKey);

        if (inst.op == MicroInstrOpcode::LoadMemReg)
        {
            StackSlotValue slotValue;
            slotValue.kind      = StackSlotValueKind::Register;
            slotValue.reg       = ops[1].reg;
            slotValues[slotKey] = slotValue;
        }
        else if (inst.op == MicroInstrOpcode::LoadMemImm)
        {
            StackSlotValue slotValue;
            slotValue.kind      = StackSlotValueKind::Immediate;
            slotValue.immediate = ops[3].valueU64;
            slotValues[slotKey] = slotValue;
        }
    }

    return updated;
}

SWC_END_NAMESPACE();
