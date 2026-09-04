#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroStorage.h"
#include "Support/Core/RefTypes.h"
#include "Support/Math/Fold.h"

SWC_BEGIN_NAMESPACE();

struct MicroPassContext;
class MicroControlFlowGraph;

namespace MicroPassHelpers
{
    // Immediate-dominator tree over the per-instruction CFG
    // (Cooper-Harvey-Kennedy). Shared by the passes that reason about
    // dominance on the linear instruction stream (LICM, value numbering).
    struct MicroDomTree
    {
        static constexpr uint32_t K_INVALID_NODE = std::numeric_limits<uint32_t>::max();

        std::vector<uint32_t> idom;   // idom[entry] == entry; K_INVALID_NODE if unreachable
        std::vector<uint32_t> rpoPos; // position in reverse-postorder; K_INVALID_NODE if unreachable

        bool reachable(uint32_t node) const { return node < idom.size() && idom[node] != K_INVALID_NODE; }

        bool dominates(uint32_t a, uint32_t b) const
        {
            if (!reachable(a) || !reachable(b))
                return false;
            uint32_t x = b;
            while (x != a && x != idom[x])
                x = idom[x];
            return x == a;
        }
    };

    MicroDomTree computeInstructionDominators(const MicroControlFlowGraph& cfg, uint32_t entry);

    // The operand holding the condition code, for the opcodes that read the CPU flags through one.
    // Inline: the combine passes ask this of every instruction they scan.
    inline bool conditionOperandIndex(MicroInstrOpcode op, uint8_t& outIdx)
    {
        switch (op)
        {
            case MicroInstrOpcode::JumpCond:
            case MicroInstrOpcode::JumpCondImm:
                outIdx = 0;
                return true;
            case MicroInstrOpcode::SetCondReg:
                outIdx = 1;
                return true;
            case MicroInstrOpcode::LoadCondRegReg:
                outIdx = 2;
                return true;
            default:
                return false;
        }
    }

    // A natural loop on the per-instruction CFG: the header a back edge lands on, the tails those
    // back edges leave from, and the membership map of everything that reaches a tail without
    // leaving the header behind.
    struct NaturalLoop
    {
        uint32_t              header = MicroDomTree::K_INVALID_NODE;
        SmallVector<uint32_t> tails;
        std::vector<uint8_t>  inBody;
        uint32_t              bodySize = 0;

        void collectBody(const MicroControlFlowGraph& cfg);
    };

    // Every natural loop of the CFG, keyed by header and with its body already collected. Empty
    // when no back edge closes a loop.
    std::unordered_map<uint32_t, NaturalLoop> findNaturalLoops(const MicroControlFlowGraph& cfg, const MicroDomTree& dom);

    // The unique entry instruction of the per-instruction CFG, or
    // K_INVALID_NODE when there is no entry or more than one.
    uint32_t findSingleCfgEntry(const MicroControlFlowGraph& cfg);

    // Exact physical-register liveness over the per-instruction CFG, for the
    // passes that run after register allocation. A backward fixed point seeded
    // at the exits with the ABI live-out set (return registers, callee-saved
    // registers, stack and frame pointers).
    //
    // Post-RA passes that guessed liveness with a bounded linear scan forward
    // from an instruction had to answer "live" whenever the scan met a jump,
    // which is every value defined at the bottom of a loop body — exactly where
    // the interesting ones are. This answers the question instead of declining
    // it.
    struct MicroPhysLiveness
    {
        // One bit per physical register: 0-31 integer, 32-63 float. Post-RA
        // there is nothing else to track, and a bitmask keeps the fixed point
        // to a machine word per instruction — a set of MicroReg values scanned
        // linearly instead cost 4-10% of a whole `core` rebuild.
        static constexpr uint32_t K_FLOAT_BIT_BASE = 32;
        static constexpr uint32_t K_INVALID_BIT    = 64;

        static uint32_t bitOf(const MicroReg reg)
        {
            if (reg.isInt() && reg.index() < K_FLOAT_BIT_BASE)
                return reg.index();
            if (reg.isFloat() && reg.index() < K_FLOAT_BIT_BASE)
                return K_FLOAT_BIT_BASE + reg.index();
            return K_INVALID_BIT;
        }

