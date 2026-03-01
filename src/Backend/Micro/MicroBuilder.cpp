#include "pch.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Micro/MicroPass.h"
#include "Backend/Micro/MicroPrinter.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.h"

SWC_BEGIN_NAMESPACE();

std::pair<MicroInstrRef, MicroInstr&> MicroBuilder::addInstructionWithRef(MicroInstrOpcode op, uint8_t numOperands)
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
        inst->opsRef = MicroOperandRef::invalid();
    }

    storeInstructionDebugInfo(instRef);
    return {instRef, *SWC_NOT_NULL(inst)};
}

MicroInstr& MicroBuilder::addInstruction(MicroInstrOpcode op, uint8_t numOperands)
{
    return addInstructionWithRef(op, numOperands).second;
}

void MicroBuilder::storeInstructionDebugInfo(MicroInstrRef instructionRef)
{
    if (!hasFlag(MicroBuilderFlagsE::DebugInfo))
        return;

    MicroInstr* inst = instructions_.ptr(instructionRef);
    if (!inst)
        return;

    inst->sourceCodeRef = currentDebugSourceCodeRef_;
}

void MicroBuilder::setCurrentDebugSourceCodeRef(const SourceCodeRef& sourceCodeRef)
{
    if (!hasFlag(MicroBuilderFlagsE::DebugInfo))
        return;

    currentDebugSourceCodeRef_ = sourceCodeRef;
}

SourceCodeRef MicroBuilder::instructionSourceCodeRef(MicroInstrRef instructionRef) const
{
    if (!hasFlag(MicroBuilderFlagsE::DebugInfo))
        return SourceCodeRef::invalid();

    const MicroInstr* inst = instructions_.ptr(instructionRef);
    if (!inst)
        return SourceCodeRef::invalid();

    return inst->sourceCodeRef;
}

void MicroBuilder::addRelocation(const MicroRelocation& relocation)
{
    switch (relocation.kind)
    {
        case MicroRelocation::Kind::ConstantAddress:
            SWC_ASSERT(relocation.constantRef.isValid());
            break;

        case MicroRelocation::Kind::LocalFunctionAddress:
        case MicroRelocation::Kind::ForeignFunctionAddress:
            SWC_ASSERT(relocation.targetSymbol && relocation.targetSymbol->isFunction());
            break;

        default:
            SWC_UNREACHABLE();
    }

    relocations_.push_back(relocation);
}

bool MicroBuilder::invalidateRelocationForInstruction(MicroInstrRef instructionRef)
{
    bool changed = false;
    for (MicroRelocation& reloc : relocations_)
    {
        if (reloc.instructionRef != instructionRef)
            continue;

        reloc.instructionRef = MicroInstrRef::invalid();
        changed              = true;
    }

    return changed;
}

