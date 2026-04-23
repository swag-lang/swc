#include "pch.h"
#include "Backend/Micro/MicroUseDefMap.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"

SWC_BEGIN_NAMESPACE();

void MicroUseDefMap::build(MicroStorage& storage, MicroOperandStorage& operands, const Encoder* encoder)
{
    storage_  = &storage;
    operands_ = &operands;
    valid_    = true;

    const uint32_t slotCount = storage.slotCount();

    instrInfos_.clear();
    instrInfos_.resize(slotCount);

    instrOrder_.clear();
    instrOrder_.reserve(storage.count());

    instrOrderIndex_.clear();
    instrOrderIndex_.resize(slotCount, std::numeric_limits<uint32_t>::max());

    // Phase 1: collect instruction order and cache use-def per instruction.
    for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
    {
        const MicroInstrRef instRef  = it.current;
        const uint32_t      slot     = instRef.get();
        const uint32_t      orderIdx = static_cast<uint32_t>(instrOrder_.size());

        instrOrder_.push_back(instRef);
        instrOrderIndex_[slot] = orderIdx;

        InstrInfo& info = instrInfos_[slot];
        info.instRef    = instRef;
        info.useDef     = it->collectUseDef(operands, encoder);
    }

    // Phase 2: build reaching definitions by walking forward.
    // At each instruction, record the current reaching definition for every live register.
    // At control flow barriers, clear all reaching defs (conservative).
    const uint32_t instrCount = static_cast<uint32_t>(instrOrder_.size());
    reachingDefs_.clear();
    reachingDefs_.resize(instrCount);

    std::unordered_map<MicroReg, MicroInstrRef> currentDefs;
    currentDefs.reserve(64);

    for (uint32_t orderIdx = 0; orderIdx < instrCount; ++orderIdx)
    {
        const MicroInstrRef instRef = instrOrder_[orderIdx];
        const uint32_t      slot    = instRef.get();
        const InstrInfo&    info    = instrInfos_[slot];

        // Snapshot current reaching defs for this instruction (before it executes).
        auto& snapshot = reachingDefs_[orderIdx];
        snapshot.reserve(currentDefs.size());
        for (const auto& [reg, defRef] : currentDefs)
            snapshot.push_back({reg, defRef});

        // Check if this instruction is a control flow barrier.
        if (MicroInstrInfo::isLocalDataflowBarrier(*storage.ptr(instRef), info.useDef))
        {
            currentDefs.clear();
            continue;
        }

        // Update reaching defs with this instruction's definitions.
        for (const MicroReg defReg : info.useDef.defs)
        {
            if (defReg.isValid() && !defReg.isNoBase())
                currentDefs[defReg] = instRef;
        }

        // Calls clobber transient registers — clear those definitions.
        if (info.useDef.isCall)
            currentDefs.clear();
    }
}

const MicroUseDefMap* MicroUseDefMap::ensureFor(const MicroPassContext& context, MicroUseDefMap& localMap)
{
    if (context.useDefMap)
    {
        if (!context.useDefMap->isValid())
        {
            if (!context.instructions || !context.operands)
                return nullptr;

            context.useDefMap->build(*context.instructions, *context.operands, context.encoder);
        }

        return context.useDefMap;
    }

    if (!context.instructions || !context.operands)
        return nullptr;

    if (!localMap.isValid())
        localMap.build(*context.instructions, *context.operands, context.encoder);

    return &localMap;
}

void MicroUseDefMap::invalidate()
{
    valid_ = false;
}

MicroUseDefMap::ReachingDef MicroUseDefMap::reachingDef(MicroReg reg, MicroInstrRef beforeInstRef) const
{
    SWC_ASSERT(valid_);
    SWC_ASSERT(storage_ != nullptr);

    const uint32_t slot = beforeInstRef.get();
    if (slot >= instrOrderIndex_.size())
        return {};

    const uint32_t orderIdx = instrOrderIndex_[slot];
    if (orderIdx >= reachingDefs_.size())
        return {};

    const auto& snapshot = reachingDefs_[orderIdx];
    for (const RegDefEntry& entry : snapshot)
    {
        if (entry.reg == reg)
        {
            ReachingDef result;
            result.instRef = entry.instRef;
            result.inst    = storage_->ptr(entry.instRef);
            return result;
        }
    }

    return {};
}

const MicroInstrUseDef* MicroUseDefMap::instrUseDef(MicroInstrRef instRef) const
{
    SWC_ASSERT(valid_);
    const uint32_t slot = instRef.get();
    if (slot >= instrInfos_.size())
        return nullptr;

    return &instrInfos_[slot].useDef;
}

bool MicroUseDefMap::isRegUsedAfter(MicroReg reg, MicroInstrRef afterInstRef) const
{
    SWC_ASSERT(valid_);
    SWC_ASSERT(storage_ != nullptr);

    if (!reg.isValid() || reg.isNoBase())
        return false;

    const uint32_t slot = afterInstRef.get();
    if (slot >= instrOrderIndex_.size())
        return false;

    const uint32_t startOrderIdx = instrOrderIndex_[slot];
    if (startOrderIdx >= instrOrder_.size())
        return false;

    for (uint32_t orderIdx = startOrderIdx + 1; orderIdx < instrOrder_.size(); ++orderIdx)
    {
        const MicroInstrRef scanRef  = instrOrder_[orderIdx];
        const uint32_t      scanSlot = scanRef.get();
        const InstrInfo&    info     = instrInfos_[scanSlot];

        // Check uses before defs: if the instruction uses the register, it's live.
        if (microRegSpanContains(info.useDef.uses, reg))
            return true;

        // If the instruction redefines the register, the old value is dead.
        if (microRegSpanContains(info.useDef.defs, reg))
            return false;

        // At a barrier, conservatively assume the register could be used.
        const MicroInstr* inst = storage_->ptr(scanRef);
        if (inst && MicroInstrInfo::isLocalDataflowBarrier(*inst, info.useDef))
            return true;
    }

    return false;
}

SWC_END_NAMESPACE();
