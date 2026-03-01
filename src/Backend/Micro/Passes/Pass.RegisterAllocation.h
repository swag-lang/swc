#pragma once
#include "Backend/Micro/MicroPassManager.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

struct CallConv;
class MicroStorage;
class MicroOperandStorage;

class MicroRegisterAllocationPass final : public MicroPass
{
public:
    std::string_view  name() const override { return "regalloc"; }
    MicroRegPrintMode printModeBefore() const override { return MicroRegPrintMode::Virtual; }
    Result            run(MicroPassContext& context) override;
    struct VRegState
    {
        MicroReg    phys;
        uint64_t    spillOffset = 0;
        MicroOpBits spillBits   = MicroOpBits::B64;
        bool        mapped      = false;
        bool        hasSpill    = false;
        bool        dirty       = false;
    };

private:
    void clearState();

    MicroPassContext*    context_      = nullptr;
    const CallConv*      conv_         = nullptr;
    MicroStorage*        instructions_ = nullptr;
    MicroOperandStorage* operands_     = nullptr;

    uint32_t instructionCount_ = 0;
    uint64_t spillFrameUsed_   = 0;
    bool     hasControlFlow_   = false;

    std::vector<std::vector<MicroReg>>                  liveOut_;
    std::vector<std::vector<MicroReg>>                  concreteLiveOut_;
    std::unordered_set<MicroReg>                        vregsLiveAcrossCall_;
    std::unordered_map<MicroReg, std::vector<uint32_t>> usePositions_;

    std::unordered_set<MicroReg> intPersistentSet_;
    std::unordered_set<MicroReg> floatPersistentSet_;

    SmallVector<MicroReg> freeIntTransient_;
    SmallVector<MicroReg> freeIntPersistent_;
    SmallVector<MicroReg> freeFloatTransient_;
    SmallVector<MicroReg> freeFloatPersistent_;

    std::unordered_map<MicroReg, VRegState> states_;
    std::unordered_map<MicroReg, MicroReg>  mapping_;
    std::unordered_map<MicroReg, uint32_t>  liveStamp_;
    std::unordered_map<MicroReg, uint32_t>  concreteLiveStamp_;
    std::unordered_set<MicroReg>            callSpillVregs_;
};

SWC_END_NAMESPACE();
