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

    EncodeResult encodeLoadSymbolRelocAddress(Micro::Reg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags);
    EncodeResult encodeLoadSymRelocValue(Micro::Reg reg, uint32_t symbolIndex, uint32_t offset, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodePush(Micro::Reg reg, EmitFlags emitFlags);
    EncodeResult encodePop(Micro::Reg reg, EmitFlags emitFlags);
    EncodeResult encodeNop(EmitFlags emitFlags);
    EncodeResult encodeRet(EmitFlags emitFlags);
    EncodeResult encodeCallLocal(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags);
    EncodeResult encodeCallExtern(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags);
    EncodeResult encodeCallReg(Micro::Reg reg, const CallConv* callConv, EmitFlags emitFlags);
    EncodeResult encodeJumpTable(Micro::Reg tableReg, Micro::Reg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags);
    EncodeResult encodeJump(Micro::Jump& jump, Micro::CondJump jumpType, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodePatchJump(const Micro::Jump& jump, uint64_t offsetDestination, EmitFlags emitFlags);
    EncodeResult encodePatchJump(const Micro::Jump& jump, EmitFlags emitFlags);
    EncodeResult encodeJumpReg(Micro::Reg reg, EmitFlags emitFlags);
    EncodeResult encodeLoadRegMem(Micro::Reg reg, Micro::Reg memReg, uint64_t memOffset, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeLoadRegImm(Micro::Reg reg, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeLoadRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeLoadSignedExtendRegMem(Micro::Reg reg, Micro::Reg memReg, uint64_t memOffset, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadSignedExtendRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadZeroExtendRegMem(Micro::Reg reg, Micro::Reg memReg, uint64_t memOffset, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadZeroExtendRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadAddressRegMem(Micro::Reg reg, Micro::Reg memReg, uint64_t memOffset, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeLoadAmcRegMem(Micro::Reg regDst, Micro::OpBits opBitsDst, Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadAmcMemReg(Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsBaseMul, Micro::Reg regSrc, Micro::OpBits opBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadAmcMemImm(Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsBaseMul, uint64_t value, Micro::OpBits opBitsValue, EmitFlags emitFlags);
    EncodeResult encodeLoadAddressAmcRegMem(Micro::Reg regDst, Micro::OpBits opBitsDst, Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsValue, EmitFlags emitFlags);
    EncodeResult encodeLoadMemReg(Micro::Reg memReg, uint64_t memOffset, Micro::Reg reg, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeLoadMemImm(Micro::Reg memReg, uint64_t memOffset, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeCmpRegReg(Micro::Reg reg0, Micro::Reg reg1, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeCmpMemReg(Micro::Reg memReg, uint64_t memOffset, Micro::Reg reg, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeCmpMemImm(Micro::Reg memReg, uint64_t memOffset, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeCmpRegImm(Micro::Reg reg, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeSetCondReg(Micro::Reg reg, Micro::Cond cpuCond, EmitFlags emitFlags);
    EncodeResult encodeLoadCondRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::Cond setType, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeClearReg(Micro::Reg reg, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpUnaryMem(Micro::Reg memReg, uint64_t memOffset, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpUnaryReg(Micro::Reg reg, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpBinaryRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpBinaryRegMem(Micro::Reg regDst, Micro::Reg memReg, uint64_t memOffset, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpBinaryMemReg(Micro::Reg memReg, uint64_t memOffset, Micro::Reg reg, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpBinaryRegImm(Micro::Reg reg, uint64_t value, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpBinaryMemImm(Micro::Reg memReg, uint64_t memOffset, uint64_t value, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpTernaryRegRegReg(Micro::Reg reg0, Micro::Reg reg1, Micro::Reg reg2, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags);

private:
    void              encodeInstruction(Encoder& encoder, const MicroInstruction& inst, size_t idx);
    MicroInstruction& addInstruction(MicroInstructionKind op, EmitFlags emitFlags, uint8_t numOperands);

    TaskContext*                  ctx_ = nullptr;
    std::vector<MicroInstruction> instructions_;
    std::vector<Micro::Jump>      jumps_;
    std::vector<bool>             jumpValid_;
};

SWC_END_NAMESPACE();
