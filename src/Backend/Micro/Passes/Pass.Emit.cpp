#include "pch.h"
#include "Backend/Micro/Passes/Pass.Emit.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Backend/Micro/MicroPassContext.h"

// Final emission pass: converts legalized micro instructions to machine code.
// Example: branch placeholders are patched to concrete displacements.
// Example: relocation-bearing immediates receive final code offsets.
// This pass does not optimize semantics; it materializes final bytes.

SWC_BEGIN_NAMESPACE();

void MicroEmitPass::bindAbs64RelocationOffset(const MicroPassContext& context, MicroInstrRef instructionRef, uint32_t codeStartOffset, uint32_t codeEndOffset) const
{
    // Relocation-backed absolute pointer loads embed a trailing 64-bit immediate.
    const auto found = relocationByInstructionRef_.find(instructionRef);
    SWC_ASSERT(found != relocationByInstructionRef_.end());
    if (found == relocationByInstructionRef_.end())
        return;

    SWC_ASSERT(codeEndOffset >= codeStartOffset + sizeof(uint64_t));
    MicroRelocation& reloc = context.builder->codeRelocations()[found->second];
    reloc.codeOffset       = codeEndOffset - sizeof(uint64_t);
}

void MicroEmitPass::encodeInstruction(const MicroPassContext& context, MicroInstrRef instructionRef, const MicroInstr& inst)
{
    SWC_ASSERT(context.encoder);
    SWC_ASSERT(context.operands);
    auto&                    encoder                    = *SWC_NOT_NULL(context.encoder);
    const MicroInstrOperand* ops                        = inst.ops(*context.operands);
    const uint32_t           instructionCodeStartOffset = encoder.size();
    const bool               emitDebugInfo              = context.builder && context.builder->hasFlag(MicroBuilderFlagsE::DebugInfo);
    switch (inst.op)
    {
        case MicroInstrOpcode::End:
            break;

        case MicroInstrOpcode::Label:
            // Record concrete code offset so pending branch patches can resolve target.
            SWC_ASSERT(ops[0].valueU64 <= std::numeric_limits<uint32_t>::max());
            labelOffsets_[MicroLabelRef(static_cast<uint32_t>(ops[0].valueU64))] = encoder.currentOffset();
            break;
        case MicroInstrOpcode::JumpCond:
        {
            // Emit jump with placeholder displacement; patch after all labels are seen.
            MicroJump jump;
            encoder.encodeJump(jump, ops[0].cpuCond, ops[1].opBits);
            jump.valid = true;
            SWC_ASSERT(ops[2].valueU64 <= std::numeric_limits<uint32_t>::max());
            pendingLabelJumps_.push_back(PendingLabelJump{.jump = jump, .labelRef = MicroLabelRef(static_cast<uint32_t>(ops[2].valueU64))});
            break;
        }
        case MicroInstrOpcode::JumpCondImm:
        {
            MicroJump  jump;
            const auto opBits = ops[1].opBits == MicroOpBits::Zero ? MicroOpBits::B32 : ops[1].opBits;
            encoder.encodeJump(jump, ops[0].cpuCond, opBits);
            encoder.encodePatchJump(jump, ops[2].valueU64);
            break;
        }
        case MicroInstrOpcode::LoadRegPtrImm:
            encoder.encodeLoadRegImm(ops[0].reg, ops[2].immediateValue(64), ops[1].opBits);
            break;
        case MicroInstrOpcode::LoadRegPtrReloc:
        {
            const uint32_t loadCodeStartOffset = encoder.size();
            encoder.encodeLoadRegImm(ops[0].reg, ops[2].immediateValue(64), ops[1].opBits);
            SWC_ASSERT(ops[1].opBits == MicroOpBits::B64);
            bindAbs64RelocationOffset(context, instructionRef, loadCodeStartOffset, encoder.size());
            break;
        }

        case MicroInstrOpcode::Push:
            encoder.encodePush(ops[0].reg);
            break;
        case MicroInstrOpcode::Pop:
            encoder.encodePop(ops[0].reg);
            break;
        case MicroInstrOpcode::Nop:
            encoder.encodeNop();
            break;
        case MicroInstrOpcode::Breakpoint:
            encoder.encodeBreakpoint();
            break;
        case MicroInstrOpcode::AssertTrap:
            encoder.encodeAssertTrap();
            break;
        case MicroInstrOpcode::Ret:
            encoder.encodeRet();
            break;
        case MicroInstrOpcode::CallLocal:
        case MicroInstrOpcode::CallExtern:
        {
            const auto relocIt = relocationByInstructionRef_.find(instructionRef);
            SWC_ASSERT(relocIt != relocationByInstructionRef_.end());
            if (relocIt == relocationByInstructionRef_.end())
                break;

            const MicroRelocation& relocation = context.builder->codeRelocations()[relocIt->second];
            if (inst.op == MicroInstrOpcode::CallLocal)
                SWC_ASSERT(relocation.kind == MicroRelocation::Kind::LocalFunctionAddress);
            else
                SWC_ASSERT(relocation.kind == MicroRelocation::Kind::ForeignFunctionAddress);

            const CallConv& conv      = CallConv::get(ops[0].callConv);
            const uint32_t  loadStart = encoder.size();

            encoder.encodeLoadRegImm(conv.intReturn, ApInt(relocation.targetAddress, 64), MicroOpBits::B64);
            bindAbs64RelocationOffset(context, instructionRef, loadStart, encoder.size());
            encoder.encodeCallReg(conv.intReturn, ops[0].callConv);
            break;
        }
        case MicroInstrOpcode::CallIndirect:
            // Call target is already materialized in ops[0] by earlier lowering stages.
            encoder.encodeCallReg(ops[0].reg, ops[1].callConv);
            break;
        case MicroInstrOpcode::JumpReg:
            encoder.encodeJumpReg(ops[0].reg);
            break;
        case MicroInstrOpcode::LoadRegReg:
            encoder.encodeLoadRegReg(ops[0].reg, ops[1].reg, ops[2].opBits);
            break;
        case MicroInstrOpcode::LoadRegImm:
            encoder.encodeLoadRegImm(ops[0].reg, ops[2].immediateValue(getNumBits(ops[1].opBits)), ops[1].opBits);
            break;
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
            encoder.encodeLoadAmcMemImm(ops[0].reg, ops[1].reg, ops[5].valueU64, ops[6].valueU64, ops[3].opBits, ops[7].immediateValue(getNumBits(ops[4].opBits)), ops[4].opBits);
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
            encoder.encodeLoadMemImm(ops[0].reg, ops[2].valueU64, ops[3].immediateValue(getNumBits(ops[1].opBits)), ops[1].opBits);
            break;
        case MicroInstrOpcode::CmpRegReg:
            encoder.encodeCmpRegReg(ops[0].reg, ops[1].reg, ops[2].opBits);
            break;
        case MicroInstrOpcode::CmpRegImm:
            encoder.encodeCmpRegImm(ops[0].reg, ops[2].immediateValue(getNumBits(ops[1].opBits)), ops[1].opBits);
            break;
        case MicroInstrOpcode::CmpMemReg:
            encoder.encodeCmpMemReg(ops[0].reg, ops[3].valueU64, ops[1].reg, ops[2].opBits);
            break;
        case MicroInstrOpcode::CmpMemImm:
            encoder.encodeCmpMemImm(ops[0].reg, ops[2].valueU64, ops[3].immediateValue(getNumBits(ops[1].opBits)), ops[1].opBits);
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
            encoder.encodeOpBinaryRegImm(ops[0].reg, ops[3].immediateValue(getNumBits(ops[1].opBits)), ops[2].microOp, ops[1].opBits);
            break;
        case MicroInstrOpcode::OpBinaryMemImm:
            encoder.encodeOpBinaryMemImm(ops[0].reg, ops[3].valueU64, ops[4].immediateValue(getNumBits(ops[1].opBits)), ops[2].microOp, ops[1].opBits);
            break;
        case MicroInstrOpcode::OpBinaryRegMem:
            encoder.encodeOpBinaryRegMem(ops[0].reg, ops[1].reg, ops[4].valueU64, ops[3].microOp, ops[2].opBits);
            break;
        case MicroInstrOpcode::OpTernaryRegRegReg:
            encoder.encodeOpTernaryRegRegReg(ops[0].reg, ops[1].reg, ops[2].reg, ops[4].microOp, ops[3].opBits);
            break;
        default:
            SWC_UNREACHABLE();
    }

    encoder.onInstructionEncoded(inst, ops, instructionCodeStartOffset, encoder.size());

    if (emitDebugInfo)
        encoder.addDebugSourceRange(instructionCodeStartOffset, encoder.size(), inst.sourceCodeRef);
}

