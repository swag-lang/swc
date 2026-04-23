#include "pch.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Support/Memory/MemoryProfile.h"

// Pre-RA dead code elimination on virtual registers.
//
// Removes side-effect-free instructions whose virtual-register results are
// never consumed. In the shared pre-RA pipeline we use backward liveness over
// the cached CFG and rely on the outer fixed-point loop to rerun DCE.
// Standalone/unit-test execution keeps the older SSA-driven fixed point.
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
    using RegSet = SmallVector<MicroReg, 8>;

    void addLiveVirtualReg(RegSet& set, MicroReg reg)
    {
        if (!reg.isVirtual())
            return;

        for (const MicroReg existing : set)
        {
            if (existing == reg)
                return;
        }

        set.push_back(reg);
    }

    bool containsLiveReg(const RegSet& set, MicroReg reg)
    {
        for (const MicroReg existing : set)
        {
            if (existing == reg)
                return true;
        }

        return false;
    }

    bool setChanged(const RegSet& before, const RegSet& after)
    {
        if (after.size() != before.size())
            return true;

        for (const MicroReg reg : after)
        {
            if (!containsLiveReg(before, reg))
                return true;
        }

        return false;
    }

    void applyVirtualTransfer(RegSet& inOutLive, const MicroInstrUseDef& useDef)
    {
        for (const MicroReg def : useDef.defs)
        {
            if (!def.isVirtual())
                continue;

            for (uint32_t i = 0; i < inOutLive.size();)
            {
                if (inOutLive[i] == def)
                    inOutLive.erase(inOutLive.begin() + i);
                else
                    ++i;
            }
        }

        for (const MicroReg use : useDef.uses)
            addLiveVirtualReg(inOutLive, use);
    }

    bool hasObservableSideEffect(const MicroInstr& inst, const MicroInstrUseDef& useDef)
    {
        return useDef.isCall || MicroInstrInfo::hasObservableSideEffect(inst);
    }

    bool allDefsAreDeadVirtualRegs(const MicroInstrUseDef& useDef, const RegSet& liveOut)
    {
        if (useDef.defs.empty())
            return false;

        for (const MicroReg def : useDef.defs)
        {
            if (!def.isVirtual())
                return false;
            if (containsLiveReg(liveOut, def))
                return false;
        }

        return true;
    }

    bool canEraseInstruction(const MicroInstr& inst, const MicroInstrUseDef& useDef, const RegSet& liveOut)
    {
        if (hasObservableSideEffect(inst, useDef))
            return false;

        return allDefsAreDeadVirtualRegs(useDef, liveOut);
    }

    bool tryEliminateDeadInstructionsViaCfg(bool& outChanged, MicroPassContext& context)
    {
        outChanged = false;
        SWC_ASSERT(context.builder != nullptr);
        SWC_ASSERT(context.instructions != nullptr);
        SWC_ASSERT(context.operands != nullptr);

        MicroStorage&              storage  = *context.instructions;
        const MicroOperandStorage& operands = *context.operands;
        const MicroControlFlowGraph& cfg    = context.builder->controlFlowGraph();

        if (!cfg.supportsDeadCodeLiveness() || cfg.hasUnsupportedControlFlowForCfgLiveness())
            return false;

        const auto instructionRefs = cfg.instructionRefs();
        const auto successors      = cfg.successors();
        const auto predecessors    = cfg.predecessors();
        const auto instCount       = static_cast<uint32_t>(instructionRefs.size());
        if (!instCount)
            return true;

        std::vector<MicroInstrUseDef> useDefs(instCount);
        for (uint32_t i = 0; i < instCount; ++i)
        {
            const MicroInstr* inst = storage.ptr(instructionRefs[i]);
            if (!inst)
                return false;

            useDefs[i] = inst->collectUseDef(operands, context.encoder);
        }

        std::vector<RegSet> liveIn(instCount);
        std::vector<RegSet> liveOut(instCount);
        std::vector<uint8_t> inWorklist(instCount, 1);
        std::vector<uint32_t> worklist;
        worklist.reserve(instCount);
        for (uint32_t i = 0; i < instCount; ++i)
            worklist.push_back(i);

        while (!worklist.empty())
        {
            const uint32_t i = worklist.back();
            worklist.pop_back();
            inWorklist[i] = 0;

            RegSet newOut;
            for (const uint32_t succ : successors[i])
            {
                for (const MicroReg reg : liveIn[succ])
                    addLiveVirtualReg(newOut, reg);
            }

            if (setChanged(liveOut[i], newOut))
                liveOut[i] = newOut;

            RegSet newIn = liveOut[i];
            applyVirtualTransfer(newIn, useDefs[i]);
            if (!setChanged(liveIn[i], newIn))
                continue;

            liveIn[i] = newIn;
            for (const uint32_t pred : predecessors[i])
            {
                if (inWorklist[pred])
                    continue;

                worklist.push_back(pred);
                inWorklist[pred] = 1;
            }
        }

        bool       changed = false;
        for (uint32_t i = 0; i < instCount; ++i)
        {
            const MicroInstrRef instRef = instructionRefs[i];
            const MicroInstr*   inst    = storage.ptr(instRef);
            if (!inst)
                continue;

            if (!canEraseInstruction(*inst, useDefs[i], liveOut[i]))
                continue;

            changed |= storage.erase(instRef);
        }

        outChanged = changed;
        return true;
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

    MicroStorage& storage = *context.instructions;

    if (context.useDefMap && context.builder)
    {
        bool changed = false;
        if (tryEliminateDeadInstructionsViaCfg(changed, context))
        {
            if (!changed)
                return Result::Continue;

            context.passChanged = true;
            return Result::Continue;
        }
    }

    MicroSsaState        localSsaState;
    const MicroSsaState* ssaState = MicroSsaState::ensureFor(context, localSsaState);
    if (!ssaState || !ssaState->isValid())
        return Result::Continue;

    if (!eliminateDeadInstructions(storage, *ssaState))
        return Result::Continue;

    context.passChanged = true;

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
