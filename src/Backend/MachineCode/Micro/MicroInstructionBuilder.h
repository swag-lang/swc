#pragma once
#include "Backend/MachineCode/Encoder/Core/Encoder.h"
#include "Backend/MachineCode/Encoder/Micro/MicroInstruction.h"

SWC_BEGIN_NAMESPACE();

class MicroInstructionBuilder
{
public:
    explicit MicroInstructionBuilder(TaskContext& ctx) :
        ctx_(&ctx)
    {
    }

    void encode(Encoder& encoder);

    EncodeResult encodeLoadSymbolRelocAddress(CpuReg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags);
    EncodeResult encodeLoadSymRelocValue(CpuReg reg, uint32_t symbolIndex, uint32_t offset, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodePush(CpuReg reg, EmitFlags emitFlags);
    EncodeResult encodePop(CpuReg reg, EmitFlags emitFlags);
    EncodeResult encodeNop(EmitFlags emitFlags);
    EncodeResult encodeRet(EmitFlags emitFlags);
    EncodeResult encodeCallLocal(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags);
    EncodeResult encodeCallExtern(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags);
    EncodeResult encodeCallReg(CpuReg reg, const CallConv* callConv, EmitFlags emitFlags);
    EncodeResult encodeJumpTable(CpuReg tableReg, CpuReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags);
    EncodeResult encodeJump(CpuJump& jump, CpuCondJump jumpType, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodePatchJump(const CpuJump& jump, uint64_t offsetDestination, EmitFlags emitFlags);
    EncodeResult encodePatchJump(const CpuJump& jump, EmitFlags emitFlags);
    EncodeResult encodeJumpReg(CpuReg reg, EmitFlags emitFlags);
    EncodeResult encodeLoadRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeLoadRegImm(CpuReg reg, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeLoadRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeLoadSignedExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadSignedExtendRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadZeroExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadZeroExtendRegReg(CpuReg regDst, CpuReg regSrc, CpuOpBits numBitsDst, CpuOpBits numBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadAddressRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeLoadAmcRegMem(CpuReg regDst, CpuOpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadAmcMemReg(CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsBaseMul, CpuReg regSrc, CpuOpBits opBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadAmcMemImm(CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsBaseMul, uint64_t value, CpuOpBits opBitsValue, EmitFlags emitFlags);
    EncodeResult encodeLoadAddressAmcRegMem(CpuReg regDst, CpuOpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, CpuOpBits opBitsValue, EmitFlags emitFlags);
    EncodeResult encodeLoadMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeLoadMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeCmpRegReg(CpuReg reg0, CpuReg reg1, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeCmpMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeCmpMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeCmpRegImm(CpuReg reg, uint64_t value, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeSetCondReg(CpuReg reg, CpuCond cpuCond, EmitFlags emitFlags);
    EncodeResult encodeLoadCondRegReg(CpuReg regDst, CpuReg regSrc, CpuCond setType, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeClearReg(CpuReg reg, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpUnaryMem(CpuReg memReg, uint64_t memOffset, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpUnaryReg(CpuReg reg, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpBinaryRegReg(CpuReg regDst, CpuReg regSrc, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpBinaryRegMem(CpuReg regDst, CpuReg memReg, uint64_t memOffset, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpBinaryMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpBinaryRegImm(CpuReg reg, uint64_t value, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpBinaryMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpTernaryRegRegReg(CpuReg reg0, CpuReg reg1, CpuReg reg2, CpuOp op, CpuOpBits opBits, EmitFlags emitFlags);

private:
    void              encodeInstruction(Encoder& encoder, const MicroInstruction& inst, size_t idx);
    MicroInstruction& addInstruction(MicroOp op, EmitFlags emitFlags, uint8_t numOperands);

    TaskContext*                   ctx_ = nullptr;
    std::vector<MicroInstruction> instructions_;
    std::vector<CpuJump>          jumps_;
    std::vector<bool>             jumpValid_;
};

SWC_END_NAMESPACE();
