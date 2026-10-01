#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroStorage.h"
#include "Support/Core/RefTypes.h"
#include "Support/Math/Fold.h"
#include <unordered_set>

SWC_BEGIN_NAMESPACE();

struct MicroPassContext;
class MicroControlFlowGraph;
class MicroBuilder;

namespace MicroPassHelpers
{
    // The integer comparison conditions accepted by branch layout rewrites.
    inline bool invertLayoutBranchCondition(MicroCond& outInverted, MicroCond cond)
    {
        switch (cond)
        {
            case MicroCond::Equal: outInverted = MicroCond::NotEqual; return true;
            case MicroCond::NotEqual: outInverted = MicroCond::Equal; return true;
            case MicroCond::Zero: outInverted = MicroCond::NotZero; return true;
            case MicroCond::NotZero: outInverted = MicroCond::Zero; return true;
            case MicroCond::Below: outInverted = MicroCond::AboveOrEqual; return true;
            case MicroCond::AboveOrEqual: outInverted = MicroCond::Below; return true;
            case MicroCond::BelowOrEqual: outInverted = MicroCond::Above; return true;
            case MicroCond::Above: outInverted = MicroCond::BelowOrEqual; return true;
            case MicroCond::Less: outInverted = MicroCond::GreaterOrEqual; return true;
            case MicroCond::GreaterOrEqual: outInverted = MicroCond::Less; return true;
            case MicroCond::LessOrEqual: outInverted = MicroCond::Greater; return true;
            case MicroCond::Greater: outInverted = MicroCond::LessOrEqual; return true;
            default: return false;
        }
    }

    // Condition code after swapping the operands of an integer compare.
    // Conditions without a direct swapped form return false.
    inline bool swapCompareCondition(MicroCond& out, MicroCond in)
    {
        switch (in)
        {
            case MicroCond::Equal: out = MicroCond::Equal; return true;
            case MicroCond::NotEqual: out = MicroCond::NotEqual; return true;
            case MicroCond::Zero: out = MicroCond::Zero; return true;
            case MicroCond::NotZero: out = MicroCond::NotZero; return true;
            case MicroCond::Above: out = MicroCond::Below; return true;
            case MicroCond::AboveOrEqual: out = MicroCond::BelowOrEqual; return true;
            case MicroCond::Below: out = MicroCond::Above; return true;
            case MicroCond::BelowOrEqual: out = MicroCond::AboveOrEqual; return true;
            case MicroCond::Greater: out = MicroCond::Less; return true;
            case MicroCond::GreaterOrEqual: out = MicroCond::LessOrEqual; return true;
            case MicroCond::Less: out = MicroCond::Greater; return true;
            case MicroCond::LessOrEqual: out = MicroCond::GreaterOrEqual; return true;
            default: return false;
        }
    }

    inline bool isVariableScalarShiftOp(MicroOp op)
    {
        switch (op)
        {
            case MicroOp::ShiftLeft:
            case MicroOp::ShiftArithmeticLeft:
            case MicroOp::ShiftRight:
            case MicroOp::ShiftArithmeticRight:
            case MicroOp::RotateLeft:
            case MicroOp::RotateRight:
                return true;
            default:
                return false;
        }
    }

    inline uint64_t extendImmediateBits(uint64_t value, MicroOpBits srcBits, MicroOpBits dstBits, bool isSigned)
    {
        const uint64_t srcMask = getBitsMask(srcBits);
        uint64_t       masked  = value & srcMask;
        if (isSigned)
        {
            const uint32_t srcBitsNum = getNumBits(srcBits);
            const uint64_t signBit    = 1ULL << (srcBitsNum - 1);
            if (masked & signBit)
                masked |= ~srcMask;
        }
        return masked & getBitsMask(dstBits);
    }

