#include "pch.h"
#include "Backend/MachineCode/Micro/MicroInstrBuilder.h"
#include "Backend/MachineCode/Micro/MicroInstrPrinter.h"
#include "Backend/MachineCode/Micro/Passes/MicroPass.h"

SWC_BEGIN_NAMESPACE();

MicroInstr& MicroInstrBuilder::addInstruction(MicroInstrOpcode op, EncodeFlags emitFlags, uint8_t numOperands)
{
    auto [_, inst]    = instructions_.emplaceUninit();
    inst->op          = op;
    inst->emitFlags   = emitFlags;
    inst->numOperands = numOperands;
    if (numOperands)
    {
        auto [opsRef, ops] = operands_.emplaceUninitArray(numOperands);
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
    const auto& inst = addInstruction(MicroInstrOpcode::SymbolRelocAddr, emitFlags, 3);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].valueU32  = symbolIndex;
    ops[2].valueU32  = offset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadSymRelocValue(MicroReg reg, uint32_t symbolIndex, uint32_t offset, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::SymbolRelocValue, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].opBits    = opBits;
    ops[2].valueU32  = symbolIndex;
    ops[3].valueU32  = offset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodePush(MicroReg reg, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::Push, emitFlags, 1);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodePop(MicroReg reg, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::Pop, emitFlags, 1);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
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

EncodeResult MicroInstrBuilder::encodeCallLocal(IdentifierRef symbolName, CallConvKind callConv, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::CallLocal, emitFlags, 2);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].name      = symbolName;
    ops[1].callConv  = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCallExtern(IdentifierRef symbolName, CallConvKind callConv, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::CallExtern, emitFlags, 2);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].name      = symbolName;
    ops[1].callConv  = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCallReg(MicroReg reg, CallConvKind callConv, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::CallIndirect, emitFlags, 2);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].callConv  = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::JumpTable, emitFlags, 5);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = tableReg;
    ops[1].reg       = offsetReg;
    ops[2].valueI32  = currentIp;
    ops[3].valueU32  = offsetTable;
    ops[4].valueU32  = numEntries;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeJump(MicroJump& jump, MicroCondJump jumpType, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const uint32_t instructionIndex = instructions_.count();
    jump.offsetStart                = static_cast<uint64_t>(instructionIndex) * sizeof(MicroInstr);
    jump.opBits                     = opBits;
    const auto& inst                = addInstruction(MicroInstrOpcode::JumpCond, emitFlags, 2);
    auto*       ops                 = inst.ops(operands_.store());
    ops[0].jumpType                 = jumpType;
    ops[1].opBits                   = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodePatchJump(const MicroJump& jump, uint64_t offsetDestination, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::PatchJump, emitFlags, 3);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].valueU64  = jump.offsetStart;
    ops[1].valueU64  = offsetDestination;
    ops[2].valueU64  = 1;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodePatchJump(const MicroJump& jump, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::PatchJump, emitFlags, 3);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].valueU64  = jump.offsetStart;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeJumpReg(MicroReg reg, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::JumpReg, emitFlags, 1);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadRegMem, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].reg       = memReg;
    ops[2].opBits    = opBits;
    ops[3].valueU64  = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadRegImm, emitFlags, 3);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].opBits    = opBits;
    ops[2].valueU64  = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadRegReg, emitFlags, 3);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = regDst;
    ops[1].reg       = regSrc;
    ops[2].opBits    = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadSignedExtRegMem, emitFlags, 5);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].reg       = memReg;
    ops[2].opBits    = numBitsDst;
    ops[3].opBits    = numBitsSrc;
    ops[4].valueU64  = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadSignedExtRegReg, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = regDst;
    ops[1].reg       = regSrc;
    ops[2].opBits    = numBitsDst;
    ops[3].opBits    = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadZeroExtRegMem, emitFlags, 5);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].reg       = memReg;
    ops[2].opBits    = numBitsDst;
    ops[3].opBits    = numBitsSrc;
    ops[4].valueU64  = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadZeroExtRegReg, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = regDst;
    ops[1].reg       = regSrc;
    ops[2].opBits    = numBitsDst;
    ops[3].opBits    = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadAddrRegMem, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].reg       = memReg;
    ops[2].opBits    = opBits;
    ops[3].valueU64  = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadAmcRegMem, emitFlags, 8);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = regDst;
    ops[1].reg       = regBase;
    ops[2].reg       = regMul;
    ops[3].opBits    = opBitsDst;
    ops[4].opBits    = opBitsSrc;
    ops[5].valueU64  = mulValue;
    ops[6].valueU64  = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadAmcMemReg, emitFlags, 8);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = regBase;
    ops[1].reg       = regMul;
    ops[2].reg       = regSrc;
    ops[3].opBits    = opBitsBaseMul;
    ops[4].opBits    = opBitsSrc;
    ops[5].valueU64  = mulValue;
    ops[6].valueU64  = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadAmcMemImm, emitFlags, 8);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = regBase;
    ops[1].reg       = regMul;
    ops[3].opBits    = opBitsBaseMul;
    ops[4].opBits    = opBitsValue;
    ops[5].valueU64  = mulValue;
    ops[6].valueU64  = addValue;
    ops[7].valueU64  = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadAddrAmcRegMem, emitFlags, 8);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = regDst;
    ops[1].reg       = regBase;
    ops[2].reg       = regMul;
    ops[3].opBits    = opBitsDst;
    ops[4].opBits    = opBitsValue;
    ops[5].valueU64  = mulValue;
    ops[6].valueU64  = addValue;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadMemReg, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = memReg;
    ops[1].reg       = reg;
    ops[2].opBits    = opBits;
    ops[3].valueU64  = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadMemImm, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = memReg;
    ops[1].opBits    = opBits;
    ops[2].valueU64  = memOffset;
    ops[3].valueU64  = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::CmpRegReg, emitFlags, 3);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg0;
    ops[1].reg       = reg1;
    ops[2].opBits    = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::CmpMemReg, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = memReg;
    ops[1].reg       = reg;
    ops[2].opBits    = opBits;
    ops[3].valueU64  = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::CmpMemImm, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = memReg;
    ops[1].opBits    = opBits;
    ops[2].valueU64  = memOffset;
    ops[3].valueU64  = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeCmpRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::CmpRegImm, emitFlags, 3);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].opBits    = opBits;
    ops[2].valueU64  = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeSetCondReg(MicroReg reg, MicroCond cpuCond, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::SetCondReg, emitFlags, 2);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].cpuCond   = cpuCond;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadCondRegReg, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = regDst;
    ops[1].reg       = regSrc;
    ops[2].cpuCond   = setType;
    ops[3].opBits    = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeClearReg(MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::ClearReg, emitFlags, 2);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].opBits    = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpUnaryMem, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = memReg;
    ops[1].opBits    = opBits;
    ops[2].microOp   = op;
    ops[3].valueU64  = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpUnaryReg, emitFlags, 3);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].opBits    = opBits;
    ops[2].microOp   = op;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpBinaryRegReg, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = regDst;
    ops[1].reg       = regSrc;
    ops[2].opBits    = opBits;
    ops[3].microOp   = op;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpBinaryRegMem, emitFlags, 5);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = regDst;
    ops[1].reg       = memReg;
    ops[2].opBits    = opBits;
    ops[3].microOp   = op;
    ops[4].valueU64  = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpBinaryMemReg, emitFlags, 5);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = memReg;
    ops[1].reg       = reg;
    ops[2].opBits    = opBits;
    ops[3].microOp   = op;
    ops[4].valueU64  = memOffset;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpBinaryRegImm, emitFlags, 4);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg;
    ops[1].opBits    = opBits;
    ops[2].microOp   = op;
    ops[3].valueU64  = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpBinaryMemImm, emitFlags, 5);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = memReg;
    ops[1].opBits    = opBits;
    ops[2].microOp   = op;
    ops[3].valueU64  = memOffset;
    ops[4].valueU64  = value;
    return EncodeResult::Zero;
}

