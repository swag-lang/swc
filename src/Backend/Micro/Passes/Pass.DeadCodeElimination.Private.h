#pragma once
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroStorage.h"
#include "Backend/Micro/Passes/Pass.DeadCodeElimination.h"

SWC_BEGIN_NAMESPACE();

namespace DeadCodeEliminationPass
{
    void addCallArgumentRegs(std::unordered_set<MicroReg>& liveRegs, const CallConv& conv);
    void killCallClobberedRegs(std::unordered_set<MicroReg>& liveRegs, const CallConv& conv);
    bool canCurrentDefKillPreviousPureDef(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg defReg);
    bool isControlFlowBarrier(const MicroInstr& inst, const MicroInstrUseDef& useDef);
    bool isPureDefCandidate(const MicroInstr& inst, const MicroInstrUseDef& useDef, const Encoder* encoder, CallConvKind callConvKind);
    bool isBackwardDeadDefRemovableInstruction(const MicroInstr& inst);
    void addLiveReg(std::unordered_set<MicroReg>& liveRegs, MicroReg reg);
    void transferInstructionLiveness(std::unordered_set<MicroReg>&       outLiveIn,
                                     const std::unordered_set<MicroReg>& liveOut,
                                     const MicroInstr&                   inst,
                                     const MicroInstrUseDef&             useDef,
                                     CallConvKind                        callConvKind);
    bool runForwardPureDefElimination(MicroPassContext& context, std::unordered_map<MicroReg, MicroInstrRef>& lastPureDefByReg);
    bool eliminateDeadPureDefsByBackwardLiveness(const MicroPassContext& context, MicroStorage& storage, const MicroOperandStorage& operands, const Encoder* encoder, CallConvKind callConvKind);
}

SWC_END_NAMESPACE();
