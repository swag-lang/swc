#include "pch.h"
#include "Backend/MachineCode/Encoder/Core/CpuEncoder.h"

SWC_BEGIN_NAMESPACE();

void CpuEncoder::emitLoadSymRelocAddress(CpuReg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags)
{
    encodeLoadSymbolRelocAddress(reg, symbolIndex, offset, emitFlags);
}

void CpuEncoder::emitJumpReg(CpuReg reg, EmitFlags emitFlags)
{
    encodeJumpReg(reg, emitFlags);
}

void CpuEncoder::emitOpBinaryRegReg(CpuReg regDst, CpuReg regSrc, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    encodeOpBinaryRegReg(regDst, regSrc, op, opBits, emitFlags);
}

void CpuEncoder::emitOpBinaryRegImm(CpuReg reg, uint64_t value, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    encodeOpBinaryRegImm(reg, value, op, opBits, emitFlags);
}

void CpuEncoder::emitLoadRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits opBits, EmitFlags emitFlags)
{
    encodeLoadRegReg(regDst, regSrc, opBits, emitFlags);
}

void CpuEncoder::emitLoadRegImm(CpuReg reg, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)
{
    encodeLoadRegImm(reg, value, opBits, emitFlags);
}

void CpuEncoder::emitLoadSignedExtendRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)
{
    encodeLoadSignedExtendRegReg(regDst, regSrc, numBitsDst, numBitsSrc, emitFlags);
}

void CpuEncoder::emitLoadZeroExtendRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)
{
    encodeLoadZeroExtendRegReg(regDst, regSrc, numBitsDst, numBitsSrc, emitFlags);
}

void CpuEncoder::emitClearReg(CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags)
{
    encodeClearReg(reg, opBits, emitFlags);
}

CpuSymbol* CpuEncoder::getOrAddSymbol(const Utf8& name, CpuSymbolKind kind)
{
    symbols_.push_back(CpuSymbol{name, kind, 0, static_cast<uint32_t>(symbols_.size())});
    return &symbols_.back();
}

void CpuEncoder::addSymbolRelocation(uint32_t, uint32_t, uint16_t)
{
}

SWC_END_NAMESPACE();
