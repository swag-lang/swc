#include "pch.h"
#include "Backend/MachineCode/Encoder/Encoder.h"

SWC_BEGIN_NAMESPACE();

void Encoder::emitLoadSymRelocAddress(MicroReg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags)
{
    encodeLoadSymbolRelocAddress(reg, symbolIndex, offset, emitFlags);
}

void Encoder::emitJumpReg(MicroReg reg, EmitFlags emitFlags)
{
    encodeJumpReg(reg, emitFlags);
}

void Encoder::emitOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags)
{
    encodeOpBinaryRegReg(regDst, regSrc, op, opBits, emitFlags);
}

void Encoder::emitOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags)
{
    encodeOpBinaryRegImm(reg, value, op, opBits, emitFlags);
}

void Encoder::emitLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits, EmitFlags emitFlags)
{
    encodeLoadRegReg(regDst, regSrc, opBits, emitFlags);
}

void Encoder::emitLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EmitFlags emitFlags)
{
    encodeLoadRegImm(reg, value, opBits, emitFlags);
}

void Encoder::emitLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EmitFlags emitFlags)
{
    encodeLoadSignedExtendRegReg(regDst, regSrc, numBitsDst, numBitsSrc, emitFlags);
}

void Encoder::emitLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EmitFlags emitFlags)
{
    encodeLoadZeroExtendRegReg(regDst, regSrc, numBitsDst, numBitsSrc, emitFlags);
}

void Encoder::emitClearReg(MicroReg reg, MicroOpBits opBits, EmitFlags emitFlags)
{
    encodeClearReg(reg, opBits, emitFlags);
}

EncoderSymbol* Encoder::getOrAddSymbol(IdentifierRef name, EncoderSymbolKind kind)
{
    symbols_.push_back(EncoderSymbol{name, kind, 0, static_cast<uint32_t>(symbols_.size())});
    return &symbols_.back();
}

void Encoder::addSymbolRelocation(uint32_t, uint32_t, uint16_t)
{
}

SWC_END_NAMESPACE();
