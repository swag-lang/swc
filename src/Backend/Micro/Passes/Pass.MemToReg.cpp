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

// mem2reg: promote non-escaping fixed-width scalar integer stack slots to
// virtual registers. See the header for rationale.
//
// Conservative by construction: it only fires for slots reached exclusively as
// the base of a constant-offset load/store, and it abandons promotion for the
// whole function on any use of the frame base (or a frame-derived address) that
// it does not fully understand — taking the address of one slot exposes the
// entire underlying object, so partial reasoning is unsound.

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
               op == MicroInstrOpcode::LoadMemImm;
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

    MicroReg detectFrameBase(MicroStorage& storage, MicroOperandStorage& operands, MicroReg stackPointer)
    {
        for (const MicroInstr& inst : storage.view())
        {
            if (inst.op != MicroInstrOpcode::LoadRegReg)
                continue;
            const MicroInstrOperand* ops = inst.ops(operands);
            if (!ops)
                continue;
            if (ops[1].reg == stackPointer && ops[0].reg.isVirtualInt())
                return ops[0].reg;
        }
        return MicroReg::invalid();
    }
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

    const MicroReg frameBase = detectFrameBase(storage, operands, stackPointer);
    if (!frameBase.isValid())
        return Result::Continue;

    // ---- Pass 1: collect address registers `lea ar, [fb + off]`. ----
    std::unordered_map<MicroReg, uint64_t> addrRegOffset;
    std::unordered_set<MicroReg>           badAddrReg;
    MicroInstrRef                          frameBaseDefRef = MicroInstrRef::invalid();

    for (auto it = storage.view().begin(), end = storage.view().end(); it != end; ++it)
    {
        const MicroInstr&        inst = *it;
        const MicroInstrOperand* ops  = inst.ops(operands);
        if (!ops)
            continue;

        if (inst.op == MicroInstrOpcode::LoadRegReg && ops[0].reg == frameBase && ops[1].reg == stackPointer)
        {
            frameBaseDefRef = it.current;
            continue;
        }

        if (inst.op == MicroInstrOpcode::LoadAddrRegMem && ops[1].reg == frameBase)
        {
            const MicroReg ar = ops[0].reg;
            if (!ar.isVirtualInt() || ar == frameBase)
                badAddrReg.insert(ar);
            else if (addrRegOffset.find(ar) != addrRegOffset.end())
                badAddrReg.insert(ar);
            else
                addrRegOffset[ar] = ops[3].valueU64;
        }
    }

    if (!frameBaseDefRef.isValid())
        return Result::Continue;

    auto isTracked = [&](MicroReg reg) -> bool {
        return reg == frameBase || addrRegOffset.find(reg) != addrRegOffset.end();
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
                baseReg = reg, baseSlot = extraOffset, baseValid = true;
            }
            else
            {
                const auto found = addrRegOffset.find(reg);
                if (found != addrRegOffset.end() && badAddrReg.find(reg) == badAddrReg.end())
                    baseReg = reg, baseSlot = found->second + extraOffset, baseValid = true;
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
                    pending = {ref, baseSlot, ops[2].opBits, false}, hasPending = true;
                break;
            case MicroInstrOpcode::LoadMemReg:
                resolveBase(ops[0].reg, ops[3].valueU64);
                valueReg = ops[1].reg;
                if (baseValid)
                    pending = {ref, baseSlot, ops[2].opBits, true}, hasPending = true;
                break;
            case MicroInstrOpcode::LoadMemImm:
                resolveBase(ops[0].reg, ops[2].valueU64);
                if (baseValid)
                    pending = {ref, baseSlot, ops[1].opBits, true}, hasPending = true;
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

    // ---- Decide promotable offsets: consistent b32/b64 width, a single
    //      register class (all-int or all-float), a write, and no overlap with
    //      any other accessed slot. ----
    struct Promotion
    {
        uint64_t    offset;
        MicroOpBits bits;
        bool        isFloat;
    };
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
        bool ok        = true;
        bool classKnown = false;
        bool isFloat   = false;
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
                continue;   // class resolved from reg accesses
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
                ok = false;   // mixed int/float view of the same slot
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
        const uint64_t pStart = p.offset;
        const uint64_t pEnd   = p.offset + getNumBytes(p.bits);
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

    // ---- Rewrite all accesses to the promoted registers. ----
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
        }
    }

    if (context.ssaState)
        context.ssaState->invalidate();
    context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
