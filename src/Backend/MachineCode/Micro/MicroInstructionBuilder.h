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

    EncodeResult encodeLoadSymbolRelocAddress(Cpu::Reg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags);
    EncodeResult encodeLoadSymRelocValue(Cpu::Reg reg, uint32_t symbolIndex, uint32_t offset, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodePush(Cpu::Reg reg, EmitFlags emitFlags);
    EncodeResult encodePop(Cpu::Reg reg, EmitFlags emitFlags);
    EncodeResult encodeNop(EmitFlags emitFlags);
    EncodeResult encodeRet(EmitFlags emitFlags);
    EncodeResult encodeCallLocal(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags);
    EncodeResult encodeCallExtern(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags);
    EncodeResult encodeCallReg(Cpu::Reg reg, const CallConv* callConv, EmitFlags emitFlags);
    EncodeResult encodeJumpTable(Cpu::Reg tableReg, Cpu::Reg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags);
    EncodeResult encodeJump(Cpu::Jump& jump, Cpu::CondJump jumpType, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodePatchJump(const Cpu::Jump& jump, uint64_t offsetDestination, EmitFlags emitFlags);
    EncodeResult encodePatchJump(const Cpu::Jump& jump, EmitFlags emitFlags);
    EncodeResult encodeJumpReg(Cpu::Reg reg, EmitFlags emitFlags);
    EncodeResult encodeLoadRegMem(Cpu::Reg reg, Cpu::Reg memReg, uint64_t memOffset, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeLoadRegImm(Cpu::Reg reg, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeLoadRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeLoadSignedExtendRegMem(Cpu::Reg reg, Cpu::Reg memReg, uint64_t memOffset, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadSignedExtendRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadZeroExtendRegMem(Cpu::Reg reg, Cpu::Reg memReg, uint64_t memOffset, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadZeroExtendRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadAddressRegMem(Cpu::Reg reg, Cpu::Reg memReg, uint64_t memOffset, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeLoadAmcRegMem(Cpu::Reg regDst, Cpu::OpBits opBitsDst, Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadAmcMemReg(Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsBaseMul, Cpu::Reg regSrc, Cpu::OpBits opBitsSrc, EmitFlags emitFlags);
    EncodeResult encodeLoadAmcMemImm(Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsBaseMul, uint64_t value, Cpu::OpBits opBitsValue, EmitFlags emitFlags);
    EncodeResult encodeLoadAddressAmcRegMem(Cpu::Reg regDst, Cpu::OpBits opBitsDst, Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsValue, EmitFlags emitFlags);
    EncodeResult encodeLoadMemReg(Cpu::Reg memReg, uint64_t memOffset, Cpu::Reg reg, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeLoadMemImm(Cpu::Reg memReg, uint64_t memOffset, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeCmpRegReg(Cpu::Reg reg0, Cpu::Reg reg1, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeCmpMemReg(Cpu::Reg memReg, uint64_t memOffset, Cpu::Reg reg, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeCmpMemImm(Cpu::Reg memReg, uint64_t memOffset, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeCmpRegImm(Cpu::Reg reg, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeSetCondReg(Cpu::Reg reg, Cpu::Cond cpuCond, EmitFlags emitFlags);
    EncodeResult encodeLoadCondRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::Cond setType, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeClearReg(Cpu::Reg reg, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpUnaryMem(Cpu::Reg memReg, uint64_t memOffset, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpUnaryReg(Cpu::Reg reg, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpBinaryRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpBinaryRegMem(Cpu::Reg regDst, Cpu::Reg memReg, uint64_t memOffset, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpBinaryMemReg(Cpu::Reg memReg, uint64_t memOffset, Cpu::Reg reg, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpBinaryRegImm(Cpu::Reg reg, uint64_t value, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpBinaryMemImm(Cpu::Reg memReg, uint64_t memOffset, uint64_t value, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags);
    EncodeResult encodeOpTernaryRegRegReg(Cpu::Reg reg0, Cpu::Reg reg1, Cpu::Reg reg2, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags);

private:
    void              encodeInstruction(Encoder& encoder, const MicroInstruction& inst, size_t idx);
    MicroInstruction& addInstruction(MicroOp op, EmitFlags emitFlags, uint8_t numOperands);

    TaskContext*                  ctx_ = nullptr;
    std::vector<MicroInstruction> instructions_;
    std::vector<Cpu::Jump>        jumps_;
    std::vector<bool>             jumpValid_;
};

SWC_END_NAMESPACE();
