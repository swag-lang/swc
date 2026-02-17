#include "pch.h"
#include "Backend/CodeGen/Micro/Passes/MicroEmitPass.h"
#include "Backend/CodeGen/Micro/MicroBuilder.h"
#include "Backend/CodeGen/Micro/MicroInstr.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Ref resolveRef(uint64_t value)
    {
        if (value > std::numeric_limits<Ref>::max())
            return INVALID_REF;
        return static_cast<Ref>(value);
    }

    uint64_t resolveJumpDestination(const std::unordered_map<Ref, uint64_t>& labelOffsets, uint64_t labelRefRaw)
    {
        const Ref  labelRef = resolveRef(labelRefRaw);
        const auto it       = labelOffsets.find(labelRef);
        SWC_ASSERT(it != labelOffsets.end());
        return it->second;
    }
}

std::optional<uint32_t> MicroEmitPass::findRelocationIndex(Ref instructionRef) const
{
    const auto found = relocationByInstructionRef_.find(instructionRef);
    if (found == relocationByInstructionRef_.end())
        return std::nullopt;

    return found->second;
}

void MicroEmitPass::bindAbs64RelocationOffset(const MicroPassContext& context, Ref instructionRef, uint32_t codeStartOffset, uint32_t codeEndOffset) const
{
    const auto relocIndex = findRelocationIndex(instructionRef);
    if (!relocIndex.has_value())
        return;

    SWC_ASSERT(codeEndOffset >= codeStartOffset + sizeof(uint64_t));
    MicroRelocation& reloc = context.builder->codeRelocations()[*relocIndex];
    reloc.codeOffset       = codeEndOffset - sizeof(uint64_t);
}

