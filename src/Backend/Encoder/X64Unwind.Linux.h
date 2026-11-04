#pragma once
#include "Backend/Encoder/X64DwarfFrame.h"
#include "Backend/Encoder/X64Unwind.h"
#include "Backend/Micro/MicroInstr.h"

SWC_BEGIN_NAMESPACE();

// DWARF describes every instruction boundary, including epilogues and cold blocks.
// Analyze stack state along CFG edges before mapping those states to final byte offsets.
class X64UnwindLinux final : public X64Unwind
{
public:
    void prepare(MicroBuilder& builder, CallConvKind callConv, const Encoder* encoder) override;
    void reset() override;
    void buildInfo(ByteArray& outUnwindInfo, uint32_t codeSize) const override;
    void onInstructionEncoded(const MicroInstr& inst, const MicroInstrOperand* ops, uint32_t codeStartOffset, uint32_t codeEndOffset) override;

private:
    static constexpr int64_t  K_UNKNOWN = std::numeric_limits<int64_t>::max();
    static constexpr uint32_t K_SP      = 4;

    struct State
    {
        std::array<int64_t, 16> frameDistance;
        std::array<int32_t, 32> saved{};
        uint32_t                original = 0;
        uint32_t                cfaReg   = K_SP;
    };

    struct Block
    {
        uint32_t first = 0;
        uint32_t end   = 0;
        State    entry{};
        bool     reached = false;
        bool     queued  = false;
    };

    static int64_t adjustDistance(int64_t distance, int64_t amount, bool subtract);
    static uint32_t registerSlot(MicroReg reg);
    static uint32_t dwarfRegister(uint32_t slot);
    State initialState() const;
    void transfer(State& state, const MicroInstr& inst, const MicroInstrOperand* ops);
    void emitState(const State& state, uint32_t codeOffset);
    static bool merge(State& into, const State& incoming);

    std::vector<const MicroInstr*> instructions_;
    std::vector<uint32_t>          blockOf_;
    std::vector<Block>             blocks_;
    MicroInstrUseDef              useDef_;
    State                         current_{};
    State                         emitted_{};
    X64DwarfFrame                  frame_;
    uint32_t                      persistent_ = 0;
    uint32_t                      frameReg_   = 5;
    uint32_t                      cursor_     = 0;
    const MicroOperandStorage*    operands_   = nullptr;
    const Encoder*                encoder_    = nullptr;
};

SWC_END_NAMESPACE();
