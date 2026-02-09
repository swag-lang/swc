#include "pch.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"

SWC_BEGIN_NAMESPACE();

MicroInstr& MicroInstrBuilder::addInstruction(MicroInstrOpcode op, EncodeFlags emitFlags, uint8_t numOperands)
{
    auto [_, inst] = instructions_.emplaceUninit<MicroInstr>();
    ++instructionCount_;
    inst->op          = op;
    inst->emitFlags   = emitFlags;
    inst->numOperands = numOperands;
    if (numOperands)
    {
        auto [opsRef, ops] = operands_.emplaceUninitArray<MicroInstrOperand>(numOperands);
        inst->opsRef       = opsRef;
        for (uint8_t idx = 0; idx < numOperands; ++idx)
            new (ops + idx) MicroInstrOperand();
    }
    else
    {
        inst->opsRef = std::numeric_limits<Ref>::max();
    }
    return *inst;
}

EncodeResult MicroInstrBuilder::encodeLoadSymbolRelocAddress(MicroReg reg, uint32_t symbolIndex, uint32_t offset, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::SymbolRelocAddr, emitFlags, 3);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = reg;
    ops[1].valueU32 = symbolIndex;
    ops[2].valueU32 = offset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadSymRelocValue(MicroReg reg, uint32_t symbolIndex, uint32_t offset, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::SymbolRelocValue, emitFlags, 4);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = reg;
    ops[1].opBits   = opBits;
    ops[2].valueU32 = symbolIndex;
    ops[3].valueU32 = offset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodePush(MicroReg reg, EncodeFlags emitFlags)
{
    auto& inst = addInstruction(MicroInstrOpcode::Push, emitFlags, 1);
    auto* ops  = inst.ops(operands_);
    ops[0].reg = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodePop(MicroReg reg, EncodeFlags emitFlags)
{
    auto& inst = addInstruction(MicroInstrOpcode::Pop, emitFlags, 1);
    auto* ops  = inst.ops(operands_);
    ops[0].reg = reg;
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
    auto& inst      = addInstruction(MicroInstrOpcode::CallLocal, emitFlags, 2);
    auto* ops       = inst.ops(operands_);
    ops[0].name     = symbolName;
    ops[1].callConv = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCallExtern(IdentifierRef symbolName, const CallConv* callConv, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::CallExtern, emitFlags, 2);
    auto* ops       = inst.ops(operands_);
    ops[0].name     = symbolName;
    ops[1].callConv = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCallReg(MicroReg reg, const CallConv* callConv, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::CallIndirect, emitFlags, 2);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = reg;
    ops[1].callConv = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::JumpTable, emitFlags, 5);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = tableReg;
    ops[1].reg      = offsetReg;
    ops[2].valueI32 = currentIp;
    ops[3].valueU32 = offsetTable;
    ops[4].valueU32 = numEntries;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeJump(MicroJump& jump, MicroCondJump jumpType, MicroOpBits opBits, EncodeFlags emitFlags)
{
    jump.offsetStart = static_cast<uint64_t>(instructionCount_) * sizeof(MicroInstr);
    jump.opBits      = opBits;
    auto& inst       = addInstruction(MicroInstrOpcode::JumpCond, emitFlags, 2);
    auto* ops        = inst.ops(operands_);
    ops[0].jumpType  = jumpType;
    ops[1].opBits    = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodePatchJump(const MicroJump& jump, uint64_t offsetDestination, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::PatchJump, emitFlags, 3);
    auto* ops       = inst.ops(operands_);
    ops[0].valueU64 = jump.offsetStart;
    ops[1].valueU64 = offsetDestination;
    ops[2].valueU64 = 1;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodePatchJump(const MicroJump& jump, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::PatchJump, emitFlags, 3);
    auto* ops       = inst.ops(operands_);
    ops[0].valueU64 = jump.offsetStart;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeJumpReg(MicroReg reg, EncodeFlags emitFlags)
{
    auto& inst = addInstruction(MicroInstrOpcode::JumpReg, emitFlags, 1);
    auto* ops  = inst.ops(operands_);
    ops[0].reg = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::LoadRegMem, emitFlags, 4);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = reg;
    ops[1].reg      = memReg;
    ops[2].opBits   = opBits;
    ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::LoadRegImm, emitFlags, 3);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = reg;
    ops[1].opBits   = opBits;
    ops[2].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst    = addInstruction(MicroInstrOpcode::LoadRegReg, emitFlags, 3);
    auto* ops     = inst.ops(operands_);
    ops[0].reg    = regDst;
    ops[1].reg    = regSrc;
    ops[2].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::LoadSignedExtRegMem, emitFlags, 5);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = reg;
    ops[1].reg      = memReg;
    ops[2].opBits   = numBitsDst;
    ops[3].opBits   = numBitsSrc;
    ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    auto& inst    = addInstruction(MicroInstrOpcode::LoadSignedExtRegReg, emitFlags, 4);
    auto* ops     = inst.ops(operands_);
    ops[0].reg    = regDst;
    ops[1].reg    = regSrc;
    ops[2].opBits = numBitsDst;
    ops[3].opBits = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::LoadZeroExtRegMem, emitFlags, 5);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = reg;
    ops[1].reg      = memReg;
    ops[2].opBits   = numBitsDst;
    ops[3].opBits   = numBitsSrc;
    ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    auto& inst    = addInstruction(MicroInstrOpcode::LoadZeroExtRegReg, emitFlags, 4);
    auto* ops     = inst.ops(operands_);
    ops[0].reg    = regDst;
    ops[1].reg    = regSrc;
    ops[2].opBits = numBitsDst;
    ops[3].opBits = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::LoadAddrRegMem, emitFlags, 4);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = reg;
    ops[1].reg      = memReg;
    ops[2].opBits   = opBits;
    ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::LoadAmcRegMem, emitFlags, 8);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = regDst;
    ops[1].reg      = regBase;
    ops[2].reg      = regMul;
    ops[3].opBits   = opBitsDst;
    ops[4].opBits   = opBitsSrc;
    ops[5].valueU64 = mulValue;
    ops[6].valueU64 = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::LoadAmcMemReg, emitFlags, 8);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = regBase;
    ops[1].reg      = regMul;
    ops[2].reg      = regSrc;
    ops[3].opBits   = opBitsBaseMul;
    ops[4].opBits   = opBitsSrc;
    ops[5].valueU64 = mulValue;
    ops[6].valueU64 = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::LoadAmcMemImm, emitFlags, 8);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = regBase;
    ops[1].reg      = regMul;
    ops[3].opBits   = opBitsBaseMul;
    ops[4].opBits   = opBitsValue;
    ops[5].valueU64 = mulValue;
    ops[6].valueU64 = addValue;
    ops[7].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::LoadAddrAmcRegMem, emitFlags, 8);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = regDst;
    ops[1].reg      = regBase;
    ops[2].reg      = regMul;
    ops[3].opBits   = opBitsDst;
    ops[4].opBits   = opBitsValue;
    ops[5].valueU64 = mulValue;
    ops[6].valueU64 = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::LoadMemReg, emitFlags, 4);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = memReg;
    ops[1].reg      = reg;
    ops[2].opBits   = opBits;
    ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::LoadMemImm, emitFlags, 4);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = memReg;
    ops[1].opBits   = opBits;
    ops[2].valueU64 = memOffset;
    ops[3].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst    = addInstruction(MicroInstrOpcode::CmpRegReg, emitFlags, 3);
    auto* ops     = inst.ops(operands_);
    ops[0].reg    = reg0;
    ops[1].reg    = reg1;
    ops[2].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::CmpMemReg, emitFlags, 4);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = memReg;
    ops[1].reg      = reg;
    ops[2].opBits   = opBits;
    ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::CmpMemImm, emitFlags, 4);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = memReg;
    ops[1].opBits   = opBits;
    ops[2].valueU64 = memOffset;
    ops[3].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCmpRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::CmpRegImm, emitFlags, 3);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = reg;
    ops[1].opBits   = opBits;
    ops[2].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeSetCondReg(MicroReg reg, MicroCond cpuCond, EncodeFlags emitFlags)
{
    auto& inst     = addInstruction(MicroInstrOpcode::SetCondReg, emitFlags, 2);
    auto* ops      = inst.ops(operands_);
    ops[0].reg     = reg;
    ops[1].cpuCond = cpuCond;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst     = addInstruction(MicroInstrOpcode::LoadCondRegReg, emitFlags, 4);
    auto* ops      = inst.ops(operands_);
    ops[0].reg     = regDst;
    ops[1].reg     = regSrc;
    ops[2].cpuCond = setType;
    ops[3].opBits  = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeClearReg(MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst    = addInstruction(MicroInstrOpcode::ClearReg, emitFlags, 2);
    auto* ops     = inst.ops(operands_);
    ops[0].reg    = reg;
    ops[1].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::OpUnaryMem, emitFlags, 4);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = memReg;
    ops[1].opBits   = opBits;
    ops[2].cpuOp    = op;
    ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst    = addInstruction(MicroInstrOpcode::OpUnaryReg, emitFlags, 3);
    auto* ops     = inst.ops(operands_);
    ops[0].reg    = reg;
    ops[1].opBits = opBits;
    ops[2].cpuOp  = op;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst    = addInstruction(MicroInstrOpcode::OpBinaryRegReg, emitFlags, 4);
    auto* ops     = inst.ops(operands_);
    ops[0].reg    = regDst;
    ops[1].reg    = regSrc;
    ops[2].opBits = opBits;
    ops[3].cpuOp  = op;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::OpBinaryRegMem, emitFlags, 5);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = regDst;
    ops[1].reg      = memReg;
    ops[2].opBits   = opBits;
    ops[3].cpuOp    = op;
    ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::OpBinaryMemReg, emitFlags, 5);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = memReg;
    ops[1].reg      = reg;
    ops[2].opBits   = opBits;
    ops[3].cpuOp    = op;
    ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::OpBinaryRegImm, emitFlags, 4);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = reg;
    ops[1].opBits   = opBits;
    ops[2].cpuOp    = op;
    ops[3].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst      = addInstruction(MicroInstrOpcode::OpBinaryMemImm, emitFlags, 5);
    auto* ops       = inst.ops(operands_);
    ops[0].reg      = memReg;
    ops[1].opBits   = opBits;
    ops[2].cpuOp    = op;
    ops[3].valueU64 = memOffset;
    ops[4].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    auto& inst    = addInstruction(MicroInstrOpcode::OpTernaryRegRegReg, emitFlags, 5);
    auto* ops     = inst.ops(operands_);
    ops[0].reg    = reg0;
    ops[1].reg    = reg1;
    ops[2].reg    = reg2;
    ops[3].opBits = opBits;
    ops[4].cpuOp  = op;
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
    const auto* ops = inst.ops(operands_);
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
            jumps_[idx]     = jump;
            jumpValid_[idx] = true;
            break;
        }
        case MicroInstrOpcode::PatchJump:
        {
            const size_t jumpIndex = resolveJumpIndex(ops[0].valueU64);
            SWC_ASSERT(jumpIndex < jumpValid_.size());
            SWC_ASSERT(jumpValid_[jumpIndex]);
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
            encoder.encodeOpUnaryMem(ops[0].reg, ops[3].valueU64, ops[2].cpuOp, ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpUnaryReg:
            encoder.encodeOpUnaryReg(ops[0].reg, ops[2].cpuOp, ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpBinaryRegReg:
            encoder.encodeOpBinaryRegReg(ops[0].reg, ops[1].reg, ops[3].cpuOp, ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpBinaryMemReg:
            encoder.encodeOpBinaryMemReg(ops[0].reg, ops[4].valueU64, ops[1].reg, ops[3].cpuOp, ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpBinaryRegImm:
            encoder.encodeOpBinaryRegImm(ops[0].reg, ops[3].valueU64, ops[2].cpuOp, ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpBinaryMemImm:
            encoder.encodeOpBinaryMemImm(ops[0].reg, ops[3].valueU64, ops[4].valueU64, ops[2].cpuOp, ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpBinaryRegMem:
            encoder.encodeOpBinaryRegMem(ops[0].reg, ops[1].reg, ops[4].valueU64, ops[3].cpuOp, ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstrOpcode::OpTernaryRegRegReg:
            encoder.encodeOpTernaryRegRegReg(ops[0].reg, ops[1].reg, ops[2].reg, ops[4].cpuOp, ops[3].opBits, inst.emitFlags);
            break;
        default:
            SWC_ASSERT(false);
            break;
    }
}

void MicroInstrBuilder::encode(Encoder& encoder)
{
    SWC_ASSERT(jumps_.empty());
    jumps_.reserve(instructionCount_);
    jumpValid_.reserve(instructionCount_);

    size_t idx = 0;
    for (const auto& inst : instructions_.typedView<MicroInstr>())
    {
        if (idx >= instructionCount_)
            break;
        if (inst.op == MicroInstrOpcode::End)
            break;
        encodeInstruction(encoder, inst, idx);
        ++idx;
    }
}

SWC_END_NAMESPACE();
