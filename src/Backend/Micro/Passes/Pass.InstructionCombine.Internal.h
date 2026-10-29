#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroOptimizationLimits.h"
#include "Backend/Micro/MicroPassHelpers.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/Passes/Pass.Peephole.Core.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class MicroStorage;
class MicroOperandStorage;
class MicroBuilder;
struct MicroPassContext;

namespace InstructionCombine
{
    using MicroOptimizationLimits::InstructionCombine::K_MAX_COPY_CHAIN;

    // A single rewrite command emitted by a pattern and applied after the
    // scan completes. Rewrites mutate opcode + operands in place when the
    // new operand count fits the existing block; otherwise allocOps forces
    // a fresh operand block allocation.
    struct Action
    {
        // 8 to hold the widest indexed addressing-mode opcode (LoadAmcMemImm:
        // base, index, _, addrBits, valBits, scale, disp, imm). Plain
        // ALU/load rewrites use far fewer.
        static constexpr uint8_t K_MAX_OPS = 8;

        MicroInstrRef     ref            = MicroInstrRef::invalid();
        MicroInstrOpcode  newOp          = MicroInstrOpcode::Nop;
        uint8_t           numOps         = 0;
        MicroInstrOperand ops[K_MAX_OPS] = {};
        bool              erase          = false;
        bool              allocOps       = false;
        // A new instruction placed before `ref` instead of a rewrite of it.
        bool insert = false;
    };

    // Context threaded through every pattern. Pointers (not references) so the
    // struct stays assignable and matches project conventions.
    struct Context : MicroPeephole::RewriteQueue<Action>
    {
        MicroPassContext*    passContext = nullptr;
        const MicroSsaState* ssa         = nullptr;
        MicroBuilder*        builder     = nullptr;
        // Instructions that carry a relocation. Rewriting or erasing one
        // drops the relocation binding - the patch then lands wherever
        // codeOffset zero points - so claimAll refuses them unless a rule
        // that explicitly manages the relocation opts in.
        MicroPeephole::LazyU32Set relocated;
        // Registers a byte copy of a setcc result writes: the boolean merges
        // branch simplification reads as bytes, which keep their width.
        MicroPeephole::LazyU32Set booleanMerges;
        // Resolve select demand from the last reader backwards. Only committed
        // queued narrowings supply reduced read widths to earlier candidates.
        SmallVector<MicroInstrRef> pendingNarrowSelects;
        MicroPeephole::LazyU32Set  narrowedSelects;

        bool isRelocated(MicroInstrRef ref) const { return relocated.contains(ref.get()); }

        // The stack pointer of the calling convention, which every frame
        // address derives from.
        MicroReg stackPointer = MicroReg::invalid();

        // The next free virtual register of each file, for rules that build
        // new values; initialized once per run, when a rule first needs one.
        uint32_t nextVirtualFloatRegIndex = 0;
        uint32_t nextVirtualIntRegIndex   = 0;

        void ensureVirtualIndices()
        {
            if (nextVirtualIntRegIndex)
                return;
            SWC_ASSERT(passContext != nullptr);
            MicroPassHelpers::computeNextVirtualRegIndices(*passContext, nextVirtualIntRegIndex, nextVirtualFloatRegIndex);
        }

        enum class FloatReadFit : uint8_t
        {
            Unknown,
            Fits,
            DoesNotFit,
        };
        std::array<FloatReadFit, 2> floatReadFits{};
        bool                        allFloatReadsFit(MicroOpBits bits);
        bool                        booleanMergesReady = false;
        bool                        isBooleanMerge(MicroReg reg);

        // Queues a new instruction to be inserted before `ref`, in queue
        // order with the other insertions before the same instruction.
        void emitInsertBefore(MicroInstrRef ref, MicroInstrOpcode op, std::span<const MicroInstrOperand> newOps)
        {
            SWC_ASSERT(newOps.size() <= Action::K_MAX_OPS);
            Action& action = actions.emplace_back();
            action.ref     = ref;
            action.newOp   = op;
            action.numOps  = static_cast<uint8_t>(newOps.size());
            action.insert  = true;
            for (size_t idx = 0; idx < newOps.size(); ++idx)
                action.ops[idx] = newOps[idx];
        }

