#include "pch.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"

SWC_BEGIN_NAMESPACE();

MicroInstr& MicroInstrBuilder::addInstruction(MicroInstrKind op, EmitFlags emitFlags, uint8_t numOperands)
{
    instructions_.emplace_back();
    auto& inst     = instructions_.back();
    inst.op        = op;
    inst.emitFlags = emitFlags;
    inst.allocateOperands(numOperands);
    return inst;
}

EncodeResult MicroInstrBuilder::encodeLoadSymbolRelocAddress(MicroReg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::SymbolRelocAddr, emitFlags, 3);
    inst.ops[0].reg      = reg;
    inst.ops[1].valueU32 = symbolIndex;
    inst.ops[2].valueU32 = offset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadSymRelocValue(MicroReg reg, uint32_t symbolIndex, uint32_t offset, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::SymbolRelocValue, emitFlags, 4);
    inst.ops[0].reg      = reg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU32 = symbolIndex;
    inst.ops[3].valueU32 = offset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodePush(MicroReg reg, EmitFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrKind::Push, emitFlags, 1);
    inst.ops[0].reg  = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodePop(MicroReg reg, EmitFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrKind::Pop, emitFlags, 1);
    inst.ops[0].reg  = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeNop(EmitFlags emitFlags)
{
    addInstruction(MicroInstrKind::Nop, emitFlags, 0);
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeRet(EmitFlags emitFlags)
{
    addInstruction(MicroInstrKind::Ret, emitFlags, 0);
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCallLocal(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::CallLocal, emitFlags, 2);
    inst.ops[0].name     = symbolName;
    inst.ops[1].callConv = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCallExtern(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::CallExtern, emitFlags, 2);
    inst.ops[0].name     = symbolName;
    inst.ops[1].callConv = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCallReg(MicroReg reg, const CallConv* callConv, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::CallIndirect, emitFlags, 2);
    inst.ops[0].reg      = reg;
    inst.ops[1].callConv = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::JumpTable, emitFlags, 5);
    inst.ops[0].reg      = tableReg;
    inst.ops[1].reg      = offsetReg;
    inst.ops[2].valueI32 = currentIp;
    inst.ops[3].valueU32 = offsetTable;
    inst.ops[4].valueU32 = numEntries;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeJump(MicroJump& jump, MicroCondJump jumpType, MicroOpBits opBits, EmitFlags emitFlags)
{
    jump.offsetStart     = instructions_.size() * sizeof(MicroInstr);
    jump.opBits          = opBits;
    const auto& inst     = addInstruction(MicroInstrKind::JumpCond, emitFlags, 2);
    inst.ops[0].jumpType = jumpType;
    inst.ops[1].opBits   = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodePatchJump(const MicroJump& jump, uint64_t offsetDestination, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::PatchJump, emitFlags, 3);
    inst.ops[0].valueU64 = jump.offsetStart;
    inst.ops[1].valueU64 = offsetDestination;
    inst.ops[2].valueU64 = 1;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodePatchJump(const MicroJump& jump, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::PatchJump, emitFlags, 3);
    inst.ops[0].valueU64 = jump.offsetStart;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeJumpReg(MicroReg reg, EmitFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrKind::JumpM, emitFlags, 1);
    inst.ops[0].reg  = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::LoadRM, emitFlags, 4);
    inst.ops[0].reg      = reg;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::LoadRI, emitFlags, 3);
    inst.ops[0].reg      = reg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstrKind::LoadRR, emitFlags, 3);
    inst.ops[0].reg    = regDst;
    inst.ops[1].reg    = regSrc;
    inst.ops[2].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::LoadSignedExtRM, emitFlags, 5);
    inst.ops[0].reg      = reg;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = numBitsDst;
    inst.ops[3].opBits   = numBitsSrc;
    inst.ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstrKind::LoadSignedExtRR, emitFlags, 4);
    inst.ops[0].reg    = regDst;
    inst.ops[1].reg    = regSrc;
    inst.ops[2].opBits = numBitsDst;
    inst.ops[3].opBits = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::LoadZeroExtRM, emitFlags, 5);
    inst.ops[0].reg      = reg;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = numBitsDst;
    inst.ops[3].opBits   = numBitsSrc;
    inst.ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstrKind::LoadZeroExtRR, emitFlags, 4);
    inst.ops[0].reg    = regDst;
    inst.ops[1].reg    = regSrc;
    inst.ops[2].opBits = numBitsDst;
    inst.ops[3].opBits = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::LoadAddrRM, emitFlags, 4);
    inst.ops[0].reg      = reg;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::LoadAmcRM, emitFlags, 8);
    inst.ops[0].reg      = regDst;
    inst.ops[1].reg      = regBase;
    inst.ops[2].reg      = regMul;
    inst.ops[3].opBits   = opBitsDst;
    inst.ops[4].opBits   = opBitsSrc;
    inst.ops[5].valueU64 = mulValue;
    inst.ops[6].valueU64 = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::LoadAmcMR, emitFlags, 8);
    inst.ops[0].reg      = regBase;
    inst.ops[1].reg      = regMul;
    inst.ops[2].reg      = regSrc;
    inst.ops[3].opBits   = opBitsBaseMul;
    inst.ops[4].opBits   = opBitsSrc;
    inst.ops[5].valueU64 = mulValue;
    inst.ops[6].valueU64 = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::LoadAmcMI, emitFlags, 8);
    inst.ops[0].reg      = regBase;
    inst.ops[1].reg      = regMul;
    inst.ops[3].opBits   = opBitsBaseMul;
    inst.ops[4].opBits   = opBitsValue;
    inst.ops[5].valueU64 = mulValue;
    inst.ops[6].valueU64 = addValue;
    inst.ops[7].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::LoadAddrAmcRM, emitFlags, 8);
    inst.ops[0].reg      = regDst;
    inst.ops[1].reg      = regBase;
    inst.ops[2].reg      = regMul;
    inst.ops[3].opBits   = opBitsDst;
    inst.ops[4].opBits   = opBitsValue;
    inst.ops[5].valueU64 = mulValue;
    inst.ops[6].valueU64 = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::LoadMR, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].reg      = reg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::LoadMI, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU64 = memOffset;
    inst.ops[3].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstrKind::CmpRR, emitFlags, 3);
    inst.ops[0].reg    = reg0;
    inst.ops[1].reg    = reg1;
    inst.ops[2].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::CmpMR, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].reg      = reg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::CmpMI, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU64 = memOffset;
    inst.ops[3].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCmpRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::CmpRI, emitFlags, 3);
    inst.ops[0].reg      = reg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeSetCondReg(MicroReg reg, MicroCond cpuCond, EmitFlags emitFlags)
{
    const auto& inst    = addInstruction(MicroInstrKind::SetCondR, emitFlags, 2);
    inst.ops[0].reg     = reg;
    inst.ops[1].cpuCond = cpuCond;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst    = addInstruction(MicroInstrKind::LoadCondRR, emitFlags, 4);
    inst.ops[0].reg     = regDst;
    inst.ops[1].reg     = regSrc;
    inst.ops[2].cpuCond = setType;
    inst.ops[3].opBits  = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeClearReg(MicroReg reg, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstrKind::ClearR, emitFlags, 2);
    inst.ops[0].reg    = reg;
    inst.ops[1].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::OpUnaryM, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].cpuOp    = op;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstrKind::OpUnaryR, emitFlags, 3);
    inst.ops[0].reg    = reg;
    inst.ops[1].opBits = opBits;
    inst.ops[2].cpuOp  = op;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstrKind::OpBinaryRR, emitFlags, 4);
    inst.ops[0].reg    = regDst;
    inst.ops[1].reg    = regSrc;
    inst.ops[2].opBits = opBits;
    inst.ops[3].cpuOp  = op;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::OpBinaryRM, emitFlags, 5);
    inst.ops[0].reg      = regDst;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].cpuOp    = op;
    inst.ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::OpBinaryMR, emitFlags, 5);
    inst.ops[0].reg      = memReg;
    inst.ops[1].reg      = reg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].cpuOp    = op;
    inst.ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::OpBinaryRI, emitFlags, 4);
    inst.ops[0].reg      = reg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].cpuOp    = op;
    inst.ops[3].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrKind::OpBinaryMI, emitFlags, 5);
    inst.ops[0].reg      = memReg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].cpuOp    = op;
    inst.ops[3].valueU64 = memOffset;
    inst.ops[4].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstrKind::OpTernaryRRR, emitFlags, 5);
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
        constexpr uint64_t stride = sizeof(MicroInstr);
        if (valueA % stride == 0)
            return valueA / stride;
        return valueA;
    }
}

