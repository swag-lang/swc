#include "pch.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Report/Assert.h"

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
//   - if it defines CPU flags, it defines only virtual integer registers and
//     the flags are provably redefined before the next control-flow boundary,
//   - it defines at least one virtual register, and
//   - every defined virtual register is dead after the instruction.

SWC_BEGIN_NAMESPACE();

namespace
{
    bool hasObservableSideEffect(const MicroStorage& storage, const MicroOperandStorage& operands, const MicroInstr& inst, const MicroInstrUseDef& useDef, const MicroInstrRef instRef)
    {
        if (useDef.isCall)
            return true;
        if (!MicroInstrInfo::hasObservableSideEffect(inst))
            return false;

        // A dead integer compute whose only side effect is the CPU flags it
        // defines is still removable when the flags are provably redefined in
        // the same straight-line window. Duplicated two-address chains that
        // value numbering rewires leave exactly this shape behind: a
        // flag-writing arithmetic prefix whose register result no longer has
        // a consumer. Float destinations stay untouchable: a float clear_reg
        // is the upper-bits-zeroing half of a clear+partial-insert idiom the
        // use/def model reads as two independent full definitions.
        for (const MicroReg def : useDef.defs)
        {
            if (!def.isVirtualInt())
                return true;
        }

        const MicroInstrDef& info = MicroInstr::info(inst.op);
        if (inst.op == MicroInstrOpcode::Label ||
            info.flags.has(MicroInstrFlagsE::TerminatorInstruction) ||
            info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
            info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
            info.flags.has(MicroInstrFlagsE::WritesMemory))
            return true;

        SWC_ASSERT(info.flags.has(MicroInstrFlagsE::DefinesCpuFlags));
        return !MicroPassHelpers::areCpuFlagsRedefinedBeforeBoundary(storage, operands, instRef);
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

    bool canEraseInstruction(const MicroStorage& storage, const MicroOperandStorage& operands, const MicroInstr& inst, const MicroInstrUseDef& useDef, const MicroSsaState& ssaState, MicroInstrRef instRef)
    {
        if (hasObservableSideEffect(storage, operands, inst, useDef, instRef))
            return false;

        return allDefsAreDeadVirtualRegs(useDef, ssaState, instRef);
    }

    bool eliminateDeadInstructions(MicroStorage& storage, const MicroOperandStorage& operands, const MicroSsaState& ssaState)
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

            if (!canEraseInstruction(storage, operands, inst, *useDef, ssaState, instRef))
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

    MicroOperandStorage& operands = *context.operands;

    if (!eliminateDeadInstructions(storage, operands, *ssaState))
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

        if (!eliminateDeadInstructions(storage, operands, *ssaState))
            break;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