        // Whether the instruction sits inside a natural loop. The loop bodies
        // are collected on the first question, since only the memory folds
        // ask; a CFG the loop analysis cannot read answers yes for everything.
        bool isInsideLoop(MicroInstrRef ref);

        // Whether the instruction is a call that reports a fault. The set is collected
        // on the first question: only a rule that already found a guard asks.
        bool isReportCall(MicroInstrRef ref);

        bool       reportCallsReady = false;
        FlatKeySet reportCalls;

        // The instruction dominator tree of the function, computed on the first question; null
        // when the graph has no single entry or control flow the analysis cannot read.
        const MicroPassHelpers::MicroDomTree* guardDominators();

        bool                           guardDominatorsReady = false;
        bool                           guardDominatorsValid = false;
        MicroPassHelpers::MicroDomTree guardDominatorTree;

        bool       loopSlotsReady = false;
        bool       loopSlotsAll   = false;
        FlatKeySet loopSlots;

        // Whether the register is the base of storage the call cannot change: a value
        // parameter's incoming address. Collected on the first question.
        bool isImmutableStorageBase(MicroReg reg);

        bool       immutableBasesReady = false;
        FlatKeySet immutableBases;

        // Whether a 64-bit read through `base` at `displacement`, its index scaled by `scale`
        // when it has one, lands on a whole slot of a frame object every write of which leaves
        // the upper half zero. Collected on the first question.
        bool isZeroExtendedFrameRead(MicroReg base, MicroInstrRef ref, uint64_t displacement, uint64_t scale) const;

        mutable bool zeroExtendedFrameReady = false;
        // A frame address: its offset from the frame base, the stride an index adds to it
        // in multiples of (zero for an exact address), and for an indexed address the offset
        // of the object its base pointed at, which the index cannot leave.
        struct FrameAddress
        {
            static constexpr uint64_t K_NO_ANCHOR = UINT64_MAX;

            uint64_t offset = 0;
            uint64_t stride = 0;
            uint64_t anchor = K_NO_ANCHOR;
        };
        mutable FlatKeyMap<FrameAddress>                   frameAddresses;
        mutable std::optional<FlatKeyMap<uint64_t>>        frameStackPointerOffsets;
        mutable std::vector<std::pair<uint64_t, uint64_t>> zeroExtendedFrameObjects;

        // Whether nothing reads the CPU flags left after `ref`. The rules anchored on one
        // instruction ask it about that instruction in turn, each answer scanning ahead.
        bool areCpuFlagsDeadAfter(MicroInstrRef ref) const;

        // The last answer of each repeated question. The scan queues its rewrites and
        // mutates nothing, so an answer stays exact until the run ends; run() forgets
        // them before the next function.
        struct AddressAnswer
        {
            MicroReg      reg;
            MicroInstrRef atRef = MicroInstrRef::invalid();
            bool          value = false;
        };
        mutable AddressAnswer lastFrameDerivedAddress;
        mutable AddressAnswer lastRelocatedAddress;
        mutable MicroInstrRef lastFlagsDeadRef = MicroInstrRef::invalid();
        mutable bool          lastFlagsDead    = false;

        // Claim every ref atomically: returns false without side-effects if
        // any was already claimed, or if one carries a relocation the caller
        // did not take responsibility for.
        bool claimAll(std::span<const MicroInstrRef> refs, bool allowRelocated = false);
        bool claimAll(std::initializer_list<MicroInstrRef> refs, bool allowRelocated = false)
        {
            return claimAll(std::span<const MicroInstrRef>(refs.begin(), refs.size()), allowRelocated);
        }
    };

    using PatternFn = bool (*)(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);

    using PatternRegistry = MicroPeephole::PatternRegistry<PatternFn>;

    //===-- Shared helpers --------------------------------------------------===//

