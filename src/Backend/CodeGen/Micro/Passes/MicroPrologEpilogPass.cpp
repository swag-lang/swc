#include "pch.h"
#include "Backend/CodeGen/Micro/Passes/MicroPrologEpilogPass.h"
#include "Backend/CodeGen/Micro/MicroInstr.h"
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

void MicroPrologEpilogPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions);

    if (!context.preservePersistentRegs)
    {
        savedRegSlots_.clear();
        savedRegsFrameSize_ = 0;
        return;
    }

    const auto& conv = CallConv::get(context.callConvKind);
    buildSavedRegsPlan(context, conv);
    if (!savedRegsFrameSize_)
        return;

    Ref                                      firstRef = INVALID_REF;
    std::vector<Ref> retRefs;
    for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
    {
        if (firstRef == INVALID_REF)
            firstRef = it.current;

        if (it->op == MicroInstrOpcode::Ret)
            retRefs.push_back(it.current);
    }

    if (firstRef != INVALID_REF)
        insertSavedRegsPrologue(context, conv, firstRef);

    for (const auto retRef : retRefs)
        insertSavedRegsEpilogue(context, conv, retRef);
}

bool MicroPrologEpilogPass::containsSavedSlot(MicroReg reg) const
{
    for (const auto& slot : savedRegSlots_)
    {
        if (slot.reg == reg)
            return true;
    }

    return false;
}

void MicroPrologEpilogPass::buildSavedRegsPlan(const MicroPassContext& context, const CallConv& conv)
{
    SWC_ASSERT(context.instructions);

    savedRegSlots_.clear();
    savedRegsFrameSize_ = 0;

    auto& storeOps = *SWC_CHECK_NOT_NULL(context.operands);
    for (const auto& inst : context.instructions->view())
    {
        SmallVector<MicroInstrRegOperandRef> refs;
        inst.collectRegOperands(storeOps, refs, context.encoder);
        for (const auto& ref : refs)
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

                if (!containsSavedSlot(reg))
                    savedRegSlots_.push_back({.reg = reg, .offset = 0, .slotBits = MicroOpBits::B64});
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

    if (savedRegSlots_.empty())
        return;

    uint64_t frameOffset = 0;
    for (auto& slot : savedRegSlots_)
    {
        const uint64_t slotSize = slot.slotBits == MicroOpBits::B128 ? 16 : 8;
        frameOffset             = Math::alignUpU64(frameOffset, slotSize);
        slot.offset             = frameOffset;
        frameOffset += slotSize;
    }

    const uint64_t stackAlignment = conv.stackAlignment ? conv.stackAlignment : 16;
    savedRegsFrameSize_           = Math::alignUpU64(frameOffset, stackAlignment);
}

void MicroPrologEpilogPass::insertSavedRegsPrologue(const MicroPassContext& context, const CallConv& conv, Ref insertBeforeRef) const
{
    if (!savedRegsFrameSize_)
        return;

    auto& instructions = *SWC_CHECK_NOT_NULL(context.instructions);
    auto& operands     = *SWC_CHECK_NOT_NULL(context.operands);

    MicroInstrOperand subOps[4];
    subOps[0].reg      = conv.stackPointer;
    subOps[1].opBits   = MicroOpBits::B64;
    subOps[2].microOp  = MicroOp::Subtract;
    subOps[3].valueU64 = savedRegsFrameSize_;
    instructions.insertBefore(operands, insertBeforeRef, MicroInstrOpcode::OpBinaryRegImm, subOps);

    for (const auto& slot : savedRegSlots_)
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
    if (!savedRegsFrameSize_)
        return;

    auto& instructions = *SWC_CHECK_NOT_NULL(context.instructions);
    auto& operands     = *SWC_CHECK_NOT_NULL(context.operands);

    for (const auto& slot : savedRegSlots_)
    {
        MicroInstrOperand loadOps[4];
        loadOps[0].reg      = slot.reg;
        loadOps[1].reg      = conv.stackPointer;
        loadOps[2].opBits   = slot.slotBits;
        loadOps[3].valueU64 = slot.offset;
        instructions.insertBefore(operands, insertBeforeRef, MicroInstrOpcode::LoadRegMem, loadOps);
    }

    MicroInstrOperand addOps[4];
    addOps[0].reg      = conv.stackPointer;
    addOps[1].opBits   = MicroOpBits::B64;
    addOps[2].microOp  = MicroOp::Add;
    addOps[3].valueU64 = savedRegsFrameSize_;
    instructions.insertBefore(operands, insertBeforeRef, MicroInstrOpcode::OpBinaryRegImm, addOps);
}

SWC_END_NAMESPACE();



