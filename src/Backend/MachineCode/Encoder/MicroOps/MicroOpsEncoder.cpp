#include "pch.h"
#include "Backend/MachineCode/Encoder/MicroOps/MicroOpsEncoder.h"

SWC_BEGIN_NAMESPACE();

MicroInstruction& MicroOpsEncoder::addInstruction(MicroOp op, CpuEmitFlags emitFlags)
{
    MicroInstruction inst{};
    inst.op        = op;
    inst.emitFlags = emitFlags;
    instructions_.push_back(inst);
    return instructions_.back();
}

CpuEncodeResult MicroOpsEncoder::encodeLoadSymbolRelocAddress(CpuReg reg, uint32_t symbolIndex, uint32_t offset, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::SymbolRelocAddr, emitFlags);
    inst.regA   = reg;
    inst.valueA = symbolIndex;
    inst.valueB = offset;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeLoadSymRelocValue(CpuReg reg, uint32_t symbolIndex, uint32_t offset, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::SymbolRelocValue, emitFlags);
    inst.regA   = reg;
    inst.valueA = symbolIndex;
    inst.valueB = offset;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodePush(CpuReg reg, CpuEmitFlags emitFlags)
{
    auto& inst = addInstruction(MicroOp::Push, emitFlags);
    inst.regA  = reg;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodePop(CpuReg reg, CpuEmitFlags emitFlags)
{
    auto& inst = addInstruction(MicroOp::Pop, emitFlags);
    inst.regA  = reg;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeNop(CpuEmitFlags emitFlags)
{
    addInstruction(MicroOp::Nop, emitFlags);
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeRet(CpuEmitFlags emitFlags)
{
    addInstruction(MicroOp::Ret, emitFlags);
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeCallLocal(const Utf8& symbolName, const CallConv* callConv, CpuEmitFlags emitFlags)
{
    auto& inst = addInstruction(MicroOp::CallLocal, emitFlags);
    inst.name  = symbolName;
    inst.cc    = callConv;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeCallExtern(const Utf8& symbolName, const CallConv* callConv, CpuEmitFlags emitFlags)
{
    auto& inst = addInstruction(MicroOp::CallExtern, emitFlags);
    inst.name  = symbolName;
    inst.cc    = callConv;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeCallReg(CpuReg reg, const CallConv* callConv, CpuEmitFlags emitFlags)
{
    auto& inst = addInstruction(MicroOp::CallIndirect, emitFlags);
    inst.regA  = reg;
    inst.cc    = callConv;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeJumpTable(CpuReg tableReg, CpuReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::JumpTable, emitFlags);
    inst.regA   = tableReg;
    inst.regB   = offsetReg;
    inst.valueA = currentIp;
    inst.valueB = offsetTable;
    inst.valueC = numEntries;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeJump(CpuJump& jump, CpuCondJump jumpType, OpBits opBits, CpuEmitFlags emitFlags)
{
    jump.offsetStart = instructions_.size() * sizeof(MicroInstruction);
    jump.opBits      = opBits;
    auto& inst       = addInstruction(MicroOp::JumpCond, emitFlags);
    inst.jumpType    = jumpType;
    inst.opBitsA     = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodePatchJump(const CpuJump& jump, uint64_t offsetDestination, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::PatchJump, emitFlags);
    inst.valueA = jump.offsetStart;
    inst.valueB = offsetDestination;
    inst.valueC = 1;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodePatchJump(const CpuJump& jump, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::PatchJump, emitFlags);
    inst.valueA = jump.offsetStart;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeJumpReg(CpuReg reg, CpuEmitFlags emitFlags)
{
    auto& inst = addInstruction(MicroOp::JumpM, emitFlags);
    inst.regA  = reg;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeLoadRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::LoadRM, emitFlags);
    inst.regA   = reg;
    inst.regB   = memReg;
    inst.valueA = memOffset;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeLoadRegImm(CpuReg reg, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::LoadRI, emitFlags);
    inst.regA   = reg;
    inst.valueA = value;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeLoadRegReg(CpuReg regDst, CpuReg regSrc, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::LoadRR, emitFlags);
    inst.regA   = regDst;
    inst.regB   = regSrc;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeLoadSignedExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::LoadSignedExtRM, emitFlags);
    inst.regA   = reg;
    inst.regB   = memReg;
    inst.valueA = memOffset;
    inst.opBitsA = numBitsDst;
    inst.opBitsB = numBitsSrc;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeLoadSignedExtendRegReg(CpuReg regDst, CpuReg regSrc, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::LoadSignedExtRR, emitFlags);
    inst.regA   = regDst;
    inst.regB   = regSrc;
    inst.opBitsA = numBitsDst;
    inst.opBitsB = numBitsSrc;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeLoadZeroExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::LoadZeroExtRM, emitFlags);
    inst.regA   = reg;
    inst.regB   = memReg;
    inst.valueA = memOffset;
    inst.opBitsA = numBitsDst;
    inst.opBitsB = numBitsSrc;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeLoadZeroExtendRegReg(CpuReg regDst, CpuReg regSrc, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::LoadZeroExtRR, emitFlags);
    inst.regA   = regDst;
    inst.regB   = regSrc;
    inst.opBitsA = numBitsDst;
    inst.opBitsB = numBitsSrc;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeLoadAddressRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::LoadAddrRM, emitFlags);
    inst.regA   = reg;
    inst.regB   = memReg;
    inst.valueA = memOffset;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeLoadAmcRegMem(CpuReg regDst, OpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsSrc, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::LoadAmcRM, emitFlags);
    inst.regA   = regDst;
    inst.regB   = regBase;
    inst.regC   = regMul;
    inst.valueA = mulValue;
    inst.valueB = addValue;
    inst.opBitsA = opBitsDst;
    inst.opBitsB = opBitsSrc;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeLoadAmcMemReg(CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsBaseMul, CpuReg regSrc, OpBits opBitsSrc, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::LoadAmcMR, emitFlags);
    inst.regA   = regBase;
    inst.regB   = regMul;
    inst.regC   = regSrc;
    inst.valueA = mulValue;
    inst.valueB = addValue;
    inst.opBitsA = opBitsBaseMul;
    inst.opBitsB = opBitsSrc;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeLoadAmcMemImm(CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsBaseMul, uint64_t value, OpBits opBitsValue, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::LoadAmcMI, emitFlags);
    inst.regA   = regBase;
    inst.regB   = regMul;
    inst.valueA = mulValue;
    inst.valueB = addValue;
    inst.valueC = value;
    inst.opBitsA = opBitsBaseMul;
    inst.opBitsB = opBitsValue;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeLoadAddressAmcRegMem(CpuReg regDst, OpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsValue, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::LoadAddrAmcRM, emitFlags);
    inst.regA   = regDst;
    inst.regB   = regBase;
    inst.regC   = regMul;
    inst.valueA = mulValue;
    inst.valueB = addValue;
    inst.opBitsA = opBitsDst;
    inst.opBitsB = opBitsValue;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeLoadMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::LoadMR, emitFlags);
    inst.regA   = memReg;
    inst.valueA = memOffset;
    inst.regB   = reg;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeLoadMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::LoadMI, emitFlags);
    inst.regA   = memReg;
    inst.valueA = memOffset;
    inst.valueB = value;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeCmpRegReg(CpuReg reg0, CpuReg reg1, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::CmpRR, emitFlags);
    inst.regA   = reg0;
    inst.regB   = reg1;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeCmpMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::CmpMR, emitFlags);
    inst.regA   = memReg;
    inst.valueA = memOffset;
    inst.regB   = reg;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeCmpMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::CmpMI, emitFlags);
    inst.regA   = memReg;
    inst.valueA = memOffset;
    inst.valueB = value;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeCmpRegImm(CpuReg reg, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::CmpRI, emitFlags);
    inst.regA   = reg;
    inst.valueA = value;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeSetCondReg(CpuReg reg, CpuCond cpuCond, CpuEmitFlags emitFlags)
{
    auto& inst = addInstruction(MicroOp::SetCondR, emitFlags);
    inst.regA  = reg;
    inst.cpuCond = cpuCond;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeLoadCondRegReg(CpuReg regDst, CpuReg regSrc, CpuCond setType, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::LoadCondRR, emitFlags);
    inst.regA   = regDst;
    inst.regB   = regSrc;
    inst.cpuCond = setType;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeClearReg(CpuReg reg, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::ClearR, emitFlags);
    inst.regA   = reg;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeOpUnaryMem(CpuReg memReg, uint64_t memOffset, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::OpUnaryM, emitFlags);
    inst.regA   = memReg;
    inst.valueA = memOffset;
    inst.cpuOp  = op;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeOpUnaryReg(CpuReg reg, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::OpUnaryR, emitFlags);
    inst.regA   = reg;
    inst.cpuOp  = op;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeOpBinaryRegReg(CpuReg regDst, CpuReg regSrc, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::OpBinaryRR, emitFlags);
    inst.regA   = regDst;
    inst.regB   = regSrc;
    inst.cpuOp  = op;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeOpBinaryRegMem(CpuReg regDst, CpuReg memReg, uint64_t memOffset, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::OpBinaryRM, emitFlags);
    inst.regA   = regDst;
    inst.regB   = memReg;
    inst.valueA = memOffset;
    inst.cpuOp  = op;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeOpBinaryMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::OpBinaryMR, emitFlags);
    inst.regA   = memReg;
    inst.valueA = memOffset;
    inst.regB   = reg;
    inst.cpuOp  = op;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeOpBinaryRegImm(CpuReg reg, uint64_t value, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::OpBinaryRI, emitFlags);
    inst.regA   = reg;
    inst.valueA = value;
    inst.cpuOp  = op;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeOpBinaryMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::OpBinaryMI, emitFlags);
    inst.regA   = memReg;
    inst.valueA = memOffset;
    inst.valueB = value;
    inst.cpuOp  = op;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult MicroOpsEncoder::encodeOpTernaryRegRegReg(CpuReg reg0, CpuReg reg1, CpuReg reg2, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)
{
    auto& inst  = addInstruction(MicroOp::OpTernaryRRR, emitFlags);
    inst.regA   = reg0;
    inst.regB   = reg1;
    inst.regC   = reg2;
    inst.cpuOp  = op;
    inst.opBitsA = opBits;
    return CpuEncodeResult::Zero;
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

void MicroOpsEncoder::encode(CpuEncoder& encoder) const
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
                encoder.encodeLoadSymbolRelocAddress(inst.regA, static_cast<uint32_t>(inst.valueA), static_cast<uint32_t>(inst.valueB), inst.emitFlags);
                break;
            case MicroOp::SymbolRelocValue:
                encoder.encodeLoadSymRelocValue(inst.regA, static_cast<uint32_t>(inst.valueA), static_cast<uint32_t>(inst.valueB), inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::Push:
                encoder.encodePush(inst.regA, inst.emitFlags);
                break;
            case MicroOp::Pop:
                encoder.encodePop(inst.regA, inst.emitFlags);
                break;
            case MicroOp::Nop:
                encoder.encodeNop(inst.emitFlags);
                break;
            case MicroOp::Ret:
                encoder.encodeRet(inst.emitFlags);
                break;
            case MicroOp::CallLocal:
                encoder.encodeCallLocal(inst.name, inst.cc, inst.emitFlags);
                break;
            case MicroOp::CallExtern:
                encoder.encodeCallExtern(inst.name, inst.cc, inst.emitFlags);
                break;
            case MicroOp::CallIndirect:
                encoder.encodeCallReg(inst.regA, inst.cc, inst.emitFlags);
                break;
            case MicroOp::JumpTable:
                encoder.encodeJumpTable(inst.regA, inst.regB, static_cast<int32_t>(inst.valueA), static_cast<uint32_t>(inst.valueB), static_cast<uint32_t>(inst.valueC), inst.emitFlags);
                break;
            case MicroOp::JumpCond:
            {
                CpuJump jump;
                encoder.encodeJump(jump, inst.jumpType, inst.opBitsA, inst.emitFlags);
                jumps[idx]     = jump;
                jumpValid[idx] = true;
                break;
            }
            case MicroOp::PatchJump:
            {
                const size_t jumpIndex = resolveJumpIndex(inst.valueA);
                SWC_ASSERT(jumpIndex < jumpValid.size());
                SWC_ASSERT(jumpValid[jumpIndex]);
                if (inst.valueC == 1)
                    encoder.encodePatchJump(jumps[jumpIndex], inst.valueB, inst.emitFlags);
                else
                    encoder.encodePatchJump(jumps[jumpIndex], inst.emitFlags);
                break;
            }
            case MicroOp::JumpCondI:
            {
                CpuJump jump;
                const auto opBits = inst.opBitsA == OpBits::Zero ? OpBits::B32 : inst.opBitsA;
                encoder.encodeJump(jump, inst.jumpType, opBits, inst.emitFlags);
                encoder.encodePatchJump(jump, inst.valueA, inst.emitFlags);
                break;
            }
            case MicroOp::JumpM:
                encoder.encodeJumpReg(inst.regA, inst.emitFlags);
                break;
            case MicroOp::LoadRR:
                encoder.encodeLoadRegReg(inst.regA, inst.regB, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::LoadRI:
                encoder.encodeLoadRegImm(inst.regA, inst.valueA, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::LoadRM:
                encoder.encodeLoadRegMem(inst.regA, inst.regB, inst.valueA, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::LoadSignedExtRM:
                encoder.encodeLoadSignedExtendRegMem(inst.regA, inst.regB, inst.valueA, inst.opBitsA, inst.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadSignedExtRR:
                encoder.encodeLoadSignedExtendRegReg(inst.regA, inst.regB, inst.opBitsA, inst.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadZeroExtRM:
                encoder.encodeLoadZeroExtendRegMem(inst.regA, inst.regB, inst.valueA, inst.opBitsA, inst.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadZeroExtRR:
                encoder.encodeLoadZeroExtendRegReg(inst.regA, inst.regB, inst.opBitsA, inst.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadAddrRM:
                encoder.encodeLoadAddressRegMem(inst.regA, inst.regB, inst.valueA, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::LoadAmcMR:
                encoder.encodeLoadAmcMemReg(inst.regA, inst.regB, inst.valueA, inst.valueB, inst.opBitsA, inst.regC, inst.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadAmcMI:
                encoder.encodeLoadAmcMemImm(inst.regA, inst.regB, inst.valueA, inst.valueB, inst.opBitsA, inst.valueC, inst.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadAmcRM:
                encoder.encodeLoadAmcRegMem(inst.regA, inst.opBitsA, inst.regB, inst.regC, inst.valueA, inst.valueB, inst.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadAddrAmcRM:
                encoder.encodeLoadAddressAmcRegMem(inst.regA, inst.opBitsA, inst.regB, inst.regC, inst.valueA, inst.valueB, inst.opBitsB, inst.emitFlags);
                break;
            case MicroOp::LoadMR:
                encoder.encodeLoadMemReg(inst.regA, inst.valueA, inst.regB, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::LoadMI:
                encoder.encodeLoadMemImm(inst.regA, inst.valueA, inst.valueB, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::CmpRR:
                encoder.encodeCmpRegReg(inst.regA, inst.regB, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::CmpRI:
                encoder.encodeCmpRegImm(inst.regA, inst.valueA, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::CmpMR:
                encoder.encodeCmpMemReg(inst.regA, inst.valueA, inst.regB, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::CmpMI:
                encoder.encodeCmpMemImm(inst.regA, inst.valueA, inst.valueB, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::SetCondR:
                encoder.encodeSetCondReg(inst.regA, inst.cpuCond, inst.emitFlags);
                break;
            case MicroOp::LoadCondRR:
                encoder.encodeLoadCondRegReg(inst.regA, inst.regB, inst.cpuCond, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::ClearR:
                encoder.encodeClearReg(inst.regA, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpUnaryM:
                encoder.encodeOpUnaryMem(inst.regA, inst.valueA, inst.cpuOp, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpUnaryR:
                encoder.encodeOpUnaryReg(inst.regA, inst.cpuOp, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpBinaryRR:
                encoder.encodeOpBinaryRegReg(inst.regA, inst.regB, inst.cpuOp, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpBinaryMR:
                encoder.encodeOpBinaryMemReg(inst.regA, inst.valueA, inst.regB, inst.cpuOp, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpBinaryRI:
                encoder.encodeOpBinaryRegImm(inst.regA, inst.valueA, inst.cpuOp, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpBinaryMI:
                encoder.encodeOpBinaryMemImm(inst.regA, inst.valueA, inst.valueB, inst.cpuOp, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpBinaryRM:
                encoder.encodeOpBinaryRegMem(inst.regA, inst.regB, inst.valueA, inst.cpuOp, inst.opBitsA, inst.emitFlags);
                break;
            case MicroOp::OpTernaryRRR:
                encoder.encodeOpTernaryRegRegReg(inst.regA, inst.regB, inst.regC, inst.cpuOp, inst.opBitsA, inst.emitFlags);
                break;
            default:
                SWC_ASSERT(false);
                break;
        }
    }
}

SWC_END_NAMESPACE();