    inline bool skipSingleUseIntCopy(Context& ctx, MicroSsaState::ReachingDef& def, MicroInstrRef& copyRef, MicroOpBits bits)
    {
        if (def.valid() && !def.isPhi && def.inst && def.inst->op == MicroInstrOpcode::LoadRegReg)
        {
            const auto* copy = def.inst->ops(*ctx.operands);
            if (!copy || !copy[1].reg.isVirtualInt() || copy[2].opBits != bits ||
                ctx.ssa->transitiveInstructionUseCount(def.valueId, 2) != 1)
                return false;
            copyRef = def.instRef;
            def     = ctx.ssa->reachingDef(copy[1].reg, copyRef);
        }
        return true;
    }

    bool        isSameOpBitsInt(MicroOpBits a, MicroOpBits b);
    bool        isRightIdentity(MicroOp op, MicroOpBits opBits, uint64_t imm);
    bool        isRightAbsorbing(MicroOp op, MicroOpBits opBits, uint64_t imm, uint64_t& outResult);
    bool        tryReassociate(MicroOp firstOp, uint64_t firstImm, MicroOp secondOp, uint64_t secondImm, MicroOpBits opBits, MicroOp& outOp, uint64_t& outImm);
    bool        isMemFoldableOp(MicroOp op);
    bool        isControlOrCall(const MicroInstr& inst);
    bool        writesMemory(const MicroInstr& inst);
    MicroOpBits useReadBits(const MicroInstr& useInst, const MicroInstrOperand* useOps, MicroReg reg);
    bool        valueHasSingleUse(const MicroSsaState& ssa, MicroReg reg, MicroInstrRef defInstRef);

    // The one instruction that reads the value, looking through phis nothing
    // reads: a value defined in a loop body flows into a phi at the header
    // whether or not the next iteration reads it. Invalid when the value has
    // no reader, several, or a phi with readers of its own.
    void runBalancedAffineChains(Context& ctx);

    MicroInstrRef singleDirectInstructionUse(const MicroSsaState& ssa, uint32_t valueId);

    // Whether `reg` holds a frame address where `atRef` reads it: the stack
    // pointer, or a chain of copies and constant-offset address computations
    // from it, followed through reaching definitions.
    bool isFrameDerivedAddress(const Context& ctx, MicroReg reg, MicroInstrRef atRef);

    // Whether `reg` holds the address of a global or a constant where `atRef`
    // reads it: a relocated address materialization, possibly copied.
    bool isRelocatedAddress(const Context& ctx, MicroReg reg, MicroInstrRef atRef);

    // Whether a memory access inside a loop is better left as a separate
    // load or store than folded into an operation's memory operand. A frame
    // slot there belongs to slot promotion and to the vectorizer, which look
    // for the scalar access and would find the value pinned in memory. A
    // global there is read and written instruction-pointer-relative, and a
    // folded form would keep its address in a register across the loop
    // instead.
    bool keepAccessScalar(Context& ctx, MicroInstrRef ref, MicroReg base);

    //===-- Patterns (one per file) -----------------------------------------===//

