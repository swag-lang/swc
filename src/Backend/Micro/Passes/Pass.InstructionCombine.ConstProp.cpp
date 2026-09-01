#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"
#include "Compiler/Sema/Constant/ConstantManager.h"

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
            if (!inst)
                return false;

            // A cleared register is the constant zero. Constant folding used to
            // stop at it, which left every `x op 0` and every float zero behind
            // the peepholes that handle the spelled-out immediate.
            if (inst->op == MicroInstrOpcode::ClearReg)
            {
                outImm = 0;
                return true;
            }

            if (inst->op != MicroInstrOpcode::LoadRegImm)
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
                    if (!MicroPassHelpers::conditionOperandIndex(inst.op, condIdx))
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
                if (MicroPassHelpers::instructionActuallyDefinesCpuFlags(inst, inst.ops(*ctx.operands)))
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

        if (!dst.isVirtual())
            return false;

        uint64_t rawImm = 0;
        if (!findImmDef(rawImm, ctx, src, copyRef))
            return false;

        const uint64_t imm = rawImm & getBitsMask(opBits);

        // Moving a zero into a float register is a two-instruction detour
        // through a general-purpose one — the constant has to be staged there
        // first. Clearing the float register directly is one instruction and
        // costs no integer register, which is what the comparison against a
        // literal zero every float `if` lowers to needs.
        if (dst.isVirtualFloat())
        {
            if (imm != 0 || !ctx.claimAll({copyRef}))
                return false;

            MicroInstrOperand clearOps[2];
            clearOps[0].reg    = dst;
            clearOps[1].opBits = opBits;
            ctx.emitRewrite(copyRef, MicroInstrOpcode::ClearReg, clearOps);
            return true;
        }

        if (!ctx.claimAll({copyRef}))
            return false;

        MicroInstrOperand newOps[3];
        newOps[0].reg    = dst;
        newOps[1].opBits = opBits;
        newOps[2].setImmediateValue(ApInt(imm, getNumBits(opBits)));

        ctx.emitRewrite(copyRef, MicroInstrOpcode::LoadRegImm, newOps);
        return true;
    }

    // An indexed address whose index is a compile-time constant is a plain
    // base+displacement address: fold the index into the displacement and
    // rewrite to the base+offset form of the same operation. This is what
    // turns an unrolled `a[i]` into `[base + K*scale]` once the counter has
    // been substituted per copy, and it frees the index register on the spot.
    bool tryFoldConstIndexAmc(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops)
            return false;

        // Per-opcode operand shape: where the addressing pieces live, and
        // what the base+offset rewrite looks like.
        int baseIdx = 1, indexIdx = 2, mulIdx = 5, addIdx = 6;
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadAmcRegMem:
            case MicroInstrOpcode::LoadSignedExtAmcRegMem:
            case MicroInstrOpcode::LoadZeroExtAmcRegMem:
            case MicroInstrOpcode::LoadAddrAmcRegMem:
                break;
            case MicroInstrOpcode::LoadAmcMemReg:
            case MicroInstrOpcode::LoadAmcMemImm:
                baseIdx  = 0;
                indexIdx = 1;
                break;
            case MicroInstrOpcode::CmpAmcImm:
                baseIdx  = 0;
                indexIdx = 1;
                mulIdx   = 4;
                addIdx   = 5;
                break;
            default:
                return false;
        }

        const MicroReg base  = ops[baseIdx].reg;
        const MicroReg index = ops[indexIdx].reg;
        if (!base.isValid() || base.isNoBase() || !index.isVirtualInt())
            return false;

        // Folding the index into the displacement assumes 64-bit address
        // arithmetic; the sign/zero-extending loads have no addressing-width
        // operand because they are 64-bit by construction.
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadAmcRegMem:
            case MicroInstrOpcode::LoadAddrAmcRegMem:
                if (ops[4].opBits != MicroOpBits::B64)
                    return false;
                break;
            case MicroInstrOpcode::LoadAmcMemReg:
            case MicroInstrOpcode::LoadAmcMemImm:
            case MicroInstrOpcode::CmpAmcImm:
                if (ops[3].opBits != MicroOpBits::B64)
                    return false;
                break;
            default:
                break;
        }

        uint64_t indexValue = 0;
        if (!findImmDef(indexValue, ctx, index, ref))
            return false;

        // The folded displacement must stay a signed 32-bit quantity.
        const uint64_t mulValue = ops[mulIdx].valueU64;
        const uint64_t addValue = ops[addIdx].valueU64;
        if (indexValue > 0x0FFFFFFFull)
            return false;
        const int64_t offset = static_cast<int64_t>(addValue) + static_cast<int64_t>(indexValue * mulValue);
        if (offset != static_cast<int64_t>(static_cast<int32_t>(offset)))
            return false;

        if (!ctx.claimAll({ref}))
            return false;

        const uint64_t offsetU64 = static_cast<uint64_t>(offset);
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadAmcRegMem:
            {
                // [dst, base, index, loadBits, addrBits, mul, add] -> [dst, base, opBits, off]
                MicroInstrOperand newOps[4];
                newOps[0].reg      = ops[0].reg;
                newOps[1].reg      = base;
                newOps[2].opBits   = ops[3].opBits;
                newOps[3].valueU64 = offsetU64;
                ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegMem, newOps);
                return true;
            }
            case MicroInstrOpcode::LoadSignedExtAmcRegMem:
            case MicroInstrOpcode::LoadZeroExtAmcRegMem:
            {
                // [dst, base, index, dstBits, srcBits, mul, add] -> [dst, base, dstBits, srcBits, off]
                MicroInstrOperand newOps[5];
                newOps[0].reg      = ops[0].reg;
                newOps[1].reg      = base;
                newOps[2].opBits   = ops[3].opBits;
                newOps[3].opBits   = ops[4].opBits;
                newOps[4].valueU64 = offsetU64;
                ctx.emitRewrite(ref, inst.op == MicroInstrOpcode::LoadSignedExtAmcRegMem ? MicroInstrOpcode::LoadSignedExtRegMem : MicroInstrOpcode::LoadZeroExtRegMem, newOps);
                return true;
            }
            case MicroInstrOpcode::LoadAddrAmcRegMem:
            {
                // [dst, base, index, dstBits, addrBits, mul, add] -> [dst, base, opBits, off]
                MicroInstrOperand newOps[4];
                newOps[0].reg      = ops[0].reg;
                newOps[1].reg      = base;
                newOps[2].opBits   = ops[3].opBits;
                newOps[3].valueU64 = offsetU64;
                ctx.emitRewrite(ref, MicroInstrOpcode::LoadAddrRegMem, newOps);
                return true;
            }
            case MicroInstrOpcode::LoadAmcMemReg:
            {
                // [base, index, src, addrBits, srcBits, mul, add] -> [mem, src, opBits, off]
                MicroInstrOperand newOps[4];
                newOps[0].reg      = base;
                newOps[1].reg      = ops[2].reg;
                newOps[2].opBits   = ops[4].opBits;
                newOps[3].valueU64 = offsetU64;
                ctx.emitRewrite(ref, MicroInstrOpcode::LoadMemReg, newOps);
                return true;
            }
            case MicroInstrOpcode::LoadAmcMemImm:
            {
                // [base, index, _, addrBits, valBits, mul, add, imm] -> [mem, opBits, off, imm]
                MicroInstrOperand newOps[4];
                newOps[0].reg      = base;
                newOps[1].opBits   = ops[4].opBits;
                newOps[2].valueU64 = offsetU64;
                newOps[3]          = ops[7];
                ctx.emitRewrite(ref, MicroInstrOpcode::LoadMemImm, newOps);
                return true;
            }
            case MicroInstrOpcode::CmpAmcImm:
            {
                // [base, index, cmpBits, addrBits, mul, add, imm] -> [mem, opBits, off, imm]
                MicroInstrOperand newOps[4];
                newOps[0].reg      = base;
                newOps[1].opBits   = ops[2].opBits;
                newOps[2].valueU64 = offsetU64;
                newOps[3]          = ops[6];
                ctx.emitRewrite(ref, MicroInstrOpcode::CmpMemImm, newOps);
                return true;
            }
            default:
                return false;
        }
    }

    // A scalar global or constant accessed through its materialized address
    // folds into a single RIP-relative access:
    //
    //     LoadRegPtrReloc %a, <segment + K>            (Absolute64 reloc)
    //     dst = [%a + off]   or   [%a + off] = src
    //   ->
    //     dst = [rip]        or   [rip] = src          (Relative32 reloc, K + off)
    //
    // The proximity arena is what makes this legal under the JIT: code and
    // the constant and global segments carve from one reserved region, so the
    // displacement always fits, and the JIT patches it straight to the real
    // storage. Constant storage is immutable, so only reads fold for it. Each
    // consumer folds independently; the materializing load dies through DCE
    // once its last consumer is gone, and its relocation is pruned with it.
    bool tryFoldRelocatedAddressIntoAccess(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa || !ctx.builder)
            return false;

        uint8_t baseIdx = 0;
        uint8_t offIdx  = 0;
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegMem:
                baseIdx = 1;
                offIdx  = 3;
                break;
            case MicroInstrOpcode::LoadMemReg:
                baseIdx = 0;
                offIdx  = 3;
                break;
            default:
                return false;
        }

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || ops[2].opBits == MicroOpBits::B128)
            return false;

        const MicroReg base = ops[baseIdx].reg;
        if (!base.isVirtualInt())
            return false;

        const auto reaching = ctx.ssa->reachingDef(base, ref);
        if (!reaching.valid() || reaching.isPhi || !reaching.inst)
            return false;
        if (reaching.inst->op != MicroInstrOpcode::LoadRegPtrReloc)
            return false;

        // The address materialization owns the relocation naming the segment.
        const MicroRelocation* sourceReloc = nullptr;
        for (const MicroRelocation& reloc : ctx.builder->codeRelocations())
        {
            if (reloc.instructionRef == reaching.instRef)
            {
                sourceReloc = &reloc;
                break;
            }
        }
        if (!sourceReloc)
            return false;
        const bool isGlobal   = sourceReloc->kind == MicroRelocation::Kind::GlobalZeroAddress || sourceReloc->kind == MicroRelocation::Kind::GlobalInitAddress;
        const bool isConstant = sourceReloc->kind == MicroRelocation::Kind::ConstantAddress && sourceReloc->hasConstantSource();
        if (!isGlobal && !isConstant)
            return false;
        if (isConstant && inst.op != MicroInstrOpcode::LoadRegMem)
            return false;

        const uint64_t accessOffset = ops[offIdx].valueU64;
        if (accessOffset > 0x7FFFFFFFull)
            return false;

        uint32_t constantAccessOffset = INVALID_REF;
        if (isConstant)
        {
            if (sourceReloc->constantShard >= ConstantManager::SHARD_COUNT)
                return false;

            const uint64_t offsetU64 = static_cast<uint64_t>(sourceReloc->constantOffset) + accessOffset;
            if (offsetU64 > std::numeric_limits<uint32_t>::max())
                return false;

            const uint64_t        accessSize = getNumBits(ops[2].opBits) / 8;
            const DataSegment&    segment    = ctx.builder->ctx().cstMgr().shardDataSegment(sourceReloc->constantShard);
            DataSegmentAllocation allocation;
            if (!segment.findAllocation(allocation, sourceReloc->constantOffset))
                return false;
            if (offsetU64 < allocation.offset || offsetU64 + accessSize > static_cast<uint64_t>(allocation.offset) + allocation.size)
                return false;

            constantAccessOffset = static_cast<uint32_t>(offsetU64);
        }

        if (!ctx.claimAll({ref}))
            return false;

        // Copy before addRelocation: growth invalidates the pointer.
        MicroRelocation newReloc = *sourceReloc;
        newReloc.form            = MicroRelocation::Form::Relative32;
        newReloc.instructionRef  = ref;
        newReloc.targetAddress   = sourceReloc->targetAddress + accessOffset;
        if (isConstant)
            newReloc.constantOffset = constantAccessOffset;
        newReloc.codeOffset        = 0;
        newReloc.relativeEndOffset = 0;
        ctx.builder->addRelocation(newReloc);

        MicroInstrOperand newOps[4];
        for (uint8_t i = 0; i < 4; ++i)
            newOps[i] = ops[i];
        newOps[baseIdx].reg     = MicroReg::instructionPointer();
        newOps[offIdx].valueU64 = 0;
        ctx.emitRewrite(ref, inst.op, newOps);
        return true;
    }
}

SWC_END_NAMESPACE();
