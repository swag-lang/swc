#include "pch.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/MicroPassContext.h"

// Eliminates side-effect-free instructions whose results are not live.
// Example: add r1, 4; ... (r1 never used) -> <remove add>.
// Example: mov r2, r3; ... (r2 never used) -> <remove mov>.
// This pass keeps memory/branch/call side effects intact.

SWC_BEGIN_NAMESPACE();

namespace
{
    void addCallArgumentRegs(std::unordered_set<uint32_t>& liveRegs, const CallConv& conv)
    {
        for (const MicroReg reg : conv.intArgRegs)
            liveRegs.insert(reg.packed);
        for (const MicroReg reg : conv.floatArgRegs)
            liveRegs.insert(reg.packed);
    }

    void killCallClobberedRegs(std::unordered_set<uint32_t>& liveRegs, const CallConv& conv)
    {
        for (const MicroReg reg : conv.intTransientRegs)
            liveRegs.erase(reg.packed);
        for (const MicroReg reg : conv.floatTransientRegs)
            liveRegs.erase(reg.packed);
    }

    bool isFullWidthIntegerWrite(MicroOpBits opBits)
    {
        return opBits == MicroOpBits::B32 || opBits == MicroOpBits::B64;
    }

    bool canCurrentDefKillPreviousPureDef(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg defReg)
    {
        if (!ops)
            return false;

        if (!defReg.isInt())
            return false;

        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegReg:
                return isFullWidthIntegerWrite(ops[2].opBits);
            case MicroInstrOpcode::LoadRegImm:
                return isFullWidthIntegerWrite(ops[1].opBits);
            case MicroInstrOpcode::LoadRegPtrImm:
            case MicroInstrOpcode::LoadRegPtrReloc:
                return isFullWidthIntegerWrite(ops[1].opBits);
            case MicroInstrOpcode::LoadRegMem:
                return isFullWidthIntegerWrite(ops[2].opBits);
            case MicroInstrOpcode::LoadSignedExtRegMem:
                return isFullWidthIntegerWrite(ops[2].opBits);
            case MicroInstrOpcode::LoadZeroExtRegMem:
                return isFullWidthIntegerWrite(ops[2].opBits);
            case MicroInstrOpcode::LoadSignedExtRegReg:
                return isFullWidthIntegerWrite(ops[2].opBits);
            case MicroInstrOpcode::LoadZeroExtRegReg:
                return isFullWidthIntegerWrite(ops[2].opBits);
            case MicroInstrOpcode::LoadAddrRegMem:
                return isFullWidthIntegerWrite(ops[2].opBits);
            case MicroInstrOpcode::LoadAddrAmcRegMem:
                return isFullWidthIntegerWrite(ops[3].opBits);
            case MicroInstrOpcode::SetCondReg:
                return false;
            case MicroInstrOpcode::ClearReg:
                return isFullWidthIntegerWrite(ops[1].opBits);
            case MicroInstrOpcode::OpUnaryReg:
                return isFullWidthIntegerWrite(ops[1].opBits);
            case MicroInstrOpcode::LoadCondRegReg:
                return isFullWidthIntegerWrite(ops[3].opBits);
            case MicroInstrOpcode::OpBinaryRegReg:
                return isFullWidthIntegerWrite(ops[2].opBits);
            case MicroInstrOpcode::OpBinaryRegImm:
                return isFullWidthIntegerWrite(ops[1].opBits);
            default:
                return false;
        }
    }

    bool isRemovableInstruction(const MicroInstr& inst)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegReg:
            case MicroInstrOpcode::LoadRegImm:
            case MicroInstrOpcode::LoadRegPtrImm:
            case MicroInstrOpcode::LoadRegPtrReloc:
            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
            case MicroInstrOpcode::LoadSignedExtRegReg:
            case MicroInstrOpcode::LoadZeroExtRegReg:
            case MicroInstrOpcode::LoadAddrRegMem:
            case MicroInstrOpcode::LoadAddrAmcRegMem:
            case MicroInstrOpcode::SetCondReg:
            case MicroInstrOpcode::LoadCondRegReg:
            case MicroInstrOpcode::ClearReg:
            case MicroInstrOpcode::OpUnaryReg:
            case MicroInstrOpcode::OpBinaryRegReg:
            case MicroInstrOpcode::OpBinaryRegImm:
                return true;
            default:
                return false;
        }
    }

    bool definesSpecialRegister(std::span<const MicroReg> defs, const Encoder* encoder, CallConvKind callConvKind)
    {
        const CallConv& conv            = CallConv::get(callConvKind);
        MicroReg        stackPointerReg = conv.stackPointer;
        const MicroReg  framePointerReg = conv.framePointer;
        if (encoder)
            stackPointerReg = encoder->stackPointerReg();

        for (const MicroReg reg : defs)
        {
            if (reg.isInstructionPointer())
                return true;

            if (stackPointerReg.isValid() && reg == stackPointerReg)
                return true;

            if (framePointerReg.isValid() && reg == framePointerReg)
                return true;
        }

        return false;
    }

    bool isControlFlowBarrier(const MicroInstr& inst, const MicroInstrUseDef& useDef)
    {
        SWC_UNUSED(useDef);
        switch (inst.op)
        {
            case MicroInstrOpcode::Label:
            case MicroInstrOpcode::JumpCond:
            case MicroInstrOpcode::JumpCondImm:
            case MicroInstrOpcode::JumpReg:
            case MicroInstrOpcode::Ret:
                return true;
            default:
                return false;
        }
    }

    bool isPureDefCandidate(const MicroInstr& inst, const MicroInstrUseDef& useDef, const Encoder* encoder, CallConvKind callConvKind)
    {
        return isRemovableInstruction(inst) &&
               !definesSpecialRegister(useDef.defs, encoder, callConvKind) &&
               useDef.defs.size() == 1 &&
               !useDef.isCall;
    }

    bool isBackwardDeadDefRemovableInstruction(const MicroInstr& inst)
    {
        if (MicroInstrInfo::definesCpuFlags(inst))
            return false;

        return isRemovableInstruction(inst);
    }

    void addLiveReg(std::unordered_set<uint32_t>& liveRegs, MicroReg reg)
    {
        if (!reg.isValid() || reg.isNoBase())
            return;
        liveRegs.insert(reg.packed);
    }

    void transferInstructionLiveness(std::unordered_set<uint32_t>&       outLiveIn,
                                     const std::unordered_set<uint32_t>& liveOut,
                                     const MicroInstr&                   inst,
                                     const MicroInstrUseDef&             useDef,
                                     CallConvKind                        callConvKind)
    {
        outLiveIn = liveOut;

        if (inst.op == MicroInstrOpcode::Ret)
        {
            const CallConv& conv = CallConv::get(callConvKind);
            addLiveReg(outLiveIn, conv.intReturn);
            addLiveReg(outLiveIn, conv.floatReturn);
        }

        if (useDef.isCall)
        {
            const CallConv& callConv = CallConv::get(useDef.callConv);
            killCallClobberedRegs(outLiveIn, callConv);
            addCallArgumentRegs(outLiveIn, callConv);

            // Calls clobber transient regs and consume argument regs.
            // Do not apply generic def-kill here: call defs can overlap arg regs.
            for (const MicroReg useReg : useDef.uses)
                outLiveIn.insert(useReg.packed);
            return;
        }

        for (const MicroReg defReg : useDef.defs)
            outLiveIn.erase(defReg.packed);

        for (const MicroReg useReg : useDef.uses)
            outLiveIn.insert(useReg.packed);
    }

    bool eliminateDeadPureDefsByBackwardLivenessCfg(MicroStorage&                storage,
                                                    const MicroOperandStorage&   operands,
                                                    const Encoder*               encoder,
                                                    CallConvKind                 callConvKind,
                                                    const MicroControlFlowGraph& controlFlowGraph)
    {
        const std::span<const MicroInstrRef> instructionRefs = controlFlowGraph.instructionRefs();
        if (instructionRefs.empty())
            return false;

        const size_t                              instructionCount = instructionRefs.size();
        std::vector<std::unordered_set<uint32_t>> liveIn(instructionCount);
        std::vector<std::unordered_set<uint32_t>> liveOut(instructionCount);
        bool                                      changed = true;
        while (changed)
        {
            changed = false;

            for (size_t i = instructionCount; i > 0; --i)
            {
                const size_t        idx            = i - 1;
                const MicroInstrRef instructionRef = instructionRefs[idx];
                const MicroInstr*   inst           = storage.ptr(instructionRef);
                if (!inst)
                    continue;

                const MicroInstrUseDef useDef = inst->collectUseDef(operands, encoder);

                std::unordered_set<uint32_t> newLiveOut;
                const SmallVector<uint32_t>& successors = controlFlowGraph.successors(static_cast<uint32_t>(idx));
                for (const uint32_t successorIndexRef : successors)
                {
                    const size_t successorIndex = successorIndexRef;
                    if (successorIndex >= liveIn.size())
                        continue;

                    const std::unordered_set<uint32_t>& successorLiveIn = liveIn[successorIndex];
                    for (const uint32_t regKey : successorLiveIn)
                        newLiveOut.insert(regKey);
                }

                std::unordered_set<uint32_t> newLiveIn;
                transferInstructionLiveness(newLiveIn, newLiveOut, *inst, useDef, callConvKind);

                if (newLiveOut != liveOut[idx] || newLiveIn != liveIn[idx])
                {
                    liveOut[idx] = std::move(newLiveOut);
                    liveIn[idx]  = std::move(newLiveIn);
                    changed      = true;
                }
            }
        }

        bool                       removedAny = false;
        std::vector<MicroInstrRef> eraseList;
        eraseList.reserve(64);

        for (size_t i = 0; i < instructionCount; ++i)
        {
            const MicroInstrRef instructionRef = instructionRefs[i];
            const MicroInstr*   inst           = storage.ptr(instructionRef);
            if (!inst)
                continue;

            const MicroInstrUseDef useDef = inst->collectUseDef(operands, encoder);
            if (!isBackwardDeadDefRemovableInstruction(*inst) || !isPureDefCandidate(*inst, useDef, encoder, callConvKind))
                continue;

            const uint32_t defRegKey = useDef.defs.front().packed;
            if (liveOut[i].contains(defRegKey))
                continue;

            eraseList.push_back(instructionRef);
        }

        for (const MicroInstrRef eraseRef : eraseList)
        {
            storage.erase(eraseRef);
            removedAny = true;
        }

        return removedAny;
    }

    bool eliminateDeadPureDefsByBackwardLivenessLinearTail(MicroStorage& storage, const MicroOperandStorage& operands, const Encoder* encoder, CallConvKind callConvKind)
    {
        bool                         changed = false;
        std::unordered_set<uint32_t> liveRegs;
        liveRegs.reserve(64);

        std::vector<MicroInstrRef> eraseList;
        eraseList.reserve(64);

        const CallConv& conv = CallConv::get(callConvKind);

        bool                     processRegion = false;
        const MicroStorage::View view          = storage.view();
        for (auto it = view.end(); it != view.begin();)
        {
            --it;
            const MicroInstrRef instRef = it.current;
            const MicroInstr&   inst    = *it;

            const MicroInstrUseDef useDef = inst.collectUseDef(operands, encoder);
            if (useDef.isCall)
            {
                if (!processRegion)
                    continue;

                const CallConv& convAtCall = CallConv::get(useDef.callConv);

                killCallClobberedRegs(liveRegs, convAtCall);
                addCallArgumentRegs(liveRegs, convAtCall);
                for (const MicroReg useReg : useDef.uses)
                    liveRegs.insert(useReg.packed);
                continue;
            }

            if (isControlFlowBarrier(inst, useDef))
            {
                liveRegs.clear();
                if (inst.op == MicroInstrOpcode::Ret)
                {
                    processRegion = true;
                    addLiveReg(liveRegs, conv.intReturn);
                    addLiveReg(liveRegs, conv.floatReturn);
                    continue;
                }

                processRegion = false;
                continue;
            }

            if (!processRegion)
                continue;

            if (!isBackwardDeadDefRemovableInstruction(inst) || !isPureDefCandidate(inst, useDef, encoder, callConvKind))
            {
                for (const MicroReg defReg : useDef.defs)
                    liveRegs.erase(defReg.packed);
                for (const MicroReg useReg : useDef.uses)
                    liveRegs.insert(useReg.packed);
                continue;
            }

            const uint32_t defKey = useDef.defs.front().packed;
            if (!liveRegs.contains(defKey))
            {
                eraseList.push_back(instRef);
                changed = true;
                continue;
            }

            for (const MicroReg defReg : useDef.defs)
                liveRegs.erase(defReg.packed);
            for (const MicroReg useReg : useDef.uses)
                liveRegs.insert(useReg.packed);
        }

        for (const MicroInstrRef ref : eraseList)
            storage.erase(ref);

        return changed;
    }

    bool eliminateDeadPureDefsByBackwardLiveness(MicroPassContext& context, MicroStorage& storage, const MicroOperandStorage& operands, const Encoder* encoder, CallConvKind callConvKind)
    {
        if (context.builder)
        {
            const MicroControlFlowGraph& controlFlowGraph = SWC_NOT_NULL(context.builder)->controlFlowGraph();
            if (!controlFlowGraph.hasUnsupportedControlFlowForCfgLiveness() && controlFlowGraph.supportsDeadCodeLiveness())
            {
                if (eliminateDeadPureDefsByBackwardLivenessCfg(storage, operands, encoder, callConvKind, controlFlowGraph))
                    return true;
                return eliminateDeadPureDefsByBackwardLivenessLinearTail(storage, operands, encoder, callConvKind);
            }
        }

        return eliminateDeadPureDefsByBackwardLivenessLinearTail(storage, operands, encoder, callConvKind);
    }
}

Result MicroDeadCodeEliminationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    bool                                        changed = false;
    std::unordered_map<uint32_t, MicroInstrRef> lastPureDefByReg;
    lastPureDefByReg.reserve(64);

    MicroStorage&              storage  = *SWC_NOT_NULL(context.instructions);
    const MicroOperandStorage& operands = *SWC_NOT_NULL(context.operands);
    for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
    {
        const MicroInstrRef currentRef = it.current;
        const MicroInstr&   inst       = *it;
        const auto*         ops        = inst.ops(operands);

        const MicroInstrUseDef useDef = inst.collectUseDef(operands, context.encoder);
        if (isControlFlowBarrier(inst, useDef))
        {
            lastPureDefByReg.clear();
            continue;
        }

        if (useDef.isCall)
        {
            // Calls consume argument registers and clobber transient registers.
            // The forward local-def map does not model ABI argument uses, so do not
            // propagate pure defs across calls.
            lastPureDefByReg.clear();
            continue;
        }

        for (const MicroReg useReg : useDef.uses)
            lastPureDefByReg.erase(useReg.packed);

        for (const MicroReg defReg : useDef.defs)
        {
            if (!canCurrentDefKillPreviousPureDef(inst, ops, defReg))
                continue;

            const auto previousDefIt = lastPureDefByReg.find(defReg.packed);
            if (previousDefIt != lastPureDefByReg.end())
            {
                storage.erase(previousDefIt->second);
                changed = true;
                lastPureDefByReg.erase(previousDefIt);
            }
        }

        const bool trackAsPureDef = isPureDefCandidate(inst, useDef, context.encoder, context.callConvKind);

        if (trackAsPureDef)
            lastPureDefByReg[useDef.defs.front().packed] = currentRef;
    }

    if (eliminateDeadPureDefsByBackwardLiveness(context, storage, operands, context.encoder, context.callConvKind))
        changed = true;

    context.passChanged = changed;
    return Result::Continue;
}

SWC_END_NAMESPACE();
