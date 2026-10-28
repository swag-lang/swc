#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroOptimizationLimits.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/Passes/Pass.InstructionCombine.Internal.h"

// Compares: flags an earlier instruction already produced reused instead of
// computed again, and known values folded into the compared operand.

SWC_BEGIN_NAMESPACE();

namespace InstructionCombine
{
    namespace
    {
        bool isAllOnesLoad(const MicroSsaState::ReachingDef& def, const MicroOperandStorage& operands, MicroOpBits bits)
        {
            if (!def.valid() || def.isPhi || !def.inst || def.inst->op != MicroInstrOpcode::LoadRegImm)
                return false;
            const MicroInstrOperand* ops = def.inst->ops(operands);
            return ops && ops[1].opBits == bits && !ops[2].hasWideImmediateValue() &&
                   (ops[2].valueU64 & getBitsMask(bits)) == getBitsMask(bits);
        }
    }

    // Whole-vector equality is an XOR followed by a zero test. Work on the
    // SSA values before allocation so a later setcc reusing the mask register
    // cannot make its dead upper bytes look like another mask observation.
    bool tryFoldVectorEqualityMask(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst)
    {
        if (!ctx.ssa || ctx.isClaimed(cmpRef))
            return false;
        const auto* cmp = cmpInst.ops(*ctx.operands);
        if (!cmp || !cmp[0].reg.isVirtualInt() || cmp[1].opBits != MicroOpBits::B32 ||
            cmp[2].hasWideImmediateValue() || cmp[2].valueU64 != 0xFFFF)
            return false;
        const MicroInstrRef readerRef = ctx.storage->findNextInstructionRef(cmpRef);
        const MicroInstr*   reader    = ctx.storage->ptr(readerRef);
        const auto*         readerOps = reader ? reader->ops(*ctx.operands) : nullptr;
        if (!reader || !readerOps || (reader->op != MicroInstrOpcode::SetCondReg && reader->op != MicroInstrOpcode::JumpCond))
            return false;
        const MicroCond condition = readerOps[reader->op == MicroInstrOpcode::SetCondReg ? 1 : 0].cpuCond;
        if ((condition != MicroCond::Equal && condition != MicroCond::NotEqual && condition != MicroCond::Zero && condition != MicroCond::NotZero) ||
            !ctx.areCpuFlagsDeadAfter(readerRef))
            return false;
        const auto extracted = ctx.ssa->reachingDef(cmp[0].reg, cmpRef);
        const auto* move     = extracted.inst ? extracted.inst->ops(*ctx.operands) : nullptr;
        if (!extracted.valid() || extracted.isPhi || !extracted.inst || extracted.inst->op != MicroInstrOpcode::VecUnaryRegReg ||
            extracted.instRef != ctx.storage->findPreviousInstructionRef(cmpRef) ||
            ctx.ssa->transitiveInstructionUseCount(extracted.valueId, 2) != 1 || !move || move[2].opBits != MicroOpBits::B128 ||
            move[3].microOp != MicroOp::VecMoveMaskB)
            return false;
        const auto compared = ctx.ssa->reachingDef(move[1].reg, extracted.instRef);
        const auto* vector  = compared.inst ? compared.inst->ops(*ctx.operands) : nullptr;
        if (!compared.valid() || compared.isPhi || !compared.inst || compared.inst->op != MicroInstrOpcode::OpBinaryRegRegReg ||
            ctx.ssa->transitiveInstructionUseCount(compared.valueId, 2) != 1 || !vector || vector[3].opBits != MicroOpBits::B128 ||
            (vector[4].microOp != MicroOp::VecCmpEq8 && vector[4].microOp != MicroOp::VecCmpEq16 &&
             vector[4].microOp != MicroOp::VecCmpEq32 && vector[4].microOp != MicroOp::VecCmpEq64) ||
            !ctx.claimAll({compared.instRef, extracted.instRef, cmpRef}))
            return false;
        MicroInstrOperand xorOps[5];
        std::copy_n(vector, 5, xorOps);
        xorOps[4].microOp = MicroOp::VecXor;
        MicroInstrOperand testOps[2] = {};
        testOps[0].reg    = move[1].reg;
        testOps[1].opBits = MicroOpBits::B128;
        ctx.emitRewrite(compared.instRef, MicroInstrOpcode::OpBinaryRegRegReg, xorOps);
        ctx.emitRewrite(extracted.instRef, MicroInstrOpcode::VecTestReg, testOps);
        ctx.emitErase(cmpRef);
        return true;
    }

