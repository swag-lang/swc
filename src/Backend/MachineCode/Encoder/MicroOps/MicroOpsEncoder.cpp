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
    auto& inst                     = addInstruction(MicroOp::SymbolRelocValue, emitFlags);
    inst.payload.regVal2Op.regA    = reg;
    inst.payload.regVal2Op.valueA  = symbolIndex;
    inst.payload.regVal2Op.valueB  = offset;
    inst.payload.regVal2Op.opBitsA = opBits;
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

EncodeResult MicroOpsEncoder::encodeCallLocal(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)
{
    auto& inst                 = addInstruction(MicroOp::CallLocal, emitFlags);
    inst.payload.callName.name = symbolName;
    inst.payload.callName.cc   = callConv;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeCallExtern(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)
{
    auto& inst                 = addInstruction(MicroOp::CallExtern, emitFlags);
    inst.payload.callName.name = symbolName;
    inst.payload.callName.cc   = callConv;
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
    auto& inst                       = addInstruction(MicroOp::LoadRM, emitFlags);
    inst.payload.regRegValOp.regA    = reg;
    inst.payload.regRegValOp.regB    = memReg;
    inst.payload.regRegValOp.valueA  = memOffset;
    inst.payload.regRegValOp.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadRegImm(CpuReg reg, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                    = addInstruction(MicroOp::LoadRI, emitFlags);
    inst.payload.regValOp.regA    = reg;
    inst.payload.regValOp.valueA  = value;
    inst.payload.regValOp.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                    = addInstruction(MicroOp::LoadRR, emitFlags);
    inst.payload.regRegOp.regA    = regDst;
    inst.payload.regRegOp.regB    = regSrc;
    inst.payload.regRegOp.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadSignedExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)
{
    auto& inst                        = addInstruction(MicroOp::LoadSignedExtRM, emitFlags);
    inst.payload.regRegValOp2.regA    = reg;
    inst.payload.regRegValOp2.regB    = memReg;
    inst.payload.regRegValOp2.valueA  = memOffset;
    inst.payload.regRegValOp2.opBitsA = numBitsDst;
    inst.payload.regRegValOp2.opBitsB = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadSignedExtendRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)
{
    auto& inst                     = addInstruction(MicroOp::LoadSignedExtRR, emitFlags);
    inst.payload.regRegOp2.regA    = regDst;
    inst.payload.regRegOp2.regB    = regSrc;
    inst.payload.regRegOp2.opBitsA = numBitsDst;
    inst.payload.regRegOp2.opBitsB = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadZeroExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)
{
    auto& inst                        = addInstruction(MicroOp::LoadZeroExtRM, emitFlags);
    inst.payload.regRegValOp2.regA    = reg;
    inst.payload.regRegValOp2.regB    = memReg;
    inst.payload.regRegValOp2.valueA  = memOffset;
    inst.payload.regRegValOp2.opBitsA = numBitsDst;
    inst.payload.regRegValOp2.opBitsB = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadZeroExtendRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)
{
    auto& inst                     = addInstruction(MicroOp::LoadZeroExtRR, emitFlags);
    inst.payload.regRegOp2.regA    = regDst;
    inst.payload.regRegOp2.regB    = regSrc;
    inst.payload.regRegOp2.opBitsA = numBitsDst;
    inst.payload.regRegOp2.opBitsB = numBitsSrc;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadAddressRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                       = addInstruction(MicroOp::LoadAddrRM, emitFlags);
    inst.payload.regRegValOp.regA    = reg;
    inst.payload.regRegValOp.regB    = memReg;
    inst.payload.regRegValOp.valueA  = memOffset;
    inst.payload.regRegValOp.opBitsA = opBits;
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
    auto& inst                       = addInstruction(MicroOp::LoadMR, emitFlags);
    inst.payload.regRegValOp.regA    = memReg;
    inst.payload.regRegValOp.regB    = reg;
    inst.payload.regRegValOp.valueA  = memOffset;
    inst.payload.regRegValOp.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeLoadMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                     = addInstruction(MicroOp::LoadMI, emitFlags);
    inst.payload.regVal2Op.regA    = memReg;
    inst.payload.regVal2Op.valueA  = memOffset;
    inst.payload.regVal2Op.valueB  = value;
    inst.payload.regVal2Op.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeCmpRegReg(CpuReg reg0, CpuReg reg1, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                    = addInstruction(MicroOp::CmpRR, emitFlags);
    inst.payload.regRegOp.regA    = reg0;
    inst.payload.regRegOp.regB    = reg1;
    inst.payload.regRegOp.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeCmpMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                       = addInstruction(MicroOp::CmpMR, emitFlags);
    inst.payload.regRegValOp.regA    = memReg;
    inst.payload.regRegValOp.regB    = reg;
    inst.payload.regRegValOp.valueA  = memOffset;
    inst.payload.regRegValOp.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeCmpMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                     = addInstruction(MicroOp::CmpMI, emitFlags);
    inst.payload.regVal2Op.regA    = memReg;
    inst.payload.regVal2Op.valueA  = memOffset;
    inst.payload.regVal2Op.valueB  = value;
    inst.payload.regVal2Op.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeCmpRegImm(CpuReg reg, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                    = addInstruction(MicroOp::CmpRI, emitFlags);
    inst.payload.regValOp.regA    = reg;
    inst.payload.regValOp.valueA  = value;
    inst.payload.regValOp.opBitsA = opBits;
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
    auto& inst                 = addInstruction(MicroOp::ClearR, emitFlags);
    inst.payload.regOp.regA    = reg;
    inst.payload.regOp.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpUnaryMem(CpuReg memReg, uint64_t memOffset, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                       = addInstruction(MicroOp::OpUnaryM, emitFlags);
    inst.payload.regValOpCpu.regA    = memReg;
    inst.payload.regValOpCpu.valueA  = memOffset;
    inst.payload.regValOpCpu.cpuOp   = op;
    inst.payload.regValOpCpu.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpUnaryReg(CpuReg reg, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                    = addInstruction(MicroOp::OpUnaryR, emitFlags);
    inst.payload.regOpCpu.regA    = reg;
    inst.payload.regOpCpu.cpuOp   = op;
    inst.payload.regOpCpu.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpBinaryRegReg(CpuReg regDst, CpuReg regSrc, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                       = addInstruction(MicroOp::OpBinaryRR, emitFlags);
    inst.payload.regRegOpCpu.regA    = regDst;
    inst.payload.regRegOpCpu.regB    = regSrc;
    inst.payload.regRegOpCpu.cpuOp   = op;
    inst.payload.regRegOpCpu.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpBinaryRegMem(CpuReg regDst, CpuReg memReg, uint64_t memOffset, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                          = addInstruction(MicroOp::OpBinaryRM, emitFlags);
    inst.payload.regRegValOpCpu.regA    = regDst;
    inst.payload.regRegValOpCpu.regB    = memReg;
    inst.payload.regRegValOpCpu.valueA  = memOffset;
    inst.payload.regRegValOpCpu.cpuOp   = op;
    inst.payload.regRegValOpCpu.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpBinaryMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                          = addInstruction(MicroOp::OpBinaryMR, emitFlags);
    inst.payload.regRegValOpCpu.regA    = memReg;
    inst.payload.regRegValOpCpu.regB    = reg;
    inst.payload.regRegValOpCpu.valueA  = memOffset;
    inst.payload.regRegValOpCpu.cpuOp   = op;
    inst.payload.regRegValOpCpu.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpBinaryRegImm(CpuReg reg, uint64_t value, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                       = addInstruction(MicroOp::OpBinaryRI, emitFlags);
    inst.payload.regValOpCpu.regA    = reg;
    inst.payload.regValOpCpu.valueA  = value;
    inst.payload.regValOpCpu.cpuOp   = op;
    inst.payload.regValOpCpu.opBitsA = opBits;
    return EncodeResult::Zero;
}

EncodeResult MicroOpsEncoder::encodeOpBinaryMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    auto& inst                        = addInstruction(MicroOp::OpBinaryMI, emitFlags);
    inst.payload.regVal2OpCpu.regA    = memReg;
    inst.payload.regVal2OpCpu.valueA  = memOffset;
    inst.payload.regVal2OpCpu.valueB  = value;
    inst.payload.regVal2OpCpu.cpuOp   = op;
    inst.payload.regVal2OpCpu.opBitsA = opBits;
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

        const auto& pl = inst.payload;
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
                encoder.encodeLoadSymbolRelocAddress(pl.regValue2.regA, static_cast<uint32_t>(pl.regValue2.valueA), static_cast<uint32_t>(pl.regValue2.valueB), inst.emitFlags);
                break;
            case MicroOp::SymbolRelocValue:
                encoder.encodeLoadSymRelocValue(pl.regVal2Op.regA, static_cast<uint32_t>(pl.regVal2Op.valueA), static_cast<uint32_t>(pl.regVal2Op.valueB), pl.regVal2Op.opBitsA, inst.emitFlags);
                break;
            case MicroOp::Push:
                encoder.encodePush(pl.reg.regA, inst.emitFlags);
                break;
            case MicroOp::Pop:
                encoder.encodePop(pl.reg.regA, inst.emitFlags);
                break;
            case MicroOp::Nop:
                encoder.encodeNop(inst.emitFlags);
                break;
            case MicroOp::Ret:
                encoder.encodeRet(inst.emitFlags);
                break;
            case MicroOp::CallLocal:
                encoder.encodeCallLocal(pl.callName.name, pl.callName.cc, inst.emitFlags);
                break;
            case MicroOp::CallExtern:
                encoder.encodeCallExtern(pl.callName.name, pl.callName.cc, inst.emitFlags);
                break;
            case MicroOp::CallIndirect:
                encoder.encodeCallReg(pl.callReg.regA, pl.callReg.cc, inst.emitFlags);
                break;
            case MicroOp::JumpTable:
                encoder.encodeJumpTable(pl.jumpTable.regA, pl.jumpTable.regB, static_cast<int32_t>(pl.jumpTable.valueA), static_cast<uint32_t>(pl.jumpTable.valueB), static_cast<uint32_t>(pl.jumpTable.valueC), inst.emitFlags);
                break;
            case MicroOp::JumpCond:
            {
                CpuJump jump;
                encoder.encodeJump(jump, pl.jumpCond.jumpType, pl.jumpCond.opBitsA, inst.emitFlags);
                jumps[idx]     = jump;
                jumpValid[idx] = true;
                break;
            }
            case MicroOp::PatchJump:
            {
                const size_t jumpIndex = resolveJumpIndex(pl.patchJump.valueA);
                SWC_ASSERT(jumpIndex < jumpValid.size());
                SWC_ASSERT(jumpValid[jumpIndex]);
                if (pl.patchJump.valueC == 1)
                    encoder.encodePatchJump(jumps[jumpIndex], pl.patchJump.valueB, inst.emitFlags);
                else
                    encoder.encodePatchJump(jumps[jumpIndex], inst.emitFlags);
                break;
            }
            case MicroOp::JumpCondI:
            {
                CpuJump    jump;
                const auto opBits = pl.jumpCondImm.opBitsA == CpuOpBits::Zero ? CpuOpBits::B32 : pl.jumpCondImm.opBitsA;
                encoder.encodeJump(jump, pl.jumpCondImm.jumpType, opBits, inst.emitFlags);
                encoder.encodePatchJump(jump, pl.jumpCondImm.valueA, inst.emitFlags);
                break;
            }
            case MicroOp::JumpM:
                encoder.encodeJumpReg(pl.reg.regA, inst.emitFlags);
                break;
            case MicroOp::LoadRR:
                encoder.encodeLoadRegReg(pl.regRegOp.regA, pl.regRegOp.regB, pl.regRegOp.opBitsA, inst.emitFlags);
                break;
            case MicroOp::LoadRI:
                encoder.encodeLoadRegImm(pl.regValOp.regA, pl.regValOp.valueA, pl.regValOp.opBitsA, inst.emitFlags);
                break;
            case MicroOp::LoadRM:
                encoder.encodeLoadRegMem(pl.regRegValOp.regA, pl.regRegValOp.regB, pl.regRegValOp.valueA, pl.regRegValOp.opBitsA, inst.emitFlags);
                break;
            case MicroOp::LoadSignedExtRM:
                encoder.encodeLoadSignedExtendRegMem(pl.regRegValOp2.regA, pl.regRegValOp2.regB, pl.regRegValOp2.valueA, pl.regRegValOp2.opBitsA, pl.regRegValOp2.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadSignedExtRR:
                encoder.encodeLoadSignedExtendRegReg(pl.regRegOp2.regA, pl.regRegOp2.regB, pl.regRegOp2.opBitsA, pl.regRegOp2.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadZeroExtRM:
                encoder.encodeLoadZeroExtendRegMem(pl.regRegValOp2.regA, pl.regRegValOp2.regB, pl.regRegValOp2.valueA, pl.regRegValOp2.opBitsA, pl.regRegValOp2.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadZeroExtRR:
                encoder.encodeLoadZeroExtendRegReg(pl.regRegOp2.regA, pl.regRegOp2.regB, pl.regRegOp2.opBitsA, pl.regRegOp2.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadAddrRM:
                encoder.encodeLoadAddressRegMem(pl.regRegValOp.regA, pl.regRegValOp.regB, pl.regRegValOp.valueA, pl.regRegValOp.opBitsA, inst.emitFlags);
                break;
            case MicroOp::LoadAmcMR:
                encoder.encodeLoadAmcMemReg(pl.amc.regA, pl.amc.regB, pl.amc.valueA, pl.amc.valueB, pl.amc.opBitsA, pl.amc.regC, pl.amc.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadAmcMI:
                encoder.encodeLoadAmcMemImm(pl.amc.regA, pl.amc.regB, pl.amc.valueA, pl.amc.valueB, pl.amc.opBitsA, pl.amc.valueC, pl.amc.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadAmcRM:
                encoder.encodeLoadAmcRegMem(pl.amc.regA, pl.amc.opBitsA, pl.amc.regB, pl.amc.regC, pl.amc.valueA, pl.amc.valueB, pl.amc.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadAddrAmcRM:
                encoder.encodeLoadAddressAmcRegMem(pl.amc.regA, pl.amc.opBitsA, pl.amc.regB, pl.amc.regC, pl.amc.valueA, pl.amc.valueB, pl.amc.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadMR:
                encoder.encodeLoadMemReg(pl.regRegValOp.regA, pl.regRegValOp.valueA, pl.regRegValOp.regB, pl.regRegValOp.opBitsA, inst.emitFlags);
                break;
            case MicroOp::LoadMI:
                encoder.encodeLoadMemImm(pl.regVal2Op.regA, pl.regVal2Op.valueA, pl.regVal2Op.valueB, pl.regVal2Op.opBitsA, inst.emitFlags);
                break;
            case MicroOp::CmpRR:
                encoder.encodeCmpRegReg(pl.regRegOp.regA, pl.regRegOp.regB, pl.regRegOp.opBitsA, inst.emitFlags);
                break;
            case MicroOp::CmpRI:
                encoder.encodeCmpRegImm(pl.regValOp.regA, pl.regValOp.valueA, pl.regValOp.opBitsA, inst.emitFlags);
                break;
            case MicroOp::CmpMR:
                encoder.encodeCmpMemReg(pl.regRegValOp.regA, pl.regRegValOp.valueA, pl.regRegValOp.regB, pl.regRegValOp.opBitsA, inst.emitFlags);
                break;
            case MicroOp::CmpMI:
                encoder.encodeCmpMemImm(pl.regVal2Op.regA, pl.regVal2Op.valueA, pl.regVal2Op.valueB, pl.regVal2Op.opBitsA, inst.emitFlags);
                break;
            case MicroOp::SetCondR:
                encoder.encodeSetCondReg(pl.regCond.regA, pl.regCond.cpuCond, inst.emitFlags);
                break;
            case MicroOp::LoadCondRR:
                encoder.encodeLoadCondRegReg(pl.regRegCondOpBits.regA, pl.regRegCondOpBits.regB, pl.regRegCondOpBits.cpuCond, pl.regRegCondOpBits.opBitsA, inst.emitFlags);
                break;
            case MicroOp::ClearR:
                encoder.encodeClearReg(pl.regOp.regA, pl.regOp.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpUnaryM:
                encoder.encodeOpUnaryMem(pl.regValOpCpu.regA, pl.regValOpCpu.valueA, pl.regValOpCpu.cpuOp, pl.regValOpCpu.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpUnaryR:
                encoder.encodeOpUnaryReg(pl.regOpCpu.regA, pl.regOpCpu.cpuOp, pl.regOpCpu.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpBinaryRR:
                encoder.encodeOpBinaryRegReg(pl.regRegOpCpu.regA, pl.regRegOpCpu.regB, pl.regRegOpCpu.cpuOp, pl.regRegOpCpu.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpBinaryMR:
                encoder.encodeOpBinaryMemReg(pl.regRegValOpCpu.regA, pl.regRegValOpCpu.valueA, pl.regRegValOpCpu.regB, pl.regRegValOpCpu.cpuOp, pl.regRegValOpCpu.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpBinaryRI:
                encoder.encodeOpBinaryRegImm(pl.regValOpCpu.regA, pl.regValOpCpu.valueA, pl.regValOpCpu.cpuOp, pl.regValOpCpu.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpBinaryMI:
                encoder.encodeOpBinaryMemImm(pl.regVal2OpCpu.regA, pl.regVal2OpCpu.valueA, pl.regVal2OpCpu.valueB, pl.regVal2OpCpu.cpuOp, pl.regVal2OpCpu.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpBinaryRM:
                encoder.encodeOpBinaryRegMem(pl.regRegValOpCpu.regA, pl.regRegValOpCpu.regB, pl.regRegValOpCpu.valueA, pl.regRegValOpCpu.cpuOp, pl.regRegValOpCpu.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpTernaryRRR:
                encoder.encodeOpTernaryRegRegReg(pl.ternary.regA, pl.ternary.regB, pl.ternary.regC, pl.ternary.cpuOp, pl.ternary.opBitsA, inst.emitFlags);
                break;
            default:
                SWC_ASSERT(false);
                break;
        }
    }
}

SWC_END_NAMESPACE();
