#include "pch.h"
#include "Backend/Encoder/Encoder.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.PostRAPeephole.Internal.h"

SWC_BEGIN_NAMESPACE();

namespace PostRaPeephole
{
    // An unsigned modular sum is at least its original left operand exactly
    // when the addition did not carry. Keep the ADD flags across a fallback
    // constant load and let the conditional move consume CF directly:
    //
    //     mov S, A                 mov S, A
    //     add S, B                 add S, B
    //     cmp S, A        ->
    //     mov R, fallback          mov R, fallback
    //     cmovae R, S              cmovae R, S
    bool tryReuseAddFlagsForUnsignedWrap(Context& ctx, const MicroInstrRef cmpRef, const MicroInstr& cmpInst)
    {
        if (ctx.isClaimed(cmpRef) || cmpInst.op != MicroInstrOpcode::CmpRegReg)
            return false;
        const auto* cmp = cmpInst.ops(*ctx.operands);
        if (!cmp || (cmp[2].opBits != MicroOpBits::B8 && cmp[2].opBits != MicroOpBits::B16 &&
                     cmp[2].opBits != MicroOpBits::B32 && cmp[2].opBits != MicroOpBits::B64) ||
            !cmp[0].reg.isInt() || !cmp[1].reg.isInt() || cmp[0].reg == cmp[1].reg)
            return false;
        const MicroReg    sum      = cmp[0].reg;
        const MicroReg    original = cmp[1].reg;
        const MicroOpBits bits     = cmp[2].opBits;

        const MicroInstrRef addRef = ctx.previousRef(cmpRef);
        const MicroInstr*   add    = ctx.instruction(addRef);
        const auto*         addOps = add ? add->ops(*ctx.operands) : nullptr;
        if (!add || !addOps || addOps[0].reg != sum)
            return false;
        MicroOpBits addBits;
        MicroOp     addOp;
        switch (add->op)
        {
            case MicroInstrOpcode::OpBinaryRegReg:
            case MicroInstrOpcode::OpBinaryRegMem:
                addBits = addOps[2].opBits;
                addOp   = addOps[3].microOp;
                break;
            case MicroInstrOpcode::OpBinaryRegAmcMem:
                addBits = addOps[3].opBits;
                addOp   = addOps[7].microOp;
                break;
            default:
                return false;
        }
        if (addBits != bits || addOp != MicroOp::Add)
            return false;

        MicroInstrRef       copyRef = ctx.previousRef(addRef);
        const MicroInstr*   copy    = ctx.instruction(copyRef);
        MicroInstrRef       middleLoadRef;
        if (copy && copy->op != MicroInstrOpcode::LoadRegReg)
        {
            const auto* middleOps = copy->ops(*ctx.operands);
            const MicroInstrUseDef useDef = copy->collectUseDef(*ctx.operands, ctx.encoder);
            if (add->op != MicroInstrOpcode::OpBinaryRegReg || !middleOps ||
                (copy->op != MicroInstrOpcode::LoadRegMem && copy->op != MicroInstrOpcode::LoadAmcRegMem) ||
                middleOps[0].reg != addOps[1].reg ||
                std::ranges::find(useDef.uses, sum) != useDef.uses.end() ||
                std::ranges::find(useDef.uses, original) != useDef.uses.end() ||
                std::ranges::find(useDef.defs, sum) != useDef.defs.end() ||
                std::ranges::find(useDef.defs, original) != useDef.defs.end())
                return false;
            middleLoadRef = copyRef;
            copyRef       = ctx.previousRef(middleLoadRef);
            copy          = ctx.instruction(copyRef);
        }
        const auto* copied = copy ? copy->ops(*ctx.operands) : nullptr;
        if (!copy || copy->op != MicroInstrOpcode::LoadRegReg || !copied ||
            copied[0].reg != sum || copied[1].reg != original || getNumBits(copied[2].opBits) < getNumBits(bits))
            return false;
        const MicroInstrRef loadRef = ctx.previousRef(copyRef);
        const MicroInstr*   load    = ctx.instruction(loadRef);
        const auto*         loaded  = load ? load->ops(*ctx.operands) : nullptr;
        if (!load || load->op != MicroInstrOpcode::LoadAmcRegMem || !loaded || loaded[0].reg != original ||
            loaded[3].opBits != bits || load->numOperands > Action::K_MAX_OPS)
            return false;

        const MicroInstrRef fallbackRef = ctx.nextRef(cmpRef);
        const MicroInstr*   fallback    = ctx.instruction(fallbackRef);
        const auto*         fallbackOps = fallback ? fallback->ops(*ctx.operands) : nullptr;
        const MicroInstrRef selectRef   = ctx.nextRef(fallbackRef);
        const MicroInstr*   select      = ctx.instruction(selectRef);
        const auto*         selected    = select ? select->ops(*ctx.operands) : nullptr;
        const bool narrow = bits == MicroOpBits::B8 || bits == MicroOpBits::B16;
        if (!fallback || fallback->op != MicroInstrOpcode::LoadRegImm || !fallbackOps ||
            !select || select->op != MicroInstrOpcode::LoadCondRegReg || !selected ||
            selected[0].reg != fallbackOps[0].reg || selected[1].reg != sum ||
            selected[2].cpuCond != MicroCond::AboveOrEqual || selected[3].opBits != (narrow ? MicroOpBits::B32 : bits) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, selectRef, ctx.builder))
            return false;

        MicroInstrRef extendRef;
        if (narrow)
        {
            extendRef               = ctx.nextRef(selectRef);
            const MicroInstr* extend = ctx.instruction(extendRef);
            const auto*       ext    = extend ? extend->ops(*ctx.operands) : nullptr;
            if (!extend || extend->op != MicroInstrOpcode::LoadZeroExtRegReg || !ext ||
                ext[0].reg != selected[0].reg || ext[1].reg != selected[0].reg ||
                ext[2].opBits != MicroOpBits::B64 || ext[3].opBits != bits)
                return false;
        }

