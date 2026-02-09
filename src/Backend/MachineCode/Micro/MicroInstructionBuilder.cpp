#include "pch.h"
#include "Backend/MachineCode/Micro/MicroInstructionBuilder.h"

SWC_BEGIN_NAMESPACE();

MicroInstruction& MicroInstructionBuilder::addInstruction(MicroInstructionKind op, EmitFlags emitFlags, uint8_t numOperands)
{
    instructions_.emplace_back();
    auto& inst     = instructions_.back();
    inst.op        = op;
    inst.emitFlags = emitFlags;
    inst.allocateOperands(numOperands);
    return inst;
}

EncodeResult MicroInstructionBuilder::encodeLoadSymbolRelocAddress(Micro::Reg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::SymbolRelocAddr, emitFlags, 3);
    inst.ops[0].reg      = reg;
    inst.ops[1].valueU32 = symbolIndex;
    inst.ops[2].valueU32 = offset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadSymRelocValue(Micro::Reg reg, uint32_t symbolIndex, uint32_t offset, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::SymbolRelocValue, emitFlags, 4);
    inst.ops[0].reg      = reg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU32 = symbolIndex;
    inst.ops[3].valueU32 = offset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodePush(Micro::Reg reg, EmitFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstructionKind::Push, emitFlags, 1);
    inst.ops[0].reg  = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodePop(Micro::Reg reg, EmitFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstructionKind::Pop, emitFlags, 1);
    inst.ops[0].reg  = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeNop(EmitFlags emitFlags)
{
    addInstruction(MicroInstructionKind::Nop, emitFlags, 0);
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeRet(EmitFlags emitFlags)
{
    addInstruction(MicroInstructionKind::Ret, emitFlags, 0);
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeCallLocal(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::CallLocal, emitFlags, 2);
    inst.ops[0].name     = symbolName;
    inst.ops[1].callConv = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeCallExtern(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::CallExtern, emitFlags, 2);
    inst.ops[0].name     = symbolName;
    inst.ops[1].callConv = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeCallReg(Micro::Reg reg, const CallConv* callConv, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::CallIndirect, emitFlags, 2);
    inst.ops[0].reg      = reg;
    inst.ops[1].callConv = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeJumpTable(Micro::Reg tableReg, Micro::Reg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::JumpTable, emitFlags, 5);
    inst.ops[0].reg      = tableReg;
    inst.ops[1].reg      = offsetReg;
    inst.ops[2].valueI32 = currentIp;
    inst.ops[3].valueU32 = offsetTable;
    inst.ops[4].valueU32 = numEntries;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeJump(Micro::Jump& jump, Micro::CondJump jumpType, Micro::OpBits opBits, EmitFlags emitFlags)
{
    jump.offsetStart     = instructions_.size() * sizeof(MicroInstruction);
    jump.opBits          = opBits;
    const auto& inst     = addInstruction(MicroInstructionKind::JumpCond, emitFlags, 2);
    inst.ops[0].jumpType = jumpType;
    inst.ops[1].opBits   = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodePatchJump(const Micro::Jump& jump, uint64_t offsetDestination, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::PatchJump, emitFlags, 3);
    inst.ops[0].valueU64 = jump.offsetStart;
    inst.ops[1].valueU64 = offsetDestination;
    inst.ops[2].valueU64 = 1;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodePatchJump(const Micro::Jump& jump, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::PatchJump, emitFlags, 3);
    inst.ops[0].valueU64 = jump.offsetStart;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeJumpReg(Micro::Reg reg, EmitFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstructionKind::JumpM, emitFlags, 1);
    inst.ops[0].reg  = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadRegMem(Micro::Reg reg, Micro::Reg memReg, uint64_t memOffset, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::LoadRM, emitFlags, 4);
    inst.ops[0].reg      = reg;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadRegImm(Micro::Reg reg, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::LoadRI, emitFlags, 3);
    inst.ops[0].reg      = reg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstructionKind::LoadRR, emitFlags, 3);
    inst.ops[0].reg    = regDst;
    inst.ops[1].reg    = regSrc;
    inst.ops[2].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadSignedExtendRegMem(Micro::Reg reg, Micro::Reg memReg, uint64_t memOffset, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::LoadSignedExtRM, emitFlags, 5);
    inst.ops[0].reg      = reg;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = numBitsDst;
    inst.ops[3].opBits   = numBitsSrc;
    inst.ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadSignedExtendRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstructionKind::LoadSignedExtRR, emitFlags, 4);
    inst.ops[0].reg    = regDst;
    inst.ops[1].reg    = regSrc;
    inst.ops[2].opBits = numBitsDst;
    inst.ops[3].opBits = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadZeroExtendRegMem(Micro::Reg reg, Micro::Reg memReg, uint64_t memOffset, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::LoadZeroExtRM, emitFlags, 5);
    inst.ops[0].reg      = reg;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = numBitsDst;
    inst.ops[3].opBits   = numBitsSrc;
    inst.ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadZeroExtendRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstructionKind::LoadZeroExtRR, emitFlags, 4);
    inst.ops[0].reg    = regDst;
    inst.ops[1].reg    = regSrc;
    inst.ops[2].opBits = numBitsDst;
    inst.ops[3].opBits = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadAddressRegMem(Micro::Reg reg, Micro::Reg memReg, uint64_t memOffset, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::LoadAddrRM, emitFlags, 4);
    inst.ops[0].reg      = reg;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadAmcRegMem(Micro::Reg regDst, Micro::OpBits opBitsDst, Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsSrc, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::LoadAmcRM, emitFlags, 8);
    inst.ops[0].reg      = regDst;
    inst.ops[1].reg      = regBase;
    inst.ops[2].reg      = regMul;
    inst.ops[3].opBits   = opBitsDst;
    inst.ops[4].opBits   = opBitsSrc;
    inst.ops[5].valueU64 = mulValue;
    inst.ops[6].valueU64 = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadAmcMemReg(Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsBaseMul, Micro::Reg regSrc, Micro::OpBits opBitsSrc, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::LoadAmcMR, emitFlags, 8);
    inst.ops[0].reg      = regBase;
    inst.ops[1].reg      = regMul;
    inst.ops[2].reg      = regSrc;
    inst.ops[3].opBits   = opBitsBaseMul;
    inst.ops[4].opBits   = opBitsSrc;
    inst.ops[5].valueU64 = mulValue;
    inst.ops[6].valueU64 = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadAmcMemImm(Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsBaseMul, uint64_t value, Micro::OpBits opBitsValue, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::LoadAmcMI, emitFlags, 8);
    inst.ops[0].reg      = regBase;
    inst.ops[1].reg      = regMul;
    inst.ops[3].opBits   = opBitsBaseMul;
    inst.ops[4].opBits   = opBitsValue;
    inst.ops[5].valueU64 = mulValue;
    inst.ops[6].valueU64 = addValue;
    inst.ops[7].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadAddressAmcRegMem(Micro::Reg regDst, Micro::OpBits opBitsDst, Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsValue, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::LoadAddrAmcRM, emitFlags, 8);
    inst.ops[0].reg      = regDst;
    inst.ops[1].reg      = regBase;
    inst.ops[2].reg      = regMul;
    inst.ops[3].opBits   = opBitsDst;
    inst.ops[4].opBits   = opBitsValue;
    inst.ops[5].valueU64 = mulValue;
    inst.ops[6].valueU64 = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadMemReg(Micro::Reg memReg, uint64_t memOffset, Micro::Reg reg, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::LoadMR, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].reg      = reg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadMemImm(Micro::Reg memReg, uint64_t memOffset, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::LoadMI, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU64 = memOffset;
    inst.ops[3].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeCmpRegReg(Micro::Reg reg0, Micro::Reg reg1, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstructionKind::CmpRR, emitFlags, 3);
    inst.ops[0].reg    = reg0;
    inst.ops[1].reg    = reg1;
    inst.ops[2].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeCmpMemReg(Micro::Reg memReg, uint64_t memOffset, Micro::Reg reg, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::CmpMR, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].reg      = reg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeCmpMemImm(Micro::Reg memReg, uint64_t memOffset, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::CmpMI, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU64 = memOffset;
    inst.ops[3].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeCmpRegImm(Micro::Reg reg, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::CmpRI, emitFlags, 3);
    inst.ops[0].reg      = reg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeSetCondReg(Micro::Reg reg, Micro::Cond cpuCond, EmitFlags emitFlags)
{
    const auto& inst    = addInstruction(MicroInstructionKind::SetCondR, emitFlags, 2);
    inst.ops[0].reg     = reg;
    inst.ops[1].cpuCond = cpuCond;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeLoadCondRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::Cond setType, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst    = addInstruction(MicroInstructionKind::LoadCondRR, emitFlags, 4);
    inst.ops[0].reg     = regDst;
    inst.ops[1].reg     = regSrc;
    inst.ops[2].cpuCond = setType;
    inst.ops[3].opBits  = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeClearReg(Micro::Reg reg, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstructionKind::ClearR, emitFlags, 2);
    inst.ops[0].reg    = reg;
    inst.ops[1].opBits = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeOpUnaryMem(Micro::Reg memReg, uint64_t memOffset, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::OpUnaryM, emitFlags, 4);
    inst.ops[0].reg      = memReg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].cpuOp    = op;
    inst.ops[3].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeOpUnaryReg(Micro::Reg reg, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstructionKind::OpUnaryR, emitFlags, 3);
    inst.ops[0].reg    = reg;
    inst.ops[1].opBits = opBits;
    inst.ops[2].cpuOp  = op;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeOpBinaryRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstructionKind::OpBinaryRR, emitFlags, 4);
    inst.ops[0].reg    = regDst;
    inst.ops[1].reg    = regSrc;
    inst.ops[2].opBits = opBits;
    inst.ops[3].cpuOp  = op;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeOpBinaryRegMem(Micro::Reg regDst, Micro::Reg memReg, uint64_t memOffset, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::OpBinaryRM, emitFlags, 5);
    inst.ops[0].reg      = regDst;
    inst.ops[1].reg      = memReg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].cpuOp    = op;
    inst.ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeOpBinaryMemReg(Micro::Reg memReg, uint64_t memOffset, Micro::Reg reg, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::OpBinaryMR, emitFlags, 5);
    inst.ops[0].reg      = memReg;
    inst.ops[1].reg      = reg;
    inst.ops[2].opBits   = opBits;
    inst.ops[3].cpuOp    = op;
    inst.ops[4].valueU64 = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeOpBinaryRegImm(Micro::Reg reg, uint64_t value, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::OpBinaryRI, emitFlags, 4);
    inst.ops[0].reg      = reg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].cpuOp    = op;
    inst.ops[3].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeOpBinaryMemImm(Micro::Reg memReg, uint64_t memOffset, uint64_t value, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst     = addInstruction(MicroInstructionKind::OpBinaryMI, emitFlags, 5);
    inst.ops[0].reg      = memReg;
    inst.ops[1].opBits   = opBits;
    inst.ops[2].cpuOp    = op;
    inst.ops[3].valueU64 = memOffset;
    inst.ops[4].valueU64 = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstructionBuilder::encodeOpTernaryRegRegReg(Micro::Reg reg0, Micro::Reg reg1, Micro::Reg reg2, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)
{
    const auto& inst   = addInstruction(MicroInstructionKind::OpTernaryRRR, emitFlags, 5);
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
        case MicroInstructionKind::End:
            break;

        case MicroInstructionKind::Ignore:
        case MicroInstructionKind::Label:
        case MicroInstructionKind::Debug:
            break;

        case MicroInstructionKind::Enter:
        case MicroInstructionKind::Leave:
        case MicroInstructionKind::LoadCallParam:
        case MicroInstructionKind::LoadCallAddrParam:
        case MicroInstructionKind::LoadCallZeroExtParam:
        case MicroInstructionKind::StoreCallParam:
            SWC_ASSERT(false);
            break;

        case MicroInstructionKind::SymbolRelocAddr:
            encoder.encodeLoadSymbolRelocAddress(inst.ops[0].reg, inst.ops[1].valueU32, inst.ops[2].valueU32, inst.emitFlags);
            break;
        case MicroInstructionKind::SymbolRelocValue:
            encoder.encodeLoadSymRelocValue(inst.ops[0].reg, inst.ops[2].valueU32, inst.ops[3].valueU32, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::Push:
            encoder.encodePush(inst.ops[0].reg, inst.emitFlags);
            break;
        case MicroInstructionKind::Pop:
            encoder.encodePop(inst.ops[0].reg, inst.emitFlags);
            break;
        case MicroInstructionKind::Nop:
            encoder.encodeNop(inst.emitFlags);
            break;
        case MicroInstructionKind::Ret:
            encoder.encodeRet(inst.emitFlags);
            break;
        case MicroInstructionKind::CallLocal:
            encoder.encodeCallLocal(inst.ops[0].name, inst.ops[1].callConv, inst.emitFlags);
            break;
        case MicroInstructionKind::CallExtern:
            encoder.encodeCallExtern(inst.ops[0].name, inst.ops[1].callConv, inst.emitFlags);
            break;
        case MicroInstructionKind::CallIndirect:
            encoder.encodeCallReg(inst.ops[0].reg, inst.ops[1].callConv, inst.emitFlags);
            break;
        case MicroInstructionKind::JumpTable:
            encoder.encodeJumpTable(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].valueI32, inst.ops[3].valueU32, inst.ops[4].valueU32, inst.emitFlags);
            break;
        case MicroInstructionKind::JumpCond:
        {
            Micro::Jump jump;
            encoder.encodeJump(jump, inst.ops[0].jumpType, inst.ops[1].opBits, inst.emitFlags);
            jumps_[idx]     = jump;
            jumpValid_[idx] = true;
            break;
        }
        case MicroInstructionKind::PatchJump:
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
        case MicroInstructionKind::JumpCondI:
        {
            Micro::Jump jump;
            const auto  opBits = inst.ops[1].opBits == Micro::OpBits::Zero ? Micro::OpBits::B32 : inst.ops[1].opBits;
            encoder.encodeJump(jump, inst.ops[0].jumpType, opBits, inst.emitFlags);
            encoder.encodePatchJump(jump, inst.ops[2].valueU64, inst.emitFlags);
            break;
        }
        case MicroInstructionKind::JumpM:
            encoder.encodeJumpReg(inst.ops[0].reg, inst.emitFlags);
            break;
        case MicroInstructionKind::LoadRR:
            encoder.encodeLoadRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::LoadRI:
            encoder.encodeLoadRegImm(inst.ops[0].reg, inst.ops[2].valueU64, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::LoadRM:
            encoder.encodeLoadRegMem(inst.ops[0].reg, inst.ops[1].reg, inst.ops[3].valueU64, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::LoadSignedExtRM:
            encoder.encodeLoadSignedExtendRegMem(inst.ops[0].reg, inst.ops[1].reg, inst.ops[4].valueU64, inst.ops[2].opBits, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::LoadSignedExtRR:
            encoder.encodeLoadSignedExtendRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].opBits, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::LoadZeroExtRM:
            encoder.encodeLoadZeroExtendRegMem(inst.ops[0].reg, inst.ops[1].reg, inst.ops[4].valueU64, inst.ops[2].opBits, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::LoadZeroExtRR:
            encoder.encodeLoadZeroExtendRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].opBits, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::LoadAddrRM:
            encoder.encodeLoadAddressRegMem(inst.ops[0].reg, inst.ops[1].reg, inst.ops[3].valueU64, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::LoadAmcMR:
            encoder.encodeLoadAmcMemReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[5].valueU64, inst.ops[6].valueU64, inst.ops[3].opBits, inst.ops[2].reg, inst.ops[4].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::LoadAmcMI:
            encoder.encodeLoadAmcMemImm(inst.ops[0].reg, inst.ops[1].reg, inst.ops[5].valueU64, inst.ops[6].valueU64, inst.ops[3].opBits, inst.ops[7].valueU64, inst.ops[4].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::LoadAmcRM:
            encoder.encodeLoadAmcRegMem(inst.ops[0].reg, inst.ops[3].opBits, inst.ops[1].reg, inst.ops[2].reg, inst.ops[5].valueU64, inst.ops[6].valueU64, inst.ops[4].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::LoadAddrAmcRM:
            encoder.encodeLoadAddressAmcRegMem(inst.ops[0].reg, inst.ops[3].opBits, inst.ops[1].reg, inst.ops[2].reg, inst.ops[5].valueU64, inst.ops[6].valueU64, inst.ops[4].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::LoadMR:
            encoder.encodeLoadMemReg(inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[1].reg, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::LoadMI:
            encoder.encodeLoadMemImm(inst.ops[0].reg, inst.ops[2].valueU64, inst.ops[3].valueU64, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::CmpRR:
            encoder.encodeCmpRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::CmpRI:
            encoder.encodeCmpRegImm(inst.ops[0].reg, inst.ops[2].valueU64, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::CmpMR:
            encoder.encodeCmpMemReg(inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[1].reg, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::CmpMI:
            encoder.encodeCmpMemImm(inst.ops[0].reg, inst.ops[2].valueU64, inst.ops[3].valueU64, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::SetCondR:
            encoder.encodeSetCondReg(inst.ops[0].reg, inst.ops[1].cpuCond, inst.emitFlags);
            break;
        case MicroInstructionKind::LoadCondRR:
            encoder.encodeLoadCondRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[2].cpuCond, inst.ops[3].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::ClearR:
            encoder.encodeClearReg(inst.ops[0].reg, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::OpUnaryM:
            encoder.encodeOpUnaryMem(inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[2].cpuOp, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::OpUnaryR:
            encoder.encodeOpUnaryReg(inst.ops[0].reg, inst.ops[2].cpuOp, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::OpBinaryRR:
            encoder.encodeOpBinaryRegReg(inst.ops[0].reg, inst.ops[1].reg, inst.ops[3].cpuOp, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::OpBinaryMR:
            encoder.encodeOpBinaryMemReg(inst.ops[0].reg, inst.ops[4].valueU64, inst.ops[1].reg, inst.ops[3].cpuOp, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::OpBinaryRI:
            encoder.encodeOpBinaryRegImm(inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[2].cpuOp, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::OpBinaryMI:
            encoder.encodeOpBinaryMemImm(inst.ops[0].reg, inst.ops[3].valueU64, inst.ops[4].valueU64, inst.ops[2].cpuOp, inst.ops[1].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::OpBinaryRM:
            encoder.encodeOpBinaryRegMem(inst.ops[0].reg, inst.ops[1].reg, inst.ops[4].valueU64, inst.ops[3].cpuOp, inst.ops[2].opBits, inst.emitFlags);
            break;
        case MicroInstructionKind::OpTernaryRRR:
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
        if (inst.op == MicroInstructionKind::End)
            break;
        encodeInstruction(encoder, inst, idx);
    }
}

SWC_END_NAMESPACE();
