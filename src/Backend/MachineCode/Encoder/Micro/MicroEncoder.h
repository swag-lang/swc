#pragma once
#include "Backend/MachineCode/Encoder/Core/Encoder.h"
#include "Backend/MachineCode/Encoder/Micro/MicroInstruction.h"

SWC_BEGIN_NAMESPACE();

class MicroEncoder : public Encoder
{
public:
    explicit MicroEncoder(TaskContext& ctx) : Encoder(ctx) {}

    void encode(Encoder& encoder);

    EncodeResult encodeLoadSymbolRelocAddress(TaskContext& ctx, CpuReg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags) override;
    EncodeResult encodeLoadSymRelocValue(TaskContext& ctx, CpuReg reg, uint32_t symbolIndex, uint32_t offset, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodePush(TaskContext& ctx, CpuReg reg, EmitFlags emitFlags) override;
    EncodeResult encodePop(TaskContext& ctx, CpuReg reg, EmitFlags emitFlags) override;
    EncodeResult encodeNop(TaskContext& ctx, EmitFlags emitFlags) override;
    EncodeResult encodeRet(TaskContext& ctx, EmitFlags emitFlags) override;
    EncodeResult encodeCallLocal(TaskContext& ctx, IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags) override;
    EncodeResult encodeCallExtern(TaskContext& ctx, IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags) override;
    EncodeResult encodeCallReg(TaskContext& ctx, CpuReg reg, const CallConv* callConv, EmitFlags emitFlags) override;
    EncodeResult encodeJumpTable(TaskContext& ctx, CpuReg tableReg, CpuReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags) override;
    EncodeResult encodeJump(TaskContext& ctx, CpuJump& jump, CpuCondJump jumpType, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodePatchJump(TaskContext& ctx, const CpuJump& jump, uint64_t offsetDestination, EmitFlags emitFlags) override;
    EncodeResult encodePatchJump(TaskContext& ctx, const CpuJump& jump, EmitFlags emitFlags) override;
    EncodeResult encodeJumpReg(TaskContext& ctx, CpuReg reg, EmitFlags emitFlags) override;
    EncodeResult encodeLoadRegMem(TaskContext& ctx, CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeLoadRegImm(TaskContext& ctx, CpuReg reg, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeLoadRegReg(TaskContext& ctx, CpuReg regDst, CpuReg regSrc, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeLoadSignedExtendRegMem(TaskContext& ctx, CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadSignedExtendRegReg(TaskContext& ctx, CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadZeroExtendRegMem(TaskContext& ctx, CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadZeroExtendRegReg(TaskContext& ctx, CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadAddressRegMem(TaskContext& ctx, CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeLoadAmcRegMem(TaskContext& ctx, CpuReg regDst, CpuOpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadAmcMemReg(TaskContext& ctx, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsBaseMul, CpuReg regSrc, CpuOpBits opBitsSrc, EmitFlags emitFlags) override;
    EncodeResult encodeLoadAmcMemImm(TaskContext& ctx, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsBaseMul, uint64_t value, CpuOpBits opBitsValue, EmitFlags emitFlags) override;
    EncodeResult encodeLoadAddressAmcRegMem(TaskContext& ctx, CpuReg regDst, CpuOpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsValue, EmitFlags emitFlags) override;
    EncodeResult encodeLoadMemReg(TaskContext& ctx, CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeLoadMemImm(TaskContext& ctx, CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeCmpRegReg(TaskContext& ctx, CpuReg reg0, CpuReg reg1, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeCmpMemReg(TaskContext& ctx, CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeCmpMemImm(TaskContext& ctx, CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeCmpRegImm(TaskContext& ctx, CpuReg reg, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeSetCondReg(TaskContext& ctx, CpuReg reg, CpuCond cpuCond, EmitFlags emitFlags) override;
    EncodeResult encodeLoadCondRegReg(TaskContext& ctx, CpuReg regDst, CpuReg regSrc, CpuCond setType, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeClearReg(TaskContext& ctx, CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpUnaryMem(TaskContext& ctx, CpuReg memReg, uint64_t memOffset, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpUnaryReg(TaskContext& ctx, CpuReg reg, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryRegReg(TaskContext& ctx, CpuReg regDst, CpuReg regSrc, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryRegMem(TaskContext& ctx, CpuReg regDst, CpuReg memReg, uint64_t memOffset, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryMemReg(TaskContext& ctx, CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryRegImm(TaskContext& ctx, CpuReg reg, uint64_t value, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpBinaryMemImm(TaskContext& ctx, CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags) override;
    EncodeResult encodeOpTernaryRegRegReg(TaskContext& ctx, CpuReg reg0, CpuReg reg1, CpuReg reg2, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags) override;

private:
    void              encodeInstruction(Encoder& encoder, const MicroInstruction& inst, size_t idx);
    MicroInstruction& addInstruction(MicroOp op, EmitFlags emitFlags, uint8_t numOperands);

    std::vector<MicroInstruction> instructions_;
    std::vector<CpuJump>          jumps_;
    std::vector<bool>             jumpValid_;
};

SWC_END_NAMESPACE();

