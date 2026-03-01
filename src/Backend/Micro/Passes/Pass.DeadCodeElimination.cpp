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
    void addCallArgumentRegs(std::unordered_set<MicroReg>& liveRegs, const CallConv& conv)
    {
        for (const MicroReg reg : conv.intArgRegs)
            liveRegs.insert(reg);
        for (const MicroReg reg : conv.floatArgRegs)
            liveRegs.insert(reg);
    }

    void killCallClobberedRegs(std::unordered_set<MicroReg>& liveRegs, const CallConv& conv)
    {
        for (const MicroReg reg : conv.intTransientRegs)
            liveRegs.erase(reg);
        for (const MicroReg reg : conv.floatTransientRegs)
            liveRegs.erase(reg);
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

    bool definesSpecialRegister(MicroRegSpan defs, const Encoder* encoder, CallConvKind callConvKind)
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

    void addLiveReg(std::unordered_set<MicroReg>& liveRegs, MicroReg reg)
    {
        if (!reg.isValid() || reg.isNoBase())
            return;
        liveRegs.insert(reg);
    }

    void transferInstructionLiveness(std::unordered_set<MicroReg>&       outLiveIn,
                                     const std::unordered_set<MicroReg>& liveOut,
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
                outLiveIn.insert(useReg);
            return;
        }

        for (const MicroReg defReg : useDef.defs)
            outLiveIn.erase(defReg);

        for (const MicroReg useReg : useDef.uses)
            outLiveIn.insert(useReg);
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
        std::vector<std::unordered_set<MicroReg>> liveIn(instructionCount);
        std::vector<std::unordered_set<MicroReg>> liveOut(instructionCount);
        bool                                      dataflowUpdated = true;
        while (dataflowUpdated)
        {
            dataflowUpdated = false;

            for (size_t i = instructionCount; i > 0; --i)
            {
                const size_t        idx            = i - 1;
                const MicroInstrRef instructionRef = instructionRefs[idx];
                const MicroInstr*   inst           = storage.ptr(instructionRef);
                if (!inst)
                    continue;

                const MicroInstrUseDef useDef = inst->collectUseDef(operands, encoder);

                std::unordered_set<MicroReg> newLiveOut;
                const SmallVector<uint32_t>& successors = controlFlowGraph.successors(static_cast<uint32_t>(idx));
                for (const uint32_t successorIndexRef : successors)
                {
                    const size_t successorIndex = successorIndexRef;
                    if (successorIndex >= liveIn.size())
                        continue;

                    const std::unordered_set<MicroReg>& successorLiveIn = liveIn[successorIndex];
                    for (const MicroReg reg : successorLiveIn)
                        newLiveOut.insert(reg);
                }

                std::unordered_set<MicroReg> newLiveIn;
                transferInstructionLiveness(newLiveIn, newLiveOut, *inst, useDef, callConvKind);

                if (newLiveOut != liveOut[idx] || newLiveIn != liveIn[idx])
                {
                    liveOut[idx]    = std::move(newLiveOut);
                    liveIn[idx]     = std::move(newLiveIn);
                    dataflowUpdated = true;
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

            const MicroReg defRegKey = useDef.defs.front();
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
        bool                         removedAny = false;
        std::unordered_set<MicroReg> liveRegs;
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
                    liveRegs.insert(useReg);
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
                    liveRegs.erase(defReg);
                for (const MicroReg useReg : useDef.uses)
                    liveRegs.insert(useReg);
                continue;
            }

            const MicroReg defKey = useDef.defs.front();
            if (!liveRegs.contains(defKey))
            {
                eraseList.push_back(instRef);
                removedAny = true;
                continue;
            }

            for (const MicroReg defReg : useDef.defs)
                liveRegs.erase(defReg);
            for (const MicroReg useReg : useDef.uses)
                liveRegs.insert(useReg);
        }

        for (const MicroInstrRef ref : eraseList)
            storage.erase(ref);

        return removedAny;
    }

    bool eliminateDeadPureDefsByBackwardLiveness(const MicroPassContext& context, MicroStorage& storage, const MicroOperandStorage& operands, const Encoder* encoder, CallConvKind callConvKind)
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

    lastPureDefByReg_.clear();
    lastPureDefByReg_.reserve(64);

    MicroStorage&              storage  = *context.instructions;
    const MicroOperandStorage& operands = *context.operands;
    for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
    {
        const MicroInstrRef currentRef = it.current;
        const MicroInstr&   inst       = *it;
        const auto*         ops        = inst.ops(operands);

        const MicroInstrUseDef useDef = inst.collectUseDef(operands, context.encoder);
        if (isControlFlowBarrier(inst, useDef))
        {
            lastPureDefByReg_.clear();
            continue;
        }

        if (useDef.isCall)
        {
            // Calls consume argument registers and clobber transient registers.
            // The forward local-def map does not model ABI argument uses, so do not
            // propagate pure defs across calls.
            lastPureDefByReg_.clear();
            continue;
        }

        for (const MicroReg useReg : useDef.uses)
            lastPureDefByReg_.erase(useReg);

        for (const MicroReg defReg : useDef.defs)
        {
            if (!canCurrentDefKillPreviousPureDef(inst, ops, defReg))
                continue;

            const auto previousDefIt = lastPureDefByReg_.find(defReg);
            if (previousDefIt != lastPureDefByReg_.end())
            {
                storage.erase(previousDefIt->second);
                context.passChanged = true;
                lastPureDefByReg_.erase(previousDefIt);
            }
        }

        const bool trackAsPureDef = isPureDefCandidate(inst, useDef, context.encoder, context.callConvKind);

        if (trackAsPureDef)
            lastPureDefByReg_[useDef.defs.front()] = currentRef;
    }

    if (eliminateDeadPureDefsByBackwardLiveness(context, storage, operands, context.encoder, context.callConvKind))
        context.passChanged = true;

    return Result::Continue;
}

SWC_END_NAMESPACE();
