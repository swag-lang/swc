#include "pch.h"
#include "Backend/CodeGen/Micro/MicroBuilder.h"
#include "Backend/CodeGen/Micro/MicroPrinter.h"
#include "Backend/CodeGen/Micro/Passes/MicroPass.h"
#include "Compiler/Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

std::pair<Ref, MicroInstr&> MicroBuilder::addInstructionWithRef(MicroInstrOpcode op, EncodeFlags emitFlags, uint8_t numOperands)
{
    auto [instRef, inst] = instructions_.emplaceUninit();
    inst->op             = op;
    inst->emitFlags      = emitFlags;
    inst->numOperands    = numOperands;
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

    storeInstructionDebugInfo(instRef);
    return {instRef, *SWC_CHECK_NOT_NULL(inst)};
}

MicroInstr& MicroBuilder::addInstruction(MicroInstrOpcode op, EncodeFlags emitFlags, uint8_t numOperands)
{
    return addInstructionWithRef(op, emitFlags, numOperands).second;
}

void MicroBuilder::storeInstructionDebugInfo(Ref instructionRef)
{
    if (!hasFlag(MicroBuilderFlagsE::DebugInfo))
        return;

    if (!currentDebugInfo_.hasData())
        return;

    if (instructionRef >= debugInfos_.size())
        debugInfos_.resize(instructionRef + 1);

    debugInfos_[instructionRef] = currentDebugInfo_;
}

const MicroDebugInfo* MicroBuilder::debugInfo(Ref instructionRef) const
{
    if (instructionRef >= debugInfos_.size())
        return nullptr;

    const auto& info = debugInfos_[instructionRef];
    if (!info.has_value())
        return nullptr;
    return &info.value();
}

void MicroBuilder::addRelocation(const MicroRelocation& relocation)
{
    codeRelocations_.push_back(relocation);
}

void MicroBuilder::encodeLoadSymbolRelocAddress(MicroReg reg, uint32_t symbolIndex, uint32_t offset, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::SymbolRelocAddr, emitFlags, 3);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = reg;
    ops[1].valueU32  = symbolIndex;
    ops[2].valueU32  = offset;
    return;
}

void MicroBuilder::encodeLoadSymRelocValue(MicroReg reg, uint32_t symbolIndex, uint32_t offset, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::SymbolRelocValue, emitFlags, 4);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = reg;
    ops[1].opBits    = opBits;
    ops[2].valueU32  = symbolIndex;
    ops[3].valueU32  = offset;
    return;
}

void MicroBuilder::encodePush(MicroReg reg, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::Push, emitFlags, 1);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = reg;
    return;
}

void MicroBuilder::encodePop(MicroReg reg, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::Pop, emitFlags, 1);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = reg;
    return;
}

void MicroBuilder::encodeNop(EncodeFlags emitFlags)
{
    addInstruction(MicroInstrOpcode::Nop, emitFlags, 0);
    return;
}

Ref MicroBuilder::createLabel()
{
    const auto labelRef = static_cast<Ref>(labels_.size());
    labels_.push_back(INVALID_REF);
    return labelRef;
}

void MicroBuilder::placeLabel(Ref labelRef, EncodeFlags emitFlags)
{
    SWC_ASSERT(labelRef < labels_.size());
    SWC_ASSERT(labels_[labelRef] == INVALID_REF);

    auto [instRef, inst] = addInstructionWithRef(MicroInstrOpcode::Label, emitFlags, 1);
    auto* ops            = inst.ops(operands_);
    ops[0].valueU64      = labelRef;
    labels_[labelRef]    = instRef;
    return;
}

void MicroBuilder::encodeLabel(Ref& outLabelRef, EncodeFlags emitFlags)
{
    outLabelRef = createLabel();
    return placeLabel(outLabelRef, emitFlags);
}

void MicroBuilder::encodeRet(EncodeFlags emitFlags)
{
    addInstruction(MicroInstrOpcode::Ret, emitFlags, 0);
    return;
}

