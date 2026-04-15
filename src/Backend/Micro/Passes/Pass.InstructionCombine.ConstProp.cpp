#include "pch.h"
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"

// Forward a LoadRegImm into its consumer so the materializing register
// disappears. We rewrite only the consumer; when every use of the
// LoadRegImm has been forwarded its result becomes dead and the
// companion DeadCodeElimination pass removes the LoadRegImm itself on
// the next iteration of the pre-RA optimization loop.
//
//   LoadRegImm    vt, bitsImm, imm
//   LoadMemReg    [base], vt, storeBits, off    -> LoadMemImm      [base], storeBits, off, imm
//   CmpRegReg     a, vt, bits                   -> CmpRegImm       a, bits, imm
//   OpBinaryRegReg dst, vt, bits, microOp       -> OpBinaryRegImm  dst, bits, microOp, imm
//   LoadRegReg    dst, vt, bits                 -> LoadRegImm      dst, bits, imm

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        constexpr int K_MAX_PHI_DEPTH = 4;

        bool resolveConstValue(uint64_t& outImm, const Context& ctx, uint32_t valueId, int depth)
        {
            if (depth <= 0)
                return false;

            const auto* info = ctx.ssa->valueInfo(valueId);
            if (!info)
                return false;

            if (info->isPhi())
            {
                const auto* phi = ctx.ssa->phiInfoForValue(valueId);
                if (!phi || phi->incomingValueIds.empty())
                    return false;

                uint64_t candidate    = 0;
                bool     hasCandidate = false;
                for (const uint32_t incomingId : phi->incomingValueIds)
                {
                    uint64_t incomingImm = 0;
                    if (!resolveConstValue(incomingImm, ctx, incomingId, depth - 1))
                        return false;
                    if (!hasCandidate)
                    {
                        candidate    = incomingImm;
                        hasCandidate = true;
                    }
                    else if (incomingImm != candidate)
                        return false;
                }

                if (!hasCandidate)
                    return false;
                outImm = candidate;
                return true;
            }

            if (!info->instRef.isValid())
                return false;

            const MicroInstr* inst = ctx.storage->ptr(info->instRef);
            if (!inst || inst->op != MicroInstrOpcode::LoadRegImm)
                return false;

            const MicroInstrOperand* immOps = inst->ops(*ctx.operands);
            if (!immOps || immOps[2].hasWideImmediateValue())
                return false;

            outImm = immOps[2].valueU64;
            return true;
        }

        bool findImmDef(uint64_t& outImm, const Context& ctx, MicroReg useReg, MicroInstrRef useRef)
        {
            if (!useReg.isVirtualInt())
                return false;

            const auto rd = ctx.ssa->reachingDef(useReg, useRef);
            if (!rd.valid())
                return false;

            return resolveConstValue(outImm, ctx, rd.valueId, K_MAX_PHI_DEPTH);
        }
    }

    bool tryFoldConstStore(Context& ctx, MicroInstrRef storeRef, const MicroInstr& storeInst)
    {
        if (ctx.isClaimed(storeRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* storeOps = storeInst.ops(*ctx.operands);
        if (!storeOps)
            return false;

        const MicroReg    base      = storeOps[0].reg;
        const MicroReg    srcReg    = storeOps[1].reg;
        const MicroOpBits storeBits = storeOps[2].opBits;
        const uint64_t    storeOff  = storeOps[3].valueU64;

        uint64_t rawImm = 0;
        if (!findImmDef(rawImm, ctx, srcReg, storeRef))
            return false;

        if (!ctx.claimAll({storeRef}))
            return false;

        const uint64_t imm = rawImm & getBitsMask(storeBits);

        MicroInstrOperand newOps[4];
        newOps[0].reg      = base;
        newOps[1].opBits   = storeBits;
        newOps[2].valueU64 = storeOff;
        newOps[3].setImmediateValue(ApInt(imm, getNumBits(storeBits)));

        ctx.emitRewrite(storeRef, MicroInstrOpcode::LoadMemImm, newOps);
        return true;
    }

    namespace
    {
        // Condition code for the operand-swapped compare (cmp a,b -> cmp b,a).
        // Returns false for conditions whose meaning depends on signed/unsigned
        // directional flags that don't have a clean swap (Sign, Parity,
        // Overflow and friends): we refuse the swap rather than risk miscompile.
        bool swapCmpCond(MicroCond in, MicroCond& out)
        {
            switch (in)
            {
                case MicroCond::Equal: out = MicroCond::Equal; return true;
                case MicroCond::NotEqual: out = MicroCond::NotEqual; return true;
                case MicroCond::Zero: out = MicroCond::Zero; return true;
                case MicroCond::NotZero: out = MicroCond::NotZero; return true;
                case MicroCond::Above: out = MicroCond::Below; return true;
                case MicroCond::AboveOrEqual: out = MicroCond::BelowOrEqual; return true;
                case MicroCond::Below: out = MicroCond::Above; return true;
                case MicroCond::BelowOrEqual: out = MicroCond::AboveOrEqual; return true;
                case MicroCond::Greater: out = MicroCond::Less; return true;
                case MicroCond::GreaterOrEqual: out = MicroCond::LessOrEqual; return true;
                case MicroCond::Less: out = MicroCond::Greater; return true;
                case MicroCond::LessOrEqual: out = MicroCond::GreaterOrEqual; return true;
                default:
                    return false;
            }
        }

        // Operand index of the MicroCond for each UsesCpuFlags opcode we
        // handle. Anything else causes us to bail out of the swap.
        bool flagConsumerCondIndex(MicroInstrOpcode op, uint8_t& outIdx)
        {
            switch (op)
            {
                case MicroInstrOpcode::JumpCond:
                case MicroInstrOpcode::JumpCondImm:
                    outIdx = 0;
                    return true;
                case MicroInstrOpcode::SetCondReg:
                    outIdx = 1;
                    return true;
                case MicroInstrOpcode::LoadCondRegReg:
                    outIdx = 2;
                    return true;
                default:
                    return false;
            }
        }

        struct FlagConsumer
        {
            MicroInstrRef ref;
            MicroCond     swappedCond;
            uint8_t       condIdx;
        };

        bool collectFlagConsumersForSwap(SmallVector<FlagConsumer, 4>& out, const Context& ctx, MicroInstrRef cmpRef)
        {
            auto       walker = ctx.storage->view().begin();
            const auto endIt  = ctx.storage->view().end();
            while (walker != endIt && walker.current != cmpRef)
                ++walker;
            if (walker == endIt)
                return false;
            ++walker;

            for (uint32_t step = 0; step < 16 && walker != endIt; ++step, ++walker)
            {
                const MicroInstr&    inst = *walker;
                const MicroInstrDef& info = MicroInstr::info(inst.op);

                const bool usesFlags = info.flags.has(MicroInstrFlagsE::UsesCpuFlags);
                if (usesFlags)
                {
                    uint8_t condIdx = 0;
                    if (!flagConsumerCondIndex(inst.op, condIdx))
                        return false;

                    const MicroInstrOperand* ops = inst.ops(*ctx.operands);
                    if (!ops)
                        return false;

                    const MicroCond srcCond = ops[condIdx].cpuCond;
                    if (srcCond == MicroCond::Unconditional)
                        continue;

                    MicroCond dstCond;
                    if (!swapCmpCond(srcCond, dstCond))
                        return false;

                    if (ctx.isClaimed(walker.current))
                        return false;

                    FlagConsumer consumer;
                    consumer.ref         = walker.current;
                    consumer.swappedCond = dstCond;
                    consumer.condIdx     = condIdx;
                    out.push_back(consumer);
                }

                // Once the flags are clobbered we can stop scanning: later
                // instructions don't observe our cmp's flags.
                if (info.flags.has(MicroInstrFlagsE::DefinesCpuFlags))
                    return true;

                // Control flow other than a conditional jump we already
                // recorded above invalidates the flag-liveness window.
                if (info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                    inst.op == MicroInstrOpcode::Label)
                    return true;
            }

            // Ran out of instructions before finding a flag clobber: that's
            // fine, every consumer we saw was captured.
            return true;
        }
    }

    bool tryFoldConstCompare(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst)
    {
        if (ctx.isClaimed(cmpRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* cmpOps = cmpInst.ops(*ctx.operands);
        if (!cmpOps)
            return false;

        const MicroReg    lhs    = cmpOps[0].reg;
        const MicroReg    rhs    = cmpOps[1].reg;
        const MicroOpBits opBits = cmpOps[2].opBits;

        uint64_t rawImm    = 0;
        MicroReg keepReg   = MicroReg::invalid();
        bool     needsSwap = false;

        if (findImmDef(rawImm, ctx, rhs, cmpRef))
        {
            keepReg = lhs;
        }
        else if (findImmDef(rawImm, ctx, lhs, cmpRef))
        {
            keepReg   = rhs;
            needsSwap = true;
        }
        else
        {
            return false;
        }

        SmallVector<FlagConsumer, 4> consumers;
        if (needsSwap && !collectFlagConsumersForSwap(consumers, ctx, cmpRef))
            return false;

        if (ctx.isClaimed(cmpRef))
            return false;
        for (const FlagConsumer& c : consumers)
            if (ctx.isClaimed(c.ref))
                return false;
        ctx.claimed.insert(cmpRef.get());
        for (const FlagConsumer& c : consumers)
            ctx.claimed.insert(c.ref.get());

        const uint64_t imm = rawImm & getBitsMask(opBits);

        MicroInstrOperand newOps[3];
        newOps[0].reg    = keepReg;
        newOps[1].opBits = opBits;
        newOps[2].setImmediateValue(ApInt(imm, getNumBits(opBits)));
        ctx.emitRewrite(cmpRef, MicroInstrOpcode::CmpRegImm, newOps);

        for (const FlagConsumer& consumer : consumers)
        {
            const MicroInstr* consumerInst = ctx.storage->ptr(consumer.ref);
            if (!consumerInst)
                continue;
            const MicroInstrOperand* consumerOps = consumerInst->ops(*ctx.operands);
            if (!consumerOps)
                continue;

            MicroInstrOperand rewritten[Action::K_MAX_OPS] = {};
            const uint8_t     numOps                       = consumerInst->numOperands;
            for (uint8_t i = 0; i < numOps; ++i)
                rewritten[i] = consumerOps[i];
            rewritten[consumer.condIdx].cpuCond = consumer.swappedCond;

            const std::span rewrittenOps(rewritten, numOps);
            ctx.emitRewrite(consumer.ref, consumerInst->op, rewrittenOps);
        }

        return true;
    }

    bool tryFoldConstBinaryRhs(Context& ctx, MicroInstrRef binRef, const MicroInstr& binInst)
    {
        if (ctx.isClaimed(binRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* binOps = binInst.ops(*ctx.operands);
        if (!binOps)
            return false;

        const MicroReg    dst     = binOps[0].reg;
        const MicroReg    rhs     = binOps[1].reg;
        const MicroOpBits opBits  = binOps[2].opBits;
        const MicroOp     microOp = binOps[3].microOp;

        // Only integer ops have a meaningful immediate form.
        if (!dst.isVirtualInt())
            return false;

        uint64_t rawImm = 0;
        if (!findImmDef(rawImm, ctx, rhs, binRef))
            return false;

        if (!ctx.claimAll({binRef}))
            return false;

        const uint64_t imm = rawImm & getBitsMask(opBits);

        MicroInstrOperand newOps[4];
        newOps[0].reg     = dst;
        newOps[1].opBits  = opBits;
        newOps[2].microOp = microOp;
        newOps[3].setImmediateValue(ApInt(imm, getNumBits(opBits)));

        ctx.emitRewrite(binRef, MicroInstrOpcode::OpBinaryRegImm, newOps);
        return true;
    }

    // LoadRegReg dst, src, bits where src = LoadRegImm imm  -> LoadRegImm dst, bits, imm.
    // Breaks constant-carrying copies (e.g. from narrowing reg-reg moves
    // that CopyElimination skips when the source/destination widths differ).
    bool tryFoldConstCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (ctx.isClaimed(copyRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* copyOps = copyInst.ops(*ctx.operands);
        if (!copyOps)
            return false;

        const MicroReg    dst    = copyOps[0].reg;
        const MicroReg    src    = copyOps[1].reg;
        const MicroOpBits opBits = copyOps[2].opBits;

        if (!dst.isVirtualInt())
            return false;

        uint64_t rawImm = 0;
        if (!findImmDef(rawImm, ctx, src, copyRef))
            return false;

        if (!ctx.claimAll({copyRef}))
            return false;

        const uint64_t imm = rawImm & getBitsMask(opBits);

        MicroInstrOperand newOps[3];
        newOps[0].reg    = dst;
        newOps[1].opBits = opBits;
        newOps[2].setImmediateValue(ApInt(imm, getNumBits(opBits)));

        ctx.emitRewrite(copyRef, MicroInstrOpcode::LoadRegImm, newOps);
        return true;
    }
}

SWC_END_NAMESPACE();
