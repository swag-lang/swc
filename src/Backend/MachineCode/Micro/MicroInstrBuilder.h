#pragma once
#include "Backend/MachineCode/Encoder/Encoder.h"
#include "Backend/MachineCode/Micro/MicroInstr.h"
#include "Support/Core/TypedStore.h"

SWC_BEGIN_NAMESPACE();

class MicroInstrPassManager;
struct MicroInstrPassContext;

class MicroInstrBuilder
{
public:
    explicit MicroInstrBuilder(TaskContext& ctx) :
        ctx_(&ctx)
    {
    }

    MicroInstrBuilder(const MicroInstrBuilder&)                = delete;
    MicroInstrBuilder& operator=(const MicroInstrBuilder&)     = delete;
    MicroInstrBuilder(MicroInstrBuilder&&) noexcept            = default;
    MicroInstrBuilder& operator=(MicroInstrBuilder&&) noexcept = default;

    TaskContext&       ctx() { return *ctx_; }
    const TaskContext& ctx() const { return *ctx_; }

    TypedStore<MicroInstr>&              instructions() { return instructions_; }
    const TypedStore<MicroInstr>&        instructions() const { return instructions_; }
    TypedStore<MicroInstrOperand>&       operands() { return operands_; }
    const TypedStore<MicroInstrOperand>& operands() const { return operands_; }

    void runPasses(MicroInstrPassManager& passes, Encoder* encoder, MicroInstrPassContext& context);

    EncodeResult encodeLoadSymbolRelocAddress(MicroReg reg, uint32_t symbolIndex, uint32_t offset, EncodeFlags emitFlags);
    EncodeResult encodeLoadSymRelocValue(MicroReg reg, uint32_t symbolIndex, uint32_t offset, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodePush(MicroReg reg, EncodeFlags emitFlags);
    EncodeResult encodePop(MicroReg reg, EncodeFlags emitFlags);
    EncodeResult encodeNop(EncodeFlags emitFlags);
    EncodeResult encodeRet(EncodeFlags emitFlags);
    EncodeResult encodeCallLocal(IdentifierRef symbolName, CallConvKind callConv, EncodeFlags emitFlags);
    EncodeResult encodeCallExtern(IdentifierRef symbolName, CallConvKind callConv, EncodeFlags emitFlags);
    EncodeResult encodeCallReg(MicroReg reg, CallConvKind callConv, EncodeFlags emitFlags);
    EncodeResult encodeJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EncodeFlags emitFlags);
    EncodeResult encodeJump(MicroJump& jump, MicroCondJump jumpType, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodePatchJump(const MicroJump& jump, uint64_t offsetDestination, EncodeFlags emitFlags);
    EncodeResult encodePatchJump(const MicroJump& jump, EncodeFlags emitFlags);
    EncodeResult encodeJumpReg(MicroReg reg, EncodeFlags emitFlags);
    EncodeResult encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags);
    EncodeResult encodeLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags);
    EncodeResult encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags);
    EncodeResult encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags);
    EncodeResult encodeLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc, EncodeFlags emitFlags);
    EncodeResult encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc, EncodeFlags emitFlags);
    EncodeResult encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue, EncodeFlags emitFlags);
    EncodeResult encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue, EncodeFlags emitFlags);
    EncodeResult encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeCmpRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeSetCondReg(MicroReg reg, MicroCond cpuCond, EncodeFlags emitFlags);
    EncodeResult encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeClearReg(MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);
    EncodeResult encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags);

private:
    MicroInstr& addInstruction(MicroInstrOpcode op, EncodeFlags emitFlags, uint8_t numOperands);

    TaskContext*                  ctx_ = nullptr;
    TypedStore<MicroInstr>        instructions_;
    TypedStore<MicroInstrOperand> operands_;
};

SWC_END_NAMESPACE();
