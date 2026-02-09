#include "pch.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"

SWC_BEGIN_NAMESPACE();

MicroInstr& MicroInstrBuilder::addInstruction(MicroInstrOpcode op, EncodeFlags emitFlags, uint8_t numOperands)
{
    instructions_.emplace_back();
    auto& inst     = instructions_.back();
    inst.op        = op;
    inst.emitFlags = emitFlags;
    inst.allocateOperands(numOperands);
    return inst;
}

EncodeResult MicroInstrBuilder::encodeLoadSymbolRelocAddress(MicroReg reg, uint32_t symbolIndex, uint32_t offset, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::SymbolRelocAddr, emitFlags, 3);
    inst.ops[0].reg      = reg;
    inst.ops[1].valueU32 = symbolIndex;
    inst.ops[2].valueU32 = offset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadSymRelocValue(MicroReg reg, uint32_t symbolIndex, uint32_t offset, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::SymbolRelocValue, emitFlags, 4);
    inst.ops[0].reg      = reg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU32 = symbolIndex;
    inst.ops[3].valueU32 = offset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodePush(MicroReg reg, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::Push, emitFlags, 1);
    inst.ops[0].reg  = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodePop(MicroReg reg, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::Pop, emitFlags, 1);
    inst.ops[0].reg  = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeNop(EncodeFlags emitFlags)
{
    addInstruction(MicroInstrOpcode::Nop, emitFlags, 0);
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeRet(EncodeFlags emitFlags)
{
    addInstruction(MicroInstrOpcode::Ret, emitFlags, 0);
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCallLocal(IdentifierRef symbolName, const CallConv* callConv, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::CallLocal, emitFlags, 2);
    inst.ops[0].name     = symbolName;
    inst.ops[1].callConv = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCallExtern(IdentifierRef symbolName, const CallConv* callConv, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::CallExtern, emitFlags, 2);
    inst.ops[0].name     = symbolName;
    inst.ops[1].callConv = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCallReg(MicroReg reg, const CallConv* callConv, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::CallIndirect, emitFlags, 2);
    inst.ops[0].reg      = reg;
    inst.ops[1].callConv = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::JumpTable, emitFlags, 5);
    inst.ops[0].reg      = tableReg;
    inst.ops[1].reg      = offsetReg;
    inst.ops[2].valueI32 = currentIp;
    inst.ops[3].valueU32 = offsetTable;
    inst.ops[4].valueU32 = numEntries;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeJump(MicroJump& jump, MicroCondJump jumpType, MicroOpBits opBits, EncodeFlags emitFlags)
{
    jump.offsetStart     = instructions_.size() * sizeof(MicroInstr);
    jump.opBits          = opBits;
    const auto& inst     = addInstruction(MicroInstrOpcode::JumpCond, emitFlags, 2);
    inst.ops[0].jumpType = jumpType;
    inst.ops[1].opBits   = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodePatchJump(const MicroJump& jump, uint64_t offsetDestination, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::PatchJump, emitFlags, 3);
    inst.ops[0].valueU64 = jump.offsetStart;
    inst.ops[1].valueU64 = offsetDestination;
    inst.ops[2].valueU64 = 1;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodePatchJump(const MicroJump& jump, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::PatchJump, emitFlags, 3);
    inst.ops[0].valueU64 = jump.offsetStart;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeJumpReg(MicroReg reg, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::JumpReg, emitFlags, 1);
    inst.ops[0].reg  = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::LoadRegMem, emitFlags, 4);
    inst.ops[0].reg      = reg;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::LoadRegImm, emitFlags, 3);
    inst.ops[0].reg      = reg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstrOpcode::LoadRegReg, emitFlags, 3);
    inst.ops[0].reg    = regDst;
    inst.ops[1].reg    = regSrc;
    inst.ops[2].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::LoadSignedExtRegMem, emitFlags, 5);
    inst.ops[0].reg      = reg;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = numBitsDst;
    inst.ops[3].opBits   = numBitsSrc;
    inst.ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstrOpcode::LoadSignedExtRegReg, emitFlags, 4);
    inst.ops[0].reg    = regDst;
    inst.ops[1].reg    = regSrc;
    inst.ops[2].opBits = numBitsDst;
    inst.ops[3].opBits = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::LoadZeroExtRegMem, emitFlags, 5);
    inst.ops[0].reg      = reg;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = numBitsDst;
    inst.ops[3].opBits   = numBitsSrc;
    inst.ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstrOpcode::LoadZeroExtRegReg, emitFlags, 4);
    inst.ops[0].reg    = regDst;
    inst.ops[1].reg    = regSrc;
    inst.ops[2].opBits = numBitsDst;
    inst.ops[3].opBits = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::LoadAddrRegMem, emitFlags, 4);
    inst.ops[0].reg      = reg;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::LoadAmcRegMem, emitFlags, 8);
    inst.ops[0].reg      = regDst;
    inst.ops[1].reg      = regBase;
    inst.ops[2].reg      = regMul;
    inst.ops[3].opBits   = opBitsDst;
    inst.ops[4].opBits   = opBitsSrc;
    inst.ops[5].valueU64 = mulValue;
    inst.ops[6].valueU64 = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::LoadAmcMemReg, emitFlags, 8);
    inst.ops[0].reg      = regBase;
    inst.ops[1].reg      = regMul;
    inst.ops[2].reg      = regSrc;
    inst.ops[3].opBits   = opBitsBaseMul;
    inst.ops[4].opBits   = opBitsSrc;
    inst.ops[5].valueU64 = mulValue;
    inst.ops[6].valueU64 = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::LoadAmcMemImm, emitFlags, 8);
    inst.ops[0].reg      = regBase;
    inst.ops[1].reg      = regMul;
    inst.ops[3].opBits   = opBitsBaseMul;
    inst.ops[4].opBits   = opBitsValue;
    inst.ops[5].valueU64 = mulValue;
    inst.ops[6].valueU64 = addValue;
    inst.ops[7].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::LoadAddrAmcRegMem, emitFlags, 8);
    inst.ops[0].reg      = regDst;
    inst.ops[1].reg      = regBase;
    inst.ops[2].reg      = regMul;
    inst.ops[3].opBits   = opBitsDst;
    inst.ops[4].opBits   = opBitsValue;
    inst.ops[5].valueU64 = mulValue;
    inst.ops[6].valueU64 = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::LoadMemReg, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].reg      = reg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::LoadMemImm, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU64 = memOffset;
    inst.ops[3].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstrOpcode::CmpRegReg, emitFlags, 3);
    inst.ops[0].reg    = reg0;
    inst.ops[1].reg    = reg1;
    inst.ops[2].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::CmpMemReg, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].reg      = reg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::CmpMemImm, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU64 = memOffset;
    inst.ops[3].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCmpRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::CmpRegImm, emitFlags, 3);
    inst.ops[0].reg      = reg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeSetCondReg(MicroReg reg, MicroCond cpuCond, EncodeFlags emitFlags)
{
    const auto& inst    = addInstruction(MicroInstrOpcode::SetCondReg, emitFlags, 2);
    inst.ops[0].reg     = reg;
    inst.ops[1].cpuCond = cpuCond;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst    = addInstruction(MicroInstrOpcode::LoadCondRegReg, emitFlags, 4);
    inst.ops[0].reg     = regDst;
    inst.ops[1].reg     = regSrc;
    inst.ops[2].cpuCond = setType;
    inst.ops[3].opBits  = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeClearReg(MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstrOpcode::ClearReg, emitFlags, 2);
    inst.ops[0].reg    = reg;
    inst.ops[1].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::OpUnaryMem, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].cpuOp    = op;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstrOpcode::OpUnaryReg, emitFlags, 3);
    inst.ops[0].reg    = reg;
    inst.ops[1].opBits = opBits;
    inst.ops[2].cpuOp  = op;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstrOpcode::OpBinaryRegReg, emitFlags, 4);
    inst.ops[0].reg    = regDst;
    inst.ops[1].reg    = regSrc;
    inst.ops[2].opBits = opBits;
    inst.ops[3].cpuOp  = op;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::OpBinaryRegMem, emitFlags, 5);
    inst.ops[0].reg      = regDst;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].cpuOp    = op;
    inst.ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::OpBinaryMemReg, emitFlags, 5);
    inst.ops[0].reg      = memReg;
    inst.ops[1].reg      = reg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].cpuOp    = op;
    inst.ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::OpBinaryRegImm, emitFlags, 4);
    inst.ops[0].reg      = reg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].cpuOp    = op;
    inst.ops[3].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstrOpcode::OpBinaryMemImm, emitFlags, 5);
    inst.ops[0].reg      = memReg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].cpuOp    = op;
    inst.ops[3].valueU64 = memOffset;
    inst.ops[4].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstrOpcode::OpTernaryRegRegReg, emitFlags, 5);
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
            encoder.encodeLoadSymbolRelocAddress(inst.ops[0].reg, inst.ops[1].valueU32, inst.ops[2].valueU32, inst.emitFlags);
            break;
        case MicroInstrOpcode::SymbolRelocValue:
            encoder.encodeLoadSymRelocValue(inst.ops[0].reg, inst.ops[2].valueU32, inst.ops[3].valueU32, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::Push:
            encoder.encodePush(inst.ops[0].reg, inst.emitFlags);
            break;
        case MicroInstrOpcode::Pop:
            encoder.encodePop(inst.ops[0].reg, inst.emitFlags);
            break;
        case MicroInstrOpcode::Nop:
            encoder.encodeNop(inst.emitFlags);
            break;
        case MicroInstrOpcode::Ret:
            encoder.encodeRet(inst.emitFlags);
            break;
        case MicroInstrOpcode::CallLocal:
            encoder.encodeCallLocal(inst.ops[0].name, inst.ops[1].callConv, inst.emitFlags);
            break;
        case MicroInstrOpcode::CallExtern:
            encoder.encodeCallExtern(inst.ops[0].name, inst.ops[1].callConv, inst.emitFlags);
            break;
        case MicroInstrOpcode::CallIndirect:
            encoder.encodeCallReg(inst.ops[0].reg, inst.ops[1].callConv, inst.emitFlags);
            break;
        case MicroInstrOpcode::JumpTable:
            encoder.encodeJumpTable(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].valueI32, inst.ops[3].valueU32, inst.ops[4].valueU32, inst.emitFlags);
            break;
        case MicroInstrOpcode::JumpCond:
        {
            MicroJump jump;
            encoder.encodeJump(jump, inst.ops[0].jumpType, inst.ops[1].opBits, inst.emitFlags);
            jumps_[idx]     = jump;
            jumpValid_[idx] = true;
            break;
        }
        case MicroInstrOpcode::PatchJump:
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
        case MicroInstrOpcode::JumpCondImm:
        {
            MicroJump  jump;
            const auto opBits = inst.ops[1].opBits == MicroOpBits::Zero ? MicroOpBits::B32 : inst.ops[1].opBits;
            encoder.encodeJump(jump, inst.ops[0].jumpType, opBits, inst.emitFlags);
            encoder.encodePatchJump(jump, inst.ops[2].valueU64, inst.emitFlags);
            break;
        }
        case MicroInstrOpcode::JumpReg:
            encoder.encodeJumpReg(inst.ops[0].reg, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadRegReg:
            encoder.encodeLoadRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadRegImm:
            encoder.encodeLoadRegImm(inst.ops[0].reg, inst.ops[2].valueU64, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadRegMem:
            encoder.encodeLoadRegMem(inst.ops[0].reg, inst.ops[1].reg, inst.ops[3].valueU64, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadSignedExtRegMem:
            encoder.encodeLoadSignedExtendRegMem(inst.ops[0].reg, inst.ops[1].reg, inst.ops[4].valueU64, inst.ops[2].opBits, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadSignedExtRegReg:
            encoder.encodeLoadSignedExtendRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].opBits, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadZeroExtRegMem:
            encoder.encodeLoadZeroExtendRegMem(inst.ops[0].reg, inst.ops[1].reg, inst.ops[4].valueU64, inst.ops[2].opBits, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadZeroExtRegReg:
            encoder.encodeLoadZeroExtendRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].opBits, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadAddrRegMem:
            encoder.encodeLoadAddressRegMem(inst.ops[0].reg, inst.ops[1].reg, inst.ops[3].valueU64, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadAmcMemReg:
            encoder.encodeLoadAmcMemReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[5].valueU64, inst.ops[6].valueU64, inst.ops[3].opBits, inst.ops[2].reg, inst.ops[4].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadAmcMemImm:
            encoder.encodeLoadAmcMemImm(inst.ops[0].reg, inst.ops[1].reg, inst.ops[5].valueU64, inst.ops[6].valueU64, inst.ops[3].opBits, inst.ops[7].valueU64, inst.ops[4].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadAmcRegMem:
            encoder.encodeLoadAmcRegMem(inst.ops[0].reg, inst.ops[3].opBits, inst.ops[1].reg, inst.ops[2].reg, inst.ops[5].valueU64, inst.ops[6].valueU64, inst.ops[4].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadAddrAmcRegMem:
            encoder.encodeLoadAddressAmcRegMem(inst.ops[0].reg, inst.ops[3].opBits, inst.ops[1].reg, inst.ops[2].reg, inst.ops[5].valueU64, inst.ops[6].valueU64, inst.ops[4].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadMemReg:
            encoder.encodeLoadMemReg(inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[1].reg, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadMemImm:
            encoder.encodeLoadMemImm(inst.ops[0].reg, inst.ops[2].valueU64, inst.ops[3].valueU64, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::CmpRegReg:
            encoder.encodeCmpRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::CmpRegImm:
            encoder.encodeCmpRegImm(inst.ops[0].reg, inst.ops[2].valueU64, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::CmpMemReg:
            encoder.encodeCmpMemReg(inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[1].reg, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::CmpMemImm:
            encoder.encodeCmpMemImm(inst.ops[0].reg, inst.ops[2].valueU64, inst.ops[3].valueU64, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::SetCondReg:
            encoder.encodeSetCondReg(inst.ops[0].reg, inst.ops[1].cpuCond, inst.emitFlags);
            break;
        case MicroInstrOpcode::LoadCondRegReg:
            encoder.encodeLoadCondRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].cpuCond, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::ClearReg:
            encoder.encodeClearReg(inst.ops[0].reg, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpUnaryMem:
            encoder.encodeOpUnaryMem(inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[2].cpuOp, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpUnaryReg:
            encoder.encodeOpUnaryReg(inst.ops[0].reg, inst.ops[2].cpuOp, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpBinaryRegReg:
            encoder.encodeOpBinaryRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[3].cpuOp, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpBinaryMemReg:
            encoder.encodeOpBinaryMemReg(inst.ops[0].reg, inst.ops[4].valueU64, inst.ops[1].reg, inst.ops[3].cpuOp, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpBinaryRegImm:
            encoder.encodeOpBinaryRegImm(inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[2].cpuOp, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpBinaryMemImm:
            encoder.encodeOpBinaryMemImm(inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[4].valueU64, inst.ops[2].cpuOp, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpBinaryRegMem:
            encoder.encodeOpBinaryRegMem(inst.ops[0].reg, inst.ops[1].reg, inst.ops[4].valueU64, inst.ops[3].cpuOp, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpTernaryRegRegReg:
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
        if (inst.op == MicroInstrOpcode::End)
            break;
        encodeInstruction(encoder, inst, idx);
    }
}

SWC_END_NAMESPACE();