void MicroEmitPass::encodeInstruction(const MicroPassContext& context, Ref instructionRef, const MicroInstr& inst)
{
    SWC_ASSERT(context.encoder);
    SWC_ASSERT(context.operands);
    auto&       encoder = *SWC_CHECK_NOT_NULL(context.encoder);
    const auto* ops     = inst.ops(*context.operands);
    switch (inst.op)
    {
        case MicroInstrOpcode::End:
            break;

        case MicroInstrOpcode::Ignore:
        case MicroInstrOpcode::Debug:
            break;
        case MicroInstrOpcode::Label:
            if (inst.numOperands >= 1)
            {
                labelOffsets_[resolveRef(ops[0].valueU64)] = encoder.currentOffset();
            }
            break;

        case MicroInstrOpcode::Enter:
        case MicroInstrOpcode::Leave:
        case MicroInstrOpcode::LoadCallParam:
        case MicroInstrOpcode::LoadCallAddrParam:
        case MicroInstrOpcode::LoadCallZeroExtParam:
        case MicroInstrOpcode::StoreCallParam:
            SWC_ASSERT(false);
            break;

        case MicroInstrOpcode::Push:
            encoder.encodePush(ops[0].reg);
            break;
        case MicroInstrOpcode::Pop:
            encoder.encodePop(ops[0].reg);
            break;
        case MicroInstrOpcode::Nop:
            encoder.encodeNop();
            break;
        case MicroInstrOpcode::Ret:
            encoder.encodeRet();
            break;
        case MicroInstrOpcode::CallIndirect:
            encoder.encodeCallReg(ops[0].reg, ops[1].callConv);
            break;
        case MicroInstrOpcode::JumpTable:
            encoder.encodeJumpTable(ops[0].reg, ops[1].reg, ops[2].valueI32, ops[3].valueU32, ops[4].valueU32);
            break;
        case MicroInstrOpcode::JumpCond:
        {
            MicroJump jump;
            encoder.encodeJump(jump, ops[0].cpuCond, ops[1].opBits);
            jump.valid = true;
            SWC_ASSERT(inst.numOperands >= 3);
            pendingLabelJumps_.push_back(PendingLabelJump{.jump = jump, .labelRef = ops[2].valueU64});
            break;
        }
        case MicroInstrOpcode::PatchJump:
            SWC_ASSERT(false);
            break;
        case MicroInstrOpcode::JumpCondImm:
        {
            MicroJump  jump;
            const auto opBits = ops[1].opBits == MicroOpBits::Zero ? MicroOpBits::B32 : ops[1].opBits;
            encoder.encodeJump(jump, ops[0].cpuCond, opBits);
            encoder.encodePatchJump(jump, ops[2].valueU64);
            break;
        }
        case MicroInstrOpcode::JumpReg:
            encoder.encodeJumpReg(ops[0].reg);
            break;
        case MicroInstrOpcode::LoadRegReg:
            encoder.encodeLoadRegReg(ops[0].reg, ops[1].reg, ops[2].opBits);
            break;
        case MicroInstrOpcode::LoadRegImm:
        {
            const uint32_t codeStartOffset = encoder.size();
            encoder.encodeLoadRegImm(ops[0].reg, ops[2].valueU64, ops[1].opBits);
            SWC_ASSERT(ops[1].opBits == MicroOpBits::B64 || !findRelocationIndex(instructionRef).has_value());
            bindAbs64RelocationOffset(context, instructionRef, codeStartOffset, encoder.size());
            break;
        }
        case MicroInstrOpcode::LoadRegMem:
            encoder.encodeLoadRegMem(ops[0].reg, ops[1].reg, ops[3].valueU64, ops[2].opBits);
            break;
        case MicroInstrOpcode::LoadSignedExtRegMem:
            encoder.encodeLoadSignedExtendRegMem(ops[0].reg, ops[1].reg, ops[4].valueU64, ops[2].opBits, ops[3].opBits);
            break;
        case MicroInstrOpcode::LoadSignedExtRegReg:
            encoder.encodeLoadSignedExtendRegReg(ops[0].reg, ops[1].reg, ops[2].opBits, ops[3].opBits);
            break;
        case MicroInstrOpcode::LoadZeroExtRegMem:
            encoder.encodeLoadZeroExtendRegMem(ops[0].reg, ops[1].reg, ops[4].valueU64, ops[2].opBits, ops[3].opBits);
            break;
        case MicroInstrOpcode::LoadZeroExtRegReg:
            encoder.encodeLoadZeroExtendRegReg(ops[0].reg, ops[1].reg, ops[2].opBits, ops[3].opBits);
            break;
        case MicroInstrOpcode::LoadAddrRegMem:
            encoder.encodeLoadAddressRegMem(ops[0].reg, ops[1].reg, ops[3].valueU64, ops[2].opBits);
            break;
        case MicroInstrOpcode::LoadAmcMemReg:
            encoder.encodeLoadAmcMemReg(ops[0].reg, ops[1].reg, ops[5].valueU64, ops[6].valueU64, ops[3].opBits, ops[2].reg, ops[4].opBits);
            break;
        case MicroInstrOpcode::LoadAmcMemImm:
            encoder.encodeLoadAmcMemImm(ops[0].reg, ops[1].reg, ops[5].valueU64, ops[6].valueU64, ops[3].opBits, ops[7].valueU64, ops[4].opBits);
            break;
        case MicroInstrOpcode::LoadAmcRegMem:
            encoder.encodeLoadAmcRegMem(ops[0].reg, ops[3].opBits, ops[1].reg, ops[2].reg, ops[5].valueU64, ops[6].valueU64, ops[4].opBits);
            break;
        case MicroInstrOpcode::LoadAddrAmcRegMem:
            encoder.encodeLoadAddressAmcRegMem(ops[0].reg, ops[3].opBits, ops[1].reg, ops[2].reg, ops[5].valueU64, ops[6].valueU64, ops[4].opBits);
            break;
        case MicroInstrOpcode::LoadMemReg:
            encoder.encodeLoadMemReg(ops[0].reg, ops[3].valueU64, ops[1].reg, ops[2].opBits);
            break;
        case MicroInstrOpcode::LoadMemImm:
            encoder.encodeLoadMemImm(ops[0].reg, ops[2].valueU64, ops[3].valueU64, ops[1].opBits);
            break;
        case MicroInstrOpcode::CmpRegReg:
            encoder.encodeCmpRegReg(ops[0].reg, ops[1].reg, ops[2].opBits);
            break;
        case MicroInstrOpcode::CmpRegImm:
            encoder.encodeCmpRegImm(ops[0].reg, ops[2].valueU64, ops[1].opBits);
            break;
        case MicroInstrOpcode::CmpMemReg:
            encoder.encodeCmpMemReg(ops[0].reg, ops[3].valueU64, ops[1].reg, ops[2].opBits);
            break;
        case MicroInstrOpcode::CmpMemImm:
            encoder.encodeCmpMemImm(ops[0].reg, ops[2].valueU64, ops[3].valueU64, ops[1].opBits);
            break;
        case MicroInstrOpcode::SetCondReg:
            encoder.encodeSetCondReg(ops[0].reg, ops[1].cpuCond);
            break;
        case MicroInstrOpcode::LoadCondRegReg:
            encoder.encodeLoadCondRegReg(ops[0].reg, ops[1].reg, ops[2].cpuCond, ops[3].opBits);
            break;
        case MicroInstrOpcode::ClearReg:
            encoder.encodeClearReg(ops[0].reg, ops[1].opBits);
            break;
        case MicroInstrOpcode::OpUnaryMem:
            encoder.encodeOpUnaryMem(ops[0].reg, ops[3].valueU64, ops[2].microOp, ops[1].opBits);
            break;
        case MicroInstrOpcode::OpUnaryReg:
            encoder.encodeOpUnaryReg(ops[0].reg, ops[2].microOp, ops[1].opBits);
            break;
        case MicroInstrOpcode::OpBinaryRegReg:
            encoder.encodeOpBinaryRegReg(ops[0].reg, ops[1].reg, ops[3].microOp, ops[2].opBits);
            break;
        case MicroInstrOpcode::OpBinaryMemReg:
            encoder.encodeOpBinaryMemReg(ops[0].reg, ops[4].valueU64, ops[1].reg, ops[3].microOp, ops[2].opBits);
            break;
        case MicroInstrOpcode::OpBinaryRegImm:
            encoder.encodeOpBinaryRegImm(ops[0].reg, ops[3].valueU64, ops[2].microOp, ops[1].opBits);
            break;
        case MicroInstrOpcode::OpBinaryMemImm:
            encoder.encodeOpBinaryMemImm(ops[0].reg, ops[3].valueU64, ops[4].valueU64, ops[2].microOp, ops[1].opBits);
            break;
        case MicroInstrOpcode::OpBinaryRegMem:
            encoder.encodeOpBinaryRegMem(ops[0].reg, ops[1].reg, ops[4].valueU64, ops[3].microOp, ops[2].opBits);
            break;
        case MicroInstrOpcode::OpTernaryRegRegReg:
            encoder.encodeOpTernaryRegRegReg(ops[0].reg, ops[1].reg, ops[2].reg, ops[4].microOp, ops[3].opBits);
            break;
        default:
            SWC_ASSERT(false);
            break;
    }
}

void MicroEmitPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.encoder);
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);
    auto& encoder = *SWC_CHECK_NOT_NULL(context.encoder);

    labelOffsets_.clear();
    pendingLabelJumps_.clear();
    relocationByInstructionRef_.clear();
    auto& relocations = context.builder->codeRelocations();
    for (uint32_t idx = 0; idx < relocations.size(); ++idx)
    {
        const auto& reloc = relocations[idx];
        if (reloc.instructionRef == INVALID_REF)
            continue;
        relocationByInstructionRef_[reloc.instructionRef] = idx;
    }

    for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
    {
        encodeInstruction(context, it.current, *it);
    }

    for (const auto& pending : pendingLabelJumps_)
    {
        const auto destination = resolveJumpDestination(labelOffsets_, pending.labelRef);
        encoder.encodePatchJump(pending.jump, destination);
    }
}

SWC_END_NAMESPACE();


