#include "pch.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"
#include "Backend/Micro/MicroPassHelpers.h"

// Zero/sign extend whose upper bits are never read. Collapses to a plain
// LoadRegReg at srcBits, or an erase when dst == src.
//
// The bits a value's readers take are its demanded bits, walked through
// plain copies as LLVM's DemandedBits walks through moves and casts: a
// parameter sign-extended on entry, copied into a local and only compared at
// 32 bits never needs its upper half.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        constexpr uint32_t K_MAX_DEMAND_DEPTH = 4;
        // A chain of selects, one per `if`, passes its value through each.
        constexpr uint32_t K_MAX_SELECT_DEPTH = 24;

        // The width of a byte or word operation that updates `reg` in place, or
        // 0: such an operation reads its own bits and carries the rest of the
        // register into its result.
        uint32_t partialUpdateBits(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg reg)
        {
            if (!ops || ops[0].reg != reg)
                return 0;

            MicroOpBits bits = MicroOpBits::Zero;
            switch (inst.op)
            {
                case MicroInstrOpcode::OpBinaryRegReg:
                    bits = ops[2].opBits;
                    break;
                case MicroInstrOpcode::OpBinaryRegImm:
                case MicroInstrOpcode::OpUnaryReg:
                    bits = ops[1].opBits;
                    break;
                default:
                    return 0;
            }

            return bits == MicroOpBits::B8 || bits == MicroOpBits::B16 ? getNumBits(bits) : 0;
        }

        // The widest bit any reader takes from the value `reg` holds; 64 when a
        // reader is not understood. A copy into another virtual register reads
        // what that register's own readers read, capped at the copy's width. A
        // byte or word update reads its own bits plus whatever its result's
        // readers take from the bits it carries through. A phi reads what the
        // merged value's readers read: one nothing reads, as the SSA places at
        // a join the value does not live through, reads nothing, and one met
        // again on a loop adds nothing new.
        uint32_t demandedBits(const MicroSsaState& ssa, const MicroStorage& storage, const MicroOperandStorage& operands, const MicroSsaState::ValueInfo& valueInfo, MicroReg reg, uint32_t depth, SmallVector<uint32_t>& visitedPhis)
        {
            uint32_t widest = 0;
            for (const auto& useSite : valueInfo.uses)
            {
                if (useSite.kind == MicroSsaState::UseSite::Kind::Phi)
                {
                    const MicroSsaState::PhiInfo* phi = ssa.phiInfo(useSite.phiIndex);
                    if (!phi || phi->reg != reg || depth >= K_MAX_DEMAND_DEPTH)
                        return 64;
                    if (std::ranges::find(visitedPhis, useSite.phiIndex) != visitedPhis.end())
                        continue;
                    visitedPhis.push_back(useSite.phiIndex);
                    const auto* phiValue = ssa.valueInfo(phi->resultValueId);
                    if (!phiValue)
                        return 64;
                    widest = std::max(widest, demandedBits(ssa, storage, operands, *phiValue, reg, depth + 1, visitedPhis));
                    if (widest >= 64)
                        return 64;
                    continue;
                }
                if (useSite.kind != MicroSsaState::UseSite::Kind::Instruction)
                    return 64;
                const MicroInstr* useInst = storage.ptr(useSite.instRef);
                if (!useInst)
                    return 64;
                const MicroInstrOperand* useOps  = useInst->ops(operands);
                const MicroOpBits        useBits = useReadBits(*useInst, useOps, reg);
                if (useBits == MicroOpBits::Zero)
                    return 64;

                uint32_t       bits        = getNumBits(useBits);
                const uint32_t partialBits = partialUpdateBits(*useInst, useOps, reg);
                if (partialBits && depth < K_MAX_DEMAND_DEPTH)
                {
                    uint32_t resultValueId = 0;
                    if (!ssa.defValue(reg, useSite.instRef, resultValueId))
                        return 64;
                    const auto* resultInfo = ssa.valueInfo(resultValueId);
                    if (!resultInfo)
                        return 64;
                    bits = std::max(partialBits, demandedBits(ssa, storage, operands, *resultInfo, reg, depth + 1, visitedPhis));
                }
                // A select carries the value it keeps through, at its width.
                if (useInst->op == MicroInstrOpcode::LoadCondRegReg && useOps[0].reg == reg && useOps[1].reg != reg && depth < K_MAX_SELECT_DEPTH)
                {
                    uint32_t resultValueId = 0;
                    if (!ssa.defValue(reg, useSite.instRef, resultValueId))
                        return 64;
                    const auto* resultInfo = ssa.valueInfo(resultValueId);
                    if (!resultInfo)
                        return 64;
                    bits = std::min(getNumBits(useOps[3].opBits), demandedBits(ssa, storage, operands, *resultInfo, reg, depth + 1, visitedPhis));
                }
                if (useInst->op == MicroInstrOpcode::LoadRegReg && useOps[1].reg == reg && useOps[0].reg != reg &&
                    useOps[0].reg.isVirtual() && depth < K_MAX_DEMAND_DEPTH)
                {
                    uint32_t copyValueId = 0;
                    if (!ssa.defValue(useOps[0].reg, useSite.instRef, copyValueId))
                        return 64;
                    const auto* copyInfo = ssa.valueInfo(copyValueId);
                    if (!copyInfo)
                        return 64;
                    bits = std::min(bits, demandedBits(ssa, storage, operands, *copyInfo, useOps[0].reg, depth + 1, visitedPhis));
                }

                widest = std::max(widest, bits);
                if (widest >= 64)
                    return 64;
            }
            return widest;
        }

        // Whether `reg`, read at 32 bits where `atRef` reads it, is a boolean:
        // a setcc byte zero-extended to at least 32 bits, possibly copied.
        bool isExtendedBooleanByte(const Context& ctx, MicroReg reg, MicroInstrRef atRef)
        {
            constexpr uint32_t K_MAX_COPY_CHAIN = 4;
            for (uint32_t depth = 0; depth < K_MAX_COPY_CHAIN; ++depth)
            {
                const MicroSsaState::ReachingDef def = ctx.ssa->reachingDef(reg, atRef);
                if (!def.valid() || def.isPhi || !def.inst)
                    return false;

                const MicroInstrOperand* ops = def.inst->ops(*ctx.operands);
                if (def.inst->op == MicroInstrOpcode::LoadRegReg && ops[1].reg.isVirtualInt() && getNumBits(ops[2].opBits) >= 32)
                {
                    reg   = ops[1].reg;
                    atRef = def.instRef;
                    continue;
                }

                if (def.inst->op != MicroInstrOpcode::LoadZeroExtRegReg || ops[3].opBits != MicroOpBits::B8 || getNumBits(ops[2].opBits) < 32 ||
                    !ops[1].reg.isVirtualInt())
                    return false;
                const MicroSsaState::ReachingDef set = ctx.ssa->reachingDef(ops[1].reg, def.instRef);
                return set.valid() && !set.isPhi && set.inst && set.inst->op == MicroInstrOpcode::SetCondReg;
            }

            return false;
        }
    }

    // `a <=> b` lowers to zext(a > b) - zext(a < b) at 32 bits, sign-extended
    // into the result. The difference of two booleans fits a byte, so the
    // subtraction and the extension take the bytes, as LLVM narrows it, and
    // the two zero-extensions die.
    bool tryNarrowBooleanDifference(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || !ops[1].reg.isVirtualInt() || ops[3].opBits != MicroOpBits::B32 || getNumBits(ops[2].opBits) < 32)
            return false;

        const MicroSsaState::ReachingDef sub = ctx.ssa->reachingDef(ops[1].reg, ref);
        if (!sub.valid() || sub.isPhi || !sub.inst || sub.inst->op != MicroInstrOpcode::OpBinaryRegReg || ctx.isClaimed(sub.instRef))
            return false;

        const MicroInstrOperand* subOps = sub.inst->ops(*ctx.operands);
        if (subOps[3].microOp != MicroOp::Subtract || subOps[2].opBits != MicroOpBits::B32 || !subOps[1].reg.isVirtualInt() || subOps[0].reg == subOps[1].reg)
            return false;
        if (singleDirectInstructionUse(*ctx.ssa, sub.valueId) != ref)
            return false;
        if (!isExtendedBooleanByte(ctx, subOps[0].reg, sub.instRef) || !isExtendedBooleanByte(ctx, subOps[1].reg, sub.instRef))
            return false;
        if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, sub.instRef, ctx.builder))
            return false;
        if (!ctx.claimAll({ref, sub.instRef}))
            return false;

        MicroInstrOperand narrowOps[4];
        for (size_t idx = 0; idx < 4; ++idx)
            narrowOps[idx] = subOps[idx];
        narrowOps[2].opBits = MicroOpBits::B8;
        ctx.emitRewrite(sub.instRef, MicroInstrOpcode::OpBinaryRegReg, narrowOps);

        MicroInstrOperand extendOps[4];
        for (size_t idx = 0; idx < 4; ++idx)
            extendOps[idx] = ops[idx];
        extendOps[3].opBits = MicroOpBits::B8;
        ctx.emitRewrite(ref, MicroInstrOpcode::LoadSignedExtRegReg, extendOps);
        return true;
    }

    namespace
    {
        // `setbe T` after `cmp I, K` after `I = X - LO` (a 32-bit lea): T says
        // whether X lies in [LO, LO + K].
        struct RangeByte
        {
            MicroInstrRef setRef;
            MicroInstrRef cmpRef;
            MicroInstrRef leaRef;
            MicroReg      value;
            uint32_t      valueId = 0;
            uint64_t      low     = 0;
            uint64_t      span    = 0;
        };

        bool matchRangeByte(RangeByte& out, const Context& ctx, const MicroSsaState::ReachingDef& set)
        {
            if (!set.valid() || set.isPhi || !set.inst || set.inst->op != MicroInstrOpcode::SetCondReg ||
                set.inst->ops(*ctx.operands)[1].cpuCond != MicroCond::BelowOrEqual)
                return false;

            const MicroInstrRef cmpRef = ctx.storage->findPreviousInstructionRef(set.instRef);
            const MicroInstr*   cmp    = cmpRef.isValid() ? ctx.storage->ptr(cmpRef) : nullptr;
            if (!cmp || cmp->op != MicroInstrOpcode::CmpRegImm)
                return false;
            const MicroInstrOperand* cmpOps = cmp->ops(*ctx.operands);
            if (cmpOps[1].opBits != MicroOpBits::B32 || cmpOps[2].hasWideImmediateValue() || !cmpOps[0].reg.isVirtualInt())
                return false;

            const MicroInstrRef leaRef = ctx.storage->findPreviousInstructionRef(cmpRef);
            const MicroInstr*   lea    = leaRef.isValid() ? ctx.storage->ptr(leaRef) : nullptr;
            if (!lea || lea->op != MicroInstrOpcode::LoadAddrRegMem)
                return false;
            const MicroInstrOperand* leaOps = lea->ops(*ctx.operands);
            if (leaOps[0].reg != cmpOps[0].reg || leaOps[2].opBits != MicroOpBits::B32 || !leaOps[1].reg.isVirtualInt() || leaOps[1].reg == leaOps[0].reg)
                return false;

            const MicroSsaState::ReachingDef source = ctx.ssa->reachingDef(leaOps[1].reg, leaRef);
            uint32_t                         leaValueId = 0;
            if (!source.valid() || !ctx.ssa->defValue(leaOps[0].reg, leaRef, leaValueId) || singleDirectInstructionUse(*ctx.ssa, leaValueId) != cmpRef)
                return false;

            out.setRef  = set.instRef;
            out.cmpRef  = cmpRef;
            out.leaRef  = leaRef;
            out.value   = leaOps[1].reg;
            out.valueId = source.valueId;
            out.low     = (0 - leaOps[3].valueU64) & 0xFFFFFFFFu;
            out.span    = cmpOps[2].valueU64 & 0xFFFFFFFFu;
            return true;
        }

        // The bit a range keeps constant from its low end to its high end, with
        // every bit above it: the range is one block of values under that bit.
        bool rangeKeepsBitsFrom(const RangeByte& range, uint32_t bit)
        {
            const uint64_t high = range.low + range.span;
            return high <= 0xFFFFFFFFu && (range.low >> bit) == (high >> bit);
        }
    }

    // Two ranges of the same span that differ in one bit, as 'a'..'z' and
    // 'A'..'Z', are one range once that bit is cleared, as LLVM folds them:
    //
    //     I1 = X - 0x61; cmp I1, 25; setbe T1      I1 = X; I1 &= ~0x20; I1 -= 0x41
    //     D = T1                             ->    cmp I1, 25; setbe T1
    //     I2 = X - 0x41; cmp I2, 25; setbe T2      D = T1
    //     D |= T2
    //
    // The second test is left to the dead-code pass.
    bool tryFoldCaseRangePair(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || ops[3].microOp != MicroOp::Or || ops[2].opBits != MicroOpBits::B8 || !ops[0].reg.isVirtualInt() || !ops[1].reg.isVirtualInt() ||
            ops[0].reg == ops[1].reg)
            return false;

        // D holds the first byte, copied or OR-ed in, and only this OR reads it.
        const MicroSsaState::ReachingDef merged = ctx.ssa->reachingDef(ops[0].reg, ref);
        if (!merged.valid() || merged.isPhi || !merged.inst || singleDirectInstructionUse(*ctx.ssa, merged.valueId) != ref)
            return false;
        const MicroInstrOperand* mergedOps = merged.inst->ops(*ctx.operands);
        MicroReg                 firstByte;
        if (merged.inst->op == MicroInstrOpcode::LoadRegReg && mergedOps[2].opBits == MicroOpBits::B8)
            firstByte = mergedOps[1].reg;
        else if (merged.inst->op == MicroInstrOpcode::OpBinaryRegReg && mergedOps[3].microOp == MicroOp::Or && mergedOps[2].opBits == MicroOpBits::B8)
            firstByte = mergedOps[1].reg;
        else
            return false;
        if (!firstByte.isVirtualInt())
            return false;

        const MicroSsaState::ReachingDef firstSet  = ctx.ssa->reachingDef(firstByte, merged.instRef);
        const MicroSsaState::ReachingDef secondSet = ctx.ssa->reachingDef(ops[1].reg, ref);
        RangeByte                        first;
        RangeByte                        second;
        if (!matchRangeByte(first, ctx, firstSet) || !matchRangeByte(second, ctx, secondSet))
            return false;
        if (singleDirectInstructionUse(*ctx.ssa, firstSet.valueId) != merged.instRef || singleDirectInstructionUse(*ctx.ssa, secondSet.valueId) != ref)
            return false;
        if (first.value != second.value || first.valueId != second.valueId || first.span != second.span)
            return false;

        const uint64_t diff = first.low ^ second.low;
        if (!diff || (diff & (diff - 1)) != 0)
            return false;
        const uint32_t bit = static_cast<uint32_t>(std::countr_zero(diff));
        if (!rangeKeepsBitsFrom(first, bit) || !rangeKeepsBitsFrom(second, bit))
            return false;

        if (ctx.isClaimed(first.leaRef) || ctx.isClaimed(first.cmpRef) || ctx.isClaimed(merged.instRef))
            return false;
        if (!ctx.claimAll({ref, first.leaRef, first.cmpRef, first.setRef, merged.instRef}))
            return false;

        const uint64_t    low     = std::min(first.low, second.low);
        const MicroReg    index   = ctx.storage->ptr(first.leaRef)->ops(*ctx.operands)[0].reg;
        MicroInstrOperand copyOps[3];
        copyOps[0].reg    = index;
        copyOps[1].reg    = first.value;
        copyOps[2].opBits = MicroOpBits::B32;
        ctx.emitRewrite(first.leaRef, MicroInstrOpcode::LoadRegReg, copyOps);

        MicroInstrOperand maskOps[4];
        maskOps[0].reg     = index;
        maskOps[1].opBits  = MicroOpBits::B32;
        maskOps[2].microOp = MicroOp::And;
        maskOps[3].setImmediateValue(ApInt(~diff & 0xFFFFFFFFu, 32));
        ctx.emitInsertBefore(first.cmpRef, MicroInstrOpcode::OpBinaryRegImm, maskOps);
        if (low)
        {
            MicroInstrOperand subOps[4];
            subOps[0].reg     = index;
            subOps[1].opBits  = MicroOpBits::B32;
            subOps[2].microOp = MicroOp::Subtract;
            subOps[3].setImmediateValue(ApInt(low, 32));
            ctx.emitInsertBefore(first.cmpRef, MicroInstrOpcode::OpBinaryRegImm, subOps);
        }

        ctx.emitErase(ref);
        return true;
    }

    // `c >= 'A' and c <= 'Z'` on a byte compares the byte promoted to 32 bits:
    //
    //     I = zext(C)                        J = C             (byte)
    //     J = I - LO           (lea)   ->    J -= LO           (byte)
    //     cmp J, K                           cmp J, K          (byte)
    //
    // When the whole range fits a byte, the byte difference wraps exactly when
    // the wide one leaves the range, so unsigned and equality tests read the
    // same flags, as LLVM keeps the test at the byte's width. The widening
    // dies once nothing else reads it.
    bool tryNarrowByteRangeCompare(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || !ops[0].reg.isVirtualInt() || ops[1].opBits != MicroOpBits::B32 || ops[2].hasWideImmediateValue())
            return false;
        const uint64_t span = ops[2].valueU64 & 0xFFFFFFFFu;

        // The only reader of the flags is the next instruction, an unsigned or
        // equality test.
        const MicroInstrRef readerRef = ctx.storage->findNextInstructionRef(ref);
        const MicroInstr*   reader    = readerRef.isValid() ? ctx.storage->ptr(readerRef) : nullptr;
        if (!reader)
            return false;
        MicroCond cond = MicroCond::Unconditional;
        if (reader->op == MicroInstrOpcode::SetCondReg)
        {
            // A byte merged into a boolean chain stays a wide range test: the
            // chain and case-range folds read that form.
            cond = reader->ops(*ctx.operands)[1].cpuCond;

            const MicroInstrRef mergeRef = ctx.storage->findNextInstructionRef(readerRef);
            const MicroInstr*   merge    = mergeRef.isValid() ? ctx.storage->ptr(mergeRef) : nullptr;
            if (merge)
            {
                const MicroInstrOperand* mergeOps = merge->ops(*ctx.operands);
                const MicroReg           flag     = reader->ops(*ctx.operands)[0].reg;
                if ((merge->op == MicroInstrOpcode::LoadRegReg && mergeOps[1].reg == flag && mergeOps[2].opBits == MicroOpBits::B8) ||
                    (merge->op == MicroInstrOpcode::OpBinaryRegReg && mergeOps[1].reg == flag && mergeOps[2].opBits == MicroOpBits::B8))
                    return false;
            }
        }
        else if (reader->op == MicroInstrOpcode::JumpCond)
            cond = reader->ops(*ctx.operands)[0].cpuCond;
        else
            return false;
        switch (cond)
        {
            case MicroCond::Equal:
            case MicroCond::NotEqual:
            case MicroCond::Below:
            case MicroCond::BelowOrEqual:
            case MicroCond::Above:
            case MicroCond::AboveOrEqual:
                break;
            default:
                return false;
        }
        if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, readerRef, ctx.builder))
            return false;

        // J = I - LO, read by this compare alone.
        const MicroSsaState::ReachingDef offset = ctx.ssa->reachingDef(ops[0].reg, ref);
        if (!offset.valid() || offset.isPhi || !offset.inst || offset.inst->op != MicroInstrOpcode::LoadAddrRegMem || ctx.isClaimed(offset.instRef) ||
            singleDirectInstructionUse(*ctx.ssa, offset.valueId) != ref)
            return false;
        const MicroInstrOperand* leaOps = offset.inst->ops(*ctx.operands);
        if (leaOps[0].reg != ops[0].reg || leaOps[2].opBits != MicroOpBits::B32 || !leaOps[1].reg.isVirtualInt())
            return false;
        const uint64_t low = (0 - leaOps[3].valueU64) & 0xFFFFFFFFu;
        if (low > 0xFF || span > 0xFF - low)
            return false;

        // I = zext(C) from a byte.
        const MicroSsaState::ReachingDef widened = ctx.ssa->reachingDef(leaOps[1].reg, offset.instRef);
        if (!widened.valid() || widened.isPhi || !widened.inst || widened.inst->op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;
        const MicroInstrOperand* extOps = widened.inst->ops(*ctx.operands);
        if (extOps[0].reg != leaOps[1].reg || extOps[3].opBits != MicroOpBits::B8 || getNumBits(extOps[2].opBits) < 32 || !extOps[1].reg.isAnyInt() ||
            extOps[1].reg == extOps[0].reg)
            return false;

        // The byte still holds C where the offset reads it.
        const MicroReg                   byteReg     = extOps[1].reg;
        const MicroSsaState::ReachingDef atExtend    = ctx.ssa->reachingDef(byteReg, widened.instRef);
        const MicroSsaState::ReachingDef atOffset    = ctx.ssa->reachingDef(byteReg, offset.instRef);
        if (!byteReg.isVirtualInt() || !atExtend.valid() || !atOffset.valid() || atExtend.valueId != atOffset.valueId)
            return false;

        if (!ctx.claimAll({ref, offset.instRef}))
            return false;

        MicroInstrOperand copyOps[3];
        copyOps[0].reg    = ops[0].reg;
        copyOps[1].reg    = byteReg;
        copyOps[2].opBits = MicroOpBits::B8;
        ctx.emitRewrite(offset.instRef, MicroInstrOpcode::LoadRegReg, copyOps);

        if (low)
        {
            MicroInstrOperand subOps[4];
            subOps[0].reg     = ops[0].reg;
            subOps[1].opBits  = MicroOpBits::B8;
            subOps[2].microOp = MicroOp::Subtract;
            subOps[3].setImmediateValue(ApInt(low, 8));
            ctx.emitInsertBefore(ref, MicroInstrOpcode::OpBinaryRegImm, subOps);
        }

        MicroInstrOperand cmpOps[3];
        cmpOps[0].reg    = ops[0].reg;
        cmpOps[1].opBits = MicroOpBits::B8;
        cmpOps[2].setImmediateValue(ApInt(span, 8));
        ctx.emitRewrite(ref, MicroInstrOpcode::CmpRegImm, cmpOps);
        return true;
    }

    namespace
    {
        constexpr uint32_t K_MAX_FLAG_WALK = 4;

        // The compare whose flags `ref` reads: the nearest earlier compare
        // across instructions that leave the flags alone.
        MicroInstrRef findFlagSource(const Context& ctx, MicroInstrRef ref)
        {
            MicroInstrRef at = ref;
            for (uint32_t step = 0; step < K_MAX_FLAG_WALK; ++step)
            {
                at                     = ctx.storage->findPreviousInstructionRef(at);
                const MicroInstr* inst = at.isValid() ? ctx.storage->ptr(at) : nullptr;
                if (!inst)
                    return MicroInstrRef::invalid();
                if (inst->op == MicroInstrOpcode::CmpRegReg || inst->op == MicroInstrOpcode::CmpRegImm)
                    return at;
                if (inst->op != MicroInstrOpcode::LoadRegImm && inst->op != MicroInstrOpcode::LoadRegReg)
                    return MicroInstrRef::invalid();
            }
            return MicroInstrRef::invalid();
        }

        // Whether two compares test the same values the same way.
        bool isSameCompareOfSameValues(const Context& ctx, MicroInstrRef leftRef, MicroInstrRef rightRef)
        {
            const MicroInstr* left  = ctx.storage->ptr(leftRef);
            const MicroInstr* right = ctx.storage->ptr(rightRef);
            if (!left || !right || left->op != right->op)
                return false;
            const MicroInstrOperand* leftOps  = left->ops(*ctx.operands);
            const MicroInstrOperand* rightOps = right->ops(*ctx.operands);
            if (leftOps[0].reg != rightOps[0].reg || leftOps[1].opBits != rightOps[1].opBits)
                return false;
            if (left->op == MicroInstrOpcode::CmpRegReg)
            {
                if (leftOps[1].reg != rightOps[1].reg || leftOps[2].opBits != rightOps[2].opBits)
                    return false;
            }
            else if (leftOps[2].hasWideImmediateValue() || rightOps[2].hasWideImmediateValue() || leftOps[2].valueU64 != rightOps[2].valueU64)
                return false;

            const auto sameValue = [&](MicroReg reg) {
                const MicroSsaState::ReachingDef atLeft  = ctx.ssa->reachingDef(reg, leftRef);
                const MicroSsaState::ReachingDef atRight = ctx.ssa->reachingDef(reg, rightRef);
                return atLeft.valid() && atRight.valid() && atLeft.valueId == atRight.valueId;
            };
            if (!leftOps[0].reg.isVirtualInt() || !sameValue(leftOps[0].reg))
                return false;
            return left->op != MicroInstrOpcode::CmpRegReg || (leftOps[1].reg.isVirtualInt() && sameValue(leftOps[1].reg));
        }

        bool constantAt(uint64_t& outValue, const Context& ctx, MicroReg reg, MicroInstrRef atRef)
        {
            if (!reg.isVirtualInt())
                return false;
            const MicroSsaState::ReachingDef def = ctx.ssa->reachingDef(reg, atRef);
            if (!def.valid() || def.isPhi || !def.inst)
                return false;
            if (def.inst->op == MicroInstrOpcode::ClearReg)
            {
                outValue = 0;
                return true;
            }
            const MicroInstrOperand* ops = def.inst->ops(*ctx.operands);
            if (def.inst->op != MicroInstrOpcode::LoadRegImm || ops[2].hasWideImmediateValue())
                return false;
            outValue = ops[2].valueU64 & getBitsMask(ops[1].opBits);
            return true;
        }

        // Whether `reg`, where `atRef` reads it, is `cond ? value : 0` at
        // `bits`: a select over a zero, or, for 1, a widened setcc. Returns the
        // compare the selection read.
        MicroInstrRef matchFlagSelect(const Context& ctx, MicroReg reg, MicroInstrRef atRef, MicroCond cond, uint64_t value, MicroOpBits bits)
        {
            MicroSsaState::ReachingDef def = ctx.ssa->reachingDef(reg, atRef);
            if (def.valid() && !def.isPhi && def.inst && def.inst->op == MicroInstrOpcode::LoadRegReg)
            {
                const MicroInstrOperand* copyOps = def.inst->ops(*ctx.operands);
                if (getNumBits(copyOps[2].opBits) < getNumBits(bits) || !copyOps[1].reg.isVirtualInt())
                    return MicroInstrRef::invalid();
                def = ctx.ssa->reachingDef(copyOps[1].reg, def.instRef);
            }
            if (!def.valid() || def.isPhi || !def.inst)
                return MicroInstrRef::invalid();

            const MicroInstrOperand* ops = def.inst->ops(*ctx.operands);
            if (def.inst->op == MicroInstrOpcode::LoadCondRegReg)
            {
                uint64_t initial  = 0;
                uint64_t selected = 0;
                if (ops[2].cpuCond != cond || getNumBits(ops[3].opBits) < getNumBits(bits) || !constantAt(initial, ctx, ops[0].reg, def.instRef) ||
                    !constantAt(selected, ctx, ops[1].reg, def.instRef))
                    return MicroInstrRef::invalid();
                if ((initial & getBitsMask(bits)) != 0 || (selected & getBitsMask(bits)) != (value & getBitsMask(bits)))
                    return MicroInstrRef::invalid();
                return findFlagSource(ctx, def.instRef);
            }

            if (def.inst->op == MicroInstrOpcode::LoadZeroExtRegReg && value == 1 && ops[3].opBits == MicroOpBits::B8 &&
                getNumBits(ops[2].opBits) >= getNumBits(bits) && ops[1].reg.isVirtualInt())
            {
                const MicroSsaState::ReachingDef set = ctx.ssa->reachingDef(ops[1].reg, def.instRef);
                if (!set.valid() || set.isPhi || !set.inst || set.inst->op != MicroInstrOpcode::SetCondReg ||
                    set.inst->ops(*ctx.operands)[1].cpuCond != cond)
                    return MicroInstrRef::invalid();
                return findFlagSource(ctx, set.instRef);
            }

            return MicroInstrRef::invalid();
        }
    }

    // `if a < b return -1; if a > b return 1; return 0` selects twice from
    // the same compare:
    //
    //     D = 0; cmovg D, 1                  setg H
    //     cmp a, b                     ->    setl L
    //     cmovl D, -1                        H -= L         (bytes)
    //                                        D = sext(H)
    //
    // The two conditions exclude each other, so D is the three-way sign,
    // lowered as LLVM lowers `scmp`. Either order of the two selects, and the
    // unsigned conditions, take the same form.
    bool tryFoldThreeWaySelects(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa || !ctx.passContext)
            return false;

        const MicroInstrOperand* ops  = inst.ops(*ctx.operands);
        const MicroReg           dst  = ops[0].reg;
        const MicroOpBits        bits = ops[3].opBits;
        if (!dst.isVirtualInt() || (bits != MicroOpBits::B32 && bits != MicroOpBits::B64))
            return false;

        MicroCond greater = MicroCond::Unconditional;
        MicroCond less    = MicroCond::Unconditional;
        switch (ops[2].cpuCond)
        {
            case MicroCond::Less:
            case MicroCond::Greater:
                greater = MicroCond::Greater;
                less    = MicroCond::Less;
                break;
            case MicroCond::Below:
            case MicroCond::Above:
                greater = MicroCond::Above;
                less    = MicroCond::Below;
                break;
            default:
                return false;
        }

        // The outer select takes 1 on `greater` or -1 on `less`; the value it
        // replaces is the other one or zero.
        const bool     outerIsLess = ops[2].cpuCond == less;
        const uint64_t minusOne    = getBitsMask(bits);
        uint64_t       selected    = 0;
        if (!constantAt(selected, ctx, ops[1].reg, ref) || selected != (outerIsLess ? minusOne : 1))
            return false;

        const MicroInstrRef outerCompare = findFlagSource(ctx, ref);
        if (!outerCompare.isValid())
            return false;
        const MicroInstrRef innerCompare = matchFlagSelect(ctx, dst, ref, outerIsLess ? greater : less, outerIsLess ? 1 : minusOne, bits);
        if (!innerCompare.isValid() || !isSameCompareOfSameValues(ctx, innerCompare, outerCompare))
            return false;
        if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder))
            return false;

        if (!ctx.nextVirtualIntRegIndex)
            MicroPassHelpers::computeNextVirtualRegIndices(*ctx.passContext, ctx.nextVirtualIntRegIndex, ctx.nextVirtualFloatRegIndex);
        if (ctx.nextVirtualIntRegIndex + 2 >= MicroReg::K_MAX_INDEX)
            return false;
        if (!ctx.claimAll({ref}))
            return false;

        const MicroReg high = MicroReg::virtualIntReg(ctx.nextVirtualIntRegIndex++);
        const MicroReg low  = MicroReg::virtualIntReg(ctx.nextVirtualIntRegIndex++);

        MicroInstrOperand highOps[2];
        highOps[0].reg     = high;
        highOps[1].cpuCond = greater;
        ctx.emitInsertBefore(ref, MicroInstrOpcode::SetCondReg, highOps);
        MicroInstrOperand lowOps[2];
        lowOps[0].reg     = low;
        lowOps[1].cpuCond = less;
        ctx.emitInsertBefore(ref, MicroInstrOpcode::SetCondReg, lowOps);
        MicroInstrOperand subOps[4];
        subOps[0].reg     = high;
        subOps[1].reg     = low;
        subOps[2].opBits  = MicroOpBits::B8;
        subOps[3].microOp = MicroOp::Subtract;
        ctx.emitInsertBefore(ref, MicroInstrOpcode::OpBinaryRegReg, subOps);

        MicroInstrOperand signOps[4];
        signOps[0].reg    = dst;
        signOps[1].reg    = high;
        signOps[2].opBits = bits;
        signOps[3].opBits = MicroOpBits::B8;
        ctx.emitRewrite(ref, MicroInstrOpcode::LoadSignedExtRegReg, signOps);
        return true;
    }

    // A compare whose flags are written again before anything reads them does
    // nothing, as a select folded away leaves its compare behind.
    bool tryDropDeadCompare(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        SWC_UNUSED(inst);
        if (ctx.isClaimed(ref) || !MicroPassHelpers::areCpuFlagsRedefinedBeforeBoundary(*ctx.storage, *ctx.operands, ref))
            return false;
        if (!ctx.claimAll({ref}))
            return false;
        ctx.emitErase(ref);
        return true;
    }

    // A 64-bit select whose result is only read on its low 32 bits selects at
    // 32 bits: a branch turned into a select takes the width of its widest
    // arm, and the narrower arm then needs a zero-extending copy the dword
    // select no longer asks for.
    bool tryNarrowSelect(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops || ops[3].opBits != MicroOpBits::B64 || !ops[0].reg.isVirtualInt() || !ops[1].reg.isAnyInt())
            return false;

        uint32_t valueId = 0;
        if (!ctx.ssa->defValue(ops[0].reg, ref, valueId))
            return false;
        const auto* valueInfo = ctx.ssa->valueInfo(valueId);
        if (!valueInfo || valueInfo->uses.empty())
            return false;
        SmallVector<uint32_t> visitedPhis;
        if (demandedBits(*ctx.ssa, *ctx.storage, *ctx.operands, *valueInfo, ops[0].reg, 0, visitedPhis) > 32)
            return false;

        // The readers keep reading no more than the low half during the sweep.
        // A reading select narrows by this same rule, from the same demand, so
        // a chain of them narrows in one sweep.
        const auto isSelect = [&](MicroInstrRef useRef) {
            const MicroInstr* useInst = ctx.storage->ptr(useRef);
            return useInst && useInst->op == MicroInstrOpcode::LoadCondRegReg;
        };
        for (const auto& useSite : valueInfo->uses)
        {
            if (useSite.kind == MicroSsaState::UseSite::Kind::Instruction && !isSelect(useSite.instRef) && ctx.isClaimed(useSite.instRef))
                return false;
        }
        if (!ctx.claimAll({ref}))
            return false;
        for (const auto& useSite : valueInfo->uses)
        {
            if (useSite.kind == MicroSsaState::UseSite::Kind::Instruction && !isSelect(useSite.instRef))
                ctx.claimed.insert(useSite.instRef.get());
        }

        MicroInstrOperand narrowOps[4];
        for (size_t i = 0; i < 4; ++i)
            narrowOps[i] = ops[i];
        narrowOps[3].opBits = MicroOpBits::B32;
        ctx.emitRewrite(ref, MicroInstrOpcode::LoadCondRegReg, narrowOps);
        return true;
    }

    bool tryNarrowExtend(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops)
            return false;

        const MicroReg    dst     = ops[0].reg;
        const MicroReg    src     = ops[1].reg;
        const MicroOpBits dstBits = ops[2].opBits;
        const MicroOpBits srcBits = ops[3].opBits;

        if (!dst.isVirtual() || dstBits == srcBits || srcBits == MicroOpBits::Zero)
            return false;

        uint32_t valueId = 0;
        if (!ctx.ssa->defValue(dst, ref, valueId))
            return false;

        const auto* valueInfo = ctx.ssa->valueInfo(valueId);
        if (!valueInfo || valueInfo->uses.empty())
            return false;

        SmallVector<uint32_t> visitedPhis;
        if (demandedBits(*ctx.ssa, *ctx.storage, *ctx.operands, *valueInfo, dst, 0, visitedPhis) > getNumBits(srcBits))
            return false;

        if (!ctx.claimAll({ref}))
            return false;

        if (dst == src)
        {
            ctx.emitErase(ref);
            return true;
        }

        MicroInstrOperand moveOps[3];
        moveOps[0].reg    = dst;
        moveOps[1].reg    = src;
        moveOps[2].opBits = srcBits;
        ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegReg, moveOps);
        return true;
    }

    // A 32-bit copy whose readers never look above bit 31 moves the whole
    // register instead. The zero-extension it performed is unobservable, and
    // a full-width move is what copy elimination merges and what the
    // allocator's same-register copies erase to: `mov ecx, ecx` survived to the
    // emitted code for every u32 parameter copied into a local. The readers are
    // claimed so no rule of the same sweep can lean on the upper half being
    // zero while it stops being so.
    //
    // A byte or word write whose readers take no more than its own bits is
    // widened to 32 bits the same way, as LLVM promotes i8 arithmetic on x86:
    // the write no longer keeps the rest of the register, so the value it
    // replaces can die, and a select of two such bytes becomes a cmov.
    bool tryWidenCopyWithNarrowReaders(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops = inst.ops(*ctx.operands);
        if (!ops)
            return false;

        const bool        immediate = inst.op == MicroInstrOpcode::LoadRegImm;
        const MicroOpBits bits      = ops[immediate ? 1 : 2].opBits;
        const bool        partial   = bits == MicroOpBits::B8 || bits == MicroOpBits::B16;
        if (bits != MicroOpBits::B32 && !partial)
            return false;
        if (immediate && (!partial || ops[2].hasWideImmediateValue()))
            return false;

        const MicroReg dst = ops[0].reg;
        const MicroReg src = immediate ? MicroReg::invalid() : ops[1].reg;
        if (!dst.isVirtualInt() || (!immediate && (!src.isAnyInt() || dst == src)))
            return false;
        if (partial && ctx.booleanMerges.contains(dst.index()))
            return false;

        uint32_t valueId = 0;
        if (!ctx.ssa->defValue(dst, ref, valueId))
            return false;
        const auto* valueInfo = ctx.ssa->valueInfo(valueId);
        if (!valueInfo || valueInfo->uses.empty())
            return false;
        SmallVector<uint32_t> visitedPhis;
        if (demandedBits(*ctx.ssa, *ctx.storage, *ctx.operands, *valueInfo, dst, 0, visitedPhis) > getNumBits(bits))
            return false;

        if (ctx.isRelocated(ref))
            return false;
        for (const auto& useSite : valueInfo->uses)
        {
            if (useSite.kind == MicroSsaState::UseSite::Kind::Instruction && ctx.isClaimed(useSite.instRef))
                return false;
        }
        if (!ctx.claimAll({ref}))
            return false;
        for (const auto& useSite : valueInfo->uses)
        {
            if (useSite.kind == MicroSsaState::UseSite::Kind::Instruction)
                ctx.claimed.insert(useSite.instRef.get());
        }

        if (immediate)
        {
            MicroInstrOperand loadOps[3];
            loadOps[0].reg      = dst;
            loadOps[1].opBits   = MicroOpBits::B32;
            loadOps[2].valueU64 = ops[2].valueU64 & (bits == MicroOpBits::B8 ? 0xFF : 0xFFFF);
            ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegImm, loadOps);
            return true;
        }

        MicroInstrOperand moveOps[3];
        moveOps[0].reg    = dst;
        moveOps[1].reg    = src;
        // A byte or word copy read on at most 32 bits moves the whole register at
        // once: both widths write all of it, and the full move is the one copy
        // elimination merges, a sweep earlier.
        moveOps[2].opBits = MicroOpBits::B64;
        ctx.emitRewrite(ref, MicroInstrOpcode::LoadRegReg, moveOps);
        return true;
    }
}

SWC_END_NAMESPACE();
