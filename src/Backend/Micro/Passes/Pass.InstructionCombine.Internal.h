#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

class MicroStorage;
class MicroOperandStorage;

namespace InstructionCombine
{
    // A single rewrite command emitted by a pattern and applied after the
    // scan completes. Rewrites mutate opcode + operands in place when the
    // new operand count fits the existing block; otherwise allocOps forces
    // a fresh operand block allocation.
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

    // Context threaded through every pattern. Pointers (not references) so the
    // struct stays assignable and matches project conventions.
    struct Context
    {
        MicroStorage*                storage  = nullptr;
        MicroOperandStorage*         operands = nullptr;
        const MicroSsaState*         ssa      = nullptr;
        std::unordered_set<uint32_t> claimed;
        SmallVector<Action, 16>      actions;

        bool isClaimed(MicroInstrRef ref) const;

        // Claim every ref atomically: returns false without side-effects if
        // any was already claimed.
        bool claimAll(std::initializer_list<MicroInstrRef> refs);

        void emitErase(MicroInstrRef ref);
        void emitRewrite(MicroInstrRef                      ref,
                         MicroInstrOpcode                   newOp,
                         std::span<const MicroInstrOperand> newOps,
                         bool                               allocNewBlock = false);
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

    //===-- Shared helpers --------------------------------------------------===//

    bool        isSameOpBitsInt(MicroOpBits a, MicroOpBits b);
    bool        isRightIdentity(MicroOp op, MicroOpBits opBits, uint64_t imm);
    bool        isRightAbsorbing(MicroOp op, MicroOpBits opBits, uint64_t imm, uint64_t& outResult);
    bool        tryReassociate(MicroOp firstOp, uint64_t firstImm,
                               MicroOp secondOp, uint64_t secondImm,
                               MicroOpBits opBits,
                               MicroOp& outOp, uint64_t& outImm);
    bool        isMemFoldableOp(MicroOp op);
    bool        isControlOrCall(const MicroInstr& inst);
    bool        writesMemory(const MicroInstr& inst);
    MicroOpBits useReadBits(const MicroInstr& useInst, const MicroInstrOperand* useOps, MicroReg reg);

    //===-- Patterns (one per file) -----------------------------------------===//

    bool tryOpBinaryRegImm(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryOpBinaryRegReg(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryMemoryFoldTriple(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldMemoryAddressing(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryNarrowExtend(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);

    //===-- Whole-IR scans --------------------------------------------------===//

    void runStoreToLoadForwarding(Context& ctx);
}

SWC_END_NAMESPACE();
