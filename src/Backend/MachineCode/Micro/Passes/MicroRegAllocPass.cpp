#include "pch.h"
#include "Backend/MachineCode/Micro/Passes/MicroRegAllocPass.h"
#include "Backend/MachineCode/Encoder/Encoder.h"
#include "Backend/MachineCode/Micro/MicroInstr.h"
#include "Support/Core/PagedStoreTyped.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

void MicroRegAllocPass::run(MicroPassContext& context)
{
    // Preconditions: this pass requires instruction stream and operand store.
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);

    // Function-level calling convention: defines available integer/float regs and which are call-preserved.
    const auto& funcConv = CallConv::get(context.callConvKind);
    const auto& store    = context.operands->store();

    const uint32_t instructionCount = context.instructions->count();
    if (instructionCount == 0)
        return;

    // regCallMask: virtRegKey -> bitmask of callconvs for which this vreg is live across a call.
    // (In current code only presence/absence is used.)
    std::unordered_map<uint32_t, uint32_t> regCallMask;

    // liveOut[i] holds the set of *virtual* regs live-out of instruction i.
    std::vector<std::vector<uint32_t>> liveOut(instructionCount);

    // Current live set while scanning backwards. Contains packed virt reg keys.
    std::unordered_set<uint32_t> live;

    // Reverse pass: build liveOut and record which vregs are live across calls.
    uint32_t idx  = instructionCount;
    auto     view = context.instructions->view();
    for (auto it = view.rbegin(); it != view.rend(); ++it)
    {
        --idx;
        auto& inst = *it;

        // Snapshot current live set as live-out of this instruction.
        liveOut[idx].assign(live.begin(), live.end());

        const auto info = MicroInstr::collectUseDef(inst, store, context.encoder);

        // If this instruction is a call, any currently live vreg is live across a call site.
        // Record that we must allocate it to a call-preserved register class (persistent pool).
        if (info.isCall)
        {
            const uint32_t bit = 1u << static_cast<uint32_t>(info.callConv);
            for (auto regKey : live)
                regCallMask[regKey] |= bit;
        }

        // Standard backward liveness update:
        // - defs kill (remove) a vreg from the live set
        // - uses add a vreg to the live set
        for (const auto& reg : info.defs)
        {
            if (reg.isVirtual())
                live.erase(reg.packed);
        }
        for (const auto& reg : info.uses)
        {
            if (reg.isVirtual())
                live.insert(reg.packed);
        }
    }

    // Build fast lookup sets of call-preserved physical regs for the current function convention.
    std::unordered_set<uint32_t> intPersistentSet;
    std::unordered_set<uint32_t> floatPersistentSet;
    for (const auto& reg : funcConv.intPersistentRegs)
        intPersistentSet.insert(reg.packed);
    for (const auto& reg : funcConv.floatPersistentRegs)
        floatPersistentSet.insert(reg.packed);

    // Free lists (pools) for allocating physical regs:
    // - transient: caller-saved / not required to survive calls
    // - persistent: call-preserved / should survive calls
    SmallVector<MicroReg, 16> freeIntTransient;
    SmallVector<MicroReg, 16> freeIntPersistent;
    SmallVector<MicroReg, 8>  freeFloatTransient;
    SmallVector<MicroReg, 8>  freeFloatPersistent;

    // Initialize free lists by partitioning available regs into persistent vs. transient pools.
    for (const auto& reg : funcConv.intRegs)
    {
        if (intPersistentSet.contains(reg.packed))
            freeIntPersistent.push_back(reg);
        else
            freeIntTransient.push_back(reg);
    }

    for (const auto& reg : funcConv.floatRegs)
    {
        if (floatPersistentSet.contains(reg.packed))
            freeFloatPersistent.push_back(reg);
        else
            freeFloatTransient.push_back(reg);
    }

    // Return a physical reg to the appropriate pool when a vreg dies.
    auto freePhysical = [&](MicroReg reg) {
        if (reg.isInt())
        {
            if (intPersistentSet.contains(reg.packed))
                freeIntPersistent.push_back(reg);
            else
                freeIntTransient.push_back(reg);
        }
        else if (reg.isFloat())
        {
            if (floatPersistentSet.contains(reg.packed))
                freeFloatPersistent.push_back(reg);
            else
                freeFloatTransient.push_back(reg);
        }
    };

    // Allocate a physical register for a given virtual register key.
    // If virtKey is live across any call, allocate from a persistent pool (call-preserved).
    // Otherwise, prefer transient, falling back to persistent if transient is empty.
    auto allocatePhysical = [&](MicroReg virtReg, uint32_t virtKey) -> MicroReg {
        const bool needsPersistent = regCallMask.contains(virtKey);

        if (virtReg.isVirtualInt())
        {
            SmallVector<MicroReg, 16>* pool = nullptr;

            if (needsPersistent)
                pool = &freeIntPersistent;
            else if (!freeIntTransient.empty())
                pool = &freeIntTransient;
            else
                pool = &freeIntPersistent;

            // No spill support: assumes some physical reg is available.
            SWC_ASSERT(pool && !pool->empty());

            const auto reg = pool->back();
            pool->pop_back();
            return reg;
        }

        // Float path.
        SWC_ASSERT(virtReg.isVirtualFloat());

        SmallVector<MicroReg, 8>* pool = nullptr;
        if (needsPersistent)
            pool = &freeFloatPersistent;
        else if (!freeFloatTransient.empty())
            pool = &freeFloatTransient;
        else
            pool = &freeFloatPersistent;

        SWC_ASSERT(pool && !pool->empty());

        const auto reg = pool->back();
        pool->pop_back();
        return reg;
    };

    // mapping: virtKey -> allocated physical reg (current live mapping).
    std::unordered_map<uint32_t, MicroReg> mapping;

    // liveStamp: virtKey -> last stamp where the vreg was considered live-out of the current instruction.
    // Using stamps avoids clearing a set each iteration; values not updated this instruction are considered dead.
    std::unordered_map<uint32_t, uint32_t> liveStamp;
    uint32_t                               stamp = 1;

    // Forward pass: rewrite operands from virtual regs to physical regs using liveOut.
    idx = 0;
    for (auto& inst : context.instructions->view())
    {
        // New instruction "epoch".
        ++stamp;

        // Mark all vregs live-out of this instruction with the current stamp.
        for (auto regKey : liveOut[idx])
            liveStamp[regKey] = stamp;

        // Collect all register operands in this instruction for in-place rewriting.
        SmallVector<MicroInstrRegOperandRef, 8> regs;
        MicroInstr::collectRegOperands(inst, context.operands->store(), regs, context.encoder);

        // Replace each virtual operand with its allocated physical reg.
        // Allocation happens at first sight; later uses reuse the mapping.
        for (auto& regRef : regs)
        {
            const auto reg = *regRef.reg;
            if (!reg.isVirtual())
                continue;

            const uint32_t key = reg.packed;
            auto           it  = mapping.find(key);
            if (it == mapping.end())
            {
                const auto physReg = allocatePhysical(reg, key);
                it                 = mapping.emplace(key, physReg).first;
            }
            *regRef.reg = it->second;
        }

        // Expire mappings for vregs not live-out of this instruction.
        // When a vreg dies, return its physical reg to the appropriate free pool.
        for (auto it = mapping.begin(); it != mapping.end();)
        {
            auto liveIt = liveStamp.find(it->first);
            if (liveIt == liveStamp.end() || liveIt->second != stamp)
            {
                freePhysical(it->second);
                it = mapping.erase(it);
            }
            else
            {
                ++it;
            }
        }

        ++idx;
    }
}

SWC_END_NAMESPACE();