bool MicroBuilder::pruneDeadRelocations()
{
    if (relocations_.empty())
        return false;

    bool changed = false;
    for (MicroRelocation& reloc : relocations_)
    {
        if (reloc.instructionRef.isInvalid())
            continue;

        if (instructions_.ptr(reloc.instructionRef))
            continue;

        reloc.instructionRef = MicroInstrRef::invalid();
        changed              = true;
    }

    const auto beforeSize = relocations_.size();
    std::erase_if(relocations_, [](const MicroRelocation& reloc) {
        return reloc.instructionRef.isInvalid();
    });

    return changed || beforeSize != relocations_.size();
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

uint32_t MicroBuilder::nextVirtualIntRegIndexHint() const
{
    uint32_t nextIndex = 1;
    for (const auto& key : virtualRegForbiddenPhysRegs_ | std::views::keys)
    {
        const uint32_t virtualRegKey = key;
        MicroReg       reg;
        reg.packed = virtualRegKey;
        if (!reg.isVirtualInt())
            continue;

        if (reg.index() < MicroReg::K_MAX_INDEX)
            nextIndex = std::max(nextIndex, reg.index() + 1);
        else
            return MicroReg::K_MAX_INDEX;
    }

    return nextIndex;
}

const MicroControlFlowGraph& MicroBuilder::controlFlowGraph()
{
    const uint64_t storageRevision = instructions_.revision();
    if (hasControlFlowGraph_ && controlFlowGraphStorageRevision_ == storageRevision)
    {
        if (!controlFlowGraphMaybeDirty_)
            return controlFlowGraph_;

        const uint64_t hash = controlFlowGraph_.computeHash(instructions_, operands_);

        if (hash == controlFlowGraphHash_)
        {
            controlFlowGraphMaybeDirty_ = false;
            return controlFlowGraph_;
        }
    }

    controlFlowGraph_.build(instructions_, operands_);
    controlFlowGraphStorageRevision_ = storageRevision;
    controlFlowGraphHash_            = controlFlowGraph_.computeHash(instructions_, operands_);

    hasControlFlowGraph_        = true;
    controlFlowGraphMaybeDirty_ = false;
    return controlFlowGraph_;
}

void MicroBuilder::invalidateControlFlowGraph()
{
    hasControlFlowGraph_        = false;
    controlFlowGraphMaybeDirty_ = false;
}

void MicroBuilder::markControlFlowGraphMaybeDirty()
{
    if (hasControlFlowGraph_)
        controlFlowGraphMaybeDirty_ = true;
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

void MicroBuilder::emitBreakpoint()
{
    addInstruction(MicroInstrOpcode::Breakpoint, 0);
    return;
}

void MicroBuilder::emitAssertTrap()
{
    addInstruction(MicroInstrOpcode::AssertTrap, 0);
    return;
}

MicroLabelRef MicroBuilder::createLabel()
{
    const MicroLabelRef labelRef(static_cast<uint32_t>(labels_.size()));
    labels_.push_back(MicroInstrRef::invalid());
    return labelRef;
}

void MicroBuilder::placeLabel(MicroLabelRef labelRef)
{
    SWC_ASSERT(labelRef.get() < labels_.size());
    SWC_ASSERT(labels_[labelRef.get()].isInvalid());

    auto [instRef, inst]    = addInstructionWithRef(MicroInstrOpcode::Label, 1);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].valueU64         = labelRef.get();
    labels_[labelRef.get()] = instRef;
    return;
}

void MicroBuilder::emitLabel(MicroLabelRef& outLabelRef)
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
    SWC_ASSERT(targetSymbol && targetSymbol->isFunction());
    const SymbolFunction& targetFunction = targetSymbol->cast<SymbolFunction>();
    SWC_ASSERT(!targetFunction.isForeign());

    auto [instRef, inst]   = addInstructionWithRef(MicroInstrOpcode::CallLocal, 1);
    MicroInstrOperand* ops = inst.ops(operands_);
    ops[0].callConv        = callConv;

    addRelocation({
        .kind           = MicroRelocation::Kind::LocalFunctionAddress,
        .instructionRef = instRef,
        .targetAddress  = 0,
        .targetSymbol   = targetSymbol,
        .constantRef    = ConstantRef::invalid(),
    });
    return;
}

void MicroBuilder::emitCallExtern(Symbol* targetSymbol, CallConvKind callConv)
{
    SWC_ASSERT(targetSymbol && targetSymbol->isFunction());
    const SymbolFunction& targetFunction = targetSymbol->cast<SymbolFunction>();
    SWC_ASSERT(targetFunction.isForeign());

    auto [instRef, inst]   = addInstructionWithRef(MicroInstrOpcode::CallExtern, 1);
    MicroInstrOperand* ops = inst.ops(operands_);
    ops[0].callConv        = callConv;

    addRelocation({
        .kind           = MicroRelocation::Kind::ForeignFunctionAddress,
        .instructionRef = instRef,
        .targetAddress  = 0,
        .targetSymbol   = targetSymbol,
        .constantRef    = ConstantRef::invalid(),
    });
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

void MicroBuilder::emitJumpToLabel(MicroCond cpuCond, MicroOpBits opBits, MicroLabelRef labelRef)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::JumpCond, 3);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].cpuCond          = cpuCond;
    ops[1].opBits           = opBits;
    ops[2].valueU64         = labelRef.get();
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

void MicroBuilder::emitLoadRegImm(MicroReg reg, const ApInt& value, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::LoadRegImm, 3);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = reg;
    ops[1].opBits           = opBits;
    ops[2].setImmediateValue(value);
    return;
}

void MicroBuilder::emitLoadRegPtrImm(MicroReg reg, uint64_t value)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::LoadRegPtrImm, 3);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = reg;
    ops[1].opBits           = MicroOpBits::B64;
    ops[2].valueU64         = value;
}

