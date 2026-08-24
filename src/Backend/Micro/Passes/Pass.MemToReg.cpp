#include "pch.h"
#include "Backend/Micro/Passes/Pass.MemToReg.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/MicroStorage.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Support/Core/SmallVector.h"
#include "Support/Report/Assert.h"

// mem2reg: promote non-escaping fixed-width scalar stack slots to virtual
// registers. See the header for rationale.
//
// Conservative by construction:
//  - it only fires for slots reached exclusively as the base of a constant-
//    offset scalar load/store, and abandons promotion for the whole function on
//    any use of the frame base (or a frame-derived address) it cannot explain
//    (taking a slot's address exposes the whole object, so partial reasoning is
//    unsound).
//
// Loop-carried slots (values live across a back-edge, e.g. reduction
// accumulators) are promoted too. The register allocator keeps the promoted
// value resident in a register when it can pin it, and otherwise gives it a
// single stable spill-slot home that it writes back at every control-flow
// boundary — so the value round-trips through one consistent location across the
// back-edge instead of corrupting silently. See
// MicroRegisterAllocationPass::preallocateLoopCarriedSlots and the loop-carried
// store in flushAllMappedVirtuals.

SWC_BEGIN_NAMESPACE();

namespace
{
    struct SlotAccess
    {
        MicroInstrRef ref     = MicroInstrRef::invalid();
        uint64_t      offset  = 0;
        MicroOpBits   bits    = MicroOpBits::Zero;
        bool          isWrite = false;
    };

    struct SlotInfo
    {
        bool                    hasWrite = false;
        SmallVector<SlotAccess> accesses;
    };

    // The memory-operand ALU and compare forms read (and for the mem-destination
    // ones also write) exactly one slot, just like a load or a store. Leaving
    // them out did not make the analysis safe, it made it self-defeating:
    // instruction-combine folds `load t, [slot]` + `op d, t` into
    // `op d, [slot]`, so a slot an earlier sweep could have promoted became an
    // unexplained escape on the next one and the whole variable was condemned
    // to memory. That is what keeps sha256's eight compression-state words in
    // the frame.
    bool isMemOperandAluOp(MicroInstrOpcode op)
    {
        return op == MicroInstrOpcode::OpBinaryRegMem ||
               op == MicroInstrOpcode::OpBinaryMemReg ||
               op == MicroInstrOpcode::OpBinaryMemImm ||
               op == MicroInstrOpcode::OpUnaryMem ||
               op == MicroInstrOpcode::CmpMemReg ||
               op == MicroInstrOpcode::CmpMemImm;
    }

    // The 128-bit vector load and store are the same shape as the scalar pair, and a slot
    // reached only through them is a vector local. Leaving them out was not neutral: an
    // unrecognized access to a frame-derived address abandons promotion for the whole
    // function, so one vector temporary kept every scalar of a SIMD routine in memory -
    // its strides, its trip counts, and every intermediate vector, each stored and reloaded
    // around the operation that produced it.
    bool isHandledScalarMemOp(MicroInstrOpcode op)
    {
        return op == MicroInstrOpcode::LoadRegMem ||
               op == MicroInstrOpcode::LoadMemReg ||
               op == MicroInstrOpcode::LoadMemImm ||
               op == MicroInstrOpcode::LoadSignedExtRegMem ||
               op == MicroInstrOpcode::LoadZeroExtRegMem ||
               op == MicroInstrOpcode::LoadVecRegMem ||
               op == MicroInstrOpcode::StoreVecMemReg ||
               isMemOperandAluOp(op);
    }

    // The register whose class the slot must match, or an invalid register when
    // the instruction carries an immediate instead (the slot's class is then
    // resolved from its other accesses, exactly as for LoadMemImm).
    MicroReg slotValueRegister(MicroInstrOpcode op, const MicroInstrOperand* ops)
    {
        switch (op)
        {
            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
            case MicroInstrOpcode::OpBinaryRegMem:
            case MicroInstrOpcode::LoadVecRegMem:
                return ops[0].reg;
            case MicroInstrOpcode::StoreVecMemReg:
            case MicroInstrOpcode::LoadMemReg:
            case MicroInstrOpcode::OpBinaryMemReg:
            case MicroInstrOpcode::CmpMemReg:
                return ops[1].reg;
            default:
                return MicroReg::invalid();
        }
    }

