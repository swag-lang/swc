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
    Micro::RegSet getReadRegisters(const MicroInstruction& inst) override;
    Micro::RegSet getWriteRegisters(const MicroInstruction& inst) override;

    EncodeResult encodeLoadSymbolRelocAddress(Micro::Reg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags) override;
    EncodeResult encodeLoadSymRelocValue(Micro::Reg reg, uint32_t symbolIndex, uint32_t offset, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodePush(Micro::Reg reg, EmitFlags emitFlags) override;
    EncodeResult encodePop(Micro::Reg reg, EmitFlags emitFlags) override;
    EncodeResult encodeNop(EmitFlags emitFlags) override;
    EncodeResult encodeRet(EmitFlags emitFlags) override;
    EncodeResult encodeCallLocal(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags) override;
    EncodeResult encodeCallExtern(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags) override;
    EncodeResult encodeCallReg(Micro::Reg reg, const CallConv* callConv, EmitFlags emitFlags) override;
    EncodeResult encodeJumpTable(Micro::Reg tableReg, Micro::Reg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags) override;
    EncodeResult encodeJump(Micro::Jump& jump, Micro::CondJump jumpType, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodePatchJump(const Micro::Jump& jump, uint64_t offsetDestination, EmitFlags emitFlags) override;
    EncodeResult encodePatchJump(const Micro::Jump& jump, EmitFlags emitFlags) override;
    EncodeResult encodeJumpReg(Micro::Reg reg, EmitFlags emitFlags) override;
    EncodeResult encodeLoadRegMem(Micro::Reg reg, Micro::Reg memReg, uint64_t memOffset, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeLoadRegImm(Micro::Reg reg, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeLoadRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeLoadSignedExtendRegMem(Micro::Reg reg, Micro::Reg memReg, uint64_t memOffset, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadSignedExtendRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadZeroExtendRegMem(Micro::Reg reg, Micro::Reg memReg, uint64_t memOffset, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadZeroExtendRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadAddressRegMem(Micro::Reg reg, Micro::Reg memReg, uint64_t memOffset, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeLoadAmcRegMem(Micro::Reg regDst, Micro::OpBits opBitsDst, Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadAmcMemReg(Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsBaseMul, Micro::Reg regSrc, Micro::OpBits opBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadAmcMemImm(Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsBaseMul, uint64_t value, Micro::OpBits opBitsValue, EmitFlags emitFlags) override;
    EncodeResult encodeLoadAddressAmcRegMem(Micro::Reg regDst, Micro::OpBits opBitsDst, Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsValue, EmitFlags emitFlags) override;
    EncodeResult encodeLoadMemReg(Micro::Reg memReg, uint64_t memOffset, Micro::Reg reg, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeLoadMemImm(Micro::Reg memReg, uint64_t memOffset, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeCmpRegReg(Micro::Reg reg0, Micro::Reg reg1, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeCmpMemReg(Micro::Reg memReg, uint64_t memOffset, Micro::Reg reg, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeCmpMemImm(Micro::Reg memReg, uint64_t memOffset, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeCmpRegImm(Micro::Reg reg, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeSetCondReg(Micro::Reg reg, Micro::Cond cpuCond, EmitFlags emitFlags) override;
    EncodeResult encodeLoadCondRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::Cond setType, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeClearReg(Micro::Reg reg, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpUnaryMem(Micro::Reg memReg, uint64_t memOffset, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpUnaryReg(Micro::Reg reg, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryRegMem(Micro::Reg regDst, Micro::Reg memReg, uint64_t memOffset, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryMemReg(Micro::Reg memReg, uint64_t memOffset, Micro::Reg reg, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryRegImm(Micro::Reg reg, uint64_t value, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryMemImm(Micro::Reg memReg, uint64_t memOffset, uint64_t value, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpTernaryRegRegReg(Micro::Reg reg0, Micro::Reg reg1, Micro::Reg reg2, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags) override;
};

SWC_END_NAMESPACE();