    inline bool instructionReadsMemory(const MicroInstr& inst)
    {
        const MicroInstrDef& info = MicroInstr::info(inst.op);
        if (info.flags.has(MicroInstrFlagsE::HasMemBaseOffsetOperands) &&
            !info.flags.has(MicroInstrFlagsE::WritesMemory) &&
            inst.op != MicroInstrOpcode::LoadAddrRegMem)
            return true;

        return inst.op == MicroInstrOpcode::LoadAmcRegMem ||
               inst.op == MicroInstrOpcode::LoadSignedExtAmcRegMem ||
               inst.op == MicroInstrOpcode::LoadZeroExtAmcRegMem ||
               inst.op == MicroInstrOpcode::VecUnaryAmcRegMem;
    }

    // Immediate-dominator tree over the per-instruction CFG
    // (Cooper-Harvey-Kennedy). Shared by the passes that reason about
    // dominance on the linear instruction stream (LICM, value numbering).
    struct MicroDomTree
    {
        static constexpr uint32_t K_INVALID_NODE = std::numeric_limits<uint32_t>::max();

        // DFS intervals in the dominator tree. A subtree is a contiguous range;
        // querying ancestry needs no walk through the immediate dominators.
        std::vector<uint32_t> subtreeBegin;
        std::vector<uint32_t> subtreeEnd;

        bool reachable(uint32_t node) const { return node < subtreeBegin.size() && subtreeBegin[node] != K_INVALID_NODE; }

        bool dominates(uint32_t a, uint32_t b) const
        {
            if (!reachable(a) || !reachable(b))
                return false;
            return subtreeBegin[a] <= subtreeBegin[b] && subtreeBegin[b] < subtreeEnd[a];
        }
    };

    MicroDomTree computeInstructionDominators(const MicroControlFlowGraph& cfg, uint32_t entry);

    // Exact flag-level complement. Sign has no complement in MicroCond.
    bool invertCondition(MicroCond& outCondition, MicroCond condition);

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
    enum class MicroPhysLivenessMode : uint8_t
    {
        WithUseDefs,
        LiveOutOnly,
        DeadDefs,
        DeadDefsBeforePrologue,
    };

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
        // Set only in DeadDefs mode, after the liveness fixed point.
        std::vector<uint8_t> deadDefs;
        bool                 valid = false;

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
    // conservative) when the CFG does not support liveness. Callers select
    // only the per-instruction data they actually consume.
    void computePhysicalLiveness(MicroPhysLiveness& out, const MicroPassContext& context, MicroPhysLivenessMode mode = MicroPhysLivenessMode::WithUseDefs);

    // Whether the instruction leaves the top half of its destination register clear.
    //
    // A 32-bit write does on x86-64, which is what makes a 32-bit copy forwardable: the copy
    // itself clears that half, so reading the source instead of the destination is only the same
    // value when the source has it clear too. Everything not listed here answers no, including
    // the sign-extending forms and the eight-bit ones that preserve what was already there.
    bool definesZeroHighBits(const MicroInstr& inst, const MicroInstrOperand* ops);

    bool violatesEncoderConformance(const MicroPassContext& context, const MicroInstr& inst, const MicroInstrOperand* ops);
    bool instructionActuallyUsesCpuFlags(const MicroInstr& inst, const MicroInstrOperand* ops);
    // The opcode table flags every arithmetic form as a flag writer; the
    // micro-op decides: an exchange, a lea, a `not`, a byte swap, and every
    // float, conversion and packed operation leave the flags alone.
    bool instructionActuallyDefinesCpuFlags(const MicroInstr& inst, const MicroInstrOperand* ops);
    // A flag writer may preserve incoming flags: rotates and zero-count shifts
    // must not terminate a liveness proof. Keep any-write checks for invalidation.
    bool instructionOverwritesCpuFlags(const MicroInstr& inst, const MicroInstrOperand* ops);
    // Relocations of direct calls whose target promises no caller-visible writes.
    // Callers still verify the instruction is a direct call before using the set.
    std::unordered_set<uint32_t> collectReadOnlyCallRefs(const MicroBuilder& builder);
    // Relocations of the calls that report a fault: the panic functions of the runtime.
    // The name alone decides. Every reader only moves or drops code a report makes cold,
    // so taking another function of that name for one changes nothing a program observes.
    std::unordered_set<uint32_t> collectReportCallRefs(const MicroBuilder& builder);
    // A straight-line proof, ending at a flag overwrite, call, or return.
    // Jumps preserve flags and require the CFG variant to prove their successors.
    bool areCpuFlagsDeadAfter(const MicroStorage& storage, const MicroOperandStorage& operands, MicroInstrRef afterRef, MicroBuilder* builder = nullptr);

