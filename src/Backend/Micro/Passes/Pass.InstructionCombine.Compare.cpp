#include "pch.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"
#include "Backend/Micro/MicroPassHelpers.h"

// Compares: flags an earlier instruction already produced reused instead of
// computed again, and known values folded into the compared operand.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        bool sameValueAt(const Context& ctx, MicroReg reg, MicroInstrRef first, MicroInstrRef second)
        {
            const MicroSsaState::ReachingDef firstDef  = ctx.ssa->reachingDef(reg, first);
            const MicroSsaState::ReachingDef secondDef = ctx.ssa->reachingDef(reg, second);
            return firstDef.valid() && secondDef.valid() && firstDef.valueId == secondDef.valueId;
        }

        bool isAllOnesLoad(const MicroSsaState::ReachingDef& def, const MicroOperandStorage& operands, MicroOpBits bits)
        {
            if (!def.valid() || def.isPhi || !def.inst || def.inst->op != MicroInstrOpcode::LoadRegImm)
                return false;
            const MicroInstrOperand* ops = def.inst->ops(operands);
            return ops && ops[1].opBits == bits && !ops[2].hasWideImmediateValue() &&
                   (ops[2].valueU64 & getBitsMask(bits)) == getBitsMask(bits);
        }
    }

    // The low byte of a copied value is unchanged. When an indexed compare
    // is its only reader, use the still-current source byte directly.
    bool tryBypassByteCopyInIndexedCompare(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst)
    {
        if (ctx.isClaimed(cmpRef) || !ctx.ssa)
            return false;
        const auto* cmp = cmpInst.ops(*ctx.operands);
        if (!cmp || cmp[4].opBits != MicroOpBits::B8 || !cmp[2].reg.isVirtualInt() ||
            cmp[2].reg == cmp[0].reg || cmp[2].reg == cmp[1].reg)
            return false;
        const MicroReg copied = cmp[2].reg;
        const auto def = ctx.ssa->reachingDef(copied, cmpRef);
        if (!def.valid() || def.isPhi || !def.inst || def.inst->op != MicroInstrOpcode::LoadRegReg ||
            ctx.isClaimed(def.instRef) || ctx.isRelocated(def.instRef))
            return false;
        const auto* copy = def.inst->ops(*ctx.operands);
        if (!copy || copy[0].reg != copied || copy[2].opBits != MicroOpBits::B8 || !copy[1].reg.isVirtualInt() ||
            copy[1].reg == cmp[0].reg || copy[1].reg == cmp[1].reg ||
            !valueHasSingleUse(*ctx.ssa, copied, def.instRef))
            return false;
        const auto sourceAtCopy = ctx.ssa->reachingDef(copy[1].reg, def.instRef);
        const auto sourceAtCmp = ctx.ssa->reachingDef(copy[1].reg, cmpRef);
        if (!sourceAtCopy.valid() || !sourceAtCmp.valid() || sourceAtCopy.valueId != sourceAtCmp.valueId ||
            !ctx.claimAll({cmpRef, def.instRef}))
            return false;
        MicroInstrOperand rewritten[7] = {};
        for (uint32_t i = 0; i < 7; ++i)
            rewritten[i] = cmp[i];
        rewritten[2].reg = copy[1].reg;
        ctx.emitRewrite(cmpRef, MicroInstrOpcode::CmpAmcReg, rewritten, /*allocNewBlock=*/true);
        ctx.emitErase(def.instRef);
        return true;
    }

    // A comparison has already read the indexed cell, so loading that same
    // cell on only one branch does not need another memory access:
    //
    //     result = fallback             result = [base + index]
    //     cmp [base + index], fallback  cmp result, fallback
    //     jCC .join                  -> cmovCC result, fallback
    //     temp = [base + index]
    //     result = temp
    //   .join:
    //
    // The unconditional load is safe because the original compare reads the
    // cell on both paths. This also leaves the conditional move available to
    // the normal register allocator instead of carrying a load-bearing arm.
    bool trySelectComparedIndexedLoad(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst)
    {
        if (!ctx.ssa || ctx.isClaimed(cmpRef) || cmpInst.op != MicroInstrOpcode::CmpAmcReg)
            return false;
        const MicroInstrOperand* cmp = cmpInst.ops(*ctx.operands);
        if (!cmp || cmp[3].opBits != MicroOpBits::B64 ||
            (cmp[4].opBits != MicroOpBits::B32 && cmp[4].opBits != MicroOpBits::B64))
            return false;

        const MicroInstrRef initRef  = ctx.storage->findPreviousInstructionRef(cmpRef);
        const MicroInstrRef jumpRef  = ctx.storage->findNextInstructionRef(cmpRef);
        const MicroInstrRef loadRef  = ctx.storage->findNextInstructionRef(jumpRef);
        const MicroInstrRef copyRef  = ctx.storage->findNextInstructionRef(loadRef);
        const MicroInstrRef labelRef = ctx.storage->findNextInstructionRef(copyRef);
        const MicroInstr* init  = ctx.storage->ptr(initRef);
        const MicroInstr* jump  = ctx.storage->ptr(jumpRef);
        const MicroInstr* load  = ctx.storage->ptr(loadRef);
        const MicroInstr* copy  = ctx.storage->ptr(copyRef);
        const MicroInstr* label = ctx.storage->ptr(labelRef);
        if (!init || init->op != MicroInstrOpcode::LoadRegReg ||
            !jump || jump->op != MicroInstrOpcode::JumpCond ||
            !load || load->op != MicroInstrOpcode::LoadAmcRegMem ||
            !copy || copy->op != MicroInstrOpcode::LoadRegReg ||
            !label || label->op != MicroInstrOpcode::Label)
            return false;
        const MicroInstrOperand* initOps  = init->ops(*ctx.operands);
        const MicroInstrOperand* jumpOps  = jump->ops(*ctx.operands);
        const MicroInstrOperand* loadOps  = load->ops(*ctx.operands);
        const MicroInstrOperand* copyOps  = copy->ops(*ctx.operands);
        const MicroInstrOperand* labelOps = label->ops(*ctx.operands);
        if (!initOps || !jumpOps || !loadOps || !copyOps || !labelOps ||
            jumpOps[0].cpuCond == MicroCond::Unconditional || jumpOps[2].valueU64 != labelOps[0].valueU64 ||
            initOps[2].opBits != cmp[4].opBits || copyOps[2].opBits != cmp[4].opBits ||
            loadOps[3].opBits != cmp[4].opBits || loadOps[4].opBits != cmp[3].opBits ||
            loadOps[1].reg != cmp[0].reg || loadOps[2].reg != cmp[1].reg ||
            loadOps[5].valueU64 != cmp[5].valueU64 || loadOps[6].valueU64 != cmp[6].valueU64 ||
            initOps[1].reg != cmp[2].reg || copyOps[0].reg != initOps[0].reg || copyOps[1].reg != loadOps[0].reg)
            return false;
        const MicroReg result   = initOps[0].reg;
        const MicroReg fallback = cmp[2].reg;
        const MicroReg temp     = loadOps[0].reg;
        if (!result.isVirtualInt() || !fallback.isVirtualInt() || !temp.isVirtualInt() ||
            result == fallback || result == cmp[0].reg || result == cmp[1].reg ||
            temp == result || temp == fallback || temp == cmp[0].reg || temp == cmp[1].reg)
            return false;
        if (!sameValueAt(ctx, cmp[0].reg, cmpRef, loadRef) ||
            !sameValueAt(ctx, cmp[1].reg, cmpRef, loadRef) ||
            !sameValueAt(ctx, fallback, initRef, cmpRef))
            return false;
        uint32_t tempValue = 0;
        if (!ctx.ssa->defValue(temp, loadRef, tempValue) || singleDirectInstructionUse(*ctx.ssa, tempValue) != copyRef ||
            !ctx.claimAll({initRef, cmpRef, jumpRef, loadRef, copyRef}))
            return false;

        MicroInstrOperand selectedLoad[7] = {};
        std::copy_n(loadOps, 7, selectedLoad);
        selectedLoad[0].reg = result;
        MicroInstrOperand selectedCompare[3] = {};
        selectedCompare[0].reg    = result;
        selectedCompare[1].reg    = fallback;
        selectedCompare[2].opBits = cmp[4].opBits;
        MicroInstrOperand selectedMove[4] = {};
        selectedMove[0].reg     = result;
        selectedMove[1].reg     = fallback;
        selectedMove[2].cpuCond = jumpOps[0].cpuCond;
        selectedMove[3].opBits  = cmp[4].opBits;
        ctx.emitRewrite(initRef, MicroInstrOpcode::LoadAmcRegMem, selectedLoad, true);
        ctx.emitRewrite(cmpRef, MicroInstrOpcode::CmpRegReg, selectedCompare);
        ctx.emitRewrite(jumpRef, MicroInstrOpcode::LoadCondRegReg, selectedMove, true);
        ctx.emitErase(loadRef);
        ctx.emitErase(copyRef);
        return true;
    }

    // A signed comparison with zero only asks for the loaded value's sign
    // bit. Read that bit directly instead of materializing flags and setcc:
    //
    //     cmp [base + index*scale + disp], 0
    //     setl B                              -> load R, [base + index*scale + disp]
    //     zero_extend R, B                       shr  R, bits - 1
    //
    // The result width deliberately matches the compared width here. Wider
    // and narrower casts keep their existing explicit extension so this rule
    // does not change how their upper bits are represented in the micro IR.
    bool tryFoldIndexedSignBit(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst)
    {
        if (ctx.isClaimed(cmpRef) || !ctx.ssa || cmpInst.op != MicroInstrOpcode::CmpAmcImm)
            return false;

        const MicroInstrOperand* cmpOps = cmpInst.ops(*ctx.operands);
        if (!cmpOps || (cmpOps[2].opBits != MicroOpBits::B32 && cmpOps[2].opBits != MicroOpBits::B64) ||
            cmpOps[6].hasWideImmediateValue() || cmpOps[6].valueU64 != 0)
            return false;

        const MicroInstrRef setRef = ctx.storage->findNextInstructionRef(cmpRef);
        const MicroInstr*   set    = setRef.isValid() ? ctx.storage->ptr(setRef) : nullptr;
        if (!set || set->op != MicroInstrOpcode::SetCondReg)
            return false;
        const MicroInstrOperand* setOps = set->ops(*ctx.operands);
        if (!setOps || setOps[1].cpuCond != MicroCond::Less || !setOps[0].reg.isVirtualInt() ||
            !valueHasSingleUse(*ctx.ssa, setOps[0].reg, setRef))
            return false;

        const MicroInstrRef extendRef = ctx.storage->findNextInstructionRef(setRef);
        const MicroInstr*   extend    = extendRef.isValid() ? ctx.storage->ptr(extendRef) : nullptr;
        if (!extend || extend->op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;
        const MicroInstrOperand* extendOps = extend->ops(*ctx.operands);
        if (!extendOps || extendOps[1].reg != setOps[0].reg || extendOps[2].opBits != cmpOps[2].opBits ||
            extendOps[3].opBits != MicroOpBits::B8 || !extendOps[0].reg.isVirtualInt() ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, setRef, ctx.builder) ||
            !ctx.claimAll({cmpRef, setRef, extendRef}))
            return false;

        MicroInstrOperand loadOps[7];
        loadOps[0]        = extendOps[0];
        loadOps[1]        = cmpOps[0];
        loadOps[2]        = cmpOps[1];
        loadOps[3].opBits = cmpOps[2].opBits;
        loadOps[4]        = cmpOps[3];
        loadOps[5]        = cmpOps[4];
        loadOps[6]        = cmpOps[5];

        MicroInstrOperand shiftOps[4];
        shiftOps[0]          = extendOps[0];
        shiftOps[1]          = cmpOps[2];
        shiftOps[2].microOp  = MicroOp::ShiftRight;
        shiftOps[3].valueU64 = getNumBits(cmpOps[2].opBits) - 1;

        ctx.emitRewrite(cmpRef, MicroInstrOpcode::LoadAmcRegMem, loadOps, /*allocNewBlock=*/true);
        ctx.emitRewrite(setRef, MicroInstrOpcode::OpBinaryRegImm, shiftOps, /*allocNewBlock=*/true);
        ctx.emitErase(extendRef);
        return true;
    }

    // For an unsigned saturating sum, `left <= MAX - right` is exactly the
    // absence of carry from `left + right`. The addition already sits next to
    // the select by the time this rule runs, so its flags can replace the
    // explicit limit calculation and comparison:
    //
    //     limit = MAX - right              sum = left
    //     result = MAX                     sum += right
    //     sum = left                ->     cmovae result, sum
    //     sum += right
    //     cmp left, limit
    //     cmovbe result, sum
    //
    // Dead-code elimination removes the now-unused limit chain.
    bool tryReuseSaturatingAddFlags(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst)
    {
        if (ctx.isClaimed(cmpRef) || !ctx.ssa || cmpInst.op != MicroInstrOpcode::CmpRegReg)
            return false;

        const MicroInstrOperand* cmpOps = cmpInst.ops(*ctx.operands);
        if (!cmpOps || (cmpOps[2].opBits != MicroOpBits::B32 && cmpOps[2].opBits != MicroOpBits::B64))
            return false;
        const MicroOpBits bits = cmpOps[2].opBits;

        const MicroInstrRef selectRef = ctx.storage->findNextInstructionRef(cmpRef);
        const MicroInstr*   select    = selectRef.isValid() ? ctx.storage->ptr(selectRef) : nullptr;
        if (!select || select->op != MicroInstrOpcode::LoadCondRegReg)
            return false;
        const MicroInstrOperand* selectOps = select->ops(*ctx.operands);
        if (!selectOps || selectOps[2].cpuCond != MicroCond::BelowOrEqual || selectOps[3].opBits != bits ||
            !selectOps[0].reg.isVirtualInt() || !selectOps[1].reg.isVirtualInt())
            return false;

        const MicroSsaState::ReachingDef sumDef = ctx.ssa->reachingDef(selectOps[1].reg, selectRef);
        if (!sumDef.valid() || sumDef.isPhi || !sumDef.inst || sumDef.inst->op != MicroInstrOpcode::OpBinaryRegReg ||
            sumDef.instRef != ctx.storage->findPreviousInstructionRef(cmpRef))
            return false;
        const MicroInstrOperand* addOps = sumDef.inst->ops(*ctx.operands);
        if (!addOps || addOps[0].reg != selectOps[1].reg || addOps[2].opBits != bits || addOps[3].microOp != MicroOp::Add)
            return false;

        const MicroSsaState::ReachingDef sumInput = ctx.ssa->reachingDef(addOps[0].reg, sumDef.instRef);
        if (!sumInput.valid() || sumInput.isPhi || !sumInput.inst || sumInput.inst->op != MicroInstrOpcode::LoadRegReg)
            return false;
        const MicroInstrOperand* copyOps = sumInput.inst->ops(*ctx.operands);
        if (!copyOps || copyOps[0].reg != addOps[0].reg || copyOps[1].reg != cmpOps[0].reg ||
            getNumBits(copyOps[2].opBits) < getNumBits(bits) || !sameValueAt(ctx, cmpOps[0].reg, sumInput.instRef, cmpRef))
            return false;

        const MicroSsaState::ReachingDef limitDef = ctx.ssa->reachingDef(cmpOps[1].reg, cmpRef);
        if (!limitDef.valid() || limitDef.isPhi || !limitDef.inst || limitDef.inst->op != MicroInstrOpcode::OpBinaryRegReg)
            return false;
        const MicroInstrOperand* subOps = limitDef.inst->ops(*ctx.operands);
        if (!subOps || subOps[0].reg != cmpOps[1].reg || subOps[1].reg != addOps[1].reg || subOps[2].opBits != bits ||
            subOps[3].microOp != MicroOp::Subtract || !sameValueAt(ctx, addOps[1].reg, limitDef.instRef, sumDef.instRef))
            return false;

        const MicroSsaState::ReachingDef limitInput = ctx.ssa->reachingDef(subOps[0].reg, limitDef.instRef);
        const MicroSsaState::ReachingDef fallback   = ctx.ssa->reachingDef(selectOps[0].reg, selectRef);
        if (!isAllOnesLoad(limitInput, *ctx.operands, bits) || !isAllOnesLoad(fallback, *ctx.operands, bits) ||
            !MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, selectRef, ctx.builder) ||
            !ctx.claimAll({sumDef.instRef, cmpRef, selectRef}))
            return false;

        MicroInstrOperand rewritten[4] = {selectOps[0], selectOps[1], selectOps[2], selectOps[3]};
        rewritten[2].cpuCond           = MicroCond::AboveOrEqual;
        ctx.emitErase(cmpRef);
        ctx.emitRewrite(selectRef, MicroInstrOpcode::LoadCondRegReg, rewritten);
        return true;
    }

    // A min/max select does not need a separate result register when one
    // compared operand dies at the select:
    //
    //     result = left                  cmp left, right
    //     cmp left, right       ->        cmov!CC right, left
    //     cmovCC result, right
    //
    //                                   result = right
    //
    // SSA proves that right's previous value has no observer other than this
    // compare/select pair and that the register is not redefined before any
    // consumer of the result, so copy elimination then renames them to
    // `right`. Renaming them here would miss a reader another rule of the
    // same sweep forwards onto `result`, which would then read the register
    // the erased copy no longer writes.
    bool tryReuseCompareOperandForSelect(Context& ctx, MicroInstrRef selectRef, const MicroInstr& selectInst)
    {
        if (ctx.isClaimed(selectRef) || !ctx.ssa || selectInst.op != MicroInstrOpcode::LoadCondRegReg)
            return false;
        const MicroInstrOperand* selectOps = selectInst.ops(*ctx.operands);
        if (!selectOps || !selectOps[0].reg.isVirtualInt() || !selectOps[1].reg.isVirtualInt() ||
            (selectOps[3].opBits != MicroOpBits::B32 && selectOps[3].opBits != MicroOpBits::B64))
            return false;

        const MicroReg    result = selectOps[0].reg;
        const MicroReg    right  = selectOps[1].reg;
        const MicroOpBits bits   = selectOps[3].opBits;
        if (result == right)
            return false;

        const MicroInstrRef cmpRef = ctx.storage->findPreviousInstructionRef(selectRef);
        const MicroInstr*   cmp    = cmpRef.isValid() ? ctx.storage->ptr(cmpRef) : nullptr;
        const MicroInstrOperand* cmpOps = cmp && cmp->op == MicroInstrOpcode::CmpRegReg ? cmp->ops(*ctx.operands) : nullptr;
        if (!cmpOps || cmpOps[1].reg != right || cmpOps[2].opBits != bits || !cmpOps[0].reg.isVirtualInt())
            return false;
        const MicroReg left = cmpOps[0].reg;
        if (left == right || left == result)
            return false;

        const MicroInstrRef copyRef = ctx.storage->findPreviousInstructionRef(cmpRef);
        const MicroInstr*   copy    = copyRef.isValid() ? ctx.storage->ptr(copyRef) : nullptr;
        const MicroInstrOperand* copyOps = copy && copy->op == MicroInstrOpcode::LoadRegReg ? copy->ops(*ctx.operands) : nullptr;
        if (!copyOps || copyOps[0].reg != result || copyOps[1].reg != left || getNumBits(copyOps[2].opBits) < getNumBits(bits) ||
            !valueHasSingleUse(*ctx.ssa, result, copyRef))
            return false;

        const MicroSsaState::ReachingDef rightValue = ctx.ssa->reachingDef(right, cmpRef);
        if (!rightValue.valid() || rightValue.isPhi || ctx.ssa->transitiveInstructionUseCount(rightValue.valueId, 3) != 2)
            return false;
        const MicroSsaState::ValueInfo* rightInfo = ctx.ssa->valueInfo(rightValue.valueId);
        if (!rightInfo)
            return false;
        for (const MicroSsaState::UseSite& use : rightInfo->uses)
        {
            if (use.kind != MicroSsaState::UseSite::Kind::Instruction || (use.instRef != cmpRef && use.instRef != selectRef))
                return false;
        }

        uint32_t resultValueId = 0;
        if (!ctx.ssa->defValue(result, selectRef, resultValueId))
            return false;
        const MicroSsaState::ValueInfo* resultInfo = ctx.ssa->valueInfo(resultValueId);
        if (!resultInfo || resultInfo->uses.empty())
            return false;

        SmallVector<MicroInstrRef, 8> uses;
        for (const MicroSsaState::UseSite& use : resultInfo->uses)
        {
            if (use.kind != MicroSsaState::UseSite::Kind::Instruction || ctx.isClaimed(use.instRef) || ctx.isRelocated(use.instRef) ||
                ctx.ssa->reachingDef(right, use.instRef).valueId != rightValue.valueId)
                return false;
            if (std::ranges::find(uses, use.instRef) == uses.end())
                uses.push_back(use.instRef);
        }

        for (const MicroInstrRef useRef : uses)
        {
            MicroInstr* useInst = ctx.storage->ptr(useRef);
            if (!useInst || useInst->numOperands > Action::K_MAX_OPS)
                return false;
            SmallVector<MicroInstrRegOperandRef> regOperands;
            useInst->collectRegOperands(*ctx.operands, regOperands, nullptr);
            bool found = false;
            for (const MicroInstrRegOperandRef& regOperand : regOperands)
            {
                if (!regOperand.reg || *regOperand.reg != result)
                    continue;
                if (!regOperand.use || regOperand.def)
                    return false;
                found = true;
            }
            if (!found)
                return false;
        }

        const MicroInstrRef nextRef = ctx.storage->findNextInstructionRef(selectRef);
        MicroCond           inverted = MicroCond::Unconditional;
        if (!nextRef.isValid() || !MicroPassHelpers::invertCondition(inverted, selectOps[2].cpuCond) ||
            !ctx.claimAll({copyRef, cmpRef, selectRef, nextRef}))
            return false;

        MicroInstrOperand rewrittenSelect[4];
        rewrittenSelect[0].reg     = right;
        rewrittenSelect[1].reg     = left;
        rewrittenSelect[2].cpuCond = inverted;
        rewrittenSelect[3].opBits  = bits;
        MicroInstrOperand resultCopy[3];
        resultCopy[0].reg    = result;
        resultCopy[1].reg    = right;
        resultCopy[2].opBits = MicroOpBits::B64;
        ctx.emitErase(copyRef);
        ctx.emitRewrite(selectRef, MicroInstrOpcode::LoadCondRegReg, rewrittenSelect);
        ctx.emitInsertBefore(nextRef, MicroInstrOpcode::LoadRegReg, resultCopy);
        return true;
    }

    // `a > b ? a - b : b - a` computes `a - b` before the compare that the
    // select reads, and a subtraction sets the flags of that very compare:
    //
    //     T = a; T -= b                      U = b; U -= a
    //     U = b; U -= a              ->      T = a; T -= b
    //     cmp a, b                           cmovbe T, U
    //     cmovbe T, U
    //
    // Moving the subtraction next to the reader drops the compare, as LLVM's
    // x86 lowering reuses the flags of a `sub` for its `cmp`. Nothing between
    // may read T or the flags, and a and b must hold the same values at both
    // places.
    bool tryReuseSubtractionFlags(Context& ctx, MicroInstrRef ref, const MicroInstr& inst)
    {
        constexpr uint32_t K_MAX_WINDOW = 6;

        if (ctx.isClaimed(ref) || !ctx.ssa)
            return false;

        const MicroInstrOperand* ops   = inst.ops(*ctx.operands);
        const MicroReg           left  = ops[0].reg;
        const MicroReg           right = ops[1].reg;
        const MicroOpBits        bits  = ops[2].opBits;
        if (!left.isVirtualInt() || !right.isVirtualInt() || left == right)
            return false;

        // The reader right after the compare, and nothing after it that reads
        // the flags a subtraction would leave different.
        const MicroInstrRef readerRef = ctx.storage->findNextInstructionRef(ref);
        const MicroInstr*   reader    = readerRef.isValid() ? ctx.storage->ptr(readerRef) : nullptr;
        if (!reader || (reader->op != MicroInstrOpcode::LoadCondRegReg && reader->op != MicroInstrOpcode::SetCondReg && reader->op != MicroInstrOpcode::JumpCond))
            return false;

        // Walk back to `sub T, right` whose T held `left`.
        SmallVector<MicroInstrRef, 8> between;
        MicroInstrRef                 subRef = ctx.storage->findPreviousInstructionRef(ref);
        for (uint32_t step = 0; step < K_MAX_WINDOW && subRef.isValid(); ++step)
        {
            const MicroInstr* candidate = ctx.storage->ptr(subRef);
            if (!candidate)
                return false;
            const MicroInstrOperand* candidateOps = candidate->ops(*ctx.operands);
            if (candidate->op == MicroInstrOpcode::OpBinaryRegReg && candidateOps[3].microOp == MicroOp::Subtract &&
                candidateOps[1].reg == right && candidateOps[2].opBits == bits && candidateOps[0].reg.isVirtualInt() &&
                candidateOps[0].reg != left && candidateOps[0].reg != right)
                break;
            if (candidate->op == MicroInstrOpcode::Label || MicroPassHelpers::instructionActuallyUsesCpuFlags(*candidate, candidateOps))
                return false;
            const MicroInstrFlags flags = MicroInstr::info(candidate->op).flags;
            if (flags.has(MicroInstrFlagsE::JumpInstruction) || flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;
            between.push_back(subRef);
            subRef = ctx.storage->findPreviousInstructionRef(subRef);
        }
        if (!subRef.isValid() || between.size() >= K_MAX_WINDOW || ctx.isClaimed(subRef))
            return false;

        const MicroInstr*        sub    = ctx.storage->ptr(subRef);
        const MicroInstrOperand* subOps = sub->ops(*ctx.operands);
        if (sub->op != MicroInstrOpcode::OpBinaryRegReg || subOps[3].microOp != MicroOp::Subtract || subOps[1].reg != right)
            return false;
        const MicroReg result = subOps[0].reg;

        // T = left right before the subtraction.
        const MicroInstrRef copyRef = ctx.storage->findPreviousInstructionRef(subRef);
        const MicroInstr*   copy    = copyRef.isValid() ? ctx.storage->ptr(copyRef) : nullptr;
        if (!copy || copy->op != MicroInstrOpcode::LoadRegReg || ctx.isClaimed(copyRef))
            return false;
        const MicroInstrOperand* copyOps = copy->ops(*ctx.operands);
        if (copyOps[0].reg != result || copyOps[1].reg != left || getNumBits(copyOps[2].opBits) < getNumBits(bits))
            return false;

        // left and right keep their values, and the moved pair's register is
        // not touched in between.
        const auto sameValue = [&](MicroReg reg, MicroInstrRef earlier) {
            const MicroSsaState::ReachingDef before = ctx.ssa->reachingDef(reg, earlier);
            const MicroSsaState::ReachingDef after  = ctx.ssa->reachingDef(reg, ref);
            return before.valid() && after.valid() && before.valueId == after.valueId;
        };
        if (!sameValue(left, copyRef) || !sameValue(right, subRef))
            return false;
        // Copies of T move along with it; nothing else in between may mention
        // T or those copies.
        SmallVector<MicroInstrRef, 4>        followers;
        SmallVector<MicroReg, 4>             followerRegs;
        SmallVector<MicroInstrRegOperandRef> regOperands;
        for (const MicroInstrRef betweenRef : between)
        {
            const MicroInstr*        betweenInst = ctx.storage->ptr(betweenRef);
            const MicroInstrOperand* betweenOps  = betweenInst->ops(*ctx.operands);
            if (betweenInst->op == MicroInstrOpcode::LoadRegReg && betweenOps[1].reg == result && betweenOps[0].reg.isVirtualInt() &&
                betweenOps[0].reg != left && betweenOps[0].reg != right && getNumBits(betweenOps[2].opBits) >= getNumBits(bits) &&
                !ctx.isClaimed(betweenRef))
            {
                followers.push_back(betweenRef);
                followerRegs.push_back(betweenOps[0].reg);
            }
        }
        for (const MicroInstrRef betweenRef : between)
        {
            if (std::ranges::find(followers, betweenRef) != followers.end())
                continue;
            const MicroInstr* betweenInst = ctx.storage->ptr(betweenRef);
            regOperands.clear();
            betweenInst->collectRegOperands(*ctx.operands, regOperands, nullptr);
            for (const MicroInstrRegOperandRef& regOperand : regOperands)
            {
                if (regOperand.reg && (*regOperand.reg == result || std::ranges::find(followerRegs, *regOperand.reg) != followerRegs.end()))
                    return false;
            }
        }

        if (!MicroPassHelpers::areCpuFlagsDeadAfter(*ctx.storage, *ctx.operands, readerRef, ctx.builder))
            return false;
        if (!ctx.claimAll({ref, subRef, copyRef, readerRef}))
            return false;

        MicroInstrOperand movedCopy[3];
        for (size_t i = 0; i < 3; ++i)
            movedCopy[i] = copyOps[i];
        MicroInstrOperand movedSub[4];
        for (size_t i = 0; i < 4; ++i)
            movedSub[i] = subOps[i];
        for (const MicroInstrRef followerRef : followers)
        {
            if (!ctx.claimAll({followerRef}))
                return false;
        }

        ctx.emitErase(copyRef);
        ctx.emitErase(subRef);
        ctx.emitInsertBefore(ref, MicroInstrOpcode::LoadRegReg, movedCopy);
        ctx.emitInsertBefore(ref, MicroInstrOpcode::OpBinaryRegReg, movedSub);
        // `between` runs backwards: the copies go back in their order.
        for (auto it = followers.rbegin(); it != followers.rend(); ++it)
        {
            const MicroInstrOperand* followerOps = ctx.storage->ptr(*it)->ops(*ctx.operands);
            MicroInstrOperand        movedFollower[3];
            for (size_t i = 0; i < 3; ++i)
                movedFollower[i] = followerOps[i];
            ctx.emitInsertBefore(ref, MicroInstrOpcode::LoadRegReg, movedFollower);
            ctx.emitErase(*it);
        }
        ctx.emitErase(ref);
        return true;
    }
}

SWC_END_NAMESPACE();