Result MicroEmitPass::run(MicroPassContext& context)
{
    SWC_ASSERT(context.encoder);
    SWC_ASSERT(context.instructions);
    SWC_ASSERT(context.operands);
    auto&       encoder     = *SWC_NOT_NULL(context.encoder);
    const auto& relocations = context.builder->codeRelocations();

    labelOffsets_.clear();
    pendingLabelJumps_.clear();
    relocationByInstructionRef_.clear();
    SWC_NOT_NULL(context.builder)->pruneDeadRelocations();

    // Build instruction->relocation lookup once so LoadRegPtrReloc can bind encoded offsets.
    for (uint32_t idx = 0; idx < relocations.size(); ++idx)
    {
        const MicroRelocation& reloc = relocations[idx];
        if (reloc.instructionRef.isInvalid())
            continue;
        relocationByInstructionRef_[reloc.instructionRef] = idx;
    }

    // Single forward pass emits bytes and accumulates unresolved label jumps.
    for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
    {
        encodeInstruction(context, it.current, *it);
    }

    // Second pass patches all label-relative branches now that offsets are known.
    for (const auto& pending : pendingLabelJumps_)
    {
        const auto it = labelOffsets_.find(pending.labelRef);
        SWC_ASSERT(it != labelOffsets_.end());
        if (it == labelOffsets_.end())
            continue;

        encoder.encodePatchJump(pending.jump, it->second);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