    // A word comparison produces two identical byte sign bits per lane.
    // Testing every high-byte bit is therefore the same as testing all 16
    // movemask bits, provided the masked value is not otherwise observed.
    bool tryFoldWordCompareMask(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst)
    {
        if (!ctx.ssa || ctx.isClaimed(cmpRef))
            return false;
        const auto* cmp = cmpInst.ops(*ctx.operands);
        if (!cmp || !cmp[0].reg.isVirtualInt() || cmp[1].opBits != MicroOpBits::B32 ||
            cmp[2].hasWideImmediateValue() || cmp[2].valueU64 != 0xAAAA)
            return false;
        MicroStorage::Iterator cursor{ctx.storage, cmpRef};
        auto                   next = cursor;
        ++next;
        const MicroInstrRef setRef = next.current;
        const MicroInstr*   set    = setRef.isValid() ? &*next : nullptr;
        const auto*         setOps = set ? set->ops(*ctx.operands) : nullptr;
        if (!set || set->op != MicroInstrOpcode::SetCondReg || !setOps ||
            (setOps[1].cpuCond != MicroCond::Equal && setOps[1].cpuCond != MicroCond::NotEqual &&
             setOps[1].cpuCond != MicroCond::Zero && setOps[1].cpuCond != MicroCond::NotZero) ||
            !ctx.areCpuFlagsDeadAfter(setRef))
            return false;
        const auto masked = ctx.ssa->reachingDef(cmp[0].reg, cmpRef);
        auto previous = cursor;
        --previous;
        if (!masked.valid() || masked.isPhi || !masked.inst || masked.inst->op != MicroInstrOpcode::OpBinaryRegImm ||
            masked.instRef != previous.current || ctx.ssa->transitiveInstructionUseCount(masked.valueId, 2) != 1)
            return false;
        const auto* mask = masked.inst->ops(*ctx.operands);
        if (!mask || mask[0].reg != cmp[0].reg || mask[1].opBits != MicroOpBits::B32 || mask[2].microOp != MicroOp::And ||
            mask[3].hasWideImmediateValue() || mask[3].valueU64 != 0xAAAA)
            return false;
        const auto extracted = ctx.ssa->reachingDef(mask[0].reg, masked.instRef);
        const auto* move = extracted.inst ? extracted.inst->ops(*ctx.operands) : nullptr;
        if (!extracted.valid() || extracted.isPhi || !extracted.inst || extracted.inst->op != MicroInstrOpcode::VecUnaryRegReg ||
            !move || move[2].opBits != MicroOpBits::B128 || move[3].microOp != MicroOp::VecMoveMaskB)
            return false;
        const auto compared = ctx.ssa->reachingDef(move[1].reg, extracted.instRef);
        const auto* vector = compared.inst ? compared.inst->ops(*ctx.operands) : nullptr;
        if (!compared.valid() || compared.isPhi || !compared.inst || compared.inst->op != MicroInstrOpcode::OpBinaryRegRegReg ||
            !vector || vector[3].opBits != MicroOpBits::B128 ||
            (vector[4].microOp != MicroOp::VecCmpEq16 && vector[4].microOp != MicroOp::VecCmpGtS16))
            return false;
        if (!ctx.claimAll({masked.instRef, cmpRef}))
            return false;
        MicroInstrOperand rewritten[3] = {cmp[0], cmp[1], cmp[2]};
        rewritten[2].setImmediateValue(ApInt(0xFFFF, 32));
        ctx.emitErase(masked.instRef);
        ctx.emitRewrite(cmpRef, MicroInstrOpcode::CmpRegImm, rewritten);
        return true;
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
        const auto     def    = ctx.ssa->reachingDef(copied, cmpRef);
        if (!def.valid() || def.isPhi || !def.inst || def.inst->op != MicroInstrOpcode::LoadRegReg ||
            ctx.isClaimed(def.instRef) || ctx.isRelocated(def.instRef))
            return false;
        const auto* copy = def.inst->ops(*ctx.operands);
        if (!copy || copy[0].reg != copied || copy[2].opBits != MicroOpBits::B8 || !copy[1].reg.isVirtualInt() ||
            copy[1].reg == cmp[0].reg || copy[1].reg == cmp[1].reg ||
            ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
            return false;
        if (!ctx.ssa->sameValueAt(copy[1].reg, def.instRef, cmpRef) ||
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

        MicroStorage::Iterator patternIt{ctx.storage, cmpRef};
        auto                   initIt = patternIt;
        --initIt;
        if (!initIt.current.isValid() || initIt->op != MicroInstrOpcode::LoadRegReg)
            return false;
        const MicroInstrRef initRef = initIt.current;
        const MicroInstr*   init    = &*initIt;

        ++patternIt;
        if (!patternIt.current.isValid() || patternIt->op != MicroInstrOpcode::JumpCond)
            return false;
        const MicroInstrRef jumpRef = patternIt.current;
        const MicroInstr*   jump    = &*patternIt;
        ++patternIt;
        if (!patternIt.current.isValid() || patternIt->op != MicroInstrOpcode::LoadAmcRegMem)
            return false;
        const MicroInstrRef loadRef = patternIt.current;
        const MicroInstr*   load    = &*patternIt;
        ++patternIt;
        if (!patternIt.current.isValid() || patternIt->op != MicroInstrOpcode::LoadRegReg)
            return false;
        const MicroInstrRef copyRef = patternIt.current;
        const MicroInstr*   copy    = &*patternIt;
        ++patternIt;
        if (!patternIt.current.isValid() || patternIt->op != MicroInstrOpcode::Label)
            return false;
        const MicroInstrRef      labelRef = patternIt.current;
        const MicroInstr*        label    = &*patternIt;
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
        if (!ctx.ssa->sameValueAt(cmp[0].reg, cmpRef, loadRef) ||
            !ctx.ssa->sameValueAt(cmp[1].reg, cmpRef, loadRef) ||
            !ctx.ssa->sameValueAt(fallback, initRef, cmpRef))
            return false;
        uint32_t tempValue = 0;
        if (!ctx.ssa->defValue(temp, loadRef, tempValue) || singleDirectInstructionUse(*ctx.ssa, tempValue) != copyRef ||
            !ctx.claimAll({initRef, cmpRef, jumpRef, loadRef, copyRef}))
            return false;

        MicroInstrOperand selectedLoad[7] = {};
        std::copy_n(loadOps, 7, selectedLoad);
        selectedLoad[0].reg                  = result;
        MicroInstrOperand selectedCompare[3] = {};
        selectedCompare[0].reg               = result;
        selectedCompare[1].reg               = fallback;
        selectedCompare[2].opBits            = cmp[4].opBits;
        MicroInstrOperand selectedMove[4]    = {};
        selectedMove[0].reg                  = result;
        selectedMove[1].reg                  = fallback;
        selectedMove[2].cpuCond              = jumpOps[0].cpuCond;
        selectedMove[3].opBits               = cmp[4].opBits;
        ctx.emitRewrite(initRef, MicroInstrOpcode::LoadAmcRegMem, selectedLoad, true);
        ctx.emitRewrite(cmpRef, MicroInstrOpcode::CmpRegReg, selectedCompare);
        ctx.emitRewrite(jumpRef, MicroInstrOpcode::LoadCondRegReg, selectedMove, true);
        ctx.emitErase(loadRef);
        ctx.emitErase(copyRef);
        return true;
    }

    namespace
    {
        // Walk backwards from the reload to the comparison. Every incoming
        // path must reach that read before a write or call, including paths
        // around nested read-only scans. A path outside the bounded region
        // declines the rewrite rather than assuming that it is unreachable.
        bool hasUnchangedComparedMemory(const Context& ctx, MicroInstrRef cmpRef, MicroInstrRef loadRef)
        {
            const MicroControlFlowGraph& cfg = ctx.builder->controlFlowGraph();
            if (cfg.hasUnsupportedControlFlowForCfgLiveness() || !cfg.supportsDeadCodeLiveness())
                return false;
            const uint32_t first = cfg.indexOf(cmpRef);
            const uint32_t last  = cfg.indexOf(loadRef);
            if (first >= last || last - first > MicroOptimizationLimits::InstructionCombineCompare::K_MAX_RELOAD_SCAN)
                return false;
            SmallVector<uint32_t> pending;
            SmallVector<uint32_t> visited;
            for (const uint32_t predecessor : cfg.predecessors(last))
                pending.push_back(predecessor);
            if (pending.empty())
                return false;
            const auto refs = cfg.instructionRefs();
            while (!pending.empty())
            {
                const uint32_t index = pending.back();
                pending.pop_back();
                if (index == first)
                    continue;
                if (index < first || index >= last)
                    return false;
                // A materialized label can be entered without following the
                // explicit CFG predecessors, bypassing the compared read.
                const auto addressTaken = cfg.addressTakenLabelIndices();
                if (std::ranges::find(addressTaken, index) != addressTaken.end())
                    return false;
                if (std::ranges::find(visited, index) != visited.end())
                    continue;
                visited.push_back(index);
                const MicroInstr* inst = ctx.storage->ptr(refs[index]);
                if (!inst || ctx.isClaimed(refs[index]))
                    return false;
                const MicroInstrDef& info = MicroInstr::info(inst->op);
                if (info.flags.has(MicroInstrFlagsE::WritesMemory) || info.flags.has(MicroInstrFlagsE::IsCallInstruction) || cfg.predecessors(index).empty())
                    return false;
                for (const uint32_t predecessor : cfg.predecessors(index))
                    pending.push_back(predecessor);
            }
            return true;
        }
    }

    // A compare followed by a branch may already have read the exact indexed
    // cell loaded on the fallthrough path. Load it into a fresh value before
    // the compare and let register allocation coalesce the fallthrough copy.
    bool tryReuseComparedIndexedLoad(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst)
    {
        if (ctx.isClaimed(cmpRef) || cmpInst.op != MicroInstrOpcode::CmpAmcReg)
            return false;
        const MicroInstrOperand* cmp = cmpInst.ops(*ctx.operands);
        if (!cmp || cmp[3].opBits != MicroOpBits::B64 ||
            (cmp[4].opBits != MicroOpBits::B32 && cmp[4].opBits != MicroOpBits::B64))
            return false;

        MicroStorage::Iterator patternIt{ctx.storage, cmpRef};
        ++patternIt;
        if (!patternIt.current.isValid() || patternIt->op != MicroInstrOpcode::JumpCond)
            return false;
        const MicroInstrRef      jumpRef = patternIt.current;
        const MicroInstr*        jump    = &*patternIt;
        const MicroInstrOperand* jumpOps = jump->ops(*ctx.operands);
        if (!jumpOps || jumpOps[0].cpuCond == MicroCond::Unconditional || !cmp[2].reg.isVirtualInt())
            return false;

        MicroInstrRef            loadRef = MicroInstrRef::invalid();
        const MicroInstrOperand* loadOps = nullptr;
        for (uint32_t distance = 0; distance < MicroOptimizationLimits::InstructionCombineCompare::K_MAX_RELOAD_SCAN; ++distance)
        {
            ++patternIt;
            if (!patternIt.current.isValid())
                break;
            if (patternIt->op != MicroInstrOpcode::LoadAmcRegMem)
                continue;
            const auto* candidate = patternIt->ops(*ctx.operands);
            if (!candidate || candidate[2].reg != cmp[1].reg ||
                candidate[3].opBits != cmp[4].opBits || candidate[4].opBits != cmp[3].opBits ||
                candidate[5].valueU64 != cmp[5].valueU64 || candidate[6].valueU64 != cmp[6].valueU64 ||
                !candidate[0].reg.isVirtualInt())
                continue;
            if (candidate[1].reg != cmp[0].reg)
            {
                if (!ctx.ssa)
                    continue;
                const auto  base = ctx.ssa->reachingDef(candidate[1].reg, patternIt.current);
                const auto* copy = base.valid() && !base.isPhi && base.inst && base.inst->op == MicroInstrOpcode::LoadRegReg ? base.inst->ops(*ctx.operands) : nullptr;
                if (!copy || copy[2].opBits != MicroOpBits::B64 || copy[1].reg != cmp[0].reg ||
                    !ctx.ssa->sameValueAt(cmp[0].reg, cmpRef, base.instRef))
                    continue;
            }
            if (distance && (!ctx.ssa || !ctx.builder ||
                             !ctx.ssa->sameValueAt(cmp[0].reg, cmpRef, patternIt.current) ||
                             !ctx.ssa->sameValueAt(cmp[1].reg, cmpRef, patternIt.current) ||
                             !hasUnchangedComparedMemory(ctx, cmpRef, patternIt.current)))
                continue;
            loadRef = patternIt.current;
            loadOps = candidate;
            break;
        }
        if (!loadRef.isValid() || !ctx.claimAll({cmpRef, jumpRef, loadRef}))
            return false;

        ctx.ensureVirtualIndices();
        const MicroReg    saved        = MicroReg::virtualIntReg(ctx.nextVirtualIntRegIndex++);
        MicroInstrOperand earlyLoad[7] = {};
        std::copy_n(loadOps, 7, earlyLoad);
        earlyLoad[0].reg = saved;
        // A copied load base may only be defined after the comparison.
        // Materialize the read through the address the comparison itself used.
        earlyLoad[1]                 = cmp[0];
        earlyLoad[2]                 = cmp[1];
        MicroInstrOperand compare[3] = {};
        compare[0].reg               = saved;
        compare[1].reg               = cmp[2].reg;
        compare[2].opBits            = cmp[4].opBits;
        MicroInstrOperand copy[3]    = {};
        copy[0].reg                  = loadOps[0].reg;
        copy[1].reg                  = saved;
        copy[2].opBits               = cmp[4].opBits;
        ctx.emitInsertBefore(cmpRef, MicroInstrOpcode::LoadAmcRegMem, earlyLoad);
        ctx.emitRewrite(cmpRef, MicroInstrOpcode::CmpRegReg, compare);
        ctx.emitRewrite(loadRef, MicroInstrOpcode::LoadRegReg, copy);
        return true;
    }

    // Delay a loop index's address-style increment until its old value is no
    // longer needed. The temporary must feed only the copy and its following
    // comparison; both then read the updated index instead.
    bool tryDelayCopiedAddressIncrement(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst)
    {
        if (ctx.isClaimed(copyRef) || !ctx.ssa || copyInst.op != MicroInstrOpcode::LoadRegReg)
            return false;
        const MicroInstrOperand* copy = copyInst.ops(*ctx.operands);
        if (!copy || copy[2].opBits != MicroOpBits::B64 ||
            !copy[0].reg.isVirtualInt() || !copy[1].reg.isVirtualInt() || copy[0].reg == copy[1].reg)
            return false;
        MicroStorage::Iterator patternIt{ctx.storage, copyRef};
        ++patternIt;
        if (!patternIt.current.isValid() || patternIt->op != MicroInstrOpcode::CmpRegReg)
            return false;
        const MicroInstrRef cmpRef  = patternIt.current;
        const MicroInstr*   cmpInst = &*patternIt;
        ++patternIt;
        if (!patternIt.current.isValid() || patternIt->op != MicroInstrOpcode::JumpCond)
            return false;
        const MicroInstrRef      jumpRef  = patternIt.current;
        const MicroInstr*        jumpInst = &*patternIt;
        const MicroInstrOperand* cmp      = cmpInst->ops(*ctx.operands);
        if (!cmp || cmp[2].opBits != MicroOpBits::B64 ||
            (cmp[0].reg != copy[1].reg && cmp[1].reg != copy[1].reg))
            return false;
        const MicroReg other = cmp[0].reg == copy[1].reg ? cmp[1].reg : cmp[0].reg;
        if (other == copy[0].reg || other == copy[1].reg)
            return false;

        const auto address = ctx.ssa->reachingDef(copy[1].reg, copyRef);
        if (!address.valid() || address.isPhi || !address.inst ||
            address.inst->op != MicroInstrOpcode::LoadAddrRegMem || ctx.isClaimed(address.instRef))
            return false;
        const MicroInstrOperand* lea = address.inst->ops(*ctx.operands);
        if (!lea || lea[0].reg != copy[1].reg || lea[1].reg != copy[0].reg ||
            lea[2].opBits != MicroOpBits::B64 || lea[3].hasWideImmediateValue() ||
            !lea[3].valueU64 ||
            static_cast<uint64_t>(static_cast<int64_t>(static_cast<int32_t>(lea[3].valueU64))) != lea[3].valueU64)
            return false;
        if (!ctx.ssa->sameValueAt(copy[0].reg, address.instRef, copyRef))
            return false;
        const auto* value = ctx.ssa->valueInfo(address.valueId);
        if (!value || ctx.ssa->transitiveInstructionUseCount(address.valueId, 3) != 2)
            return false;
        bool usedByCopy    = false;
        bool usedByCompare = false;
        for (const auto& use : value->uses)
        {
            if (use.kind != MicroSsaState::UseSite::Kind::Instruction)
                continue;
            if (use.instRef != copyRef && use.instRef != cmpRef)
                return false;
            usedByCopy |= use.instRef == copyRef;
            usedByCompare |= use.instRef == cmpRef;
        }
        if (!usedByCopy || !usedByCompare || !ctx.claimAll({address.instRef, copyRef, cmpRef}))
            return false;

        MicroInstrOperand increment[4] = {};
        increment[0].reg               = copy[0].reg;
        increment[1].opBits            = MicroOpBits::B64;
        increment[2].microOp           = MicroOp::Add;
        increment[3].valueU64          = lea[3].valueU64;
        MicroInstrOperand compare[3]   = {};
        std::copy_n(cmp, 3, compare);
        if (compare[0].reg == copy[1].reg)
            compare[0].reg = copy[0].reg;
        else
            compare[1].reg = copy[0].reg;
        ctx.emitErase(address.instRef);
        ctx.emitRewrite(copyRef, MicroInstrOpcode::OpBinaryRegImm, increment, true);
        ctx.emitRewrite(cmpRef, MicroInstrOpcode::CmpRegReg, compare);
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

        MicroStorage::Iterator patternIt{ctx.storage, cmpRef};
        ++patternIt;
        if (!patternIt.current.isValid() || patternIt->op != MicroInstrOpcode::SetCondReg)
            return false;
        const MicroInstrRef      setRef = patternIt.current;
        const MicroInstr*        set    = &*patternIt;
        const MicroInstrOperand* setOps = set->ops(*ctx.operands);
        if (!setOps || setOps[1].cpuCond != MicroCond::Less || !setOps[0].reg.isVirtualInt() ||
            !valueHasSingleUse(*ctx.ssa, setOps[0].reg, setRef))
            return false;

        ++patternIt;
        if (!patternIt.current.isValid() || patternIt->op != MicroInstrOpcode::LoadZeroExtRegReg)
            return false;
        const MicroInstrRef      extendRef = patternIt.current;
        const MicroInstr*        extend    = &*patternIt;
        const MicroInstrOperand* extendOps = extend->ops(*ctx.operands);
        if (!extendOps || extendOps[1].reg != setOps[0].reg || extendOps[2].opBits != cmpOps[2].opBits ||
            extendOps[3].opBits != MicroOpBits::B8 || !extendOps[0].reg.isVirtualInt() ||
            !ctx.areCpuFlagsDeadAfter(setRef) ||
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

        MicroStorage::Iterator patternIt{ctx.storage, cmpRef};
        ++patternIt;
        if (!patternIt.current.isValid() || patternIt->op != MicroInstrOpcode::LoadCondRegReg)
            return false;
        const MicroInstrRef      selectRef = patternIt.current;
        const MicroInstr*        select    = &*patternIt;
        const MicroInstrOperand* selectOps = select->ops(*ctx.operands);
        if (!selectOps || selectOps[2].cpuCond != MicroCond::BelowOrEqual || selectOps[3].opBits != bits ||
            !selectOps[0].reg.isVirtualInt() || !selectOps[1].reg.isVirtualInt())
            return false;

        auto previousIt = MicroStorage::Iterator{ctx.storage, cmpRef};
        --previousIt;
        if (!previousIt.current.isValid())
            return false;
        const MicroInstrRef              previousRef = previousIt.current;
        const MicroSsaState::ReachingDef sumDef      = ctx.ssa->reachingDef(selectOps[1].reg, selectRef);
        if (!sumDef.valid() || sumDef.isPhi || !sumDef.inst || sumDef.inst->op != MicroInstrOpcode::OpBinaryRegReg ||
            sumDef.instRef != previousRef)
            return false;
        const MicroInstrOperand* addOps = sumDef.inst->ops(*ctx.operands);
        if (!addOps || addOps[0].reg != selectOps[1].reg || addOps[2].opBits != bits || addOps[3].microOp != MicroOp::Add)
            return false;

        const MicroSsaState::ReachingDef sumInput = ctx.ssa->reachingDef(addOps[0].reg, sumDef.instRef);
        if (!sumInput.valid() || sumInput.isPhi || !sumInput.inst || sumInput.inst->op != MicroInstrOpcode::LoadRegReg)
            return false;
        const MicroInstrOperand* copyOps = sumInput.inst->ops(*ctx.operands);
        if (!copyOps || copyOps[0].reg != addOps[0].reg || copyOps[1].reg != cmpOps[0].reg ||
            getNumBits(copyOps[2].opBits) < getNumBits(bits) || !ctx.ssa->sameValueAt(cmpOps[0].reg, sumInput.instRef, cmpRef))
            return false;

        const MicroSsaState::ReachingDef limitDef = ctx.ssa->reachingDef(cmpOps[1].reg, cmpRef);
        if (!limitDef.valid() || limitDef.isPhi || !limitDef.inst || limitDef.inst->op != MicroInstrOpcode::OpBinaryRegReg)
            return false;
        const MicroInstrOperand* subOps = limitDef.inst->ops(*ctx.operands);
        if (!subOps || subOps[0].reg != cmpOps[1].reg || subOps[1].reg != addOps[1].reg || subOps[2].opBits != bits ||
            subOps[3].microOp != MicroOp::Subtract || !ctx.ssa->sameValueAt(addOps[1].reg, limitDef.instRef, sumDef.instRef))
            return false;

        const MicroSsaState::ReachingDef limitInput = ctx.ssa->reachingDef(subOps[0].reg, limitDef.instRef);
        const MicroSsaState::ReachingDef fallback   = ctx.ssa->reachingDef(selectOps[0].reg, selectRef);
        if (!isAllOnesLoad(limitInput, *ctx.operands, bits) || !isAllOnesLoad(fallback, *ctx.operands, bits) ||
            !ctx.areCpuFlagsDeadAfter(selectRef) ||
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

        MicroStorage::Iterator patternIt{ctx.storage, selectRef};
        --patternIt;
        if (!patternIt.current.isValid() || patternIt->op != MicroInstrOpcode::CmpRegReg)
            return false;
        const MicroInstrRef      cmpRef = patternIt.current;
        const MicroInstr*        cmp    = &*patternIt;
        const MicroInstrOperand* cmpOps = cmp->ops(*ctx.operands);
        if (!cmpOps || cmpOps[1].reg != right || cmpOps[2].opBits != bits || !cmpOps[0].reg.isVirtualInt())
            return false;
        const MicroReg left = cmpOps[0].reg;
        if (left == right || left == result)
            return false;

        --patternIt;
        if (!patternIt.current.isValid() || patternIt->op != MicroInstrOpcode::LoadRegReg)
            return false;
        const MicroInstrRef      copyRef = patternIt.current;
        const MicroInstr*        copy    = &*patternIt;
        const MicroInstrOperand* copyOps = copy->ops(*ctx.operands);
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
                ctx.ssa->reachingValueId(right, use.instRef) != rightValue.valueId)
                return false;
            if (std::ranges::find(uses, use.instRef) == uses.end())
                uses.push_back(use.instRef);
        }

        for (const MicroInstrRef useRef : uses)
        {
            MicroInstr* useInst = ctx.storage->ptr(useRef);
            if (!useInst || useInst->numOperands > Action::K_MAX_OPS)
                return false;
            const MicroInstrOperand* useOps = useInst->ops(*ctx.operands);
            if (!useOps)
                return false;
            const auto modes = MicroInstr::info(useInst->op).resolvedRegModes(useOps);
            bool       found = false;
            for (size_t operandIndex = 0; operandIndex < modes.size(); ++operandIndex)
            {
                const MicroInstrRegMode mode = modes[operandIndex];
                if (mode == MicroInstrRegMode::None || useOps[operandIndex].reg != result)
                    continue;
                if (mode != MicroInstrRegMode::Use)
                    return false;
                found = true;
            }
            if (!found)
                return false;
        }

        const MicroInstrRef nextRef  = ctx.storage->findNextInstructionRef(selectRef);
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
        using MicroOptimizationLimits::InstructionCombineCompare::K_MAX_WINDOW;

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
        MicroStorage::Iterator patternIt{ctx.storage, ref};
        ++patternIt;
        if (!patternIt.current.isValid() ||
            (patternIt->op != MicroInstrOpcode::LoadCondRegReg && patternIt->op != MicroInstrOpcode::SetCondReg && patternIt->op != MicroInstrOpcode::JumpCond))
            return false;
        const MicroInstrRef readerRef = patternIt.current;

        // Walk back to `sub T, right` whose T held `left`.
        SmallVector<MicroInstrRef, 8> between;
        auto                          scanIt = MicroStorage::Iterator{ctx.storage, ref};
        --scanIt;
        MicroInstrRef subRef = MicroInstrRef::invalid();
        for (uint32_t step = 0; step < K_MAX_WINDOW && scanIt.current.isValid(); ++step)
        {
            const MicroInstr*        candidate    = &*scanIt;
            const MicroInstrOperand* candidateOps = candidate->ops(*ctx.operands);
            if (candidate->op == MicroInstrOpcode::OpBinaryRegReg && candidateOps[3].microOp == MicroOp::Subtract &&
                candidateOps[1].reg == right && candidateOps[2].opBits == bits && candidateOps[0].reg.isVirtualInt() &&
                candidateOps[0].reg != left && candidateOps[0].reg != right)
            {
                subRef = scanIt.current;
                break;
            }
            if (candidate->op == MicroInstrOpcode::Label || MicroPassHelpers::instructionActuallyUsesCpuFlags(*candidate, candidateOps))
                return false;
            const MicroInstrFlags flags = MicroInstr::info(candidate->op).flags;
            if (flags.has(MicroInstrFlagsE::JumpInstruction) || flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
                flags.has(MicroInstrFlagsE::IsCallInstruction))
                return false;
            between.push_back(scanIt.current);
            --scanIt;
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
        if (!ctx.ssa->sameValueAt(left, copyRef, ref) || !ctx.ssa->sameValueAt(right, subRef, ref))
            return false;
        // Copies of T move along with it; nothing else in between may mention
        // T or those copies.
        SmallVector<MicroInstrRef, 4> followers;
        SmallVector<MicroReg, 4>      followerRegs;
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
            const MicroInstr*        betweenInst = ctx.storage->ptr(betweenRef);
            const MicroInstrOperand* betweenOps  = betweenInst->ops(*ctx.operands);
            if (!betweenOps)
                continue;
            const auto modes = MicroInstr::info(betweenInst->op).resolvedRegModes(betweenOps);
            for (size_t operandIndex = 0; operandIndex < modes.size(); ++operandIndex)
            {
                if (modes[operandIndex] == MicroInstrRegMode::None)
                    continue;
                const MicroReg reg = betweenOps[operandIndex].reg;
                if (!reg.isValid() || reg.isNoBase())
                    continue;
                if (reg == result || std::ranges::find(followerRegs, reg) != followerRegs.end())
                    return false;
            }
        }

        if (!ctx.areCpuFlagsDeadAfter(readerRef))
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
