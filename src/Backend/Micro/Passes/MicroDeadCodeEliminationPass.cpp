#include "pch.h"
#include "Backend/Micro/Passes/MicroDeadCodeEliminationPass.h"

SWC_BEGIN_NAMESPACE();

namespace
{
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
}

bool MicroDeadCodeEliminationPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);

    bool                                 changed = false;
    std::unordered_map<uint32_t, Ref> lastPureDefByReg;
    lastPureDefByReg.reserve(64);

    MicroStorage&        storage  = *SWC_CHECK_NOT_NULL(context.instructions);
    MicroOperandStorage& operands = *SWC_CHECK_NOT_NULL(context.operands);
    for (auto it = storage.view().begin(); it != storage.view().end(); ++it)
    {
        const Ref   currentRef = it.current;
        MicroInstr& inst       = *it;

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
            const auto previousDefIt = lastPureDefByReg.find(defReg.packed);
            if (previousDefIt != lastPureDefByReg.end())
            {
                storage.erase(previousDefIt->second);
                changed = true;
                lastPureDefByReg.erase(previousDefIt);
            }
        }

        const bool trackAsPureDef =
            isRemovableInstruction(inst) &&
            !definesSpecialRegister(useDef.defs, context.encoder) &&
            useDef.defs.size() == 1 &&
            !useDef.isCall;

        if (trackAsPureDef)
            lastPureDefByReg[useDef.defs.front().packed] = currentRef;
    }

    return changed;
}

SWC_END_NAMESPACE();
