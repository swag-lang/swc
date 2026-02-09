#include "pch.h"
#include "Backend/MachineCode/Encoder/Core/Encoder.h"

SWC_BEGIN_NAMESPACE();

void Encoder::emitLoadSymRelocAddress(CpuReg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags)
{
    encodeLoadSymbolRelocAddress(ctx(), reg, symbolIndex, offset, emitFlags);
}

void Encoder::emitJumpReg(CpuReg reg, EmitFlags emitFlags)
{
    encodeJumpReg(ctx(), reg, emitFlags);
}

void Encoder::emitOpBinaryRegReg(CpuReg regDst, CpuReg regSrc, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    encodeOpBinaryRegReg(ctx(), regDst, regSrc, op, opBits, emitFlags);
}

void Encoder::emitOpBinaryRegImm(CpuReg reg, uint64_t value, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags)
{
    encodeOpBinaryRegImm(ctx(), reg, value, op, opBits, emitFlags);
}

void Encoder::emitLoadRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits opBits, EmitFlags emitFlags)
{
    encodeLoadRegReg(ctx(), regDst, regSrc, opBits, emitFlags);
}

void Encoder::emitLoadRegImm(CpuReg reg, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags)
{
    encodeLoadRegImm(ctx(), reg, value, opBits, emitFlags);
}

void Encoder::emitLoadSignedExtendRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)
{
    encodeLoadSignedExtendRegReg(ctx(), regDst, regSrc, numBitsDst, numBitsSrc, emitFlags);
}

void Encoder::emitLoadZeroExtendRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags)
{
    encodeLoadZeroExtendRegReg(ctx(), regDst, regSrc, numBitsDst, numBitsSrc, emitFlags);
}

void Encoder::emitClearReg(CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags)
{
    encodeClearReg(ctx(), reg, opBits, emitFlags);
}

CpuSymbol* Encoder::getOrAddSymbol(IdentifierRef name, CpuSymbolKind kind)
{
    symbols_.push_back(CpuSymbol{name, kind, 0, static_cast<uint32_t>(symbols_.size())});
    return &symbols_.back();
}

void Encoder::addSymbolRelocation(uint32_t, uint32_t, uint16_t)
{
}

SWC_END_NAMESPACE();
