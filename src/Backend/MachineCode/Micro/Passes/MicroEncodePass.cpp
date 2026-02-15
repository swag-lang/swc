#include "pch.h"
#include "Backend/MachineCode/Micro/Passes/MicroEncodePass.h"
#include "Backend/MachineCode/Micro/MicroInstr.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Ref resolveJumpRef(uint64_t valueA)
    {
        if (valueA > std::numeric_limits<Ref>::max())
            return INVALID_REF;
        return static_cast<Ref>(valueA);
    }
}

void MicroEncodePass::encodeInstruction(const MicroPassContext& context, const MicroInstr& inst, Ref instRef)
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
            jump.valid      = true;
            jumps_[instRef] = jump;
            break;
        }
        case MicroInstrOpcode::PatchJump:
        {
            Ref  jumpRef = resolveJumpRef(ops[0].valueU64);
            auto it      = jumps_.find(jumpRef);
            if (it == jumps_.end())
            {
                constexpr uint64_t stride = sizeof(MicroInstr);
                if (ops[0].valueU64 % stride == 0)
                {
                    jumpRef = resolveJumpRef(ops[0].valueU64 / stride);
                    it      = jumps_.find(jumpRef);
                }
            }
            SWC_ASSERT(it != jumps_.end());
            SWC_ASSERT(it->second.valid);
            if (ops[2].valueU64 == 1)
                encoder.encodePatchJump(it->second, ops[1].valueU64, inst.emitFlags);
            else
                encoder.encodePatchJump(it->second, inst.emitFlags);
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

    jumps_.clear();

    for (auto it = context.instructions->view().begin(); it != context.instructions->view().end(); ++it)
    {
        encodeInstruction(context, *it, it.current);
    }
}

SWC_END_NAMESPACE();
