#include "pch.h"
#include "Backend/MachineCode/Micro/MicroInstructionBuilder.h"

SWC_BEGIN_NAMESPACE();

MicroInstruction& MicroInstructionBuilder::addInstruction(MicroOp op, EmitFlags emitFlags, uint8_t numOperands)
{
    instructions_.emplace_back();
    auto& inst     = instructions_.back();
    inst.op        = op;
    inst.emitFlags = emitFlags;
    inst.allocateOperands(numOperands);
    return inst;
}

EncodeResult MicroInstructionBuilder::encodeLoadSymbolRelocAddress(Cpu::Reg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::SymbolRelocAddr, emitFlags, 3);
    inst.ops[0].reg      = reg;
    inst.ops[1].valueU32 = symbolIndex;
    inst.ops[2].valueU32 = offset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadSymRelocValue(Cpu::Reg reg, uint32_t symbolIndex, uint32_t offset, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::SymbolRelocValue, emitFlags, 4);
    inst.ops[0].reg      = reg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU32 = symbolIndex;
    inst.ops[3].valueU32 = offset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodePush(Cpu::Reg reg, EmitFlags emitFlags)
{
    const auto& inst = addInstruction(MicroOp::Push, emitFlags, 1);
    inst.ops[0].reg  = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodePop(Cpu::Reg reg, EmitFlags emitFlags)
{
    const auto& inst = addInstruction(MicroOp::Pop, emitFlags, 1);
    inst.ops[0].reg  = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeNop(EmitFlags emitFlags)
{
    addInstruction(MicroOp::Nop, emitFlags, 0);
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeRet(EmitFlags emitFlags)
{
    addInstruction(MicroOp::Ret, emitFlags, 0);
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeCallLocal(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::CallLocal, emitFlags, 2);
    inst.ops[0].name     = symbolName;
    inst.ops[1].callConv = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeCallExtern(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::CallExtern, emitFlags, 2);
    inst.ops[0].name     = symbolName;
    inst.ops[1].callConv = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeCallReg(Cpu::Reg reg, const CallConv* callConv, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::CallIndirect, emitFlags, 2);
    inst.ops[0].reg      = reg;
    inst.ops[1].callConv = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeJumpTable(Cpu::Reg tableReg, Cpu::Reg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::JumpTable, emitFlags, 5);
    inst.ops[0].reg      = tableReg;
    inst.ops[1].reg      = offsetReg;
    inst.ops[2].valueI32 = currentIp;
    inst.ops[3].valueU32 = offsetTable;
    inst.ops[4].valueU32 = numEntries;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeJump(Cpu::Jump& jump, Cpu::CondJump jumpType, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    jump.offsetStart     = instructions_.size() * sizeof(MicroInstruction);
    jump.opBits          = opBits;
    const auto& inst     = addInstruction(MicroOp::JumpCond, emitFlags, 2);
    inst.ops[0].jumpType = jumpType;
    inst.ops[1].opBits   = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodePatchJump(const Cpu::Jump& jump, uint64_t offsetDestination, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::PatchJump, emitFlags, 3);
    inst.ops[0].valueU64 = jump.offsetStart;
    inst.ops[1].valueU64 = offsetDestination;
    inst.ops[2].valueU64 = 1;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodePatchJump(const Cpu::Jump& jump, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::PatchJump, emitFlags, 3);
    inst.ops[0].valueU64 = jump.offsetStart;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeJumpReg(Cpu::Reg reg, EmitFlags emitFlags)
{
    const auto& inst = addInstruction(MicroOp::JumpM, emitFlags, 1);
    inst.ops[0].reg  = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadRegMem(Cpu::Reg reg, Cpu::Reg memReg, uint64_t memOffset, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::LoadRM, emitFlags, 4);
    inst.ops[0].reg      = reg;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadRegImm(Cpu::Reg reg, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::LoadRI, emitFlags, 3);
    inst.ops[0].reg      = reg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroOp::LoadRR, emitFlags, 3);
    inst.ops[0].reg    = regDst;
    inst.ops[1].reg    = regSrc;
    inst.ops[2].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadSignedExtendRegMem(Cpu::Reg reg, Cpu::Reg memReg, uint64_t memOffset, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::LoadSignedExtRM, emitFlags, 5);
    inst.ops[0].reg      = reg;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = numBitsDst;
    inst.ops[3].opBits   = numBitsSrc;
    inst.ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadSignedExtendRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroOp::LoadSignedExtRR, emitFlags, 4);
    inst.ops[0].reg    = regDst;
    inst.ops[1].reg    = regSrc;
    inst.ops[2].opBits = numBitsDst;
    inst.ops[3].opBits = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadZeroExtendRegMem(Cpu::Reg reg, Cpu::Reg memReg, uint64_t memOffset, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::LoadZeroExtRM, emitFlags, 5);
    inst.ops[0].reg      = reg;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = numBitsDst;
    inst.ops[3].opBits   = numBitsSrc;
    inst.ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadZeroExtendRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroOp::LoadZeroExtRR, emitFlags, 4);
    inst.ops[0].reg    = regDst;
    inst.ops[1].reg    = regSrc;
    inst.ops[2].opBits = numBitsDst;
    inst.ops[3].opBits = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadAddressRegMem(Cpu::Reg reg, Cpu::Reg memReg, uint64_t memOffset, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::LoadAddrRM, emitFlags, 4);
    inst.ops[0].reg      = reg;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadAmcRegMem(Cpu::Reg regDst, Cpu::OpBits opBitsDst, Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsSrc, EmitFlags emitFlags)
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

EncodeResult MicroInstructionBuilder::encodeLoadAmcMemReg(Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsBaseMul, Cpu::Reg regSrc, Cpu::OpBits opBitsSrc, EmitFlags emitFlags)
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

EncodeResult MicroInstructionBuilder::encodeLoadAmcMemImm(Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsBaseMul, uint64_t value, Cpu::OpBits opBitsValue, EmitFlags emitFlags)
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

EncodeResult MicroInstructionBuilder::encodeLoadAddressAmcRegMem(Cpu::Reg regDst, Cpu::OpBits opBitsDst, Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsValue, EmitFlags emitFlags)
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

EncodeResult MicroInstructionBuilder::encodeLoadMemReg(Cpu::Reg memReg, uint64_t memOffset, Cpu::Reg reg, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::LoadMR, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].reg      = reg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadMemImm(Cpu::Reg memReg, uint64_t memOffset, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::LoadMI, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU64 = memOffset;
    inst.ops[3].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeCmpRegReg(Cpu::Reg reg0, Cpu::Reg reg1, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroOp::CmpRR, emitFlags, 3);
    inst.ops[0].reg    = reg0;
    inst.ops[1].reg    = reg1;
    inst.ops[2].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeCmpMemReg(Cpu::Reg memReg, uint64_t memOffset, Cpu::Reg reg, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::CmpMR, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].reg      = reg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeCmpMemImm(Cpu::Reg memReg, uint64_t memOffset, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::CmpMI, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU64 = memOffset;
    inst.ops[3].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeCmpRegImm(Cpu::Reg reg, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::CmpRI, emitFlags, 3);
    inst.ops[0].reg      = reg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeSetCondReg(Cpu::Reg reg, Cpu::Cond cpuCond, EmitFlags emitFlags)
{
    const auto& inst    = addInstruction(MicroOp::SetCondR, emitFlags, 2);
    inst.ops[0].reg     = reg;
    inst.ops[1].cpuCond = cpuCond;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadCondRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::Cond setType, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst    = addInstruction(MicroOp::LoadCondRR, emitFlags, 4);
    inst.ops[0].reg     = regDst;
    inst.ops[1].reg     = regSrc;
    inst.ops[2].cpuCond = setType;
    inst.ops[3].opBits  = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeClearReg(Cpu::Reg reg, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroOp::ClearR, emitFlags, 2);
    inst.ops[0].reg    = reg;
    inst.ops[1].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeOpUnaryMem(Cpu::Reg memReg, uint64_t memOffset, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::OpUnaryM, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].cpuOp    = op;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeOpUnaryReg(Cpu::Reg reg, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroOp::OpUnaryR, emitFlags, 3);
    inst.ops[0].reg    = reg;
    inst.ops[1].opBits = opBits;
    inst.ops[2].cpuOp  = op;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeOpBinaryRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroOp::OpBinaryRR, emitFlags, 4);
    inst.ops[0].reg    = regDst;
    inst.ops[1].reg    = regSrc;
    inst.ops[2].opBits = opBits;
    inst.ops[3].cpuOp  = op;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeOpBinaryRegMem(Cpu::Reg regDst, Cpu::Reg memReg, uint64_t memOffset, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::OpBinaryRM, emitFlags, 5);
    inst.ops[0].reg      = regDst;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].cpuOp    = op;
    inst.ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeOpBinaryMemReg(Cpu::Reg memReg, uint64_t memOffset, Cpu::Reg reg, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::OpBinaryMR, emitFlags, 5);
    inst.ops[0].reg      = memReg;
    inst.ops[1].reg      = reg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].cpuOp    = op;
    inst.ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeOpBinaryRegImm(Cpu::Reg reg, uint64_t value, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::OpBinaryRI, emitFlags, 4);
    inst.ops[0].reg      = reg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].cpuOp    = op;
    inst.ops[3].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeOpBinaryMemImm(Cpu::Reg memReg, uint64_t memOffset, uint64_t value, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroOp::OpBinaryMI, emitFlags, 5);
    inst.ops[0].reg      = memReg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].cpuOp    = op;
    inst.ops[3].valueU64 = memOffset;
    inst.ops[4].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeOpTernaryRegRegReg(Cpu::Reg reg0, Cpu::Reg reg1, Cpu::Reg reg2, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)
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

void MicroInstructionBuilder::encodeInstruction(Encoder& encoder, const MicroInstruction& inst, size_t idx)
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
            encoder.encodeLoadSymbolRelocAddress(inst.ops[0].reg, inst.ops[1].valueU32, inst.ops[2].valueU32, inst.emitFlags);
            break;
        case MicroOp::SymbolRelocValue:
            encoder.encodeLoadSymRelocValue(inst.ops[0].reg, inst.ops[2].valueU32, inst.ops[3].valueU32, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroOp::Push:
            encoder.encodePush(inst.ops[0].reg, inst.emitFlags);
            break;
        case MicroOp::Pop:
            encoder.encodePop(inst.ops[0].reg, inst.emitFlags);
            break;
        case MicroOp::Nop:
            encoder.encodeNop(inst.emitFlags);
            break;
        case MicroOp::Ret:
            encoder.encodeRet(inst.emitFlags);
            break;
        case MicroOp::CallLocal:
            encoder.encodeCallLocal(inst.ops[0].name, inst.ops[1].callConv, inst.emitFlags);
            break;
        case MicroOp::CallExtern:
            encoder.encodeCallExtern(inst.ops[0].name, inst.ops[1].callConv, inst.emitFlags);
            break;
        case MicroOp::CallIndirect:
            encoder.encodeCallReg(inst.ops[0].reg, inst.ops[1].callConv, inst.emitFlags);
            break;
        case MicroOp::JumpTable:
            encoder.encodeJumpTable(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].valueI32, inst.ops[3].valueU32, inst.ops[4].valueU32, inst.emitFlags);
            break;
        case MicroOp::JumpCond:
        {
            Cpu::Jump jump;
            encoder.encodeJump(jump, inst.ops[0].jumpType, inst.ops[1].opBits, inst.emitFlags);
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
                encoder.encodePatchJump(jumps_[jumpIndex], inst.ops[1].valueU64, inst.emitFlags);
            else
                encoder.encodePatchJump(jumps_[jumpIndex], inst.emitFlags);
            break;
        }
        case MicroOp::JumpCondI:
        {
            Cpu::Jump  jump;
            const auto opBits = inst.ops[1].opBits == Cpu::OpBits::Zero ? Cpu::OpBits::B32 : inst.ops[1].opBits;
            encoder.encodeJump(jump, inst.ops[0].jumpType, opBits, inst.emitFlags);
            encoder.encodePatchJump(jump, inst.ops[2].valueU64, inst.emitFlags);
            break;
        }
        case MicroOp::JumpM:
            encoder.encodeJumpReg(inst.ops[0].reg, inst.emitFlags);
            break;
        case MicroOp::LoadRR:
            encoder.encodeLoadRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadRI:
            encoder.encodeLoadRegImm(inst.ops[0].reg, inst.ops[2].valueU64, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadRM:
            encoder.encodeLoadRegMem(inst.ops[0].reg, inst.ops[1].reg, inst.ops[3].valueU64, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadSignedExtRM:
            encoder.encodeLoadSignedExtendRegMem(inst.ops[0].reg, inst.ops[1].reg, inst.ops[4].valueU64, inst.ops[2].opBits, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadSignedExtRR:
            encoder.encodeLoadSignedExtendRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].opBits, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadZeroExtRM:
            encoder.encodeLoadZeroExtendRegMem(inst.ops[0].reg, inst.ops[1].reg, inst.ops[4].valueU64, inst.ops[2].opBits, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadZeroExtRR:
            encoder.encodeLoadZeroExtendRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].opBits, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadAddrRM:
            encoder.encodeLoadAddressRegMem(inst.ops[0].reg, inst.ops[1].reg, inst.ops[3].valueU64, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadAmcMR:
            encoder.encodeLoadAmcMemReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[5].valueU64, inst.ops[6].valueU64, inst.ops[3].opBits, inst.ops[2].reg, inst.ops[4].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadAmcMI:
            encoder.encodeLoadAmcMemImm(inst.ops[0].reg, inst.ops[1].reg, inst.ops[5].valueU64, inst.ops[6].valueU64, inst.ops[3].opBits, inst.ops[7].valueU64, inst.ops[4].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadAmcRM:
            encoder.encodeLoadAmcRegMem(inst.ops[0].reg, inst.ops[3].opBits, inst.ops[1].reg, inst.ops[2].reg, inst.ops[5].valueU64, inst.ops[6].valueU64, inst.ops[4].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadAddrAmcRM:
            encoder.encodeLoadAddressAmcRegMem(inst.ops[0].reg, inst.ops[3].opBits, inst.ops[1].reg, inst.ops[2].reg, inst.ops[5].valueU64, inst.ops[6].valueU64, inst.ops[4].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadMR:
            encoder.encodeLoadMemReg(inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[1].reg, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroOp::LoadMI:
            encoder.encodeLoadMemImm(inst.ops[0].reg, inst.ops[2].valueU64, inst.ops[3].valueU64, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroOp::CmpRR:
            encoder.encodeCmpRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroOp::CmpRI:
            encoder.encodeCmpRegImm(inst.ops[0].reg, inst.ops[2].valueU64, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroOp::CmpMR:
            encoder.encodeCmpMemReg(inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[1].reg, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroOp::CmpMI:
            encoder.encodeCmpMemImm(inst.ops[0].reg, inst.ops[2].valueU64, inst.ops[3].valueU64, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroOp::SetCondR:
            encoder.encodeSetCondReg(inst.ops[0].reg, inst.ops[1].cpuCond, inst.emitFlags);
            break;
        case MicroOp::LoadCondRR:
            encoder.encodeLoadCondRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].cpuCond, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroOp::ClearR:
            encoder.encodeClearReg(inst.ops[0].reg, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroOp::OpUnaryM:
            encoder.encodeOpUnaryMem(inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[2].cpuOp, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroOp::OpUnaryR:
            encoder.encodeOpUnaryReg(inst.ops[0].reg, inst.ops[2].cpuOp, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroOp::OpBinaryRR:
            encoder.encodeOpBinaryRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[3].cpuOp, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroOp::OpBinaryMR:
            encoder.encodeOpBinaryMemReg(inst.ops[0].reg, inst.ops[4].valueU64, inst.ops[1].reg, inst.ops[3].cpuOp, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroOp::OpBinaryRI:
            encoder.encodeOpBinaryRegImm(inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[2].cpuOp, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroOp::OpBinaryMI:
            encoder.encodeOpBinaryMemImm(inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[4].valueU64, inst.ops[2].cpuOp, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroOp::OpBinaryRM:
            encoder.encodeOpBinaryRegMem(inst.ops[0].reg, inst.ops[1].reg, inst.ops[4].valueU64, inst.ops[3].cpuOp, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroOp::OpTernaryRRR:
            encoder.encodeOpTernaryRegRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].reg, inst.ops[4].cpuOp, inst.ops[3].opBits, inst.emitFlags);
            break;
        default:
            SWC_ASSERT(false);
            break;
    }
}

void MicroInstructionBuilder::encode(Encoder& encoder)
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
