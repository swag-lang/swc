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

    // An instruction we must never erase, regardless of its defs' liveness.
    // Defining CPU flags is treated conservatively as a side effect: flag
    // liveness isn't modeled separately, so an arithmetic op whose register
    // result is dead may still be keeping the flags live for a following
    // conditional branch.
    bool hasObservableSideEffect(const MicroInstr& inst)
    {
        return MicroInstrInfo::hasObservableSideEffect(inst) ||
               inst.op == MicroInstrOpcode::Push ||
               inst.op == MicroInstrOpcode::Pop;
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
    bool changed = false;
    for (uint32_t i = 0; i < instCount; ++i)
    {
        const MicroInstr* inst = storage.ptr(instructionRefs[i]);
        if (!inst)
            continue;
        if (hasObservableSideEffect(*inst))
            continue;

        if (!allDefsAreDead(liveness, i))
            continue;

        if (storage.erase(instructionRefs[i]))
            changed = true;
    }

    if (changed)
        context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
