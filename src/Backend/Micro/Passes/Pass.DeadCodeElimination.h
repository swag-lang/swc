#pragma once
#include "Backend/Micro/MicroDenseRegIndex.h"
#include "Backend/Micro/MicroPassManager.h"
#include "Support/Core/SmallVector.h"

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
    bool eliminateDeadPureDefsByBackwardLiveness();
    bool eliminateDeadPureDefsByBackwardLivenessCfg(const MicroControlFlowGraph& controlFlowGraph);
    bool eliminateDeadPureDefsByBackwardLivenessLinearTail();

    static void addCallArgumentRegs(std::unordered_set<MicroReg>& liveRegs, const CallConv& conv);
    static void killCallClobberedRegs(std::unordered_set<MicroReg>& liveRegs, const CallConv& conv);
    static bool canCurrentDefKillPreviousPureDef(const MicroInstr& inst, const MicroInstrOperand* ops, MicroReg defReg);
    static bool isControlFlowBarrier(const MicroInstr& inst);
    static bool isPureDefCandidate(const MicroInstr& inst, const MicroInstrUseDef& useDef, const Encoder* encoder, CallConvKind callConvKind);
    static bool isBackwardDeadDefRemovableInstruction(const MicroInstr& inst);
    bool        areCpuFlagsDeadAfterInstruction(MicroInstrRef instructionRef) const;
    static void addLiveReg(std::unordered_set<MicroReg>& liveRegs, MicroReg reg);
    static void transferInstructionLiveness(std::unordered_set<MicroReg>& outLiveIn, const std::unordered_set<MicroReg>& liveOut, const MicroInstr& inst, const MicroInstrUseDef& useDef, CallConvKind callConvKind);

    MicroPassContext*                           context_      = nullptr;
    MicroStorage*                               storage_      = nullptr;
    const MicroOperandStorage*                  operands_     = nullptr;
    const Encoder*                              encoder_      = nullptr;
    CallConvKind                                callConvKind_ = CallConvKind::Host;
    std::unordered_map<MicroReg, MicroInstrRef> lastPureDefByReg_;

    // Reusable buffers for CFG liveness analysis
    std::vector<const MicroInstr*>        cfgInstructionPtrs_;
    std::vector<uint8_t>                  cfgPureDefCandidateFlags_;
    std::vector<uint32_t>                 cfgPureDefDenseDefIndex_;
    std::vector<SmallVector<uint32_t, 4>> cfgKillDenseIndices_;
    std::vector<SmallVector<uint32_t, 4>> cfgUseDenseIndices_;
    std::vector<uint64_t>                 cfgLiveInBits_;
    std::vector<SmallVector<uint32_t, 2>> cfgPredecessors_;
    std::vector<uint32_t>                 cfgWorklist_;
    std::vector<uint8_t>                  cfgInWorklist_;
    std::vector<uint64_t>                 cfgTempOut_;
    std::vector<uint64_t>                 cfgTempIn_;
    std::vector<MicroInstrRef>            cfgEraseList_;

    // Reusable buffers for linear tail liveness
    std::unordered_set<MicroReg> linearLiveRegs_;
    std::vector<MicroInstrRef>   linearEraseList_;
};

SWC_END_NAMESPACE();
