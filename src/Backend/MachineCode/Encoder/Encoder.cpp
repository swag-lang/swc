#include "pch.h"
#include "Backend/MachineCode/Encoder/Encoder.h"

SWC_BEGIN_NAMESPACE();

void Encoder::emitLoadSymRelocAddress(Cpu::Reg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags)
{
    encodeLoadSymbolRelocAddress(reg, symbolIndex, offset, emitFlags);
}

void Encoder::emitJumpReg(Cpu::Reg reg, EmitFlags emitFlags)
{
    encodeJumpReg(reg, emitFlags);
}

void Encoder::emitOpBinaryRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    encodeOpBinaryRegReg(regDst, regSrc, op, opBits, emitFlags);
}

void Encoder::emitOpBinaryRegImm(Cpu::Reg reg, uint64_t value, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    encodeOpBinaryRegImm(reg, value, op, opBits, emitFlags);
}

void Encoder::emitLoadRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    encodeLoadRegReg(regDst, regSrc, opBits, emitFlags);
}

void Encoder::emitLoadRegImm(Cpu::Reg reg, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    encodeLoadRegImm(reg, value, opBits, emitFlags);
}

void Encoder::emitLoadSignedExtendRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags)
{
    encodeLoadSignedExtendRegReg(regDst, regSrc, numBitsDst, numBitsSrc, emitFlags);
}

void Encoder::emitLoadZeroExtendRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags)
{
    encodeLoadZeroExtendRegReg(regDst, regSrc, numBitsDst, numBitsSrc, emitFlags);
}

void Encoder::emitClearReg(Cpu::Reg reg, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    encodeClearReg(reg, opBits, emitFlags);
}

Cpu::Symbol* Encoder::getOrAddSymbol(IdentifierRef name, Cpu::SymbolKind kind)
{
    symbols_.push_back(Cpu::Symbol{name, kind, 0, static_cast<uint32_t>(symbols_.size())});
    return &symbols_.back();
}

void Encoder::addSymbolRelocation(uint32_t, uint32_t, uint16_t)
{
}

SWC_END_NAMESPACE();
