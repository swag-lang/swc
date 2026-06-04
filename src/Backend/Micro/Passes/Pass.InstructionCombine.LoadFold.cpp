#include "pch.h"
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"

// Load into source-operand folding (register destination).
//
//     LoadRegMem     vt,  [b+o]
//     OpBinaryRegReg dst, vt        (dst = dst <op> vt)
//   ->
//     OpBinaryRegMem dst, [b+o]     (dst = dst <op> [b+o])
//
// This is the counterpart to tryMemoryFoldTriple: the triple folds a
// load/modify/store back to the *same* memory cell (memory destination),
// whereas this rule folds a load consumed as the *source* of an op whose
// destination stays in a register. It matches `acc <op>= data[i]` once
// mem2reg has promoted the accumulators to virtual registers, removing the
// copy chain that used to sit between the load and its consumer.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        constexpr uint32_t K_MAX_LOADFOLD_WINDOW = 16;

        // Ops the encoder can express as `reg <op>= [mem]` (encodeOpBinaryRegMem).
        // Note: shifts are NOT foldable here (no `shl reg, [mem]` form), but
        // MultiplySigned IS (`imul reg, [mem]`), unlike the memory-destination
        // set covered by isMemFoldableOp.
        bool isRegMemFoldableOp(MicroOp op)
        {
            switch (op)
            {
                case MicroOp::Add:
                case MicroOp::Subtract:
                case MicroOp::And:
                case MicroOp::Or:
                case MicroOp::Xor:
                case MicroOp::MultiplySigned:
                    return true;
                default:
                    return false;
            }
        }

        bool findAnchorPosition(MicroStorage::Iterator& outIter, MicroStorage& storage, MicroInstrRef anchor)
        {
            const auto view  = storage.view();
            const auto endIt = view.end();
            for (auto it = view.begin(); it != endIt; ++it)
            {
                if (it.current == anchor)
                {
                    outIter = it;
                    return true;
                }
            }
            return false;
        }
    }

    bool tryFoldLoadIntoRegOp(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        if (ctx.isClaimed(loadRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* loadOps = loadInst.ops(*ctx.operands);
        if (!loadOps)
            return false;

        const MicroReg    vt       = loadOps[0].reg;
        const MicroReg    base     = loadOps[1].reg;
        const MicroOpBits loadBits = loadOps[2].opBits;
        const uint64_t    loadOff  = loadOps[3].valueU64;

        // The loaded value is consumed by an integer ALU op, so it must live
        // in an integer vreg. base==vt would mean the load clobbers its own
        // address register, which folding would then misuse.
        if (!vt.isVirtualInt() || base == vt)
            return false;

        // The load value must flow into exactly one consumer for the move to
        // be sound; otherwise the other uses would lose their definition.
        if (!valueHasSingleUse(*ctx.ssa, vt, loadRef))
            return false;

        MicroStorage::Iterator walker;
        if (!findAnchorPosition(walker, *ctx.storage, loadRef))
            return false;
        ++walker;

        const auto endIt = ctx.storage->view().end();

        for (uint32_t step = 0; step < K_MAX_LOADFOLD_WINDOW && walker != endIt; ++step, ++walker)
        {
            const MicroInstr& w = *walker;

            // The load read is being delayed to the consumer's position, so an
            // aliasing memory write, a call, or any control flow in between
            // could change the value it observes.
            if (isControlOrCall(w) || writesMemory(w))
                return false;

            const auto* useDef   = ctx.ssa->instrUseDef(walker.current);
            const bool  defsBase = useDef && microRegSpanContains(useDef->defs, base);
            const bool  defsVt   = useDef && microRegSpanContains(useDef->defs, vt);
            const bool  usesVt   = useDef && microRegSpanContains(useDef->uses, vt);

            // Rewriting [base+off] in place requires base to be unchanged.
            if (defsBase)
                return false;

            if (!usesVt && !defsVt)
                continue;

            // First (and, by single-use, only) reference to vt. It must be an
            // OpBinaryRegReg with vt as the right-hand source and a distinct
            // register destination; anything else is not foldable.
            if (w.op != MicroInstrOpcode::OpBinaryRegReg)
                return false;

            const MicroInstrOperand* wOps = w.ops(*ctx.operands);
            if (!wOps)
                return false;

            const MicroReg    dstReg  = wOps[0].reg;
            const MicroReg    rhsReg  = wOps[1].reg;
            const MicroOpBits opBits  = wOps[2].opBits;
            const MicroOp     microOp = wOps[3].microOp;

            if (rhsReg != vt || dstReg == vt)
                return false;
            if (opBits != loadBits || !isRegMemFoldableOp(microOp))
                return false;

            const MicroInstrRef opRef = walker.current;
            if (!ctx.claimAll({loadRef, opRef}))
                return false;

            // OpBinaryRegMem: [regDst, memReg, opBits, microOp, memOffset].
            MicroInstrOperand newOps[5];
            newOps[0].reg      = dstReg;
            newOps[1].reg      = base;
            newOps[2].opBits   = opBits;
            newOps[3].microOp  = microOp;
            newOps[4].valueU64 = loadOff;
            ctx.emitRewrite(opRef, MicroInstrOpcode::OpBinaryRegMem, newOps, /*allocNewBlock=*/true);
            ctx.emitErase(loadRef);
            return true;
        }

        return false;
    }
}

SWC_END_NAMESPACE();
