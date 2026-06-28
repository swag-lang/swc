#pragma once
#include "Support/Core/RefTypes.h"
#include "Backend/Micro/MicroInstr.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class MicroStorage;
class MicroOperandStorage;
class Encoder;

namespace PostRaPeephole
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
        const Encoder*               encoder  = nullptr;
        std::unordered_set<uint32_t> claimed;
        SmallVector<Action>          actions;

        // Copy/const forwarding is only run while this is set (the first
        // post-RA sweep). See MicroPassContext::isFirstOptimizationSweep.
        bool allowForwarding = true;

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

        void                       add(MicroInstrOpcode op, PatternFn fn);
        std::span<const PatternFn> patternsFor(MicroInstrOpcode op) const;
    };

    void applyAction(const Context& ctx, const Action& action);

    bool isTriviallyErasableNoEffect(const MicroInstr& inst, const MicroInstrOperand* ops);
    bool instructionActuallyUsesCpuFlags(const MicroInstr& inst, const MicroInstrOperand* ops);
    bool isRedundantFallthroughJumpToNextLabel(const Context& ctx, MicroInstrRef ref, const MicroInstr& inst, const MicroInstrOperand* ops);

    bool tryEraseTrivial(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryEraseDeadCompare(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryReuseFlagsForCompare(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst);
    bool tryForwardLoadRegImm(Context& ctx, MicroInstrRef defRef, const MicroInstr& defInst);
    bool tryForwardCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryCanonicalizeZeroToClear(Context& ctx, MicroInstrRef defRef, const MicroInstr& defInst);
}

SWC_END_NAMESPACE();