        std::vector<MicroInstrUseDef> useDefs;
        std::vector<uint64_t>         liveIn;
        std::vector<uint64_t>         liveOut;
        bool                          valid = false;

        bool isLiveOut(uint32_t index, MicroReg reg) const
        {
            if (!valid || index >= liveOut.size())
                return true; // unknown: answer conservatively
            const uint32_t bit = bitOf(reg);
            if (bit >= K_INVALID_BIT)
                return true; // a register the mask cannot name: assume live
            return (liveOut[index] & (1ull << bit)) != 0;
        }
    };

    // Fills 'out' from the context's CFG. Leaves it invalid (and every query
    // conservative) when the CFG does not support liveness.
    void computePhysicalLiveness(MicroPhysLiveness& out, const MicroPassContext& context);

    bool violatesEncoderConformance(const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops);
    bool instructionActuallyUsesCpuFlags(const MicroInstr& inst, const MicroInstrOperand* ops);
    // The opcode table flags every arithmetic form as a flag writer; the
    // micro-op decides: an exchange, a lea, a `not`, a byte swap, and every
    // float, conversion and packed operation leave the flags alone.
    bool instructionActuallyDefinesCpuFlags(const MicroInstr& inst, const MicroInstrOperand* ops);
    bool areCpuFlagsDeadAfter(const MicroStorage& storage, const MicroOperandStorage& operands, MicroInstrRef afterRef);

    // True when the CPU flags are redefined after 'instRef' before any label,
    // jump, call, or terminator. Stricter than areCpuFlagsDeadAfter, whose
    // callers replace one flag definition with another in place: a transform
    // that REMOVES a flag definition outright must not lean on the "no flags
    // across control flow" convention — branch fusion does keep flags live
    // across a jump to the branches it fused — so only the straight-line
    // window up to the next boundary is trusted.
    bool areCpuFlagsRedefinedBeforeBoundary(const MicroStorage& storage, const MicroOperandStorage& operands, MicroInstrRef instRef);

    // First virtual register index not used by any operand, starting above the
    // builder's hint. Passes that synthesize registers allocate upward from here.
    uint32_t computeNextVirtualIntRegIndex(const MicroPassContext& context);
    uint32_t computeNextVirtualFloatRegIndex(const MicroPassContext& context);

    // Replace all uses of 'fromReg' with 'toReg' in instructions after 'afterInstRef',
    // within the same local flow region (stops at redefinition of either register, calls,
    // labels, branches). Returns the number of uses replaced.
    uint32_t replaceRegInLocalUses(MicroStorage& storage, MicroOperandStorage& operands, MicroInstrRef afterInstRef, MicroReg fromReg, MicroReg toReg);

    // The addressing-piece layout of the AMC opcode family. These instructions address
    // memory as base + index * scale + offset, and the table in 'MicroInstr.Def.inc' cannot
    // describe them the way it describes the base+offset forms: there is no single offset
    // operand, so they carry no 'HasMemBaseOffsetOperands' flag and every consumer has to
    // ask for the layout by opcode.
    struct AmcLayout
    {
        uint8_t baseIdx  = 1;
        uint8_t indexIdx = 2;
        uint8_t mulIdx   = 5;
        uint8_t addIdx   = 6;
    };

    bool amcLayoutFor(AmcLayout& out, MicroInstrOpcode op);

    // The operand holding the base register an instruction reads or writes THROUGH, in
    // either addressing shape. False when the instruction touches no memory, and false for
    // the address computations ('lea'), which form an address without dereferencing it.
    bool dereferenceBaseOperandIndex(uint8_t& outIndex, MicroInstrOpcode op, const MicroInstrDef& def);

    // Fold a binary integer operation on two immediate values.
    // Maps MicroOp to Math::FoldBinaryOp and delegates to Math::foldBinaryInt.
    // Returns Math::FoldStatus::Unsupported if the MicroOp has no fold mapping.
    Math::FoldStatus foldBinaryImmediate(uint64_t& outValue, uint64_t lhs, uint64_t rhs, MicroOp op, MicroOpBits opBits);
    bool             tryReassociateBinaryImmediate(MicroOp firstOp, uint64_t firstImm, MicroOp secondOp, uint64_t secondImm, MicroOpBits opBits, MicroOp& outOp, uint64_t& outImm);
}

SWC_END_NAMESPACE();