    bool carriesImmediateSlotWrite(MicroInstrOpcode op)
    {
        return op == MicroInstrOpcode::LoadMemImm ||
               op == MicroInstrOpcode::OpBinaryMemImm ||
               op == MicroInstrOpcode::OpUnaryMem ||
               op == MicroInstrOpcode::CmpMemImm;
    }

    bool isPromotableBits(MicroOpBits bits)
    {
        // 128 bits is the vector width, and a float register copy of it is full width too;
        // the class check downstream is what keeps it off the integer file.
        if (bits == MicroOpBits::B128)
            return true;
        // b32/b64 only. For integers, 64-bit copies are full width and 32-bit
        // writes zero-extend to the full register on x86-64, so a register copy
        // matches the zero-extending memory load (b8/b16 would leave stale upper
        // bits). For floats, b32/b64 are the scalar single/double widths and a
        // float register copy is full-width.
        return bits == MicroOpBits::B32 || bits == MicroOpBits::B64;
    }

    // The local frame base is the stack-pointer-derived register the front-end
    // addresses locals through. It is either a plain copy `mov reg, sp` or a
    // constant lea `lea reg, [sp + C]` (the compiler often biases it past the
    // saved-register / spill area). We pick the candidate that is (a) never
    // redefined or arithmetic-modified after its definition — a register that
    // gets `reg += imm` is a transient address-calculation scratch, not the
    // stable base — and (b) actually used as the base of constant-offset scalar
    // loads/stores, preferring the most-used one. The escape analysis then
    // validates the choice and bails the whole function if it is wrong.
    MicroReg detectFrameBase(MicroStorage& storage, MicroOperandStorage& operands, MicroReg stackPointer, MicroInstrRef& outDefRef)
    {
        struct Cand
        {
            MicroInstrRef defRef   = MicroInstrRef::invalid();
            uint32_t      baseUses = 0;
            bool          stable   = true;
        };
        std::unordered_map<MicroReg, Cand> cands;

        // Pass A: collect sp-derived definitions.
        for (auto it = storage.view().begin(), end = storage.view().end(); it != end; ++it)
        {
            const MicroInstr&        inst = *it;
            const MicroInstrOperand* ops  = inst.ops(operands);
            if (!ops)
                continue;
            const bool isMov = inst.op == MicroInstrOpcode::LoadRegReg && ops[1].reg == stackPointer;
            const bool isLea = inst.op == MicroInstrOpcode::LoadAddrRegMem && ops[1].reg == stackPointer;
            if ((isMov || isLea) && ops[0].reg.isVirtualInt())
            {
                Cand& c = cands[ops[0].reg];
                if (c.defRef.isValid())
                    c.stable = false; // defined more than once: not a stable base.
                else
                    c.defRef = it.current;
            }
        }
        if (cands.empty())
            return MicroReg::invalid();

        // Pass B: invalidate candidates redefined/modified elsewhere, and count
        // their uses as a constant-offset memory base.
        for (auto it = storage.view().begin(), end = storage.view().end(); it != end; ++it)
        {
            const MicroInstr&        inst = *it;
            const MicroInstrOperand* ops  = inst.ops(operands);
            if (!ops)
                continue;

            SmallVector<MicroInstrRegOperandRef> regRefs;
            inst.collectRegOperands(operands, regRefs, nullptr);
            for (const auto& rref : regRefs)
            {
                if (!rref.reg || !rref.def)
                    continue;
                const auto found = cands.find(*rref.reg);
                if (found != cands.end() && it.current != found->second.defRef)
                    found->second.stable = false;
            }

            // Count uses where the candidate is the addressing base: a direct
            // scalar load/store base, or the base of a `lea` that derives a
            // sub-address (`lea ar, [base + off]`). The latter matters because
            // the front-end frequently materializes each local's address with a
            // lea first, so the frame base may never appear as a direct base.
            MicroReg baseReg = MicroReg::invalid();
            if (inst.op == MicroInstrOpcode::LoadRegMem || inst.op == MicroInstrOpcode::LoadAddrRegMem)
                baseReg = ops[1].reg;
            else if (inst.op == MicroInstrOpcode::LoadMemReg || inst.op == MicroInstrOpcode::LoadMemImm)
                baseReg = ops[0].reg;
            if (baseReg.isValid())
            {
                const auto found = cands.find(baseReg);
                if (found != cands.end())
                    ++found->second.baseUses;
            }
        }

        MicroReg best;
        uint32_t bestUses = 0;
        for (const auto& [reg, c] : cands)
        {
            if (c.stable && c.defRef.isValid() && c.baseUses > bestUses)
            {
                best      = reg;
                bestUses  = c.baseUses;
                outDefRef = c.defRef;
            }
        }
        return best;
    }

