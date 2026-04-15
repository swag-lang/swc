#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class MicroStorage;
class MicroOperandStorage;

namespace PreRaPeephole
{
    struct Action
    {
        static constexpr uint8_t K_MAX_OPS = 8;

        MicroInstrRef     ref            = MicroInstrRef::invalid();
        MicroInstrOpcode  newOp          = MicroInstrOpcode::Nop;
        uint8_t           numOps         = 0;
        MicroInstrOperand ops[K_MAX_OPS] = {};
        bool              erase          = false;
        bool              allocOps       = false;
    };

    struct Context
    {
        MicroStorage*                storage  = nullptr;
        MicroOperandStorage*         operands = nullptr;
        std::unordered_set<uint32_t> claimed;
        SmallVector<Action>          actions;

        bool                     isClaimed(MicroInstrRef ref) const;
        bool                     claimAll(std::initializer_list<MicroInstrRef> refs);
        void                     emitErase(MicroInstrRef ref);
        void                     emitRewrite(MicroInstrRef ref, MicroInstrOpcode newOp, std::span<const MicroInstrOperand> newOps, bool allocNewBlock = false);
        const MicroInstr*        instruction(MicroInstrRef ref) const;
        const MicroInstrOperand* operandsFor(MicroInstrRef ref) const;
        MicroInstrRef            nextRef(MicroInstrRef ref) const;
    };

    using PatternFn = bool (*)(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);

    struct PatternRegistry
    {
        static constexpr size_t K_OPCODE_COUNT = MICRO_INSTR_OPCODE_INFOS.size();

        std::array<SmallVector<PatternFn, 2>, K_OPCODE_COUNT> byOpcode;

        void                       add(MicroInstrOpcode op, PatternFn fn);
        std::span<const PatternFn> patternsFor(MicroInstrOpcode op) const;
    };

    bool     buildUseOnlyRegRewrite(Action& outAction, const MicroInstr& consumer, const MicroInstrOperand* ops, MicroReg fromReg, MicroReg toReg);
    uint64_t extendBits(uint64_t value, MicroOpBits srcBits, MicroOpBits dstBits, bool isSigned);
    void     setMaskedImmediateValue(MicroInstrOperand& op, uint64_t value, MicroOpBits bits);

    void applyAction(const Context& ctx, const Action& action);

    bool tryForwardConstantLike(Context& ctx, MicroInstrRef defRef, const MicroInstr& defInst);
    bool tryFoldCopyAddIntoLoadAddress(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryForwardCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryForwardLoadAddr(Context& ctx, MicroInstrRef defRef, const MicroInstr& defInst);
    bool tryForwardLoadAddrAmc(Context& ctx, MicroInstrRef defRef, const MicroInstr& defInst);
    bool tryCombineAdjacentRegImm(Context& ctx, MicroInstrRef firstRef, const MicroInstr& firstInst);
}

SWC_END_NAMESPACE();