        MicroInstrOperand rewrittenLoad[Action::K_MAX_OPS] = {};
        std::copy_n(loaded, load->numOperands, rewrittenLoad);
        rewrittenLoad[0].reg = sum;
        MicroInstr loadProbe = *load;
        if (narrow)
        {
            loadProbe.op               = MicroInstrOpcode::LoadZeroExtAmcRegMem;
            loadProbe.numOperands      = 7;
            rewrittenLoad[3].opBits    = MicroOpBits::B32;
            rewrittenLoad[4].opBits    = bits;
        }
        std::array<MicroInstrRef, 8> refs;
        size_t                       numRefs = 0;
        refs[numRefs++]                      = loadRef;
        refs[numRefs++]                      = copyRef;
        if (middleLoadRef.isValid())
            refs[numRefs++] = middleLoadRef;
        refs[numRefs++] = addRef;
        refs[numRefs++] = cmpRef;
        refs[numRefs++] = fallbackRef;
        refs[numRefs++] = selectRef;
        if (narrow)
            refs[numRefs++] = extendRef;
        MicroConformanceIssue issue;
        if ((ctx.encoder && ctx.encoder->queryConformanceIssue(issue, loadProbe, rewrittenLoad)) ||
            !ctx.claimAll(std::span{refs.data(), numRefs}))
            return false;
        if (narrow)
            ctx.emitRewrite(loadRef, loadProbe.op, std::span{rewrittenLoad, 7}, true);
        else
            ctx.emitRewrite(loadRef, loadProbe.op, std::span{rewrittenLoad, load->numOperands});
        ctx.emitErase(copyRef);
        ctx.emitErase(cmpRef);
        if (narrow)
            ctx.emitErase(extendRef);
        return true;
    }

    // Reuse a nearby identical register comparison across instructions that
    // preserve both its operands and the CPU flags. Conditional moves are the
    // common case: they consume the first comparison without changing it, so
    // a second comparison of the same values is redundant.
    bool tryEraseRepeatedCompare(Context& ctx, const MicroInstrRef cmpRef, const MicroInstr& cmpInst)
    {
        if (ctx.isClaimed(cmpRef) || cmpInst.op != MicroInstrOpcode::CmpRegReg)
            return false;
        const auto* cmp = cmpInst.ops(*ctx.operands);
        if (!cmp || !cmp[0].reg.isAnyInt() || !cmp[1].reg.isAnyInt())
            return false;

        constexpr uint32_t                       maxWindow = 4;
        std::array<MicroInstrRef, maxWindow + 1> window;
        window[0]            = cmpRef;
        MicroInstrRef cursor = ctx.previousRef(cmpRef);
        for (uint32_t step = 1; step <= maxWindow && cursor.isValid(); ++step, cursor = ctx.previousRef(cursor))
        {
            const MicroInstr* previous = ctx.instruction(cursor);
            if (!previous || ctx.isClaimed(cursor))
                return false;
            window[step]                 = cursor;
            const auto* previousOperands = previous->ops(*ctx.operands);
            if (previous->op == MicroInstrOpcode::CmpRegReg && previousOperands &&
                previousOperands[0].reg == cmp[0].reg && previousOperands[1].reg == cmp[1].reg &&
                previousOperands[2].opBits == cmp[2].opBits)
            {
                if (!ctx.claimAll(std::span{window.data(), step + 1}))
                    return false;
                ctx.emitErase(cmpRef);
                return true;
            }

            const MicroInstrDef& info = MicroInstr::info(previous->op);
            if (previous->op == MicroInstrOpcode::Label || info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                info.flags.has(MicroInstrFlagsE::JumpInstruction) || info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                instructionActuallyDefinesCpuFlags(*previous, previousOperands))
                return false;

            const MicroInstrUseDef useDef = previous->collectUseDef(*ctx.operands, ctx.encoder);
            if (std::ranges::find(useDef.defs, cmp[0].reg) != useDef.defs.end() ||
                std::ranges::find(useDef.defs, cmp[1].reg) != useDef.defs.end())
                return false;
        }
        return false;
    }

    bool isComparisonOpcode(MicroInstrOpcode op)
    {
        switch (op)
        {
            case MicroInstrOpcode::CmpRegReg:
            case MicroInstrOpcode::CmpRegImm:
            case MicroInstrOpcode::CmpMemReg:
            case MicroInstrOpcode::CmpMemImm:
            case MicroInstrOpcode::CmpAmcReg:
            case MicroInstrOpcode::CmpAmcImm:
            case MicroInstrOpcode::TestRegReg:
            case MicroInstrOpcode::TestRegImm:
            case MicroInstrOpcode::TestMemReg:
            case MicroInstrOpcode::TestMemImm:
                return true;
            default:
                return false;
        }
    }

    // A comparison repeated right after the branch that read it is redundant:
    // a conditional jump leaves the flags it tested untouched, and nothing
    // runs between it and the instruction it falls through to.
    //
    //     cmp [rcx + rax], r9b ; je .L ; cmp [rcx + rax], r9b ; setae
    //   ->
    //     cmp [rcx + rax], r9b ; je .L ; setae
    //
    // A byte-by-byte comparison ends that way: the loop leaves on the first
    // difference and the exit block asks which side was larger, which is the
    // flags the loop's own compare left.
    bool tryEraseCompareAfterBranch(Context& ctx, const MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !isComparisonOpcode(inst.op))
            return false;

        const MicroInstrRef jumpRef = ctx.previousRef(ref);
        const MicroInstr*   jump    = ctx.instruction(jumpRef);
        if (!jump || jump->op != MicroInstrOpcode::JumpCond)
            return false;
        const MicroInstrOperand* jumpOps = jump->ops(*ctx.operands);
        if (!jumpOps || jumpOps[0].cpuCond == MicroCond::Unconditional)
            return false;

        const MicroInstrRef earlierRef = ctx.previousRef(jumpRef);
        const MicroInstr*   earlier    = ctx.instruction(earlierRef);
        if (!earlier || earlier->op != inst.op || earlier->numOperands != inst.numOperands)
            return false;

        const MicroInstrOperand* repeated = inst.ops(*ctx.operands);
        const MicroInstrOperand* original = earlier->ops(*ctx.operands);
        if (!repeated || !original)
            return false;
        for (uint8_t index = 0; index < inst.numOperands; ++index)
        {
            if (repeated[index].valueU64 != original[index].valueU64 ||
                repeated[index].hasWideImmediateValue() || original[index].hasWideImmediateValue())
                return false;
        }

        if (!ctx.claimAll({earlierRef, jumpRef, ref}))
            return false;
        ctx.emitErase(ref);
        return true;
    }

    // The overflow-safe unsigned average idiom can use a widened add once
    // both dword inputs are known to have clear upper halves:
    //
    //     M = A; M &= B                  A += B, b64
    //     A ^= B; A >>= 1, b32    ->    A >>= 1, b64
    //     A += M
    bool tryFoldUnsignedAverage(Context& ctx, MicroInstrRef addRef, const MicroInstr& addInst)
    {
        if (ctx.isClaimed(addRef))
            return false;
        const auto* add = addInst.ops(*ctx.operands);
        if (!add || add[2].opBits != MicroOpBits::B32 || add[3].microOp != MicroOp::Add ||
            !add[0].reg.isInt() || !add[1].reg.isInt() || add[0].reg == add[1].reg ||
            ctx.isPrivateFrameBase(add[0].reg) || ctx.isPrivateFrameBase(add[1].reg) ||
            !ctx.isRegDeadAfterCurrent(add[1].reg) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, addRef, ctx.builder))
            return false;

        const MicroReg      result = add[0].reg;
        const MicroReg      mask   = add[1].reg;
        const MicroInstrRef shiftRef = ctx.previousRef(addRef);
        const MicroInstr*   shift    = ctx.instruction(shiftRef);
        const auto*         shifted  = shift ? shift->ops(*ctx.operands) : nullptr;
        if (!shift || shift->op != MicroInstrOpcode::OpBinaryRegImm || !shifted || shifted[0].reg != result ||
            shifted[1].opBits != MicroOpBits::B32 || shifted[2].microOp != MicroOp::ShiftRight ||
            shifted[3].hasWideImmediateValue() || shifted[3].valueU64 != 1)
            return false;

        const MicroInstrRef xorRef = ctx.previousRef(shiftRef);
        const MicroInstr*   xorInst = ctx.instruction(xorRef);
        const auto*         xorOps  = xorInst ? xorInst->ops(*ctx.operands) : nullptr;
        if (!xorInst || xorInst->op != MicroInstrOpcode::OpBinaryRegReg || !xorOps || xorOps[0].reg != result ||
            !xorOps[1].reg.isInt() || xorOps[1].reg == result || xorOps[1].reg == mask ||
            xorOps[2].opBits != MicroOpBits::B32 || xorOps[3].microOp != MicroOp::Xor)
            return false;
        const MicroReg other = xorOps[1].reg;

        const MicroInstrRef andRef = ctx.previousRef(xorRef);
        const MicroInstr*   andInst = ctx.instruction(andRef);
        const auto*         andOps  = andInst ? andInst->ops(*ctx.operands) : nullptr;
        const MicroInstrRef copyRef = ctx.previousRef(andRef);
        const MicroInstr*   copyInst = ctx.instruction(copyRef);
        const auto*         copyOps  = copyInst ? copyInst->ops(*ctx.operands) : nullptr;
        if (!andInst || andInst->op != MicroInstrOpcode::OpBinaryRegReg || !andOps ||
            andOps[0].reg != mask || andOps[1].reg != other || andOps[2].opBits != MicroOpBits::B32 || andOps[3].microOp != MicroOp::And ||
            !copyInst || copyInst->op != MicroInstrOpcode::LoadRegReg || !copyOps ||
            copyOps[0].reg != mask || copyOps[1].reg != result || copyOps[2].opBits != MicroOpBits::B32 ||
            !ctx.isUpperHalfZeroBefore(copyRef, result) || !ctx.isUpperHalfZeroBefore(copyRef, other))
            return false;

        MicroInstrOperand widenedAdd[4] = {add[0], xorOps[1], add[2], add[3]};
        widenedAdd[2].opBits            = MicroOpBits::B64;
        MicroInstrOperand widenedShift[4] = {shifted[0], shifted[1], shifted[2], shifted[3]};
        widenedShift[1].opBits            = MicroOpBits::B64;
        MicroConformanceIssue issue;
        if ((ctx.encoder && (ctx.encoder->queryConformanceIssue(issue, addInst, widenedAdd) ||
                             ctx.encoder->queryConformanceIssue(issue, *shift, widenedShift))) ||
            !ctx.claimAll({copyRef, andRef, xorRef, shiftRef, addRef}))
            return false;
        ctx.emitErase(copyRef);
        ctx.emitRewrite(andRef, MicroInstrOpcode::OpBinaryRegReg, widenedAdd);
        ctx.emitErase(xorRef);
        ctx.emitRewrite(shiftRef, shift->op, widenedShift);
        ctx.emitErase(addRef);
        return true;
    }

    // A byte/word overflow-safe average can add in a dword once both indexed
    // loads zero-extend. The widened sum cannot overflow, and its low result
    // is the same value as the original bitwise identity. The ceiling form
    // similarly becomes `(A + B + 1) >> 1`.
    bool tryFoldNarrowUnsignedAverage(Context& ctx, const MicroInstrRef extendRef, const MicroInstr& extendInst)
    {
        if (ctx.isClaimed(extendRef) || !ctx.encoder || extendInst.op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;
        const auto* extend = extendInst.ops(*ctx.operands);
        if (!extend || extend[2].opBits != MicroOpBits::B64 ||
            (extend[3].opBits != MicroOpBits::B8 && extend[3].opBits != MicroOpBits::B16) ||
            !extend[0].reg.isInt() || !extend[1].reg.isInt() || extend[0].reg == extend[1].reg)
            return false;
        const MicroOpBits bits   = extend[3].opBits;
        const MicroReg    result = extend[0].reg;
        const MicroReg    merged = extend[1].reg;

        const MicroInstrRef combineRef = ctx.previousRef(extendRef);
        const MicroInstr*   combine    = ctx.instruction(combineRef);
        const auto*         combined   = combine ? combine->ops(*ctx.operands) : nullptr;
        const MicroInstrRef shiftRef   = ctx.previousRef(combineRef);
        const MicroInstr*   shift      = ctx.instruction(shiftRef);
        const auto*         shifted    = shift ? shift->ops(*ctx.operands) : nullptr;
        const MicroInstrRef xorRef     = ctx.previousRef(shiftRef);
        const MicroInstr*   xorInst    = ctx.instruction(xorRef);
        const auto*         xorOps     = xorInst ? xorInst->ops(*ctx.operands) : nullptr;
        const MicroInstrRef mergeRef   = ctx.previousRef(xorRef);
        const MicroInstr*   merge      = ctx.instruction(mergeRef);
        const auto*         mergeOps   = merge ? merge->ops(*ctx.operands) : nullptr;
        const MicroInstrRef copyRef    = ctx.previousRef(mergeRef);
        const MicroInstr*   copy       = ctx.instruction(copyRef);
        const auto*         copyOps    = copy ? copy->ops(*ctx.operands) : nullptr;
        if (!combine || combine->op != MicroInstrOpcode::OpBinaryRegReg || !combined ||
            combined[0].reg != merged || combined[1].reg != result || combined[2].opBits != bits ||
            (combined[3].microOp != MicroOp::Add && combined[3].microOp != MicroOp::Subtract) ||
            !shift || shift->op != MicroInstrOpcode::OpBinaryRegImm || !shifted || shifted[0].reg != result ||
            shifted[1].opBits != bits || shifted[2].microOp != MicroOp::ShiftRight || shifted[3].hasWideImmediateValue() || shifted[3].valueU64 != 1 ||
            !xorInst || xorInst->op != MicroInstrOpcode::OpBinaryRegReg || !xorOps || xorOps[0].reg != result ||
            xorOps[2].opBits != bits || xorOps[3].microOp != MicroOp::Xor ||
            !merge || merge->op != MicroInstrOpcode::OpBinaryRegReg || !mergeOps || mergeOps[0].reg != merged ||
            mergeOps[1].reg != xorOps[1].reg || mergeOps[2].opBits != bits ||
            !copy || copy->op != MicroInstrOpcode::LoadRegReg || !copyOps || copyOps[0].reg != merged ||
            copyOps[1].reg != result || copyOps[2].opBits != MicroOpBits::B64 ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, combineRef, ctx.builder))
            return false;
        const bool floor = mergeOps[3].microOp == MicroOp::And && combined[3].microOp == MicroOp::Add;
        const bool ceil  = mergeOps[3].microOp == MicroOp::Or && combined[3].microOp == MicroOp::Subtract;
        if ((!floor && !ceil) || !xorOps[1].reg.isInt() || xorOps[1].reg == result || xorOps[1].reg == merged)
            return false;
        const MicroReg other = xorOps[1].reg;

        const MicroInstrRef otherLoadRef  = ctx.previousRef(copyRef);
        const MicroInstr*   otherLoad     = ctx.instruction(otherLoadRef);
        const auto*         otherLoadOps  = otherLoad ? otherLoad->ops(*ctx.operands) : nullptr;
        const MicroInstrRef resultLoadRef = ctx.previousRef(otherLoadRef);
        const MicroInstr*   resultLoad    = ctx.instruction(resultLoadRef);
        const auto*         resultLoadOps = resultLoad ? resultLoad->ops(*ctx.operands) : nullptr;
        if (!otherLoad || otherLoad->op != MicroInstrOpcode::LoadAmcRegMem || !otherLoadOps ||
            otherLoadOps[0].reg != other || otherLoadOps[3].opBits != bits || otherLoadOps[4].opBits != MicroOpBits::B64 ||
            !resultLoad || resultLoad->op != MicroInstrOpcode::LoadAmcRegMem || !resultLoadOps ||
            resultLoadOps[0].reg != result || resultLoadOps[3].opBits != bits || resultLoadOps[4].opBits != MicroOpBits::B64)
            return false;

        MicroInstrOperand widenedResultLoad[7];
        MicroInstrOperand widenedOtherLoad[7];
        std::copy_n(resultLoadOps, 7, widenedResultLoad);
        std::copy_n(otherLoadOps, 7, widenedOtherLoad);
        widenedResultLoad[3].opBits = MicroOpBits::B32;
        widenedResultLoad[4].opBits = bits;
        widenedOtherLoad[3].opBits  = MicroOpBits::B32;
        widenedOtherLoad[4].opBits  = bits;
        MicroInstrOperand widenedAdd[4] = {mergeOps[0], mergeOps[1], mergeOps[2], mergeOps[3]};
        widenedAdd[0].reg               = result;
        widenedAdd[2].opBits            = MicroOpBits::B32;
        widenedAdd[3].microOp           = MicroOp::Add;
        MicroInstrOperand widenedShift[4] = {shifted[0], shifted[1], shifted[2], shifted[3]};
        widenedShift[1].opBits            = MicroOpBits::B32;
        MicroInstrOperand increment[3]    = {};
        increment[0].reg                  = result;
        increment[1].opBits               = MicroOpBits::B32;
        increment[2].microOp              = MicroOp::Add;

        MicroInstr loadProbe;
        loadProbe.op          = MicroInstrOpcode::LoadZeroExtAmcRegMem;
        loadProbe.numOperands = 7;
        MicroInstr incrementProbe;
        incrementProbe.op          = MicroInstrOpcode::OpUnaryReg;
        incrementProbe.numOperands = 3;
        MicroConformanceIssue issue;
        if (ctx.encoder->queryConformanceIssue(issue, loadProbe, widenedResultLoad) ||
            ctx.encoder->queryConformanceIssue(issue, loadProbe, widenedOtherLoad) ||
            ctx.encoder->queryConformanceIssue(issue, *merge, widenedAdd) ||
            ctx.encoder->queryConformanceIssue(issue, *shift, widenedShift) ||
            (ceil && ctx.encoder->queryConformanceIssue(issue, incrementProbe, increment)) ||
            !ctx.claimAll({resultLoadRef, otherLoadRef, copyRef, mergeRef, xorRef, shiftRef, combineRef, extendRef}))
            return false;

        ctx.emitRewrite(resultLoadRef, loadProbe.op, widenedResultLoad, true);
        ctx.emitRewrite(otherLoadRef, loadProbe.op, widenedOtherLoad, true);
        ctx.emitErase(copyRef);
        ctx.emitRewrite(mergeRef, merge->op, widenedAdd);
        if (ceil)
            ctx.emitRewrite(xorRef, incrementProbe.op, increment);
        else
            ctx.emitErase(xorRef);
        ctx.emitRewrite(shiftRef, shift->op, widenedShift);
        ctx.emitErase(combineRef);
        ctx.emitErase(extendRef);
        return true;
    }

    namespace
    {
        bool isCompareInstruction(MicroInstrOpcode op)
        {
            switch (op)
            {
                case MicroInstrOpcode::TestRegReg:
                case MicroInstrOpcode::TestRegImm:
                case MicroInstrOpcode::TestMemReg:
                case MicroInstrOpcode::TestMemImm:
                case MicroInstrOpcode::CmpRegReg:
                case MicroInstrOpcode::CmpRegImm:
                case MicroInstrOpcode::CmpMemReg:
                case MicroInstrOpcode::CmpMemImm:
                case MicroInstrOpcode::CmpAmcImm:
                case MicroInstrOpcode::CmpAmcReg:
                    return true;

                default:
                    return false;
            }
        }

        bool canMoveComparisonForSelect(const MicroInstr& inst, const MicroInstrOperand* ops)
        {
            if (!isCompareInstruction(inst.op) || !ops)
                return false;
            // A RIP-relative memory comparison can own a relocation tied to
            // its instruction reference. Keep such comparisons in place.
            return (inst.op != MicroInstrOpcode::CmpMemReg && inst.op != MicroInstrOpcode::CmpMemImm &&
                    inst.op != MicroInstrOpcode::TestMemReg && inst.op != MicroInstrOpcode::TestMemImm) ||
                   !ops[0].reg.isInstructionPointer();
        }
    }

    // Turn `flag != 0 ? ~value : value` into a zero/nonzero mask. NEG exposes
    // nonzero as carry, SBB materializes the mask, and XOR applies it.
    bool tryFoldConditionalBitwiseNot(Context& ctx, const MicroInstrRef compareRef, const MicroInstr& compareInst)
    {
        if (ctx.isClaimed(compareRef) || !ctx.encoder || !ctx.encoder->supportsCarryArithmetic() ||
            compareInst.op != MicroInstrOpcode::CmpRegImm)
            return false;
        const auto* compared = compareInst.ops(*ctx.operands);
        if (!compared || !compared[0].reg.isInt() || ctx.isPrivateFrameBase(compared[0].reg) ||
            (compared[1].opBits != MicroOpBits::B32 && compared[1].opBits != MicroOpBits::B64) ||
            compared[2].hasWideImmediateValue() || compared[2].valueU64 != 0)
            return false;
        const MicroReg    flag = compared[0].reg;
        const MicroOpBits bits = compared[1].opBits;

        const MicroInstrRef copyRef = ctx.nextRef(compareRef);
        const MicroInstr*   copy    = ctx.instruction(copyRef);
        const auto*         copied  = copy ? copy->ops(*ctx.operands) : nullptr;
        if (!copy || copy->op != MicroInstrOpcode::LoadRegReg || !copied ||
            !copied[0].reg.isInt() || !copied[1].reg.isInt() || copied[0].reg == copied[1].reg ||
            copied[0].reg == flag || copied[1].reg == flag || ctx.isPrivateFrameBase(copied[0].reg) ||
            (copied[2].opBits != bits && !(copied[2].opBits == MicroOpBits::B64 && bits == MicroOpBits::B32)))
            return false;
        const MicroReg result = copied[0].reg;
        const MicroReg value  = copied[1].reg;

        const MicroInstrRef notRef = ctx.nextRef(copyRef);
        const MicroInstr*   bitNot = ctx.instruction(notRef);
        const auto*         negated = bitNot ? bitNot->ops(*ctx.operands) : nullptr;
        const MicroInstrRef selectRef = ctx.nextRef(notRef);
        const MicroInstr*   select    = ctx.instruction(selectRef);
        const auto*         selected  = select ? select->ops(*ctx.operands) : nullptr;
        if (!bitNot || bitNot->op != MicroInstrOpcode::OpUnaryReg || !negated ||
            negated[0].reg != result || negated[1].opBits != bits || negated[2].microOp != MicroOp::BitwiseNot ||
            !select || select->op != MicroInstrOpcode::LoadCondRegReg || !selected ||
            selected[0].reg != result || selected[1].reg != value || selected[2].cpuCond != MicroCond::Equal ||
            selected[3].opBits != bits || !ctx.isRegDeadAfter(flag, ctx.instructionIndex + 3) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, selectRef, ctx.builder))
            return false;

        MicroInstrOperand clear[2] = {};
        clear[0].reg               = result;
        clear[1].opBits            = bits;
        MicroInstr clearProbe;
        clearProbe.op          = MicroInstrOpcode::ClearReg;
        clearProbe.numOperands = 2;
        MicroInstrOperand negate[3] = {};
        negate[0].reg               = flag;
        negate[1].opBits            = bits;
        negate[2].microOp           = MicroOp::Negate;
        MicroInstr negateProbe;
        negateProbe.op          = MicroInstrOpcode::OpUnaryReg;
        negateProbe.numOperands = 3;
        MicroInstrOperand subtract[3] = {};
        subtract[0].reg               = result;
        subtract[1].reg               = result;
        subtract[2].opBits            = bits;
        MicroInstr subtractProbe;
        subtractProbe.op          = MicroInstrOpcode::SubtractBorrowRegReg;
        subtractProbe.numOperands = 3;
        MicroInstrOperand apply[4] = {};
        apply[0].reg               = result;
        apply[1].reg               = value;
        apply[2].opBits            = bits;
        apply[3].microOp           = MicroOp::Xor;
        MicroInstr applyProbe;
        applyProbe.op          = MicroInstrOpcode::OpBinaryRegReg;
        applyProbe.numOperands = 4;
        MicroConformanceIssue issue;
        if (ctx.encoder->queryConformanceIssue(issue, clearProbe, clear) ||
            ctx.encoder->queryConformanceIssue(issue, negateProbe, negate) ||
            ctx.encoder->queryConformanceIssue(issue, subtractProbe, subtract) ||
            ctx.encoder->queryConformanceIssue(issue, applyProbe, apply) ||
            !ctx.claimAll({compareRef, copyRef, notRef, selectRef}))
            return false;

        ctx.emitRewrite(compareRef, clearProbe.op, clear);
        ctx.emitRewrite(copyRef, negateProbe.op, negate);
        ctx.emitRewrite(notRef, subtractProbe.op, subtract);
        ctx.emitRewrite(selectRef, applyProbe.op, apply);
        return true;
    }

    // Select between `a + b` and `a - b` by selecting the sign of `b`, then
    // adding `a` once. The masked flag and `a` must both die with the select
    // because the shorter sequence keeps their original values until then.
    bool tryFoldConditionalAddSubtract(Context& ctx, const MicroInstrRef maskRef, const MicroInstr& maskInst)
    {
        if (ctx.isClaimed(maskRef) || !ctx.encoder || maskInst.op != MicroInstrOpcode::OpBinaryRegImm)
            return false;
        const auto* mask = maskInst.ops(*ctx.operands);
        if (!mask || !mask[0].reg.isInt() || ctx.isPrivateFrameBase(mask[0].reg) ||
            (mask[1].opBits != MicroOpBits::B32 && mask[1].opBits != MicroOpBits::B64) ||
            mask[2].microOp != MicroOp::And || mask[3].hasWideImmediateValue() || mask[3].valueU64 != 1)
            return false;
        const MicroReg    flag = mask[0].reg;
        const MicroOpBits bits = mask[1].opBits;

        const MicroInstrRef sumRef = ctx.nextRef(maskRef);
        const MicroInstr*   sum    = ctx.instruction(sumRef);
        const auto*         summed = sum ? sum->ops(*ctx.operands) : nullptr;
        if (!sum || sum->op != MicroInstrOpcode::LoadAddrAmcRegMem || !summed ||
            !summed[0].reg.isInt() || !summed[1].reg.isInt() || !summed[2].reg.isInt() ||
            summed[3].opBits != bits || summed[4].opBits != MicroOpBits::B64 ||
            summed[5].hasWideImmediateValue() || summed[5].valueU64 != 1 ||
            summed[6].hasWideImmediateValue() || summed[6].valueU64 != 0)
            return false;
        const MicroReg result = summed[0].reg;

        const MicroInstrRef differenceRef = ctx.nextRef(sumRef);
        const MicroInstr*   difference    = ctx.instruction(differenceRef);
        const auto*         sub           = difference ? difference->ops(*ctx.operands) : nullptr;
        if (!difference || difference->op != MicroInstrOpcode::OpBinaryRegReg || !sub ||
            !sub[0].reg.isInt() || !sub[1].reg.isInt() || sub[2].opBits != bits || sub[3].microOp != MicroOp::Subtract ||
            !((summed[1].reg == sub[0].reg && summed[2].reg == sub[1].reg) ||
              (summed[1].reg == sub[1].reg && summed[2].reg == sub[0].reg)))
            return false;
        const MicroReg left  = sub[0].reg;
        const MicroReg right = sub[1].reg;
        if (result == left || result == right || result == flag || left == flag || right == flag ||
            ctx.isPrivateFrameBase(result) || ctx.isPrivateFrameBase(left) || ctx.isPrivateFrameBase(right))
            return false;

        const MicroInstrRef compareRef = ctx.nextRef(differenceRef);
        const MicroInstr*   compare    = ctx.instruction(compareRef);
        const auto*         compared   = compare ? compare->ops(*ctx.operands) : nullptr;
        const MicroInstrRef selectRef  = ctx.nextRef(compareRef);
        const MicroInstr*   select     = ctx.instruction(selectRef);
        const auto*         selected   = select ? select->ops(*ctx.operands) : nullptr;
        if (!compare || compare->op != MicroInstrOpcode::CmpRegImm || !compared ||
            compared[0].reg != flag || compared[1].opBits != bits ||
            compared[2].hasWideImmediateValue() || compared[2].valueU64 != 0 ||
            !select || select->op != MicroInstrOpcode::LoadCondRegReg || !selected ||
            selected[0].reg != result || selected[1].reg != left ||
            selected[2].cpuCond != MicroCond::Equal || selected[3].opBits != bits ||
            !ctx.isRegDeadAfter(left, ctx.instructionIndex + 4) ||
            !ctx.isRegDeadAfter(flag, ctx.instructionIndex + 4) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, selectRef, ctx.builder))
            return false;

        MicroInstrOperand copy[3] = {};
        copy[0].reg               = result;
        copy[1].reg               = right;
        copy[2].opBits            = bits;
        MicroInstr copyProbe;
        copyProbe.op          = MicroInstrOpcode::LoadRegReg;
        copyProbe.numOperands = 3;
        MicroInstrOperand negate[3] = {};
        negate[0].reg               = result;
        negate[1].opBits            = bits;
        negate[2].microOp           = MicroOp::Negate;
        MicroInstr negateProbe;
        negateProbe.op          = MicroInstrOpcode::OpUnaryReg;
        negateProbe.numOperands = 3;
        MicroInstrOperand test[3] = {};
        test[0].reg               = flag;
        test[1].opBits            = MicroOpBits::B8;
        test[2].valueU64          = 1;
        MicroInstr testProbe;
        testProbe.op          = MicroInstrOpcode::TestRegImm;
        testProbe.numOperands = 3;
        MicroInstrOperand choose[4] = {};
        choose[0].reg               = result;
        choose[1].reg               = right;
        choose[2].cpuCond           = MicroCond::NotEqual;
        choose[3].opBits            = bits;
        MicroInstr chooseProbe;
        chooseProbe.op          = MicroInstrOpcode::LoadCondRegReg;
        chooseProbe.numOperands = 4;
        MicroInstrOperand add[4] = {};
        add[0].reg               = result;
        add[1].reg               = left;
        add[2].opBits            = bits;
        add[3].microOp           = MicroOp::Add;
        MicroInstr addProbe;
        addProbe.op          = MicroInstrOpcode::OpBinaryRegReg;
        addProbe.numOperands = 4;
        MicroConformanceIssue issue;
        if (ctx.encoder->queryConformanceIssue(issue, copyProbe, copy) ||
            ctx.encoder->queryConformanceIssue(issue, negateProbe, negate) ||
            ctx.encoder->queryConformanceIssue(issue, testProbe, test) ||
            ctx.encoder->queryConformanceIssue(issue, chooseProbe, choose) ||
            ctx.encoder->queryConformanceIssue(issue, addProbe, add) ||
            !ctx.claimAll({maskRef, sumRef, differenceRef, compareRef, selectRef}))
            return false;

        ctx.emitRewrite(maskRef, copyProbe.op, copy);
        ctx.emitRewrite(sumRef, negateProbe.op, negate);
        ctx.emitRewrite(differenceRef, testProbe.op, test);
        ctx.emitRewrite(compareRef, chooseProbe.op, choose);
        ctx.emitRewrite(selectRef, addProbe.op, add);
        return true;
    }

    namespace
    {
        // ALU ops that set ZF/SF/PF from their register result exactly as
        // `cmp result, 0` would. add/sub/and/or/xor all qualify. Multiply
        // (imul leaves SF/ZF/PF undefined on x64) and shifts (flags depend on
        // the count, undefined for count 0) are intentionally excluded.
        bool isFlagReuseSafeMicroOp(MicroOp op)
        {
            switch (op)
            {
                case MicroOp::Add:
                case MicroOp::Subtract:
                case MicroOp::And:
                case MicroOp::Or:
                case MicroOp::Xor:
                    return true;
                default:
                    return false;
            }
        }

        // Conditions whose truth depends only on ZF/SF/PF, which the reused
        // arithmetic flags reproduce identically. Carry/overflow-sensitive
        // orderings (Above/Below/Greater/Less/Overflow) are NOT reusable: a
        // `cmp r, 0` clears CF/OF whereas the producing add/sub may set them.
        bool isFlagReuseSafeCond(MicroCond cond)
        {
            switch (cond)
            {
                case MicroCond::Equal:
                case MicroCond::NotEqual:
                case MicroCond::Zero:
                case MicroCond::NotZero:
                case MicroCond::Sign:
                case MicroCond::Parity:
                case MicroCond::NotParity:
                case MicroCond::EvenParity:
                case MicroCond::NotEvenParity:
                    return true;
                default:
                    return false;
            }
        }

        bool flagConsumerCond(const MicroInstr& inst, const MicroInstrOperand* ops, MicroCond& out)
        {
            if (!ops)
                return false;

            switch (inst.op)
            {
                case MicroInstrOpcode::JumpCond:
                case MicroInstrOpcode::JumpCondImm:
                    out = ops[0].cpuCond;
                    return true;
                case MicroInstrOpcode::SetCondReg:
                    out = ops[1].cpuCond;
                    return true;
                case MicroInstrOpcode::LoadCondRegReg:
                    out = ops[2].cpuCond;
                    return true;
                default:
                    return false;
            }
        }

        // If `inst` produces its register result together with reusable
        // ZF/SF/PF flags, report the destination register and the width those
        // flags were computed at.
        bool flagSettingResultDef(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg& outReg, MicroOpBits& outBits)
        {
            if (!ops)
                return false;

            switch (inst.op)
            {
                case MicroInstrOpcode::OpBinaryRegImm:
                    // [dst, opBits, microOp, imm]
                    if (!isFlagReuseSafeMicroOp(ops[2].microOp))
                        return false;
                    outReg  = ops[0].reg;
                    outBits = ops[1].opBits;
                    return true;

                case MicroInstrOpcode::OpBinaryRegReg:
                    // [dst, rhs, opBits, microOp]
                    if (!isFlagReuseSafeMicroOp(ops[3].microOp))
                        return false;
                    outReg  = ops[0].reg;
                    outBits = ops[2].opBits;
                    return true;

                default:
                    return false;
            }
        }

        // Nearest preceding instruction that actually does something. Only
        // no-effect fillers (nop, redundant self-copy) are skipped; those
        // touch neither registers nor CPU flags, so skipping them preserves
        // the "nothing happened between producer and compare" invariant.
        const MicroInstr* previousMeaningfulInstr(const Context& ctx, MicroInstrRef fromRef, MicroInstrRef& outRef)
        {
            for (MicroInstrRef cur = ctx.previousRef(fromRef); cur.isValid(); cur = ctx.previousRef(cur))
            {
                const MicroInstr* inst = ctx.instruction(cur);
                if (!inst)
                    return nullptr;
                if (isTriviallyErasableNoEffect(*inst, inst->ops(*ctx.operands)))
                    continue;
                outRef = cur;
                return inst;
            }
            return nullptr;
        }
    }

    // Drop a `cmp reg, 0` when the immediately preceding ALU instruction
    // already produced `reg` and left ZF/SF/PF describing it. The branch /
    // setcc consumers read the arithmetic flags directly:
    //
    //     sub  reg, x          sub  reg, x
    //     cmp  reg, 0    ->     (erased)
    //     je   .L              je   .L      ; tests ZF set by sub
    //
    // Only fires when every flag consumer uses a ZF/SF/PF-only condition.
    bool tryReuseFlagsForCompare(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst)
    {
        if (cmpInst.op != MicroInstrOpcode::CmpRegImm || ctx.isClaimed(cmpRef))
            return false;

        const MicroInstrOperand* cmpOps = cmpInst.ops(*ctx.operands);
        if (!cmpOps)
            return false;
        if (cmpOps[2].hasWideImmediateValue() || cmpOps[2].valueU64 != 0)
            return false;

        const MicroReg    cmpReg  = cmpOps[0].reg;
        const MicroOpBits cmpBits = cmpOps[1].opBits;
        if (!cmpReg.isAnyInt())
            return false;

        MicroInstrRef     prevRef = MicroInstrRef::invalid();
        const MicroInstr* prev    = previousMeaningfulInstr(ctx, cmpRef, prevRef);
        if (!prev)
            return false;

        MicroReg    prodReg;
        MicroOpBits prodBits;
        if (!flagSettingResultDef(*prev, prev->ops(*ctx.operands), prodReg, prodBits))
            return false;
        if (prodReg != cmpReg || prodBits != cmpBits)
            return false;

        // Validate every consumer that observes our flags before they are
        // overwritten. Anything that uses an unsafe condition, or any flags
        // user we don't recognize, aborts the rewrite.
        for (MicroInstrRef scanRef = ctx.nextRef(cmpRef); scanRef.isValid(); scanRef = ctx.nextRef(scanRef))
        {
            const MicroInstr* scanInst = ctx.instruction(scanRef);
            if (!scanInst)
                return false;

            const MicroInstrOperand* scanOps = scanInst->ops(*ctx.operands);
            if (isTriviallyErasableNoEffect(*scanInst, scanOps))
                continue;

            if (instructionActuallyUsesCpuFlags(*scanInst, scanOps))
            {
                MicroCond cond;
                if (!flagConsumerCond(*scanInst, scanOps, cond))
                    return false;
                if (!isFlagReuseSafeCond(cond))
                    return false;
            }

            const MicroInstrDef& info = MicroInstr::info(scanInst->op);
            if (info.flags.has(MicroInstrFlagsE::JumpInstruction))
            {
                if (!ctx.builder || !MicroPassHelpers::areCpuFlagsDeadAfterInCfg(*ctx.builder, scanRef))
                    return false;
                break;
            }
            if (MicroPassHelpers::instructionOverwritesCpuFlags(*scanInst, scanOps) ||
                info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
                break;
        }

        // The producer is claimed with the compare: a rule of the same sweep
        // that rewrites it into a flag-free form (`mov r, a; add r, b` into a
        // `lea`, relying on this very compare to redefine the flags) would
        // leave the consumers reading nothing.
        if (!ctx.claimAll({cmpRef, prevRef}))
            return false;

        ctx.emitErase(cmpRef);
        return true;
    }

    // (a == 0) * (b == 0) is (a | b) == 0. At this late stage the first
    // source may be destroyed only when physical liveness proves that it is
    // dead after the original product.
    bool tryFoldZeroBooleanProduct(Context& ctx, MicroInstrRef multiplyRef, const MicroInstr& multiplyInst)
    {
        if (ctx.isClaimed(multiplyRef) || multiplyInst.op != MicroInstrOpcode::OpBinaryRegReg)
            return false;
        const auto* product = multiplyInst.ops(*ctx.operands);
        if (!product || product[3].microOp != MicroOp::MultiplySigned)
            return false;

        const MicroInstrRef extSecondRef = ctx.previousRef(multiplyRef);
        const MicroInstr*   extSecond    = ctx.instruction(extSecondRef);
        const MicroInstrRef extFirstRef  = ctx.previousRef(extSecondRef);
        const MicroInstr*   extFirst     = ctx.instruction(extFirstRef);
        const MicroInstrRef setSecondRef = ctx.previousRef(extFirstRef);
        const MicroInstr*   setSecond    = ctx.instruction(setSecondRef);
        const MicroInstrRef cmpSecondRef = ctx.previousRef(setSecondRef);
        const MicroInstr*   cmpSecond    = ctx.instruction(cmpSecondRef);
        const MicroInstrRef setFirstRef  = ctx.previousRef(cmpSecondRef);
        const MicroInstr*   setFirst     = ctx.instruction(setFirstRef);
        const MicroInstrRef cmpFirstRef  = ctx.previousRef(setFirstRef);
        const MicroInstr*   cmpFirst     = ctx.instruction(cmpFirstRef);
        if (!cmpFirst || !setFirst || !cmpSecond || !setSecond || !extFirst || !extSecond ||
            cmpFirst->op != MicroInstrOpcode::CmpRegImm || setFirst->op != MicroInstrOpcode::SetCondReg ||
            cmpSecond->op != MicroInstrOpcode::CmpRegImm ||
            setSecond->op != MicroInstrOpcode::SetCondReg ||
            extFirst->op != MicroInstrOpcode::LoadZeroExtRegReg || extSecond->op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;

        const auto* firstCmp  = cmpFirst->ops(*ctx.operands);
        const auto* firstSet  = setFirst->ops(*ctx.operands);
        const auto* secondCmp = cmpSecond->ops(*ctx.operands);
        const auto* secondSet = setSecond->ops(*ctx.operands);
        const auto* firstExt  = extFirst->ops(*ctx.operands);
        const auto* secondExt = extSecond->ops(*ctx.operands);
        if (!firstCmp || !firstSet || !secondCmp || !secondSet || !firstExt || !secondExt ||
            !firstCmp[0].reg.isInt() || !secondCmp[0].reg.isInt() || secondCmp[0].reg == firstCmp[0].reg ||
            firstCmp[2].hasWideImmediateValue() || firstCmp[2].valueU64 != 0 ||
            (firstCmp[1].opBits != MicroOpBits::B32 && firstCmp[1].opBits != MicroOpBits::B64) ||
            secondCmp[2].hasWideImmediateValue() || secondCmp[2].valueU64 != 0 || secondCmp[1].opBits != firstCmp[1].opBits ||
            firstSet[0].reg != firstExt[0].reg || firstExt[0].reg != firstExt[1].reg ||
            secondSet[0].reg != secondExt[0].reg || secondExt[0].reg != secondExt[1].reg ||
            (firstSet[1].cpuCond != MicroCond::Equal && firstSet[1].cpuCond != MicroCond::Zero) ||
            (secondSet[1].cpuCond != MicroCond::Equal && secondSet[1].cpuCond != MicroCond::Zero) ||
            firstExt[3].opBits != MicroOpBits::B8 || secondExt[3].opBits != MicroOpBits::B8 ||
            firstExt[2].opBits != secondExt[2].opBits ||
            (firstExt[2].opBits != MicroOpBits::B32 && firstExt[2].opBits != MicroOpBits::B64) ||
            product[0].reg != firstExt[0].reg || product[1].reg != secondExt[0].reg ||
            product[2].opBits != firstExt[2].opBits ||
            firstExt[0].reg == firstCmp[0].reg || firstExt[0].reg == secondCmp[0].reg ||
            !ctx.isRegDeadAfterCurrent(firstCmp[0].reg) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, multiplyRef, ctx.builder) ||
            !ctx.claimAll({cmpFirstRef, setFirstRef, cmpSecondRef, setSecondRef, extFirstRef, extSecondRef, multiplyRef}))
            return false;

        MicroInstrOperand clear[2] = {};
        clear[0].reg               = firstExt[0].reg;
        clear[1].opBits            = MicroOpBits::B32;
        MicroInstrOperand either[4] = {};
        either[0].reg               = firstCmp[0].reg;
        either[1].reg               = secondCmp[0].reg;
        either[2].opBits            = firstCmp[1].opBits;
        either[3].microOp           = MicroOp::Or;
        MicroInstrOperand set[2] = {};
        set[0].reg               = firstExt[0].reg;
        set[1].cpuCond           = MicroCond::Equal;
        ctx.emitRewrite(cmpFirstRef, MicroInstrOpcode::ClearReg, clear);
        ctx.emitRewrite(setFirstRef, MicroInstrOpcode::OpBinaryRegReg, either, true);
        ctx.emitRewrite(cmpSecondRef, MicroInstrOpcode::SetCondReg, set);
        ctx.emitErase(setSecondRef);
        ctx.emitErase(extFirstRef);
        ctx.emitErase(extSecondRef);
        ctx.emitErase(multiplyRef);
        return true;
    }

    namespace
    {
        struct CarryBoolean
        {
            MicroInstrRef clearRef;
            MicroInstrRef compareRef;
            MicroInstrRef setRef;
            MicroReg      reg;
            bool          inverse = false;
        };

        // A cleared register followed by SETB or SETAE contains CF or its inverse.
        // Keep the flag producer explicit so another queued rewrite cannot move it.
        bool findCarryBoolean(const Context& ctx, MicroInstrRef ref, CarryBoolean& out)
        {
            if (!ctx.encoder || !ctx.encoder->supportsCarryArithmetic())
                return false;
            out.setRef            = ctx.previousRef(ref);
            const MicroInstr* set = ctx.instruction(out.setRef);
            if (!set || set->op != MicroInstrOpcode::SetCondReg)
                return false;
            const auto* setOps = set->ops(*ctx.operands);
            if (!setOps || !setOps[0].reg.isInt() || (setOps[1].cpuCond != MicroCond::Below && setOps[1].cpuCond != MicroCond::AboveOrEqual))
                return false;
            out.reg     = setOps[0].reg;
            out.inverse = setOps[1].cpuCond == MicroCond::AboveOrEqual;
            if (ctx.isPrivateFrameBase(out.reg))
                return false;
            out.compareRef            = ctx.previousRef(out.setRef);
            const MicroInstr* compare = ctx.instruction(out.compareRef);
            if (!compare || (compare->op != MicroInstrOpcode::CmpRegReg && compare->op != MicroInstrOpcode::CmpRegImm))
                return false;
            const auto* compareOps = compare->ops(*ctx.operands);
            if (!compareOps || !compareOps[0].reg.isInt() ||
                (compare->op == MicroInstrOpcode::CmpRegReg && !compareOps[1].reg.isInt()))
                return false;
            out.clearRef            = ctx.previousRef(out.compareRef);
            const MicroInstr* clear = ctx.instruction(out.clearRef);
            if (!clear || clear->op != MicroInstrOpcode::ClearReg)
                return false;
            const auto* clearOps = clear->ops(*ctx.operands);
            return clearOps && clearOps[0].reg == out.reg &&
                   (clearOps[1].opBits == MicroOpBits::B32 || clearOps[1].opBits == MicroOpBits::B64);
        }

        bool findZeroBoolean(const Context& ctx, MicroInstrRef ref, CarryBoolean& out)
        {
            if (!ctx.encoder || !ctx.encoder->supportsCarryArithmetic())
                return false;
            out.setRef            = ctx.previousRef(ref);
            const MicroInstr* set = ctx.instruction(out.setRef);
            if (!set || set->op != MicroInstrOpcode::SetCondReg)
                return false;
            const auto* setOps = set->ops(*ctx.operands);
            if (!setOps || !setOps[0].reg.isInt() ||
                (setOps[1].cpuCond != MicroCond::Equal && setOps[1].cpuCond != MicroCond::Zero))
                return false;
            out.reg     = setOps[0].reg;
            out.inverse = false;
            if (ctx.isPrivateFrameBase(out.reg))
                return false;

            out.compareRef            = ctx.previousRef(out.setRef);
            const MicroInstr* compare = ctx.instruction(out.compareRef);
            if (!compare || compare->op != MicroInstrOpcode::CmpRegImm)
                return false;
            const auto* compareOps = compare->ops(*ctx.operands);
            if (!compareOps || !compareOps[0].reg.isInt() || compareOps[0].reg == out.reg ||
                compareOps[2].hasWideImmediateValue() || compareOps[2].valueU64 != 0)
                return false;

            out.clearRef            = ctx.previousRef(out.compareRef);
            const MicroInstr* clear = ctx.instruction(out.clearRef);
            if (!clear || clear->op != MicroInstrOpcode::ClearReg)
                return false;
            const auto* clearOps = clear->ops(*ctx.operands);
            return clearOps && clearOps[0].reg == out.reg &&
                   (clearOps[1].opBits == MicroOpBits::B32 || clearOps[1].opBits == MicroOpBits::B64);
        }

        bool claimCarryBoolean(Context& ctx, MicroInstrRef ref, const CarryBoolean& value)
        {
            return MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) &&
                   ctx.claimAll({value.clearRef, value.compareRef, value.setRef, ref});
        }
    }

    // SBB computes the same all-zero/all-one mask while consuming CF directly.
    // Its use/def destination keeps the preceding clear to break the dependency.
    bool tryFoldCarryMask(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* ops = inst.ops(*ctx.operands);
        if (!ops || ops[2].microOp != MicroOp::Negate ||
            (ops[1].opBits != MicroOpBits::B32 && ops[1].opBits != MicroOpBits::B64))
            return false;
        CarryBoolean value;
        if (!findCarryBoolean(ctx, ref, value) || value.inverse || value.reg != ops[0].reg || !claimCarryBoolean(ctx, ref, value))
            return false;
        const MicroInstrOperand subtract[3] = {ops[0], ops[0], ops[1]};
        ctx.emitRewrite(value.setRef, MicroInstrOpcode::SubtractBorrowRegReg, subtract, true);
        ctx.emitErase(ref);
        return true;
    }

    // Zero/nonzero masks can consume CF directly. For nonzero, NEG establishes
    // CF while destroying a source only when that physical value is dead.
    bool tryFoldZeroComparisonMask(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* ops = inst.ops(*ctx.operands);
        if (ctx.isClaimed(ref) || !ctx.encoder || !ctx.encoder->supportsCarryArithmetic() || !ops ||
            ops[2].microOp != MicroOp::Negate || !ops[0].reg.isInt() || ctx.isPrivateFrameBase(ops[0].reg) ||
            (ops[1].opBits != MicroOpBits::B32 && ops[1].opBits != MicroOpBits::B64))
            return false;
        const MicroInstrRef setRef = ctx.previousRef(ref);
        const MicroInstr*   set    = ctx.instruction(setRef);
        if (!set || set->op != MicroInstrOpcode::SetCondReg)
            return false;
        const auto* setOps = set->ops(*ctx.operands);
        if (!setOps || setOps[0].reg != ops[0].reg ||
            (setOps[1].cpuCond != MicroCond::Equal && setOps[1].cpuCond != MicroCond::NotEqual))
            return false;
        const MicroInstrRef compareRef = ctx.previousRef(setRef);
        const MicroInstr*   compare    = ctx.instruction(compareRef);
        if (!compare || compare->op != MicroInstrOpcode::CmpRegImm)
            return false;
        const auto* cmp = compare->ops(*ctx.operands);
        if (!cmp || !cmp[0].reg.isInt() || cmp[0].reg == ops[0].reg || ctx.isPrivateFrameBase(cmp[0].reg) ||
            cmp[2].hasWideImmediateValue() || cmp[2].valueU64 != 0)
            return false;
        const bool nonzero = setOps[1].cpuCond == MicroCond::NotEqual;
        if (nonzero && !ctx.isRegDeadAfterCurrent(cmp[0].reg))
            return false;
        const MicroInstrRef clearRef = ctx.previousRef(compareRef);
        const MicroInstr*   clear    = ctx.instruction(clearRef);
        if (!clear || clear->op != MicroInstrOpcode::ClearReg)
            return false;
        const auto* cleared = clear->ops(*ctx.operands);
        if (!cleared || cleared[0].reg != ops[0].reg ||
            (cleared[1].opBits != MicroOpBits::B32 && cleared[1].opBits != MicroOpBits::B64) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
            !ctx.claimAll({clearRef, compareRef, setRef, ref}))
            return false;
        MicroInstrOperand producer[3];
        producer[0] = cmp[0];
        producer[1] = cmp[1];
        if (nonzero)
        {
            producer[2].microOp = MicroOp::Negate;
            ctx.emitRewrite(compareRef, MicroInstrOpcode::OpUnaryReg, producer);
        }
        else
        {
            producer[2].valueU64 = 1;
            ctx.emitRewrite(compareRef, MicroInstrOpcode::CmpRegImm, producer);
        }
        const MicroInstrOperand subtract[3] = {ops[0], ops[0], ops[1]};
        ctx.emitRewrite(setRef, MicroInstrOpcode::SubtractBorrowRegReg, subtract, true);
        ctx.emitErase(ref);
        return true;
    }

    bool tryFoldCarryArithmetic(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* ops = inst.ops(*ctx.operands);
        if (!ops || (ops[3].microOp != MicroOp::Add && ops[3].microOp != MicroOp::Subtract) || !ops[0].reg.isInt() || !ops[1].reg.isInt() ||
            ops[0].reg == ops[1].reg || ctx.isPrivateFrameBase(ops[0].reg) ||
            (ops[2].opBits != MicroOpBits::B32 && ops[2].opBits != MicroOpBits::B64))
            return false;
        const bool   subtract = ops[3].microOp == MicroOp::Subtract;
        CarryBoolean value;
        if (!findCarryBoolean(ctx, ref, value) || (value.reg != ops[0].reg && value.reg != ops[1].reg))
            return false;
        if (subtract && value.reg != ops[1].reg)
            return false;
        if (value.reg != ops[0].reg && !ctx.isRegDeadAfterCurrent(value.reg))
            return false;
        if (!claimCarryBoolean(ctx, ref, value))
            return false;
        if (value.reg == ops[0].reg)
        {
            const MicroInstrOperand copy[3] = {ops[0], ops[1], ops[2]};
            ctx.emitRewrite(value.setRef, MicroInstrOpcode::LoadRegReg, copy, true);
        }
        else
            ctx.emitErase(value.setRef);
        MicroInstrOperand add[3] = {};
        add[0].reg               = ops[0].reg;
        add[1].opBits            = ops[2].opBits;
        add[2].valueU64          = value.inverse ? getBitsMask(ops[2].opBits) : 0;
        const auto opcode        = subtract != value.inverse ? MicroInstrOpcode::SubtractBorrowRegImm : MicroInstrOpcode::AddCarryRegImm;
        ctx.emitRewrite(ref, opcode, add);
        // The copy or existing addend supplies every result bit now. Retain
        // the old clear only if the comparison itself reads that zero value.
        const MicroInstr*      compare       = ctx.instruction(value.compareRef);
        const MicroInstrUseDef compareUseDef = compare->collectUseDef(*ctx.operands, ctx.encoder);
        if (!microRegSpanContains(compareUseDef.uses.span(), value.reg))
            ctx.emitErase(value.clearRef);
        return true;
    }

    // Sum two unsigned comparisons without widening both byte booleans. The
    // second SETB is the carry flag itself, so ADC can consume it directly.
    bool tryFoldCarryComparisonSum(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.encoder || !ctx.encoder->supportsCarryArithmetic())
            return false;
        const auto* add = inst.ops(*ctx.operands);
        if (!add || add[3].microOp != MicroOp::Add || !add[0].reg.isInt() || !add[1].reg.isInt() ||
            add[0].reg == add[1].reg || ctx.isPrivateFrameBase(add[0].reg) ||
            (add[2].opBits != MicroOpBits::B32 && add[2].opBits != MicroOpBits::B64) ||
            !ctx.isRegDeadAfterCurrent(add[1].reg))
            return false;

        const MicroInstrRef extSecondRef = ctx.previousRef(ref);
        const MicroInstr*   extSecond    = ctx.instruction(extSecondRef);
        const MicroInstrRef extFirstRef  = ctx.previousRef(extSecondRef);
        const MicroInstr*   extFirst     = ctx.instruction(extFirstRef);
        const MicroInstrRef setSecondRef = ctx.previousRef(extFirstRef);
        const MicroInstr*   setSecond    = ctx.instruction(setSecondRef);
        const MicroInstrRef cmpSecondRef = ctx.previousRef(setSecondRef);
        const MicroInstr*   cmpSecond    = ctx.instruction(cmpSecondRef);
        const MicroInstrRef setFirstRef  = ctx.previousRef(cmpSecondRef);
        const MicroInstr*   setFirst     = ctx.instruction(setFirstRef);
        const MicroInstrRef cmpFirstRef  = ctx.previousRef(setFirstRef);
        const MicroInstr*   cmpFirst     = ctx.instruction(cmpFirstRef);
        if (!extFirst || !extSecond || !setFirst || !setSecond || !cmpFirst || !cmpSecond ||
            extFirst->op != MicroInstrOpcode::LoadZeroExtRegReg || extSecond->op != MicroInstrOpcode::LoadZeroExtRegReg ||
            setFirst->op != MicroInstrOpcode::SetCondReg || setSecond->op != MicroInstrOpcode::SetCondReg ||
            cmpFirst->op != MicroInstrOpcode::CmpRegReg || cmpSecond->op != MicroInstrOpcode::CmpRegReg)
            return false;

        const auto* firstExt  = extFirst->ops(*ctx.operands);
        const auto* secondExt = extSecond->ops(*ctx.operands);
        const auto* firstSet  = setFirst->ops(*ctx.operands);
        const auto* secondSet = setSecond->ops(*ctx.operands);
        const auto* firstCmp  = cmpFirst->ops(*ctx.operands);
        const auto* secondCmp = cmpSecond->ops(*ctx.operands);
        if (!firstExt || !secondExt || !firstSet || !secondSet || !firstCmp || !secondCmp ||
            firstExt[0].reg != add[0].reg || firstExt[1].reg != add[0].reg ||
            secondExt[0].reg != add[1].reg || secondExt[1].reg != add[1].reg ||
            firstExt[2].opBits != add[2].opBits || secondExt[2].opBits != add[2].opBits ||
            firstExt[3].opBits != MicroOpBits::B8 || secondExt[3].opBits != MicroOpBits::B8 ||
            firstSet[0].reg != add[0].reg || secondSet[0].reg != add[1].reg ||
            firstSet[1].cpuCond != MicroCond::Below || secondSet[1].cpuCond != MicroCond::Below ||
            firstCmp[2].opBits != add[2].opBits || secondCmp[2].opBits != add[2].opBits ||
            !firstCmp[0].reg.isInt() || !firstCmp[1].reg.isInt() ||
            !secondCmp[0].reg.isInt() || !secondCmp[1].reg.isInt() ||
            firstCmp[0].reg == add[0].reg || firstCmp[1].reg == add[0].reg ||
            secondCmp[0].reg == add[0].reg || secondCmp[1].reg == add[0].reg ||
            !ctx.claimAll({cmpFirstRef, setFirstRef, cmpSecondRef, setSecondRef, extFirstRef, extSecondRef, ref}))
            return false;

        MicroInstrOperand clear[2] = {};
        clear[0].reg               = add[0].reg;
        clear[1].opBits            = MicroOpBits::B32;
        MicroInstrOperand addCarry[3] = {};
        addCarry[0].reg               = add[0].reg;
        addCarry[1].opBits            = add[2].opBits;
        addCarry[2].valueU64          = 0;
        ctx.emitRewrite(cmpFirstRef, MicroInstrOpcode::ClearReg, clear);
        ctx.emitRewrite(setFirstRef, cmpFirst->op, std::span{firstCmp, cmpFirst->numOperands}, true);
        ctx.emitRewrite(cmpSecondRef, setFirst->op, std::span{firstSet, setFirst->numOperands});
        ctx.emitRewrite(setSecondRef, cmpSecond->op, std::span{secondCmp, cmpSecond->numOperands}, true);
        ctx.emitRewrite(extFirstRef, MicroInstrOpcode::AddCarryRegImm, addCarry);
        ctx.emitErase(extSecondRef);
        ctx.emitErase(ref);
        return true;
    }

    // Two zero/nonzero comparisons can share one full-width boolean destination.
    // Comparing unsigned x with one exposes x == 0 as carry; SBB by -1 exposes
    // its inverse. Reusing the existing instruction slots also moves the clear
    // before the first SETcc, so neither byte result needs a MOVZX.
    bool tryFoldZeroTestBooleanSum(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || !ctx.encoder || !ctx.encoder->supportsCarryArithmetic())
            return false;
        const auto* add = inst.ops(*ctx.operands);
        if (!add || add[3].microOp != MicroOp::Add || !add[0].reg.isInt() || !add[1].reg.isInt() ||
            add[0].reg == add[1].reg || ctx.isPrivateFrameBase(add[0].reg) ||
            (add[2].opBits != MicroOpBits::B32 && add[2].opBits != MicroOpBits::B64) ||
            !ctx.isRegDeadAfterCurrent(add[1].reg))
            return false;

        const MicroInstrRef extSecondRef = ctx.previousRef(ref);
        const MicroInstr*   extSecond    = ctx.instruction(extSecondRef);
        const MicroInstrRef extFirstRef  = ctx.previousRef(extSecondRef);
        const MicroInstr*   extFirst     = ctx.instruction(extFirstRef);
        if (!extFirst || !extSecond || extFirst->op != MicroInstrOpcode::LoadZeroExtRegReg ||
            extSecond->op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;
        const auto* firstExt  = extFirst->ops(*ctx.operands);
        const auto* secondExt = extSecond->ops(*ctx.operands);
        if (!firstExt || !secondExt ||
            firstExt[0].reg != add[0].reg || firstExt[1].reg != add[0].reg ||
            secondExt[0].reg != add[1].reg || secondExt[1].reg != add[1].reg ||
            firstExt[2].opBits != add[2].opBits || secondExt[2].opBits != add[2].opBits ||
            firstExt[3].opBits != MicroOpBits::B8 || secondExt[3].opBits != MicroOpBits::B8)
            return false;

        const MicroInstrRef setSecondRef = ctx.previousRef(extFirstRef);
        const MicroInstr*   setSecond    = ctx.instruction(setSecondRef);
        const MicroInstrRef cmpSecondRef = ctx.previousRef(setSecondRef);
        const MicroInstr*   cmpSecond    = ctx.instruction(cmpSecondRef);
        const MicroInstrRef setFirstRef  = ctx.previousRef(cmpSecondRef);
        const MicroInstr*   setFirst     = ctx.instruction(setFirstRef);
        const MicroInstrRef cmpFirstRef  = ctx.previousRef(setFirstRef);
        const MicroInstr*   cmpFirst     = ctx.instruction(cmpFirstRef);
        if (!setFirst || !setSecond || !cmpFirst || !cmpSecond ||
            setFirst->op != MicroInstrOpcode::SetCondReg || setSecond->op != MicroInstrOpcode::SetCondReg ||
            cmpFirst->op != MicroInstrOpcode::CmpRegImm || cmpSecond->op != MicroInstrOpcode::CmpRegImm)
            return false;
        const auto* firstSet  = setFirst->ops(*ctx.operands);
        const auto* secondSet = setSecond->ops(*ctx.operands);
        const auto* firstCmp  = cmpFirst->ops(*ctx.operands);
        const auto* secondCmp = cmpSecond->ops(*ctx.operands);
        const bool  firstZero    = firstSet && (firstSet[1].cpuCond == MicroCond::Equal || firstSet[1].cpuCond == MicroCond::Zero);
        const bool  firstNonzero = firstSet && (firstSet[1].cpuCond == MicroCond::NotEqual || firstSet[1].cpuCond == MicroCond::NotZero);
        const bool  secondZero   = secondSet && (secondSet[1].cpuCond == MicroCond::Equal || secondSet[1].cpuCond == MicroCond::Zero);
        const bool  secondNonzero = secondSet && (secondSet[1].cpuCond == MicroCond::NotEqual || secondSet[1].cpuCond == MicroCond::NotZero);
        if (!firstSet || !secondSet || !firstCmp || !secondCmp ||
            firstSet[0].reg != add[0].reg || secondSet[0].reg != add[1].reg ||
            (!firstZero && !firstNonzero) || (!secondZero && !secondNonzero) ||
            !firstCmp[0].reg.isInt() || !secondCmp[0].reg.isInt() ||
            firstCmp[0].reg == add[0].reg || secondCmp[0].reg == add[0].reg ||
            firstCmp[2].hasWideImmediateValue() || secondCmp[2].hasWideImmediateValue() ||
            firstCmp[2].valueU64 != 0 || secondCmp[2].valueU64 != 0 ||
            (secondNonzero && !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder)) ||
            !ctx.claimAll({cmpFirstRef, setFirstRef, cmpSecondRef, setSecondRef, extFirstRef, extSecondRef, ref}))
            return false;

        MicroInstrOperand clear[2] = {};
        clear[0].reg               = add[0].reg;
        clear[1].opBits            = MicroOpBits::B32;
        MicroInstrOperand compareFirst[3] = {firstCmp[0], firstCmp[1], firstCmp[2]};
        MicroInstrOperand set[2]          = {firstSet[0], firstSet[1]};
        MicroInstrOperand compareSecond[3] = {secondCmp[0], secondCmp[1], secondCmp[2]};
        compareSecond[2].valueU64          = 1;
        MicroInstrOperand addCarry[3] = {};
        addCarry[0].reg               = add[0].reg;
        addCarry[1].opBits            = add[2].opBits;
        addCarry[2].valueU64          = secondNonzero ? getBitsMask(add[2].opBits) : 0;
        ctx.emitRewrite(cmpFirstRef, MicroInstrOpcode::ClearReg, clear);
        ctx.emitRewrite(setFirstRef, MicroInstrOpcode::CmpRegImm, compareFirst, true);
        ctx.emitRewrite(cmpSecondRef, MicroInstrOpcode::SetCondReg, set);
        ctx.emitRewrite(setSecondRef, MicroInstrOpcode::CmpRegImm, compareSecond, true);
        ctx.emitRewrite(extFirstRef, secondNonzero ? MicroInstrOpcode::SubtractBorrowRegImm : MicroInstrOpcode::AddCarryRegImm, addCarry);
        ctx.emitErase(extSecondRef);
        ctx.emitErase(ref);
        return true;
    }

    // Compute a bitwise operation before widening two byte values. The final
    // flags differ for arbitrary values because B8 and B32/B64 have different
    // sign bits, so only fold when those flags are dead.
    bool tryNarrowBitwiseZeroExtensions(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || inst.op != MicroInstrOpcode::OpBinaryRegReg)
            return false;
        const auto* binary = inst.ops(*ctx.operands);
        if (!binary || (binary[3].microOp != MicroOp::And && binary[3].microOp != MicroOp::Or && binary[3].microOp != MicroOp::Xor) ||
            (binary[2].opBits != MicroOpBits::B32 && binary[2].opBits != MicroOpBits::B64))
            return false;

        const MicroInstrRef extSecondRef = ctx.previousRef(ref);
        const MicroInstr*   extSecond    = ctx.instruction(extSecondRef);
        const MicroInstrRef extFirstRef  = ctx.previousRef(extSecondRef);
        const MicroInstr*   extFirst     = ctx.instruction(extFirstRef);
        if (!extFirst || !extSecond || extFirst->op != MicroInstrOpcode::LoadZeroExtRegReg ||
            extSecond->op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;
        const auto* first  = extFirst->ops(*ctx.operands);
        const auto* second = extSecond->ops(*ctx.operands);
        if (!first || !second || first[0].reg != binary[0].reg || second[0].reg != binary[1].reg ||
            first[0].reg != first[1].reg || second[0].reg != second[1].reg || first[0].reg == second[0].reg ||
            first[2].opBits != binary[2].opBits || second[2].opBits != binary[2].opBits ||
            first[3].opBits != MicroOpBits::B8 || second[3].opBits != MicroOpBits::B8 ||
            !ctx.isRegDeadAfterCurrent(second[0].reg) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
            !ctx.claimAll({extFirstRef, extSecondRef, ref}))
            return false;

        MicroInstrOperand narrow[4] = {};
        narrow[0].reg               = second[0].reg;
        narrow[1].reg               = first[0].reg;
        narrow[2].opBits            = MicroOpBits::B8;
        narrow[3].microOp           = binary[3].microOp;
        MicroInstrOperand extend[4] = {};
        extend[0].reg               = first[0].reg;
        extend[1].reg               = second[0].reg;
        extend[2].opBits            = binary[2].opBits;
        extend[3].opBits            = MicroOpBits::B8;
        ctx.emitRewrite(extFirstRef, MicroInstrOpcode::OpBinaryRegReg, narrow);
        ctx.emitRewrite(extSecondRef, MicroInstrOpcode::LoadZeroExtRegReg, extend);
        ctx.emitErase(ref);
        return true;
    }

    bool tryFoldCarryOffset(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* ops = inst.ops(*ctx.operands);
        if (!ops)
            return false;
        MicroOpBits bits;
        if (inst.op == MicroInstrOpcode::LoadAddrRegMem)
        {
            if (ops[0].reg != ops[1].reg)
                return false;
            bits = ops[2].opBits;
        }
        else
        {
            if (ops[2].microOp != MicroOp::Add || ops[3].hasWideImmediateValue())
                return false;
            bits = ops[1].opBits;
        }
        if (bits != MicroOpBits::B32 && bits != MicroOpBits::B64)
            return false;
        const uint64_t offset       = ops[3].valueU64;
        const uint64_t signedOffset = static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(offset)));
        if ((signedOffset & getBitsMask(bits)) != (offset & getBitsMask(bits)))
            return false;
        CarryBoolean value;
        if (!findCarryBoolean(ctx, ref, value))
        {
            if (!findZeroBoolean(ctx, ref, value) || value.reg != ops[0].reg || !claimCarryBoolean(ctx, ref, value))
                return false;
            const MicroInstr* compare = ctx.instruction(value.compareRef);
            const auto*       cmpOps  = compare->ops(*ctx.operands);
            MicroInstrOperand compareOne[3] = {cmpOps[0], cmpOps[1], cmpOps[2]};
            compareOne[2].valueU64           = 1;
            MicroInstrOperand add[3]         = {};
            add[0].reg                       = ops[0].reg;
            add[1].opBits                    = bits;
            add[2].valueU64                  = signedOffset & getBitsMask(bits);
            ctx.emitRewrite(value.compareRef, compare->op, compareOne, true);
            ctx.emitRewrite(value.setRef, MicroInstrOpcode::AddCarryRegImm, add);
            ctx.emitErase(ref);
            return true;
        }
        if (value.reg != ops[0].reg)
            return false;
        // The cleared boolean plus CF is ADC by the offset; plus the inverse
        // of CF it is offset + 1 - CF, which SBB by the negated successor
        // leaves in the cleared register.
        uint64_t immediate = signedOffset;
        if (value.inverse)
        {
            const int64_t successor = static_cast<int64_t>(signedOffset) + 1;
            if (successor > INT32_MAX)
                return false;
            immediate = static_cast<uint64_t>(-successor);
        }
        if (!claimCarryBoolean(ctx, ref, value))
            return false;
        MicroInstrOperand add[3] = {};
        add[0].reg               = ops[0].reg;
        add[1].opBits            = bits;
        add[2].valueU64          = immediate & getBitsMask(bits);
        ctx.emitRewrite(ref, value.inverse ? MicroInstrOpcode::SubtractBorrowRegImm : MicroInstrOpcode::AddCarryRegImm, add);
        ctx.emitErase(value.setRef);
        return true;
    }

    // Two constants one apart, selected on the carry, are the carry added to
    // or subtracted from one of them, as LLVM's x86 lowering turns
    // `c < 0xF0 ? 3 : 4` into `mov eax, 4; sbb eax, 0`:
    //
    //     mov R, K                           mov R, K
    //     mov T, K - 1              ->       sbb R, 0
    //     cmovb R, T
    //
    // Moves leave the flags alone, so the carry the select reads is the one
    // SBB or ADC reads. The load of T goes once T dies at the select.
    bool tryFoldCarrySelectOfConstants(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        constexpr uint32_t K_MAX_WINDOW = 4;

        if (ctx.isClaimed(ref) || !ctx.encoder || !ctx.encoder->supportsCarryArithmetic())
            return false;
        const auto* select = inst.ops(*ctx.operands);
        if (!select || !select[0].reg.isInt() || !select[1].reg.isInt() || select[0].reg == select[1].reg ||
            ctx.isPrivateFrameBase(select[0].reg) || (select[3].opBits != MicroOpBits::B32 && select[3].opBits != MicroOpBits::B64))
            return false;
        const MicroCond cond = select[2].cpuCond;
        if (cond != MicroCond::Below && cond != MicroCond::AboveOrEqual)
            return false;
        const MicroReg    result = select[0].reg;
        const MicroReg    other  = select[1].reg;
        const MicroOpBits bits   = select[3].opBits;
        const uint64_t    mask   = getBitsMask(bits);

        // The constant loads of both registers; nothing between a load and
        // the select mentions its register.
        MicroInstrRef resultLoad = MicroInstrRef::invalid();
        MicroInstrRef otherLoad  = MicroInstrRef::invalid();
        MicroInstrRef cursor     = ctx.previousRef(ref);
        for (uint32_t step = 0; step < K_MAX_WINDOW && cursor.isValid() && (!resultLoad.isValid() || !otherLoad.isValid()); ++step)
        {
            const MicroInstr* current = ctx.instruction(cursor);
            if (!current || current->op == MicroInstrOpcode::Label)
                return false;
            const MicroInstrFlags flags = MicroInstr::info(current->op).flags;
            if (flags.has(MicroInstrFlagsE::JumpInstruction) || flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;
            const auto* currentOps = current->ops(*ctx.operands);
            const bool  isLoad     = current->op == MicroInstrOpcode::LoadRegImm && currentOps && !currentOps[2].hasWideImmediateValue() &&
                                (currentOps[1].opBits == MicroOpBits::B32 || currentOps[1].opBits == MicroOpBits::B64);
            if (isLoad && !resultLoad.isValid() && currentOps[0].reg == result)
            {
                resultLoad = cursor;
            }
            else if (isLoad && !otherLoad.isValid() && currentOps[0].reg == other)
            {
                otherLoad = cursor;
            }
            else
            {
                const MicroInstrUseDef useDef = current->collectUseDef(*ctx.operands, ctx.encoder);
                for (const MicroReg reg : {result, other})
                {
                    const bool pending = reg == result ? !resultLoad.isValid() : !otherLoad.isValid();
                    if (pending && (microRegSpanContains(useDef.uses.span(), reg) || microRegSpanContains(useDef.defs.span(), reg)))
                        return false;
                }
            }
            cursor = ctx.previousRef(cursor);
        }
        if (!resultLoad.isValid() || !otherLoad.isValid())
            return false;

        const auto*    resultOps = ctx.instruction(resultLoad)->ops(*ctx.operands);
        const auto*    otherOps  = ctx.instruction(otherLoad)->ops(*ctx.operands);
        const uint64_t kept      = resultOps[2].valueU64 & getBitsMask(resultOps[1].opBits) & mask;
        const uint64_t selected  = otherOps[2].valueU64 & getBitsMask(otherOps[1].opBits) & mask;

        // The value the register holds without carry, and whether the carry
        // subtracts from it or adds to it.
        const bool     carryKeeps = cond == MicroCond::AboveOrEqual;
        const uint64_t base       = carryKeeps ? selected : kept;
        const uint64_t onCarry    = carryKeeps ? kept : selected;
        bool           borrow     = false;
        if (onCarry == ((base - 1) & mask))
            borrow = true;
        else if (onCarry != ((base + 1) & mask))
            return false;

        if (!ctx.isRegDeadAfterCurrent(other) || !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
            !ctx.claimAll({ref, resultLoad, otherLoad}))
            return false;

        if (carryKeeps)
        {
            MicroInstrOperand baseLoad[3] = {otherOps[0], otherOps[1], otherOps[2]};
            baseLoad[0].reg               = result;
            ctx.emitRewrite(resultLoad, MicroInstrOpcode::LoadRegImm, baseLoad);
        }
        ctx.emitErase(otherLoad);
        MicroInstrOperand carry[3] = {};
        carry[0].reg               = result;
        carry[1].opBits            = bits;
        carry[2].valueU64          = 0;
        ctx.emitRewrite(ref, borrow ? MicroInstrOpcode::SubtractBorrowRegImm : MicroInstrOpcode::AddCarryRegImm, carry);
        return true;
    }

    // A SETcc result is zero or one. After a preceding clear, shifting it by
    // at most 31 bits fits in a dword, whose write still defines the same
    // zero-extended 64-bit result.
    bool tryNarrowShiftedBoolean(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || inst.op != MicroInstrOpcode::OpBinaryRegImm)
            return false;
        const auto* shift = inst.ops(*ctx.operands);
        if (!shift || !shift[0].reg.isInt() || ctx.isPrivateFrameBase(shift[0].reg) ||
            shift[1].opBits != MicroOpBits::B64 || shift[2].microOp != MicroOp::ShiftLeft ||
            shift[3].hasWideImmediateValue() || shift[3].valueU64 == 0 || shift[3].valueU64 > 31 ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder))
            return false;

        const MicroInstrRef setRef = ctx.previousRef(ref);
        const MicroInstr*   set    = ctx.instruction(setRef);
        const MicroInstrRef cmpRef = ctx.previousRef(setRef);
        const MicroInstr*   cmp    = ctx.instruction(cmpRef);
        const MicroInstrRef clearRef = ctx.previousRef(cmpRef);
        const MicroInstr*   clear    = ctx.instruction(clearRef);
        if (!set || !cmp || !clear || set->op != MicroInstrOpcode::SetCondReg ||
            clear->op != MicroInstrOpcode::ClearReg || !instructionActuallyDefinesCpuFlags(*cmp, cmp->ops(*ctx.operands)))
            return false;
        const auto* setOps   = set->ops(*ctx.operands);
        const auto* clearOps = clear->ops(*ctx.operands);
        if (!setOps || !clearOps || setOps[0].reg != shift[0].reg || clearOps[0].reg != shift[0].reg ||
            (clearOps[1].opBits != MicroOpBits::B32 && clearOps[1].opBits != MicroOpBits::B64) ||
            !ctx.claimAll({clearRef, cmpRef, setRef, ref}))
            return false;

        MicroInstrOperand narrow[4] = {shift[0], shift[1], shift[2], shift[3]};
        narrow[1].opBits            = MicroOpBits::B32;
        ctx.emitRewrite(ref, inst.op, narrow);
        return true;
    }

    // A unit address displacement on its own register is the compact INC/DEC
    // form. The newly written flags must be unobserved.
    bool tryShortenAddressUnitOffset(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* ops = inst.ops(*ctx.operands);
        if (!ops || !ops[0].reg.isInt() || ops[0].reg != ops[1].reg ||
            (ops[2].opBits != MicroOpBits::B32 && ops[2].opBits != MicroOpBits::B64) ||
            (ops[3].valueU64 != 1 && ops[3].valueU64 != UINT64_MAX) || ctx.isPrivateFrameBase(ops[0].reg) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) || !ctx.claimAll({ref}))
            return false;

        MicroInstrOperand unary[3];
        unary[0].reg     = ops[0].reg;
        unary[1].opBits  = ops[2].opBits;
        unary[2].microOp = ops[3].valueU64 == 1 ? MicroOp::Add : MicroOp::Subtract;
        ctx.emitRewrite(ref, MicroInstrOpcode::OpUnaryReg, unary);
        return true;
    }

    // With one input already in the result register, ADD is one byte shorter
    // than an unscaled LEA. The newly written flags must be unobserved.
    bool tryShortenAddressAdd(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* ops = inst.ops(*ctx.operands);
        if (!ops || !ops[0].reg.isInt() || !ops[1].reg.isInt() || !ops[2].reg.isInt() ||
            (ops[3].opBits != MicroOpBits::B32 && ops[3].opBits != MicroOpBits::B64) ||
            ops[4].opBits != MicroOpBits::B64 || ops[5].valueU64 != 1 || ops[6].valueU64 != 0 ||
            ctx.isPrivateFrameBase(ops[0].reg))
            return false;
        const MicroReg other = ops[0].reg == ops[1].reg ? ops[2].reg : ops[1].reg;
        if ((ops[0].reg != ops[1].reg && ops[0].reg != ops[2].reg) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) || !ctx.claimAll({ref}))
            return false;
        MicroInstrOperand add[4] = {};
        add[0].reg               = ops[0].reg;
        add[1].reg               = other;
        add[2].opBits            = ops[3].opBits;
        add[3].microOp           = MicroOp::Add;
        ctx.emitRewrite(ref, MicroInstrOpcode::OpBinaryRegReg, add);
        return true;
    }

    // A selection between x and -x can use the flags from NEG itself.
    // At INT_MIN both choices are identical, so NEG overflow does not change
    // either absolute-value result, including its wrapped negative form.
    bool tryReuseNegationForSignSelect(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* select = inst.ops(*ctx.operands);
        if (ctx.isClaimed(ref) || !select || !select[0].reg.isInt() || !select[1].reg.isInt() ||
            select[0].reg == select[1].reg || ctx.isPrivateFrameBase(select[0].reg) ||
            (select[3].opBits != MicroOpBits::B32 && select[3].opBits != MicroOpBits::B64))
            return false;
        const MicroCond condition = select[2].cpuCond;
        if (condition != MicroCond::GreaterOrEqual && condition != MicroCond::Greater &&
            condition != MicroCond::Less && condition != MicroCond::LessOrEqual)
            return false;
        const MicroInstrRef compareRef = ctx.previousRef(ref);
        const MicroInstr*   compare    = ctx.instruction(compareRef);
        if (!compare || compare->op != MicroInstrOpcode::CmpRegImm)
            return false;
        const auto* cmp = compare->ops(*ctx.operands);
        if (!cmp || cmp[0].reg != select[1].reg || cmp[1].opBits != select[3].opBits ||
            cmp[2].hasWideImmediateValue() || cmp[2].valueU64 != 0)
            return false;
        const MicroInstrRef negateRef = ctx.previousRef(compareRef);
        const MicroInstr*   negate    = ctx.instruction(negateRef);
        if (!negate || negate->op != MicroInstrOpcode::OpUnaryReg)
            return false;
        const auto* neg = negate->ops(*ctx.operands);
        if (!neg || neg[0].reg != select[0].reg || neg[1].opBits != select[3].opBits || neg[2].microOp != MicroOp::Negate)
            return false;
        const MicroInstrRef copyRef = ctx.previousRef(negateRef);
        const MicroInstr*   copy    = ctx.instruction(copyRef);
        if (!copy || copy->op != MicroInstrOpcode::LoadRegReg)
            return false;
        const auto* copied = copy->ops(*ctx.operands);
        if (!copied || copied[0].reg != select[0].reg || copied[1].reg != select[1].reg || copied[2].opBits != select[3].opBits ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
            !ctx.claimAll({copyRef, negateRef, compareRef, ref}))
            return false;
        MicroInstrOperand rewritten[4] = {select[0], select[1], select[2], select[3]};
        rewritten[2].cpuCond           = condition == MicroCond::GreaterOrEqual || condition == MicroCond::Greater ? MicroCond::Sign : MicroCond::Greater;
        ctx.emitRewrite(ref, inst.op, rewritten);
        ctx.emitErase(compareRef);
        return true;
    }

    // A zero-extended byte/word shifted entirely within the low dword needs
    // no 64-bit shift. Keep flags out of the rewrite: SF/OF may differ.
    bool tryNarrowZeroExtendedShift(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref))
            return false;
        const auto* ops = inst.ops(*ctx.operands);
        if (!ops || !ops[0].reg.isInt() || ops[1].opBits != MicroOpBits::B64 ||
            ops[2].microOp != MicroOp::ShiftLeft || ops[3].hasWideImmediateValue() || ops[3].valueU64 >= 32)
            return false;
        const MicroInstrRef extRef = ctx.previousRef(ref);
        const MicroInstr*   ext    = ctx.instruction(extRef);
        if (!ext || ext->op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;
        const auto* extOps = ext->ops(*ctx.operands);
        if (!extOps || extOps[0].reg != ops[0].reg ||
            (extOps[2].opBits != MicroOpBits::B32 && extOps[2].opBits != MicroOpBits::B64) ||
            (extOps[3].opBits != MicroOpBits::B8 && extOps[3].opBits != MicroOpBits::B16) ||
            getNumBits(extOps[3].opBits) + ops[3].valueU64 > 32 ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
            !ctx.claimAll({extRef, ref}))
            return false;
        MicroInstrOperand rewritten[4] = {ops[0], ops[1], ops[2], ops[3]};
        rewritten[1].opBits            = MicroOpBits::B32;
        ctx.emitRewrite(ref, inst.op, rewritten);
        return true;
    }

    // Move a zero initialization before the comparison whose flags feed the
    // following conditional move. This exposes XOR zeroing without changing
    // the selected value or letting XOR replace the comparison flags.
    bool tryClearZeroBeforeSelect(Context& ctx, const MicroInstrRef zeroRef, const MicroInstr& zeroInst)
    {
        if (ctx.isClaimed(zeroRef) || zeroInst.op != MicroInstrOpcode::LoadRegImm)
            return false;
        const auto* zero = zeroInst.ops(*ctx.operands);
        if (!zero || !zero[0].reg.isInt() || zero[2].hasWideImmediateValue() || zero[2].valueU64 != 0 ||
            (zero[1].opBits != MicroOpBits::B32 && zero[1].opBits != MicroOpBits::B64))
            return false;

        const MicroInstrRef cmpRef = ctx.previousRef(zeroRef);
        const MicroInstr*   cmp    = ctx.instruction(cmpRef);
        if (!cmp || !canMoveComparisonForSelect(*cmp, cmp->ops(*ctx.operands)))
            return false;
        const MicroInstrUseDef cmpUseDef = cmp->collectUseDef(*ctx.operands, ctx.encoder);
        if (std::ranges::find(cmpUseDef.uses, zero[0].reg) != cmpUseDef.uses.end() ||
            std::ranges::find(cmpUseDef.defs, zero[0].reg) != cmpUseDef.defs.end())
            return false;

        const MicroInstrRef selectRef = ctx.nextRef(zeroRef);
        const MicroInstr*   select    = ctx.instruction(selectRef);
        const auto*         selected  = select ? select->ops(*ctx.operands) : nullptr;
        if (!select || select->op != MicroInstrOpcode::LoadCondRegReg || !selected ||
            selected[0].reg != zero[0].reg || selected[3].opBits != zero[1].opBits)
            return false;

        MicroInstrOperand clear[2] = {};
        clear[0].reg               = zero[0].reg;
        clear[1].opBits            = zero[1].opBits;
        MicroInstr clearProbe;
        clearProbe.op          = MicroInstrOpcode::ClearReg;
        clearProbe.numOperands = 2;
        MicroConformanceIssue issue;
        if (ctx.encoder->queryConformanceIssue(issue, clearProbe, clear) ||
            !ctx.claimAll({cmpRef, zeroRef, selectRef}))
            return false;

        ctx.emitRewrite(cmpRef, clearProbe.op, clear);
        ctx.emitRewrite(zeroRef, cmp->op, std::span{cmp->ops(*ctx.operands), cmp->numOperands}, true);
        return true;
    }

    // Initialize a value-or-zero selection with XOR before its compare.
    // Postpone the old zero load until after CMOV so both registers retain
    // their original final values, even when it overwrites the input.
    bool tryInvertZeroSelect(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref))
            return false;
        const auto* copy = inst.ops(*ctx.operands);
        if (!copy || !copy[0].reg.isInt() || !copy[1].reg.isInt() || copy[0].reg == copy[1].reg ||
            ctx.isPrivateFrameBase(copy[0].reg) || (copy[2].opBits != MicroOpBits::B32 && copy[2].opBits != MicroOpBits::B64))
            return false;
        MicroInstrRef     cmpRef       = ctx.nextRef(ref);
        const MicroInstr* cmp          = ctx.instruction(cmpRef);
        bool              compareFirst = false;
        if (!cmp || !canMoveComparisonForSelect(*cmp, cmp->ops(*ctx.operands)))
        {
            cmpRef       = ctx.previousRef(ref);
            cmp          = ctx.instruction(cmpRef);
            compareFirst = true;
        }
        if (!cmp || !canMoveComparisonForSelect(*cmp, cmp->ops(*ctx.operands)))
            return false;
        const MicroInstrUseDef cmpUseDef = cmp->collectUseDef(*ctx.operands, ctx.encoder);
        for (const MicroReg reg : cmpUseDef.uses)
            if (reg == copy[0].reg)
                return false;
        const MicroInstrRef zeroRef = ctx.nextRef(compareFirst ? ref : cmpRef);
        const MicroInstr*   zero    = ctx.instruction(zeroRef);
        if (!zero || zero->op != MicroInstrOpcode::LoadRegImm)
            return false;
        const auto* zeroOps = zero->ops(*ctx.operands);
        if (!zeroOps || !zeroOps[0].reg.isInt() || zeroOps[0].reg == copy[0].reg || zeroOps[2].hasWideImmediateValue() ||
            zeroOps[2].valueU64 != 0 || (zeroOps[1].opBits != MicroOpBits::B32 && zeroOps[1].opBits != MicroOpBits::B64))
            return false;
        const MicroInstrRef selectRef = ctx.nextRef(zeroRef);
        const MicroInstr*   select    = ctx.instruction(selectRef);
        if (!select || select->op != MicroInstrOpcode::LoadCondRegReg)
            return false;
        const auto* selectOps = select->ops(*ctx.operands);
        MicroCond   inverted;
        if (!selectOps || selectOps[0].reg != copy[0].reg || selectOps[1].reg != zeroOps[0].reg ||
            selectOps[3].opBits != copy[2].opBits || !MicroPassHelpers::invertCondition(inverted, selectOps[2].cpuCond) ||
            !ctx.claimAll({ref, cmpRef, zeroRef, selectRef}))
            return false;
        MicroInstrOperand clear[2] = {};
        clear[0].reg               = copy[0].reg;
        clear[1].opBits            = MicroOpBits::B32;
        MicroInstrOperand move[4]  = {selectOps[0], copy[1], selectOps[2], selectOps[3]};
        move[2].cpuCond            = inverted;
        if (compareFirst)
        {
            ctx.emitRewrite(cmpRef, MicroInstrOpcode::ClearReg, clear);
            ctx.emitRewrite(ref, cmp->op, std::span{cmp->ops(*ctx.operands), cmp->numOperands}, true);
        }
        else
            ctx.emitRewrite(ref, MicroInstrOpcode::ClearReg, clear);
        ctx.emitRewrite(zeroRef, select->op, move, true);
        ctx.emitRewrite(selectRef, zero->op, std::span{zeroOps, zero->numOperands});
        return true;
    }

    // A selected value copied back over its zero register can select directly
    // into that register. Keep the reverse copy until DCE proves it unnecessary.
    bool tryInvertResultZeroSelect(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (ctx.isClaimed(copyRef))
            return false;
        const auto* copy = copyInst.ops(*ctx.operands);
        if (!copy || !copy[0].reg.isInt() || !copy[1].reg.isInt() || copy[0].reg == copy[1].reg ||
            ctx.isPrivateFrameBase(copy[0].reg) || ctx.isPrivateFrameBase(copy[1].reg) ||
            (copy[2].opBits != MicroOpBits::B32 && copy[2].opBits != MicroOpBits::B64))
            return false;
        const MicroInstrRef selectRef = ctx.previousRef(copyRef);
        const MicroInstr*   select    = ctx.instruction(selectRef);
        if (!select || select->op != MicroInstrOpcode::LoadCondRegReg)
            return false;
        const auto* selectOps = select->ops(*ctx.operands);
        MicroCond   inverted;
        if (!selectOps || selectOps[0].reg != copy[1].reg || selectOps[1].reg != copy[0].reg ||
            selectOps[3].opBits != copy[2].opBits || !MicroPassHelpers::invertCondition(inverted, selectOps[2].cpuCond))
            return false;
        const MicroInstrRef zeroRef = ctx.previousRef(selectRef);
        const MicroInstr*   zero    = ctx.instruction(zeroRef);
        if (!zero || zero->op != MicroInstrOpcode::LoadRegImm)
            return false;
        const auto* zeroOps = zero->ops(*ctx.operands);
        if (!zeroOps || zeroOps[0].reg != copy[0].reg || zeroOps[2].hasWideImmediateValue() || zeroOps[2].valueU64 != 0 ||
            (zeroOps[1].opBits != MicroOpBits::B32 && zeroOps[1].opBits != MicroOpBits::B64))
            return false;
        const MicroInstrRef cmpRef = ctx.previousRef(zeroRef);
        const MicroInstr*   cmp    = ctx.instruction(cmpRef);
        if (!cmp || !canMoveComparisonForSelect(*cmp, cmp->ops(*ctx.operands)))
            return false;
        const MicroInstrUseDef useDef = cmp->collectUseDef(*ctx.operands, ctx.encoder);
        for (const MicroReg reg : useDef.uses)
            if (reg == copy[0].reg)
                return false;
        if (!ctx.claimAll({cmpRef, zeroRef, selectRef, copyRef}))
            return false;
        MicroInstrOperand clear[2]         = {};
        clear[0].reg                       = copy[0].reg;
        clear[1].opBits                    = MicroOpBits::B32;
        MicroInstrOperand selected[4]      = {copy[0], copy[1], selectOps[2], copy[2]};
        selected[2].cpuCond                = inverted;
        const MicroInstrOperand reverse[3] = {copy[1], copy[0], copy[2]};
        ctx.emitRewrite(cmpRef, MicroInstrOpcode::ClearReg, clear);
        ctx.emitRewrite(zeroRef, cmp->op, std::span{cmp->ops(*ctx.operands), cmp->numOperands}, true);
        ctx.emitRewrite(selectRef, select->op, selected);
        ctx.emitRewrite(copyRef, copyInst.op, reverse);
        return true;
    }

    // When only SUB's flags reach a widened boolean, replace its copied
    // result with CMP and clear the boolean destination before that compare.
    bool tryFoldSubtractBoolean(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref))
            return false;
        const auto* result = inst.ops(*ctx.operands);
        if (!result || !result[0].reg.isInt() || result[0].reg != result[1].reg || result[3].opBits != MicroOpBits::B8 ||
            (result[2].opBits != MicroOpBits::B32 && result[2].opBits != MicroOpBits::B64) || ctx.isPrivateFrameBase(result[0].reg))
            return false;
        const MicroInstrRef setRef = ctx.previousRef(ref);
        const MicroInstr*   set    = ctx.instruction(setRef);
        if (!set || set->op != MicroInstrOpcode::SetCondReg)
            return false;
        const auto* setOps = set->ops(*ctx.operands);
        if (!setOps || setOps[0].reg != result[0].reg)
            return false;
        const MicroInstrRef subRef = ctx.previousRef(setRef);
        const MicroInstr*   sub    = ctx.instruction(subRef);
        if (!sub || sub->op != MicroInstrOpcode::OpBinaryRegReg)
            return false;
        const auto* subOps = sub->ops(*ctx.operands);
        if (!subOps || subOps[0].reg != result[0].reg || !subOps[1].reg.isInt() || subOps[3].microOp != MicroOp::Subtract ||
            (subOps[2].opBits != MicroOpBits::B32 && subOps[2].opBits != MicroOpBits::B64))
            return false;
        const MicroInstrRef copyRef = ctx.previousRef(subRef);
        const MicroInstr*   copy    = ctx.instruction(copyRef);
        if (!copy || copy->op != MicroInstrOpcode::LoadRegReg)
            return false;
        const auto* copyOps = copy->ops(*ctx.operands);
        if (!copyOps || copyOps[0].reg != result[0].reg || !copyOps[1].reg.isInt() || copyOps[1].reg == result[0].reg ||
            copyOps[2].opBits != subOps[2].opBits || !ctx.claimAll({copyRef, subRef, setRef, ref}))
            return false;
        MicroInstrOperand clear[2]   = {};
        clear[0].reg                 = result[0].reg;
        clear[1].opBits              = MicroOpBits::B32;
        MicroInstrOperand compare[3] = {copyOps[1], subOps[1], subOps[2]};
        if (compare[1].reg == result[0].reg)
            compare[1].reg = copyOps[1].reg;
        ctx.emitRewrite(copyRef, MicroInstrOpcode::ClearReg, clear);
        ctx.emitRewrite(subRef, MicroInstrOpcode::CmpRegReg, compare);
        ctx.emitErase(ref);
        return true;
    }

    // SETcc produces 0 or 1, so an 8-bit AND/OR/XOR of two SETcc values is
    // already a canonical boolean. A following SETNE only reproduces it.
    bool tryEraseBooleanRecanonicalization(Context& ctx, const MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref) || inst.op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;
        const auto* widened = inst.ops(*ctx.operands);
        if (!widened || widened[0].reg != widened[1].reg || widened[3].opBits != MicroOpBits::B8 ||
            (widened[2].opBits != MicroOpBits::B32 && widened[2].opBits != MicroOpBits::B64))
            return false;

        const MicroInstrRef canonicalRef = ctx.previousRef(ref);
        const MicroInstr*   canonical    = ctx.instruction(canonicalRef);
        const auto*         canonicalOps = canonical ? canonical->ops(*ctx.operands) : nullptr;
        if (!canonical || canonical->op != MicroInstrOpcode::SetCondReg || !canonicalOps ||
            canonicalOps[0].reg != widened[0].reg ||
            (canonicalOps[1].cpuCond != MicroCond::NotEqual && canonicalOps[1].cpuCond != MicroCond::NotZero))
            return false;

        const MicroInstrRef binaryRef = ctx.previousRef(canonicalRef);
        const MicroInstr*   binary    = ctx.instruction(binaryRef);
        const auto*         binaryOps = binary ? binary->ops(*ctx.operands) : nullptr;
        if (!binary || binary->op != MicroInstrOpcode::OpBinaryRegReg || !binaryOps ||
            binaryOps[0].reg != widened[0].reg || !binaryOps[1].reg.isInt() || binaryOps[2].opBits != MicroOpBits::B8 ||
            (binaryOps[3].microOp != MicroOp::And && binaryOps[3].microOp != MicroOp::Or && binaryOps[3].microOp != MicroOp::Xor))
            return false;

        const MicroInstrRef secondSetRef = ctx.previousRef(binaryRef);
        const MicroInstr*   secondSet    = ctx.instruction(secondSetRef);
        const auto*         secondOps    = secondSet ? secondSet->ops(*ctx.operands) : nullptr;
        if (!secondSet || secondSet->op != MicroInstrOpcode::SetCondReg || !secondOps ||
            secondOps[0].reg != binaryOps[1].reg)
            return false;
        const MicroInstrRef secondCompareRef = ctx.previousRef(secondSetRef);
        const MicroInstr*   secondCompare    = ctx.instruction(secondCompareRef);
        if (!secondCompare ||
            (secondCompare->op != MicroInstrOpcode::CmpRegReg && secondCompare->op != MicroInstrOpcode::CmpRegImm &&
             secondCompare->op != MicroInstrOpcode::TestRegReg && secondCompare->op != MicroInstrOpcode::TestRegImm))
            return false;
        const MicroInstrRef firstSetRef = ctx.previousRef(secondCompareRef);
        const MicroInstr*   firstSet    = ctx.instruction(firstSetRef);
        const auto*         firstOps    = firstSet ? firstSet->ops(*ctx.operands) : nullptr;
        if (!firstSet || firstSet->op != MicroInstrOpcode::SetCondReg || !firstOps ||
            firstOps[0].reg != binaryOps[0].reg || !ctx.claimAll({canonicalRef, ref}))
            return false;

        ctx.emitErase(canonicalRef);
        return true;
    }

    // Fold zero-extend; compare; SETcc; zero-extend into a narrow compare
    // with a pre-cleared boolean destination. Unsigned/equality conditions
    // survive narrowing when the immediate fits the source width.
    bool tryFoldZeroExtendedBooleanCompare(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref))
            return false;
        const auto* result = inst.ops(*ctx.operands);
        if (!result || !result[0].reg.isInt() || result[0].reg != result[1].reg || result[3].opBits != MicroOpBits::B8 ||
            (result[2].opBits != MicroOpBits::B32 && result[2].opBits != MicroOpBits::B64) || ctx.isPrivateFrameBase(result[0].reg))
            return false;
        const MicroInstrRef setRef = ctx.previousRef(ref);
        const MicroInstr*   set    = ctx.instruction(setRef);
        if (!set || set->op != MicroInstrOpcode::SetCondReg)
            return false;
        const auto* setOps = set->ops(*ctx.operands);
        if (!setOps || setOps[0].reg != result[0].reg)
            return false;
        switch (setOps[1].cpuCond)
        {
            case MicroCond::Equal:
            case MicroCond::NotEqual:
            case MicroCond::Zero:
            case MicroCond::NotZero:
            case MicroCond::Above:
            case MicroCond::AboveOrEqual:
            case MicroCond::Below:
            case MicroCond::BelowOrEqual:
            case MicroCond::NotAbove:
                break;
            default:
                return false;
        }
        const MicroInstrRef cmpRef = ctx.previousRef(setRef);
        const MicroInstr*   cmp    = ctx.instruction(cmpRef);
        if (!cmp || cmp->op != MicroInstrOpcode::CmpRegImm)
            return false;
        const auto* cmpOps = cmp->ops(*ctx.operands);
        if (!cmpOps || cmpOps[0].reg != result[0].reg || cmpOps[2].hasWideImmediateValue())
            return false;
        const MicroInstrRef sourceRef = ctx.previousRef(cmpRef);
        const MicroInstr*   source    = ctx.instruction(sourceRef);
        if (!source || source->op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;
        const auto* sourceOps = source->ops(*ctx.operands);
        if (!sourceOps || sourceOps[0].reg != result[0].reg || !sourceOps[1].reg.isInt() || sourceOps[1].reg == result[0].reg ||
            (sourceOps[2].opBits != MicroOpBits::B32 && sourceOps[2].opBits != MicroOpBits::B64) ||
            (sourceOps[3].opBits != MicroOpBits::B8 && sourceOps[3].opBits != MicroOpBits::B16) ||
            getNumBits(cmpOps[1].opBits) < getNumBits(sourceOps[3].opBits) ||
            cmpOps[2].valueU64 > getBitsMask(sourceOps[3].opBits) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
            !ctx.claimAll({sourceRef, cmpRef, setRef, ref}))
            return false;
        MicroInstrOperand clear[2]  = {};
        clear[0].reg                = result[0].reg;
        clear[1].opBits             = MicroOpBits::B32;
        MicroInstrOperand narrow[3] = {cmpOps[0], cmpOps[1], cmpOps[2]};
        narrow[0].reg               = sourceOps[1].reg;
        narrow[1].opBits            = sourceOps[3].opBits;
        ctx.emitRewrite(sourceRef, MicroInstrOpcode::ClearReg, clear);
        ctx.emitRewrite(cmpRef, cmp->op, narrow);
        ctx.emitErase(ref);
        return true;
    }

    // The legacy high-byte registers can replace a shift plus byte extraction.
    // Ask the encoder before forming one: a REX prefix makes them unavailable.
    bool tryExtractHighByte(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* ext = inst.ops(*ctx.operands);
        if (!ext || !ctx.encoder || ext[3].opBits != MicroOpBits::B8 ||
            (ext[2].opBits != MicroOpBits::B32 && ext[2].opBits != MicroOpBits::B64) ||
            ctx.isPrivateFrameBase(ext[0].reg) || ctx.isPrivateFrameBase(ext[1].reg) ||
            !ctx.encoder->supportsHighByteExtract(ext[0].reg, ext[1].reg))
            return false;
        const MicroInstrRef shiftRef = ctx.previousRef(ref);
        const MicroInstr*   shift    = ctx.instruction(shiftRef);
        if (!shift || shift->op != MicroInstrOpcode::OpBinaryRegImm)
            return false;
        const auto* ops = shift->ops(*ctx.operands);
        if (!ops || ops[0].reg != ext[1].reg ||
            (ops[1].opBits != MicroOpBits::B32 && ops[1].opBits != MicroOpBits::B64) ||
            (ops[2].microOp != MicroOp::ShiftRight && ops[2].microOp != MicroOp::ShiftArithmeticRight) || ops[3].hasWideImmediateValue() || ops[3].valueU64 != 8 ||
            (ext[0].reg != ext[1].reg && !ctx.isRegDeadAfterCurrent(ext[1].reg)) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
            !ctx.claimAll({shiftRef, ref}))
            return false;
        const MicroInstrOperand extract[3] = {ext[0], ext[1], ext[2]};
        ctx.emitRewrite(ref, MicroInstrOpcode::LoadHighByteRegReg, extract);
        ctx.emitErase(shiftRef);
        return true;
    }

    // If only a low byte/word of a logical right shift survives, perform the
    // shift in 32 bits when all bits contributing to that slice are below bit 32.
    bool tryNarrowTruncatedRightShift(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* ext = inst.ops(*ctx.operands);
        if (!ext || !ext[0].reg.isInt() || !ext[1].reg.isInt() ||
            (ext[2].opBits != MicroOpBits::B32 && ext[2].opBits != MicroOpBits::B64) ||
            (ext[3].opBits != MicroOpBits::B8 && ext[3].opBits != MicroOpBits::B16))
            return false;
        const MicroInstrRef shiftRef = ctx.previousRef(ref);
        const MicroInstr*   shift    = ctx.instruction(shiftRef);
        if (!shift || shift->op != MicroInstrOpcode::OpBinaryRegImm)
            return false;
        const auto* ops = shift->ops(*ctx.operands);
        if (!ops || ops[0].reg != ext[1].reg || ops[1].opBits != MicroOpBits::B64 ||
            ops[2].microOp != MicroOp::ShiftRight || ops[3].hasWideImmediateValue() ||
            ops[3].valueU64 == 0 || ops[3].valueU64 >= 32 || ops[3].valueU64 + getNumBits(ext[3].opBits) > 32 ||
            ctx.isPrivateFrameBase(ops[0].reg) ||
            (ext[0].reg != ext[1].reg && !ctx.isRegDeadAfterCurrent(ext[1].reg)) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
            !ctx.claimAll({shiftRef, ref}))
            return false;
        MicroInstrOperand narrowed[4] = {ops[0], ops[1], ops[2], ops[3]};
        narrowed[1].opBits            = MicroOpBits::B32;
        ctx.emitRewrite(shiftRef, shift->op, narrowed);
        return true;
    }

    // A signed comparison against zero exposes the sign bit directly. Keep
    // the original full-width source and define every result bit with a shift.
    bool tryExtractSignBoolean(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        const auto* ext = inst.ops(*ctx.operands);
        if (!ext || !ext[0].reg.isInt() || ext[0].reg != ext[1].reg ||
            ext[3].opBits != MicroOpBits::B8 ||
            (ext[2].opBits != MicroOpBits::B32 && ext[2].opBits != MicroOpBits::B64) ||
            ctx.isPrivateFrameBase(ext[0].reg))
            return false;
        const MicroInstrRef setRef = ctx.previousRef(ref);
        const MicroInstr*   set    = ctx.instruction(setRef);
        if (!set || set->op != MicroInstrOpcode::SetCondReg)
            return false;
        const auto* setOps = set->ops(*ctx.operands);
        if (!setOps || setOps[0].reg != ext[0].reg)
            return false;
        const MicroCond condition = setOps[1].cpuCond;
        if (condition != MicroCond::Less && condition != MicroCond::Sign)
            return false;
        const MicroInstrRef cmpRef = ctx.previousRef(setRef);
        const MicroInstr*   cmp    = ctx.instruction(cmpRef);
        if (!cmp || cmp->op != MicroInstrOpcode::CmpRegImm)
            return false;
        const auto* cmpOps = cmp->ops(*ctx.operands);
        if (!cmpOps || !cmpOps[0].reg.isInt() || cmpOps[2].hasWideImmediateValue() || cmpOps[2].valueU64 != 0 ||
            (cmpOps[1].opBits != MicroOpBits::B32 && cmpOps[1].opBits != MicroOpBits::B64) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, ref, ctx.builder) ||
            !ctx.claimAll({cmpRef, setRef, ref}))
            return false;
        MicroInstrOperand copy[3] = {};
        copy[0].reg               = ext[0].reg;
        copy[1].reg               = cmpOps[0].reg;
        copy[2].opBits            = cmpOps[1].opBits;
        ctx.emitRewrite(cmpRef, MicroInstrOpcode::LoadRegReg, copy);
        MicroInstrOperand shift[4] = {};
        shift[0].reg               = ext[0].reg;
        shift[1].opBits            = cmpOps[1].opBits;
        shift[2].microOp           = MicroOp::ShiftRight;
        shift[3].valueU64          = getNumBits(cmpOps[1].opBits) - 1;
        ctx.emitRewrite(setRef, MicroInstrOpcode::OpBinaryRegImm, shift, true);
        ctx.emitErase(ref);
        return true;
    }

    // Zero the full result before its flag producer instead of extending
    // SETcc's byte afterward. The producer must not read that result register.
    bool tryClearBeforeSetCondition(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref))
            return false;
        const auto* ext = inst.ops(*ctx.operands);
        if (!ext || !ext[0].reg.isInt() || ext[0].reg != ext[1].reg ||
            ext[3].opBits != MicroOpBits::B8 ||
            (ext[2].opBits != MicroOpBits::B32 && ext[2].opBits != MicroOpBits::B64) ||
            ctx.isPrivateFrameBase(ext[0].reg))
            return false;
        const MicroInstrRef setRef = ctx.previousRef(ref);
        const MicroInstr*   set    = ctx.instruction(setRef);
        if (!set || set->op != MicroInstrOpcode::SetCondReg)
            return false;
        const auto* setOps = set->ops(*ctx.operands);
        if (!setOps || setOps[0].reg != ext[0].reg)
            return false;
        const MicroInstrRef cmpRef = ctx.previousRef(setRef);
        const MicroInstr*   cmp    = ctx.instruction(cmpRef);
        if (!cmp)
            return false;
        const auto* cmpOps = cmp->ops(*ctx.operands);
        if (!cmpOps || !cmpOps[0].reg.isInt())
            return false;

        // Register allocation can coalesce the compare source with the SETcc
        // result and leave a copy immediately before an indexed comparison:
        //
        //     copy result, source
        //     cmp  [base + index*scale], result
        //     setcc result
        //     movzx result, result.byte
        //
        // Restore the original compare source so the copy's slot can clear the
        // result before CMP. This is the same three-instruction boolean idiom as
        // the generic case below, despite the post-RA coalescing.
        if (cmp->op == MicroInstrOpcode::CmpAmcReg && cmpOps[2].reg == ext[0].reg &&
            cmpOps[0].reg != ext[0].reg && cmpOps[1].reg != ext[0].reg)
        {
            const MicroInstrRef copyRef = ctx.previousRef(cmpRef);
            const MicroInstr*   copy    = ctx.instruction(copyRef);
            const auto*         copyOps = copy && copy->op == MicroInstrOpcode::LoadRegReg ? copy->ops(*ctx.operands) : nullptr;
            if (copyOps && copyOps[0].reg == ext[0].reg && copyOps[1].reg.isInt() && copyOps[1].reg != ext[0].reg &&
                copyOps[2].opBits == cmpOps[4].opBits && !ctx.isPrivateFrameBase(copyOps[1].reg) &&
                ctx.claimAll({copyRef, cmpRef, setRef, ref}))
            {
                MicroInstrOperand clear[2] = {};
                clear[0].reg               = ext[0].reg;
                clear[1].opBits            = MicroOpBits::B32;
                MicroInstrOperand compare[7] = {cmpOps[0], cmpOps[1], cmpOps[2], cmpOps[3], cmpOps[4], cmpOps[5], cmpOps[6]};
                compare[2].reg               = copyOps[1].reg;
                ctx.emitRewrite(copyRef, MicroInstrOpcode::ClearReg, clear);
                ctx.emitRewrite(cmpRef, cmp->op, compare, true);
                ctx.emitErase(ref);
                return true;
            }
        }

        if (isCompareInstruction(cmp->op))
        {
            if (!canMoveComparisonForSelect(*cmp, cmpOps))
                return false;
        }
        else
        {
            // These integer ALU producers overwrite the incoming flags and
            // read their destination, so the use check also protects its result.
            MicroReg    resultReg;
            MicroOpBits resultBits;
            if (!flagSettingResultDef(*cmp, cmpOps, resultReg, resultBits))
                return false;
        }
        const MicroInstrUseDef useDef = cmp->collectUseDef(*ctx.operands, ctx.encoder);
        for (const MicroReg reg : useDef.uses)
            if (reg == ext[0].reg)
                return false;
        if (!ctx.claimAll({cmpRef, setRef, ref}))
            return false;
        MicroInstrOperand clear[2] = {};
        clear[0].reg               = ext[0].reg;
        clear[1].opBits            = MicroOpBits::B32;
        ctx.emitRewrite(cmpRef, MicroInstrOpcode::ClearReg, clear);
        ctx.emitRewrite(setRef, cmp->op, std::span{cmpOps, cmp->numOperands}, true);
        ctx.emitRewrite(ref, set->op, std::span{setOps, set->numOperands});
        return true;
    }

    bool tryUseTestForDeadMask(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (ctx.isClaimed(ref))
            return false;
        const auto* ops = inst.ops(*ctx.operands);
        if (!ops || ops[2].microOp != MicroOp::And || !ops[0].reg.isInt() ||
            (ops[1].opBits != MicroOpBits::B32 && ops[1].opBits != MicroOpBits::B64) ||
            ops[3].hasWideImmediateValue() || ops[3].valueU64 > 0x7F ||
            ctx.isPrivateFrameBase(ops[0].reg) || !ctx.isRegDeadAfterCurrent(ops[0].reg))
            return false;

        // With bit 7 clear, both widths produce SF=0 and the same ZF/PF;
        // AND and TEST also clear CF/OF. No result value survives the mask.
        MicroInstrOperand test[3] = {};
        test[0]                   = ops[0];
        test[1].opBits            = MicroOpBits::B8;
        test[2]                   = ops[3];
        MicroInstr probe          = inst;
        probe.op                  = MicroInstrOpcode::TestRegImm;
        probe.numOperands         = 3;
        MicroConformanceIssue issue;
        if ((ctx.encoder && ctx.encoder->queryConformanceIssue(issue, probe, test)) || !ctx.claimAll({ref}))
            return false;
        ctx.emitRewrite(ref, probe.op, test);
        return true;
    }

    bool tryEraseDeadCompare(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        if (!isCompareInstruction(inst.op))
            return false;

        for (MicroInstrRef scanRef = ctx.nextRef(ref); scanRef.isValid(); scanRef = ctx.nextRef(scanRef))
        {
            const MicroInstr* scanInst = ctx.instruction(scanRef);
            if (!scanInst)
                return false;

            const MicroInstrOperand* scanOps = scanInst->ops(*ctx.operands);
            if (isTriviallyErasableNoEffect(*scanInst, scanOps))
                continue;

            if (instructionActuallyUsesCpuFlags(*scanInst, scanOps))
            {
                if (isRedundantFallthroughJumpToNextLabel(ctx, scanRef, *scanInst, scanOps))
                    continue;

                return false;
            }

            const MicroInstrDef& info = MicroInstr::info(scanInst->op);
            if (info.flags.has(MicroInstrFlagsE::JumpInstruction) && (!ctx.builder || !MicroPassHelpers::areCpuFlagsDeadAfterInCfg(*ctx.builder, scanRef)))
                return false;
            if (MicroPassHelpers::instructionOverwritesCpuFlags(*scanInst, scanOps) ||
                info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                info.flags.has(MicroInstrFlagsE::JumpInstruction))
            {
                if (!ctx.claimAll({ref}))
                    return false;

                ctx.emitErase(ref);
                return true;
            }
        }

        if (!ctx.claimAll({ref}))
            return false;

        ctx.emitErase(ref);
        return true;
    }
}

SWC_END_NAMESPACE();
