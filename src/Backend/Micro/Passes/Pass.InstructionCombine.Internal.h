#pragma once
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/Passes/Pass.Peephole.Core.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class MicroStorage;
class MicroOperandStorage;
class MicroBuilder;

namespace InstructionCombine
{
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
    };

    // Context threaded through every pattern. Pointers (not references) so the
    // struct stays assignable and matches project conventions.
    struct Context : MicroPeephole::RewriteQueue<Action>
    {
        const MicroSsaState* ssa     = nullptr;
        MicroBuilder*        builder = nullptr;
        // Instructions that carry a relocation. Rewriting or erasing one
        // drops the relocation binding - the patch then lands wherever
        // codeOffset zero points - so claimAll refuses them unless a rule
        // that explicitly manages the relocation opts in.
        std::unordered_set<uint32_t> relocated;

        bool isRelocated(MicroInstrRef ref) const { return relocated.contains(ref.get()); }

        // The stack pointer of the calling convention, which every frame
        // address derives from.
        MicroReg stackPointer = MicroReg::invalid();

        // Whether the instruction sits inside a natural loop. The loop bodies
        // are collected on the first question, since only the memory folds
        // ask; a CFG the loop analysis cannot read answers yes for everything.
        bool isInsideLoop(MicroInstrRef ref);

        bool                         loopSlotsReady = false;
        bool                         loopSlotsAll   = false;
        std::unordered_set<uint32_t> loopSlots;

        // Claim every ref atomically: returns false without side-effects if
        // any was already claimed, or if one carries a relocation the caller
        // did not take responsibility for.
        bool claimAll(std::initializer_list<MicroInstrRef> refs, bool allowRelocated = false);
    };

    using PatternFn = bool (*)(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);

    using PatternRegistry = MicroPeephole::PatternRegistry<PatternFn>;

    //===-- Shared helpers --------------------------------------------------===//

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
    bool tryFuseInPlaceUpdate(Context& ctx, MicroInstrRef opRef, const MicroInstr& opInst);
    bool tryMemoryFoldTriple(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFoldLoadIntoRegOp(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFoldAmcLoadIntoSignExtend(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFoldAmcLoadIntoZeroExtend(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFoldZeroExtAmcLoadIntoCompare(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFoldAmcLoadIntoCompare(Context& ctx, MicroInstrRef loadRef, const MicroInstr& loadInst);
    bool tryFoldConstIndexAmc(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldLeaConstIntoAmcIndex(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldShiftAddIntoScaledAddress(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldLeaConstIntoMemBase(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldRelocatedAddressIntoAccess(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldMemoryAddressing(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryNarrowExtend(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryDropRedundantZeroExtend(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryNarrowMaskedArithmetic(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryFoldConstStore(Context& ctx, MicroInstrRef storeRef, const MicroInstr& storeInst);
    bool tryFoldConstCompare(Context& ctx, MicroInstrRef cmpRef, const MicroInstr& cmpInst);
    bool tryFoldConstBinaryRhs(Context& ctx, MicroInstrRef binRef, const MicroInstr& binInst);
    bool tryFoldConstCopy(Context& ctx, MicroInstrRef copyRef, const MicroInstr& copyInst);
    bool tryDropFloatOrderedGuard(Context& ctx, MicroInstrRef ref, const MicroInstr& inst);
    bool tryCommuteConstantLhs(Context& ctx, MicroInstrRef binRef, const MicroInstr& binInst);

    //===-- Whole-IR scans --------------------------------------------------===//

    void runStoreToLoadForwarding(Context& ctx);
}

SWC_END_NAMESPACE();
