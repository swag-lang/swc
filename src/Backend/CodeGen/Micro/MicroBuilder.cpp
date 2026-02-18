#include "pch.h"
#include "Backend/CodeGen/Micro/MicroBuilder.h"
#include "Backend/CodeGen/ABI/CallConv.h"
#include "Backend/CodeGen/Micro/MicroPrinter.h"
#include "Backend/CodeGen/Micro/Passes/MicroPass.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

std::pair<Ref, MicroInstr&> MicroBuilder::addInstructionWithRef(MicroInstrOpcode op, uint8_t numOperands)
{
    auto [instRef, inst] = instructions_.emplaceUninit();
    inst->op             = op;
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

MicroInstr& MicroBuilder::addInstruction(MicroInstrOpcode op, uint8_t numOperands)
{
    return addInstructionWithRef(op, numOperands).second;
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
    relocations_.push_back(relocation);
}

void MicroBuilder::addVirtualRegForbiddenPhysReg(MicroReg virtualReg, MicroReg forbiddenReg)
{
    SWC_ASSERT(virtualReg.isVirtual());
    SWC_ASSERT(forbiddenReg.isValid());
    SWC_ASSERT(!forbiddenReg.isVirtual());

    if (!virtualReg.isVirtual() || !forbiddenReg.isValid() || forbiddenReg.isVirtual())
        return;

    auto& forbiddenRegs = virtualRegForbiddenPhysRegs_[virtualReg.packed];
    for (const auto reg : forbiddenRegs)
    {
        if (reg == forbiddenReg)
            return;
    }

    forbiddenRegs.push_back(forbiddenReg);
}

void MicroBuilder::addVirtualRegForbiddenPhysRegs(MicroReg virtualReg, std::span<const MicroReg> forbiddenRegs)
{
    SWC_ASSERT(virtualReg.isVirtual());
    if (!virtualReg.isVirtual())
        return;

    for (const auto forbiddenReg : forbiddenRegs)
        addVirtualRegForbiddenPhysReg(virtualReg, forbiddenReg);
}

bool MicroBuilder::isVirtualRegPhysRegForbidden(MicroReg virtualReg, MicroReg physReg) const
{
    if (!virtualReg.isVirtual())
        return false;

    return isVirtualRegPhysRegForbidden(virtualReg.packed, physReg);
}

bool MicroBuilder::isVirtualRegPhysRegForbidden(uint32_t virtualRegKey, MicroReg physReg) const
{
    if (!physReg.isValid() || physReg.isVirtual())
        return false;

    const auto it = virtualRegForbiddenPhysRegs_.find(virtualRegKey);
    if (it == virtualRegForbiddenPhysRegs_.end())
        return false;

    for (const auto forbiddenReg : it->second)
    {
        if (forbiddenReg == physReg)
            return true;
    }

    return false;
}

void MicroBuilder::emitPush(MicroReg reg)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::Push, 1);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = reg;
    return;
}

void MicroBuilder::emitPop(MicroReg reg)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::Pop, 1);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = reg;
    return;
}

void MicroBuilder::emitNop()
{
    addInstruction(MicroInstrOpcode::Nop, 0);
    return;
}

Ref MicroBuilder::createLabel()
{
    const Ref labelRef = static_cast<Ref>(labels_.size());
    labels_.push_back(INVALID_REF);
    return labelRef;
}

void MicroBuilder::placeLabel(Ref labelRef)
{
    SWC_ASSERT(labelRef < labels_.size());
    SWC_ASSERT(labels_[labelRef] == INVALID_REF);

    auto [instRef, inst]   = addInstructionWithRef(MicroInstrOpcode::Label, 1);
    MicroInstrOperand* ops = inst.ops(operands_);
    ops[0].valueU64        = labelRef;
    labels_[labelRef]      = instRef;
    return;
}

void MicroBuilder::emitLabel(Ref& outLabelRef)
{
    outLabelRef = createLabel();
    return placeLabel(outLabelRef);
}

void MicroBuilder::emitRet()
{
    addInstruction(MicroInstrOpcode::Ret, 0);
    return;
}

void MicroBuilder::emitCallLocal(Symbol* targetSymbol, CallConvKind callConv)
{
    // Convenience wrapper: materialize target address then use the generic indirect call opcode.
    const CallConv& conv = CallConv::get(callConv);
    emitLoadRegPtrImm(conv.intReturn, 0, ConstantRef::invalid(), targetSymbol);
    emitCallReg(conv.intReturn, callConv);
    return;
}

void MicroBuilder::emitCallExtern(Symbol* targetSymbol, CallConvKind callConv)
{
    // Extern/local share the same micro-level representation; relocation kind differs.
    const CallConv& conv = CallConv::get(callConv);
    emitLoadRegPtrImm(conv.intReturn, 0, ConstantRef::invalid(), targetSymbol);
    emitCallReg(conv.intReturn, callConv);
    return;
}

