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

    namespace
    {
        // Walks back from `reg` at `atRef` through one optional single-use 64-bit copy, and
        // reports the instruction that produced the value.
        bool resolveThroughCopy(const Context& ctx, MicroReg reg, MicroInstrRef atRef, MicroInstrRef& outCopyRef, MicroSsaState::ReachingDef& outDef)
        {
            outCopyRef = MicroInstrRef::invalid();
            outDef     = ctx.ssa->reachingDef(reg, atRef);
            if (!outDef.valid() || outDef.isPhi || !outDef.inst)
                return false;
            if (outDef.inst->op != MicroInstrOpcode::LoadRegReg)
                return true;

            const MicroInstrOperand* copyOps = outDef.inst->ops(*ctx.operands);
            if (!copyOps || copyOps[2].opBits != MicroOpBits::B64 || !copyOps[1].reg.isVirtualInt())
                return true;
            if (!valueHasSingleUse(*ctx.ssa, copyOps[0].reg, outDef.instRef))
                return true;

            const MicroInstrRef copyRef = outDef.instRef;
            const auto          through = ctx.ssa->reachingDef(copyOps[1].reg, copyRef);
            if (!through.valid() || through.isPhi || !through.inst)
                return false;

            outCopyRef = copyRef;
            outDef     = through;
            return true;
        }

        struct ScaledIndex
        {
            MicroReg      indexReg;
            uint64_t      scale     = 0;
            MicroInstrRef shiftRef  = MicroInstrRef::invalid();
            MicroInstrRef afterCopy = MicroInstrRef::invalid();
            MicroInstrRef inCopyRef = MicroInstrRef::invalid();
        };

        // Recognizes what a subscript of a two, four or eight byte element lowers to: a copy of
        // the index, a shift of that copy, and a copy of the result into whatever the add works
        // on. Every link has to be single-use, since the fold erases all three.
        bool matchScaledIndex(ScaledIndex& out, const Context& ctx, MicroReg reg, MicroInstrRef atRef)
        {
            MicroSsaState::ReachingDef def;
            if (!resolveThroughCopy(ctx, reg, atRef, out.afterCopy, def))
                return false;
            if (def.inst->op != MicroInstrOpcode::OpBinaryRegImm)
                return false;

            const MicroInstrOperand* shiftOps = def.inst->ops(*ctx.operands);
            if (!shiftOps || shiftOps[1].opBits != MicroOpBits::B64 || shiftOps[2].microOp != MicroOp::ShiftLeft)
                return false;
            if (shiftOps[3].hasWideImmediateValue())
                return false;

            const uint64_t shiftAmount = shiftOps[3].valueU64;
            if (shiftAmount < 1 || shiftAmount > 3)
                return false;
            if (!valueHasSingleUse(*ctx.ssa, shiftOps[0].reg, def.instRef))
                return false;

            // The shift is two-address, so the value it scales arrives through its own copy.
            const auto shifted = ctx.ssa->reachingDef(shiftOps[0].reg, def.instRef);
            if (!shifted.valid() || shifted.isPhi || !shifted.inst || shifted.inst->op != MicroInstrOpcode::LoadRegReg)
                return false;

            const MicroInstrOperand* inOps = shifted.inst->ops(*ctx.operands);
            if (!inOps || inOps[2].opBits != MicroOpBits::B64 || !inOps[1].reg.isVirtualInt())
                return false;
            if (!valueHasSingleUse(*ctx.ssa, inOps[0].reg, shifted.instRef))
                return false;
            if (!sameValueAt(ctx, inOps[1].reg, shifted.instRef, atRef))
                return false;

            out.indexReg  = inOps[1].reg;
            out.scale     = 1ull << shiftAmount;
            out.shiftRef  = def.instRef;
            out.inCopyRef = shifted.instRef;
            return true;
        }
    }

    // Fold a scaling shift and the add that follows it into one address:
    //
    //     idx2 = index; idx2 <<= K; sum = idx2; sum += base
    //   ->
    //     sum = &[base + index * (1 << K)]
    //
    // The shape every subscript of a two, four or eight byte element lowers to. Left alone it
    // is four instructions and three dependent steps in front of the load that wants the
    // address, where the machine has one instruction that does all of it.
    bool tryFoldShiftAddIntoScaledAddress(Context& ctx, const MicroInstrRef ref, const MicroInstr& inst)
    {
        if (!ctx.ssa || ctx.isClaimed(ref))
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || ops[2].opBits != MicroOpBits::B64 || ops[3].microOp != MicroOp::Add)
            return false;

        const MicroReg dst = ops[0].reg;
        const MicroReg src = ops[1].reg;
        if (!dst.isVirtualInt() || !src.isVirtualInt() || dst == src)
            return false;

        // Either operand can be the scaled one; the other is the base.
        for (uint32_t attempt = 0; attempt < 2; ++attempt)
        {
            const MicroReg scaledReg = attempt == 0 ? src : dst;
            const MicroReg baseReg   = attempt == 0 ? dst : src;

            ScaledIndex scaled;
            if (!matchScaledIndex(scaled, ctx, scaledReg, ref))
                continue;
            if (scaled.indexReg == dst || scaled.indexReg == baseReg)
                continue;

            if (!ctx.claimAll({ref, scaled.shiftRef, scaled.inCopyRef}))
                continue;
            if (scaled.afterCopy.isValid() && !ctx.claimAll({scaled.afterCopy}))
                continue;

            MicroInstrOperand newOps[8] = {};
            newOps[0].reg               = dst;
            newOps[1].reg               = baseReg;
            newOps[2].reg               = scaled.indexReg;
            newOps[3].opBits            = MicroOpBits::B64;
            newOps[4].opBits            = MicroOpBits::B64;
            newOps[5].valueU64          = scaled.scale;
            newOps[6].valueU64          = 0;
            ctx.emitRewrite(ref, MicroInstrOpcode::LoadAddrAmcRegMem, std::span{newOps, 8}, true);
            ctx.emitErase(scaled.shiftRef);
            ctx.emitErase(scaled.inCopyRef);
            if (scaled.afterCopy.isValid())
                ctx.emitErase(scaled.afterCopy);
            return true;
        }

        return false;
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
