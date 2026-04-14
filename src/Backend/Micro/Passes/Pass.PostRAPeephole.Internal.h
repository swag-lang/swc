#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class MicroStorage;
class MicroOperandStorage;

namespace PostRAPeephole
{
    struct Action
    {
        static constexpr uint8_t K_MAX_OPS = 5;

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
        SmallVector<Action, 16>      actions;

        bool                     isClaimed(MicroInstrRef ref) const;
        bool                     claimAll(std::initializer_list<MicroInstrRef> refs);
        void                     emitErase(MicroInstrRef ref);
        void                     emitRewrite(MicroInstrRef ref, MicroInstrOpcode newOp, std::span<const MicroInstrOperand> newOps, bool allocNewBlock = false);
        const MicroInstr*        instruction(MicroInstrRef ref) const;
        const MicroInstrOperand* operandsFor(MicroInstrRef ref) const;
        MicroInstrRef            nextRef(MicroInstrRef ref) const;
        MicroInstrRef            previousRef(MicroInstrRef ref) const;
    };

    using PatternFn = bool (*)(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);

    struct PatternRegistry
    {
        static constexpr size_t K_OPCODE_COUNT = MICRO_INSTR_OPCODE_INFOS.size();

        std::array<SmallVector<PatternFn, 2>, K_OPCODE_COUNT> byOpcode;

        void add(MicroInstrOpcode op, PatternFn fn);
        std::span<PatternFn const> patternsFor(MicroInstrOpcode op) const;
    };

    void applyAction(Context& ctx, const Action& action);

    bool isTriviallyErasableNoEffect(const MicroInstr& inst, const MicroInstrOperand* ops);
    bool instructionActuallyUsesCpuFlags(const MicroInstr& inst, const MicroInstrOperand* ops);
    bool isRedundantFallthroughJumpToNextLabel(Context& ctx, MicroInstrRef ref, const MicroInstr& inst, const MicroInstrOperand* ops);

    bool tryEraseTrivial(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryEraseDeadCompare(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
}

SWC_END_NAMESPACE();
