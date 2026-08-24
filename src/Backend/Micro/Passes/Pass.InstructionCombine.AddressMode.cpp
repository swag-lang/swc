#include "pch.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"
#include "Support/Report/Assert.h"

// Fold a constant-offset computation into a memory operand's offset:
//
//     base' = OpBinaryRegImm(base', ADD/SUB, imm)       (single-use)
//     [optionally] base' = LoadRegReg origBase           (single-use, src stable)
//     [base'] = src  or  dst = [base']
//   ->
//     [origBase + imm] = src  (or the symmetric load form)

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        struct MemLayout
        {
            uint8_t baseIdx = 0;
            uint8_t offIdx  = 0;
        };

        bool memoryLayoutFor(MemLayout& out, MicroInstrOpcode op)
        {
            switch (op)
            {
                case MicroInstrOpcode::LoadMemReg:
                    out.baseIdx = 0;
                    out.offIdx  = 3;
                    return true;
                case MicroInstrOpcode::LoadRegMem:
                // The 128-bit vector pair carries the same base/offset operands as the
                // scalar one, and SIMD code is where the front end materializes an address
                // per access most often.
                case MicroInstrOpcode::LoadVecRegMem:
                    out.baseIdx = 1;
                    out.offIdx  = 3;
                    return true;
                case MicroInstrOpcode::StoreVecMemReg:
                    out.baseIdx = 0;
                    out.offIdx  = 3;
                    return true;
                default:
                    return false;
            }
        }

        struct AddChain
        {
            MicroInstrRef     addRef;
            const MicroInstr* addInst = nullptr;
            MicroOp           addOp   = MicroOp::Add;
            uint64_t          addImm  = 0;
        };

        struct AddSearchContext
        {
            const MicroSsaState* ssa      = nullptr;
            MicroOperandStorage* operands = nullptr;
            MicroReg             baseReg  = MicroReg::invalid();
            MicroInstrRef        memRef   = MicroInstrRef::invalid();
        };

        bool findAdjacentAdd(AddChain& out, const AddSearchContext& ctx)
        {
            SWC_ASSERT(ctx.ssa != nullptr);
            SWC_ASSERT(ctx.operands != nullptr);

            const auto reaching = ctx.ssa->reachingDef(ctx.baseReg, ctx.memRef);
            if (!reaching.valid() || reaching.isPhi || !reaching.inst)
                return false;
            if (reaching.inst->op != MicroInstrOpcode::OpBinaryRegImm)
                return false;

            const MicroInstrOperand* addOps = reaching.inst->ops(*ctx.operands);
            if (!addOps || addOps[0].reg != ctx.baseReg)
                return false;
            if (addOps[1].opBits != MicroOpBits::B64)
                return false;

            const MicroOp addOp = addOps[2].microOp;
            if (addOp != MicroOp::Add && addOp != MicroOp::Subtract)
                return false;

            const auto* addValue = ctx.ssa->valueInfo(reaching.valueId);
            if (!addValue || addValue->uses.size() != 1)
                return false;

            out.addRef  = reaching.instRef;
            out.addInst = reaching.inst;
            out.addOp   = addOp;
            out.addImm  = addOps[3].valueU64;
            return true;
        }

        struct CopySearchContext
        {
            const MicroSsaState* ssa      = nullptr;
            MicroOperandStorage* operands = nullptr;
            MicroReg             baseReg  = MicroReg::invalid();
            MicroInstrRef        addRef   = MicroInstrRef::invalid();
            MicroInstrRef        memRef   = MicroInstrRef::invalid();
        };

        // If baseReg was just copied from another register via a single-use
        // LoadRegReg AND that source register still holds the same SSA value
        // at the memory op, return the copy's source so we can skip the copy
        // entirely. Otherwise originalReg stays as baseReg (we only erase
        // the add).
        void findEliminableCopy(MicroInstrRef& outCopyRef, MicroReg& outOriginalReg, const CopySearchContext& ctx)
        {
            SWC_ASSERT(ctx.ssa != nullptr);
            SWC_ASSERT(ctx.operands != nullptr);

            outCopyRef     = MicroInstrRef::invalid();
            outOriginalReg = ctx.baseReg;

            const auto copyReaching = ctx.ssa->reachingDef(ctx.baseReg, ctx.addRef);
            if (!copyReaching.valid() || copyReaching.isPhi || !copyReaching.inst)
                return;
            if (copyReaching.inst->op != MicroInstrOpcode::LoadRegReg)
                return;

            const MicroInstrOperand* copyOps = copyReaching.inst->ops(*ctx.operands);
            if (!copyOps || copyOps[0].reg != ctx.baseReg)
                return;

            const auto* copyValue = ctx.ssa->valueInfo(copyReaching.valueId);
            if (!copyValue || copyValue->uses.size() != 1)
                return;

            const MicroReg candidate = copyOps[1].reg;

            // Soundness: the copy's source must still hold the same SSA value
            // at the memory op, otherwise substituting it would read a newer
            // value and change semantics.
            const auto srcAtCopy = ctx.ssa->reachingDef(candidate, copyReaching.instRef);
            const auto srcAtMem  = ctx.ssa->reachingDef(candidate, ctx.memRef);
            if (!srcAtCopy.valid() || !srcAtMem.valid() || srcAtCopy.valueId != srcAtMem.valueId)
                return;

            outCopyRef     = copyReaching.instRef;
            outOriginalReg = candidate;
        }
    }

    bool tryFoldMemoryAddressing(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (!ctx.ssa || ctx.isClaimed(ref))
            return false;

        MemLayout layout;
        if (!memoryLayoutFor(layout, inst.op))
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops)
            return false;

        const MicroReg baseReg = ops[layout.baseIdx].reg;
        const uint64_t baseOff = ops[layout.offIdx].valueU64;
        if (!baseReg.isVirtual())
            return false;

        AddChain         chain;
        AddSearchContext addSearch;
        addSearch.ssa      = ctx.ssa;
        addSearch.operands = ctx.operands;
        addSearch.baseReg  = baseReg;
        addSearch.memRef   = ref;
        if (!findAdjacentAdd(chain, addSearch))
            return false;

        MicroInstrRef     copyRef;
        MicroReg          originalReg;
        CopySearchContext copySearch;
        copySearch.ssa      = ctx.ssa;
        copySearch.operands = ctx.operands;
        copySearch.baseReg  = baseReg;
        copySearch.addRef   = chain.addRef;
        copySearch.memRef   = ref;
        findEliminableCopy(copyRef, originalReg, copySearch);

        // 64-bit wrapping arithmetic matches native address behavior.
        const uint64_t newOff = (chain.addOp == MicroOp::Add) ? baseOff + chain.addImm : baseOff - chain.addImm;

        if (!ctx.claimAll({ref, chain.addRef}))
            return false;
        if (copyRef.isValid() && !ctx.claimAll({copyRef}))
            return false;

        MicroInstrOperand newMemOps[4];
        for (uint8_t i = 0; i < 4; ++i)
            newMemOps[i] = ops[i];
        newMemOps[layout.baseIdx].reg     = originalReg;
        newMemOps[layout.offIdx].valueU64 = newOff;
        ctx.emitRewrite(ref, inst.op, newMemOps);

        ctx.emitErase(chain.addRef);
        if (copyRef.isValid())
            ctx.emitErase(copyRef);
        return true;
    }

    namespace
    {
        // The addressing-piece layout shared by the AMC opcode family.
        struct AmcLayout
        {
            uint8_t baseIdx  = 1;
            uint8_t indexIdx = 2;
            uint8_t mulIdx   = 5;
            uint8_t addIdx   = 6;
        };

        bool amcLayoutFor(AmcLayout& out, MicroInstrOpcode op)
        {
            switch (op)
            {
                case MicroInstrOpcode::LoadAmcRegMem:
                case MicroInstrOpcode::LoadSignedExtAmcRegMem:
                case MicroInstrOpcode::LoadZeroExtAmcRegMem:
                case MicroInstrOpcode::LoadAddrAmcRegMem:
                    return true;
                case MicroInstrOpcode::LoadAmcMemReg:
                case MicroInstrOpcode::LoadAmcMemImm:
                    out.baseIdx  = 0;
                    out.indexIdx = 1;
                    return true;
                case MicroInstrOpcode::CmpAmcImm:
                    out.baseIdx  = 0;
                    out.indexIdx = 1;
                    out.mulIdx   = 4;
                    out.addIdx   = 5;
                    return true;
                default:
                    return false;
            }
        }

        // True when `reg` holds the same SSA value at both instructions.
        bool sameValueAt(const Context& ctx, MicroReg reg, MicroInstrRef atA, MicroInstrRef atB)
        {
            const auto a = ctx.ssa->reachingDef(reg, atA);
            const auto b = ctx.ssa->reachingDef(reg, atB);
            return a.valid() && b.valid() && a.valueId == b.valueId;
        }
    }

    // Fold `lea idx2, [idx + C]` into the displacement of an indexed access:
    //
    //     LoadAddrRegMem idx2, [idx + C]
    //     ... [base + idx2*scale + d] ...
    //   ->
    //     ... [base + idx*scale + (d + C*scale)] ...
    //
    // The row[i+1] shape of every stencil loop. The lea is left in place when
    // other consumers remain; DCE sweeps it once the last one is folded.
    bool tryFoldLeaConstIntoAmcIndex(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (!ctx.ssa || ctx.isClaimed(ref))
            return false;

        AmcLayout layout;
        if (!amcLayoutFor(layout, inst.op))
            return false;
        if (inst.numOperands > Action::K_MAX_OPS)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops)
            return false;

        const MicroReg index = ops[layout.indexIdx].reg;
        if (!index.isVirtualInt())
            return false;

        const auto reaching = ctx.ssa->reachingDef(index, ref);
        if (!reaching.valid() || reaching.isPhi || !reaching.inst)
            return false;
        if (reaching.inst->op != MicroInstrOpcode::LoadAddrRegMem)
            return false;

        // LoadAddrRegMem: [dst, base, opBits, off].
        const MicroInstrOperand* leaOps = reaching.inst->ops(*ctx.operands);
        if (!leaOps || leaOps[0].reg != index || leaOps[2].opBits != MicroOpBits::B64)
            return false;
        const MicroReg leaBase = leaOps[1].reg;
        if (!leaBase.isVirtualInt())
            return false;
        if (!sameValueAt(ctx, leaBase, reaching.instRef, ref))
            return false;

        const uint64_t mulValue = ops[layout.mulIdx].valueU64;
        const int64_t  newAdd   = static_cast<int64_t>(ops[layout.addIdx].valueU64) + static_cast<int64_t>(leaOps[3].valueU64 * mulValue);
        if (newAdd != static_cast<int64_t>(static_cast<int32_t>(newAdd)))
            return false;

        if (!ctx.claimAll({ref}))
            return false;

        SmallVector<MicroInstrOperand, 8> newOps;
        for (uint32_t i = 0; i < inst.numOperands; ++i)
            newOps.push_back(ops[i]);
        newOps[layout.indexIdx].reg    = leaBase;
        newOps[layout.addIdx].valueU64 = static_cast<uint64_t>(newAdd);
        ctx.emitRewrite(ref, inst.op, {newOps.data(), newOps.size()});
        return true;
    }

    // Fold `lea addr, [base + C]` into the displacement of a plain access:
    //
    //     LoadAddrRegMem addr, [base + C]
    //     ... [addr + d] ...
    //   ->
    //     ... [base + (d + C)] ...
    //
    // The same rewrite the indexed forms get above, for the two operand shapes
    // that carry no index. It matters most where a struct field is read early
    // and written late: the read already comes out as `[base + C]` directly, so
    // the address register survives only to serve the store, and then stays live
    // across everything in between. A function pays for that twice — the value
    // holds a register its own locals wanted, and when it loses that contest it
    // is spilled and reloaded around each store.
    //
    // The lea is left in place when other consumers remain; DCE sweeps it once
    // the last one is folded.
    bool tryFoldLeaConstIntoMemBase(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (!ctx.ssa || ctx.isClaimed(ref))
            return false;

        MemLayout layout;
        if (!memoryLayoutFor(layout, inst.op))
            return false;
        if (inst.numOperands > Action::K_MAX_OPS)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops)
            return false;

        const MicroReg base = ops[layout.baseIdx].reg;
        if (!base.isVirtualInt())
            return false;

        const auto reaching = ctx.ssa->reachingDef(base, ref);
        if (!reaching.valid() || reaching.isPhi || !reaching.inst)
            return false;
        if (reaching.inst->op != MicroInstrOpcode::LoadAddrRegMem)
            return false;

        // LoadAddrRegMem: [dst, base, opBits, off].
        const MicroInstrOperand* leaOps = reaching.inst->ops(*ctx.operands);
        if (!leaOps || leaOps[0].reg != base || leaOps[2].opBits != MicroOpBits::B64)
            return false;

        const MicroReg leaBase = leaOps[1].reg;
        if (!leaBase.isVirtualInt())
            return false;
        if (!sameValueAt(ctx, leaBase, reaching.instRef, ref))
            return false;

        const int64_t newOff = static_cast<int64_t>(ops[layout.offIdx].valueU64) + static_cast<int64_t>(leaOps[3].valueU64);
        if (newOff != static_cast<int64_t>(static_cast<int32_t>(newOff)))
            return false;

        if (!ctx.claimAll({ref}))
            return false;

        SmallVector<MicroInstrOperand, 8> newOps;
        for (uint32_t i = 0; i < inst.numOperands; ++i)
            newOps.push_back(ops[i]);
        newOps[layout.baseIdx].reg     = leaBase;
        newOps[layout.offIdx].valueU64 = static_cast<uint64_t>(newOff);
        ctx.emitRewrite(ref, inst.op, {newOps.data(), newOps.size()});
        return true;
    }

}

SWC_END_NAMESPACE();