void MicroBuilder::encodeCallLocal(Symbol* targetSymbol, CallConvKind callConv, EncodeFlags emitFlags)
{
    const auto  symbolName = targetSymbol ? targetSymbol->idRef() : IdentifierRef::invalid();
    const auto& inst       = addInstruction(MicroInstrOpcode::CallLocal, emitFlags, 4);
    auto*       ops        = inst.ops(operands_);
    ops[0].name            = symbolName;
    ops[1].callConv        = callConv;
    ops[2].valueU64        = 0;
    ops[3].valueU64        = reinterpret_cast<uint64_t>(targetSymbol);
    return;
}

void MicroBuilder::encodeCallExtern(Symbol* targetSymbol, CallConvKind callConv, EncodeFlags emitFlags)
{
    const IdentifierRef symbolName = targetSymbol ? targetSymbol->idRef() : IdentifierRef::invalid();
    const auto&         inst       = addInstruction(MicroInstrOpcode::CallExtern, emitFlags, 4);
    auto*               ops        = inst.ops(operands_);
    ops[0].name                    = symbolName;
    ops[1].callConv                = callConv;
    ops[2].valueU64                = reinterpret_cast<uint64_t>(targetSymbol);
    ops[3].valueU64                = 0;
    return;
}

void MicroBuilder::encodeCallReg(MicroReg reg, CallConvKind callConv, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::CallIndirect, emitFlags, 2);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = reg;
    ops[1].callConv  = callConv;
    return;
}

void MicroBuilder::encodeJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::JumpTable, emitFlags, 5);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = tableReg;
    ops[1].reg       = offsetReg;
    ops[2].valueI32  = currentIp;
    ops[3].valueU32  = offsetTable;
    ops[4].valueU32  = numEntries;
    return;
}

void MicroBuilder::encodeJumpToLabel(MicroCond cpuCond, MicroOpBits opBits, Ref labelRef, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::JumpCond, emitFlags, 3);
    auto*       ops  = inst.ops(operands_);
    ops[0].cpuCond   = cpuCond;
    ops[1].opBits    = opBits;
    ops[2].valueU64  = labelRef;
    return;
}

void MicroBuilder::encodeJumpReg(MicroReg reg, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::JumpReg, emitFlags, 1);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = reg;
    return;
}

void MicroBuilder::encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadRegMem, emitFlags, 4);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = reg;
    ops[1].reg       = memReg;
    ops[2].opBits    = opBits;
    ops[3].valueU64  = memOffset;
    return;
}

void MicroBuilder::encodeLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadRegImm, emitFlags, 3);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = reg;
    ops[1].opBits    = opBits;
    ops[2].valueU64  = value;
    return;
}

void MicroBuilder::encodeLoadRegPtrImm(MicroReg reg, uint64_t value, ConstantRef constantRef, Symbol* targetSymbol, IdentifierRef symbolName, EncodeFlags emitFlags)
{
    auto [instRef, inst] = addInstructionWithRef(MicroInstrOpcode::LoadRegImm, emitFlags, 3);
    auto* ops            = inst.ops(operands_);
    ops[0].reg           = reg;
    ops[1].opBits        = MicroOpBits::B64;
    ops[2].valueU64      = value;

    addRelocation({
        .kind           = MicroRelocation::Kind::Abs64,
        .instructionRef = instRef,
        .symbolName     = symbolName,
        .targetAddress  = value,
        .targetSymbol   = targetSymbol,
        .constantRef    = constantRef,
    });
}

void MicroBuilder::encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadRegReg, emitFlags, 3);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = regDst;
    ops[1].reg       = regSrc;
    ops[2].opBits    = opBits;
    return;
}

