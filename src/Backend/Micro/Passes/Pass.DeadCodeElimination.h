#pragma once
#include "Backend/Micro/MicroPassManager.h"

SWC_BEGIN_NAMESPACE();

class MicroControlFlowGraph;
class MicroStorage;
class MicroOperandStorage;
class Encoder;
struct CallConv;
struct MicroInstr;
struct MicroInstrOperand;
struct MicroInstrUseDef;

class MicroDeadCodeEliminationPass final : public MicroPass
{
public:
    std::string_view name() const override { return "dce"; }
    Result           run(MicroPassContext& context) override;

private:
    void initRunState(MicroPassContext& context);
    bool runForwardPureDefElimination();
    bool eliminateDeadPureDefsByBackwardLiveness() const;
    bool eliminateDeadPureDefsByBackwardLivenessCfg(const MicroControlFlowGraph& controlFlowGraph) const;
    bool eliminateDeadPureDefsByBackwardLivenessLinearTail() const;

    static void addCallArgumentRegs(std::unordered_set<MicroReg>& liveRegs, const CallConv& conv);
    static void killCallClobberedRegs(std::unordered_set<MicroReg>& liveRegs, const CallConv& conv);
    static bool canCurrentDefKillPreviousPureDef(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg defReg);
    static bool isControlFlowBarrier(const MicroInstr& inst, const MicroInstrUseDef& useDef);
    static bool isPureDefCandidate(const MicroInstr& inst, const MicroInstrUseDef& useDef, const Encoder* encoder, CallConvKind callConvKind);
    static bool isBackwardDeadDefRemovableInstruction(const MicroInstr& inst);
    static void addLiveReg(std::unordered_set<MicroReg>& liveRegs, MicroReg reg);
    static void transferInstructionLiveness(std::unordered_set<MicroReg>& outLiveIn, const std::unordered_set<MicroReg>& liveOut, const MicroInstr& inst, const MicroInstrUseDef& useDef, CallConvKind callConvKind);

    MicroPassContext*                           context_      = nullptr;
    MicroStorage*                               storage_      = nullptr;
    const MicroOperandStorage*                  operands_     = nullptr;
    const Encoder*                              encoder_      = nullptr;
    CallConvKind                                callConvKind_ = CallConvKind::Host;
    std::unordered_map<MicroReg, MicroInstrRef> lastPureDefByReg_;
};

SWC_END_NAMESPACE();
