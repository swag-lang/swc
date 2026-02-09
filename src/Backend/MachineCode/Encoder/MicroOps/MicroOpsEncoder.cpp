#include "pch.h"
#include "Backend/MachineCode/Encoder/MicroOps/MicroOpsEncoder.h"

SWC_BEGIN_NAMESPACE();

MicroInstruction& MicroOpsEncoder::addInstruction(MicroOp op, EmitFlags emitFlags, uint8_t numOperands)
{
    instructions_.emplace_back();
    auto& inst   = instructions_.back();
    inst.op      = op;
    inst.emitFlags = emitFlags;
    inst.allocateOperands(numOperands);
    return inst;
}

EncodeResult MicroOpsEncoder::encodeLoadSymbolRelocAddress(CpuReg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags)
{
    auto& inst            = addInstruction(MicroOp::SymbolRelocAddr, emitFlags, 3);
    inst.operands[0].reg  = reg;
    inst.operands[1].value = symbolIndex;
    inst.operands[2].value = offset;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadSymRelocValue(CpuReg reg, uint32_t symbolIndex, uint32_t offset, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::SymbolRelocValue, emitFlags, 4);
    inst.operands[0].reg   = reg;
    inst.operands[1].opBits = opBits;
    inst.operands[2].value = symbolIndex;
    inst.operands[3].value = offset;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodePush(CpuReg reg, EmitFlags emitFlags)
{
    auto& inst           = addInstruction(MicroOp::Push, emitFlags, 1);
    inst.operands[0].reg = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodePop(CpuReg reg, EmitFlags emitFlags)
{
    auto& inst           = addInstruction(MicroOp::Pop, emitFlags, 1);
    inst.operands[0].reg = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeNop(EmitFlags emitFlags)
{
    addInstruction(MicroOp::Nop, emitFlags, 0);
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeRet(EmitFlags emitFlags)
{
    addInstruction(MicroOp::Ret, emitFlags, 0);
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeCallLocal(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)
{
    auto& inst            = addInstruction(MicroOp::CallLocal, emitFlags, 2);
    inst.operands[0].name = symbolName;
    inst.operands[1].callConv   = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeCallExtern(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)
{
    auto& inst            = addInstruction(MicroOp::CallExtern, emitFlags, 2);
    inst.operands[0].name = symbolName;
    inst.operands[1].callConv   = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeCallReg(CpuReg reg, const CallConv* callConv, EmitFlags emitFlags)
{
    auto& inst           = addInstruction(MicroOp::CallIndirect, emitFlags, 2);
    inst.operands[0].reg = reg;
    inst.operands[1].callConv = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeJumpTable(CpuReg tableReg, CpuReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags)
{
    auto& inst            = addInstruction(MicroOp::JumpTable, emitFlags, 5);
    inst.operands[0].reg  = tableReg;
    inst.operands[1].reg  = offsetReg;
    inst.operands[2].value = currentIp;
    inst.operands[3].value = offsetTable;
    inst.operands[4].value = numEntries;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeJump(CpuJump& jump, CpuCondJump jumpType, CpuOpBits opBits, EmitFlags emitFlags)
{
    jump.offsetStart               = instructions_.size() * sizeof(MicroInstruction);
    jump.opBits                    = opBits;
    auto& inst              = addInstruction(MicroOp::JumpCond, emitFlags, 2);
    inst.operands[0].jumpType = jumpType;
    inst.operands[1].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodePatchJump(const CpuJump& jump, uint64_t offsetDestination, EmitFlags emitFlags)
{
    auto& inst            = addInstruction(MicroOp::PatchJump, emitFlags, 3);
    inst.operands[0].value = jump.offsetStart;
    inst.operands[1].value = offsetDestination;
    inst.operands[2].value = 1;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodePatchJump(const CpuJump& jump, EmitFlags emitFlags)
{
    auto& inst            = addInstruction(MicroOp::PatchJump, emitFlags, 3);
    inst.operands[0].value = jump.offsetStart;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeJumpReg(CpuReg reg, EmitFlags emitFlags)
{
    auto& inst           = addInstruction(MicroOp::JumpM, emitFlags, 1);
    inst.operands[0].reg = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::LoadRM, emitFlags, 4);
    inst.operands[0].reg   = reg;
    inst.operands[1].reg   = memReg;
    inst.operands[2].opBits = opBits;
    inst.operands[3].value = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadRegImm(CpuReg reg, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::LoadRI, emitFlags, 3);
    inst.operands[0].reg   = reg;
    inst.operands[1].opBits = opBits;
    inst.operands[2].value = value;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::LoadRR, emitFlags, 3);
    inst.operands[0].reg   = regDst;
    inst.operands[1].reg   = regSrc;
    inst.operands[2].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadSignedExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::LoadSignedExtRM, emitFlags, 5);
    inst.operands[0].reg   = reg;
    inst.operands[1].reg   = memReg;
    inst.operands[2].opBits = numBitsDst;
    inst.operands[3].opBits = numBitsSrc;
    inst.operands[4].value = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadSignedExtendRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::LoadSignedExtRR, emitFlags, 4);
    inst.operands[0].reg   = regDst;
    inst.operands[1].reg   = regSrc;
    inst.operands[2].opBits = numBitsDst;
    inst.operands[3].opBits = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadZeroExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::LoadZeroExtRM, emitFlags, 5);
    inst.operands[0].reg   = reg;
    inst.operands[1].reg   = memReg;
    inst.operands[2].opBits = numBitsDst;
    inst.operands[3].opBits = numBitsSrc;
    inst.operands[4].value = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadZeroExtendRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::LoadZeroExtRR, emitFlags, 4);
    inst.operands[0].reg   = regDst;
    inst.operands[1].reg   = regSrc;
    inst.operands[2].opBits = numBitsDst;
    inst.operands[3].opBits = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadAddressRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::LoadAddrRM, emitFlags, 4);
    inst.operands[0].reg   = reg;
    inst.operands[1].reg   = memReg;
    inst.operands[2].opBits = opBits;
    inst.operands[3].value = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadAmcRegMem(CpuReg regDst, CpuOpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsSrc, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::LoadAmcRM, emitFlags, 8);
    inst.operands[0].reg   = regDst;
    inst.operands[1].reg   = regBase;
    inst.operands[2].reg   = regMul;
    inst.operands[3].opBits = opBitsDst;
    inst.operands[4].opBits = opBitsSrc;
    inst.operands[5].value = mulValue;
    inst.operands[6].value = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadAmcMemReg(CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsBaseMul, CpuReg regSrc, CpuOpBits opBitsSrc, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::LoadAmcMR, emitFlags, 8);
    inst.operands[0].reg   = regBase;
    inst.operands[1].reg   = regMul;
    inst.operands[2].reg   = regSrc;
    inst.operands[3].opBits = opBitsBaseMul;
    inst.operands[4].opBits = opBitsSrc;
    inst.operands[5].value = mulValue;
    inst.operands[6].value = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadAmcMemImm(CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsBaseMul, uint64_t value, CpuOpBits opBitsValue, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::LoadAmcMI, emitFlags, 8);
    inst.operands[0].reg   = regBase;
    inst.operands[1].reg   = regMul;
    inst.operands[3].opBits = opBitsBaseMul;
    inst.operands[4].opBits = opBitsValue;
    inst.operands[5].value = mulValue;
    inst.operands[6].value = addValue;
    inst.operands[7].value = value;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadAddressAmcRegMem(CpuReg regDst, CpuOpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsValue, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::LoadAddrAmcRM, emitFlags, 8);
    inst.operands[0].reg   = regDst;
    inst.operands[1].reg   = regBase;
    inst.operands[2].reg   = regMul;
    inst.operands[3].opBits = opBitsDst;
    inst.operands[4].opBits = opBitsValue;
    inst.operands[5].value = mulValue;
    inst.operands[6].value = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::LoadMR, emitFlags, 4);
    inst.operands[0].reg   = memReg;
    inst.operands[1].reg   = reg;
    inst.operands[2].opBits = opBits;
    inst.operands[3].value = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::LoadMI, emitFlags, 4);
    inst.operands[0].reg   = memReg;
    inst.operands[1].opBits = opBits;
    inst.operands[2].value = memOffset;
    inst.operands[3].value = value;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeCmpRegReg(CpuReg reg0, CpuReg reg1, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::CmpRR, emitFlags, 3);
    inst.operands[0].reg   = reg0;
    inst.operands[1].reg   = reg1;
    inst.operands[2].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeCmpMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::CmpMR, emitFlags, 4);
    inst.operands[0].reg   = memReg;
    inst.operands[1].reg   = reg;
    inst.operands[2].opBits = opBits;
    inst.operands[3].value = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeCmpMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::CmpMI, emitFlags, 4);
    inst.operands[0].reg   = memReg;
    inst.operands[1].opBits = opBits;
    inst.operands[2].value = memOffset;
    inst.operands[3].value = value;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeCmpRegImm(CpuReg reg, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::CmpRI, emitFlags, 3);
    inst.operands[0].reg   = reg;
    inst.operands[1].opBits = opBits;
    inst.operands[2].value = value;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeSetCondReg(CpuReg reg, CpuCond cpuCond, EmitFlags emitFlags)
{
    auto& inst              = addInstruction(MicroOp::SetCondR, emitFlags, 2);
    inst.operands[0].reg    = reg;
    inst.operands[1].cpuCond = cpuCond;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadCondRegReg(CpuReg regDst, CpuReg regSrc, CpuCond setType, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::LoadCondRR, emitFlags, 4);
    inst.operands[0].reg   = regDst;
    inst.operands[1].reg   = regSrc;
    inst.operands[2].cpuCond = setType;
    inst.operands[3].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeClearReg(CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::ClearR, emitFlags, 2);
    inst.operands[0].reg   = reg;
    inst.operands[1].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpUnaryMem(CpuReg memReg, uint64_t memOffset, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::OpUnaryM, emitFlags, 4);
    inst.operands[0].reg   = memReg;
    inst.operands[1].opBits = opBits;
    inst.operands[2].cpuOp = op;
    inst.operands[3].value = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpUnaryReg(CpuReg reg, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::OpUnaryR, emitFlags, 3);
    inst.operands[0].reg   = reg;
    inst.operands[1].opBits = opBits;
    inst.operands[2].cpuOp = op;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpBinaryRegReg(CpuReg regDst, CpuReg regSrc, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::OpBinaryRR, emitFlags, 4);
    inst.operands[0].reg   = regDst;
    inst.operands[1].reg   = regSrc;
    inst.operands[2].opBits = opBits;
    inst.operands[3].cpuOp = op;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpBinaryRegMem(CpuReg regDst, CpuReg memReg, uint64_t memOffset, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::OpBinaryRM, emitFlags, 5);
    inst.operands[0].reg   = regDst;
    inst.operands[1].reg   = memReg;
    inst.operands[2].opBits = opBits;
    inst.operands[3].cpuOp = op;
    inst.operands[4].value = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpBinaryMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::OpBinaryMR, emitFlags, 5);
    inst.operands[0].reg   = memReg;
    inst.operands[1].reg   = reg;
    inst.operands[2].opBits = opBits;
    inst.operands[3].cpuOp = op;
    inst.operands[4].value = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpBinaryRegImm(CpuReg reg, uint64_t value, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::OpBinaryRI, emitFlags, 4);
    inst.operands[0].reg   = reg;
    inst.operands[1].opBits = opBits;
    inst.operands[2].cpuOp = op;
    inst.operands[3].value = value;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpBinaryMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::OpBinaryMI, emitFlags, 5);
    inst.operands[0].reg   = memReg;
    inst.operands[1].opBits = opBits;
    inst.operands[2].cpuOp = op;
    inst.operands[3].value = memOffset;
    inst.operands[4].value = value;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpTernaryRegRegReg(CpuReg reg0, CpuReg reg1, CpuReg reg2, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst             = addInstruction(MicroOp::OpTernaryRRR, emitFlags, 5);
    inst.operands[0].reg   = reg0;
    inst.operands[1].reg   = reg1;
    inst.operands[2].reg   = reg2;
    inst.operands[3].opBits = opBits;
    inst.operands[4].cpuOp = op;
    return EncodeResult::Zero;
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

void MicroOpsEncoder::encode(Encoder& encoder) const
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
                encoder.encodeLoadSymbolRelocAddress(inst.operands[0].reg, static_cast<uint32_t>(inst.operands[1].value), static_cast<uint32_t>(inst.operands[2].value), inst.emitFlags);
                break;
            case MicroOp::SymbolRelocValue:
                encoder.encodeLoadSymRelocValue(inst.operands[0].reg, static_cast<uint32_t>(inst.operands[2].value), static_cast<uint32_t>(inst.operands[3].value), inst.operands[1].opBits, inst.emitFlags);
                break;
            case MicroOp::Push:
                encoder.encodePush(inst.operands[0].reg, inst.emitFlags);
                break;
            case MicroOp::Pop:
                encoder.encodePop(inst.operands[0].reg, inst.emitFlags);
                break;
            case MicroOp::Nop:
                encoder.encodeNop(inst.emitFlags);
                break;
            case MicroOp::Ret:
                encoder.encodeRet(inst.emitFlags);
                break;
            case MicroOp::CallLocal:
                encoder.encodeCallLocal(inst.operands[0].name, inst.operands[1].callConv, inst.emitFlags);
                break;
            case MicroOp::CallExtern:
                encoder.encodeCallExtern(inst.operands[0].name, inst.operands[1].callConv, inst.emitFlags);
                break;
            case MicroOp::CallIndirect:
                encoder.encodeCallReg(inst.operands[0].reg, inst.operands[1].callConv, inst.emitFlags);
                break;
            case MicroOp::JumpTable:
                encoder.encodeJumpTable(inst.operands[0].reg, inst.operands[1].reg, static_cast<int32_t>(inst.operands[2].value), static_cast<uint32_t>(inst.operands[3].value), static_cast<uint32_t>(inst.operands[4].value), inst.emitFlags);
                break;
            case MicroOp::JumpCond:
            {
                CpuJump jump;
                encoder.encodeJump(jump, inst.operands[0].jumpType, inst.operands[1].opBits, inst.emitFlags);
                jumps[idx]     = jump;
                jumpValid[idx] = true;
                break;
            }
            case MicroOp::PatchJump:
            {
                const size_t jumpIndex = resolveJumpIndex(inst.operands[0].value);
                SWC_ASSERT(jumpIndex < jumpValid.size());
                SWC_ASSERT(jumpValid[jumpIndex]);
                if (inst.operands[2].value == 1)
                    encoder.encodePatchJump(jumps[jumpIndex], inst.operands[1].value, inst.emitFlags);
                else
                    encoder.encodePatchJump(jumps[jumpIndex], inst.emitFlags);
                break;
            }
            case MicroOp::JumpCondI:
            {
                CpuJump    jump;
                const auto opBits = inst.operands[1].opBits == CpuOpBits::Zero ? CpuOpBits::B32 : inst.operands[1].opBits;
                encoder.encodeJump(jump, inst.operands[0].jumpType, opBits, inst.emitFlags);
                encoder.encodePatchJump(jump, inst.operands[2].value, inst.emitFlags);
                break;
            }
            case MicroOp::JumpM:
                encoder.encodeJumpReg(inst.operands[0].reg, inst.emitFlags);
                break;
            case MicroOp::LoadRR:
                encoder.encodeLoadRegReg(inst.operands[0].reg, inst.operands[1].reg, inst.operands[2].opBits, inst.emitFlags);
                break;
            case MicroOp::LoadRI:
                encoder.encodeLoadRegImm(inst.operands[0].reg, inst.operands[2].value, inst.operands[1].opBits, inst.emitFlags);
                break;
            case MicroOp::LoadRM:
                encoder.encodeLoadRegMem(inst.operands[0].reg, inst.operands[1].reg, inst.operands[3].value, inst.operands[2].opBits, inst.emitFlags);
                break;
            case MicroOp::LoadSignedExtRM:
                encoder.encodeLoadSignedExtendRegMem(inst.operands[0].reg, inst.operands[1].reg, inst.operands[4].value, inst.operands[2].opBits, inst.operands[3].opBits, inst.emitFlags);
                break;
            case MicroOp::LoadSignedExtRR:
                encoder.encodeLoadSignedExtendRegReg(inst.operands[0].reg, inst.operands[1].reg, inst.operands[2].opBits, inst.operands[3].opBits, inst.emitFlags);
                break;
            case MicroOp::LoadZeroExtRM:
                encoder.encodeLoadZeroExtendRegMem(inst.operands[0].reg, inst.operands[1].reg, inst.operands[4].value, inst.operands[2].opBits, inst.operands[3].opBits, inst.emitFlags);
                break;
            case MicroOp::LoadZeroExtRR:
                encoder.encodeLoadZeroExtendRegReg(inst.operands[0].reg, inst.operands[1].reg, inst.operands[2].opBits, inst.operands[3].opBits, inst.emitFlags);
                break;
            case MicroOp::LoadAddrRM:
                encoder.encodeLoadAddressRegMem(inst.operands[0].reg, inst.operands[1].reg, inst.operands[3].value, inst.operands[2].opBits, inst.emitFlags);
                break;
            case MicroOp::LoadAmcMR:
                encoder.encodeLoadAmcMemReg(inst.operands[0].reg, inst.operands[1].reg, inst.operands[5].value, inst.operands[6].value, inst.operands[3].opBits, inst.operands[2].reg, inst.operands[4].opBits, inst.emitFlags);
                break;
            case MicroOp::LoadAmcMI:
                encoder.encodeLoadAmcMemImm(inst.operands[0].reg, inst.operands[1].reg, inst.operands[5].value, inst.operands[6].value, inst.operands[3].opBits, inst.operands[7].value, inst.operands[4].opBits, inst.emitFlags);
                break;
            case MicroOp::LoadAmcRM:
                encoder.encodeLoadAmcRegMem(inst.operands[0].reg, inst.operands[3].opBits, inst.operands[1].reg, inst.operands[2].reg, inst.operands[5].value, inst.operands[6].value, inst.operands[4].opBits, inst.emitFlags);
                break;
            case MicroOp::LoadAddrAmcRM:
                encoder.encodeLoadAddressAmcRegMem(inst.operands[0].reg, inst.operands[3].opBits, inst.operands[1].reg, inst.operands[2].reg, inst.operands[5].value, inst.operands[6].value, inst.operands[4].opBits, inst.emitFlags);
                break;
            case MicroOp::LoadMR:
                encoder.encodeLoadMemReg(inst.operands[0].reg, inst.operands[3].value, inst.operands[1].reg, inst.operands[2].opBits, inst.emitFlags);
                break;
            case MicroOp::LoadMI:
                encoder.encodeLoadMemImm(inst.operands[0].reg, inst.operands[2].value, inst.operands[3].value, inst.operands[1].opBits, inst.emitFlags);
                break;
            case MicroOp::CmpRR:
                encoder.encodeCmpRegReg(inst.operands[0].reg, inst.operands[1].reg, inst.operands[2].opBits, inst.emitFlags);
                break;
            case MicroOp::CmpRI:
                encoder.encodeCmpRegImm(inst.operands[0].reg, inst.operands[2].value, inst.operands[1].opBits, inst.emitFlags);
                break;
            case MicroOp::CmpMR:
                encoder.encodeCmpMemReg(inst.operands[0].reg, inst.operands[3].value, inst.operands[1].reg, inst.operands[2].opBits, inst.emitFlags);
                break;
            case MicroOp::CmpMI:
                encoder.encodeCmpMemImm(inst.operands[0].reg, inst.operands[2].value, inst.operands[3].value, inst.operands[1].opBits, inst.emitFlags);
                break;
            case MicroOp::SetCondR:
                encoder.encodeSetCondReg(inst.operands[0].reg, inst.operands[1].cpuCond, inst.emitFlags);
                break;
            case MicroOp::LoadCondRR:
                encoder.encodeLoadCondRegReg(inst.operands[0].reg, inst.operands[1].reg, inst.operands[2].cpuCond, inst.operands[3].opBits, inst.emitFlags);
                break;
            case MicroOp::ClearR:
                encoder.encodeClearReg(inst.operands[0].reg, inst.operands[1].opBits, inst.emitFlags);
                break;
            case MicroOp::OpUnaryM:
                encoder.encodeOpUnaryMem(inst.operands[0].reg, inst.operands[3].value, inst.operands[2].cpuOp, inst.operands[1].opBits, inst.emitFlags);
                break;
            case MicroOp::OpUnaryR:
                encoder.encodeOpUnaryReg(inst.operands[0].reg, inst.operands[2].cpuOp, inst.operands[1].opBits, inst.emitFlags);
                break;
            case MicroOp::OpBinaryRR:
                encoder.encodeOpBinaryRegReg(inst.operands[0].reg, inst.operands[1].reg, inst.operands[3].cpuOp, inst.operands[2].opBits, inst.emitFlags);
                break;
            case MicroOp::OpBinaryMR:
                encoder.encodeOpBinaryMemReg(inst.operands[0].reg, inst.operands[4].value, inst.operands[1].reg, inst.operands[3].cpuOp, inst.operands[2].opBits, inst.emitFlags);
                break;
            case MicroOp::OpBinaryRI:
                encoder.encodeOpBinaryRegImm(inst.operands[0].reg, inst.operands[3].value, inst.operands[2].cpuOp, inst.operands[1].opBits, inst.emitFlags);
                break;
            case MicroOp::OpBinaryMI:
                encoder.encodeOpBinaryMemImm(inst.operands[0].reg, inst.operands[3].value, inst.operands[4].value, inst.operands[2].cpuOp, inst.operands[1].opBits, inst.emitFlags);
                break;
            case MicroOp::OpBinaryRM:
                encoder.encodeOpBinaryRegMem(inst.operands[0].reg, inst.operands[1].reg, inst.operands[4].value, inst.operands[3].cpuOp, inst.operands[2].opBits, inst.emitFlags);
                break;
            case MicroOp::OpTernaryRRR:
                encoder.encodeOpTernaryRegRegReg(inst.operands[0].reg, inst.operands[1].reg, inst.operands[2].reg, inst.operands[4].cpuOp, inst.operands[3].opBits, inst.emitFlags);
                break;
            default:
                SWC_ASSERT(false);
                break;
        }
    }
}

SWC_END_NAMESPACE();
