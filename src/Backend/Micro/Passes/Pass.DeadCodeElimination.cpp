#include "pch.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"
#include "Backend/Micro/MicroInstrInfo.h"

// Eliminates side-effect-free instructions whose results are not live.
// Example: add r1, 4; ... (r1 never used) -> <remove add>.
// Example: mov r2, r3; ... (r2 never used) -> <remove mov>.
// This pass keeps memory/branch/call side effects intact.

SWC_BEGIN_NAMESPACE();

namespace
{
    struct InstructionIndexData
    {
        std::vector<Ref>             refs;
        std::unordered_map<Ref, Ref> labelRefToInstructionRef;
        std::unordered_map<Ref, Ref> instructionRefToIndex;
    };

    struct ControlFlowData
    {
        std::vector<std::vector<Ref>> successors;
    };

    void addCallArgumentRegs(std::unordered_set<uint32_t>& liveRegs, const CallConv& conv)
    {
        for (const MicroReg reg : conv.intArgRegs)
            liveRegs.insert(reg.packed);
        for (const MicroReg reg : conv.floatArgRegs)
            liveRegs.insert(reg.packed);
    }

    void addHiddenIndirectReturnArgReg(std::unordered_set<uint32_t>& liveRegs, const CallConv& conv)
    {
        if (!conv.intArgRegs.empty())
            liveRegs.insert(conv.intArgRegs.front().packed);
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

    bool definesSpecialRegister(std::span<const MicroReg> defs, const Encoder* encoder)
    {
        MicroReg stackPointerReg;
        if (encoder)
            stackPointerReg = encoder->stackPointerReg();

        for (const MicroReg reg : defs)
        {
            if (reg.isInstructionPointer())
                return true;

            if (stackPointerReg.isValid() && reg == stackPointerReg)
                return true;

            if (reg.isInt() && reg.index() == 4)
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
            case MicroInstrOpcode::JumpTable:
            case MicroInstrOpcode::Ret:
                return true;
            default:
                return false;
        }
    }

    bool isPureDefCandidate(const MicroInstr& inst, const MicroInstrUseDef& useDef, const Encoder* encoder)
    {
        return isRemovableInstruction(inst) &&
               !definesSpecialRegister(useDef.defs, encoder) &&
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

    bool isUnsupportedControlFlowForCfgLiveness(const MicroInstr& inst)
    {
        switch (inst.op)
        {
            case MicroInstrOpcode::JumpReg:
            case MicroInstrOpcode::JumpTable:
            case MicroInstrOpcode::JumpCondImm:
                return true;
            default:
                return false;
        }
    }

    bool buildInstructionIndexData(const MicroStorage& storage, const MicroOperandStorage& operands, InstructionIndexData& outData)
    {
        outData.refs.clear();
        outData.labelRefToInstructionRef.clear();
        outData.instructionRefToIndex.clear();

        outData.refs.reserve(storage.count());
        outData.labelRefToInstructionRef.reserve(storage.count());
        outData.instructionRefToIndex.reserve(storage.count());

        Ref index = 0;
        for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
        {
            const Ref instructionRef = it.current;
            outData.refs.push_back(instructionRef);
            outData.instructionRefToIndex[instructionRef] = index;
            ++index;

            if (it->op != MicroInstrOpcode::Label)
                continue;

            const MicroInstrOperand* labelOps = it->ops(operands);
            if (!labelOps || labelOps[0].valueU64 > std::numeric_limits<Ref>::max())
                return false;

            const Ref labelRef                         = static_cast<Ref>(labelOps[0].valueU64);
            outData.labelRefToInstructionRef[labelRef] = instructionRef;
        }

        return true;
    }

    bool buildControlFlowData(const MicroStorage& storage, const MicroOperandStorage& operands, const InstructionIndexData& indexData, ControlFlowData& outData)
    {
        outData.successors.clear();
        outData.successors.resize(indexData.refs.size());

        const size_t instructionCount = indexData.refs.size();
        for (size_t i = 0; i < instructionCount; ++i)
        {
            const Ref         instructionRef = indexData.refs[i];
            const MicroInstr* inst           = storage.ptr(instructionRef);
            if (!inst)
                return false;

            const bool hasFallthrough = i + 1 < instructionCount;
            if (inst->op == MicroInstrOpcode::JumpCond)
            {
                const MicroInstrOperand* jumpOps = inst->ops(operands);
                if (!jumpOps || jumpOps[2].valueU64 > std::numeric_limits<Ref>::max())
                    return false;

                const Ref  targetLabelRef = static_cast<Ref>(jumpOps[2].valueU64);
                const auto targetRefIt    = indexData.labelRefToInstructionRef.find(targetLabelRef);
                if (targetRefIt == indexData.labelRefToInstructionRef.end())
                    return false;

                const auto targetIndexIt = indexData.instructionRefToIndex.find(targetRefIt->second);
                if (targetIndexIt == indexData.instructionRefToIndex.end())
                    return false;

                std::vector<Ref>& successors = outData.successors[i];
                successors.push_back(targetIndexIt->second);
                if (!MicroInstrInfo::isUnconditionalJumpInstruction(*inst, jumpOps) && hasFallthrough)
                    successors.push_back(static_cast<Ref>(i + 1));
                continue;
            }

            if (inst->op == MicroInstrOpcode::Ret)
                continue;

            if (MicroInstrInfo::isTerminatorInstruction(*inst))
                return false;

            if (hasFallthrough)
                outData.successors[i].push_back(static_cast<Ref>(i + 1));
        }

        return true;
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
            addHiddenIndirectReturnArgReg(outLiveIn, conv);
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

    bool eliminateDeadPureDefsByBackwardLivenessCfg(MicroStorage& storage, const MicroOperandStorage& operands, const Encoder* encoder, CallConvKind callConvKind)
    {
        InstructionIndexData indexData;
        if (!buildInstructionIndexData(storage, operands, indexData))
            return false;

        if (indexData.refs.empty())
            return false;

        ControlFlowData controlFlowData;
        if (!buildControlFlowData(storage, operands, indexData, controlFlowData))
            return false;

        const size_t                              instructionCount = indexData.refs.size();
        std::vector<std::unordered_set<uint32_t>> liveIn(instructionCount);
        std::vector<std::unordered_set<uint32_t>> liveOut(instructionCount);
        bool                                      changed = true;
        while (changed)
        {
            changed = false;

            for (size_t i = instructionCount; i > 0; --i)
            {
                const size_t      idx            = i - 1;
                const Ref         instructionRef = indexData.refs[idx];
                const MicroInstr* inst           = storage.ptr(instructionRef);
                if (!inst)
                    continue;

                const MicroInstrUseDef useDef = inst->collectUseDef(operands, encoder);

                std::unordered_set<uint32_t> newLiveOut;
                const std::vector<Ref>&      successors = controlFlowData.successors[idx];
                for (const Ref successorIndexRef : successors)
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

        bool             removedAny = false;
        std::vector<Ref> eraseList;
        eraseList.reserve(64);

        for (size_t i = 0; i < instructionCount; ++i)
        {
            const Ref         instructionRef = indexData.refs[i];
            const MicroInstr* inst           = storage.ptr(instructionRef);
            if (!inst)
                continue;

            const MicroInstrUseDef useDef = inst->collectUseDef(operands, encoder);
            if (!isBackwardDeadDefRemovableInstruction(*inst) || !isPureDefCandidate(*inst, useDef, encoder))
                continue;

            const uint32_t defRegKey = useDef.defs.front().packed;
            if (liveOut[i].contains(defRegKey))
                continue;

            eraseList.push_back(instructionRef);
        }

        for (const Ref eraseRef : eraseList)
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

        std::vector<Ref> eraseList;
        eraseList.reserve(64);

        const CallConv& conv = CallConv::get(callConvKind);

        bool                     processRegion = false;
        const MicroStorage::View view          = storage.view();
        for (auto it = view.end(); it != view.begin();)
        {
            --it;
            const Ref         instRef = it.current;
            const MicroInstr& inst    = *it;

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
                    addHiddenIndirectReturnArgReg(liveRegs, conv);
                    continue;
                }

                processRegion = false;
                continue;
            }

            if (!processRegion)
                continue;

            if (!isBackwardDeadDefRemovableInstruction(inst) || !isPureDefCandidate(inst, useDef, encoder))
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

        for (const Ref ref : eraseList)
            storage.erase(ref);

        return changed;
    }

    bool eliminateDeadPureDefsByBackwardLiveness(MicroStorage& storage, const MicroOperandStorage& operands, const Encoder* encoder, CallConvKind callConvKind)
    {
        bool hasUnsupportedControlFlow = false;
        for (const MicroInstr& inst : storage.view())
        {
            if (!isUnsupportedControlFlowForCfgLiveness(inst))
                continue;
            hasUnsupportedControlFlow = true;
            break;
        }

        if (!hasUnsupportedControlFlow)
        {
            if (eliminateDeadPureDefsByBackwardLivenessCfg(storage, operands, encoder, callConvKind))
                return true;
            return eliminateDeadPureDefsByBackwardLivenessLinearTail(storage, operands, encoder, callConvKind);
        }

        return eliminateDeadPureDefsByBackwardLivenessLinearTail(storage, operands, encoder, callConvKind);
    }
}

Result MicroDeadCodeEliminationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    bool                              changed = false;
    std::unordered_map<uint32_t, Ref> lastPureDefByReg;
    lastPureDefByReg.reserve(64);

    MicroStorage&              storage  = *SWC_NOT_NULL(context.instructions);
    const MicroOperandStorage& operands = *SWC_NOT_NULL(context.operands);
    for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
    {
        const Ref   currentRef = it.current;
        MicroInstr& inst       = *it;
        const auto* ops        = inst.ops(operands);

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

        const bool trackAsPureDef = isPureDefCandidate(inst, useDef, context.encoder);

        if (trackAsPureDef)
            lastPureDefByReg[useDef.defs.front().packed] = currentRef;
    }

    if (eliminateDeadPureDefsByBackwardLiveness(storage, operands, context.encoder, context.callConvKind))
        changed = true;

    context.passChanged = changed;
    return Result::Continue;
}

SWC_END_NAMESPACE();
