#include "pch.h"
#include "Backend/Micro/Passes/Pass.PostRADeadCodeElim.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroReg.h"
#include "Support/Report/Assert.h"

// Post-RA dead-code elimination.
//
// Classic backward-liveness DCE over the per-instruction CFG on physical
// registers. Live-out at function-exit instructions is seeded with the ABI
// live-out set (return regs + callee-save / persistent regs + stack pointer
// + frame pointer). Iterative worklist computes per-instruction live-out;
// any instruction whose defs are all non-live and which has no observable
// side effect is erased.

SWC_BEGIN_NAMESPACE();

namespace
{
    using MicroPassHelpers::MicroPhysLiveness;

    // Preserve control, memory, and stack effects. Integer flag writes may be
    // discarded only after both register and flag liveness have been checked.
    bool hasObservableSideEffect(const MicroInstr& inst)
    {
        return MicroInstrInfo::hasObservableSideEffect(inst) ||
               inst.op == MicroInstrOpcode::Push ||
               inst.op == MicroInstrOpcode::Pop;
    }

    // Only non-trapping integer register arithmetic may lose a flag write.
    // Division, memory operands, and floating-point exception state stay out.
    bool isDiscardableIntegerArithmetic(const MicroInstr& inst, const MicroInstrOperand* ops)
    {
        if (!ops || !ops[0].reg.isInt())
            return false;
        if (inst.op == MicroInstrOpcode::ClearReg)
            return true;
        if (inst.op == MicroInstrOpcode::OpUnaryReg)
            return ops[2].microOp == MicroOp::Negate || ops[2].microOp == MicroOp::BitwiseNot || ops[2].microOp == MicroOp::ByteSwap;
        const bool immediate = inst.op == MicroInstrOpcode::OpBinaryRegImm;
        if (!immediate && inst.op != MicroInstrOpcode::OpBinaryRegReg)
            return false;
        if (!immediate && !ops[1].reg.isInt())
            return false;
        switch (ops[immediate ? 2 : 3].microOp)
        {
            case MicroOp::Add:
            case MicroOp::Subtract:
            case MicroOp::And:
            case MicroOp::Or:
            case MicroOp::Xor:
            case MicroOp::MultiplySigned:
            case MicroOp::MultiplyUnsigned:
            case MicroOp::MultiplyWideSigned:
            case MicroOp::ShiftLeft:
            case MicroOp::ShiftRight:
            case MicroOp::ShiftArithmeticLeft:
            case MicroOp::ShiftArithmeticRight:
            case MicroOp::RotateLeft:
            case MicroOp::RotateRight:
                return true;
            default:
                return false;
        }
    }

    bool allDefsAreDead(const MicroPhysLiveness& liveness, uint32_t index)
    {
        const MicroInstrUseDef& useDef = liveness.useDefs[index];
        if (useDef.defs.empty())
            return false;

        for (const MicroReg def : useDef.defs)
        {
            if (liveness.isLiveOut(index, def))
                return false;
        }

        return true;
    }
}

Result MicroPostRaDeadCodeElimPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);
    SWC_ASSERT(context.builder != nullptr);

    MicroStorage& storage = *context.instructions;

    const MicroControlFlowGraph& cfg = context.builder->controlFlowGraph();
    if (!cfg.supportsDeadCodeLiveness() || cfg.hasUnsupportedControlFlowForCfgLiveness())
        return Result::Continue;

    const auto instructionRefs = cfg.instructionRefs();
    const auto instCount       = static_cast<uint32_t>(instructionRefs.size());
    if (instCount == 0)
        return Result::Continue;

    // The shared physical-register analysis computes the same backward fixed point,
    // using one machine word per set instead of repeatedly scanning register vectors.
    MicroPhysLiveness liveness;
    MicroPassHelpers::computePhysicalLiveness(liveness, context);
    if (!liveness.valid)
        return Result::Continue;

    // Sweep: erase instructions whose every defined reg is dead in liveOut
    // and which have no observable side effect. Instructions with no defs
    // either have side effects (caught by hasObservableSideEffect) or are
    // truly useless (rare post-RA).
    // Flag queries can consult the builder's cached CFG. Keep storage unchanged
    // until every decision is made: rebuilding that CFG after an erase would
    // invalidate its instruction span and the physical-liveness index mapping.
    SmallVector<MicroInstrRef> erased;
    for (uint32_t i = 0; i < instCount; ++i)
    {
        const MicroInstr* inst = storage.ptr(instructionRefs[i]);
        if (!inst)
            continue;
        if (!allDefsAreDead(liveness, i))
            continue;
        if (hasObservableSideEffect(*inst) &&
            (!isDiscardableIntegerArithmetic(*inst, inst->ops(*context.operands)) ||
             !MicroPassHelpers::areCpuFlagsDeadAfter(storage, *context.operands, instructionRefs[i], context.builder)))
            continue;

        erased.push_back(instructionRefs[i]);
    }

    for (const MicroInstrRef ref : erased)
        storage.erase(ref);
    if (!erased.empty())
        context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
