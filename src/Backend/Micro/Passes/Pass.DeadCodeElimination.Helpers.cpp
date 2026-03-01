#include "pch.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroInstrInfo.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.Private.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isFullWidthIntegerWrite(MicroOpBits opBits)
    {
        return opBits == MicroOpBits::B32 || opBits == MicroOpBits::B64;
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
}

namespace DeadCodeEliminationPass
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

    bool canCurrentDefKillPreviousPureDef(const MicroInstr& inst, const MicroInstrOperand* ops, const MicroReg defReg)
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

    bool isPureDefCandidate(const MicroInstr& inst, const MicroInstrUseDef& useDef, const Encoder* encoder, const CallConvKind callConvKind)
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

    void addLiveReg(std::unordered_set<MicroReg>& liveRegs, const MicroReg reg)
    {
        if (!reg.isValid() || reg.isNoBase())
            return;
        liveRegs.insert(reg);
    }

    void transferInstructionLiveness(std::unordered_set<MicroReg>&       outLiveIn,
                                     const std::unordered_set<MicroReg>& liveOut,
                                     const MicroInstr&                   inst,
                                     const MicroInstrUseDef&             useDef,
                                     const CallConvKind                  callConvKind)
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
}

SWC_END_NAMESPACE();