void MicroBuilder::encodeLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadSignedExtRegMem, emitFlags, 5);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = reg;
    ops[1].reg       = memReg;
    ops[2].opBits    = numBitsDst;
    ops[3].opBits    = numBitsSrc;
    ops[4].valueU64  = memOffset;
    return;
}

void MicroBuilder::encodeLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadSignedExtRegReg, emitFlags, 4);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = regDst;
    ops[1].reg       = regSrc;
    ops[2].opBits    = numBitsDst;
    ops[3].opBits    = numBitsSrc;
    return;
}

void MicroBuilder::encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadZeroExtRegMem, emitFlags, 5);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = reg;
    ops[1].reg       = memReg;
    ops[2].opBits    = numBitsDst;
    ops[3].opBits    = numBitsSrc;
    ops[4].valueU64  = memOffset;
    return;
}

void MicroBuilder::encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadZeroExtRegReg, emitFlags, 4);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = regDst;
    ops[1].reg       = regSrc;
    ops[2].opBits    = numBitsDst;
    ops[3].opBits    = numBitsSrc;
    return;
}

void MicroBuilder::encodeLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadAddrRegMem, emitFlags, 4);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = reg;
    ops[1].reg       = memReg;
    ops[2].opBits    = opBits;
    ops[3].valueU64  = memOffset;
    return;
}

void MicroBuilder::encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadAmcRegMem, emitFlags, 8);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = regDst;
    ops[1].reg       = regBase;
    ops[2].reg       = regMul;
    ops[3].opBits    = opBitsDst;
    ops[4].opBits    = opBitsSrc;
    ops[5].valueU64  = mulValue;
    ops[6].valueU64  = addValue;
    return;
}

void MicroBuilder::encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadAmcMemReg, emitFlags, 8);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = regBase;
    ops[1].reg       = regMul;
    ops[2].reg       = regSrc;
    ops[3].opBits    = opBitsBaseMul;
    ops[4].opBits    = opBitsSrc;
    ops[5].valueU64  = mulValue;
    ops[6].valueU64  = addValue;
    return;
}

void MicroBuilder::encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadAmcMemImm, emitFlags, 8);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = regBase;
    ops[1].reg       = regMul;
    ops[3].opBits    = opBitsBaseMul;
    ops[4].opBits    = opBitsValue;
    ops[5].valueU64  = mulValue;
    ops[6].valueU64  = addValue;
    ops[7].valueU64  = value;
    return;
}

void MicroBuilder::encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadAddrAmcRegMem, emitFlags, 8);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = regDst;
    ops[1].reg       = regBase;
    ops[2].reg       = regMul;
    ops[3].opBits    = opBitsDst;
    ops[4].opBits    = opBitsValue;
    ops[5].valueU64  = mulValue;
    ops[6].valueU64  = addValue;
    return;
}

void MicroBuilder::encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadMemReg, emitFlags, 4);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = memReg;
    ops[1].reg       = reg;
    ops[2].opBits    = opBits;
    ops[3].valueU64  = memOffset;
    return;
}

void MicroBuilder::encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadMemImm, emitFlags, 4);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = memReg;
    ops[1].opBits    = opBits;
    ops[2].valueU64  = memOffset;
    ops[3].valueU64  = value;
    return;
}

void MicroBuilder::encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::CmpRegReg, emitFlags, 3);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = reg0;
    ops[1].reg       = reg1;
    ops[2].opBits    = opBits;
    return;
}

void MicroBuilder::encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::CmpMemReg, emitFlags, 4);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = memReg;
    ops[1].reg       = reg;
    ops[2].opBits    = opBits;
    ops[3].valueU64  = memOffset;
    return;
}

void MicroBuilder::encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::CmpMemImm, emitFlags, 4);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = memReg;
    ops[1].opBits    = opBits;
    ops[2].valueU64  = memOffset;
    ops[3].valueU64  = value;
    return;
}

void MicroBuilder::encodeCmpRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::CmpRegImm, emitFlags, 3);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = reg;
    ops[1].opBits    = opBits;
    ops[2].valueU64  = value;
    return;
}

