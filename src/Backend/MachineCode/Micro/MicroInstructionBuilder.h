#pragma once
#include "Backend/MachineCode/Encoder/Encoder.h"
#include "Backend/MachineCode/Micro/MicroInstruction.h"

SWC_BEGIN_NAMESPACE();

class MicroInstructionBuilder
{
public:
    explicit MicroInstructionBuilder(TaskContext& ctx) :
        ctx_(&ctx)
    {
    }

    void encode(Encoder& encoder);

    EncodeResult encodeLoadSymbolRelocAddress(MicroReg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags);
    EncodeResult encodeLoadSymRelocValue(MicroReg reg, uint32_t symbolIndex, uint32_t offset, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodePush(MicroReg reg, EmitFlags emitFlags);
    EncodeResult encodePop(MicroReg reg, EmitFlags emitFlags);
    EncodeResult encodeNop(EmitFlags emitFlags);
    EncodeResult encodeRet(EmitFlags emitFlags);
    EncodeResult encodeCallLocal(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags);
    EncodeResult encodeCallExtern(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags);
    EncodeResult encodeCallReg(MicroReg reg, const CallConv* callConv, EmitFlags emitFlags);
    EncodeResult encodeJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags);
    EncodeResult encodeJump(MicroJump& jump, MicroCondJump jumpType, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodePatchJump(const MicroJump& jump, uint64_t offsetDestination, EmitFlags emitFlags);
    EncodeResult encodePatchJump(const MicroJump& jump, EmitFlags emitFlags);
    EncodeResult encodeJumpReg(MicroReg reg, EmitFlags emitFlags);
    EncodeResult encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue, EmitFlags emitFlags);
    EncodeResult encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue, EmitFlags emitFlags);
    EncodeResult encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeCmpRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeSetCondReg(MicroReg reg, MicroCond cpuCond, EmitFlags emitFlags);
    EncodeResult encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeClearReg(MicroReg reg, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits, EmitFlags emitFlags);

private:
    void              encodeInstruction(Encoder& encoder, const MicroInstruction& inst, size_t idx);
    MicroInstruction& addInstruction(MicroInstructionKind op, EmitFlags emitFlags, uint8_t numOperands);

    TaskContext*                  ctx_ = nullptr;
    std::vector<MicroInstruction> instructions_;
    std::vector<MicroJump> jumps_;
    std::vector<bool>             jumpValid_;
};

SWC_END_NAMESPACE();
