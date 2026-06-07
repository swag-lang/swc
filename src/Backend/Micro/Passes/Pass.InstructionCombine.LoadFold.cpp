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

    // Fuse an indexed 32-bit load feeding a sign-extend-to-64 into a single
    // indexed movsxd (LoadSignedExtAmcRegMem):
    //
    //     LoadAmcRegMem       vt,  [base + idx*scale + disp]   (load b32)
    //     LoadSignedExtRegReg dst, vt, b64<-b32
    //   ->
    //     LoadSignedExtAmcRegMem dst, [base + idx*scale + disp], b64<-b32
    //
    // Matches a widening reduction `acc(s64) += narrowArray[i]`. Uses the
    // transitive-instruction use count (not raw uses.size()) so a dead loop-header
    // phi on the element temp does not hide its single-consumer shape — local to
    // this fold, so it does not perturb the global single-use heuristics that
    // mem2reg promotion depends on.
    bool tryFoldAmcLoadIntoSignExtend(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst)
    {
        if (ctx.isClaimed(loadRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* loadOps = loadInst.ops(*ctx.operands);
        if (!loadOps)
            return false;

        // LoadAmcRegMem: [dst, base, index, loadBits, addrBits, mulValue, addValue].
        const MicroReg    vt       = loadOps[0].reg;
        const MicroReg    base     = loadOps[1].reg;
        const MicroReg    index    = loadOps[2].reg;
        const MicroOpBits loadBits = loadOps[3].opBits;
        const MicroOpBits addrBits = loadOps[4].opBits;

        // The encoder's indexed movsxd only handles a 32-bit dword load into a
        // 64-bit register with 64-bit addressing.
        if (loadBits != MicroOpBits::B32 || addrBits != MicroOpBits::B64)
            return false;
        if (!vt.isVirtualInt() || base == vt || index == vt)
            return false;

        uint32_t loadValueId = 0;
        if (!ctx.ssa->defValue(vt, loadRef, loadValueId) || ctx.ssa->transitiveInstructionUseCount(loadValueId, 2) != 1)
            return false;

        MicroStorage::Iterator walker;
        if (!findAnchorPosition(walker, *ctx.storage, loadRef))
            return false;
        ++walker;

        const auto endIt = ctx.storage->view().end();
        for (uint32_t step = 0; step < K_MAX_LOADFOLD_WINDOW && walker != endIt; ++step, ++walker)
        {
            const MicroInstr& w = *walker;

            // Delaying the load to the extend's position must not cross an
            // aliasing store, a call, control flow, or a redefinition of an
            // addressing register.
            if (isControlOrCall(w) || writesMemory(w))
                return false;

            const auto* useDef   = ctx.ssa->instrUseDef(walker.current);
            const bool  defsAddr = useDef && (microRegSpanContains(useDef->defs, base) || microRegSpanContains(useDef->defs, index));
            const bool  usesVt   = useDef && microRegSpanContains(useDef->uses, vt);
            const bool  defsVt   = useDef && microRegSpanContains(useDef->defs, vt);

            if (defsAddr)
                return false;
            if (!usesVt && !defsVt)
                continue;

            // First reference to vt must be the sign-extend.
            if (w.op != MicroInstrOpcode::LoadSignedExtRegReg)
                return false;

            const MicroInstrOperand* wOps = w.ops(*ctx.operands);
            if (!wOps)
                return false;
            const MicroReg    dstReg  = wOps[0].reg;
            const MicroReg    srcReg  = wOps[1].reg;
            const MicroOpBits dstBits = wOps[2].opBits;
            const MicroOpBits srcBits = wOps[3].opBits;
            if (srcReg != vt || dstReg == vt || dstBits != MicroOpBits::B64 || srcBits != MicroOpBits::B32)
                return false;

            const MicroInstrRef extRef = walker.current;
            if (!ctx.claimAll({loadRef, extRef}))
                return false;

            // LoadSignedExtAmcRegMem: [dst, base, index, dstBits, srcBits, mul, add].
            MicroInstrOperand newOps[7];
            newOps[0].reg      = dstReg;
            newOps[1].reg      = base;
            newOps[2].reg      = index;
            newOps[3].opBits   = dstBits;
            newOps[4].opBits   = srcBits;
            newOps[5].valueU64 = loadOps[5].valueU64;
            newOps[6].valueU64 = loadOps[6].valueU64;
            ctx.emitRewrite(extRef, MicroInstrOpcode::LoadSignedExtAmcRegMem, newOps, /*allocNewBlock=*/true);
            ctx.emitErase(loadRef);
            return true;
        }

        return false;
    }
}

SWC_END_NAMESPACE();
