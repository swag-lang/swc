#include "pch.h"
#include "Backend/MachineCode/Micro/Passes/MicroRegAllocPass.h"
#include "Backend/MachineCode/Encoder/Encoder.h"
#include "Backend/MachineCode/Micro/MicroInstr.h"
#include "Support/Core/SmallVector.h"
#include "Support/Core/TypedStore.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    // Collected register uses/defs for an instruction.
    // - uses: registers read by the instruction
    // - defs: registers written by the instruction
    // - isCall/callConv: marks call instructions so the allocator can conservatively
    //   require call-preserved ("persistent") physical registers for vregs live across calls.
    struct RegUseDef
    {
        SmallVector<MicroReg, 6> uses;
        SmallVector<MicroReg, 3> defs;
        bool                     isCall   = false;
        CallConvKind             callConv = CallConvKind::C;
    };

    // Reference to a MicroReg operand field inside the instruction's operand storage.
    // This allows in-place rewriting of virtual regs to physical regs.
    struct RegOperandRef
    {
        MicroReg* reg = nullptr; // pointer into operand storage
        bool      use = false;   // operand is read
        bool      def = false;   // operand is written
    };

    // Add a register to the use list if it's a meaningful register for allocation.
    void addUse(RegUseDef& info, MicroReg reg)
    {
        if (reg.isValid() && !reg.isNoBase())
            info.uses.push_back(reg);
    }

    // Add a register to the def list if it's a meaningful register for allocation.
    void addDef(RegUseDef& info, MicroReg reg)
    {
        if (reg.isValid() && !reg.isNoBase())
            info.defs.push_back(reg);
    }

    // Convenience: treat as both a use and a def (read-modify-write operand).
    void addUseDef(RegUseDef& info, MicroReg reg)
    {
        addUse(info, reg);
        addDef(info, reg);
    }

    std::array<MicroInstrRegMode, 3> resolveRegModes(const MicroInstrOpcodeInfo& info, const MicroInstrOperand* ops)
    {
        auto modes = info.regModes;

        switch (info.special)
        {
            case MicroInstrRegSpecial::None:
                break;
            case MicroInstrRegSpecial::OpBinaryRegReg:
                if (ops[info.microOpIndex].microOp == MicroOp::Exchange)
                {
                    modes[0] = MicroInstrRegMode::UseDef;
                    modes[1] = MicroInstrRegMode::UseDef;
                }
                break;
            case MicroInstrRegSpecial::OpBinaryMemReg:
                if (ops[info.microOpIndex].microOp == MicroOp::Exchange)
                    modes[1] = MicroInstrRegMode::UseDef;
                break;
            case MicroInstrRegSpecial::OpTernaryRegRegReg:
                if (ops[info.microOpIndex].microOp == MicroOp::CompareExchange)
                    modes[1] = MicroInstrRegMode::UseDef;
                break;
        }

        return modes;
    }

    void collectRegUseDefFromModes(RegUseDef& info, const MicroInstrOperand* ops, const std::array<MicroInstrRegMode, 3>& modes)
    {
        if (!ops)
            return;

        for (size_t i = 0; i < modes.size(); ++i)
        {
            switch (modes[i])
            {
                case MicroInstrRegMode::None:
                    break;
                case MicroInstrRegMode::Use:
                    addUse(info, ops[i].reg);
                    break;
                case MicroInstrRegMode::Def:
                    addDef(info, ops[i].reg);
                    break;
                case MicroInstrRegMode::UseDef:
                    addUseDef(info, ops[i].reg);
                    break;
            }
        }
    }

    // Add an operand reference for later rewriting, skipping invalid / non-allocatable regs.
    void addOperand(SmallVector<RegOperandRef, 8>& out, MicroReg* reg, bool use, bool def)
    {
        if (!reg || !reg->isValid() || reg->isNoBase())
            return;
        out.push_back({reg, use, def});
    }

    void collectRegOperandsFromModes(MicroInstrOperand* ops, const std::array<MicroInstrRegMode, 3>& modes, SmallVector<RegOperandRef, 8>& out)
    {
        if (!ops)
            return;

        for (size_t i = 0; i < modes.size(); ++i)
        {
            switch (modes[i])
            {
                case MicroInstrRegMode::None:
                    break;
                case MicroInstrRegMode::Use:
                    addOperand(out, &ops[i].reg, true, false);
                    break;
                case MicroInstrRegMode::Def:
                    addOperand(out, &ops[i].reg, false, true);
                    break;
                case MicroInstrRegMode::UseDef:
                    addOperand(out, &ops[i].reg, true, true);
                    break;
            }
        }
    }

    // Compute the uses/defs for one instruction.
    // This is used in the reverse liveness pre-pass (to build liveOut and call-crossing info).
    RegUseDef collectRegUseDef(const MicroInstr& inst, const Store& store)
    {
        RegUseDef info;

        const auto& opcodeInfo = MicroInstr::info(inst.op);
        const auto* ops        = inst.ops(store);

        if (opcodeInfo.isCall)
        {
            info.isCall   = true;
            info.callConv = ops[opcodeInfo.callConvIndex].callConv;
        }

        const auto modes = resolveRegModes(opcodeInfo, ops);
        collectRegUseDefFromModes(info, ops, modes);
        return info;
    }

    // Collect all register operand references for an instruction so they can be rewritten in-place.
    // This duplicates the opcode classification from collectRegUseDef but returns pointer refs
    // rather than values.
    void collectRegOperands(const MicroInstr& inst, Store& store, SmallVector<RegOperandRef, 8>& out)
    {
        const auto& opcodeInfo = MicroInstr::info(inst.op);
        auto*       ops        = inst.ops(store);
        const auto  modes      = resolveRegModes(opcodeInfo, ops);
        collectRegOperandsFromModes(ops, modes, out);
    }
}

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
    uint32_t idx = instructionCount;
    for (auto& inst : context.instructions->viewMutReverse())
    {
        --idx;

        // Snapshot current live set as live-out of this instruction.
        liveOut[idx].assign(live.begin(), live.end());

        const auto info = collectRegUseDef(inst, store);

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
    for (auto& inst : context.instructions->viewMut())
    {
        // New instruction "epoch".
        ++stamp;

        // Mark all vregs live-out of this instruction with the current stamp.
        for (auto regKey : liveOut[idx])
            liveStamp[regKey] = stamp;

        // Collect all register operands in this instruction for in-place rewriting.
        SmallVector<RegOperandRef, 8> regs;
        collectRegOperands(inst, context.operands->store(), regs);

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
