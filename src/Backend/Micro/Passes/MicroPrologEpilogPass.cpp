#include "pch.h"
#include "Backend/Micro/Passes/MicroPrologEpilogPass.h"
#include "Backend/Micro/MicroInstr.h"
#include "Support/Math/Helpers.h"

// Inserts ABI-mandated save/restore code around the function body.
// Example: if callee-saved rbx is used, emit push rbx in prolog and pop rbx in epilog.
// Example: reserve stack slots for preserved state when required by calling convention.
// This pass enforces ABI correctness, not optimization.

SWC_BEGIN_NAMESPACE();

bool MicroPrologEpilogPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions);

    // Caller can disable this when generated code does not need ABI-preserved registers.
    if (!context.preservePersistentRegs)
    {
        pushedRegs_.clear();
        savedRegSlots_.clear();
        savedRegsStackSubSize_ = 0;
        return false;
    }

    const CallConv& conv = CallConv::get(context.callConvKind);
    buildSavedRegsPlan(context, conv);
    if (pushedRegs_.empty() && !savedRegsStackSubSize_)
        return false;

    Ref              firstRef = INVALID_REF;
    SmallVector<Ref> retRefs;
    for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
    {
        if (firstRef == INVALID_REF)
            firstRef = it.current;
        if (it->op == MicroInstrOpcode::Ret)
            retRefs.push_back(it.current);
    }

    if (firstRef != INVALID_REF)
        insertSavedRegsPrologue(context, conv, firstRef);
    for (const Ref retRef : retRefs)
        insertSavedRegsEpilogue(context, conv, retRef);

    return firstRef != INVALID_REF;
}

bool MicroPrologEpilogPass::containsSavedSlot(MicroReg reg) const
{
    for (const SavedRegSlot& slot : savedRegSlots_)
    {
        if (slot.reg == reg)
            return true;
    }

    return false;
}

bool MicroPrologEpilogPass::containsPushedReg(MicroReg reg) const
{
    for (const MicroReg pushedReg : pushedRegs_)
    {
        if (pushedReg == reg)
            return true;
    }

    return false;
}

void MicroPrologEpilogPass::buildSavedRegsPlan(const MicroPassContext& context, const CallConv& conv)
{
    SWC_ASSERT(context.instructions);

    pushedRegs_.clear();
    savedRegSlots_.clear();
    savedRegsStackSubSize_ = 0;

    // Scan concrete register operands and collect only ABI-persistent regs that are used.
    auto& storeOps = *SWC_CHECK_NOT_NULL(context.operands);
    for (const auto& inst : context.instructions->view())
    {
        SmallVector<MicroInstrRegOperandRef> refs;
        inst.collectRegOperands(storeOps, refs, context.encoder);
        for (const MicroInstrRegOperandRef& ref : refs)
        {
            if (!ref.reg)
                continue;

            const MicroReg reg = *SWC_CHECK_NOT_NULL(ref.reg);
            if (!reg.isValid() || reg.isVirtual())
                continue;

            if (reg.isInt())
            {
                if (!conv.isIntPersistentReg(reg))
                    continue;

                if (!containsPushedReg(reg))
                    pushedRegs_.push_back(reg);
            }
            else if (reg.isFloat())
            {
                if (!conv.isFloatPersistentReg(reg))
                    continue;

                if (!containsSavedSlot(reg))
                    savedRegSlots_.push_back({.reg = reg, .offset = 0, .slotBits = MicroOpBits::B128});
            }
        }
    }

    if (pushedRegs_.empty() && savedRegSlots_.empty())
        return;

    uint64_t frameOffset = 0;
    for (auto& slot : savedRegSlots_)
    {
        const uint64_t slotSize = slot.slotBits == MicroOpBits::B128 ? 16 : 8;
        frameOffset             = Math::alignUpU64(frameOffset, slotSize);
        slot.offset             = frameOffset;
        frameOffset += slotSize;
    }

    // Final frame size includes push area + spill slots, rounded to ABI stack alignment.
    const uint64_t pushedRegsSize = pushedRegs_.size() * sizeof(uint64_t);
    const uint64_t stackAlignment = conv.stackAlignment ? conv.stackAlignment : 16;
    const uint64_t totalFrameSize = Math::alignUpU64(pushedRegsSize + frameOffset, stackAlignment);
    savedRegsStackSubSize_        = totalFrameSize > pushedRegsSize ? totalFrameSize - pushedRegsSize : 0;
}

