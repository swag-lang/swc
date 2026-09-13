#include "pch.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
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

    void collectUsedValues(std::vector<uint8_t>& usedValues, std::vector<uint32_t>& worklist, const MicroStorage& storage, const MicroSsaState& ssaState)
    {
        const auto values = ssaState.values();
        usedValues.assign(values.size(), 0);
        worklist.clear();
        for (uint32_t valueId = 0; valueId < values.size(); ++valueId)
        {
            for (const auto& use : values[valueId].uses)
            {
                if (use.kind != MicroSsaState::UseSite::Kind::Instruction || !storage.ptr(use.instRef))
                    continue;
                usedValues[valueId] = 1;
                if (values[valueId].isPhi())
                    worklist.push_back(valueId);
                break;
            }
        }

        // Only instruction consumers make a phi live. Walking backwards from them
        // also handles phi cycles with no consumer, without revisiting every cycle
        // separately for every definition queried by the elimination sweep.
        while (!worklist.empty())
        {
            const uint32_t valueId = worklist.back();
            worklist.pop_back();
            const auto* phi = ssaState.phiInfoForValue(valueId);
            SWC_ASSERT(phi != nullptr);
            for (const uint32_t incomingValueId : phi->incomingValueIds)
            {
                if (incomingValueId == MicroSsaState::K_INVALID_VALUE || usedValues[incomingValueId])
                    continue;
                usedValues[incomingValueId] = 1;
                if (values[incomingValueId].isPhi())
                    worklist.push_back(incomingValueId);
            }
        }
    }

    bool allDefsAreDeadVirtualRegs(const MicroInstrUseDef& useDef, const MicroSsaState& ssaState, const std::vector<uint8_t>& usedValues, MicroInstrRef instRef)
    {
        if (useDef.defs.empty())
            return false;

        for (const MicroReg def : useDef.defs)
        {
            if (!def.isVirtual())
                return false;
            uint32_t valueId = MicroSsaState::K_INVALID_VALUE;
            if (ssaState.defValue(def, instRef, valueId) && usedValues[valueId])
                return false;
        }

        return true;
    }

    bool canEraseInstruction(const MicroStorage& storage, const MicroOperandStorage& operands, const MicroInstr& inst, const MicroInstrUseDef& useDef, const MicroSsaState& ssaState, const std::vector<uint8_t>& usedValues, MicroInstrRef instRef)
    {
        if (!allDefsAreDeadVirtualRegs(useDef, ssaState, usedValues, instRef))
            return false;

        return !hasObservableSideEffect(storage, operands, inst, useDef, instRef);
    }

    bool eliminateDeadInstructions(MicroStorage& storage, const MicroOperandStorage& operands, const MicroSsaState& ssaState, const std::vector<uint8_t>& usedValues)
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

            if (!canEraseInstruction(storage, operands, inst, *useDef, ssaState, usedValues, instRef))
                continue;

            changed |= storage.erase(instRef);
        }

        return changed;
    }
}

Result MicroDeadCodeEliminationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);
    SWC_ASSERT(context.builder != nullptr);

    MicroStorage&        storage = *context.instructions;
    MicroSsaState        localSsaState;
    const MicroSsaState* ssaState = MicroSsaState::ensureFor(context, localSsaState);
    if (!ssaState || !ssaState->isValid())
        return Result::Continue;

    MicroOperandStorage&  operands = *context.operands;
    std::vector<uint8_t>  usedValues;
    std::vector<uint32_t> worklist;
    bool                  changed = false;

    // Erasing a dead definition cannot change the reaching value of a surviving
    // use. Keep this SSA graph for the entire fixed point and ignore erased
    // instruction consumers, instead of rebuilding CFG, dominators and SSA after
    // each level of a dead chain. Snapshot usage once per sweep to preserve the
    // original erasure order, including its CPU-flag redefinition checks.
    while (true)
    {
        collectUsedValues(usedValues, worklist, storage, *ssaState);
        if (!eliminateDeadInstructions(storage, operands, *ssaState, usedValues))
            break;
        changed = true;
    }

    if (changed)
    {
        context.passChanged = true;
        if (context.ssaState)
            context.ssaState->invalidate();
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
