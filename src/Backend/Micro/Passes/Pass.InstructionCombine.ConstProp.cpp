#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroReg.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"
#include "Backend/RuntimeBuildConfig.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"

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

    // A select between zero and one is the condition itself. Reuse the adjacent,
    // single-use source materialization for setcc, then widen its byte explicitly:
    // the use/def model must not mistake setcc for a full-register definition.
    bool tryFoldBooleanSelect(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;
        const MicroInstrOperand* ops  = inst.ops(*ctx.operands);
        const MicroReg           dst  = ops[0].reg;
        const MicroReg           src  = ops[1].reg;
        const MicroOpBits        bits = ops[3].opBits;
        if (!dst.isVirtualInt() || !src.isVirtualInt() || dst == src ||
            (bits != MicroOpBits::B32 && bits != MicroOpBits::B64))
            return false;

        const MicroInstrRef sourceRef = ctx.previousRef(ref);
        const MicroInstr*   source    = ctx.instruction(sourceRef);
        if (!source || source->op != MicroInstrOpcode::LoadRegImm)
            return false;
        const MicroInstrOperand* sourceOps = source->ops(*ctx.operands);
        if (sourceOps[0].reg != src || sourceOps[1].opBits != bits ||
            sourceOps[2].hasWideImmediateValue() || sourceOps[2].valueU64 > 1)
            return false;
        const uint64_t sourceValue = sourceOps[2].valueU64;

        const auto destinationDef = ctx.ssa->reachingDef(dst, ref);
        if (!destinationDef.valid())
            return false;
        const auto* destinationValue = ctx.ssa->valueInfo(destinationDef.valueId);
        if (!destinationValue || destinationValue->isPhi())
            return false;
        const MicroInstr* initial = ctx.instruction(destinationValue->instRef);
        if (!initial || initial->op != MicroInstrOpcode::LoadRegImm)
            return false;
        const MicroInstrOperand* initialOps = initial->ops(*ctx.operands);
        if (initialOps[1].opBits != bits || initialOps[2].hasWideImmediateValue() || initialOps[2].valueU64 != 1 - sourceValue)
            return false;
        if (!valueHasSingleUse(*ctx.ssa, src, sourceRef))
            return false;

        MicroCond condition = ops[2].cpuCond;
        if (condition == MicroCond::Unconditional ||
            (sourceValue == 0 && !MicroPassHelpers::invertCondition(condition, condition)))
            return false;
        if (!ctx.claimAll({sourceRef, ref}))
            return false;

        MicroInstrOperand setOps[2];
        setOps[0].reg     = src;
        setOps[1].cpuCond = condition;
        ctx.emitRewrite(sourceRef, MicroInstrOpcode::SetCondReg, setOps);
        MicroInstrOperand extendOps[4];
        extendOps[0].reg    = dst;
        extendOps[1].reg    = src;
        extendOps[2].opBits = bits;
        extendOps[3].opBits = MicroOpBits::B8;
        ctx.emitRewrite(ref, MicroInstrOpcode::LoadZeroExtRegReg, extendOps);
        return true;
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
            case MicroInstrOpcode::VecUnaryAmcRegMem:
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
            case MicroInstrOpcode::VecUnaryAmcRegMem:
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
            case MicroInstrOpcode::VecUnaryAmcRegMem:
            {
                // [dst, base, index, opBits, addrBits, mul, add, microOp] -> [dst, base, opBits, off, microOp]
                MicroInstrOperand newOps[5];
                newOps[0].reg      = ops[0].reg;
                newOps[1].reg      = base;
                newOps[2].opBits   = ops[3].opBits;
                newOps[3].valueU64 = offsetU64;
                newOps[4].microOp  = ops[7].microOp;
                ctx.emitRewrite(ref, MicroInstrOpcode::VecUnaryRegMem, newOps);
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
            case MicroInstrOpcode::LoadVecRegMem:
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
        if (!ops)
            return false;

        // Sixteen bytes read into a vector register are the one wide form the
        // instruction-pointer-relative encoding covers, and the form every
        // vector constant arrives in: a broadcast lane, a rounding term, a
        // mask, each built once in the constant pool and read through an
        // address a general register had to hold. A sixteen-byte store keeps
        // its address register.
        const bool isVectorLoad = ops[2].opBits == MicroOpBits::B128 && inst.op != MicroInstrOpcode::LoadMemReg;
        if (ops[2].opBits == MicroOpBits::B128 && !isVectorLoad)
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
        const bool isGlobal = sourceReloc->kind == MicroRelocation::Kind::GlobalZeroAddress || sourceReloc->kind == MicroRelocation::Kind::GlobalInitAddress;

        // Constants fold in every artifact, library images included. They were
        // gated out of those for a year after a module DLL came back rendering
        // black: the hazard was never the address arithmetic but the
        // relocation the fold hands to the access, which another rule could
        // then rewrite into an encoding the emitter does not bind - leaving
        // the patch site at zero, and the image writer overwriting the first
        // bytes of a function. Every rewriting pass now refuses a relocated
        // access, and the emitter fails the build if a relocation it still
        // carries goes unbound.
        const bool isConstant = sourceReloc->kind == MicroRelocation::Kind::ConstantAddress && sourceReloc->hasConstantSource();
        if (!isGlobal && !isConstant)
            return false;
        if (isConstant && inst.op == MicroInstrOpcode::LoadMemReg)
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

        // The access now carries a relocation, so it is opaque to every rule
        // for the rest of this run as well: the set the pass built at entry
        // knows nothing of a relocation made since.
        ctx.relocated.insert(ref.get());

        MicroInstrOperand newOps[4];
        for (uint8_t i = 0; i < 4; ++i)
            newOps[i] = ops[i];
        newOps[baseIdx].reg     = MicroReg::instructionPointer();
        newOps[offIdx].valueU64 = 0;

        // Both loads move the same sixteen bytes into the same register; the
        // general form is the one whose displacement the emitter binds, and it
        // encodes the unaligned vector move when its destination is a vector
        // register.
        const MicroInstrOpcode newOp = inst.op == MicroInstrOpcode::LoadVecRegMem ? MicroInstrOpcode::LoadRegMem : inst.op;
        ctx.emitRewrite(ref, newOp, newOps);
        return true;
    }

    namespace
    {
        constexpr int K_MAX_BOUND_DEPTH = 6;

        // Proves an inclusive unsigned upper bound for the full value of 'reg' at
        // 'useRef', by walking its reaching definitions. Only definitions whose
        // write zero-extends to the full register width participate (32- and
        // 64-bit forms); a narrower write merges with stale upper bits and proves
        // nothing.
        bool unsignedUpperBound(uint64_t& outBound, const Context& ctx, MicroReg reg, MicroInstrRef useRef, int depth)
        {
            if (depth <= 0 || !reg.isVirtualInt())
                return false;

            const auto rd = ctx.ssa->reachingDef(reg, useRef);
            if (!rd.valid() || rd.isPhi || !rd.inst)
                return false;

            const MicroInstrOperand* defOps = rd.inst->ops(*ctx.operands);
            if (!defOps || defOps[0].reg != reg)
                return false;

            switch (rd.inst->op)
            {
                case MicroInstrOpcode::LoadRegImm:
                    if (getNumBits(defOps[1].opBits) < 32)
                        return false;
                    outBound = defOps[2].valueU64 & getBitsMask(defOps[1].opBits);
                    return true;

                case MicroInstrOpcode::ClearReg:
                    outBound = 0;
                    return true;

                case MicroInstrOpcode::LoadRegReg:
                    if (getNumBits(defOps[2].opBits) < 32)
                        return false;
                    return unsignedUpperBound(outBound, ctx, defOps[1].reg, rd.instRef, depth - 1);

                case MicroInstrOpcode::LoadZeroExtRegReg:
                {
                    if (getNumBits(defOps[2].opBits) < 32)
                        return false;
                    const uint64_t srcMask = getBitsMask(defOps[3].opBits);
                    uint64_t       inner   = 0;
                    if (unsignedUpperBound(inner, ctx, defOps[1].reg, rd.instRef, depth - 1))
                        outBound = std::min(inner, srcMask);
                    else
                        outBound = srcMask;
                    return true;
                }

                case MicroInstrOpcode::OpBinaryRegImm:
                {
                    if (getNumBits(defOps[1].opBits) < 32)
                        return false;
                    const uint64_t opMask = getBitsMask(defOps[1].opBits);
                    const uint64_t imm    = defOps[3].valueU64 & opMask;
                    if (defOps[2].microOp == MicroOp::And)
                    {
                        outBound = imm;
                        return true;
                    }
                    if (defOps[2].microOp == MicroOp::ShiftRight)
                    {
                        uint64_t inner = 0;
                        if (!unsignedUpperBound(inner, ctx, reg, rd.instRef, depth - 1))
                            inner = opMask;
                        outBound = imm >= 64 ? 0 : inner >> imm;
                        return true;
                    }
                    if (defOps[2].microOp == MicroOp::Add || defOps[2].microOp == MicroOp::Or)
                    {
                        // x|imm never exceeds x+imm, so one saturating sum
                        // bounds both, as long as the sum stays in the width.
                        uint64_t inner = 0;
                        if (!unsignedUpperBound(inner, ctx, reg, rd.instRef, depth - 1))
                            return false;
                        if (inner + imm < inner || inner + imm > opMask)
                            return false;
                        outBound = inner + imm;
                        return true;
                    }
                    return false;
                }

                case MicroInstrOpcode::OpBinaryRegReg:
                {
                    if (getNumBits(defOps[2].opBits) < 32)
                        return false;
                    if (defOps[1].reg == reg)
                        return false;
                    if (defOps[3].microOp != MicroOp::Add && defOps[3].microOp != MicroOp::Or)
                        return false;
                    const uint64_t opMask = getBitsMask(defOps[2].opBits);
                    uint64_t       lhs    = 0;
                    uint64_t       rhs    = 0;
                    if (!unsignedUpperBound(lhs, ctx, reg, rd.instRef, depth - 1))
                        return false;
                    if (!unsignedUpperBound(rhs, ctx, defOps[1].reg, rd.instRef, depth - 1))
                        return false;
                    if (lhs + rhs < lhs || lhs + rhs > opMask)
                        return false;
                    outBound = lhs + rhs;
                    return true;
                }

                default:
                    return false;
            }
        }
    }

    // cmp reg, imm whose outcome the operand's provable range decides.
    //
    // The shift legalizer guards every variable-count shift with
    // 'cmp count, width' + 'cmov value, 0 if ae', but the count usually reaches
    // the compare through 'and count, mask' with mask < width. The compare then
    // never takes its AboveOrEqual arm, and a Huffman or bit-stream loop pays
    // four dead instructions per shift for it. When an unsigned upper bound
    // proves the register below the immediate, resolve every conditional-move
    // consumer of the flags and drop the compare.
    bool tryDropRangeProvedCompare(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst)
    {
        if (ctx.isClaimed(cmpRef) || !ctx.ssa)
            return false;

        const MicroInstrOperand* cmpOps = cmpInst.ops(*ctx.operands);
        if (!cmpOps)
            return false;

        const MicroReg reg      = cmpOps[0].reg;
        const uint64_t cmpMask  = getBitsMask(cmpOps[1].opBits);
        const uint64_t immValue = cmpOps[2].valueU64 & cmpMask;
        if (immValue == 0)
            return false;

        uint64_t bound = 0;
        if (!unsignedUpperBound(bound, ctx, reg, cmpRef, K_MAX_BOUND_DEPTH))
            return false;
        if (bound >= immValue)
            return false;

        // The register is provably Below the immediate. Collect every consumer
        // of the compare's flags up to the next flag write; anything but a
        // conditional move on a decided unsigned condition keeps the compare.
        struct ResolvedUse
        {
            MicroInstrRef ref;
            bool          taken;
        };
        SmallVector<ResolvedUse, 4> uses;

        auto       walker = ctx.storage->view().begin();
        const auto endIt  = ctx.storage->view().end();
        while (walker != endIt && walker.current != cmpRef)
            ++walker;
        if (walker == endIt)
            return false;
        ++walker;

        bool windowClosed = false;
        for (uint32_t step = 0; step < 16 && walker != endIt; ++step, ++walker)
        {
            const MicroInstr&    inst = *walker;
            const MicroInstrDef& info = MicroInstr::info(inst.op);

            if (info.flags.has(MicroInstrFlagsE::UsesCpuFlags))
            {
                if (inst.op != MicroInstrOpcode::LoadCondRegReg || ctx.isClaimed(walker.current))
                    return false;
                const MicroInstrOperand* useOps = inst.ops(*ctx.operands);
                if (!useOps)
                    return false;

                bool taken = false;
                switch (useOps[2].cpuCond)
                {
                    case MicroCond::Above:
                    case MicroCond::AboveOrEqual:
                    case MicroCond::Equal:
                        taken = false;
                        break;
                    case MicroCond::Below:
                    case MicroCond::BelowOrEqual:
                    case MicroCond::NotEqual:
                        taken = true;
                        break;
                    default:
                        return false;
                }

                uses.push_back({walker.current, taken});
            }

            if (MicroPassHelpers::instructionActuallyDefinesCpuFlags(inst, inst.ops(*ctx.operands)))
            {
                windowClosed = true;
                break;
            }

            // A return or a call ends the flags' life; any jump or label can
            // leak them to code this scan does not see.
            if (inst.op == MicroInstrOpcode::Ret || info.flags.has(MicroInstrFlagsE::IsCallInstruction))
            {
                windowClosed = true;
                break;
            }
            if (info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                inst.op == MicroInstrOpcode::Label)
                return false;
        }

        if (!windowClosed)
            return false;

        if (!ctx.claimAll({cmpRef}))
            return false;
        for (const ResolvedUse& use : uses)
        {
            if (!ctx.claimAll({use.ref}))
                return false;
        }

        ctx.emitErase(cmpRef);
        for (const ResolvedUse& use : uses)
        {
            if (!use.taken)
            {
                ctx.emitErase(use.ref);
                continue;
            }

            const MicroInstr*        useInst = ctx.storage->ptr(use.ref);
            const MicroInstrOperand* useOps  = useInst->ops(*ctx.operands);
            MicroInstrOperand        moveOps[3];
            moveOps[0].reg    = useOps[0].reg;
            moveOps[1].reg    = useOps[1].reg;
            moveOps[2].opBits = useOps[3].opBits;
            ctx.emitRewrite(use.ref, MicroInstrOpcode::LoadRegReg, moveOps);
        }

        return true;
    }
}

SWC_END_NAMESPACE();