void MicroBuilder::emitCallReg(MicroReg reg, CallConvKind callConv)
{
    // Micro IR models calls as indirect calls carrying the selected calling convention.
    const auto&        inst = addInstruction(MicroInstrOpcode::CallIndirect, 2);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = reg;
    ops[1].callConv         = callConv;
    return;
}

void MicroBuilder::emitJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::JumpTable, 5);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = tableReg;
    ops[1].reg              = offsetReg;
    ops[2].valueI32         = currentIp;
    ops[3].valueU32         = offsetTable;
    ops[4].valueU32         = numEntries;
    return;
}

void MicroBuilder::emitJumpToLabel(MicroCond cpuCond, MicroOpBits opBits, Ref labelRef)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::JumpCond, 3);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].cpuCond          = cpuCond;
    ops[1].opBits           = opBits;
    ops[2].valueU64         = labelRef;
    return;
}

void MicroBuilder::emitJumpReg(MicroReg reg)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::JumpReg, 1);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = reg;
    return;
}

void MicroBuilder::emitLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::LoadRegMem, 4);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = reg;
    ops[1].reg              = memReg;
    ops[2].opBits           = opBits;
    ops[3].valueU64         = memOffset;
    return;
}

void MicroBuilder::emitLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::LoadRegImm, 3);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = reg;
    ops[1].opBits           = opBits;
    ops[2].valueU64         = value;
    return;
}

void MicroBuilder::emitLoadRegPtrImm(MicroReg reg, uint64_t value, ConstantRef constantRef, Symbol* targetSymbol)
{
    // Record relocation metadata so the emitter/JIT can patch the final absolute target.
    auto relocationKind = MicroRelocation::Kind::ConstantAddress;
    if (targetSymbol && targetSymbol->isFunction())
    {
        const SymbolFunction& targetFunction = targetSymbol->cast<SymbolFunction>();
        relocationKind                       = targetFunction.isForeign() ? MicroRelocation::Kind::ForeignFunctionAddress : MicroRelocation::Kind::LocalFunctionAddress;
    }

    auto [instRef, inst]   = addInstructionWithRef(MicroInstrOpcode::LoadRegPtrImm, 3);
    MicroInstrOperand* ops = inst.ops(operands_);
    ops[0].reg             = reg;
    ops[1].opBits          = MicroOpBits::B64;
    ops[2].valueU64        = value;

    addRelocation({
        .kind           = relocationKind,
        .instructionRef = instRef,
        .targetAddress  = value,
        .targetSymbol   = targetSymbol,
        .constantRef    = constantRef,
    });
}

void MicroBuilder::emitLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::LoadRegReg, 3);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = regDst;
    ops[1].reg              = regSrc;
    ops[2].opBits           = opBits;
    return;
}

void MicroBuilder::emitLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::LoadSignedExtRegMem, 5);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = reg;
    ops[1].reg              = memReg;
    ops[2].opBits           = numBitsDst;
    ops[3].opBits           = numBitsSrc;
    ops[4].valueU64         = memOffset;
    return;
}

void MicroBuilder::emitLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::LoadSignedExtRegReg, 4);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = regDst;
    ops[1].reg              = regSrc;
    ops[2].opBits           = numBitsDst;
    ops[3].opBits           = numBitsSrc;
    return;
}

void MicroBuilder::emitLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::LoadZeroExtRegMem, 5);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = reg;
    ops[1].reg              = memReg;
    ops[2].opBits           = numBitsDst;
    ops[3].opBits           = numBitsSrc;
    ops[4].valueU64         = memOffset;
    return;
}

void MicroBuilder::emitLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::LoadZeroExtRegReg, 4);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = regDst;
    ops[1].reg              = regSrc;
    ops[2].opBits           = numBitsDst;
    ops[3].opBits           = numBitsSrc;
    return;
}

void MicroBuilder::emitLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::LoadAddrRegMem, 4);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = reg;
    ops[1].reg              = memReg;
    ops[2].opBits           = opBits;
    ops[3].valueU64         = memOffset;
    return;
}

void MicroBuilder::emitLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::LoadAmcRegMem, 8);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = regDst;
    ops[1].reg              = regBase;
    ops[2].reg              = regMul;
    ops[3].opBits           = opBitsDst;
    ops[4].opBits           = opBitsSrc;
    ops[5].valueU64         = mulValue;
    ops[6].valueU64         = addValue;
    return;
}

