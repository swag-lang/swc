#include "pch.h"
#include "Backend/Micro/Passes/Pass.MemToReg.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroSsaState.h"
#include "Backend/Micro/MicroStorage.h"
#include "Support/Core/SmallVector.h"
#include "Support/Memory/MemoryProfile.h"

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

    bool isHandledScalarMemOp(MicroInstrOpcode op)
    {
        return op == MicroInstrOpcode::LoadRegMem ||
               op == MicroInstrOpcode::LoadMemReg ||
               op == MicroInstrOpcode::LoadMemImm ||
               op == MicroInstrOpcode::LoadSignedExtRegMem ||
               op == MicroInstrOpcode::LoadZeroExtRegMem;
    }

    bool isPromotableBits(MicroOpBits bits)
    {
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
    SWC_MEM_SCOPE("Backend/MicroLower/MemToReg");
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
    std::unordered_map<MicroReg, uint64_t> addrRegOffset;
    std::unordered_set<MicroReg>           badAddrReg;

    for (auto it = storage.view().begin(), end = storage.view().end(); it != end; ++it)
    {
        const MicroInstr&        inst = *it;
        const MicroInstrOperand* ops  = inst.ops(operands);
        if (!ops)
            continue;

        if (it.current == frameBaseDefRef)
            continue;

        if (inst.op == MicroInstrOpcode::LoadAddrRegMem && ops[1].reg == frameBase)
        {
            const MicroReg ar = ops[0].reg;
            if (!ar.isVirtualInt() || ar == frameBase)
                badAddrReg.insert(ar);
            else if (addrRegOffset.contains(ar))
                badAddrReg.insert(ar);
            else
                addrRegOffset[ar] = ops[3].valueU64;
        }
    }

    auto isTracked = [&](MicroReg reg) -> bool {
        return reg == frameBase || addrRegOffset.contains(reg);
    };

    // ---- Pass 2: classify accesses; bail the whole function on any escape. ----
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
                    baseSlot  = found->second + extraOffset;
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
                resolveBase(ops[1].reg, ops[3].valueU64);
                valueReg = ops[0].reg;
                if (baseValid)
                {
                    pending    = {ref, baseSlot, ops[2].opBits, false};
                    hasPending = true;
                }
                break;
            case MicroInstrOpcode::LoadMemReg:
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
            default:
                break;
        }

        // Moving a tracked pointer as a value means the address escapes.
        if (baseValid && valueReg.isValid() && isTracked(valueReg))
        {
            bail = true;
            break;
        }

        // Any tracked register appearing anywhere other than as the base of a
        // recognized scalar access is an escape we cannot reason about.
        SmallVector<MicroInstrRegOperandRef> regRefs;
        inst.collectRegOperands(operands, regRefs, context.encoder);
        for (const auto& rref : regRefs)
        {
            if (!rref.reg || !isTracked(*rref.reg))
                continue;
            const bool isExplainedBase = baseValid && *rref.reg == baseReg && isHandledScalarMemOp(inst.op);
            if (!isExplainedBase)
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

    for (auto& [offset, slot] : slots)
    {
        if (slot.accesses.empty() || !slot.hasWrite)
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
            if (inst->op == MicroInstrOpcode::LoadMemImm)
                continue; // class resolved from reg accesses
            const MicroReg valueReg = (inst->op == MicroInstrOpcode::LoadRegMem) ? iops[0].reg : iops[1].reg;
            const bool     regFloat = valueReg.isAnyFloat();
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

        if (isFloat)
        {
            // A float slot initialized via an integer immediate store can't be
            // turned into a float register copy safely — skip it.
            bool hasImm = false;
            for (const SlotAccess& acc : slot.accesses)
            {
                const MicroInstr* inst = storage.ptr(acc.ref);
                if (inst && inst->op == MicroInstrOpcode::LoadMemImm)
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

            if (inst->op == MicroInstrOpcode::LoadRegMem)
            {
                const MicroReg dst = ops[0].reg;
                ops[0].reg         = dst;
                ops[1].reg         = vreg;
                ops[2].opBits      = bits;
                inst->op           = MicroInstrOpcode::LoadRegReg;
                inst->numOperands  = 3;
            }
            else if (inst->op == MicroInstrOpcode::LoadMemReg)
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
        }
    }

    if (context.ssaState)
        context.ssaState->invalidate();
    context.builder->invalidateControlFlowGraph();
    context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
