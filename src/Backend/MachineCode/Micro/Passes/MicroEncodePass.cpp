#include "pch.h"
#include "Backend/MachineCode/Micro/Passes/MicroEncodePass.h"
#include "Backend/MachineCode/Micro/MicroInstr.h"
#include "Support/Core/PagedStoreTyped.h"

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

    size_t resolveJumpIndex(uint64_t valueA)
    {
        if (valueA == 0)
            return 0;
        constexpr uint64_t stride = sizeof(MicroInstr);
        if (valueA % stride == 0)
            return valueA / stride;
        return valueA;
    }

}

void MicroEncodePass::encodeInstruction(const MicroPassContext& context, const MicroInstr& inst, size_t idx)
{
    SWC_ASSERT(context.encoder);
    SWC_ASSERT(context.operands);
    auto&       encoder = *context.encoder;
    const auto* ops     = inst.ops(context.operands->store());
    switch (inst.op)
    {
        case MicroInstrOpcode::End:
            break;

        case MicroInstrOpcode::Ignore:
        case MicroInstrOpcode::Label:
        case MicroInstrOpcode::Debug:
            break;

        case MicroInstrOpcode::Enter:
        case MicroInstrOpcode::Leave:
        case MicroInstrOpcode::LoadCallParam:
        case MicroInstrOpcode::LoadCallAddrParam:
        case MicroInstrOpcode::LoadCallZeroExtParam:
        case MicroInstrOpcode::StoreCallParam:
            SWC_ASSERT(false);
            break;

        case MicroInstrOpcode::SymbolRelocAddr:
            encoder.encodeLoadSymbolRelocAddress(ops[0].reg, ops[1].valueU32, ops[2].valueU32, inst.emitFlags);
            break;
        case MicroInstrOpcode::SymbolRelocValue:
            encoder.encodeLoadSymRelocValue(ops[0].reg, ops[2].valueU32, ops[3].valueU32, ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::Push:
            encoder.encodePush(ops[0].reg, inst.emitFlags);
            break;
        case MicroInstrOpcode::Pop:
            encoder.encodePop(ops[0].reg, inst.emitFlags);
            break;
        case MicroInstrOpcode::Nop:
            encoder.encodeNop(inst.emitFlags);
            break;
        case MicroInstrOpcode::Ret:
            encodeSavedRegsEpilogue(context, CallConv::get(context.callConvKind), inst.emitFlags);
            encoder.encodeRet(inst.emitFlags);
            break;
        case MicroInstrOpcode::CallLocal:
            encoder.encodeCallLocal(ops[0].name, ops[1].callConv, inst.emitFlags);
            break;
        case MicroInstrOpcode::CallExtern:
            encoder.encodeCallExtern(ops[0].name, ops[1].callConv, inst.emitFlags);
            break;
        case MicroInstrOpcode::CallIndirect:
            encoder.encodeCallReg(ops[0].reg, ops[1].callConv, inst.emitFlags);
            break;
        case MicroInstrOpcode::JumpTable:
            encoder.encodeJumpTable(ops[0].reg, ops[1].reg, ops[2].valueI32, ops[3].valueU32, ops[4].valueU32, inst.emitFlags);
            break;
        case MicroInstrOpcode::JumpCond:
        {
            MicroJump jump;
            encoder.encodeJump(jump, ops[0].jumpType, ops[1].opBits, inst.emitFlags);
            jump.valid  = true;
            jumps_[idx] = jump;
            break;
        }
        case MicroInstrOpcode::PatchJump:
        {
            const size_t jumpIndex = resolveJumpIndex(ops[0].valueU64);
            SWC_ASSERT(jumpIndex < jumps_.size());
            SWC_ASSERT(jumps_[jumpIndex].valid);
            if (ops[2].valueU64 == 1)
                encoder.encodePatchJump(jumps_[jumpIndex], ops[1].valueU64, inst.emitFlags);
            else
                encoder.encodePatchJump(jumps_[jumpIndex], inst.emitFlags);
            break;
        }
        case MicroInstrOpcode::JumpCondImm:
        {
            MicroJump  jump;
            const auto opBits = ops[1].opBits == MicroOpBits::Zero ? MicroOpBits::B32 : ops[1].opBits;
            encoder.encodeJump(jump, ops[0].jumpType, opBits, inst.emitFlags);
            encoder.encodePatchJump(jump, ops[2].valueU64, inst.emitFlags);
            break;
        }
        case MicroInstrOpcode::JumpReg:
            encoder.encodeJumpReg(ops[0].reg, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadRegReg:
            encoder.encodeLoadRegReg(ops[0].reg, ops[1].reg, ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadRegImm:
            encoder.encodeLoadRegImm(ops[0].reg, ops[2].valueU64, ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadRegMem:
            encoder.encodeLoadRegMem(ops[0].reg, ops[1].reg, ops[3].valueU64, ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadSignedExtRegMem:
            encoder.encodeLoadSignedExtendRegMem(ops[0].reg, ops[1].reg, ops[4].valueU64, ops[2].opBits, ops[3].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadSignedExtRegReg:
            encoder.encodeLoadSignedExtendRegReg(ops[0].reg, ops[1].reg, ops[2].opBits, ops[3].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadZeroExtRegMem:
            encoder.encodeLoadZeroExtendRegMem(ops[0].reg, ops[1].reg, ops[4].valueU64, ops[2].opBits, ops[3].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadZeroExtRegReg:
            encoder.encodeLoadZeroExtendRegReg(ops[0].reg, ops[1].reg, ops[2].opBits, ops[3].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadAddrRegMem:
            encoder.encodeLoadAddressRegMem(ops[0].reg, ops[1].reg, ops[3].valueU64, ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadAmcMemReg:
            encoder.encodeLoadAmcMemReg(ops[0].reg, ops[1].reg, ops[5].valueU64, ops[6].valueU64, ops[3].opBits, ops[2].reg, ops[4].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadAmcMemImm:
            encoder.encodeLoadAmcMemImm(ops[0].reg, ops[1].reg, ops[5].valueU64, ops[6].valueU64, ops[3].opBits, ops[7].valueU64, ops[4].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadAmcRegMem:
            encoder.encodeLoadAmcRegMem(ops[0].reg, ops[3].opBits, ops[1].reg, ops[2].reg, ops[5].valueU64, ops[6].valueU64, ops[4].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadAddrAmcRegMem:
            encoder.encodeLoadAddressAmcRegMem(ops[0].reg, ops[3].opBits, ops[1].reg, ops[2].reg, ops[5].valueU64, ops[6].valueU64, ops[4].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadMemReg:
            encoder.encodeLoadMemReg(ops[0].reg, ops[3].valueU64, ops[1].reg, ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadMemImm:
            encoder.encodeLoadMemImm(ops[0].reg, ops[2].valueU64, ops[3].valueU64, ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::CmpRegReg:
            encoder.encodeCmpRegReg(ops[0].reg, ops[1].reg, ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::CmpRegImm:
            encoder.encodeCmpRegImm(ops[0].reg, ops[2].valueU64, ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::CmpMemReg:
            encoder.encodeCmpMemReg(ops[0].reg, ops[3].valueU64, ops[1].reg, ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::CmpMemImm:
            encoder.encodeCmpMemImm(ops[0].reg, ops[2].valueU64, ops[3].valueU64, ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::SetCondReg:
            encoder.encodeSetCondReg(ops[0].reg, ops[1].cpuCond, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadCondRegReg:
            encoder.encodeLoadCondRegReg(ops[0].reg, ops[1].reg, ops[2].cpuCond, ops[3].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::ClearReg:
            encoder.encodeClearReg(ops[0].reg, ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpUnaryMem:
            encoder.encodeOpUnaryMem(ops[0].reg, ops[3].valueU64, ops[2].microOp, ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpUnaryReg:
            encoder.encodeOpUnaryReg(ops[0].reg, ops[2].microOp, ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpBinaryRegReg:
            encoder.encodeOpBinaryRegReg(ops[0].reg, ops[1].reg, ops[3].microOp, ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpBinaryMemReg:
            encoder.encodeOpBinaryMemReg(ops[0].reg, ops[4].valueU64, ops[1].reg, ops[3].microOp, ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpBinaryRegImm:
            encoder.encodeOpBinaryRegImm(ops[0].reg, ops[3].valueU64, ops[2].microOp, ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpBinaryMemImm:
            encoder.encodeOpBinaryMemImm(ops[0].reg, ops[3].valueU64, ops[4].valueU64, ops[2].microOp, ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpBinaryRegMem:
            encoder.encodeOpBinaryRegMem(ops[0].reg, ops[1].reg, ops[4].valueU64, ops[3].microOp, ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpTernaryRegRegReg:
            encoder.encodeOpTernaryRegRegReg(ops[0].reg, ops[1].reg, ops[2].reg, ops[4].microOp, ops[3].opBits, inst.emitFlags);
            break;
        default:
            SWC_ASSERT(false);
            break;
    }
}

void MicroEncodePass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.encoder);
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);

    if (context.preservePersistentRegs)
    {
        const auto& conv = CallConv::get(context.callConvKind);
        buildSavedRegsPlan(context, conv);
        encodeSavedRegsPrologue(context, conv);
    }
    else
    {
        savedRegSlots_.clear();
        savedRegsFrameSize_ = 0;
    }

    const uint32_t instructionCount = context.instructions->count();
    jumps_.clear();
    jumps_.resize(instructionCount);

    size_t idx = 0;
    for (const auto& inst : context.instructions->view())
    {
        SWC_ASSERT(idx < instructionCount);
        encodeInstruction(context, inst, idx);
        ++idx;
    }
}

bool MicroEncodePass::containsSavedSlot(MicroReg reg) const
{
    for (const auto& slot : savedRegSlots_)
    {
        if (slot.reg == reg)
            return true;
    }

    return false;
}

void MicroEncodePass::buildSavedRegsPlan(const MicroPassContext& context, const CallConv& conv)
{
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);

    savedRegSlots_.clear();
    savedRegsFrameSize_ = 0;

    auto& storeOps = context.operands->store();
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

void MicroEncodePass::encodeSavedRegsPrologue(const MicroPassContext& context, const CallConv& conv) const
{
    SWC_ASSERT(context.encoder);
    auto& encoder = *context.encoder;

    if (!savedRegsFrameSize_)
        return;

    encoder.encodeOpBinaryRegImm(conv.stackPointer, savedRegsFrameSize_, MicroOp::Subtract, MicroOpBits::B64, EncodeFlagsE::Zero);

    for (const auto& slot : savedRegSlots_)
        encoder.encodeLoadMemReg(conv.stackPointer, slot.offset, slot.reg, slot.slotBits, EncodeFlagsE::Zero);
}

void MicroEncodePass::encodeSavedRegsEpilogue(const MicroPassContext& context, const CallConv& conv, EncodeFlags emitFlags) const
{
    SWC_ASSERT(context.encoder);
    auto& encoder = *context.encoder;

    if (!savedRegsFrameSize_)
        return;

    for (const auto& slot : savedRegSlots_)
        encoder.encodeLoadRegMem(slot.reg, conv.stackPointer, slot.offset, slot.slotBits, emitFlags);

    encoder.encodeOpBinaryRegImm(conv.stackPointer, savedRegsFrameSize_, MicroOp::Add, MicroOpBits::B64, emitFlags);
}

SWC_END_NAMESPACE();
