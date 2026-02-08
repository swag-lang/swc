#pragma once
#include "Backend/MachineCode/Encoder/Core/CpuEncoder.h"

SWC_BEGIN_NAMESPACE();

struct MicroInstruction;

class X64Encoder : CpuEncoder
{
public:
    RegisterSet getReadRegisters(const MicroInstruction& inst) override;
    RegisterSet getWriteRegisters(const MicroInstruction& inst) override;

    EncodeResult encodeLoadSymbolRelocAddress(CpuReg reg, uint32_t symbolIndex, uint32_t offset, CpuEmitFlags emitFlags) override;
    EncodeResult encodeLoadSymRelocValue(CpuReg reg, uint32_t symbolIndex, uint32_t offset, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodePush(CpuReg reg, CpuEmitFlags emitFlags) override;
    EncodeResult encodePop(CpuReg reg, CpuEmitFlags emitFlags) override;
    EncodeResult encodeNop(CpuEmitFlags emitFlags) override;
    EncodeResult encodeRet(CpuEmitFlags emitFlags) override;
    EncodeResult encodeCallLocal(const Utf8& symbolName, const CallConv* callConv, CpuEmitFlags emitFlags) override;
    EncodeResult encodeCallExtern(const Utf8& symbolName, const CallConv* callConv, CpuEmitFlags emitFlags) override;
    EncodeResult encodeCallReg(CpuReg reg, const CallConv* callConv, CpuEmitFlags emitFlags) override;
    EncodeResult encodeJumpTable(CpuReg tableReg, CpuReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, CpuEmitFlags emitFlags) override;
    EncodeResult encodeJump(CpuJump& jump, CpuCondJump jumpType, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodePatchJump(const CpuJump& jump, uint64_t offsetDestination, CpuEmitFlags emitFlags) override;
    EncodeResult encodePatchJump(const CpuJump& jump, CpuEmitFlags emitFlags) override;
    EncodeResult encodeJumpReg(CpuReg reg, CpuEmitFlags emitFlags) override;
    EncodeResult encodeLoadRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodeLoadRegImm(CpuReg reg, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodeLoadRegReg(CpuReg regDst, CpuReg regSrc, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodeLoadSignedExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags) override;
    EncodeResult encodeLoadSignedExtendRegReg(CpuReg regDst, CpuReg regSrc, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags) override;
    EncodeResult encodeLoadZeroExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags) override;
    EncodeResult encodeLoadZeroExtendRegReg(CpuReg regDst, CpuReg regSrc, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags) override;
    EncodeResult encodeLoadAddressRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodeLoadAmcRegMem(CpuReg regDst, OpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsSrc, CpuEmitFlags emitFlags) override;
    EncodeResult encodeLoadAmcMemReg(CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsBaseMul, CpuReg regSrc, OpBits opBitsSrc, CpuEmitFlags emitFlags) override;
    EncodeResult encodeLoadAmcMemImm(CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsBaseMul, uint64_t value, OpBits opBitsValue, CpuEmitFlags emitFlags) override;
    EncodeResult encodeLoadAddressAmcRegMem(CpuReg regDst, OpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsValue, CpuEmitFlags emitFlags) override;
    EncodeResult encodeLoadMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodeLoadMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodeCmpRegReg(CpuReg reg0, CpuReg reg1, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodeCmpMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodeCmpMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodeCmpRegImm(CpuReg reg, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodeSetCondReg(CpuReg reg, CpuCond cpuCond, CpuEmitFlags emitFlags) override;
    EncodeResult encodeLoadCondRegReg(CpuReg regDst, CpuReg regSrc, CpuCond setType, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodeClearReg(CpuReg reg, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodeOpUnaryMem(CpuReg memReg, uint64_t memOffset, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodeOpUnaryReg(CpuReg reg, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryRegReg(CpuReg regDst, CpuReg regSrc, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryRegMem(CpuReg regDst, CpuReg memReg, uint64_t memOffset, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryRegImm(CpuReg reg, uint64_t value, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags) override;
    EncodeResult encodeOpTernaryRegRegReg(CpuReg reg0, CpuReg reg1, CpuReg reg2, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags) override;
};

SWC_END_NAMESPACE();
