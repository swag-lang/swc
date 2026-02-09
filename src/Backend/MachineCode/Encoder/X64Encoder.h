#pragma once
#include "Backend/MachineCode/Encoder/Encoder.h"

#ifndef IMAGE_REL_AMD64_ADDR64
#define IMAGE_REL_AMD64_ADDR64 0x0001
#endif
#ifndef IMAGE_REL_AMD64_REL32
#define IMAGE_REL_AMD64_REL32 0x0004
#endif

SWC_BEGIN_NAMESPACE();

struct MicroInstr;

class X64Encoder : public Encoder
{
public:
    explicit X64Encoder(TaskContext& ctx) :
        Encoder(ctx)
    {
    }

private:
    MicroRegSet getReadRegisters(const MicroInstr& inst) override;
    MicroRegSet getWriteRegisters(const MicroInstr& inst) override;

    EncodeResult encodeLoadSymbolRelocAddress(MicroReg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags) override;
    EncodeResult encodeLoadSymRelocValue(MicroReg reg, uint32_t symbolIndex, uint32_t offset, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodePush(MicroReg reg, EmitFlags emitFlags) override;
    EncodeResult encodePop(MicroReg reg, EmitFlags emitFlags) override;
    EncodeResult encodeNop(EmitFlags emitFlags) override;
    EncodeResult encodeRet(EmitFlags emitFlags) override;
    EncodeResult encodeCallLocal(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags) override;
    EncodeResult encodeCallExtern(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags) override;
    EncodeResult encodeCallReg(MicroReg reg, const CallConv* callConv, EmitFlags emitFlags) override;
    EncodeResult encodeJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags) override;
    EncodeResult encodeJump(MicroJump& jump, MicroCondJump jumpType, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodePatchJump(const MicroJump& jump, uint64_t offsetDestination, EmitFlags emitFlags) override;
    EncodeResult encodePatchJump(const MicroJump& jump, EmitFlags emitFlags) override;
    EncodeResult encodeJumpReg(MicroReg reg, EmitFlags emitFlags) override;
    EncodeResult encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue, EmitFlags emitFlags) override;
    EncodeResult encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue, EmitFlags emitFlags) override;
    EncodeResult encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeCmpRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeSetCondReg(MicroReg reg, MicroCond cpuCond, EmitFlags emitFlags) override;
    EncodeResult encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeClearReg(MicroReg reg, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags) override;
};

SWC_END_NAMESPACE();