    struct Promotion
    {
        uint64_t    offset;
        MicroOpBits bits;
        bool        isFloat;
    };

}

Result MicroMemToRegPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions != nullptr);
    SWC_ASSERT(context.operands != nullptr);
    if (!context.builder)
        return Result::Continue;

    MicroStorage&        storage  = *context.instructions;
    MicroOperandStorage& operands = *context.operands;

    const CallConv& callConv     = CallConv::get(context.callConvKind);
    const MicroReg  stackPointer = callConv.stackPointer;
    if (!stackPointer.isValid())
        return Result::Continue;

    MicroInstrRef  frameBaseDefRef = MicroInstrRef::invalid();
    const MicroReg frameBase       = detectFrameBase(storage, operands, stackPointer, frameBaseDefRef);
    if (!frameBase.isValid() || !frameBaseDefRef.isValid())
        return Result::Continue;

    // ---- Pass 1: collect address registers `lea ar, [fb + off]`. ----
    struct AddrRegInfo
    {
        uint64_t      offset = 0;
        MicroInstrRef defRef = MicroInstrRef::invalid();
    };
    std::unordered_map<MicroReg, AddrRegInfo> addrRegOffset;
    std::unordered_set<MicroReg>              badAddrReg;

    for (auto it = storage.view().begin(), end = storage.view().end(); it != end; ++it)
    {
        const MicroInstr&        inst = *it;
        const MicroInstrOperand* ops  = inst.ops(operands);
        if (!ops)
            continue;

        if (it.current == frameBaseDefRef)
            continue;

        // `lea ar, [fb + off]`, and its degenerate spelling `mov ar, fb`: the
        // front end passes the address of a frame object at offset zero (an
        // error payload, a first local) as a plain copy of the base, and
        // treating that copy as an untrackable escape used to abandon the
        // whole function.
        const bool isAddrLea  = inst.op == MicroInstrOpcode::LoadAddrRegMem && ops[1].reg == frameBase;
        const bool isBaseCopy = inst.op == MicroInstrOpcode::LoadRegReg && ops[1].reg == frameBase && ops[2].opBits == MicroOpBits::B64;
        if (isAddrLea || isBaseCopy)
        {
            const MicroReg ar = ops[0].reg;
            if (!ar.isVirtualInt() || ar == frameBase)
                badAddrReg.insert(ar);
            else if (addrRegOffset.contains(ar))
                badAddrReg.insert(ar);
            else
                addrRegOffset[ar] = {isAddrLea ? ops[3].valueU64 : 0, it.current};
        }
    }

    // A tracked address register redefined by anything other than its recorded
    // definition — plain arithmetic (`ar += reg`), an unrelated copy, a second
    // lea — no longer points at its recorded offset. The map is flow-insensitive
    // and a loop can run the redefinition before an access that appears earlier
    // in the linear order, so the register is disqualified everywhere: accesses
    // through it stop resolving, and its remaining appearances read as
    // unexplainable escapes.
    if (!addrRegOffset.empty())
    {
        for (auto it = storage.view().begin(), end = storage.view().end(); it != end; ++it)
        {
            SmallVector<MicroInstrRegOperandRef> regRefs;
            it->collectRegOperands(operands, regRefs, context.encoder);
            for (const auto& rref : regRefs)
            {
                if (!rref.reg || !rref.def)
                    continue;
                const auto found = addrRegOffset.find(*rref.reg);
                if (found != addrRegOffset.end() && it.current != found->second.defRef)
                    badAddrReg.insert(*rref.reg);
            }
        }
    }

    auto isTracked = [&](MicroReg reg) -> bool {
        return reg == frameBase || addrRegOffset.contains(reg);
    };

    // ---- Local-variable extents: escapes poison one variable, not the function. ----
    //
    // Taking a slot's address exposes the whole OBJECT behind it, and the micro
    // level cannot see object boundaries — which used to force abandoning the
    // entire function on the first escape (one `&local` passed to a call kept
    // every hot scalar of the function in memory). The front end knows every
    // local's frame extent, so when the lowered function is available an escape
    // at a known offset only poisons the variable that contains it, and every
    // other slot stays promotable. The fallback (no function symbol, a frame
    // base that is not the local-stack base, or an escape outside any known
    // variable) is the old whole-function bail.
    struct FrameVarRange
    {
        uint64_t lo       = 0;
        uint64_t hi       = 0;
        bool     poisoned = false;
    };
    std::vector<FrameVarRange> varRanges;

    bool rangesUsable = context.sanitizerFunction != nullptr &&
                        (!context.debugStackBaseVirtualReg.isValid() || context.debugStackBaseVirtualReg == frameBase);
    if (rangesUsable)
    {
        for (const SymbolVariable* localVar : context.sanitizerFunction->localVariables())
        {
            if (!localVar || !localVar->hasExtraFlag(SymbolVariableFlagsE::CodeGenLocalStack))
                continue;
            const uint64_t size = localVar->codeGenLocalSize();
            if (!size)
                continue;
            varRanges.push_back({.lo = localVar->offset(), .hi = localVar->offset() + size});
        }
    }

    // An escape at an offset outside every known variable exposes an object the
    // analysis cannot bound - a compiler temporary such as an error payload,
    // which the front end does not list as a local. Frame objects are disjoint,
    // so that unknown object cannot overlap a known variable: the sound answer
    // is to treat all frame space OUTSIDE the known variables as reachable
    // through the escaped pointer, and keep promoting inside them.
    bool unknownSpaceEscaped = false;

    // Poison the variable containing 'offset'; false only when no extent
    // information is available at all and the caller must fall back to the
    // whole-function bail.
    auto poisonEscapedOffset = [&](const uint64_t offset) -> bool {
        if (!rangesUsable)
            return false;
        bool found = false;
        for (FrameVarRange& range : varRanges)
        {
            if (offset >= range.lo && offset < range.hi)
            {
                range.poisoned = true;
                found          = true;
            }
        }
        if (!found)
            unknownSpaceEscaped = true;
        return true;
    };

    // The escaped offset of a tracked register, when it has a single known one.
    auto trackedEscapeOffset = [&](const MicroReg reg, uint64_t& outOffset) -> bool {
        if (reg == frameBase || badAddrReg.contains(reg))
            return false;
        const auto found = addrRegOffset.find(reg);
        if (found == addrRegOffset.end())
            return false;
        outOffset = found->second.offset;
        return true;
    };

    // Same, for the appearances that use the pointer AS the address of the
    // object it points to: stored as a plain value, or the base of an indexed
    // (Amc) access. There the frame base itself is meaningful: it is the
    // address of the object at offset zero - the store-operand spelling of the
    // degenerate `mov ar, fb` the collection pass models - and the front end
    // produces it whenever the address of a function's FIRST local escapes or
    // is indexed (an inlined callee's pointer parameter home, a `state[i]`
    // over a first local). Everywhere else - plain arithmetic on the base - a
    // frame-base appearance keeps the whole-function bail.
    auto escapedObjectOffset = [&](const MicroReg reg, uint64_t& outOffset) -> bool {
        if (reg == frameBase && !badAddrReg.contains(reg))
        {
            outOffset = 0;
            return true;
        }
        return trackedEscapeOffset(reg, outOffset);
    };

    // ---- Pass 2: classify accesses; an unexplained escape poisons the
    //      containing variable, or bails the whole function when it cannot be
    //      pinned to one. ----
    std::unordered_map<uint64_t, SlotInfo> slots;
    bool                                   bail = false;

    for (auto it = storage.view().begin(), end = storage.view().end(); it != end && !bail; ++it)
    {
        const MicroInstrRef      ref  = it.current;
        const MicroInstr&        inst = *it;
        const MicroInstrOperand* ops  = inst.ops(operands);
        if (!ops)
            continue;

        if (ref == frameBaseDefRef)
            continue;
        if (inst.op == MicroInstrOpcode::LoadAddrRegMem && ops[1].reg == frameBase)
            continue;
        // The `mov ar, fb` address definition recognized by pass 1.
        if (inst.op == MicroInstrOpcode::LoadRegReg && ops[1].reg == frameBase && ops[2].opBits == MicroOpBits::B64 && addrRegOffset.contains(ops[0].reg))
            continue;

        MicroReg baseReg   = MicroReg::invalid();
        uint64_t baseSlot  = 0;
        bool     baseValid = false;

        auto resolveBase = [&](MicroReg reg, uint64_t extraOffset) {
            if (reg == frameBase)
            {
                baseReg   = reg;
                baseSlot  = extraOffset;
                baseValid = true;
            }
            else
            {
                const auto found = addrRegOffset.find(reg);
                if (found != addrRegOffset.end() && !badAddrReg.contains(reg))
                {
                    baseReg   = reg;
                    baseSlot  = found->second.offset + extraOffset;
                    baseValid = true;
                }
            }
        };

        MicroReg   valueReg = MicroReg::invalid();
        SlotAccess pending;
        bool       hasPending = false;
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadRegMem:
            case MicroInstrOpcode::LoadVecRegMem:
                resolveBase(ops[1].reg, ops[3].valueU64);
                valueReg = ops[0].reg;
                if (baseValid)
                {
                    pending    = {ref, baseSlot, ops[2].opBits, false};
                    hasPending = true;
                }
                break;
            case MicroInstrOpcode::LoadMemReg:
            case MicroInstrOpcode::StoreVecMemReg:
                resolveBase(ops[0].reg, ops[3].valueU64);
                valueReg = ops[1].reg;
                if (baseValid)
                {
                    pending    = {ref, baseSlot, ops[2].opBits, true};
                    hasPending = true;
                }
                break;
            case MicroInstrOpcode::LoadMemImm:
                resolveBase(ops[0].reg, ops[2].valueU64);
                if (baseValid)
                {
                    pending    = {ref, baseSlot, ops[1].opBits, true};
                    hasPending = true;
                }
                break;
            case MicroInstrOpcode::LoadSignedExtRegMem:
            case MicroInstrOpcode::LoadZeroExtRegMem:
                // A widening load of a slot (e.g. a 32-bit index sign-extended to
                // 64 bits for array addressing). The slot's width is the SOURCE
                // width (ops[3]); the destination width (ops[2]) belongs to the
                // extended result, not the slot. The offset lives in ops[4].
                resolveBase(ops[1].reg, ops[4].valueU64);
                valueReg = ops[0].reg;
                if (baseValid)
                {
                    pending    = {ref, baseSlot, ops[3].opBits, false};
                    hasPending = true;
                }
                break;

            // `reg op= [slot]` — one read of the slot at the operation width.
            case MicroInstrOpcode::OpBinaryRegMem:
                resolveBase(ops[1].reg, ops[4].valueU64);
                valueReg = ops[0].reg;
                if (baseValid)
                {
                    pending    = {ref, baseSlot, ops[2].opBits, false};
                    hasPending = true;
                }
                break;

            // `[slot] op= reg` and `[slot] op= imm` — read-modify-write.
            case MicroInstrOpcode::OpBinaryMemReg:
                resolveBase(ops[0].reg, ops[4].valueU64);
                valueReg = ops[1].reg;
                if (baseValid)
                {
                    pending    = {ref, baseSlot, ops[2].opBits, true};
                    hasPending = true;
                }
                break;
            case MicroInstrOpcode::OpBinaryMemImm:
                resolveBase(ops[0].reg, ops[3].valueU64);
                if (baseValid)
                {
                    pending    = {ref, baseSlot, ops[1].opBits, true};
                    hasPending = true;
                }
                break;
            case MicroInstrOpcode::OpUnaryMem:
                resolveBase(ops[0].reg, ops[3].valueU64);
                if (baseValid)
                {
                    pending    = {ref, baseSlot, ops[1].opBits, true};
                    hasPending = true;
                }
                break;

            // `cmp [slot], reg` and `cmp [slot], imm` — one read.
            case MicroInstrOpcode::CmpMemReg:
                resolveBase(ops[0].reg, ops[3].valueU64);
                valueReg = ops[1].reg;
                if (baseValid)
                {
                    pending    = {ref, baseSlot, ops[2].opBits, false};
                    hasPending = true;
                }
                break;
            case MicroInstrOpcode::CmpMemImm:
                resolveBase(ops[0].reg, ops[2].valueU64);
                if (baseValid)
                {
                    pending    = {ref, baseSlot, ops[1].opBits, false};
                    hasPending = true;
                }
                break;

            default:
                break;
        }

        // An indexed (Amc) access reaches an unknown offset INSIDE the object
        // its base points to: the base is not a whole-function escape, it
        // exposes exactly that object - poison it and keep going, like any
        // other address escape. Index and stored-value registers still go
        // through the generic escape scan below.
        MicroReg amcBase = MicroReg::invalid();
        switch (inst.op)
        {
            case MicroInstrOpcode::LoadAmcRegMem:
            case MicroInstrOpcode::LoadSignedExtAmcRegMem:
            case MicroInstrOpcode::LoadZeroExtAmcRegMem:
            case MicroInstrOpcode::LoadAddrAmcRegMem:
                amcBase = ops[1].reg;
                break;
            case MicroInstrOpcode::LoadAmcMemReg:
            case MicroInstrOpcode::LoadAmcMemImm:
            case MicroInstrOpcode::CmpAmcImm:
                amcBase = ops[0].reg;
                break;
            default:
                break;
        }
        if (amcBase.isValid() && (amcBase == frameBase || isTracked(amcBase)))
        {
            uint64_t escapedOffset = 0;
            if (!escapedObjectOffset(amcBase, escapedOffset) || !poisonEscapedOffset(escapedOffset))
            {
                bail = true;
                break;
            }
        }

        // Moving a tracked pointer as a value means the address escapes. Only
        // a STORE moves it as a plain value; a load overwrites the register,
        // which the redefinition sweep above already disqualified.
        const bool storesTrackedValue = inst.op == MicroInstrOpcode::LoadMemReg &&
                                        baseValid && valueReg.isValid() && isTracked(valueReg);
        if (baseValid && valueReg.isValid() && isTracked(valueReg))
        {
            uint64_t   escapedOffset = 0;
            const bool resolved      = storesTrackedValue ? escapedObjectOffset(valueReg, escapedOffset)
                                                          : trackedEscapeOffset(valueReg, escapedOffset);
            if (!resolved || !poisonEscapedOffset(escapedOffset))
            {
                bail = true;
                break;
            }
            // The destination slot access stays valid: it holds the pointer as
            // a plain value, and only the pointed-to variable is poisoned.
        }

        // Any tracked register appearing anywhere other than as the base of a
        // recognized scalar access is an escape the scalar analysis cannot
        // explain: poison the variable it points into.
        SmallVector<MicroInstrRegOperandRef> regRefs;
        inst.collectRegOperands(operands, regRefs, context.encoder);
        for (const auto& rref : regRefs)
        {
            if (!rref.reg || !isTracked(*rref.reg))
                continue;
            const bool isExplainedBase    = baseValid && *rref.reg == baseReg && isHandledScalarMemOp(inst.op);
            const bool isExplainedValue   = storesTrackedValue && *rref.reg == valueReg;
            const bool isExplainedAmcBase = amcBase.isValid() && *rref.reg == amcBase;
            if (isExplainedBase || isExplainedValue || isExplainedAmcBase)
                continue;
            uint64_t escapedOffset = 0;
            if (!trackedEscapeOffset(*rref.reg, escapedOffset) || !poisonEscapedOffset(escapedOffset))
            {
                bail = true;
                break;
            }
        }
        if (bail)
            break;

        if (hasPending)
        {
            SlotInfo& slot = slots[pending.offset];
            slot.accesses.push_back(pending);
            if (pending.isWrite)
                slot.hasWrite = true;
        }
    }

    if (bail)
        return Result::Continue;

    // ---- Decide candidate offsets: consistent b32/b64 width, a single
    //      register class (all-int or all-float), a write, and no overlap with
    //      any other accessed slot. ----
    SmallVector<Promotion> promotions;

    auto overlapsPoisonedVariable = [&](const uint64_t lo, const uint64_t hi) -> bool {
        for (const FrameVarRange& range : varRanges)
        {
            if (range.poisoned && lo < range.hi && range.lo < hi)
                return true;
        }
        return false;
    };

    auto insideKnownVariable = [&](const uint64_t lo, const uint64_t hi) -> bool {
        for (const FrameVarRange& range : varRanges)
        {
            if (lo >= range.lo && hi <= range.hi)
                return true;
        }
        return false;
    };

    for (auto& [offset, slot] : slots)
    {
        if (slot.accesses.empty() || !slot.hasWrite)
            continue;

        // A slot inside an escaped variable can be written behind the scalar
        // analysis's back through the escaped pointer. When an escape landed
        // outside every known variable, the whole unknown part of the frame is
        // reachable through it and only slots inside known variables remain
        // promotable.
        bool touchesPoisoned = false;
        for (const SlotAccess& acc : slot.accesses)
        {
            const uint64_t lo = acc.offset;
            const uint64_t hi = acc.offset + getNumBytes(acc.bits);
            if (overlapsPoisonedVariable(lo, hi) || (unknownSpaceEscaped && !insideKnownVariable(lo, hi)))
            {
                touchesPoisoned = true;
                break;
            }
        }
        if (touchesPoisoned)
            continue;

        const MicroOpBits bits       = slot.accesses[0].bits;
        bool              consistent = isPromotableBits(bits);
        for (const SlotAccess& acc : slot.accesses)
        {
            if (acc.bits != bits)
            {
                consistent = false;
                break;
            }
        }
        if (!consistent)
            continue;

        // Determine the slot's register class from its reg-valued accesses; all
        // must agree. Float slots may not carry a LoadMemImm (an integer
        // immediate must not be written into a float register).
        bool ok         = true;
        bool classKnown = false;
        bool isFloat    = false;
        for (const SlotAccess& acc : slot.accesses)
        {
            const MicroInstr*        inst = storage.ptr(acc.ref);
            const MicroInstrOperand* iops = inst ? inst->ops(operands) : nullptr;
            if (!iops)
            {
                ok = false;
                break;
            }
            const MicroReg valueReg = slotValueRegister(inst->op, iops);
            if (!valueReg.isValid())
                continue; // an immediate form: class resolved from the reg accesses
            const bool regFloat = valueReg.isAnyFloat();
            if (!regFloat && !valueReg.isAnyInt())
            {
                ok = false;
                break;
            }
            if (!classKnown)
            {
                classKnown = true;
                isFloat    = regFloat;
            }
            else if (isFloat != regFloat)
            {
                ok = false; // mixed int/float view of the same slot
                break;
            }
        }
        if (!ok || !classKnown)
            continue;

        // The integer file has no 128-bit register to promote into.
        if (bits == MicroOpBits::B128 && !isFloat)
            continue;

        if (isFloat)
        {
            // A float slot reached by an integer immediate — a store, an
            // in-place operation or a compare — can't be turned into a float
            // register form safely, since the immediate has no float encoding.
            bool hasImm = false;
            for (const SlotAccess& acc : slot.accesses)
            {
                const MicroInstr* inst = storage.ptr(acc.ref);
                if (inst && carriesImmediateSlotWrite(inst->op))
                {
                    hasImm = true;
                    break;
                }
            }
            if (hasImm)
                continue;
        }

        promotions.push_back({offset, bits, isFloat});
    }

    if (promotions.empty())
        return Result::Continue;

    SmallVector<Promotion> filtered;
    for (const Promotion& p : promotions)
    {
        const uint64_t pStart  = p.offset;
        const uint64_t pEnd    = p.offset + getNumBytes(p.bits);
        bool           overlap = false;
        for (const auto& [otherOffset, otherSlot] : slots)
        {
            if (otherOffset == p.offset)
                continue;
            for (const SlotAccess& acc : otherSlot.accesses)
            {
                const uint64_t aStart = acc.offset;
                const uint64_t aEnd   = acc.offset + getNumBytes(acc.bits);
                if (!(aEnd <= pStart || pEnd <= aStart))
                {
                    overlap = true;
                    break;
                }
            }
            if (overlap)
                break;
        }
        if (!overlap)
            filtered.push_back(p);
    }
    promotions = std::move(filtered);
    if (promotions.empty())
        return Result::Continue;

    // Loop-carried slots (values live across a back-edge) are promoted too: the
    // register allocator gives every non-pinned loop-carried virtual register a
    // stable spill-slot home and writes it back at each control-flow boundary, so
    // a promoted accumulator round-trips through one consistent location across
    // the back-edge instead of corrupting silently. See
    // MicroRegisterAllocationPass::preallocateLoopCarriedSlots and the
    // loop-carried store in flushAllMappedVirtuals.
    if (promotions.empty())
        return Result::Continue;

    // ---- Allocate a fresh virtual register per promoted offset (int or float). ----
    uint32_t nextVirtualIntRegIndex   = std::max<uint32_t>(1, context.builder->nextVirtualIntRegIndexHint());
    uint32_t nextVirtualFloatRegIndex = 1;
    for (const MicroInstr& inst : storage.view())
    {
        SmallVector<MicroInstrRegOperandRef> refs;
        inst.collectRegOperands(operands, refs, context.encoder);
        for (const auto& ref : refs)
        {
            if (!ref.reg || ref.reg->index() >= MicroReg::K_MAX_INDEX)
                continue;
            if (ref.reg->isVirtualInt())
                nextVirtualIntRegIndex = std::max(nextVirtualIntRegIndex, ref.reg->index() + 1);
            else if (ref.reg->isVirtualFloat())
                nextVirtualFloatRegIndex = std::max(nextVirtualFloatRegIndex, ref.reg->index() + 1);
        }
    }

    std::unordered_map<uint64_t, MicroReg> slotReg;
    for (const Promotion& p : promotions)
        slotReg[p.offset] = p.isFloat ? MicroReg::virtualFloatReg(nextVirtualFloatRegIndex++)
                                      : MicroReg::virtualIntReg(nextVirtualIntRegIndex++);

    // ---- Rewrite all accesses of the promoted slots to register ops. ----
    for (const Promotion& p : promotions)
    {
        const MicroReg    vreg = slotReg[p.offset];
        const MicroOpBits bits = p.bits;

        for (const SlotAccess& acc : slots[p.offset].accesses)
        {
            MicroInstr* inst = storage.ptr(acc.ref);
            if (!inst)
                continue;
            MicroInstrOperand* ops = inst->ops(operands);
            if (!ops)
                continue;

            if (inst->op == MicroInstrOpcode::LoadRegMem || inst->op == MicroInstrOpcode::LoadVecRegMem)
            {
                const MicroReg dst = ops[0].reg;
                ops[0].reg         = dst;
                ops[1].reg         = vreg;
                ops[2].opBits      = bits;
                inst->op           = MicroInstrOpcode::LoadRegReg;
                inst->numOperands  = 3;
            }
            else if (inst->op == MicroInstrOpcode::LoadMemReg || inst->op == MicroInstrOpcode::StoreVecMemReg)
            {
                const MicroReg src = ops[1].reg;
                ops[0].reg         = vreg;
                ops[1].reg         = src;
                ops[2].opBits      = bits;
                inst->op           = MicroInstrOpcode::LoadRegReg;
                inst->numOperands  = 3;
            }
            else if (inst->op == MicroInstrOpcode::LoadMemImm)
            {
                const MicroInstrOperand imm = ops[3];
                ops[0].reg                  = vreg;
                ops[1].opBits               = bits;
                ops[2]                      = imm;
                inst->op                    = MicroInstrOpcode::LoadRegImm;
                inst->numOperands           = 3;
            }
            else if (inst->op == MicroInstrOpcode::LoadSignedExtRegMem ||
                     inst->op == MicroInstrOpcode::LoadZeroExtRegMem)
            {
                // Widening load of the slot becomes a widening register move from
                // the promoted (source-width) register. Destination width
                // (ops[2]) and source width (ops[3]) are preserved; the memory
                // base in ops[1] is replaced by the slot register and the offset
                // operand (ops[4]) is dropped.
                ops[1].reg        = vreg;
                inst->op          = (inst->op == MicroInstrOpcode::LoadSignedExtRegMem)
                                        ? MicroInstrOpcode::LoadSignedExtRegReg
                                        : MicroInstrOpcode::LoadZeroExtRegReg;
                inst->numOperands = 4;
            }
            // The memory-operand ALU and compare forms lose their memory
            // operand and become the register form of the same operation. Only
            // the base and, where the operand order shifts, the immediate move;
            // the operation and its width are already the slot's.
            else if (inst->op == MicroInstrOpcode::OpBinaryRegMem)
            {
                ops[1].reg        = vreg;
                inst->op          = MicroInstrOpcode::OpBinaryRegReg;
                inst->numOperands = 4;
            }
            else if (inst->op == MicroInstrOpcode::OpBinaryMemReg)
            {
                ops[0].reg        = vreg;
                inst->op          = MicroInstrOpcode::OpBinaryRegReg;
                inst->numOperands = 4;
            }
            else if (inst->op == MicroInstrOpcode::OpBinaryMemImm)
            {
                const MicroInstrOperand imm = ops[4];
                ops[0].reg                  = vreg;
                ops[3]                      = imm;
                inst->op                    = MicroInstrOpcode::OpBinaryRegImm;
                inst->numOperands           = 4;
            }
            else if (inst->op == MicroInstrOpcode::OpUnaryMem)
            {
                ops[0].reg        = vreg;
                inst->op          = MicroInstrOpcode::OpUnaryReg;
                inst->numOperands = 3;
            }
            else if (inst->op == MicroInstrOpcode::CmpMemReg)
            {
                ops[0].reg        = vreg;
                inst->op          = MicroInstrOpcode::CmpRegReg;
                inst->numOperands = 3;
            }
            else if (inst->op == MicroInstrOpcode::CmpMemImm)
            {
                const MicroInstrOperand imm = ops[3];
                ops[0].reg                  = vreg;
                ops[2]                      = imm;
                inst->op                    = MicroInstrOpcode::CmpRegImm;
                inst->numOperands           = 3;
            }
        }
    }

    if (context.ssaState)
        context.ssaState->invalidate();
    context.builder->invalidateControlFlowGraph();
    context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
