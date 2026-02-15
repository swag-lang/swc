#include "pch.h"
#include "Backend/MachineCode/Micro/Passes/MicroPersistentRegsPass.h"
#include "Backend/MachineCode/Micro/MicroInstr.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    uint64_t alignUpU64(uint64_t value, uint64_t alignment)
    {
        if (!alignment)
            return value;

        const uint64_t rem = value % alignment;
        if (!rem)
            return value;

        return value + alignment - rem;
    }

    bool containsReg(std::span<const MicroReg> regs, MicroReg reg)
    {
        for (const auto value : regs)
        {
            if (value == reg)
                return true;
        }

        return false;
    }

    Ref insertInstructionBefore(MicroInstrStorage& instructions, MicroOperandStorage& operands, Ref beforeRef, MicroInstrOpcode op, EncodeFlags emitFlags, std::span<const MicroInstrOperand> opsData)
    {
        MicroInstr inst;
        inst.op          = op;
        inst.emitFlags   = emitFlags;
        inst.numOperands = static_cast<uint8_t>(opsData.size());
        if (!opsData.empty())
        {
            auto [opsRef, dstOps] = operands.emplaceUninitArray(inst.numOperands);
            inst.opsRef           = opsRef;
            for (uint32_t i = 0; i < inst.numOperands; ++i)
                dstOps[i] = opsData[i];
        }
        else
        {
            inst.opsRef = INVALID_REF;
        }

        return instructions.insertBefore(beforeRef, inst);
    }
}

void MicroPersistentRegsPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);

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

    Ref firstRef = INVALID_REF;
    std::vector<std::pair<Ref, EncodeFlags>> retRefs;
    for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
    {
        if (firstRef == INVALID_REF)
            firstRef = it.current;

        if (it->op == MicroInstrOpcode::Ret)
            retRefs.emplace_back(it.current, it->emitFlags);
    }

    if (firstRef != INVALID_REF)
        insertSavedRegsPrologue(context, conv, firstRef);

    for (const auto [retRef, emitFlags] : retRefs)
        insertSavedRegsEpilogue(context, conv, retRef, emitFlags);
}

bool MicroPersistentRegsPass::containsSavedSlot(MicroReg reg) const
{
    for (const auto& slot : savedRegSlots_)
    {
        if (slot.reg == reg)
            return true;
    }

    return false;
}

void MicroPersistentRegsPass::buildSavedRegsPlan(const MicroPassContext& context, const CallConv& conv)
{
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);

    savedRegSlots_.clear();
    savedRegsFrameSize_ = 0;

    auto& storeOps = *context.operands;
    for (const auto& inst : context.instructions->view())
    {
        SmallVector<MicroInstrRegOperandRef> refs;
        inst.collectRegOperands(storeOps, refs, context.encoder);
        for (const auto& ref : refs)
        {
            if (!ref.reg)
                continue;

            const MicroReg reg = *ref.reg;
            if (!reg.isValid() || reg.isVirtual())
                continue;

            if (reg.isInt())
            {
                if (!containsReg(conv.intPersistentRegs, reg))
                    continue;

                if (!containsSavedSlot(reg))
                    savedRegSlots_.push_back({.reg = reg, .offset = 0, .slotBits = MicroOpBits::B64});
            }
            else if (reg.isFloat())
            {
                if (!containsReg(conv.floatPersistentRegs, reg))
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
        frameOffset             = alignUpU64(frameOffset, slotSize);
        slot.offset             = frameOffset;
        frameOffset += slotSize;
    }

    const uint64_t stackAlignment = conv.stackAlignment ? conv.stackAlignment : 16;
    savedRegsFrameSize_           = alignUpU64(frameOffset, stackAlignment);
}

void MicroPersistentRegsPass::insertSavedRegsPrologue(const MicroPassContext& context, const CallConv& conv, Ref insertBeforeRef) const
{
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);

    if (!savedRegsFrameSize_)
        return;

    auto& instructions = *context.instructions;
    auto& operands     = *context.operands;

    MicroInstrOperand subOps[4];
    subOps[0].reg      = conv.stackPointer;
    subOps[1].opBits   = MicroOpBits::B64;
    subOps[2].microOp  = MicroOp::Subtract;
    subOps[3].valueU64 = savedRegsFrameSize_;
    insertInstructionBefore(instructions, operands, insertBeforeRef, MicroInstrOpcode::OpBinaryRegImm, EncodeFlagsE::Zero, subOps);

    for (const auto& slot : savedRegSlots_)
    {
        MicroInstrOperand storeOps[4];
        storeOps[0].reg      = conv.stackPointer;
        storeOps[1].reg      = slot.reg;
        storeOps[2].opBits   = slot.slotBits;
        storeOps[3].valueU64 = slot.offset;
        insertInstructionBefore(instructions, operands, insertBeforeRef, MicroInstrOpcode::LoadMemReg, EncodeFlagsE::Zero, storeOps);
    }
}

void MicroPersistentRegsPass::insertSavedRegsEpilogue(const MicroPassContext& context, const CallConv& conv, Ref insertBeforeRef, EncodeFlags emitFlags) const
{
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);

    if (!savedRegsFrameSize_)
        return;

    auto& instructions = *context.instructions;
    auto& operands     = *context.operands;

    for (const auto& slot : savedRegSlots_)
    {
        MicroInstrOperand loadOps[4];
        loadOps[0].reg      = slot.reg;
        loadOps[1].reg      = conv.stackPointer;
        loadOps[2].opBits   = slot.slotBits;
        loadOps[3].valueU64 = slot.offset;
        insertInstructionBefore(instructions, operands, insertBeforeRef, MicroInstrOpcode::LoadRegMem, emitFlags, loadOps);
    }

    MicroInstrOperand addOps[4];
    addOps[0].reg      = conv.stackPointer;
    addOps[1].opBits   = MicroOpBits::B64;
    addOps[2].microOp  = MicroOp::Add;
    addOps[3].valueU64 = savedRegsFrameSize_;
    insertInstructionBefore(instructions, operands, insertBeforeRef, MicroInstrOpcode::OpBinaryRegImm, emitFlags, addOps);
}

SWC_END_NAMESPACE();