void MicroBuilder::emitLoadRegPtrReloc(MicroReg reg, uint64_t value, ConstantRef constantRef, Symbol* targetSymbol)
{
    const bool hasFunctionTarget = targetSymbol && targetSymbol->isFunction();
    const bool hasConstantTarget = constantRef.isValid();
    SWC_ASSERT(!targetSymbol || hasFunctionTarget);
    SWC_ASSERT(hasConstantTarget || hasFunctionTarget);

    // Record relocation metadata so the emitter/JIT can patch the final absolute target.
    auto    relocationKind         = MicroRelocation::Kind::ConstantAddress;
    Symbol* relocationTargetSymbol = nullptr;
    if (hasFunctionTarget)
    {
        const SymbolFunction& targetFunction = targetSymbol->cast<SymbolFunction>();
        relocationKind                       = targetFunction.isForeign() ? MicroRelocation::Kind::ForeignFunctionAddress : MicroRelocation::Kind::LocalFunctionAddress;
        relocationTargetSymbol               = targetSymbol;
    }

    auto [instRef, inst]   = addInstructionWithRef(MicroInstrOpcode::LoadRegPtrReloc, 3);
    MicroInstrOperand* ops = inst.ops(operands_);
    ops[0].reg             = reg;
    ops[1].opBits          = MicroOpBits::B64;
    ops[2].valueU64        = value;

    addRelocation({
        .kind           = relocationKind,
        .instructionRef = instRef,
        .targetAddress  = value,
        .targetSymbol   = relocationTargetSymbol,
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

void MicroBuilder::emitLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, const ApInt& value, MicroOpBits opBitsValue)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::LoadAmcMemImm, 8);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = regBase;
    ops[1].reg              = regMul;
    ops[3].opBits           = opBitsBaseMul;
    ops[4].opBits           = opBitsValue;
    ops[5].valueU64         = mulValue;
    ops[6].valueU64         = addValue;
    ops[7].setImmediateValue(value);
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

void MicroBuilder::emitLoadMemImm(MicroReg memReg, uint64_t memOffset, const ApInt& value, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::LoadMemImm, 4);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = memReg;
    ops[1].opBits           = opBits;
    ops[2].valueU64         = memOffset;
    ops[3].setImmediateValue(value);
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

void MicroBuilder::emitCmpMemImm(MicroReg memReg, uint64_t memOffset, const ApInt& value, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::CmpMemImm, 4);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = memReg;
    ops[1].opBits           = opBits;
    ops[2].valueU64         = memOffset;
    ops[3].setImmediateValue(value);
    return;
}

void MicroBuilder::emitCmpRegImm(MicroReg reg, const ApInt& value, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::CmpRegImm, 3);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = reg;
    ops[1].opBits           = opBits;
    ops[2].setImmediateValue(value);
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

void MicroBuilder::emitOpBinaryRegImm(MicroReg reg, const ApInt& value, MicroOp op, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::OpBinaryRegImm, 4);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = reg;
    ops[1].opBits           = opBits;
    ops[2].microOp          = op;
    ops[3].setImmediateValue(value);
    return;
}

void MicroBuilder::emitOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, const ApInt& value, MicroOp op, MicroOpBits opBits)
{
    const auto&        inst = addInstruction(MicroInstrOpcode::OpBinaryMemImm, 5);
    MicroInstrOperand* ops  = inst.ops(operands_);
    ops[0].reg              = memReg;
    ops[1].opBits           = opBits;
    ops[2].microOp          = op;
    ops[3].valueU64         = memOffset;
    ops[4].setImmediateValue(value);
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

Result MicroBuilder::runPasses(const MicroPassManager& passes, Encoder* encoder, MicroPassContext& context)
{
    context.encoder          = encoder;
    context.taskContext      = ctx_;
    context.builder          = this;
    context.instructions     = &instructions_;
    context.operands         = &operands_;
    context.passPrintOptions = printPassOptions_;

    return passes.run(context);
}

Result MicroBuilder::runPasses(Encoder* encoder, MicroPassContext& context)
{
    passManager_.configureDefaultPipeline(backendBuildCfg_.optimize);
    return runPasses(passManager_, encoder, context);
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