void MicroBuilder::emitLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::LoadAmcMemReg, 8);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = regBase;
    ops[1].reg              = regMul;
    ops[2].reg              = regSrc;
    ops[3].opBits           = opBitsBaseMul;
    ops[4].opBits           = opBitsSrc;
    ops[5].valueU64         = mulValue;
    ops[6].valueU64         = addValue;
    return;
}

void MicroBuilder::emitLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::LoadAmcMemImm, 8);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = regBase;
    ops[1].reg              = regMul;
    ops[3].opBits           = opBitsBaseMul;
    ops[4].opBits           = opBitsValue;
    ops[5].valueU64         = mulValue;
    ops[6].valueU64         = addValue;
    ops[7].valueU64         = value;
    return;
}

void MicroBuilder::emitLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::LoadAddrAmcRegMem, 8);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = regDst;
    ops[1].reg              = regBase;
    ops[2].reg              = regMul;
    ops[3].opBits           = opBitsDst;
    ops[4].opBits           = opBitsValue;
    ops[5].valueU64         = mulValue;
    ops[6].valueU64         = addValue;
    return;
}

void MicroBuilder::emitLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::LoadMemReg, 4);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = memReg;
    ops[1].reg              = reg;
    ops[2].opBits           = opBits;
    ops[3].valueU64         = memOffset;
    return;
}

void MicroBuilder::emitLoadMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::LoadMemImm, 4);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = memReg;
    ops[1].opBits           = opBits;
    ops[2].valueU64         = memOffset;
    ops[3].valueU64         = value;
    return;
}

void MicroBuilder::emitCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::CmpRegReg, 3);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = reg0;
    ops[1].reg              = reg1;
    ops[2].opBits           = opBits;
    return;
}

void MicroBuilder::emitCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::CmpMemReg, 4);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = memReg;
    ops[1].reg              = reg;
    ops[2].opBits           = opBits;
    ops[3].valueU64         = memOffset;
    return;
}

void MicroBuilder::emitCmpMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::CmpMemImm, 4);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = memReg;
    ops[1].opBits           = opBits;
    ops[2].valueU64         = memOffset;
    ops[3].valueU64         = value;
    return;
}

void MicroBuilder::emitCmpRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::CmpRegImm, 3);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = reg;
    ops[1].opBits           = opBits;
    ops[2].valueU64         = value;
    return;
}

void MicroBuilder::emitSetCondReg(MicroReg reg, MicroCond cpuCond)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::SetCondReg, 2);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = reg;
    ops[1].cpuCond          = cpuCond;
    return;
}

void MicroBuilder::emitLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::LoadCondRegReg, 4);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = regDst;
    ops[1].reg              = regSrc;
    ops[2].cpuCond          = setType;
    ops[3].opBits           = opBits;
    return;
}

void MicroBuilder::emitClearReg(MicroReg reg, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::ClearReg, 2);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = reg;
    ops[1].opBits           = opBits;
    return;
}

void MicroBuilder::emitOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::OpUnaryMem, 4);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = memReg;
    ops[1].opBits           = opBits;
    ops[2].microOp          = op;
    ops[3].valueU64         = memOffset;
    return;
}

void MicroBuilder::emitOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::OpUnaryReg, 3);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = reg;
    ops[1].opBits           = opBits;
    ops[2].microOp          = op;
    return;
}

void MicroBuilder::emitOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::OpBinaryRegReg, 4);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = regDst;
    ops[1].reg              = regSrc;
    ops[2].opBits           = opBits;
    ops[3].microOp          = op;
    return;
}

void MicroBuilder::emitOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::OpBinaryRegMem, 5);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = regDst;
    ops[1].reg              = memReg;
    ops[2].opBits           = opBits;
    ops[3].microOp          = op;
    ops[4].valueU64         = memOffset;
    return;
}

void MicroBuilder::emitOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::OpBinaryMemReg, 5);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = memReg;
    ops[1].reg              = reg;
    ops[2].opBits           = opBits;
    ops[3].microOp          = op;
    ops[4].valueU64         = memOffset;
    return;
}

void MicroBuilder::emitOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::OpBinaryRegImm, 4);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = reg;
    ops[1].opBits           = opBits;
    ops[2].microOp          = op;
    ops[3].valueU64         = value;
    return;
}

void MicroBuilder::emitOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOp op, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::OpBinaryMemImm, 5);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = memReg;
    ops[1].opBits           = opBits;
    ops[2].microOp          = op;
    ops[3].valueU64         = memOffset;
    ops[4].valueU64         = value;
    return;
}

void MicroBuilder::emitOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::OpTernaryRegRegReg, 5);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = reg0;
    ops[1].reg              = reg1;
    ops[2].reg              = reg2;
    ops[3].opBits           = opBits;
    ops[4].microOp          = op;
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