void MicroInstrBuilder::encodeInstruction(Encoder& encoder, const MicroInstr& inst, size_t idx)
{
    switch (inst.op)
    {
        case MicroInstrKind::End:
            break;

        case MicroInstrKind::Ignore:
        case MicroInstrKind::Label:
        case MicroInstrKind::Debug:
            break;

        case MicroInstrKind::Enter:
        case MicroInstrKind::Leave:
        case MicroInstrKind::LoadCallParam:
        case MicroInstrKind::LoadCallAddrParam:
        case MicroInstrKind::LoadCallZeroExtParam:
        case MicroInstrKind::StoreCallParam:
            SWC_ASSERT(false);
            break;

        case MicroInstrKind::SymbolRelocAddr:
            encoder.encodeLoadSymbolRelocAddress(inst.ops[0].reg, inst.ops[1].valueU32, inst.ops[2].valueU32, inst.emitFlags);
            break;
        case MicroInstrKind::SymbolRelocValue:
            encoder.encodeLoadSymRelocValue(inst.ops[0].reg, inst.ops[2].valueU32, inst.ops[3].valueU32, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::Push:
            encoder.encodePush(inst.ops[0].reg, inst.emitFlags);
            break;
        case MicroInstrKind::Pop:
            encoder.encodePop(inst.ops[0].reg, inst.emitFlags);
            break;
        case MicroInstrKind::Nop:
            encoder.encodeNop(inst.emitFlags);
            break;
        case MicroInstrKind::Ret:
            encoder.encodeRet(inst.emitFlags);
            break;
        case MicroInstrKind::CallLocal:
            encoder.encodeCallLocal(inst.ops[0].name, inst.ops[1].callConv, inst.emitFlags);
            break;
        case MicroInstrKind::CallExtern:
            encoder.encodeCallExtern(inst.ops[0].name, inst.ops[1].callConv, inst.emitFlags);
            break;
        case MicroInstrKind::CallIndirect:
            encoder.encodeCallReg(inst.ops[0].reg, inst.ops[1].callConv, inst.emitFlags);
            break;
        case MicroInstrKind::JumpTable:
            encoder.encodeJumpTable(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].valueI32, inst.ops[3].valueU32, inst.ops[4].valueU32, inst.emitFlags);
            break;
        case MicroInstrKind::JumpCond:
        {
            MicroJump jump;
            encoder.encodeJump(jump, inst.ops[0].jumpType, inst.ops[1].opBits, inst.emitFlags);
            jumps_[idx]     = jump;
            jumpValid_[idx] = true;
            break;
        }
        case MicroInstrKind::PatchJump:
        {
            const size_t jumpIndex = resolveJumpIndex(inst.ops[0].valueU64);
            SWC_ASSERT(jumpIndex < jumpValid_.size());
            SWC_ASSERT(jumpValid_[jumpIndex]);
            if (inst.ops[2].valueU64 == 1)
                encoder.encodePatchJump(jumps_[jumpIndex], inst.ops[1].valueU64, inst.emitFlags);
            else
                encoder.encodePatchJump(jumps_[jumpIndex], inst.emitFlags);
            break;
        }
        case MicroInstrKind::JumpCondI:
        {
            MicroJump  jump;
            const auto opBits = inst.ops[1].opBits == MicroOpBits::Zero ? MicroOpBits::B32 : inst.ops[1].opBits;
            encoder.encodeJump(jump, inst.ops[0].jumpType, opBits, inst.emitFlags);
            encoder.encodePatchJump(jump, inst.ops[2].valueU64, inst.emitFlags);
            break;
        }
        case MicroInstrKind::JumpM:
            encoder.encodeJumpReg(inst.ops[0].reg, inst.emitFlags);
            break;
        case MicroInstrKind::LoadRR:
            encoder.encodeLoadRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::LoadRI:
            encoder.encodeLoadRegImm(inst.ops[0].reg, inst.ops[2].valueU64, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::LoadRM:
            encoder.encodeLoadRegMem(inst.ops[0].reg, inst.ops[1].reg, inst.ops[3].valueU64, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::LoadSignedExtRM:
            encoder.encodeLoadSignedExtendRegMem(inst.ops[0].reg, inst.ops[1].reg, inst.ops[4].valueU64, inst.ops[2].opBits, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::LoadSignedExtRR:
            encoder.encodeLoadSignedExtendRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].opBits, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::LoadZeroExtRM:
            encoder.encodeLoadZeroExtendRegMem(inst.ops[0].reg, inst.ops[1].reg, inst.ops[4].valueU64, inst.ops[2].opBits, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::LoadZeroExtRR:
            encoder.encodeLoadZeroExtendRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].opBits, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::LoadAddrRM:
            encoder.encodeLoadAddressRegMem(inst.ops[0].reg, inst.ops[1].reg, inst.ops[3].valueU64, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::LoadAmcMR:
            encoder.encodeLoadAmcMemReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[5].valueU64, inst.ops[6].valueU64, inst.ops[3].opBits, inst.ops[2].reg, inst.ops[4].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::LoadAmcMI:
            encoder.encodeLoadAmcMemImm(inst.ops[0].reg, inst.ops[1].reg, inst.ops[5].valueU64, inst.ops[6].valueU64, inst.ops[3].opBits, inst.ops[7].valueU64, inst.ops[4].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::LoadAmcRM:
            encoder.encodeLoadAmcRegMem(inst.ops[0].reg, inst.ops[3].opBits, inst.ops[1].reg, inst.ops[2].reg, inst.ops[5].valueU64, inst.ops[6].valueU64, inst.ops[4].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::LoadAddrAmcRM:
            encoder.encodeLoadAddressAmcRegMem(inst.ops[0].reg, inst.ops[3].opBits, inst.ops[1].reg, inst.ops[2].reg, inst.ops[5].valueU64, inst.ops[6].valueU64, inst.ops[4].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::LoadMR:
            encoder.encodeLoadMemReg(inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[1].reg, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::LoadMI:
            encoder.encodeLoadMemImm(inst.ops[0].reg, inst.ops[2].valueU64, inst.ops[3].valueU64, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::CmpRR:
            encoder.encodeCmpRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::CmpRI:
            encoder.encodeCmpRegImm(inst.ops[0].reg, inst.ops[2].valueU64, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::CmpMR:
            encoder.encodeCmpMemReg(inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[1].reg, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::CmpMI:
            encoder.encodeCmpMemImm(inst.ops[0].reg, inst.ops[2].valueU64, inst.ops[3].valueU64, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::SetCondR:
            encoder.encodeSetCondReg(inst.ops[0].reg, inst.ops[1].cpuCond, inst.emitFlags);
            break;
        case MicroInstrKind::LoadCondRR:
            encoder.encodeLoadCondRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].cpuCond, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::ClearR:
            encoder.encodeClearReg(inst.ops[0].reg, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::OpUnaryM:
            encoder.encodeOpUnaryMem(inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[2].cpuOp, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::OpUnaryR:
            encoder.encodeOpUnaryReg(inst.ops[0].reg, inst.ops[2].cpuOp, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::OpBinaryRR:
            encoder.encodeOpBinaryRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[3].cpuOp, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::OpBinaryMR:
            encoder.encodeOpBinaryMemReg(inst.ops[0].reg, inst.ops[4].valueU64, inst.ops[1].reg, inst.ops[3].cpuOp, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::OpBinaryRI:
            encoder.encodeOpBinaryRegImm(inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[2].cpuOp, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::OpBinaryMI:
            encoder.encodeOpBinaryMemImm(inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[4].valueU64, inst.ops[2].cpuOp, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::OpBinaryRM:
            encoder.encodeOpBinaryRegMem(inst.ops[0].reg, inst.ops[1].reg, inst.ops[4].valueU64, inst.ops[3].cpuOp, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrKind::OpTernaryRRR:
            encoder.encodeOpTernaryRegRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].reg, inst.ops[4].cpuOp, inst.ops[3].opBits, inst.emitFlags);
            break;
        default:
            SWC_ASSERT(false);
            break;
    }
}

void MicroInstrBuilder::encode(Encoder& encoder)
{
    SWC_ASSERT(jumps_.empty());
    jumps_.reserve(instructions_.size());
    jumpValid_.reserve(instructions_.size());

    for (size_t idx = 0; idx < instructions_.size(); ++idx)
    {
        const auto& inst = instructions_[idx];
        if (inst.op == MicroInstrKind::End)
            break;
        encodeInstruction(encoder, inst, idx);
    }
}

SWC_END_NAMESPACE();
