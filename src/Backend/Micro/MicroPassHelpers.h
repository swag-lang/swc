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

    bool violatesEncoderConformance(const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops);
    bool instructionActuallyUsesCpuFlags(const MicroInstr& inst, const MicroInstrOperand* ops);
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

    // Fold a binary integer operation on two immediate values.
    // Maps MicroOp to Math::FoldBinaryOp and delegates to Math::foldBinaryInt.
    // Returns Math::FoldStatus::Unsupported if the MicroOp has no fold mapping.
    Math::FoldStatus foldBinaryImmediate(uint64_t& outValue, uint64_t lhs, uint64_t rhs, MicroOp op, MicroOpBits opBits);
    bool             tryReassociateBinaryImmediate(MicroOp firstOp, uint64_t firstImm, MicroOp secondOp, uint64_t secondImm, MicroOpBits opBits, MicroOp& outOp, uint64_t& outImm);
}

SWC_END_NAMESPACE();
