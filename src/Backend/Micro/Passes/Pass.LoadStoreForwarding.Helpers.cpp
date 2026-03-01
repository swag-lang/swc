#include "pch.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.LoadStoreForwarding.Private.h"

SWC_BEGIN_NAMESPACE();

namespace LoadStoreForwardingPass
{
    bool getStackSlotKey(StackSlotKey& outKey, const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        if (!ops)
            return false;

        uint8_t baseIndex   = 0;
        uint8_t offsetIndex = 0;
        if (!MicroInstrInfo::getMemBaseOffsetOperandIndices(baseIndex, offsetIndex, inst))
            return false;

        const MicroReg baseReg = ops[baseIndex].reg;
        if (!MicroPassHelpers::isStackBaseRegister(context, baseReg))
            return false;

        auto opBits = MicroOpBits::Zero;
        if (!MicroPassHelpers::getMemAccessOpBits(opBits, inst, ops))
            return false;

        outKey.baseReg = baseReg;
        outKey.offset  = ops[offsetIndex].valueU64;
        outKey.opBits  = opBits;
        return true;
    }

    void invalidateOverlappingSlots(StackSlotMap& slots, const StackSlotKey& targetKey)
    {
        const uint32_t targetSize = getNumBytes(targetKey.opBits);
        if (!targetSize)
        {
            slots.clear();
            return;
        }

        for (auto it = slots.begin(); it != slots.end();)
        {
            const StackSlotKey& slotKey  = it->first;
            const uint32_t      slotSize = getNumBytes(slotKey.opBits);
            if (slotSize &&
                slotKey.baseReg == targetKey.baseReg &&
                MicroPassHelpers::rangesOverlap(slotKey.offset, slotSize, targetKey.offset, targetSize))
            {
                it = slots.erase(it);
            }
            else
            {
                ++it;
            }
        }
    }

    void invalidateSlotsUsingRegister(StackSlotMap& slots, const MicroReg reg)
    {
        if (!reg.isValid() || reg.isNoBase())
            return;

        for (auto it = slots.begin(); it != slots.end();)
        {
            const StackSlotValue& slotValue = it->second;
            if (slotValue.kind == StackSlotValueKind::Register && slotValue.reg == reg)
            {
                it = slots.erase(it);
            }
            else
            {
                ++it;
            }
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
        const MicroInstrUseDef useDef = scanInst.collectUseDef(*context.operands, context.encoder);
        if (MicroInstrInfo::isLocalDataflowBarrier(scanInst, useDef))
            return false;
        if (MicroInstrInfo::isMemoryWriteInstruction(scanInst))
            return false;

        const MicroReg storeBaseReg = storeOps[0].reg;
        if (microRegSpanContains(useDef.defs, storeBaseReg))
            return false;

        if (store.op == MicroInstrOpcode::LoadMemReg)
        {
            const MicroReg storeValueReg = storeOps[1].reg;
            if (microRegSpanContains(useDef.defs, storeValueReg))
                return false;
        }

        return true;
    }
}

SWC_END_NAMESPACE();
