#pragma once
#include "Backend/MachineCode/Encoder/Encoder.h"

#ifndef IMAGE_REL_AMD64_ADDR64
#define IMAGE_REL_AMD64_ADDR64 0x0001
#endif
#ifndef IMAGE_REL_AMD64_REL32
#define IMAGE_REL_AMD64_REL32 0x0004
#endif

SWC_BEGIN_NAMESPACE();

struct MicroInstruction;

class X64Encoder : public Encoder
{
public:
    explicit X64Encoder(TaskContext& ctx) :
        Encoder(ctx)
    {
    }

private:
    Cpu::RegSet getReadRegisters(const MicroInstruction& inst) override;
    Cpu::RegSet getWriteRegisters(const MicroInstruction& inst) override;

    EncodeResult encodeLoadSymbolRelocAddress(Cpu::Reg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags) override;
    EncodeResult encodeLoadSymRelocValue(Cpu::Reg reg, uint32_t symbolIndex, uint32_t offset, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodePush(Cpu::Reg reg, EmitFlags emitFlags) override;
    EncodeResult encodePop(Cpu::Reg reg, EmitFlags emitFlags) override;
    EncodeResult encodeNop(EmitFlags emitFlags) override;
    EncodeResult encodeRet(EmitFlags emitFlags) override;
    EncodeResult encodeCallLocal(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags) override;
    EncodeResult encodeCallExtern(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags) override;
    EncodeResult encodeCallReg(Cpu::Reg reg, const CallConv* callConv, EmitFlags emitFlags) override;
    EncodeResult encodeJumpTable(Cpu::Reg tableReg, Cpu::Reg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags) override;
    EncodeResult encodeJump(Cpu::Jump& jump, Cpu::CondJump jumpType, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodePatchJump(const Cpu::Jump& jump, uint64_t offsetDestination, EmitFlags emitFlags) override;
    EncodeResult encodePatchJump(const Cpu::Jump& jump, EmitFlags emitFlags) override;
    EncodeResult encodeJumpReg(Cpu::Reg reg, EmitFlags emitFlags) override;
    EncodeResult encodeLoadRegMem(Cpu::Reg reg, Cpu::Reg memReg, uint64_t memOffset, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeLoadRegImm(Cpu::Reg reg, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeLoadRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeLoadSignedExtendRegMem(Cpu::Reg reg, Cpu::Reg memReg, uint64_t memOffset, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadSignedExtendRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadZeroExtendRegMem(Cpu::Reg reg, Cpu::Reg memReg, uint64_t memOffset, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadZeroExtendRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadAddressRegMem(Cpu::Reg reg, Cpu::Reg memReg, uint64_t memOffset, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeLoadAmcRegMem(Cpu::Reg regDst, Cpu::OpBits opBitsDst, Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadAmcMemReg(Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsBaseMul, Cpu::Reg regSrc, Cpu::OpBits opBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadAmcMemImm(Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsBaseMul, uint64_t value, Cpu::OpBits opBitsValue, EmitFlags emitFlags) override;
    EncodeResult encodeLoadAddressAmcRegMem(Cpu::Reg regDst, Cpu::OpBits opBitsDst, Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsValue, EmitFlags emitFlags) override;
    EncodeResult encodeLoadMemReg(Cpu::Reg memReg, uint64_t memOffset, Cpu::Reg reg, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeLoadMemImm(Cpu::Reg memReg, uint64_t memOffset, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeCmpRegReg(Cpu::Reg reg0, Cpu::Reg reg1, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeCmpMemReg(Cpu::Reg memReg, uint64_t memOffset, Cpu::Reg reg, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeCmpMemImm(Cpu::Reg memReg, uint64_t memOffset, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeCmpRegImm(Cpu::Reg reg, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeSetCondReg(Cpu::Reg reg, Cpu::Cond cpuCond, EmitFlags emitFlags) override;
    EncodeResult encodeLoadCondRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::Cond setType, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeClearReg(Cpu::Reg reg, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpUnaryMem(Cpu::Reg memReg, uint64_t memOffset, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpUnaryReg(Cpu::Reg reg, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryRegMem(Cpu::Reg regDst, Cpu::Reg memReg, uint64_t memOffset, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryMemReg(Cpu::Reg memReg, uint64_t memOffset, Cpu::Reg reg, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryRegImm(Cpu::Reg reg, uint64_t value, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryMemImm(Cpu::Reg memReg, uint64_t memOffset, uint64_t value, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpTernaryRegRegReg(Cpu::Reg reg0, Cpu::Reg reg1, Cpu::Reg reg2, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags) override;
};

SWC_END_NAMESPACE();