void MicroPrologEpilogPass::insertSavedRegsPrologue(const MicroPassContext& context, const CallConv& conv, Ref insertBeforeRef) const
{
    if (pushedRegs_.empty() && !savedRegsStackSubSize_)
        return;

    auto& instructions = *SWC_CHECK_NOT_NULL(context.instructions);
    auto& operands     = *SWC_CHECK_NOT_NULL(context.operands);

    // Integer persistent regs are saved with push/pop.
    for (const MicroReg pushedReg : pushedRegs_)
    {
        MicroInstrOperand pushOps[1];
        pushOps[0].reg = pushedReg;
        instructions.insertBefore(operands, insertBeforeRef, MicroInstrOpcode::Push, pushOps);
    }

    if (savedRegsStackSubSize_)
    {
        MicroInstrOperand subOps[4];
        subOps[0].reg      = conv.stackPointer;
        subOps[1].opBits   = MicroOpBits::B64;
        subOps[2].microOp  = MicroOp::Subtract;
        subOps[3].valueU64 = savedRegsStackSubSize_;
        instructions.insertBefore(operands, insertBeforeRef, MicroInstrOpcode::OpBinaryRegImm, subOps);
    }

    // Float persistent regs use explicit stack slots because there is no push/pop form.
    for (const SavedRegSlot& slot : savedRegSlots_)
    {
        MicroInstrOperand storeOps[4];
        storeOps[0].reg      = conv.stackPointer;
        storeOps[1].reg      = slot.reg;
        storeOps[2].opBits   = slot.slotBits;
        storeOps[3].valueU64 = slot.offset;
        instructions.insertBefore(operands, insertBeforeRef, MicroInstrOpcode::LoadMemReg, storeOps);
    }
}

void MicroPrologEpilogPass::insertSavedRegsEpilogue(const MicroPassContext& context, const CallConv& conv, Ref insertBeforeRef) const
{
    if (pushedRegs_.empty() && !savedRegsStackSubSize_)
        return;

    auto& instructions = *SWC_CHECK_NOT_NULL(context.instructions);
    auto& operands     = *SWC_CHECK_NOT_NULL(context.operands);

    // Restore in reverse: load slot-backed regs, undo stack allocation, then pop integer regs.
    for (const SavedRegSlot& slot : savedRegSlots_)
    {
        MicroInstrOperand loadOps[4];
        loadOps[0].reg      = slot.reg;
        loadOps[1].reg      = conv.stackPointer;
        loadOps[2].opBits   = slot.slotBits;
        loadOps[3].valueU64 = slot.offset;
        instructions.insertBefore(operands, insertBeforeRef, MicroInstrOpcode::LoadRegMem, loadOps);
    }

    if (savedRegsStackSubSize_)
    {
        MicroInstrOperand addOps[4];
        addOps[0].reg      = conv.stackPointer;
        addOps[1].opBits   = MicroOpBits::B64;
        addOps[2].microOp  = MicroOp::Add;
        addOps[3].valueU64 = savedRegsStackSubSize_;
        instructions.insertBefore(operands, insertBeforeRef, MicroInstrOpcode::OpBinaryRegImm, addOps);
    }

    for (const MicroReg pushedReg : std::ranges::reverse_view(pushedRegs_))
    {
        MicroInstrOperand popOps[1];
        popOps[0].reg = pushedReg;
        instructions.insertBefore(operands, insertBeforeRef, MicroInstrOpcode::Pop, popOps);
    }
}

SWC_END_NAMESPACE();
