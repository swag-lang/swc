#include "pch.h"
#include "Backend/MachineCode/Encoder/MicroOps/MicroOpsEncoder.h"

SWC_BEGIN_NAMESPACE();

MicroInstruction& MicroOpsEncoder::addInstruction(MicroOp op, CpuEmitFlags emitFlags)
{
    MicroInstruction inst{};
    inst.op        = op;
    inst.emitFlags = emitFlags;
    instructions_.push_back(inst);
    return instructions_.back();
}

namespace
{
    size_t resolveJumpIndex(uint64_t valueA)
    {
        if (valueA == 0)
            return 0;
        constexpr uint64_t stride = sizeof(MicroInstruction);
        if (valueA % stride == 0)
            return valueA / stride;
        return valueA;
    }
}

void MicroOpsEncoder::encode(CpuEncoder& encoder) const
{
    std::vector<CpuJump> jumps(instructions_.size());
    std::vector          jumpValid(instructions_.size(), false);

    for (size_t idx = 0; idx < instructions_.size(); ++idx)
    {
        const auto& inst = instructions_[idx];
        if (inst.op == MicroOp::End)
            break;

        switch (inst.op)
        {
            case MicroOp::End:
                break;

            case MicroOp::Ignore:
            case MicroOp::Label:
            case MicroOp::Debug:
                break;

            case MicroOp::Enter:
            case MicroOp::Leave:
            case MicroOp::LoadCallParam:
            case MicroOp::LoadCallAddrParam:
            case MicroOp::LoadCallZeroExtParam:
            case MicroOp::StoreCallParam:
                SWC_ASSERT(false);
                break;

            case MicroOp::SymbolRelocAddr:
                encoder.encodeLoadSymbolRelocAddress(inst.regA, static_cast<uint32_t>(inst.valueA), static_cast<uint32_t>(inst.valueB), inst.emitFlags);
                break;
            case MicroOp::SymbolRelocValue:
                encoder.encodeLoadSymRelocValue(inst.regA, static_cast<uint32_t>(inst.valueA), static_cast<uint32_t>(inst.valueB), inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::Push:
                encoder.encodePush(inst.regA, inst.emitFlags);
                break;
            case MicroOp::Pop:
                encoder.encodePop(inst.regA, inst.emitFlags);
                break;
            case MicroOp::Nop:
                encoder.encodeNop(inst.emitFlags);
                break;
            case MicroOp::Ret:
                encoder.encodeRet(inst.emitFlags);
                break;
            case MicroOp::CallLocal:
                encoder.encodeCallLocal(inst.name, inst.cc, inst.emitFlags);
                break;
            case MicroOp::CallExtern:
                encoder.encodeCallExtern(inst.name, inst.cc, inst.emitFlags);
                break;
            case MicroOp::CallIndirect:
                encoder.encodeCallReg(inst.regA, inst.cc, inst.emitFlags);
                break;
            case MicroOp::JumpTable:
                encoder.encodeJumpTable(inst.regA, inst.regB, static_cast<int32_t>(inst.valueA), static_cast<uint32_t>(inst.valueB), static_cast<uint32_t>(inst.valueC), inst.emitFlags);
                break;
            case MicroOp::JumpCond:
            {
                CpuJump jump;
                encoder.encodeJump(jump, inst.jumpType, inst.opBitsA, inst.emitFlags);
                jumps[idx]     = jump;
                jumpValid[idx] = true;
                break;
            }
            case MicroOp::PatchJump:
            {
                const size_t jumpIndex = resolveJumpIndex(inst.valueA);
                SWC_ASSERT(jumpIndex < jumpValid.size());
                SWC_ASSERT(jumpValid[jumpIndex]);
                encoder.encodePatchJump(jumps[jumpIndex], inst.emitFlags);
                break;
            }
            case MicroOp::JumpCondI:
            {
                CpuJump jump;
                encoder.encodeJump(jump, inst.jumpType, inst.opBitsA, inst.emitFlags);
                encoder.encodePatchJump(jump, inst.valueA, inst.emitFlags);
                break;
            }
            case MicroOp::JumpM:
                encoder.encodeJumpReg(inst.regA, inst.emitFlags);
                break;
            case MicroOp::LoadRR:
                encoder.encodeLoadRegReg(inst.regA, inst.regB, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::LoadRI:
                encoder.encodeLoadRegImm(inst.regA, inst.valueA, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::LoadRM:
                encoder.encodeLoadRegMem(inst.regA, inst.regB, inst.valueA, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::LoadSignedExtRM:
                encoder.encodeLoadSignedExtendRegMem(inst.regA, inst.regB, inst.valueA, inst.opBitsA, inst.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadSignedExtRR:
                encoder.encodeLoadSignedExtendRegReg(inst.regA, inst.regB, inst.opBitsA, inst.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadZeroExtRM:
                encoder.encodeLoadZeroExtendRegMem(inst.regA, inst.regB, inst.valueA, inst.opBitsA, inst.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadZeroExtRR:
                encoder.encodeLoadZeroExtendRegReg(inst.regA, inst.regB, inst.opBitsA, inst.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadAddrRM:
                encoder.encodeLoadAddressRegMem(inst.regA, inst.regB, inst.valueA, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::LoadAmcMR:
                encoder.encodeLoadAmcMemReg(inst.regA, inst.regB, inst.valueA, inst.valueB, inst.opBitsA, inst.regC, inst.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadAmcMI:
                encoder.encodeLoadAmcMemImm(inst.regA, inst.regB, inst.valueA, inst.valueB, inst.opBitsA, inst.valueC, inst.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadAmcRM:
                encoder.encodeLoadAmcRegMem(inst.regA, inst.opBitsA, inst.regB, inst.regC, inst.valueA, inst.valueB, inst.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadAddrAmcRM:
                encoder.encodeLoadAddressAmcRegMem(inst.regA, inst.opBitsA, inst.regB, inst.regC, inst.valueA, inst.valueB, inst.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadMR:
                encoder.encodeLoadMemReg(inst.regA, inst.valueA, inst.regB, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::LoadMI:
                encoder.encodeLoadMemImm(inst.regA, inst.valueA, inst.valueB, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::CmpRR:
                encoder.encodeCmpRegReg(inst.regA, inst.regB, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::CmpRI:
                encoder.encodeCmpRegImm(inst.regA, inst.valueA, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::CmpMR:
                encoder.encodeCmpMemReg(inst.regA, inst.valueA, inst.regB, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::CmpMI:
                encoder.encodeCmpMemImm(inst.regA, inst.valueA, inst.valueB, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::SetCondR:
                encoder.encodeSetCondReg(inst.regA, inst.cpuCond, inst.emitFlags);
                break;
            case MicroOp::LoadCondRR:
                encoder.encodeLoadCondRegReg(inst.regA, inst.regB, inst.cpuCond, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::ClearR:
                encoder.encodeClearReg(inst.regA, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpUnaryM:
                encoder.encodeOpUnaryMem(inst.regA, inst.valueA, inst.cpuOp, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpUnaryR:
                encoder.encodeOpUnaryReg(inst.regA, inst.cpuOp, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpBinaryRR:
                encoder.encodeOpBinaryRegReg(inst.regA, inst.regB, inst.cpuOp, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpBinaryMR:
                encoder.encodeOpBinaryMemReg(inst.regA, inst.valueA, inst.regB, inst.cpuOp, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpBinaryRI:
                encoder.encodeOpBinaryRegImm(inst.regA, inst.valueA, inst.cpuOp, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpBinaryMI:
                encoder.encodeOpBinaryMemImm(inst.regA, inst.valueA, inst.valueB, inst.cpuOp, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpBinaryRM:
                encoder.encodeOpBinaryRegMem(inst.regA, inst.regB, inst.valueA, inst.cpuOp, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpTernaryRRR:
                encoder.encodeOpTernaryRegRegReg(inst.regA, inst.regB, inst.regC, inst.cpuOp, inst.opBitsA, inst.emitFlags);
                break;
            default:
                SWC_ASSERT(false);
                break;
        }
    }
}

SWC_END_NAMESPACE();