    // True when the CPU flags are redefined after 'instRef' before any label,
    // jump, call, or terminator. Unlike areCpuFlagsDeadAfter, this also stops
    // at labels and requires an actual overwrite rather than an ABI boundary.
    bool areCpuFlagsRedefinedBeforeBoundary(const MicroStorage& storage, const MicroOperandStorage& operands, MicroInstrRef instRef);

    // True when no path out of the instruction at 'index' reads the CPU flags
    // before redefining them: the straight line, and past a jump or a label
    // every successor in the graph. The exact form of the boundary criterion,
    // for a transform that removes a flag definition inside a branch. A call
    // ends a path like a definition does.
    bool areCpuFlagsDeadAfterInCfg(const MicroControlFlowGraph& cfg, const MicroStorage& storage, const MicroOperandStorage& operands, uint32_t index);
    bool areCpuFlagsDeadAfterInCfg(MicroBuilder& builder, MicroInstrRef afterRef);

    // Flow-insensitive closure of frame-derived addresses through copies,
    // address computations and additions. Consumers use the same conservative
    // set when coordinating memory forwarding with scalar stack promotion.
    void collectFrameDerivedRegs(std::unordered_set<MicroReg>& out, const MicroStorage& storage, const MicroOperandStorage& operands, MicroReg stackPointer);

    // The frame extents [lo, hi) of the function's stack locals, as offsets from the frame base
    // the code generator names (MicroPassContext::debugStackBaseVirtualReg). Frame objects are
    // disjoint, and an address formed from one object reaches that object alone, so these are
    // what bounds an escaped frame address. Empty when the lowered function is unknown, or its
    // locals hang from another register.
    void collectFrameVariableExtents(std::vector<std::pair<uint64_t, uint64_t>>& out, const MicroPassContext& context, MicroReg frameBase);

    // First virtual register index not used by any operand, starting above the
    // builder's hint. Passes that synthesize registers allocate upward from here.
    uint32_t computeNextVirtualIntRegIndex(const MicroPassContext& context);
    uint32_t computeNextVirtualFloatRegIndex(const MicroPassContext& context);
    // One operand walk when a pass needs fresh registers from both files.
    void computeNextVirtualRegIndices(const MicroPassContext& context, uint32_t& outIntIndex, uint32_t& outFloatIndex);

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

    // The registers the code generator marked as the address of an immutable value-handle
    // parameter, kept only when the function still honors the mark: one definition from the
    // incoming argument, and no use but as the base of a read - or, for a value handle, as an
    // argument handed on to a callee. A register that is copied elsewhere, offset, stored, or
    // written through may name storage someone else changes.
    void collectImmutableStorageBases(std::unordered_set<MicroReg>& out, const MicroPassContext& context);

    // Fold a binary integer operation on two immediate values.
    // Maps MicroOp to Math::FoldBinaryOp and delegates to Math::foldBinaryInt.
    // Returns Math::FoldStatus::Unsupported if the MicroOp has no fold mapping.
    Math::FoldStatus foldBinaryImmediate(uint64_t& outValue, uint64_t lhs, uint64_t rhs, MicroOp op, MicroOpBits opBits);
    bool             tryReassociateBinaryImmediate(MicroOp firstOp, uint64_t firstImm, MicroOp secondOp, uint64_t secondImm, MicroOpBits opBits, MicroOp& outOp, uint64_t& outImm);
}

SWC_END_NAMESPACE();
