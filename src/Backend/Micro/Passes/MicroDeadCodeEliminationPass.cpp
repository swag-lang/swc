#include "pch.h"
#include "Backend/Micro/Passes/MicroDeadCodeEliminationPass.h"

// Eliminates side-effect-free instructions whose results are not live.
// Example: add r1, 4; ... (r1 never used) -> <remove add>.
// Example: mov r2, r3; ... (r2 never used) -> <remove mov>.
// This pass keeps memory/branch/call side effects intact.

SWC_BEGIN_NAMESPACE();

namespace
{
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
        MicroReg stackPointerReg = MicroReg::invalid();
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
        if (useDef.isCall)
            return true;

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
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegReg:
                return true;
            default:
                return false;
        }
    }

    void addLiveReg(std::unordered_set<uint32_t>& liveRegs, MicroReg reg)
    {
        if (!reg.isValid() || reg.isNoBase())
            return;
        liveRegs.insert(reg.packed);
    }

    bool eliminateDeadPureDefsByBackwardLiveness(MicroStorage& storage, const MicroOperandStorage& operands, const Encoder* encoder, CallConvKind callConvKind)
    {
        bool                         changed = false;
        std::unordered_set<uint32_t> liveRegs;
        liveRegs.reserve(64);

        std::vector<Ref> eraseList;
        eraseList.reserve(64);

        const CallConv& conv = CallConv::get(callConvKind);

        bool startedSuffix = false;
        const MicroStorage::View view = storage.view();
        for (auto it = view.end(); it != view.begin();)
        {
            --it;
            const Ref              instRef = it.current;
            const MicroInstr&      inst    = *it;

            const MicroInstrUseDef useDef = inst.collectUseDef(operands, encoder);
            if (isControlFlowBarrier(inst, useDef))
            {
                if (!startedSuffix)
                {
                    if (inst.op == MicroInstrOpcode::Ret)
                    {
                        addLiveReg(liveRegs, conv.intReturn);
                        addLiveReg(liveRegs, conv.floatReturn);
                    }

                    continue;
                }

                break;
            }

            startedSuffix = true;

            if (!isBackwardDeadDefRemovableInstruction(inst) || !isPureDefCandidate(inst, useDef, encoder))
            {
                for (const MicroReg defReg : useDef.defs)
                    liveRegs.erase(defReg.packed);
                for (const MicroReg useReg : useDef.uses)
                    liveRegs.insert(useReg.packed);
                continue;
            }

            const uint32_t defKey = useDef.defs.front().packed;
            if (liveRegs.find(defKey) == liveRegs.end())
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
}

bool MicroDeadCodeEliminationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    bool                              changed = false;
    std::unordered_map<uint32_t, Ref> lastPureDefByReg;
    lastPureDefByReg.reserve(64);

    MicroStorage&              storage  = *SWC_CHECK_NOT_NULL(context.instructions);
    const MicroOperandStorage& operands = *SWC_CHECK_NOT_NULL(context.operands);
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

    return changed;
}

SWC_END_NAMESPACE();
