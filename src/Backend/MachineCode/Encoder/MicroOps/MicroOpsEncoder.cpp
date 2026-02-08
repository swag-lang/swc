#include "pch.h"
#include "Backend/MachineCode/Encoder/MicroOps/MicroOpsEncoder.h"

SWC_BEGIN_NAMESPACE();

MicroInstruction& MicroOpsEncoder::addInstruction(MicroOp op, EmitFlags emitFlags)
{
    MicroInstruction inst{};
    inst.op        = op;
    inst.emitFlags = emitFlags;
    instructions_.push_back(inst);
    return instructions_.back();
}

EncodeResult MicroOpsEncoder::encodeLoadSymbolRelocAddress(CpuReg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags)
{
    auto& inst                    = addInstruction(MicroOp::SymbolRelocAddr, emitFlags);
    inst.payload.regValue2.regA   = reg;
    inst.payload.regValue2.valueA = symbolIndex;
    inst.payload.regValue2.valueB = offset;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadSymRelocValue(CpuReg reg, uint32_t symbolIndex, uint32_t offset, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                           = addInstruction(MicroOp::SymbolRelocValue, emitFlags);
    inst.payload.regValue2OpBits.regA    = reg;
    inst.payload.regValue2OpBits.valueA  = symbolIndex;
    inst.payload.regValue2OpBits.valueB  = offset;
    inst.payload.regValue2OpBits.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodePush(CpuReg reg, EmitFlags emitFlags)
{
    auto& inst            = addInstruction(MicroOp::Push, emitFlags);
    inst.payload.reg.regA = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodePop(CpuReg reg, EmitFlags emitFlags)
{
    auto& inst            = addInstruction(MicroOp::Pop, emitFlags);
    inst.payload.reg.regA = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeNop(EmitFlags emitFlags)
{
    addInstruction(MicroOp::Nop, emitFlags);
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeRet(EmitFlags emitFlags)
{
    addInstruction(MicroOp::Ret, emitFlags);
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeCallLocal(const Utf8& symbolName, const CallConv* callConv, EmitFlags emitFlags)
{
    auto&      inst      = addInstruction(MicroOp::CallLocal, emitFlags);
    const auto nameIndex = static_cast<uint32_t>(callNames_.size());
    callNames_.push_back(symbolName);
    inst.payload.callName.nameIndex = nameIndex;
    inst.payload.callName.cc        = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeCallExtern(const Utf8& symbolName, const CallConv* callConv, EmitFlags emitFlags)
{
    auto&      inst      = addInstruction(MicroOp::CallExtern, emitFlags);
    const auto nameIndex = static_cast<uint32_t>(callNames_.size());
    callNames_.push_back(symbolName);
    inst.payload.callName.nameIndex = nameIndex;
    inst.payload.callName.cc        = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeCallReg(CpuReg reg, const CallConv* callConv, EmitFlags emitFlags)
{
    auto& inst                = addInstruction(MicroOp::CallIndirect, emitFlags);
    inst.payload.callReg.regA = reg;
    inst.payload.callReg.cc   = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeJumpTable(CpuReg tableReg, CpuReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags)
{
    auto& inst                    = addInstruction(MicroOp::JumpTable, emitFlags);
    inst.payload.jumpTable.regA   = tableReg;
    inst.payload.jumpTable.regB   = offsetReg;
    inst.payload.jumpTable.valueA = currentIp;
    inst.payload.jumpTable.valueB = offsetTable;
    inst.payload.jumpTable.valueC = numEntries;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeJump(CpuJump& jump, CpuCondJump jumpType, CpuOpBits opBits, EmitFlags emitFlags)
{
    jump.offsetStart               = instructions_.size() * sizeof(MicroInstruction);
    jump.opBits                    = opBits;
    auto& inst                     = addInstruction(MicroOp::JumpCond, emitFlags);
    inst.payload.jumpCond.jumpType = jumpType;
    inst.payload.jumpCond.opBitsA  = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodePatchJump(const CpuJump& jump, uint64_t offsetDestination, EmitFlags emitFlags)
{
    auto& inst                    = addInstruction(MicroOp::PatchJump, emitFlags);
    inst.payload.patchJump.valueA = jump.offsetStart;
    inst.payload.patchJump.valueB = offsetDestination;
    inst.payload.patchJump.valueC = 1;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodePatchJump(const CpuJump& jump, EmitFlags emitFlags)
{
    auto& inst                    = addInstruction(MicroOp::PatchJump, emitFlags);
    inst.payload.patchJump.valueA = jump.offsetStart;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeJumpReg(CpuReg reg, EmitFlags emitFlags)
{
    auto& inst            = addInstruction(MicroOp::JumpM, emitFlags);
    inst.payload.reg.regA = reg;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                             = addInstruction(MicroOp::LoadRM, emitFlags);
    inst.payload.regRegValueOpBits.regA    = reg;
    inst.payload.regRegValueOpBits.regB    = memReg;
    inst.payload.regRegValueOpBits.valueA  = memOffset;
    inst.payload.regRegValueOpBits.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadRegImm(CpuReg reg, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                          = addInstruction(MicroOp::LoadRI, emitFlags);
    inst.payload.regValueOpBits.regA    = reg;
    inst.payload.regValueOpBits.valueA  = value;
    inst.payload.regValueOpBits.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                        = addInstruction(MicroOp::LoadRR, emitFlags);
    inst.payload.regRegOpBits.regA    = regDst;
    inst.payload.regRegOpBits.regB    = regSrc;
    inst.payload.regRegOpBits.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadSignedExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)
{
    auto& inst                              = addInstruction(MicroOp::LoadSignedExtRM, emitFlags);
    inst.payload.regRegValueOpBits2.regA    = reg;
    inst.payload.regRegValueOpBits2.regB    = memReg;
    inst.payload.regRegValueOpBits2.valueA  = memOffset;
    inst.payload.regRegValueOpBits2.opBitsA = numBitsDst;
    inst.payload.regRegValueOpBits2.opBitsB = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadSignedExtendRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)
{
    auto& inst                         = addInstruction(MicroOp::LoadSignedExtRR, emitFlags);
    inst.payload.regRegOpBits2.regA    = regDst;
    inst.payload.regRegOpBits2.regB    = regSrc;
    inst.payload.regRegOpBits2.opBitsA = numBitsDst;
    inst.payload.regRegOpBits2.opBitsB = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadZeroExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)
{
    auto& inst                              = addInstruction(MicroOp::LoadZeroExtRM, emitFlags);
    inst.payload.regRegValueOpBits2.regA    = reg;
    inst.payload.regRegValueOpBits2.regB    = memReg;
    inst.payload.regRegValueOpBits2.valueA  = memOffset;
    inst.payload.regRegValueOpBits2.opBitsA = numBitsDst;
    inst.payload.regRegValueOpBits2.opBitsB = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadZeroExtendRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)
{
    auto& inst                         = addInstruction(MicroOp::LoadZeroExtRR, emitFlags);
    inst.payload.regRegOpBits2.regA    = regDst;
    inst.payload.regRegOpBits2.regB    = regSrc;
    inst.payload.regRegOpBits2.opBitsA = numBitsDst;
    inst.payload.regRegOpBits2.opBitsB = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadAddressRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                             = addInstruction(MicroOp::LoadAddrRM, emitFlags);
    inst.payload.regRegValueOpBits.regA    = reg;
    inst.payload.regRegValueOpBits.regB    = memReg;
    inst.payload.regRegValueOpBits.valueA  = memOffset;
    inst.payload.regRegValueOpBits.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadAmcRegMem(CpuReg regDst, CpuOpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsSrc, EmitFlags emitFlags)
{
    auto& inst               = addInstruction(MicroOp::LoadAmcRM, emitFlags);
    inst.payload.amc.regA    = regDst;
    inst.payload.amc.regB    = regBase;
    inst.payload.amc.regC    = regMul;
    inst.payload.amc.valueA  = mulValue;
    inst.payload.amc.valueB  = addValue;
    inst.payload.amc.opBitsA = opBitsDst;
    inst.payload.amc.opBitsB = opBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadAmcMemReg(CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsBaseMul, CpuReg regSrc, CpuOpBits opBitsSrc, EmitFlags emitFlags)
{
    auto& inst               = addInstruction(MicroOp::LoadAmcMR, emitFlags);
    inst.payload.amc.regA    = regBase;
    inst.payload.amc.regB    = regMul;
    inst.payload.amc.regC    = regSrc;
    inst.payload.amc.valueA  = mulValue;
    inst.payload.amc.valueB  = addValue;
    inst.payload.amc.opBitsA = opBitsBaseMul;
    inst.payload.amc.opBitsB = opBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadAmcMemImm(CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsBaseMul, uint64_t value, CpuOpBits opBitsValue, EmitFlags emitFlags)
{
    auto& inst               = addInstruction(MicroOp::LoadAmcMI, emitFlags);
    inst.payload.amc.regA    = regBase;
    inst.payload.amc.regB    = regMul;
    inst.payload.amc.valueA  = mulValue;
    inst.payload.amc.valueB  = addValue;
    inst.payload.amc.valueC  = value;
    inst.payload.amc.opBitsA = opBitsBaseMul;
    inst.payload.amc.opBitsB = opBitsValue;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadAddressAmcRegMem(CpuReg regDst, CpuOpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsValue, EmitFlags emitFlags)
{
    auto& inst               = addInstruction(MicroOp::LoadAddrAmcRM, emitFlags);
    inst.payload.amc.regA    = regDst;
    inst.payload.amc.regB    = regBase;
    inst.payload.amc.regC    = regMul;
    inst.payload.amc.valueA  = mulValue;
    inst.payload.amc.valueB  = addValue;
    inst.payload.amc.opBitsA = opBitsDst;
    inst.payload.amc.opBitsB = opBitsValue;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                             = addInstruction(MicroOp::LoadMR, emitFlags);
    inst.payload.regRegValueOpBits.regA    = memReg;
    inst.payload.regRegValueOpBits.regB    = reg;
    inst.payload.regRegValueOpBits.valueA  = memOffset;
    inst.payload.regRegValueOpBits.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                           = addInstruction(MicroOp::LoadMI, emitFlags);
    inst.payload.regValue2OpBits.regA    = memReg;
    inst.payload.regValue2OpBits.valueA  = memOffset;
    inst.payload.regValue2OpBits.valueB  = value;
    inst.payload.regValue2OpBits.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeCmpRegReg(CpuReg reg0, CpuReg reg1, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                        = addInstruction(MicroOp::CmpRR, emitFlags);
    inst.payload.regRegOpBits.regA    = reg0;
    inst.payload.regRegOpBits.regB    = reg1;
    inst.payload.regRegOpBits.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeCmpMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                             = addInstruction(MicroOp::CmpMR, emitFlags);
    inst.payload.regRegValueOpBits.regA    = memReg;
    inst.payload.regRegValueOpBits.regB    = reg;
    inst.payload.regRegValueOpBits.valueA  = memOffset;
    inst.payload.regRegValueOpBits.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeCmpMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                           = addInstruction(MicroOp::CmpMI, emitFlags);
    inst.payload.regValue2OpBits.regA    = memReg;
    inst.payload.regValue2OpBits.valueA  = memOffset;
    inst.payload.regValue2OpBits.valueB  = value;
    inst.payload.regValue2OpBits.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeCmpRegImm(CpuReg reg, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                          = addInstruction(MicroOp::CmpRI, emitFlags);
    inst.payload.regValueOpBits.regA    = reg;
    inst.payload.regValueOpBits.valueA  = value;
    inst.payload.regValueOpBits.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeSetCondReg(CpuReg reg, CpuCond cpuCond, EmitFlags emitFlags)
{
    auto& inst                   = addInstruction(MicroOp::SetCondR, emitFlags);
    inst.payload.regCond.regA    = reg;
    inst.payload.regCond.cpuCond = cpuCond;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadCondRegReg(CpuReg regDst, CpuReg regSrc, CpuCond setType, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                            = addInstruction(MicroOp::LoadCondRR, emitFlags);
    inst.payload.regRegCondOpBits.regA    = regDst;
    inst.payload.regRegCondOpBits.regB    = regSrc;
    inst.payload.regRegCondOpBits.cpuCond = setType;
    inst.payload.regRegCondOpBits.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeClearReg(CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                     = addInstruction(MicroOp::ClearR, emitFlags);
    inst.payload.regOpBits.regA    = reg;
    inst.payload.regOpBits.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpUnaryMem(CpuReg memReg, uint64_t memOffset, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                               = addInstruction(MicroOp::OpUnaryM, emitFlags);
    inst.payload.regValueOpBitsCpuOp.regA    = memReg;
    inst.payload.regValueOpBitsCpuOp.valueA  = memOffset;
    inst.payload.regValueOpBitsCpuOp.cpuOp   = op;
    inst.payload.regValueOpBitsCpuOp.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpUnaryReg(CpuReg reg, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                          = addInstruction(MicroOp::OpUnaryR, emitFlags);
    inst.payload.regOpBitsCpuOp.regA    = reg;
    inst.payload.regOpBitsCpuOp.cpuOp   = op;
    inst.payload.regOpBitsCpuOp.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpBinaryRegReg(CpuReg regDst, CpuReg regSrc, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                             = addInstruction(MicroOp::OpBinaryRR, emitFlags);
    inst.payload.regRegOpBitsCpuOp.regA    = regDst;
    inst.payload.regRegOpBitsCpuOp.regB    = regSrc;
    inst.payload.regRegOpBitsCpuOp.cpuOp   = op;
    inst.payload.regRegOpBitsCpuOp.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpBinaryRegMem(CpuReg regDst, CpuReg memReg, uint64_t memOffset, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                                  = addInstruction(MicroOp::OpBinaryRM, emitFlags);
    inst.payload.regRegValueOpBitsCpuOp.regA    = regDst;
    inst.payload.regRegValueOpBitsCpuOp.regB    = memReg;
    inst.payload.regRegValueOpBitsCpuOp.valueA  = memOffset;
    inst.payload.regRegValueOpBitsCpuOp.cpuOp   = op;
    inst.payload.regRegValueOpBitsCpuOp.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpBinaryMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                                  = addInstruction(MicroOp::OpBinaryMR, emitFlags);
    inst.payload.regRegValueOpBitsCpuOp.regA    = memReg;
    inst.payload.regRegValueOpBitsCpuOp.regB    = reg;
    inst.payload.regRegValueOpBitsCpuOp.valueA  = memOffset;
    inst.payload.regRegValueOpBitsCpuOp.cpuOp   = op;
    inst.payload.regRegValueOpBitsCpuOp.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpBinaryRegImm(CpuReg reg, uint64_t value, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                               = addInstruction(MicroOp::OpBinaryRI, emitFlags);
    inst.payload.regValueOpBitsCpuOp.regA    = reg;
    inst.payload.regValueOpBitsCpuOp.valueA  = value;
    inst.payload.regValueOpBitsCpuOp.cpuOp   = op;
    inst.payload.regValueOpBitsCpuOp.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpBinaryMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                                = addInstruction(MicroOp::OpBinaryMI, emitFlags);
    inst.payload.regValue2OpBitsCpuOp.regA    = memReg;
    inst.payload.regValue2OpBitsCpuOp.valueA  = memOffset;
    inst.payload.regValue2OpBitsCpuOp.valueB  = value;
    inst.payload.regValue2OpBitsCpuOp.cpuOp   = op;
    inst.payload.regValue2OpBitsCpuOp.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpTernaryRegRegReg(CpuReg reg0, CpuReg reg1, CpuReg reg2, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                   = addInstruction(MicroOp::OpTernaryRRR, emitFlags);
    inst.payload.ternary.regA    = reg0;
    inst.payload.ternary.regB    = reg1;
    inst.payload.ternary.regC    = reg2;
    inst.payload.ternary.cpuOp   = op;
    inst.payload.ternary.opBitsA = opBits;
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

void MicroOpsEncoder::encode(Encoder& encoder) const
{
    std::vector<CpuJump> jumps(instructions_.size());
    std::vector          jumpValid(instructions_.size(), false);

    for (size_t idx = 0; idx < instructions_.size(); ++idx)
    {
        const auto& inst = instructions_[idx];
        if (inst.op == MicroOp::End)
            break;

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
                encoder.encodeLoadSymbolRelocAddress(inst.payload.regValue2.regA,
                                                     static_cast<uint32_t>(inst.payload.regValue2.valueA),
                                                     static_cast<uint32_t>(inst.payload.regValue2.valueB),
                                                     inst.emitFlags);
                break;
            case MicroOp::SymbolRelocValue:
                encoder.encodeLoadSymRelocValue(inst.payload.regValue2OpBits.regA,
                                                static_cast<uint32_t>(inst.payload.regValue2OpBits.valueA),
                                                static_cast<uint32_t>(inst.payload.regValue2OpBits.valueB),
                                                inst.payload.regValue2OpBits.opBitsA,
                                                inst.emitFlags);
                break;
            case MicroOp::Push:
                encoder.encodePush(inst.payload.reg.regA, inst.emitFlags);
                break;
            case MicroOp::Pop:
                encoder.encodePop(inst.payload.reg.regA, inst.emitFlags);
                break;
            case MicroOp::Nop:
                encoder.encodeNop(inst.emitFlags);
                break;
            case MicroOp::Ret:
                encoder.encodeRet(inst.emitFlags);
                break;
            case MicroOp::CallLocal:
                encoder.encodeCallLocal(callNames_[inst.payload.callName.nameIndex], inst.payload.callName.cc, inst.emitFlags);
                break;
            case MicroOp::CallExtern:
                encoder.encodeCallExtern(callNames_[inst.payload.callName.nameIndex], inst.payload.callName.cc, inst.emitFlags);
                break;
            case MicroOp::CallIndirect:
                encoder.encodeCallReg(inst.payload.callReg.regA, inst.payload.callReg.cc, inst.emitFlags);
                break;
            case MicroOp::JumpTable:
                encoder.encodeJumpTable(inst.payload.jumpTable.regA,
                                        inst.payload.jumpTable.regB,
                                        static_cast<int32_t>(inst.payload.jumpTable.valueA),
                                        static_cast<uint32_t>(inst.payload.jumpTable.valueB),
                                        static_cast<uint32_t>(inst.payload.jumpTable.valueC),
                                        inst.emitFlags);
                break;
            case MicroOp::JumpCond:
            {
                CpuJump jump;
                encoder.encodeJump(jump, inst.payload.jumpCond.jumpType, inst.payload.jumpCond.opBitsA, inst.emitFlags);
                jumps[idx]     = jump;
                jumpValid[idx] = true;
                break;
            }
            case MicroOp::PatchJump:
            {
                const size_t jumpIndex = resolveJumpIndex(inst.payload.patchJump.valueA);
                SWC_ASSERT(jumpIndex < jumpValid.size());
                SWC_ASSERT(jumpValid[jumpIndex]);
                if (inst.payload.patchJump.valueC == 1)
                    encoder.encodePatchJump(jumps[jumpIndex], inst.payload.patchJump.valueB, inst.emitFlags);
                else
                    encoder.encodePatchJump(jumps[jumpIndex], inst.emitFlags);
                break;
            }
            case MicroOp::JumpCondI:
            {
                CpuJump    jump;
                const auto opBits = inst.payload.jumpCondImm.opBitsA == CpuOpBits::Zero ? CpuOpBits::B32 : inst.payload.jumpCondImm.opBitsA;
                encoder.encodeJump(jump, inst.payload.jumpCondImm.jumpType, opBits, inst.emitFlags);
                encoder.encodePatchJump(jump, inst.payload.jumpCondImm.valueA, inst.emitFlags);
                break;
            }
            case MicroOp::JumpM:
                encoder.encodeJumpReg(inst.payload.reg.regA, inst.emitFlags);
                break;
            case MicroOp::LoadRR:
                encoder.encodeLoadRegReg(inst.payload.regRegOpBits.regA, inst.payload.regRegOpBits.regB, inst.payload.regRegOpBits.opBitsA, inst.emitFlags);
                break;
            case MicroOp::LoadRI:
                encoder.encodeLoadRegImm(inst.payload.regValueOpBits.regA, inst.payload.regValueOpBits.valueA, inst.payload.regValueOpBits.opBitsA, inst.emitFlags);
                break;
            case MicroOp::LoadRM:
                encoder.encodeLoadRegMem(inst.payload.regRegValueOpBits.regA, inst.payload.regRegValueOpBits.regB, inst.payload.regRegValueOpBits.valueA, inst.payload.regRegValueOpBits.opBitsA, inst.emitFlags);
                break;
            case MicroOp::LoadSignedExtRM:
                encoder.encodeLoadSignedExtendRegMem(inst.payload.regRegValueOpBits2.regA,
                                                     inst.payload.regRegValueOpBits2.regB,
                                                     inst.payload.regRegValueOpBits2.valueA,
                                                     inst.payload.regRegValueOpBits2.opBitsA,
                                                     inst.payload.regRegValueOpBits2.opBitsB,
                                                     inst.emitFlags);
                break;
            case MicroOp::LoadSignedExtRR:
                encoder.encodeLoadSignedExtendRegReg(inst.payload.regRegOpBits2.regA, inst.payload.regRegOpBits2.regB, inst.payload.regRegOpBits2.opBitsA, inst.payload.regRegOpBits2.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadZeroExtRM:
                encoder.encodeLoadZeroExtendRegMem(inst.payload.regRegValueOpBits2.regA,
                                                   inst.payload.regRegValueOpBits2.regB,
                                                   inst.payload.regRegValueOpBits2.valueA,
                                                   inst.payload.regRegValueOpBits2.opBitsA,
                                                   inst.payload.regRegValueOpBits2.opBitsB,
                                                   inst.emitFlags);
                break;
            case MicroOp::LoadZeroExtRR:
                encoder.encodeLoadZeroExtendRegReg(inst.payload.regRegOpBits2.regA, inst.payload.regRegOpBits2.regB, inst.payload.regRegOpBits2.opBitsA, inst.payload.regRegOpBits2.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadAddrRM:
                encoder.encodeLoadAddressRegMem(inst.payload.regRegValueOpBits.regA,
                                                inst.payload.regRegValueOpBits.regB,
                                                inst.payload.regRegValueOpBits.valueA,
                                                inst.payload.regRegValueOpBits.opBitsA,
                                                inst.emitFlags);
                break;
            case MicroOp::LoadAmcMR:
                encoder.encodeLoadAmcMemReg(inst.payload.amc.regA,
                                            inst.payload.amc.regB,
                                            inst.payload.amc.valueA,
                                            inst.payload.amc.valueB,
                                            inst.payload.amc.opBitsA,
                                            inst.payload.amc.regC,
                                            inst.payload.amc.opBitsB,
                                            inst.emitFlags);
                break;
            case MicroOp::LoadAmcMI:
                encoder.encodeLoadAmcMemImm(inst.payload.amc.regA,
                                            inst.payload.amc.regB,
                                            inst.payload.amc.valueA,
                                            inst.payload.amc.valueB,
                                            inst.payload.amc.opBitsA,
                                            inst.payload.amc.valueC,
                                            inst.payload.amc.opBitsB,
                                            inst.emitFlags);
                break;
            case MicroOp::LoadAmcRM:
                encoder.encodeLoadAmcRegMem(inst.payload.amc.regA,
                                            inst.payload.amc.opBitsA,
                                            inst.payload.amc.regB,
                                            inst.payload.amc.regC,
                                            inst.payload.amc.valueA,
                                            inst.payload.amc.valueB,
                                            inst.payload.amc.opBitsB,
                                            inst.emitFlags);
                break;
            case MicroOp::LoadAddrAmcRM:
                encoder.encodeLoadAddressAmcRegMem(inst.payload.amc.regA,
                                                   inst.payload.amc.opBitsA,
                                                   inst.payload.amc.regB,
                                                   inst.payload.amc.regC,
                                                   inst.payload.amc.valueA,
                                                   inst.payload.amc.valueB,
                                                   inst.payload.amc.opBitsB,
                                                   inst.emitFlags);
                break;
            case MicroOp::LoadMR:
                encoder.encodeLoadMemReg(inst.payload.regRegValueOpBits.regA,
                                         inst.payload.regRegValueOpBits.valueA,
                                         inst.payload.regRegValueOpBits.regB,
                                         inst.payload.regRegValueOpBits.opBitsA,
                                         inst.emitFlags);
                break;
            case MicroOp::LoadMI:
                encoder.encodeLoadMemImm(inst.payload.regValue2OpBits.regA,
                                         inst.payload.regValue2OpBits.valueA,
                                         inst.payload.regValue2OpBits.valueB,
                                         inst.payload.regValue2OpBits.opBitsA,
                                         inst.emitFlags);
                break;
            case MicroOp::CmpRR:
                encoder.encodeCmpRegReg(inst.payload.regRegOpBits.regA, inst.payload.regRegOpBits.regB, inst.payload.regRegOpBits.opBitsA, inst.emitFlags);
                break;
            case MicroOp::CmpRI:
                encoder.encodeCmpRegImm(inst.payload.regValueOpBits.regA, inst.payload.regValueOpBits.valueA, inst.payload.regValueOpBits.opBitsA, inst.emitFlags);
                break;
            case MicroOp::CmpMR:
                encoder.encodeCmpMemReg(inst.payload.regRegValueOpBits.regA,
                                        inst.payload.regRegValueOpBits.valueA,
                                        inst.payload.regRegValueOpBits.regB,
                                        inst.payload.regRegValueOpBits.opBitsA,
                                        inst.emitFlags);
                break;
            case MicroOp::CmpMI:
                encoder.encodeCmpMemImm(inst.payload.regValue2OpBits.regA,
                                        inst.payload.regValue2OpBits.valueA,
                                        inst.payload.regValue2OpBits.valueB,
                                        inst.payload.regValue2OpBits.opBitsA,
                                        inst.emitFlags);
                break;
            case MicroOp::SetCondR:
                encoder.encodeSetCondReg(inst.payload.regCond.regA, inst.payload.regCond.cpuCond, inst.emitFlags);
                break;
            case MicroOp::LoadCondRR:
                encoder.encodeLoadCondRegReg(inst.payload.regRegCondOpBits.regA,
                                             inst.payload.regRegCondOpBits.regB,
                                             inst.payload.regRegCondOpBits.cpuCond,
                                             inst.payload.regRegCondOpBits.opBitsA,
                                             inst.emitFlags);
                break;
            case MicroOp::ClearR:
                encoder.encodeClearReg(inst.payload.regOpBits.regA, inst.payload.regOpBits.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpUnaryM:
                encoder.encodeOpUnaryMem(inst.payload.regValueOpBitsCpuOp.regA,
                                         inst.payload.regValueOpBitsCpuOp.valueA,
                                         inst.payload.regValueOpBitsCpuOp.cpuOp,
                                         inst.payload.regValueOpBitsCpuOp.opBitsA,
                                         inst.emitFlags);
                break;
            case MicroOp::OpUnaryR:
                encoder.encodeOpUnaryReg(inst.payload.regOpBitsCpuOp.regA,
                                         inst.payload.regOpBitsCpuOp.cpuOp,
                                         inst.payload.regOpBitsCpuOp.opBitsA,
                                         inst.emitFlags);
                break;
            case MicroOp::OpBinaryRR:
                encoder.encodeOpBinaryRegReg(inst.payload.regRegOpBitsCpuOp.regA,
                                             inst.payload.regRegOpBitsCpuOp.regB,
                                             inst.payload.regRegOpBitsCpuOp.cpuOp,
                                             inst.payload.regRegOpBitsCpuOp.opBitsA,
                                             inst.emitFlags);
                break;
            case MicroOp::OpBinaryMR:
                encoder.encodeOpBinaryMemReg(inst.payload.regRegValueOpBitsCpuOp.regA,
                                             inst.payload.regRegValueOpBitsCpuOp.valueA,
                                             inst.payload.regRegValueOpBitsCpuOp.regB,
                                             inst.payload.regRegValueOpBitsCpuOp.cpuOp,
                                             inst.payload.regRegValueOpBitsCpuOp.opBitsA,
                                             inst.emitFlags);
                break;
            case MicroOp::OpBinaryRI:
                encoder.encodeOpBinaryRegImm(inst.payload.regValueOpBitsCpuOp.regA,
                                             inst.payload.regValueOpBitsCpuOp.valueA,
                                             inst.payload.regValueOpBitsCpuOp.cpuOp,
                                             inst.payload.regValueOpBitsCpuOp.opBitsA,
                                             inst.emitFlags);
                break;
            case MicroOp::OpBinaryMI:
                encoder.encodeOpBinaryMemImm(inst.payload.regValue2OpBitsCpuOp.regA,
                                             inst.payload.regValue2OpBitsCpuOp.valueA,
                                             inst.payload.regValue2OpBitsCpuOp.valueB,
                                             inst.payload.regValue2OpBitsCpuOp.cpuOp,
                                             inst.payload.regValue2OpBitsCpuOp.opBitsA,
                                             inst.emitFlags);
                break;
            case MicroOp::OpBinaryRM:
                encoder.encodeOpBinaryRegMem(inst.payload.regRegValueOpBitsCpuOp.regA,
                                             inst.payload.regRegValueOpBitsCpuOp.regB,
                                             inst.payload.regRegValueOpBitsCpuOp.valueA,
                                             inst.payload.regRegValueOpBitsCpuOp.cpuOp,
                                             inst.payload.regRegValueOpBitsCpuOp.opBitsA,
                                             inst.emitFlags);
                break;
            case MicroOp::OpTernaryRRR:
                encoder.encodeOpTernaryRegRegReg(inst.payload.ternary.regA,
                                                 inst.payload.ternary.regB,
                                                 inst.payload.ternary.regC,
                                                 inst.payload.ternary.cpuOp,
                                                 inst.payload.ternary.opBitsA,
                                                 inst.emitFlags);
                break;
            default:
                SWC_ASSERT(false);
                break;
        }
    }
}

SWC_END_NAMESPACE();
