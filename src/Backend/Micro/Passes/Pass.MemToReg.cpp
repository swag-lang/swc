#include "pch.h"
#include "Backend/Micro/Passes/Pass.MemToReg.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroControlFlowGraph.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"
#include "Backend/Micro/MicroPassHelpers.h"
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
        uint64_t                maxAccessEnd       = 0;
        bool                    hasWrite           = false;
        bool                    stackPointerAccess = false;
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

    // Whether `reg`, read at `atRef`, holds an all-zero vector. The producer
    // that matters is the clear the front end emits for a local's
    // zero-initialization; a register redefined by anything else in between is
    // not one.
    bool isZeroedVectorRegister(MicroStorage& storage, MicroOperandStorage& operands, MicroInstrRef atRef, MicroReg reg)
    {
        if (!reg.isValid())
            return false;
        for (MicroInstrRef cur = storage.findPreviousInstructionRef(atRef); cur.isValid(); cur = storage.findPreviousInstructionRef(cur))
        {
            const MicroInstr* inst = storage.ptr(cur);
            if (!inst)
                return false;
            const MicroInstrOperand* ops = inst->ops(operands);
            if (!ops)
                continue;
            const auto modes   = MicroInstr::info(inst->op).resolvedRegModes(ops);
            bool       defines = false;
            for (size_t i = 0; i < modes.size(); ++i)
                defines |= (modes[i] == MicroInstrRegMode::Def || modes[i] == MicroInstrRegMode::UseDef) && ops[i].reg == reg;
            if (!defines)
                continue;
            return inst->op == MicroInstrOpcode::ClearReg && ops[0].reg == reg;
        }
        return false;
    }

    bool isPromotableBits(MicroOpBits bits)
    {
        // 128 bits is the vector width, and a float register copy of it is full width too;
        // the class check downstream is what keeps it off the integer file.
        if (bits == MicroOpBits::B128)
            return true;
        // Every scalar width has a register copy of the same shape as its memory
        // access: a 64-bit copy is full width, a 32-bit write zero-extends the
        // register exactly as the 32-bit load does, and the 8- and 16-bit forms
        // are partial writes on both sides - a byte load leaves the upper bits
        // alone and so does a byte register copy, so a slot every access reads
        // and writes at that one width promotes without any extension. For
        // floats, b32/b64 are the scalar single/double widths.
        return bits == MicroOpBits::B8 || bits == MicroOpBits::B16 || bits == MicroOpBits::B32 || bits == MicroOpBits::B64;
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
    MicroReg detectFrameBase(MicroStorage& storage, MicroOperandStorage& operands, MicroReg stackPointer, MicroReg preferred, MicroInstrRef& outDefRef, uint64_t& outSpOffset)
    {
        struct Cand
        {
            MicroInstrRef defRef   = MicroInstrRef::invalid();
            uint64_t      spOffset = 0;
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
                {
                    c.defRef   = it.current;
                    c.spOffset = isLea ? ops[3].valueU64 : 0;
                }
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

            const auto modes = MicroInstr::info(inst.op).resolvedRegModes(ops);
            for (size_t i = 0; i < modes.size(); ++i)
            {
                if (modes[i] != MicroInstrRegMode::Def && modes[i] != MicroInstrRegMode::UseDef)
                    continue;
                const auto found = cands.find(ops[i].reg);
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

        // The code generator names the register its locals hang from; when it
        // is a stable candidate it is the base, however many other addresses
        // the function derives from the stack pointer. The local extents the
        // escapes are measured against are offsets from that register, and a
        // detection that settled on another sp-derived register - an indirect
        // return slot's, a parameter home's - left every extent unusable and
        // every escape a whole-function bail.
        if (preferred.isValid())
        {
            const auto found = cands.find(preferred);
            if (found != cands.end() && found->second.stable && found->second.defRef.isValid())
            {
                outDefRef   = found->second.defRef;
                outSpOffset = found->second.spOffset;
                return preferred;
            }
        }

        MicroReg best;
        uint32_t bestUses = 0;
        for (const auto& [reg, c] : cands)
        {
            if (c.stable && c.defRef.isValid() && c.baseUses > bestUses)
            {
                best        = reg;
                bestUses    = c.baseUses;
                outDefRef   = c.defRef;
                outSpOffset = c.spOffset;
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

    // The reads a field of a split word can serve: each has a register form
    // that reads the field's width from the low bits of a register.
    bool isFieldReadOp(MicroInstrOpcode op)
    {
        return op == MicroInstrOpcode::LoadRegMem ||
               op == MicroInstrOpcode::LoadSignedExtRegMem ||
               op == MicroInstrOpcode::LoadZeroExtRegMem ||
               op == MicroInstrOpcode::OpBinaryRegMem ||
               op == MicroInstrOpcode::CmpMemReg ||
               op == MicroInstrOpcode::CmpMemImm;
    }

    // Turns one slot access into the register form of the same operation on
    // `vreg`, at the width the access used.
    void rewriteSlotAccess(MicroStorage& storage, MicroOperandStorage& operands, const SlotAccess& acc, const MicroReg vreg)
    {
        const MicroOpBits bits = acc.bits;

        MicroInstr* inst = storage.ptr(acc.ref);
        if (!inst)
            return;
        MicroInstrOperand* ops = inst->ops(operands);
        if (!ops)
            return;

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

    MicroInstrRef  frameBaseDefRef   = MicroInstrRef::invalid();
    uint64_t       frameBaseSpOffset = 0;
    const MicroReg frameBase         = detectFrameBase(storage, operands, stackPointer, context.debugStackBaseVirtualReg, frameBaseDefRef, frameBaseSpOffset);
    if (!frameBase.isValid() || !frameBaseDefRef.isValid())
        return Result::Continue;

    // The stack pointer names the same frame as the base, shifted by where the
    // base sits: once the peephole folds the code generator's base copy into
    // its users, `[sp + C]` and `lea r, [sp + C]` are `[fb + C - D]` for a base
    // `lea fb, [sp + D]`. Reading them as anything else hides both their
    // writes and the escape of the addresses they make. That only holds while
    // the body never moves the stack pointer. A function with calls can reserve
    // outgoing argument space around each call while continuing to address all
    // locals through the stable frame base. In that case, ignore SP-relative
    // memory altogether instead of abandoning promotion for the frame-base
    // slots. A local address stored into the untracked outgoing area still
    // appears as a tracked VALUE and the generic escape scan poisons its object.
    bool stackPointerTracksFrame = true;
    {
        bool spMoved    = false;
        bool inEntryRun = true;
        for (auto it = storage.view().begin(), end = storage.view().end(); it != end && !spMoved; ++it)
        {
            const MicroInstrOperand* ops = it->ops(operands);
            if (it->op == MicroInstrOpcode::Nop || it->op == MicroInstrOpcode::Label)
                continue;
            const bool isAdjust = it->op == MicroInstrOpcode::OpBinaryRegImm && ops && ops[0].reg == stackPointer;
            if (!isAdjust)
                inEntryRun = false;
            if (it.current == frameBaseDefRef)
                continue;
            if (isAdjust)
            {
                if (!inEntryRun)
                {
                    MicroInstrRef next = storage.findNextInstructionRef(it.current);
                    while (next.isValid() && storage.ptr(next)->op == MicroInstrOpcode::Nop)
                        next = storage.findNextInstructionRef(next);
                    if (!next.isValid() || storage.ptr(next)->op != MicroInstrOpcode::Ret)
                        spMoved = true;
                }
                continue;
            }

            if (!ops)
                continue;
            const auto modes = MicroInstr::info(it->op).resolvedRegModes(ops);
            for (size_t i = 0; i < modes.size(); ++i)
            {
                if ((modes[i] == MicroInstrRegMode::Def || modes[i] == MicroInstrRegMode::UseDef) && ops[i].reg == stackPointer)
                    spMoved = true;
            }
        }
        stackPointerTracksFrame = !spMoved;
    }
    const auto isFrameRegister = [&](const MicroReg reg) {
        return reg == frameBase || (stackPointerTracksFrame && reg == stackPointer);
    };
    const auto frameRegisterOffset = [&](const MicroReg reg) -> uint64_t {
        return reg == stackPointer ? 0ull - frameBaseSpOffset : 0;
    };

    // ---- Pass 1: collect address registers `lea ar, [fb + off]`. ----
    struct AddrRegInfo
    {
        uint64_t      offset    = 0;
        MicroInstrRef defRef    = MicroInstrRef::invalid();
        bool          ambiguous = false;
    };
    // These tables describe one function, but their capacity can serve
    // later mem2reg rounds and functions on the same worker.
    thread_local std::unordered_map<MicroReg, AddrRegInfo> addrRegOffset;
    thread_local std::unordered_set<uint32_t>              addressAdjustments;
    // The further frame offsets a register is given by later leas or copies:
    // it may point at any of those objects, so an escape poisons them all.
    thread_local std::unordered_map<MicroReg, SmallVector<uint64_t, 2>> addrRegMoreOffsets;
    addrRegOffset.clear();
    addressAdjustments.clear();
    addrRegMoreOffsets.clear();

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
        const bool isAddrLea  = inst.op == MicroInstrOpcode::LoadAddrRegMem && isFrameRegister(ops[1].reg);
        const bool isBaseCopy = inst.op == MicroInstrOpcode::LoadRegReg && isFrameRegister(ops[1].reg) && ops[2].opBits == MicroOpBits::B64;
        if (isAddrLea || isBaseCopy)
        {
            const MicroReg ar     = ops[0].reg;
            uint64_t       offset = (isAddrLea ? ops[3].valueU64 : 0) + frameRegisterOffset(ops[1].reg);
            // An adjacent add/sub is an exact address even when its flags are
            // live and prevent folding the pair to LEA. No access can observe
            // the intermediate pointer between these adjacent instructions.
            const MicroInstrRef nextRef = storage.findNextInstructionRef(it.current);
            const MicroInstr*   next    = nextRef.isValid() ? storage.ptr(nextRef) : nullptr;
            if (next && next->op == MicroInstrOpcode::OpBinaryRegImm && ar.isVirtualInt() && ar != frameBase)
            {
                const MicroInstrOperand* nextOps = next->ops(operands);
                if (nextOps[0].reg == ar && nextOps[1].opBits == MicroOpBits::B64 && !nextOps[3].hasWideImmediateValue() &&
                    (nextOps[2].microOp == MicroOp::Add || nextOps[2].microOp == MicroOp::Subtract))
                {
                    offset += nextOps[2].microOp == MicroOp::Add ? nextOps[3].valueU64 : 0ull - nextOps[3].valueU64;
                    addressAdjustments.insert(nextRef.get());
                }
            }
            if (!ar.isVirtualInt() || ar == frameBase)
                continue;
            const auto [found, inserted] = addrRegOffset.try_emplace(ar, AddrRegInfo{offset, it.current});
            if (!inserted)
            {
                found->second.ambiguous = true;
                addrRegMoreOffsets[ar].push_back(offset);
            }
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
            const MicroInstrOperand* ops = it->ops(operands);
            if (!ops)
                continue;
            const auto modes = MicroInstr::info(it->op).resolvedRegModes(ops);
            for (size_t i = 0; i < modes.size(); ++i)
            {
                if (modes[i] != MicroInstrRegMode::Def && modes[i] != MicroInstrRegMode::UseDef)
                    continue;
                const auto found = addrRegOffset.find(ops[i].reg);
                if (found != addrRegOffset.end() && it.current != found->second.defRef && !addressAdjustments.contains(it.current.get()))
                {
                    // A frame-derived pointer can cross local-object boundaries:
                    // lowering spells an address as `copy frame; add offset`.
                    // Its original object does not bound the modified pointer.
                    // Only another recorded frame address has a known extent;
                    // defer promotion until address folding resolves the rest.
                    const bool knownFrameAddress = (it->op == MicroInstrOpcode::LoadAddrRegMem ||
                                                    (it->op == MicroInstrOpcode::LoadRegReg && ops[2].opBits == MicroOpBits::B64)) &&
                                                   isFrameRegister(ops[1].reg);
                    if (!knownFrameAddress)
                        return Result::Continue;
                    found->second.ambiguous = true;
                }
            }
        }
    }

    // Follow pointer copies whose only definition follows the known address on
    // the same straight line. Interface dispatch copies a local's address into
    // a temporary before reading its first field; the copy does not expose the
    // object. An actual escape through either register still poisons it below.
    std::unordered_set<uint32_t> addressCopies;
    if (!addrRegOffset.empty())
    {
        std::unordered_map<MicroReg, uint32_t> definitions;
        for (const MicroInstr& inst : storage.view())
        {
            const auto* ops   = inst.ops(operands);
            const auto  modes = MicroInstr::info(inst.op).resolvedRegModes(ops);
            for (size_t i = 0; i < modes.size(); ++i)
                if ((modes[i] == MicroInstrRegMode::Def || modes[i] == MicroInstrRegMode::UseDef) && ops[i].reg.isVirtualInt())
                    ++definitions[ops[i].reg];
        }
        std::unordered_set<MicroReg> available;
        for (auto it = storage.view().begin(), end = storage.view().end(); it != end; ++it)
        {
            const auto& info = MicroInstr::info(it->op);
            if (it->op == MicroInstrOpcode::Label || info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                info.flags.has(MicroInstrFlagsE::IsCallInstruction) || info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
                available.clear();
            const auto* ops = it->ops(operands);
            if (!ops)
                continue;
            if (it->op == MicroInstrOpcode::LoadRegReg && ops[2].opBits == MicroOpBits::B64 &&
                ops[0].reg.isVirtualInt() && ops[0].reg != frameBase && definitions[ops[0].reg] == 1 &&
                !addrRegOffset.contains(ops[0].reg) && available.contains(ops[1].reg))
            {
                const uint64_t offset = addrRegOffset.at(ops[1].reg).offset;
                addrRegOffset.emplace(ops[0].reg, AddrRegInfo{offset, it.current});
                addressCopies.insert(it.current.get());
            }
            const auto found = addrRegOffset.find(ops[0].reg);
            if (found != addrRegOffset.end() && !found->second.ambiguous && found->second.defRef == it.current)
                available.insert(found->first);
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
        uint64_t      lo          = 0;
        uint64_t      hi          = 0;
        MicroInstrRef firstEscape = MicroInstrRef::invalid();
        bool          poisoned    = false;
    };
    thread_local std::vector<FrameVarRange> varRanges;
    varRanges.clear();

    const bool rangesUsable = context.sanitizerFunction != nullptr &&
                              (!context.debugStackBaseVirtualReg.isValid() || context.debugStackBaseVirtualReg == frameBase);
    bool varRangesReady = false;

    // An escape at an offset outside every known variable exposes an object the
    // analysis cannot bound - a compiler temporary such as an error payload,
    // which the front end does not list as a local. Frame objects are disjoint,
    // so that unknown object cannot overlap a known variable: the sound answer
    // is to treat all frame space OUTSIDE the known variables as reachable
    // through the escaped pointer, and keep promoting inside them.
    bool          unknownSpaceEscaped = false;
    MicroInstrRef unknownFirstEscape  = MicroInstrRef::invalid();
    // The instruction pass 2 is classifying: where an escape it records happens.
    MicroInstrRef escapingRef = MicroInstrRef::invalid();

    // Poison the variable containing 'offset'; false only when no extent
    // information is available at all and the caller must fall back to the
    // whole-function bail.
    auto poisonEscapedOffset = [&](const uint64_t offset) -> bool {
        if (!rangesUsable)
            return false;
        if (!varRangesReady)
        {
            thread_local std::vector<std::pair<uint64_t, uint64_t>> extents;
            MicroPassHelpers::collectFrameVariableExtents(extents, context, frameBase);
            for (const auto& [lo, hi] : extents)
                varRanges.push_back({.lo = lo, .hi = hi});
            varRangesReady = true;
        }
        bool found = false;
        for (FrameVarRange& range : varRanges)
        {
            if (offset >= range.lo && offset < range.hi)
            {
                if (!range.poisoned)
                    range.firstEscape = escapingRef;
                range.poisoned = true;
                found          = true;
            }
        }
        if (!found && !unknownSpaceEscaped)
        {
            unknownSpaceEscaped = true;
            unknownFirstEscape  = escapingRef;
        }
        return true;
    };

    // The escaped offset of a tracked register: the frame offset it was given.
    // One given a second recorded frame object is escaped for both (see
    // poisonTrackedEscape); unbounded redefinitions were rejected above.
    auto trackedEscapeOffset = [&](const MicroReg reg, uint64_t& outOffset) -> bool {
        if (reg == frameBase)
            return false;
        const auto found = addrRegOffset.find(reg);
        if (found == addrRegOffset.end())
            return false;
        outOffset = found->second.offset;
        return true;
    };

    // Poisons the object `offset` bytes behind every frame object the tracked
    // register `reg` was given.
    auto poisonTrackedEscape = [&](const MicroReg reg, const uint64_t baseOffset, const uint64_t extra) -> bool {
        if (!poisonEscapedOffset(baseOffset + extra))
            return false;
        const auto more = addrRegMoreOffsets.find(reg);
        if (more != addrRegMoreOffsets.end())
        {
            for (const uint64_t offset : more->second)
            {
                if (!poisonEscapedOffset(offset + extra))
                    return false;
            }
        }
        return true;
    };

    // Same, for the appearances that use the pointer AS the address of the
    // object it points to: stored as a plain value, or the base of an indexed
    // (Amc) access. There the frame base itself is meaningful: it is the
    // address of the object at offset zero - the store-operand spelling of the
    // degenerate `mov ar, fb` the collection pass models - and the front end
    // produces it whenever the address of a function's FIRST local escapes or
    // is indexed (an inlined callee's pointer parameter home, a `state[i]`
    // over a first local). Every appearance of the base as a value is read
    // the same way: the first local, escaping.
    auto escapedObjectOffset = [&](const MicroReg reg, uint64_t& outOffset) -> bool {
        if (isFrameRegister(reg))
        {
            outOffset = frameRegisterOffset(reg);
            return true;
        }
        return trackedEscapeOffset(reg, outOffset);
    };

    // ---- Pass 2: classify accesses; an unexplained escape poisons the
    //      containing variable, or bails the whole function when it cannot be
    //      pinned to one. ----
    thread_local std::unordered_map<uint64_t, SlotInfo> slots;
    slots.clear();
    SmallVector<std::pair<uint64_t, uint64_t>> wrappingRanges;
    bool bail               = false;
    bool hasFieldSplitWrite = false;
    bool hasNarrowFieldRead = false;
    bool hasVectorWrite     = false;
    // Slots addressed directly by the stack pointer include outgoing arguments;
    // a callee can read those behind this analysis, so they cannot be promoted.
    for (auto it = storage.view().begin(), end = storage.view().end(); it != end && !bail; ++it)
    {
        const MicroInstrRef      ref  = it.current;
        const MicroInstr&        inst = *it;
        const MicroInstrOperand* ops  = inst.ops(operands);
        if (!ops)
            continue;
        escapingRef = ref;

        if (ref == frameBaseDefRef)
            continue;
        if (addressAdjustments.contains(ref.get()))
            continue;
        if (addressCopies.contains(ref.get()))
            continue;
        if (inst.op == MicroInstrOpcode::LoadAddrRegMem && isFrameRegister(ops[1].reg))
            continue;
        // The `mov ar, fb` address definition recognized by pass 1.
        if (inst.op == MicroInstrOpcode::LoadRegReg && isFrameRegister(ops[1].reg) && ops[2].opBits == MicroOpBits::B64 && addrRegOffset.contains(ops[0].reg))
            continue;
        // The entry subtract and the releases, checked above.
        if (inst.op == MicroInstrOpcode::OpBinaryRegImm && ops[0].reg == stackPointer)
            continue;

        MicroReg baseReg   = MicroReg::invalid();
        uint64_t baseSlot  = 0;
        bool     baseValid = false;

        auto resolveBase = [&](MicroReg reg, uint64_t extraOffset) {
            if (isFrameRegister(reg))
            {
                baseReg   = reg;
                baseSlot  = extraOffset + frameRegisterOffset(reg);
                baseValid = true;
            }
            else
            {
                const auto found = addrRegOffset.find(reg);
                if (found != addrRegOffset.end() && !found->second.ambiguous)
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
            case MicroInstrOpcode::OpUnaryAmcMem:
            case MicroInstrOpcode::OpBinaryAmcMemImm:
            case MicroInstrOpcode::CmpAmcReg:
                amcBase = ops[0].reg;
                break;
            default:
                break;
        }
        if (amcBase.isValid() && (isFrameRegister(amcBase) || isTracked(amcBase)))
        {
            // The object is the one at the base's offset plus the access's
            // displacement: a lea of the array's address folded into the
            // indexed form leaves the array behind the displacement, not
            // behind the base.
            MicroPassHelpers::AmcLayout layout;
            uint64_t                    escapedOffset = 0;
            if (!MicroPassHelpers::amcLayoutFor(layout, inst.op) || !escapedObjectOffset(amcBase, escapedOffset) || !poisonTrackedEscape(amcBase, escapedOffset, ops[layout.addIdx].valueU64))
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
            if (!resolved || !poisonTrackedEscape(valueReg, escapedOffset, 0))
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
        const auto modes = MicroInstr::info(inst.op).resolvedRegModes(ops);
        for (size_t i = 0; i < modes.size(); ++i)
        {
            if (modes[i] == MicroInstrRegMode::None)
                continue;
            const MicroReg reg = ops[i].reg;
            if (!reg.isValid() || reg.isNoBase() ||
                !(isTracked(reg) || (stackPointerTracksFrame && reg == stackPointer)))
                continue;
            const bool isExplainedBase    = baseValid && reg == baseReg && isHandledScalarMemOp(inst.op);
            const bool isExplainedValue   = storesTrackedValue && reg == valueReg;
            const bool isExplainedAmcBase = amcBase.isValid() && reg == amcBase;
            if (isExplainedBase || isExplainedValue || isExplainedAmcBase)
                continue;
            // The frame base read as a value - added to an element offset,
            // copied into an argument register, compared, stored - is the
            // address of the first local, whose object escapes; the front end
            // forms every element address from the object's address, so the
            // base never stands for another object.
            uint64_t   escapedOffset = 0;
            const bool resolved      = escapedObjectOffset(reg, escapedOffset);
            if (!resolved || !poisonTrackedEscape(reg, escapedOffset, 0))
            {
                bail = true;
                break;
            }
        }
        if (bail)
            break;

        if (hasPending)
        {
            // Interval proofs below use unsigned half-open ranges. An outgoing
            // object below the local frame base can end at offset zero: its
            // wrapped endpoint must not make it appear inside a known local.
            if (pending.offset + getNumBytes(pending.bits) <= pending.offset)
                wrappingRanges.emplace_back(pending.offset, pending.offset + getNumBytes(pending.bits));
            if (baseReg != stackPointer && inst.op == MicroInstrOpcode::LoadMemReg &&
                pending.bits == MicroOpBits::B64 && ops[1].reg.isAnyInt())
                hasFieldSplitWrite = true;
            if (!pending.isWrite && isFieldReadOp(inst.op) &&
                (pending.bits == MicroOpBits::B8 || pending.bits == MicroOpBits::B16 || pending.bits == MicroOpBits::B32))
                hasNarrowFieldRead = true;
            SlotInfo& slot = slots[pending.offset];
            slot.stackPointerAccess |= baseReg == stackPointer;
            slot.accesses.push_back(pending);
            // Compare computed ends, not widths: displacement addition can wrap.
            slot.maxAccessEnd = std::max(slot.maxAccessEnd, pending.offset + getNumBytes(pending.bits));
            if (pending.isWrite)
            {
                slot.hasWrite = true;
                hasVectorWrite |= pending.bits == MicroOpBits::B128;
            }
        }
    }

    if (bail)
        return Result::Continue;

    bool erasedDeadStores = false;
    const auto finish     = [&] {
        if (context.ssaState)
            context.ssaState->invalidate();
        context.builder->invalidateControlFlowGraph();
        context.passChanged = true;
        return Result::Continue;
    };

    // ---- Stores killed by a later store before anything reads them. ----
    //
    // A local is cleared where it is declared, and a program that then writes
    // every byte of it before reading one leaves that clear dead - a transpose
    // tile filled right after its declaration, a record assembled field by
    // field over its zero default. On one straight line, a store is dead once
    // later stores through the frame have covered each of its bytes and no
    // instruction in between read an uncovered one.
    //
    // Reads the analysis resolved are compared byte for byte. Any other read
    // through the frame, or through the stack pointer, may reach the store and
    // keeps it. A read through some other pointer cannot reach an object whose
    // address never escapes; nor, on the function's entry line, one whose first
    // escape has not been executed yet, since nothing before that escape can
    // have handed its address out. Calls, jumps and labels end the line.
    {
        // Only a store some other write overlaps can be killed.
        thread_local std::vector<std::pair<uint64_t, uint64_t>> writeRanges;
        writeRanges.clear();
        for (const auto& [offset, slot] : slots)
        {
            for (const SlotAccess& acc : slot.accesses)
            {
                if (acc.isWrite)
                    writeRanges.emplace_back(offset, offset + getNumBytes(acc.bits));
            }
        }
        std::ranges::sort(writeRanges);
        bool overlappingWrites = false;
        for (size_t i = 1; i < writeRanges.size() && !overlappingWrites; ++i)
            overlappingWrites = writeRanges[i].first < writeRanges[i - 1].second;

        if (overlappingWrites && wrappingRanges.empty())
        {
            thread_local std::unordered_map<uint32_t, const SlotAccess*> accessOf;
            accessOf.clear();
            for (const auto& [offset, slot] : slots)
            {
                for (const SlotAccess& acc : slot.accesses)
                    accessOf[acc.ref.get()] = &acc;
            }

            // The object a byte range lies in: a known variable's index, or
            // -1 for the frame space outside every known variable.
            const auto objectOf = [&](const uint64_t lo, const uint64_t hi) -> int32_t {
                for (size_t i = 0; i < varRanges.size(); ++i)
                {
                    if (lo >= varRanges[i].lo && hi <= varRanges[i].hi)
                        return static_cast<int32_t>(i);
                }
                return -1;
            };

            struct PendingStore
            {
                MicroInstrRef ref       = MicroInstrRef::invalid();
                uint64_t      lo        = 0;
                uint32_t      uncovered = 0;
                int32_t       object    = -1;
                bool          onEntry   = false;
            };
            constexpr uint32_t         K_MAX_PENDING = 64;
            SmallVector<PendingStore>  pendingStores;
            SmallVector<MicroInstrRef> deadStores;
            std::vector<uint8_t>       escapedNow(varRanges.size(), 0);
            bool                       unknownEscapedNow = false;
            bool                       onEntryLine       = true;

            // Whether a read through a pointer the analysis does not track can
            // see the pending store's object at this point.
            const auto reachableByUnknownPointer = [&](const PendingStore& pendingStore) {
                if (pendingStore.object < 0)
                    return unknownSpaceEscaped && (!pendingStore.onEntry || unknownEscapedNow);
                const FrameVarRange& range = varRanges[pendingStore.object];
                return range.poisoned && (!pendingStore.onEntry || escapedNow[pendingStore.object] != 0);
            };

            // The bytes of [lo, lo + 16) an access to [accessLo, accessHi) touches.
            const auto touchedBytes = [](const uint64_t lo, const uint64_t accessLo, const uint64_t accessHi) -> uint32_t {
                const uint64_t from = std::max(lo, accessLo);
                const uint64_t to   = std::min(lo + 16, accessHi);
                if (from >= to)
                    return 0;
                const uint32_t width = static_cast<uint32_t>(to - from);
                return ((1u << width) - 1) << (from - lo);
            };

            for (auto it = storage.view().begin(), end = storage.view().end(); it != end; ++it)
            {
                const MicroInstrRef      ref  = it.current;
                const MicroInstr&        inst = *it;
                const MicroInstrDef&     info = MicroInstr::info(inst.op);
                const MicroInstrOperand* ops  = inst.ops(operands);

                if (inst.op == MicroInstrOpcode::Label || info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                    info.flags.has(MicroInstrFlagsE::IsCallInstruction) || info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
                {
                    pendingStores.clear();
                    onEntryLine = false;
                    continue;
                }

                // Escapes first: the instruction that hands an address out can
                // also read through it.
                if (onEntryLine)
                {
                    for (size_t i = 0; i < varRanges.size(); ++i)
                        escapedNow[i] |= varRanges[i].firstEscape == ref ? 1 : 0;
                    unknownEscapedNow |= unknownFirstEscape == ref;
                }

                const auto found = accessOf.find(ref.get());
                if (found != accessOf.end())
                {
                    const SlotAccess& acc       = *found->second;
                    const uint64_t    accessLo  = acc.offset;
                    const uint64_t    accessHi  = acc.offset + getNumBytes(acc.bits);
                    const bool        pureStore = inst.op == MicroInstrOpcode::LoadMemReg ||
                                           inst.op == MicroInstrOpcode::LoadMemImm ||
                                           inst.op == MicroInstrOpcode::StoreVecMemReg;
                    for (size_t i = 0; i < pendingStores.size();)
                    {
                        PendingStore&  pendingStore = pendingStores[i];
                        const uint32_t touched      = touchedBytes(pendingStore.lo, accessLo, accessHi) & pendingStore.uncovered;
                        if (touched && !pureStore)
                        {
                            pendingStores.erase(pendingStores.begin() + i);
                            continue;
                        }
                        if (touched)
                        {
                            pendingStore.uncovered &= ~touched;
                            if (!pendingStore.uncovered)
                            {
                                deadStores.push_back(pendingStore.ref);
                                pendingStores.erase(pendingStores.begin() + i);
                                continue;
                            }
                        }
                        ++i;
                    }

                    const uint64_t width = accessHi - accessLo;
                    if (pureStore && width <= 16 && pendingStores.size() < K_MAX_PENDING)
                    {
                        PendingStore pendingStore;
                        pendingStore.ref       = ref;
                        pendingStore.lo        = accessLo;
                        pendingStore.uncovered = (1u << width) - 1;
                        pendingStore.object    = objectOf(accessLo, accessHi);
                        pendingStore.onEntry   = onEntryLine;
                        pendingStores.push_back(pendingStore);
                    }
                    continue;
                }

                if (pendingStores.empty() || !ops)
                    continue;

                // A read the analysis could not place. Stores through other
                // pointers read nothing.
                uint8_t    baseIndex = 0;
                const bool viaBase   = MicroPassHelpers::dereferenceBaseOperandIndex(baseIndex, inst.op, info);
                bool       reads     = false;
                if (viaBase)
                    reads = inst.op != MicroInstrOpcode::LoadMemReg && inst.op != MicroInstrOpcode::LoadMemImm &&
                            inst.op != MicroInstrOpcode::StoreVecMemReg && inst.op != MicroInstrOpcode::LoadAmcMemReg &&
                            inst.op != MicroInstrOpcode::LoadAmcMemImm;
                else
                    reads = inst.op == MicroInstrOpcode::Pop || inst.op == MicroInstrOpcode::LoadRegTlsSlot ||
                            inst.op == MicroInstrOpcode::SanityInvalidate || inst.op == MicroInstrOpcode::Breakpoint;
                if (!reads)
                    continue;

                const MicroReg base         = viaBase ? ops[baseIndex].reg : MicroReg::invalid();
                const bool     framePointer = !base.isValid() || isFrameRegister(base) || isTracked(base) || base == stackPointer;
                for (size_t i = 0; i < pendingStores.size();)
                {
                    if (framePointer || reachableByUnknownPointer(pendingStores[i]))
                        pendingStores.erase(pendingStores.begin() + i);
                    else
                        ++i;
                }
            }

            // The stores go, and so do their accesses: what the slots still
            // see is what the rest of this round rewrites.
            if (!deadStores.empty())
            {
                std::unordered_set<uint32_t> erased;
                for (const MicroInstrRef deadStore : deadStores)
                {
                    erased.insert(deadStore.get());
                    storage.erase(deadStore);
                }
                for (auto& [offset, slot] : slots)
                {
                    SmallVector<SlotAccess> live;
                    for (const SlotAccess& acc : slot.accesses)
                    {
                        if (!erased.contains(acc.ref.get()))
                            live.push_back(acc);
                    }
                    slot.accesses = std::move(live);
                    slot.hasWrite = std::ranges::any_of(slot.accesses, [](const SlotAccess& acc) { return acc.isWrite; });
                }
                std::erase_if(slots, [](const auto& entry) { return entry.second.accesses.empty(); });
                context.builder->invalidateControlFlowGraph();
                erasedDeadStores = true;
            }
        }
    }

    // ---- Decide candidate offsets: consistent b32/b64 width, a single
    //      register class (all-int or all-float), a write, and no overlap with
    //      any other accessed slot. ----
    SmallVector<Promotion> promotions;

    auto overlapsPoisonedVariable = [&](const uint64_t lo, const uint64_t hi) -> bool {
        if (hi <= lo)
            return true;
        for (const auto& [wrapLo, wrapHi] : wrappingRanges)
            if (lo < wrapHi || wrapLo < hi)
                return true;
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

    // ---- Scalarize a vector zero-fill over narrowly-used slots. ----
    //
    // A local array is zero-initialized with 16-byte stores of a cleared vector
    // register, whatever its element width. Every element then carries both
    // that B128 write and its own narrow accesses, and a wider WRITE
    // disqualifies the slot (see the width-disagreement rule below), so the
    // whole array stays in memory and pays a load and a store per operation.
    //
    // The fill becomes one immediate store per element when the sixteen bytes
    // it covers are otherwise used only as scalars of one width, each starting
    // on its own element boundary - which is what says the object is an array
    // of scalars and not a vector. Promotion then happens on the next sweep of
    // the pre-RA loop, from a slot map with no width disagreement left.
    //
    // Only the zero fill is split. A whole-object copy is the other vector
    // access such an array sees, and splitting it means rebuilding the loaded
    // value element by element, which this does not attempt.
    if (hasVectorWrite)
    {
        SmallVector<std::pair<MicroInstrRef, std::pair<uint64_t, uint64_t>>> fills;
        for (const auto& [offset, slot] : slots)
        {
            for (const SlotAccess& acc : slot.accesses)
            {
                if (!acc.isWrite || acc.bits != MicroOpBits::B128)
                    continue;
                const MicroInstr* fill = storage.ptr(acc.ref);
                if (!fill || (fill->op != MicroInstrOpcode::LoadMemReg && fill->op != MicroInstrOpcode::StoreVecMemReg))
                    continue;
                if (!isZeroedVectorRegister(storage, operands, acc.ref, fill->ops(operands)[1].reg))
                    continue;

                const uint64_t lo           = offset;
                const uint64_t hi           = offset + getNumBytes(MicroOpBits::B128);
                uint64_t       elementBytes = 0;
                bool           uniform      = true;
                for (const auto& [other, otherSlot] : slots)
                {
                    if (otherSlot.maxAccessEnd <= lo || other >= hi)
                        continue;
                    if (otherSlot.stackPointerAccess)
                        uniform = false;
                    for (const SlotAccess& inner : otherSlot.accesses)
                    {
                        if (inner.ref == acc.ref)
                            continue;
                        const uint64_t width = getNumBytes(inner.bits);
                        if (width != 4 && width != 8)
                            uniform = false;
                        else if (!elementBytes)
                            elementBytes = width;
                        else if (elementBytes != width)
                            uniform = false;
                        if (!uniform || other + width > hi || (other - lo) % width != 0)
                        {
                            uniform = false;
                            break;
                        }
                    }
                    if (!uniform)
                        break;
                }
                if (!uniform || !elementBytes ||
                    overlapsPoisonedVariable(lo, hi) || (unknownSpaceEscaped && !insideKnownVariable(lo, hi)))
                    continue;

                fills.emplace_back(acc.ref, std::make_pair(offset, elementBytes));
            }
        }

        if (!fills.empty())
        {
            for (const auto& [fillRef, shape] : fills)
            {
                const auto [offset, elementBytes] = shape;
                const MicroOpBits bits            = elementBytes == 8 ? MicroOpBits::B64 : MicroOpBits::B32;
                const uint64_t    count           = getNumBytes(MicroOpBits::B128) / elementBytes;
                for (uint64_t i = 0; i < count; ++i)
                {
                    MicroInstrOperand storeOps[4] = {};
                    // The collected offset is relative to the frame, even
                    // when the original fill used a derived address register.
                    storeOps[0].reg               = frameBase;
                    storeOps[1].opBits            = bits;
                    storeOps[2].valueU64          = offset + i * elementBytes;
                    storeOps[3].setImmediateValue(ApInt(uint64_t{0}, getNumBits(bits)));
                    storage.insertSyntheticBefore(operands, fillRef, MicroInstrOpcode::LoadMemImm, storeOps);
                }
                storage.erase(fillRef);
            }

            context.passChanged = true;
            return Result::Continue;
        }
    }

    for (auto& [offset, slot] : slots)
    {
        if (slot.accesses.empty() || !slot.hasWrite || slot.stackPointerAccess)
            continue;

        // A slot inside an escaped variable can be written behind the scalar
        // analysis's back through the escaped pointer. When an escape landed
        // outside every known variable, the whole unknown part of the frame is
        // reachable through it and only slots inside known variables remain
        // promotable.
        // All accesses have this offset. Both rejection predicates are monotonic
        // in the computed endpoint, so the largest one covers every access.
        if (overlapsPoisonedVariable(offset, slot.maxAccessEnd) || (unknownSpaceEscaped && !insideKnownVariable(offset, slot.maxAccessEnd)))
            continue;

        MicroOpBits bits = slot.accesses[0].bits;
        for (const SlotAccess& acc : slot.accesses)
        {
            if (getNumBits(acc.bits) > getNumBits(bits))
                bits = acc.bits;
        }

        bool consistent = isPromotableBits(bits);
        for (const SlotAccess& acc : slot.accesses)
        {
            if (!consistent)
                break;
            if (acc.bits == bits)
                continue;

            // One width disagreement is allowed, because it has a register form: reading the
            // low half of a vector into an integer register, which is what a lane-zero read
            // compiles to. Promoted, the pair becomes one move out of the vector register
            // instead of a sixteen-byte store followed by a narrower load of the same slot.
            // A narrower WRITE has no such form - it would have to preserve the rest of the
            // register - so it still disqualifies the slot.
            if (bits != MicroOpBits::B128 || acc.isWrite ||
                (acc.bits != MicroOpBits::B32 && acc.bits != MicroOpBits::B64))
            {
                consistent = false;
                break;
            }

            const MicroInstr*        narrowInst = storage.ptr(acc.ref);
            const MicroInstrOperand* narrowOps  = narrowInst ? narrowInst->ops(operands) : nullptr;
            if (!narrowInst || !narrowOps ||
                narrowInst->op != MicroInstrOpcode::LoadRegMem ||
                !narrowOps[0].reg.isAnyInt())
                consistent = false;
        }
        if (!consistent)
            continue;

        // Determine the slot's register class from its reg-valued accesses.
        // The operating forms (memory-operand ALU, compare, widening load,
        // vector) name the class outright and must agree. A plain load or
        // store may disagree with it: the front-end copies a scalar into a
        // local through an integer register whatever its type, so a float
        // local read as a float is written from an integer register - and a
        // scalar register copy across the classes is one `movq`, which is what
        // promotion turns the disagreeing access into. When only plain
        // accesses reach the slot, the readers name the class, so the single
        // cross-class move lands on the write, off the consumers' path.
        bool     ok               = true;
        bool     operatingKnown   = false;
        bool     operatingFloat   = false;
        uint32_t plainReadsInt    = 0;
        uint32_t plainReadsFloat  = 0;
        uint32_t plainWritesInt   = 0;
        uint32_t plainWritesFloat = 0;
        for (const SlotAccess& acc : slot.accesses)
        {
            // A narrow read of a vector slot lands in an integer register; the slot itself is
            // still a vector, so it is the full-width accesses that name the class.
            if (acc.bits != bits)
                continue;

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

            const bool plainScalar = (inst->op == MicroInstrOpcode::LoadRegMem || inst->op == MicroInstrOpcode::LoadMemReg) && bits != MicroOpBits::B128;
            if (plainScalar)
            {
                uint32_t& counter = acc.isWrite ? (regFloat ? plainWritesFloat : plainWritesInt) : (regFloat ? plainReadsFloat : plainReadsInt);
                ++counter;
                continue;
            }
            if (!operatingKnown)
            {
                operatingKnown = true;
                operatingFloat = regFloat;
            }
            else if (operatingFloat != regFloat)
            {
                ok = false; // mixed int/float view of the same slot
                break;
            }
        }
        if (!ok)
            continue;

        bool isFloat = false;
        if (operatingKnown)
            isFloat = operatingFloat;
        else if (plainReadsInt || plainReadsFloat)
            isFloat = plainReadsFloat >= plainReadsInt;
        else if (plainWritesInt || plainWritesFloat)
            isFloat = plainWritesFloat >= plainWritesInt;
        else
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
            // All accesses at this key share their start. The largest end
            // answers whether any of them overlaps, including rejected slots.
            if (!(otherSlot.maxAccessEnd <= pStart || pEnd <= otherOffset))
            {
                overlap = true;
                break;
            }
        }
        if (!overlap)
            filtered.push_back(p);
    }
    promotions = std::move(filtered);

    // ---- A word-sized object written once and read field by field. ----
    // A small aggregate passed by value arrives in one register and is spilled
    // to its home at entry, then its fields are read at their own widths, so no
    // single-width promotion applies. LLVM splits such an object into its fields
    // (SROA) and reads each as a shift and a truncation of the incoming value.
    // The same happens here: the store becomes a register copy, each field
    // offset gets one shifted copy right after it, and every read takes its
    // field from there. The store must sit on the entry straight line, so it
    // dominates every read, and nothing else may write the word.
    struct FieldSplit
    {
        uint64_t                offset   = 0;
        MicroInstrRef           writeRef = MicroInstrRef::invalid();
        SmallVector<SlotAccess> reads;
    };
    SmallVector<FieldSplit> splits;
    // A split needs a word store and a narrower field reader. Without both,
    // no candidate can use instruction ordinals or the entry boundary.
    if (hasFieldSplitWrite && hasNarrowFieldRead)
    {
        std::unordered_map<uint32_t, uint32_t> position;
        uint32_t                               entryEnd = std::numeric_limits<uint32_t>::max();
        uint32_t                               index    = 0;
        for (auto it = storage.view().begin(), endIt = storage.view().end(); it != endIt; ++it, ++index)
        {
            position[it.current.get()] = index;
            const MicroInstrDef& info  = MicroInstr::info(it->op);
            if (entryEnd == std::numeric_limits<uint32_t>::max() &&
                (it->op == MicroInstrOpcode::Label || info.flags.has(MicroInstrFlagsE::JumpInstruction) ||
                 info.flags.has(MicroInstrFlagsE::IsCallInstruction) || info.flags.has(MicroInstrFlagsE::TerminatorInstruction)))
                entryEnd = index;
        }

        for (const auto& [offset, slot] : slots)
        {
            if (slot.stackPointerAccess)
                continue;

            const SlotAccess* write  = nullptr;
            bool              usable = true;
            for (const SlotAccess& acc : slot.accesses)
            {
                if (!acc.isWrite)
                    continue;
                usable = write == nullptr;
                write  = &acc;
            }
            if (!usable || !write || write->bits != MicroOpBits::B64)
                continue;
            const MicroInstr* writeInst = storage.ptr(write->ref);
            if (!writeInst || writeInst->op != MicroInstrOpcode::LoadMemReg || !writeInst->ops(operands)[1].reg.isAnyInt())
                continue;
            const uint32_t writePos = position[write->ref.get()];
            const uint64_t end      = offset + 8;
            if (writePos >= entryEnd || overlapsPoisonedVariable(offset, end) || (unknownSpaceEscaped && !insideKnownVariable(offset, end)))
                continue;

            FieldSplit split;
            split.offset   = offset;
            split.writeRef = write->ref;
            bool narrow    = false;
            for (const auto& [other, otherSlot] : slots)
            {
                if (otherSlot.maxAccessEnd <= offset || other >= end)
                    continue;
                if (other < offset || otherSlot.maxAccessEnd > end || (other != offset && otherSlot.hasWrite) || otherSlot.stackPointerAccess)
                {
                    usable = false;
                    break;
                }
                for (const SlotAccess& acc : otherSlot.accesses)
                {
                    if (acc.ref == write->ref)
                        continue;
                    const MicroInstr* read = storage.ptr(acc.ref);
                    if (acc.isWrite || !read || !isFieldReadOp(read->op) || position[acc.ref.get()] <= writePos)
                    {
                        usable = false;
                        break;
                    }
                    // A float field is moved out of the word by movd, or movq
                    // for a double filling it.
                    const MicroReg valueReg = slotValueRegister(read->op, read->ops(operands));
                    if (valueReg.isValid() && !valueReg.isAnyInt() &&
                        !(valueReg.isVirtualFloat() && (acc.bits == MicroOpBits::B32 || (acc.bits == MicroOpBits::B64 && other == offset))))
                    {
                        usable = false;
                        break;
                    }
                    narrow |= other != offset || acc.bits != MicroOpBits::B64;
                    split.reads.push_back(acc);
                }
                if (!usable)
                    break;
            }

            // A word read whole is the plain promotion's; the shifted copies go
            // right after the store, where the flags must be dead.
            if (!usable || !narrow || !MicroPassHelpers::areCpuFlagsDeadAfter(storage, operands, write->ref, context.builder))
                continue;
            splits.push_back(std::move(split));
        }
    }

    // ---- A vector written once and read lane by lane. ----
    // `v[k]` of a local vector spills the vector and reads the lane back: a
    // 16-byte store, then narrower loads at +4, +8 or +12, which overlap the
    // vector slot and keep every access in memory. When the store is the only
    // write and every read follows it on the same straight line, the store
    // becomes a copy into a vector register and each lane comes out with a
    // shuffle that brings it to lane zero and one move to an integer register,
    // which is how LLVM extracts a lane without SSE4.1.
    struct LaneSplit
    {
        uint64_t                offset   = 0;
        MicroInstrRef           writeRef = MicroInstrRef::invalid();
        SmallVector<SlotAccess> reads;
    };
    SmallVector<LaneSplit> laneSplits;
    if (hasVectorWrite)
    {
        // Instruction ordinals, and the number of block breaks before each, so a
        // read on the write's straight line is one with the same break count.
        // Built on the first slot that has the shape, since most functions with a
        // vector store have none.
        std::unordered_map<uint32_t, uint32_t> ordinal;
        std::unordered_map<uint32_t, uint32_t> breaksBefore;
        bool                                   ordinalsReady = false;
        const auto                             ensureOrdinals = [&] {
            if (ordinalsReady)
                return;
            ordinalsReady   = true;
            uint32_t index  = 0;
            uint32_t breaks = 0;
            for (auto it = storage.view().begin(), endIt = storage.view().end(); it != endIt; ++it, ++index)
            {
                const MicroInstrDef& info = MicroInstr::info(it->op);
                if (it->op == MicroInstrOpcode::Label)
                    ++breaks;
                ordinal[it.current.get()]      = index;
                breaksBefore[it.current.get()] = breaks;
                if (info.flags.has(MicroInstrFlagsE::JumpInstruction) || info.flags.has(MicroInstrFlagsE::IsCallInstruction) ||
                    info.flags.has(MicroInstrFlagsE::TerminatorInstruction))
                    ++breaks;
            }
        };

        for (const auto& [offset, slot] : slots)
        {
            if (slot.stackPointerAccess)
                continue;

            const SlotAccess* write  = nullptr;
            bool              usable = true;
            for (const SlotAccess& acc : slot.accesses)
            {
                if (!acc.isWrite)
                    continue;
                usable = write == nullptr;
                write  = &acc;
            }
            if (!usable || !write || write->bits != MicroOpBits::B128)
                continue;
            const MicroInstr* writeInst = storage.ptr(write->ref);
            if (!writeInst || (writeInst->op != MicroInstrOpcode::LoadMemReg && writeInst->op != MicroInstrOpcode::StoreVecMemReg) ||
                !writeInst->ops(operands)[1].reg.isVirtualFloat())
                continue;
            const uint64_t end = offset + 16;
            if (overlapsPoisonedVariable(offset, end) || (unknownSpaceEscaped && !insideKnownVariable(offset, end)))
                continue;

            // Only a vector some narrower read overlaps is a candidate.
            bool narrowRead = false;
            for (const auto& [other, otherSlot] : slots)
                narrowRead = narrowRead || (other > offset && other < end);
            if (!narrowRead)
                continue;

            ensureOrdinals();
            const uint32_t writeOrdinal = ordinal[write->ref.get()];
            const uint32_t writeBreaks  = breaksBefore[write->ref.get()];
            LaneSplit      split;
            split.offset   = offset;
            split.writeRef = write->ref;
            bool beyondLaneZero = false;
            for (const auto& [other, otherSlot] : slots)
            {
                if (otherSlot.maxAccessEnd <= offset || other >= end)
                    continue;
                if (other < offset || otherSlot.maxAccessEnd > end || (other != offset && otherSlot.hasWrite) || otherSlot.stackPointerAccess)
                {
                    usable = false;
                    break;
                }
                for (const SlotAccess& acc : otherSlot.accesses)
                {
                    if (acc.ref == write->ref)
                        continue;
                    const MicroInstr* read     = storage.ptr(acc.ref);
                    const uint64_t    at       = other - offset;
                    const bool        laneRead = (acc.bits == MicroOpBits::B32 && at % 4 == 0) || (acc.bits == MicroOpBits::B64 && at % 8 == 0);
                    if (acc.isWrite || !read || !isFieldReadOp(read->op) || !laneRead || ordinal[acc.ref.get()] <= writeOrdinal ||
                        breaksBefore[acc.ref.get()] != writeBreaks)
                    {
                        usable = false;
                        break;
                    }
                    const MicroReg valueReg = slotValueRegister(read->op, read->ops(operands));
                    if (valueReg.isValid() && !valueReg.isAnyInt())
                    {
                        usable = false;
                        break;
                    }
                    beyondLaneZero |= at != 0;
                    split.reads.push_back(acc);
                }
                if (!usable)
                    break;
            }

            if (usable && beyondLaneZero)
                laneSplits.push_back(std::move(split));
        }
    }

    // ---- A word-sized record written field by field and read back whole. ----
    // A small aggregate returned or passed in one register is assembled in its
    // frame home: a default for the whole word, then one store per field,
    // then a load of the word - on every path that returns it. The load waits
    // on narrow stores it cannot forward from, and the stores and the load are
    // memory traffic LLVM never emits: SROA keeps such a record in one integer
    // and inserts each field with a shift and an or. The same happens here: a
    // whole store sets the word register, a field store clears the field's
    // bits and ors the shifted field in, and every read takes the word or its
    // shifted field. The clear is skipped where a forward pass over the graph
    // proves the field's bytes still zero, as they are after the declaration's
    // default, so a field costs its shift and its or. Every read and every
    // field store must find the whole word defined on every path.
    struct RecordWord
    {
        uint64_t                offset = 0;
        uint32_t                bytes  = 0;
        SmallVector<SlotAccess> accesses;
    };
    SmallVector<RecordWord> records;
    {
        // Bytes another rewrite of this round already owns.
        const auto claimed = [&](const uint64_t lo, const uint64_t hi) {
            for (const Promotion& p : promotions)
            {
                if (lo < p.offset + getNumBytes(p.bits) && p.offset < hi)
                    return true;
            }
            for (const FieldSplit& split : splits)
            {
                if (lo < split.offset + 8 && split.offset < hi)
                    return true;
            }
            for (const LaneSplit& split : laneSplits)
            {
                if (lo < split.offset + 16 && split.offset < hi)
                    return true;
            }
            return false;
        };

        for (const auto& [offset, slot] : slots)
        {
            if (slot.stackPointerAccess)
                continue;

            // The word is the widest integer read at the slot's own offset.
            uint32_t wordBytes = 0;
            for (const SlotAccess& acc : slot.accesses)
            {
                const MicroInstr* inst = storage.ptr(acc.ref);
                if (!acc.isWrite && inst && inst->op == MicroInstrOpcode::LoadRegMem && inst->ops(operands)[0].reg.isVirtualInt() &&
                    (acc.bits == MicroOpBits::B32 || acc.bits == MicroOpBits::B64))
                    wordBytes = std::max(wordBytes, getNumBytes(acc.bits));
            }
            if (!wordBytes)
                continue;
            const uint64_t end = offset + wordBytes;
            if (claimed(offset, end) || overlapsPoisonedVariable(offset, end) || (unknownSpaceEscaped && !insideKnownVariable(offset, end)))
                continue;

            RecordWord record;
            record.offset = offset;
            record.bytes  = wordBytes;
            bool usable   = true;
            bool narrow   = false;
            for (const auto& [other, otherSlot] : slots)
            {
                if (otherSlot.maxAccessEnd <= offset || other >= end)
                    continue;
                if (other < offset || otherSlot.maxAccessEnd > end || otherSlot.stackPointerAccess)
                {
                    usable = false;
                    break;
                }
                for (const SlotAccess& acc : otherSlot.accesses)
                {
                    const MicroInstr* inst = storage.ptr(acc.ref);
                    if (!inst)
                    {
                        usable = false;
                        break;
                    }
                    const MicroReg valueReg = slotValueRegister(inst->op, inst->ops(operands));
                    const bool     store    = inst->op == MicroInstrOpcode::LoadMemImm || inst->op == MicroInstrOpcode::LoadMemReg;
                    const bool     read     = !acc.isWrite && isFieldReadOp(inst->op);
                    if ((!store && !read) || (valueReg.isValid() && !valueReg.isVirtualInt()))
                    {
                        usable = false;
                        break;
                    }
                    narrow |= other != offset || getNumBytes(acc.bits) != wordBytes;
                    record.accesses.push_back(acc);
                }
                if (!usable)
                    break;
            }
            if (usable && narrow)
                records.push_back(std::move(record));
        }

        // Two words over the same bytes - a narrower one read inside a wider
        // one - are neither a record.
        SmallVector<RecordWord> disjoint;
        for (size_t i = 0; i < records.size(); ++i)
        {
            bool overlap = false;
            for (size_t j = 0; j < records.size() && !overlap; ++j)
                overlap = i != j && records[i].offset < records[j].offset + records[j].bytes && records[j].offset < records[i].offset + records[i].bytes;
            if (!overlap)
                disjoint.push_back(std::move(records[i]));
        }
        records = std::move(disjoint);
    }

    // Per record, the word's defined and known-zero bytes where each access
    // runs, from a forward pass over the instruction graph.
    struct RecordState
    {
        uint8_t defined = 0;
        uint8_t zero    = 0;
    };
    std::unordered_map<uint32_t, RecordState> recordStateAt;
    if (!records.empty())
    {
        const MicroControlFlowGraph& cfg = context.builder->controlFlowGraph();
        const uint32_t               n   = cfg.instructionCount();
        const auto                   refs = cfg.instructionRefs();
        const uint32_t               entry = MicroPassHelpers::findSingleCfgEntry(cfg);

        SmallVector<RecordWord> kept;
        for (RecordWord& record : records)
        {
            const uint8_t all = static_cast<uint8_t>((1u << record.bytes) - 1);
            std::unordered_map<uint32_t, const SlotAccess*> accessAt;
            for (const SlotAccess& acc : record.accesses)
                accessAt[acc.ref.get()] = &acc;

            // The state after an instruction, from the state before it.
            const auto transfer = [&](const uint32_t index, RecordState state) {
                const auto found = accessAt.find(refs[index].get());
                if (found == accessAt.end() || !found->second->isWrite)
                    return state;
                const SlotAccess&        acc   = *found->second;
                const MicroInstr*        inst  = storage.ptr(acc.ref);
                const MicroInstrOperand* iops  = inst->ops(operands);
                const uint32_t           rel   = static_cast<uint32_t>(acc.offset - record.offset);
                const uint32_t           count = getNumBytes(acc.bits);
                const uint8_t            mask  = static_cast<uint8_t>(((1u << count) - 1) << rel);
                state.defined |= mask;
                state.zero &= static_cast<uint8_t>(~mask);
                if (inst->op == MicroInstrOpcode::LoadMemImm)
                {
                    const uint64_t value = iops[3].valueU64;
                    for (uint32_t b = 0; b < count; ++b)
                    {
                        if (((value >> (b * 8)) & 0xFF) == 0)
                            state.zero |= static_cast<uint8_t>(1u << (rel + b));
                    }
                }
                return state;
            };

            // Unreached instructions keep the optimistic state; the entry
            // starts with nothing defined.
            std::vector<RecordState> in(n, RecordState{all, all});
            std::vector<uint8_t>     reached(n, 0);
            bool                     valid = entry != MicroPassHelpers::MicroDomTree::K_INVALID_NODE && !cfg.hasUnsupportedControlFlowForCfgLiveness();
            if (valid)
            {
                in[entry]      = RecordState{};
                reached[entry] = 1;
                bool changed   = true;
                for (uint32_t sweep = 0; changed && sweep < 64; ++sweep)
                {
                    changed = false;
                    for (uint32_t index = 0; index < n; ++index)
                    {
                        if (!reached[index])
                            continue;
                        const RecordState out = transfer(index, in[index]);
                        for (const uint32_t succ : cfg.successors(index))
                        {
                            const RecordState merged{
                                .defined = static_cast<uint8_t>(reached[succ] ? in[succ].defined & out.defined : out.defined),
                                .zero    = static_cast<uint8_t>(reached[succ] ? in[succ].zero & out.zero : out.zero),
                            };
                            if (!reached[succ] || merged.defined != in[succ].defined || merged.zero != in[succ].zero)
                            {
                                reached[succ] = 1;
                                in[succ]      = merged;
                                changed       = true;
                            }
                        }
                    }
                }
                valid = !changed;
            }

            // A field store and a read need the whole word; a whole store
            // needs nothing.
            for (const SlotAccess& acc : record.accesses)
            {
                if (!valid)
                    break;
                const uint32_t index = cfg.indexOf(acc.ref);
                if (index == MicroControlFlowGraph::K_NO_INDEX || !reached[index])
                {
                    valid = false;
                    break;
                }
                const bool wholeStore = acc.isWrite && acc.offset == record.offset && getNumBytes(acc.bits) == record.bytes;
                if (!wholeStore && in[index].defined != all)
                    valid = false;
                // The field's clear, shift and or write the flags.
                const bool rewritesFlags = acc.isWrite ? !wholeStore : acc.offset != record.offset;
                if (rewritesFlags && !MicroPassHelpers::areCpuFlagsDeadAfter(storage, operands, acc.ref, context.builder))
                    valid = false;
                recordStateAt[acc.ref.get()] = in[index];
            }
            if (valid)
                kept.push_back(std::move(record));
        }
        records = std::move(kept);
    }

    if (promotions.empty() && splits.empty() && laneSplits.empty() && records.empty())
        return erasedDeadStores ? finish() : Result::Continue;

    // Loop-carried slots (values live across a back-edge) are promoted too: the
    // register allocator gives every non-pinned loop-carried virtual register a
    // stable spill-slot home and writes it back at each control-flow boundary, so
    // a promoted accumulator round-trips through one consistent location across
    // the back-edge instead of corrupting silently. See
    // MicroRegisterAllocationPass::preallocateLoopCarriedSlots and the
    // loop-carried store in flushAllMappedVirtuals.

    // ---- Allocate a fresh virtual register per promoted offset (int or float). ----
    uint32_t nextVirtualIntRegIndex   = std::max<uint32_t>(1, context.builder->nextVirtualIntRegIndexHint());
    uint32_t nextVirtualFloatRegIndex = 1;
    for (const MicroInstr& inst : storage.view())
    {
        const MicroInstrOperand* ops = inst.ops(operands);
        if (!ops)
            continue;
        const auto modes = MicroInstr::info(inst.op).resolvedRegModes(ops);
        for (size_t i = 0; i < modes.size(); ++i)
        {
            if (modes[i] == MicroInstrRegMode::None)
                continue;
            const MicroReg reg = ops[i].reg;
            if (!reg.isValid() || reg.isNoBase() || reg.index() >= MicroReg::K_MAX_INDEX)
                continue;
            if (reg.isVirtualInt())
                nextVirtualIntRegIndex = std::max(nextVirtualIntRegIndex, reg.index() + 1);
            else if (reg.isVirtualFloat())
                nextVirtualFloatRegIndex = std::max(nextVirtualFloatRegIndex, reg.index() + 1);
        }
    }

    // ---- Rewrite all accesses of the promoted slots to register ops. ----
    for (const Promotion& p : promotions)
    {
        const MicroReg vreg = p.isFloat ? MicroReg::virtualFloatReg(nextVirtualFloatRegIndex++)
                                        : MicroReg::virtualIntReg(nextVirtualIntRegIndex++);

        for (const SlotAccess& acc : slots[p.offset].accesses)
            rewriteSlotAccess(storage, operands, acc, vreg);
    }

    // ---- Split the word-sized objects read field by field. ----
    for (const FieldSplit& split : splits)
    {
        const MicroReg word = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);

        // The store becomes the copy of the incoming word.
        MicroInstr*        writeInst = storage.ptr(split.writeRef);
        MicroInstrOperand* writeOps  = writeInst->ops(operands);
        const MicroReg     source    = writeOps[1].reg;
        writeOps[0].reg              = word;
        writeOps[1].reg              = source;
        writeOps[2].opBits           = MicroOpBits::B64;
        writeInst->op                = MicroInstrOpcode::LoadRegReg;
        writeInst->numOperands       = 3;

        const MicroInstrRef                    afterWrite = storage.findNextInstructionRef(split.writeRef);
        std::unordered_map<uint64_t, MicroReg> fields;
        std::unordered_map<uint64_t, MicroReg> floatFields;
        fields[0] = word;
        // Low fields first: the word's last reader is then the copy that
        // shifts it, which the allocator can make the word itself.
        SmallVector<SlotAccess> reads = split.reads;
        std::ranges::stable_sort(reads, [](const SlotAccess& a, const SlotAccess& b) { return a.offset < b.offset; });
        for (const SlotAccess& acc : reads)
        {
            const uint64_t shift = (acc.offset - split.offset) * 8;
            auto           found = fields.find(shift);
            if (found == fields.end())
            {
                const MicroReg    field = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);
                MicroInstrOperand copyOps[3];
                copyOps[0].reg    = field;
                copyOps[1].reg    = word;
                copyOps[2].opBits = MicroOpBits::B64;
                storage.insertDerivedBefore(operands, afterWrite, MicroInstrOpcode::LoadRegReg, copyOps);
                MicroInstrOperand shiftOps[4];
                shiftOps[0].reg     = field;
                shiftOps[1].opBits  = MicroOpBits::B64;
                shiftOps[2].microOp = MicroOp::ShiftRight;
                shiftOps[3].setImmediateValue(ApInt(shift, 64));
                storage.insertDerivedBefore(operands, afterWrite, MicroInstrOpcode::OpBinaryRegImm, shiftOps);
                found = fields.emplace(shift, field).first;
            }

            const MicroInstr* read     = storage.ptr(acc.ref);
            const MicroReg    valueReg = read ? slotValueRegister(read->op, read->ops(operands)) : MicroReg::invalid();
            if (!valueReg.isVirtualFloat())
            {
                rewriteSlotAccess(storage, operands, acc, found->second);
                continue;
            }

            const uint64_t floatKey = shift * 2 + (acc.bits == MicroOpBits::B64 ? 1 : 0);
            auto           floatIt  = floatFields.find(floatKey);
            if (floatIt == floatFields.end())
            {
                const MicroReg    floatField = MicroReg::virtualFloatReg(nextVirtualFloatRegIndex++);
                MicroInstrOperand moveOps[3];
                moveOps[0].reg    = floatField;
                moveOps[1].reg    = found->second;
                moveOps[2].opBits = acc.bits;
                storage.insertDerivedBefore(operands, afterWrite, MicroInstrOpcode::LoadRegReg, moveOps);
                floatIt = floatFields.emplace(floatKey, floatField).first;
            }
            rewriteSlotAccess(storage, operands, acc, floatIt->second);
        }
    }

    // ---- Split the vectors read lane by lane. ----
    for (const LaneSplit& split : laneSplits)
    {
        const MicroReg vector = MicroReg::virtualFloatReg(nextVirtualFloatRegIndex++);

        // The store becomes the copy of the stored vector.
        MicroInstr*        writeInst = storage.ptr(split.writeRef);
        MicroInstrOperand* writeOps  = writeInst->ops(operands);
        const MicroReg     source    = writeOps[1].reg;
        writeOps[0].reg              = vector;
        writeOps[1].reg              = source;
        writeOps[2].opBits           = MicroOpBits::B128;
        writeInst->op                = MicroInstrOpcode::LoadRegReg;
        writeInst->numOperands       = 3;

        const MicroInstrRef                    afterWrite = storage.findNextInstructionRef(split.writeRef);
        std::unordered_map<uint64_t, MicroReg> lanes;
        for (const SlotAccess& acc : split.reads)
        {
            const uint64_t at  = acc.offset - split.offset;
            const uint64_t key = at * 2 + (acc.bits == MicroOpBits::B64 ? 1 : 0);
            auto           found = lanes.find(key);
            if (found == lanes.end())
            {
                MicroReg laneSource = vector;
                if (at != 0)
                {
                    // Lane `at / 4` of the dwords, or the high quadword, down to lane zero.
                    laneSource = MicroReg::virtualFloatReg(nextVirtualFloatRegIndex++);
                    MicroInstrOperand shuffleOps[4];
                    shuffleOps[0].reg      = laneSource;
                    shuffleOps[1].reg      = vector;
                    shuffleOps[2].opBits   = MicroOpBits::B128;
                    shuffleOps[3].valueU64 = acc.bits == MicroOpBits::B64 ? 0xEE : at / 4;
                    storage.insertDerivedBefore(operands, afterWrite, MicroInstrOpcode::VecShuffleRegRegImm, shuffleOps);
                }

                const MicroReg    lane = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);
                MicroInstrOperand moveOps[3];
                moveOps[0].reg    = lane;
                moveOps[1].reg    = laneSource;
                moveOps[2].opBits = acc.bits;
                storage.insertDerivedBefore(operands, afterWrite, MicroInstrOpcode::LoadRegReg, moveOps);
                found = lanes.emplace(key, lane).first;
            }

            rewriteSlotAccess(storage, operands, acc, found->second);
        }
    }

    // ---- Assemble the records in their word register. ----
    for (const RecordWord& record : records)
    {
        const MicroReg    word     = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);
        const MicroOpBits wordBits = record.bytes == 8 ? MicroOpBits::B64 : MicroOpBits::B32;
        const uint64_t    wordMask = record.bytes == 8 ? ~0ull : 0xFFFFFFFFull;

        const auto insertBinaryImm = [&](const MicroInstrRef before, const MicroOp op, const uint64_t value) {
            MicroInstrOperand binOps[4];
            binOps[0].reg     = word;
            binOps[1].opBits  = wordBits;
            binOps[2].microOp = op;
            binOps[3].setImmediateValue(ApInt(value & wordMask, getNumBits(wordBits)));
            storage.insertDerivedBefore(operands, before, MicroInstrOpcode::OpBinaryRegImm, binOps);
        };

        for (const SlotAccess& acc : record.accesses)
        {
            // Read before anything is inserted: an insertion can move the
            // instruction and its operands.
            const MicroInstr*        inst     = storage.ptr(acc.ref);
            const MicroInstrOperand* iops     = inst->ops(operands);
            const bool               storeImm = inst->op == MicroInstrOpcode::LoadMemImm;
            const uint64_t           imm      = storeImm ? iops[3].valueU64 : 0;
            const MicroReg           src      = acc.isWrite && !storeImm ? iops[1].reg : MicroReg::invalid();
            const uint32_t           rel      = static_cast<uint32_t>(acc.offset - record.offset);
            const uint32_t           count    = getNumBytes(acc.bits);
            const uint32_t           shift    = rel * 8;

            if (!acc.isWrite)
            {
                // The word itself, or its field brought down to the low bits.
                if (!rel)
                {
                    rewriteSlotAccess(storage, operands, acc, word);
                    continue;
                }
                const MicroReg    field = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);
                MicroInstrOperand copyOps[3];
                copyOps[0].reg    = field;
                copyOps[1].reg    = word;
                copyOps[2].opBits = wordBits;
                storage.insertDerivedBefore(operands, acc.ref, MicroInstrOpcode::LoadRegReg, copyOps);
                MicroInstrOperand shiftOps[4];
                shiftOps[0].reg     = field;
                shiftOps[1].opBits  = wordBits;
                shiftOps[2].microOp = MicroOp::ShiftRight;
                shiftOps[3].setImmediateValue(ApInt(shift, getNumBits(wordBits)));
                storage.insertDerivedBefore(operands, acc.ref, MicroInstrOpcode::OpBinaryRegImm, shiftOps);
                rewriteSlotAccess(storage, operands, acc, field);
                continue;
            }

            // A store of the whole word sets the register.
            if (!rel && count == record.bytes)
            {
                rewriteSlotAccess(storage, operands, acc, word);
                continue;
            }

            // A field store: clear the field unless it is known zero, then or
            // the value in.
            // Over a word known to be zero, the field is the whole word.
            const uint64_t    fieldMask = (count == 8 ? ~0ull : (1ull << (count * 8)) - 1) << shift;
            const RecordState state     = recordStateAt[acc.ref.get()];
            const uint8_t     byteMask  = static_cast<uint8_t>(((1u << count) - 1) << rel);
            const bool        wordZero  = state.zero == static_cast<uint8_t>((1u << record.bytes) - 1);
            if ((state.zero & byteMask) != byteMask)
                insertBinaryImm(acc.ref, MicroOp::And, ~fieldMask);

            if (storeImm)
            {
                const uint64_t value = (imm << shift) & fieldMask;
                if (value && wordZero)
                {
                    MicroInstrOperand loadOps[3];
                    loadOps[0].reg    = word;
                    loadOps[1].opBits = wordBits;
                    loadOps[2].setImmediateValue(ApInt(value, getNumBits(wordBits)));
                    storage.insertDerivedBefore(operands, acc.ref, MicroInstrOpcode::LoadRegImm, loadOps);
                }
                else if (value)
                    insertBinaryImm(acc.ref, MicroOp::Or, value);
            }
            else
            {
                const MicroReg    part = MicroReg::virtualIntReg(nextVirtualIntRegIndex++);
                MicroInstrOperand extendOps[4];
                extendOps[0].reg    = part;
                extendOps[1].reg    = src;
                extendOps[2].opBits = wordBits;
                extendOps[3].opBits = acc.bits;
                if (count == 4)
                {
                    // A 32-bit copy clears the upper half.
                    extendOps[2].opBits = MicroOpBits::B32;
                    storage.insertDerivedBefore(operands, acc.ref, MicroInstrOpcode::LoadRegReg, std::span<const MicroInstrOperand>(extendOps, 3));
                }
                else
                    storage.insertDerivedBefore(operands, acc.ref, MicroInstrOpcode::LoadZeroExtRegReg, extendOps);
                if (shift)
                {
                    MicroInstrOperand shiftOps[4];
                    shiftOps[0].reg     = part;
                    shiftOps[1].opBits  = wordBits;
                    shiftOps[2].microOp = MicroOp::ShiftLeft;
                    shiftOps[3].setImmediateValue(ApInt(shift, getNumBits(wordBits)));
                    storage.insertDerivedBefore(operands, acc.ref, MicroInstrOpcode::OpBinaryRegImm, shiftOps);
                }
                if (wordZero)
                {
                    MicroInstrOperand copyOps[3];
                    copyOps[0].reg    = word;
                    copyOps[1].reg    = part;
                    copyOps[2].opBits = wordBits;
                    storage.insertDerivedBefore(operands, acc.ref, MicroInstrOpcode::LoadRegReg, copyOps);
                }
                else
                {
                    MicroInstrOperand orOps[4];
                    orOps[0].reg     = word;
                    orOps[1].reg     = part;
                    orOps[2].opBits  = wordBits;
                    orOps[3].microOp = MicroOp::Or;
                    storage.insertDerivedBefore(operands, acc.ref, MicroInstrOpcode::OpBinaryRegReg, orOps);
                }
            }
            storage.erase(acc.ref);
        }
    }

    if (context.ssaState)
        context.ssaState->invalidate();
    context.builder->invalidateControlFlowGraph();
    context.passChanged = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
