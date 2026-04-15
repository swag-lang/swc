#include "pch.h"
#include "Backend/Micro/Passes/Pass.PostRADeadCodeElim.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroReg.h"
#include "Support/Memory/MemoryProfile.h"

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
    using RegSet = SmallVector<MicroReg, 8>;

    void addRegUnique(RegSet& set, MicroReg reg)
    {
        if (!reg.isValid())
            return;
        for (const MicroReg existing : set)
            if (existing == reg)
                return;
        set.push_back(reg);
    }

    bool contains(const RegSet& set, MicroReg reg)
    {
        for (const MicroReg existing : set)
            if (existing == reg)
                return true;
        return false;
    }

    // Did the second set grow relative to the first? Called after merging
    // successor live-in into this block's live-out to detect fixed-point.
    bool setChanged(const RegSet& before, const RegSet& after)
    {
        if (after.size() != before.size())
            return true;
        for (const MicroReg reg : after)
            if (!contains(before, reg))
                return true;
        return false;
    }

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

    bool allDefsAreDead(const MicroInstrUseDef& useDef, const RegSet& liveOut)
    {
        if (useDef.defs.empty())
            return false;

        for (const MicroReg def : useDef.defs)
        {
            if (contains(liveOut, def))
                return false;
        }

        return true;
    }

    RegSet buildExitLiveOut(const CallConv& conv, const MicroPassContext& context)
    {
        RegSet live;
        if (context.usesIntReturnRegOnRet)
            addRegUnique(live, conv.intReturn);
        if (context.usesFloatReturnRegOnRet)
            addRegUnique(live, conv.floatReturn);
        addRegUnique(live, conv.stackPointer);
        addRegUnique(live, conv.framePointer);
        for (const MicroReg reg : conv.intPersistentRegs)
            addRegUnique(live, reg);
        for (const MicroReg reg : conv.floatPersistentRegs)
            addRegUnique(live, reg);
        return live;
    }

    void applyTransfer(RegSet& inOutLive, const MicroInstrUseDef& useDef)
    {
        // live_in = (live_out \ defs) | uses
        for (const MicroReg def : useDef.defs)
        {
            for (uint32_t i = 0; i < inOutLive.size();)
            {
                if (inOutLive[i] == def)
                    inOutLive.erase(inOutLive.begin() + i);
                else
                    ++i;
            }
        }
        for (const MicroReg use : useDef.uses)
            addRegUnique(inOutLive, use);
    }
}

Result MicroPostRADeadCodeElimPass::run(MicroPassContext& context)
{
    SWC_MEM_SCOPE("Backend/MicroLower/PostRADCE");
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);
    SWC_ASSERT(context.builder != nullptr);

    MicroStorage&              storage  = *context.instructions;
    const MicroOperandStorage& operands = *context.operands;

    const MicroControlFlowGraph& cfg = context.builder->controlFlowGraph();
    if (!cfg.supportsDeadCodeLiveness() || cfg.hasUnsupportedControlFlowForCfgLiveness())
        return Result::Continue;

    const auto instructionRefs = cfg.instructionRefs();
    const auto successors      = cfg.successors();
    const auto predecessors    = cfg.predecessors();
    const auto instCount       = static_cast<uint32_t>(instructionRefs.size());
    if (instCount == 0)
        return Result::Continue;

    // Per-instruction use/def cache. Computed once; the IR isn't mutated
    // until the final erase pass so these stay valid.
    std::vector<MicroInstrUseDef> useDefs(instCount);
    for (uint32_t i = 0; i < instCount; ++i)
    {
        const MicroInstr* inst = storage.ptr(instructionRefs[i]);
        if (!inst)
            return Result::Continue;
        useDefs[i] = inst->collectUseDef(operands, context.encoder);
    }

    const CallConv& conv        = CallConv::get(context.callConvKind);
    const RegSet    exitLiveOut = buildExitLiveOut(conv, context);

    // Iterative backward dataflow.
    //   liveIn[i]  = (liveOut[i] \ defs[i]) | uses[i]
    //   liveOut[i] = union of liveIn[s] for s in successors[i]
    // Seed: at instructions with no successors (Ret, JumpReg handled earlier),
    // liveOut is the ABI exit set.
    std::vector<RegSet> liveIn(instCount);
    std::vector<RegSet> liveOut(instCount);
    for (uint32_t i = 0; i < instCount; ++i)
    {
        if (successors[i].empty())
            liveOut[i] = exitLiveOut;
    }

    std::vector<uint8_t>  inWorklist(instCount, 0);
    std::vector<uint32_t> worklist;
    worklist.reserve(instCount);
    for (uint32_t i = 0; i < instCount; ++i)
    {
        worklist.push_back(i);
        inWorklist[i] = 1;
    }

    while (!worklist.empty())
    {
        const uint32_t i = worklist.back();
        worklist.pop_back();
        inWorklist[i] = 0;

        RegSet newOut;
        if (successors[i].empty())
        {
            newOut = exitLiveOut;
        }
        else
        {
            for (const uint32_t succ : successors[i])
            {
                for (const MicroReg reg : liveIn[succ])
                    addRegUnique(newOut, reg);
            }
        }

        if (setChanged(liveOut[i], newOut))
            liveOut[i] = newOut;

        RegSet newIn = liveOut[i];
        applyTransfer(newIn, useDefs[i]);

        if (setChanged(liveIn[i], newIn))
        {
            liveIn[i] = newIn;
            for (const uint32_t pred : predecessors[i])
            {
                if (!inWorklist[pred])
                {
                    worklist.push_back(pred);
                    inWorklist[pred] = 1;
                }
            }
        }
    }

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

        const MicroInstrUseDef& useDef = useDefs[i];
        if (!allDefsAreDead(useDef, liveOut[i]))
            continue;

        if (storage.erase(instructionRefs[i]))
            changed = true;
    }

    if (changed)
        context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
