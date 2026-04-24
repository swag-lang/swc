#include "pch.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Support/Memory/MemoryProfile.h"

// Pre-RA dead code elimination on virtual registers.
//
// Removes side-effect-free instructions whose virtual-register results are
// never consumed (transitively, across the SSA use graph). Iterates to a
// fixed point so that erasing one instruction can expose its operands as
// newly dead.
//
// An instruction is a candidate when:
//   - it is not a terminator, jump, call, or label,
//   - it does not write memory,
//   - it does not define CPU flags (flag liveness is not tracked here),
//   - it defines at least one virtual register, and
//   - every defined virtual register is dead after the instruction.

SWC_BEGIN_NAMESPACE();

namespace
{
    bool hasObservableSideEffect(const MicroInstr& inst, const MicroInstrUseDef& useDef)
    {
        return useDef.isCall || MicroInstrInfo::hasObservableSideEffect(inst);
    }

    bool allDefsAreDeadVirtualRegs(const MicroInstrUseDef& useDef, const MicroSsaState& ssaState, MicroInstrRef instRef)
    {
        if (useDef.defs.empty())
            return false;

        for (const MicroReg def : useDef.defs)
        {
            if (!def.isVirtual())
                return false;
            if (ssaState.isRegUsedAfter(def, instRef))
                return false;
        }

        return true;
    }

    bool canEraseInstruction(const MicroInstr& inst, const MicroInstrUseDef& useDef, const MicroSsaState& ssaState, MicroInstrRef instRef)
    {
        if (hasObservableSideEffect(inst, useDef))
            return false;

        return allDefsAreDeadVirtualRegs(useDef, ssaState, instRef);
    }

    bool eliminateDeadInstructions(MicroStorage& storage, const MicroSsaState& ssaState)
    {
        bool       changed = false;
        const auto view    = storage.view();
        const auto endIt   = view.end();
        for (auto it = view.begin(); it != endIt;)
        {
            const MicroInstrRef instRef = it.current;
            const MicroInstr&   inst    = *it;
            ++it;

            const MicroInstrUseDef* useDef = ssaState.instrUseDef(instRef);
            if (!useDef)
                continue;

            if (!canEraseInstruction(inst, *useDef, ssaState, instRef))
                continue;

            changed |= storage.erase(instRef);
        }

        return changed;
    }
}

Result MicroDeadCodeEliminationPass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/DCE");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);
    SWC_ASSERT(context.builder != nullptr);

    MicroStorage&        storage = *context.instructions;
    MicroSsaState        localSsaState;
    const MicroSsaState* ssaState = MicroSsaState::ensureFor(context, localSsaState);
    if (!ssaState || !ssaState->isValid())
        return Result::Continue;

    if (!eliminateDeadInstructions(storage, *ssaState))
        return Result::Continue;

    context.passChanged = true;

    // Each erasure may free up further candidates; iterate on a freshly
    // rebuilt SSA until the set of dead instructions stabilises.
    while (true)
    {
        if (context.ssaState)
            context.ssaState->invalidate();
        else
            localSsaState.invalidate();

        ssaState = MicroSsaState::ensureFor(context, localSsaState);
        if (!ssaState || !ssaState->isValid())
            break;

        if (!eliminateDeadInstructions(storage, *ssaState))
            break;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