EncodeResult MicroInstrBuilder::encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpTernaryRegRegReg, emitFlags, 5);
    auto*       ops  = inst.ops(operands_.store());
    ops[0].reg       = reg0;
    ops[1].reg       = reg1;
    ops[2].reg       = reg2;
    ops[3].opBits    = opBits;
    ops[4].microOp   = op;
    return EncodeResult::Zero;
}

void MicroInstrBuilder::runPasses(const MicroPassManager& passes, Encoder* encoder, MicroPassContext& context)
{
    context.encoder      = encoder;
    context.instructions = &instructions_;
    context.operands     = &operands_;
    passes.run(context);
}

std::string MicroInstrBuilder::formatInstructions(MicroInstrRegPrintMode regPrintMode, const Encoder* encoder, bool colorize) const
{
    return MicroInstrPrinter::format(ctx(), instructions_, operands_, regPrintMode, encoder, colorize);
}

void MicroInstrBuilder::printInstructions(MicroInstrRegPrintMode regPrintMode, const Encoder* encoder, bool colorize) const
{
    MicroInstrPrinter::print(ctx(), instructions_, operands_, regPrintMode, encoder, colorize);
}

void MicroInstrBuilder::setPrintLocation(std::string symbolName, std::string filePath, uint32_t sourceLine)
{
    printSymbolName_ = std::move(symbolName);
    printFilePath_   = std::move(filePath);
    printSourceLine_ = sourceLine;
}

SWC_END_NAMESPACE();
