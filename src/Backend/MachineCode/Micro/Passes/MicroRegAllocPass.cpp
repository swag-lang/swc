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

    // Add an operand reference for later rewriting, skipping invalid / non-allocatable regs.
    void addOperand(SmallVector<RegOperandRef, 8>& out, MicroReg* reg, bool use, bool def)
    {
        if (!reg || !reg->isValid() || reg->isNoBase())
            return;
        out.push_back({reg, use, def});
    }

    // Compute the uses/defs for one instruction.
    // This is used in the reverse liveness pre-pass (to build liveOut and call-crossing info).
    RegUseDef collectRegUseDef(const MicroInstr& inst, const Store& store)
    {
        RegUseDef info;
        auto*     ops = inst.ops(store);

        switch (inst.op)
        {
            // No register effects (as modeled here).
            case MicroInstrOpcode::End:
            case MicroInstrOpcode::Enter:
            case MicroInstrOpcode::Leave:
            case MicroInstrOpcode::Ignore:
            case MicroInstrOpcode::Label:
            case MicroInstrOpcode::Debug:
            case MicroInstrOpcode::LoadCallParam:
            case MicroInstrOpcode::LoadCallAddrParam:
            case MicroInstrOpcode::LoadCallZeroExtParam:
            case MicroInstrOpcode::StoreCallParam:
            case MicroInstrOpcode::Nop:
            case MicroInstrOpcode::Ret:
                break;

            // dst := ...
            case MicroInstrOpcode::SymbolRelocAddr:
            case MicroInstrOpcode::SymbolRelocValue:
            case MicroInstrOpcode::LoadRegImm:
            case MicroInstrOpcode::SetCondReg:
            case MicroInstrOpcode::ClearReg:
                addDef(info, ops[0].reg);
                break;

            // uses only
            case MicroInstrOpcode::Push:
            case MicroInstrOpcode::JumpReg:
            case MicroInstrOpcode::CmpRegImm:
                addUse(info, ops[0].reg);
                break;

            // defs only
            case MicroInstrOpcode::Pop:
                addDef(info, ops[0].reg);
                break;

            // Direct calls: mark as call and record call convention.
            // (No explicit operand regs here; call clobbers/args presumably modeled elsewhere.)
            case MicroInstrOpcode::CallLocal:
            case MicroInstrOpcode::CallExtern:
                info.isCall   = true;
                info.callConv = ops[1].callConv;
                break;

            // Indirect call uses target reg and is a call.
            case MicroInstrOpcode::CallIndirect:
                info.isCall   = true;
                info.callConv = ops[1].callConv;
                addUse(info, ops[0].reg);
                break;

            // Jump-table uses base/index regs.
            case MicroInstrOpcode::JumpTable:
                addUse(info, ops[0].reg);
                addUse(info, ops[1].reg);
                break;

            // Conditional jumps: no reg effects (condition likely modeled as prior cmp/setcc).
            case MicroInstrOpcode::JumpCond:
            case MicroInstrOpcode::JumpCondImm:
            case MicroInstrOpcode::PatchJump:
                break;

            // dst := src (reg-reg variants)
            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
            case MicroInstrOpcode::LoadCondRegReg:
                addDef(info, ops[0].reg);
                addUse(info, ops[1].reg);
                break;

            // dst := [mem(base,...)] - base reg is used
            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
            case MicroInstrOpcode::LoadAddrRegMem:
                addDef(info, ops[0].reg);
                addUse(info, ops[1].reg);
                break;

            // Atomic/multi-component mem forms: typically use base + amc reg(s).
            case MicroInstrOpcode::LoadAmcRegMem:
            case MicroInstrOpcode::LoadAddrAmcRegMem:
                addDef(info, ops[0].reg);
                addUse(info, ops[1].reg);
                addUse(info, ops[2].reg);
                break;

            case MicroInstrOpcode::LoadAmcMemReg:
                addUse(info, ops[0].reg);
                addUse(info, ops[1].reg);
                addUse(info, ops[2].reg);
                break;

            case MicroInstrOpcode::LoadAmcMemImm:
                addUse(info, ops[0].reg);
                addUse(info, ops[1].reg);
                break;

            // Store: [mem(base,...)] := src
            case MicroInstrOpcode::LoadMemReg:
                addUse(info, ops[0].reg);
                addUse(info, ops[1].reg);
                break;

            case MicroInstrOpcode::LoadMemImm:
                addUse(info, ops[0].reg);
                break;

            // Comparisons read their operands.
            case MicroInstrOpcode::CmpRegReg:
                addUse(info, ops[0].reg);
                addUse(info, ops[1].reg);
                break;

            case MicroInstrOpcode::CmpMemReg:
                addUse(info, ops[0].reg);
                addUse(info, ops[1].reg);
                break;

            case MicroInstrOpcode::CmpMemImm:
                addUse(info, ops[0].reg);
                break;

            case MicroInstrOpcode::OpUnaryMem:
                addUse(info, ops[0].reg);
                break;

            // Unary op on reg is read-modify-write.
            case MicroInstrOpcode::OpUnaryReg:
                addUseDef(info, ops[0].reg);
                break;

            // Binary reg-reg ops:
            // - Exchange: both operands are read/write
            // - Otherwise: dst is read/write, src is read
            case MicroInstrOpcode::OpBinaryRegReg:
            {
                const auto op = ops[3].microOp;
                if (op == MicroOp::Exchange)
                {
                    addUseDef(info, ops[0].reg);
                    addUseDef(info, ops[1].reg);
                }
                else
                {
                    addUseDef(info, ops[0].reg);
                    addUse(info, ops[1].reg);
                }
                break;
            }

            // dst is read-modify-write; imm is not a reg
            case MicroInstrOpcode::OpBinaryRegImm:
                addUseDef(info, ops[0].reg);
                break;

            // dst is read-modify-write; mem base reg is read
            case MicroInstrOpcode::OpBinaryRegMem:
                addUseDef(info, ops[0].reg);
                addUse(info, ops[1].reg);
                break;

            // mem op: base reg is used; second reg may be used or use/def for exchange
            case MicroInstrOpcode::OpBinaryMemReg:
            {
                const auto op = ops[3].microOp;
                addUse(info, ops[0].reg);
                if (op == MicroOp::Exchange)
                    addUseDef(info, ops[1].reg);
                else
                    addUse(info, ops[1].reg);
                break;
            }

            case MicroInstrOpcode::OpBinaryMemImm:
                addUse(info, ops[0].reg);
                break;

            // Ternary reg-reg-reg:
            // - CompareExchange: first two are read/write, third is read
            // - Otherwise: dst is read/write, two sources are read
            case MicroInstrOpcode::OpTernaryRegRegReg:
            {
                const auto op = ops[4].microOp;
                if (op == MicroOp::CompareExchange)
                {
                    addUseDef(info, ops[0].reg);
                    addUseDef(info, ops[1].reg);
                    addUse(info, ops[2].reg);
                }
                else
                {
                    addUseDef(info, ops[0].reg);
                    addUse(info, ops[1].reg);
                    addUse(info, ops[2].reg);
                }
                break;
            }

            default:
                SWC_ASSERT(false);
                break;
        }

        return info;
    }

    // Collect all register operand references for an instruction so they can be rewritten in-place.
    // This duplicates the opcode classification from collectRegUseDef, but returns pointer refs
    // rather than values.
    void collectRegOperands(const MicroInstr& inst, Store& store, SmallVector<RegOperandRef, 8>& out)
    {
        auto* ops = inst.ops(store);

        switch (inst.op)
        {
            case MicroInstrOpcode::End:
            case MicroInstrOpcode::Enter:
            case MicroInstrOpcode::Leave:
            case MicroInstrOpcode::Ignore:
            case MicroInstrOpcode::Label:
            case MicroInstrOpcode::Debug:
            case MicroInstrOpcode::LoadCallParam:
            case MicroInstrOpcode::LoadCallAddrParam:
            case MicroInstrOpcode::LoadCallZeroExtParam:
            case MicroInstrOpcode::StoreCallParam:
            case MicroInstrOpcode::Nop:
            case MicroInstrOpcode::Ret:
                break;

            case MicroInstrOpcode::SymbolRelocAddr:
            case MicroInstrOpcode::SymbolRelocValue:
            case MicroInstrOpcode::LoadRegImm:
            case MicroInstrOpcode::SetCondReg:
            case MicroInstrOpcode::ClearReg:
                // def(dst)
                addOperand(out, &ops[0].reg, false, true);
                break;

            case MicroInstrOpcode::Push:
            case MicroInstrOpcode::JumpReg:
            case MicroInstrOpcode::CmpRegImm:
                // use(reg)
                addOperand(out, &ops[0].reg, true, false);
                break;

            case MicroInstrOpcode::Pop:
                // def(reg)
                addOperand(out, &ops[0].reg, false, true);
                break;

            case MicroInstrOpcode::CallLocal:
            case MicroInstrOpcode::CallExtern:
                break;

            case MicroInstrOpcode::CallIndirect:
                addOperand(out, &ops[0].reg, true, false);
                break;

            case MicroInstrOpcode::JumpTable:
                addOperand(out, &ops[0].reg, true, false);
                addOperand(out, &ops[1].reg, true, false);
                break;

            case MicroInstrOpcode::JumpCond:
            case MicroInstrOpcode::JumpCondImm:
            case MicroInstrOpcode::PatchJump:
                break;

            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
            case MicroInstrOpcode::LoadCondRegReg:
                addOperand(out, &ops[0].reg, false, true);
                addOperand(out, &ops[1].reg, true, false);
                break;

            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
            case MicroInstrOpcode::LoadAddrRegMem:
                addOperand(out, &ops[0].reg, false, true);
                addOperand(out, &ops[1].reg, true, false);
                break;

            case MicroInstrOpcode::LoadAmcRegMem:
            case MicroInstrOpcode::LoadAddrAmcRegMem:
                addOperand(out, &ops[0].reg, false, true);
                addOperand(out, &ops[1].reg, true, false);
                addOperand(out, &ops[2].reg, true, false);
                break;

            case MicroInstrOpcode::LoadAmcMemReg:
                addOperand(out, &ops[0].reg, true, false);
                addOperand(out, &ops[1].reg, true, false);
                addOperand(out, &ops[2].reg, true, false);
                break;

            case MicroInstrOpcode::LoadAmcMemImm:
                addOperand(out, &ops[0].reg, true, false);
                addOperand(out, &ops[1].reg, true, false);
                break;

            case MicroInstrOpcode::LoadMemReg:
                addOperand(out, &ops[0].reg, true, false);
                addOperand(out, &ops[1].reg, true, false);
                break;

            case MicroInstrOpcode::LoadMemImm:
                addOperand(out, &ops[0].reg, true, false);
                break;

            case MicroInstrOpcode::CmpRegReg:
                addOperand(out, &ops[0].reg, true, false);
                addOperand(out, &ops[1].reg, true, false);
                break;

            case MicroInstrOpcode::CmpMemReg:
                addOperand(out, &ops[0].reg, true, false);
                addOperand(out, &ops[1].reg, true, false);
                break;

            case MicroInstrOpcode::CmpMemImm:
                addOperand(out, &ops[0].reg, true, false);
                break;

            case MicroInstrOpcode::OpUnaryMem:
                addOperand(out, &ops[0].reg, true, false);
                break;

            case MicroInstrOpcode::OpUnaryReg:
                addOperand(out, &ops[0].reg, true, true);
                break;

            case MicroInstrOpcode::OpBinaryRegReg:
            {
                const auto op = ops[3].microOp;
                if (op == MicroOp::Exchange)
                {
                    addOperand(out, &ops[0].reg, true, true);
                    addOperand(out, &ops[1].reg, true, true);
                }
                else
                {
                    addOperand(out, &ops[0].reg, true, true);
                    addOperand(out, &ops[1].reg, true, false);
                }
                break;
            }

            case MicroInstrOpcode::OpBinaryRegImm:
                addOperand(out, &ops[0].reg, true, true);
                break;

            case MicroInstrOpcode::OpBinaryRegMem:
                addOperand(out, &ops[0].reg, true, true);
                addOperand(out, &ops[1].reg, true, false);
                break;

            case MicroInstrOpcode::OpBinaryMemReg:
            {
                const auto op = ops[3].microOp;
                addOperand(out, &ops[0].reg, true, false);
                if (op == MicroOp::Exchange)
                    addOperand(out, &ops[1].reg, true, true);
                else
                    addOperand(out, &ops[1].reg, true, false);
                break;
            }

            case MicroInstrOpcode::OpBinaryMemImm:
                addOperand(out, &ops[0].reg, true, false);
                break;

            case MicroInstrOpcode::OpTernaryRegRegReg:
            {
                const auto op = ops[4].microOp;
                if (op == MicroOp::CompareExchange)
                {
                    addOperand(out, &ops[0].reg, true, true);
                    addOperand(out, &ops[1].reg, true, true);
                    addOperand(out, &ops[2].reg, true, false);
                }
                else
                {
                    addOperand(out, &ops[0].reg, true, true);
                    addOperand(out, &ops[1].reg, true, false);
                    addOperand(out, &ops[2].reg, true, false);
                }
                break;
            }

            default:
                SWC_ASSERT(false);
                break;
        }
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

    // -----------------------------
    // Reverse pass: build liveOut and record which vregs are live across calls.
    // -----------------------------
    uint32_t idx = instructionCount;
    for (auto& inst : context.instructions->viewMutReverse())
    {
        --idx;

        // Snapshot current live set as live-out of this instruction.
        liveOut[idx].assign(live.begin(), live.end());

        const auto info = collectRegUseDef(inst, store);

        // If this instruction is a call, any currently-live vreg is live across a call site.
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

    // Initialize free lists by partitioning available regs into persistent vs transient pools.
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
    // If virtKey is live across any call, allocate from persistent pool (call-preserved).
    // Otherwise prefer transient, falling back to persistent if transient is empty.
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

    // -----------------------------
    // Forward pass: rewrite operands from virtual regs to physical regs using liveOut.
    // -----------------------------
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
        // Allocation happens on first sight; subsequent uses reuse the mapping.
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
