#include "pch.h"
#include "Backend/MachineCode/Encoder/Micro/MicroEncoder.h"

SWC_BEGIN_NAMESPACE();

MicroInstruction& MicroEncoder::addInstruction(MicroOp op, EmitFlags emitFlags, uint8_t numOperands)
{
    instructions_.emplace_back();
    auto& inst     = instructions_.back();
    inst.op        = op;
    inst.emitFlags = emitFlags;
    inst.allocateOperands(numOperands);
    return inst;
}

EncodeResult MicroEncoder::encodeLoadSymbolRelocAddress(TaskContext&, CpuReg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::SymbolRelocAddr, emitFlags, 3);
    inst.ops[0].reg      = reg;
    inst.ops[1].valueU32 = symbolIndex;
    inst.ops[2].valueU32 = offset;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeLoadSymRelocValue(TaskContext&, CpuReg reg, uint32_t symbolIndex, uint32_t offset, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::SymbolRelocValue, emitFlags, 4);
    inst.ops[0].reg      = reg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU32 = symbolIndex;
    inst.ops[3].valueU32 = offset;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodePush(TaskContext&, CpuReg reg, EmitFlags emitFlags)
{
    const auto& inst = addInstruction(MicroOp::Push, emitFlags, 1);
    inst.ops[0].reg  = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodePop(TaskContext&, CpuReg reg, EmitFlags emitFlags)
{
    const auto& inst = addInstruction(MicroOp::Pop, emitFlags, 1);
    inst.ops[0].reg  = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeNop(TaskContext&, EmitFlags emitFlags)
{
    addInstruction(MicroOp::Nop, emitFlags, 0);
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeRet(TaskContext&, EmitFlags emitFlags)
{
    addInstruction(MicroOp::Ret, emitFlags, 0);
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeCallLocal(TaskContext&, IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::CallLocal, emitFlags, 2);
    inst.ops[0].name     = symbolName;
    inst.ops[1].callConv = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeCallExtern(TaskContext&, IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::CallExtern, emitFlags, 2);
    inst.ops[0].name     = symbolName;
    inst.ops[1].callConv = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeCallReg(TaskContext&, CpuReg reg, const CallConv* callConv, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::CallIndirect, emitFlags, 2);
    inst.ops[0].reg      = reg;
    inst.ops[1].callConv = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeJumpTable(TaskContext&, CpuReg tableReg, CpuReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::JumpTable, emitFlags, 5);
    inst.ops[0].reg      = tableReg;
    inst.ops[1].reg      = offsetReg;
    inst.ops[2].valueI32 = currentIp;
    inst.ops[3].valueU32 = offsetTable;
    inst.ops[4].valueU32 = numEntries;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeJump(TaskContext&, CpuJump& jump, CpuCondJump jumpType, CpuOpBits opBits, EmitFlags emitFlags)
{
    jump.offsetStart     = instructions_.size() * sizeof(MicroInstruction);
    jump.opBits          = opBits;
    const auto& inst     = addInstruction(MicroOp::JumpCond, emitFlags, 2);
    inst.ops[0].jumpType = jumpType;
    inst.ops[1].opBits   = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodePatchJump(TaskContext&, const CpuJump& jump, uint64_t offsetDestination, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::PatchJump, emitFlags, 3);
    inst.ops[0].valueU64 = jump.offsetStart;
    inst.ops[1].valueU64 = offsetDestination;
    inst.ops[2].valueU64 = 1;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodePatchJump(TaskContext&, const CpuJump& jump, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::PatchJump, emitFlags, 3);
    inst.ops[0].valueU64 = jump.offsetStart;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeJumpReg(TaskContext&, CpuReg reg, EmitFlags emitFlags)
{
    const auto& inst = addInstruction(MicroOp::JumpM, emitFlags, 1);
    inst.ops[0].reg  = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeLoadRegMem(TaskContext&, CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::LoadRM, emitFlags, 4);
    inst.ops[0].reg      = reg;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeLoadRegImm(TaskContext&, CpuReg reg, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::LoadRI, emitFlags, 3);
    inst.ops[0].reg      = reg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeLoadRegReg(TaskContext&, CpuReg regDst, CpuReg regSrc, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroOp::LoadRR, emitFlags, 3);
    inst.ops[0].reg    = regDst;
    inst.ops[1].reg    = regSrc;
    inst.ops[2].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeLoadSignedExtendRegMem(TaskContext&, CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::LoadSignedExtRM, emitFlags, 5);
    inst.ops[0].reg      = reg;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = numBitsDst;
    inst.ops[3].opBits   = numBitsSrc;
    inst.ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeLoadSignedExtendRegReg(TaskContext&, CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroOp::LoadSignedExtRR, emitFlags, 4);
    inst.ops[0].reg    = regDst;
    inst.ops[1].reg    = regSrc;
    inst.ops[2].opBits = numBitsDst;
    inst.ops[3].opBits = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeLoadZeroExtendRegMem(TaskContext&, CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::LoadZeroExtRM, emitFlags, 5);
    inst.ops[0].reg      = reg;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = numBitsDst;
    inst.ops[3].opBits   = numBitsSrc;
    inst.ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeLoadZeroExtendRegReg(TaskContext&, CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroOp::LoadZeroExtRR, emitFlags, 4);
    inst.ops[0].reg    = regDst;
    inst.ops[1].reg    = regSrc;
    inst.ops[2].opBits = numBitsDst;
    inst.ops[3].opBits = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeLoadAddressRegMem(TaskContext&, CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::LoadAddrRM, emitFlags, 4);
    inst.ops[0].reg      = reg;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeLoadAmcRegMem(TaskContext&, CpuReg regDst, CpuOpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsSrc, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::LoadAmcRM, emitFlags, 8);
    inst.ops[0].reg      = regDst;
    inst.ops[1].reg      = regBase;
    inst.ops[2].reg      = regMul;
    inst.ops[3].opBits   = opBitsDst;
    inst.ops[4].opBits   = opBitsSrc;
    inst.ops[5].valueU64 = mulValue;
    inst.ops[6].valueU64 = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeLoadAmcMemReg(TaskContext&, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsBaseMul, CpuReg regSrc, CpuOpBits opBitsSrc, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::LoadAmcMR, emitFlags, 8);
    inst.ops[0].reg      = regBase;
    inst.ops[1].reg      = regMul;
    inst.ops[2].reg      = regSrc;
    inst.ops[3].opBits   = opBitsBaseMul;
    inst.ops[4].opBits   = opBitsSrc;
    inst.ops[5].valueU64 = mulValue;
    inst.ops[6].valueU64 = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeLoadAmcMemImm(TaskContext&, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsBaseMul, uint64_t value, CpuOpBits opBitsValue, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::LoadAmcMI, emitFlags, 8);
    inst.ops[0].reg      = regBase;
    inst.ops[1].reg      = regMul;
    inst.ops[3].opBits   = opBitsBaseMul;
    inst.ops[4].opBits   = opBitsValue;
    inst.ops[5].valueU64 = mulValue;
    inst.ops[6].valueU64 = addValue;
    inst.ops[7].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeLoadAddressAmcRegMem(TaskContext&, CpuReg regDst, CpuOpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsValue, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::LoadAddrAmcRM, emitFlags, 8);
    inst.ops[0].reg      = regDst;
    inst.ops[1].reg      = regBase;
    inst.ops[2].reg      = regMul;
    inst.ops[3].opBits   = opBitsDst;
    inst.ops[4].opBits   = opBitsValue;
    inst.ops[5].valueU64 = mulValue;
    inst.ops[6].valueU64 = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeLoadMemReg(TaskContext&, CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::LoadMR, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].reg      = reg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeLoadMemImm(TaskContext&, CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::LoadMI, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU64 = memOffset;
    inst.ops[3].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeCmpRegReg(TaskContext&, CpuReg reg0, CpuReg reg1, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroOp::CmpRR, emitFlags, 3);
    inst.ops[0].reg    = reg0;
    inst.ops[1].reg    = reg1;
    inst.ops[2].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeCmpMemReg(TaskContext&, CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::CmpMR, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].reg      = reg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeCmpMemImm(TaskContext&, CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::CmpMI, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU64 = memOffset;
    inst.ops[3].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeCmpRegImm(TaskContext&, CpuReg reg, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::CmpRI, emitFlags, 3);
    inst.ops[0].reg      = reg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeSetCondReg(TaskContext&, CpuReg reg, CpuCond cpuCond, EmitFlags emitFlags)
{
    const auto& inst    = addInstruction(MicroOp::SetCondR, emitFlags, 2);
    inst.ops[0].reg     = reg;
    inst.ops[1].cpuCond = cpuCond;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeLoadCondRegReg(TaskContext&, CpuReg regDst, CpuReg regSrc, CpuCond setType, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst    = addInstruction(MicroOp::LoadCondRR, emitFlags, 4);
    inst.ops[0].reg     = regDst;
    inst.ops[1].reg     = regSrc;
    inst.ops[2].cpuCond = setType;
    inst.ops[3].opBits  = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeClearReg(TaskContext&, CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroOp::ClearR, emitFlags, 2);
    inst.ops[0].reg    = reg;
    inst.ops[1].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeOpUnaryMem(TaskContext&, CpuReg memReg, uint64_t memOffset, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::OpUnaryM, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].cpuOp    = op;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeOpUnaryReg(TaskContext&, CpuReg reg, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroOp::OpUnaryR, emitFlags, 3);
    inst.ops[0].reg    = reg;
    inst.ops[1].opBits = opBits;
    inst.ops[2].cpuOp  = op;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeOpBinaryRegReg(TaskContext&, CpuReg regDst, CpuReg regSrc, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroOp::OpBinaryRR, emitFlags, 4);
    inst.ops[0].reg    = regDst;
    inst.ops[1].reg    = regSrc;
    inst.ops[2].opBits = opBits;
    inst.ops[3].cpuOp  = op;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeOpBinaryRegMem(TaskContext&, CpuReg regDst, CpuReg memReg, uint64_t memOffset, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::OpBinaryRM, emitFlags, 5);
    inst.ops[0].reg      = regDst;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].cpuOp    = op;
    inst.ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeOpBinaryMemReg(TaskContext&, CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::OpBinaryMR, emitFlags, 5);
    inst.ops[0].reg      = memReg;
    inst.ops[1].reg      = reg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].cpuOp    = op;
    inst.ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeOpBinaryRegImm(TaskContext&, CpuReg reg, uint64_t value, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::OpBinaryRI, emitFlags, 4);
    inst.ops[0].reg      = reg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].cpuOp    = op;
    inst.ops[3].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeOpBinaryMemImm(TaskContext&, CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::OpBinaryMI, emitFlags, 5);
    inst.ops[0].reg      = memReg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].cpuOp    = op;
    inst.ops[3].valueU64 = memOffset;
    inst.ops[4].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroEncoder::encodeOpTernaryRegRegReg(TaskContext&, CpuReg reg0, CpuReg reg1, CpuReg reg2, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroOp::OpTernaryRRR, emitFlags, 5);
    inst.ops[0].reg    = reg0;
    inst.ops[1].reg    = reg1;
    inst.ops[2].reg    = reg2;
    inst.ops[3].opBits = opBits;
    inst.ops[4].cpuOp  = op;
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

void MicroEncoder::encodeInstruction(Encoder& encoder, const MicroInstruction& inst, size_t idx)
{
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
            encoder.encodeLoadSymbolRelocAddress(encoder.ctx(), inst.ops[0].reg, inst.ops[1].valueU32, inst.ops[2].valueU32, inst.emitFlags);
            break;
        case MicroOp::SymbolRelocValue:
            encoder.encodeLoadSymRelocValue(encoder.ctx(), inst.ops[0].reg, inst.ops[2].valueU32, inst.ops[3].valueU32, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroOp::Push:
            encoder.encodePush(encoder.ctx(), inst.ops[0].reg, inst.emitFlags);
            break;
        case MicroOp::Pop:
            encoder.encodePop(encoder.ctx(), inst.ops[0].reg, inst.emitFlags);
            break;
        case MicroOp::Nop:
            encoder.encodeNop(encoder.ctx(), inst.emitFlags);
            break;
        case MicroOp::Ret:
            encoder.encodeRet(encoder.ctx(), inst.emitFlags);
            break;
        case MicroOp::CallLocal:
            encoder.encodeCallLocal(encoder.ctx(), inst.ops[0].name, inst.ops[1].callConv, inst.emitFlags);
            break;
        case MicroOp::CallExtern:
            encoder.encodeCallExtern(encoder.ctx(), inst.ops[0].name, inst.ops[1].callConv, inst.emitFlags);
            break;
        case MicroOp::CallIndirect:
            encoder.encodeCallReg(encoder.ctx(), inst.ops[0].reg, inst.ops[1].callConv, inst.emitFlags);
            break;
        case MicroOp::JumpTable:
            encoder.encodeJumpTable(encoder.ctx(), inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].valueI32, inst.ops[3].valueU32, inst.ops[4].valueU32, inst.emitFlags);
            break;
        case MicroOp::JumpCond:
        {
            CpuJump jump;
            encoder.encodeJump(encoder.ctx(), jump, inst.ops[0].jumpType, inst.ops[1].opBits, inst.emitFlags);
            jumps_[idx]     = jump;
            jumpValid_[idx] = true;
            break;
        }
        case MicroOp::PatchJump:
        {
            const size_t jumpIndex = resolveJumpIndex(inst.ops[0].valueU64);
            SWC_ASSERT(jumpIndex < jumpValid_.size());
            SWC_ASSERT(jumpValid_[jumpIndex]);
            if (inst.ops[2].valueU64 == 1)
                encoder.encodePatchJump(encoder.ctx(), jumps_[jumpIndex], inst.ops[1].valueU64, inst.emitFlags);
            else
                encoder.encodePatchJump(encoder.ctx(), jumps_[jumpIndex], inst.emitFlags);
            break;
        }
        case MicroOp::JumpCondI:
        {
            CpuJump    jump;
            const auto opBits = inst.ops[1].opBits == CpuOpBits::Zero ? CpuOpBits::B32 : inst.ops[1].opBits;
            encoder.encodeJump(encoder.ctx(), jump, inst.ops[0].jumpType, opBits, inst.emitFlags);
            encoder.encodePatchJump(encoder.ctx(), jump, inst.ops[2].valueU64, inst.emitFlags);
            break;
        }
        case MicroOp::JumpM:
            encoder.encodeJumpReg(encoder.ctx(), inst.ops[0].reg, inst.emitFlags);
            break;
        case MicroOp::LoadRR:
            encoder.encodeLoadRegReg(encoder.ctx(), inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadRI:
            encoder.encodeLoadRegImm(encoder.ctx(), inst.ops[0].reg, inst.ops[2].valueU64, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadRM:
            encoder.encodeLoadRegMem(encoder.ctx(), inst.ops[0].reg, inst.ops[1].reg, inst.ops[3].valueU64, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadSignedExtRM:
            encoder.encodeLoadSignedExtendRegMem(encoder.ctx(), inst.ops[0].reg, inst.ops[1].reg, inst.ops[4].valueU64, inst.ops[2].opBits, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadSignedExtRR:
            encoder.encodeLoadSignedExtendRegReg(encoder.ctx(), inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].opBits, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadZeroExtRM:
            encoder.encodeLoadZeroExtendRegMem(encoder.ctx(), inst.ops[0].reg, inst.ops[1].reg, inst.ops[4].valueU64, inst.ops[2].opBits, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadZeroExtRR:
            encoder.encodeLoadZeroExtendRegReg(encoder.ctx(), inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].opBits, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadAddrRM:
            encoder.encodeLoadAddressRegMem(encoder.ctx(), inst.ops[0].reg, inst.ops[1].reg, inst.ops[3].valueU64, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadAmcMR:
            encoder.encodeLoadAmcMemReg(encoder.ctx(), inst.ops[0].reg, inst.ops[1].reg, inst.ops[5].valueU64, inst.ops[6].valueU64, inst.ops[3].opBits, inst.ops[2].reg, inst.ops[4].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadAmcMI:
            encoder.encodeLoadAmcMemImm(encoder.ctx(), inst.ops[0].reg, inst.ops[1].reg, inst.ops[5].valueU64, inst.ops[6].valueU64, inst.ops[3].opBits, inst.ops[7].valueU64, inst.ops[4].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadAmcRM:
            encoder.encodeLoadAmcRegMem(encoder.ctx(), inst.ops[0].reg, inst.ops[3].opBits, inst.ops[1].reg, inst.ops[2].reg, inst.ops[5].valueU64, inst.ops[6].valueU64, inst.ops[4].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadAddrAmcRM:
            encoder.encodeLoadAddressAmcRegMem(encoder.ctx(), inst.ops[0].reg, inst.ops[3].opBits, inst.ops[1].reg, inst.ops[2].reg, inst.ops[5].valueU64, inst.ops[6].valueU64, inst.ops[4].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadMR:
            encoder.encodeLoadMemReg(encoder.ctx(), inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[1].reg, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadMI:
            encoder.encodeLoadMemImm(encoder.ctx(), inst.ops[0].reg, inst.ops[2].valueU64, inst.ops[3].valueU64, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroOp::CmpRR:
            encoder.encodeCmpRegReg(encoder.ctx(), inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroOp::CmpRI:
            encoder.encodeCmpRegImm(encoder.ctx(), inst.ops[0].reg, inst.ops[2].valueU64, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroOp::CmpMR:
            encoder.encodeCmpMemReg(encoder.ctx(), inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[1].reg, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroOp::CmpMI:
            encoder.encodeCmpMemImm(encoder.ctx(), inst.ops[0].reg, inst.ops[2].valueU64, inst.ops[3].valueU64, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroOp::SetCondR:
            encoder.encodeSetCondReg(encoder.ctx(), inst.ops[0].reg, inst.ops[1].cpuCond, inst.emitFlags);
            break;
        case MicroOp::LoadCondRR:
            encoder.encodeLoadCondRegReg(encoder.ctx(), inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].cpuCond, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroOp::ClearR:
            encoder.encodeClearReg(encoder.ctx(), inst.ops[0].reg, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroOp::OpUnaryM:
            encoder.encodeOpUnaryMem(encoder.ctx(), inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[2].cpuOp, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroOp::OpUnaryR:
            encoder.encodeOpUnaryReg(encoder.ctx(), inst.ops[0].reg, inst.ops[2].cpuOp, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroOp::OpBinaryRR:
            encoder.encodeOpBinaryRegReg(encoder.ctx(), inst.ops[0].reg, inst.ops[1].reg, inst.ops[3].cpuOp, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroOp::OpBinaryMR:
            encoder.encodeOpBinaryMemReg(encoder.ctx(), inst.ops[0].reg, inst.ops[4].valueU64, inst.ops[1].reg, inst.ops[3].cpuOp, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroOp::OpBinaryRI:
            encoder.encodeOpBinaryRegImm(encoder.ctx(), inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[2].cpuOp, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroOp::OpBinaryMI:
            encoder.encodeOpBinaryMemImm(encoder.ctx(), inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[4].valueU64, inst.ops[2].cpuOp, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroOp::OpBinaryRM:
            encoder.encodeOpBinaryRegMem(encoder.ctx(), inst.ops[0].reg, inst.ops[1].reg, inst.ops[4].valueU64, inst.ops[3].cpuOp, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroOp::OpTernaryRRR:
            encoder.encodeOpTernaryRegRegReg(encoder.ctx(), inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].reg, inst.ops[4].cpuOp, inst.ops[3].opBits, inst.emitFlags);
            break;
        default:
            SWC_ASSERT(false);
            break;
    }
}

void MicroEncoder::encode(Encoder& encoder)
{
    SWC_ASSERT(jumps_.empty());
    jumps_.reserve(instructions_.size());
    jumpValid_.reserve(instructions_.size());

    for (size_t idx = 0; idx < instructions_.size(); ++idx)
    {
        const auto& inst = instructions_[idx];
        if (inst.op == MicroOp::End)
            break;
        encodeInstruction(encoder, inst, idx);
    }
}

SWC_END_NAMESPACE();
