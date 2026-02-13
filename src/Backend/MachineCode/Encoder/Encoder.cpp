#include "pch.h"
#include "Backend/MachineCode/Encoder/Encoder.h"

SWC_BEGIN_NAMESPACE();

const uint8_t* Encoder::data() const
{
    if (!store_.size())
        return nullptr;
    return store_.ptr<uint8_t>(0);
}

uint8_t Encoder::byteAt(uint32_t index) const
{
    SWC_ASSERT(index < store_.size());
    return *store_.ptr<uint8_t>(index);
}

void Encoder::copyTo(std::span<std::byte> dst) const
{
    store_.copyTo(dst);
}

Encoder::Encoder(TaskContext& ctx) :
    ctx_(&ctx)
{
}

void Encoder::emitLoadSymRelocAddress(MicroReg reg, uint32_t symbolIndex, uint32_t offset, EncodeFlags emitFlags)
{
    encodeLoadSymbolRelocAddress(reg, symbolIndex, offset, emitFlags);
}

void Encoder::emitJumpReg(MicroReg reg, EncodeFlags emitFlags)
{
    encodeJumpReg(reg, emitFlags);
}

void Encoder::emitOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    encodeOpBinaryRegReg(regDst, regSrc, op, opBits, emitFlags);
}

void Encoder::emitOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    encodeOpBinaryRegImm(reg, value, op, opBits, emitFlags);
}

void Encoder::emitLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits, EncodeFlags emitFlags)
{
    encodeLoadRegReg(regDst, regSrc, opBits, emitFlags);
}

void Encoder::emitLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    encodeLoadRegImm(reg, value, opBits, emitFlags);
}

void Encoder::emitLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    encodeLoadSignedExtendRegReg(regDst, regSrc, numBitsDst, numBitsSrc, emitFlags);
}

void Encoder::emitLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    encodeLoadZeroExtendRegReg(regDst, regSrc, numBitsDst, numBitsSrc, emitFlags);
}

void Encoder::emitClearReg(MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)
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