    bool tryOpBinaryRegImm(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldRedundantMaskBeforeShift(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryOpBinaryRegReg(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldAbsoluteValueSignMask(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFuseInPlaceUpdate(Context& ctx, MicroInstrRef opRef, const MicroInstr& opInst);
    bool tryReadCopyInSelfOperation(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryMemoryFoldTriple(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFoldGlobalUnaryMemoryOp(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryMemoryFoldAmcTriple(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryReuseAmcLoadForClearLowestBit(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFactorReloadedProduct(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldLoadIntoRegOp(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFoldAmcAddressedLoadIntoRegOp(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFoldAmcLoadIntoRegOp(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFoldVecLoadIntoWiden(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFoldVecLoadIntoFullUnary(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryScalarizeVectorLoad(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryBuildVectorFromStores(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFoldAmcLoadIntoSignExtend(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFoldAmcLoadIntoZeroExtend(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFoldZeroExtAmcLoadIntoCompare(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFoldAmcLoadIntoCompare(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFoldRightAmcLoadIntoEqualityCompare(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryBypassByteCopyInIndexedCompare(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst);
    bool tryFoldVectorEqualityMask(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst);
    bool tryFoldWordCompareMask(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst);
    bool trySelectComparedIndexedLoad(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst);
    bool tryReuseComparedIndexedLoad(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst);
    bool tryDelayCopiedAddressIncrement(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldConstIndexAmc(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldLeaConstIntoAmcIndex(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldShiftAddIntoScaledAddress(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldMultiplyAddIntoScaledAddress(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool trySplitWideAddressScale(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryPeelScaledIndexConstant(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldAddressOperandConstant(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldCopyAddIntoAddress(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldComplementedSum(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldComplementPlusOne(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldPureResultCopy(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryBypassShiftCountMask(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryBypassShiftCountExtension(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldIndexedAddressIntoAccess(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryNarrowCompareOfZeroExtension(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryThreeOperandShift(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldLeaConstIntoMemBase(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldRelocatedAddressIntoAccess(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldMemoryAddressing(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryUseOffsetRelatedIndex(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldGlobalMemoryOp(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryNarrowExtend(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool deferNarrowSelect(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    void runSelectNarrowing(Context& ctx);
    bool tryNarrowBooleanDifference(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldCaseRangePair(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryNarrowByteRangeCompare(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldThreeWaySelects(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryDropDeadCompare(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryReuseSubtractionFlags(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryReuseSaturatingAddFlags(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldIndexedSignBit(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryWidenCopyWithNarrowReaders(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryDropRedundantZeroExtend(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldLoadIntoExtend(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryLoadDirectlyIntoFloat(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryCommuteFloatConstantLhs(Context& ctx, MicroInstrRef binRef, const MicroInstr& binInst);
    bool tryBuildScalarFromStores(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFoldLoadIntoRegCompare(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryRecognizeByteSwap(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryPackAdjacentByteLoads(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldComplementOfDecrement(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool isValueZeroExtended32(const Context& ctx, uint32_t valueId);
    bool tryNarrowMaskedArithmetic(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryDropNonNegativeSignExtend(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryDivideBoundedByConstant(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryWidenMaskedNarrowValue(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool resolveIntConstant(uint64_t& outImm, const Context& ctx, MicroReg useReg, MicroInstrRef useRef, MicroOpBits readBits);
    bool tryFoldConstStore(Context& ctx, MicroInstrRef storeRef, const MicroInstr& storeInst);
    bool tryEraseStoreOfLoadedValue(Context& ctx, MicroInstrRef storeRef, const MicroInstr& storeInst);
    bool tryFoldConstCompare(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst);
    bool tryFoldConstAmcCompare(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst);
    bool tryDropRangeProvedCompare(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst);
    bool tryResolveRangeProvedBranch(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryDropRepeatedGuard(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst);
    bool tryResolveDominatedOverflowGuard(Context& ctx, MicroInstrRef opRef, const MicroInstr& opInst);
    bool tryDropFrameWriteGuard(Context& ctx, MicroInstrRef callRef, const MicroInstr& callInst);
    bool tryFoldConstBinaryRhs(Context& ctx, MicroInstrRef binRef, const MicroInstr& binInst);
    bool tryFoldConstCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryFoldBooleanSelect(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryReuseCompareOperandForSelect(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryDropFloatOrderedGuard(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldConstantLhs(Context& ctx, MicroInstrRef binRef, const MicroInstr& binInst);

    //===-- Whole-IR scans --------------------------------------------------===//

    void runStoreToLoadForwarding(Context& ctx);
    void runDeadStoreElimination(Context& ctx);
    void runDropUnobservedBorrows(Context& ctx, const FlatKeyMap<uint32_t>& borrowArgs);
}

SWC_END_NAMESPACE();