void MicroBuilder::encodeSetCondReg(MicroReg reg, MicroCond cpuCond, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::SetCondReg, emitFlags, 2);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = reg;
    ops[1].cpuCond   = cpuCond;
    return;
}

void MicroBuilder::encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::LoadCondRegReg, emitFlags, 4);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = regDst;
    ops[1].reg       = regSrc;
    ops[2].cpuCond   = setType;
    ops[3].opBits    = opBits;
    return;
}

void MicroBuilder::encodeClearReg(MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::ClearReg, emitFlags, 2);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = reg;
    ops[1].opBits    = opBits;
    return;
}

void MicroBuilder::encodeOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpUnaryMem, emitFlags, 4);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = memReg;
    ops[1].opBits    = opBits;
    ops[2].microOp   = op;
    ops[3].valueU64  = memOffset;
    return;
}

void MicroBuilder::encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpUnaryReg, emitFlags, 3);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = reg;
    ops[1].opBits    = opBits;
    ops[2].microOp   = op;
    return;
}

void MicroBuilder::encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpBinaryRegReg, emitFlags, 4);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = regDst;
    ops[1].reg       = regSrc;
    ops[2].opBits    = opBits;
    ops[3].microOp   = op;
    return;
}

void MicroBuilder::encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpBinaryRegMem, emitFlags, 5);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = regDst;
    ops[1].reg       = memReg;
    ops[2].opBits    = opBits;
    ops[3].microOp   = op;
    ops[4].valueU64  = memOffset;
    return;
}

void MicroBuilder::encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpBinaryMemReg, emitFlags, 5);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = memReg;
    ops[1].reg       = reg;
    ops[2].opBits    = opBits;
    ops[3].microOp   = op;
    ops[4].valueU64  = memOffset;
    return;
}

void MicroBuilder::encodeOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpBinaryRegImm, emitFlags, 4);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = reg;
    ops[1].opBits    = opBits;
    ops[2].microOp   = op;
    ops[3].valueU64  = value;
    return;
}

void MicroBuilder::encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpBinaryMemImm, emitFlags, 5);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = memReg;
    ops[1].opBits    = opBits;
    ops[2].microOp   = op;
    ops[3].valueU64  = memOffset;
    ops[4].valueU64  = value;
    return;
}

void MicroBuilder::encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    const auto& inst = addInstruction(MicroInstrOpcode::OpTernaryRegRegReg, emitFlags, 5);
    auto*       ops  = inst.ops(operands_);
    ops[0].reg       = reg0;
    ops[1].reg       = reg1;
    ops[2].reg       = reg2;
    ops[3].opBits    = opBits;
    ops[4].microOp   = op;
    return;
}

void MicroBuilder::runPasses(const MicroPassManager& passes, Encoder* encoder, MicroPassContext& context)
{
    context.encoder          = encoder;
    context.taskContext      = ctx_;
    context.builder          = this;
    context.instructions     = &instructions_;
    context.operands         = &operands_;
    context.passPrintOptions = printPassOptions_;

    passes.run(context);
}

Utf8 MicroBuilder::formatInstructions(MicroRegPrintMode regPrintMode, const Encoder* encoder) const
{
    return MicroPrinter::format(ctx(), instructions_, operands_, regPrintMode, encoder, this);
}

void MicroBuilder::printInstructions(MicroRegPrintMode regPrintMode, const Encoder* encoder) const
{
    MicroPrinter::print(ctx(), instructions_, operands_, regPrintMode, encoder, this);
}

void MicroBuilder::setPrintLocation(Utf8 symbolName, Utf8 filePath, uint32_t sourceLine)
{
    printSymbolName_ = std::move(symbolName);
    printFilePath_   = std::move(filePath);
    printSourceLine_ = sourceLine;
}

SWC_END_NAMESPACE();
