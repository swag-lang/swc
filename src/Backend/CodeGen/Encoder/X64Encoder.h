#pragma once
#include "Backend/CodeGen/Encoder/Encoder.h"

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

    std::string formatRegisterName(MicroReg reg) const override;
    MicroReg    stackPointerReg() const override { return MicroReg::intReg(4); }

private:
    uint64_t currentOffset() const override { return store_.size(); }
    void     updateRegUseDef(const MicroInstr& inst, const MicroInstrOperand* ops, MicroInstrUseDef& info) const override;
    bool     queryConformanceIssue(MicroConformanceIssue& outIssue, const MicroInstr& inst, const MicroInstrOperand* ops) const override;

    void encodePush(MicroReg reg) override;
    void encodePop(MicroReg reg) override;
    void encodeNop() override;
    void encodeRet() override;
    void encodeCallLocal(Symbol* targetSymbol, CallConvKind callConv) override;
    void encodeCallExtern(Symbol* targetSymbol, uint64_t targetAddress, CallConvKind callConv) override;
    void encodeCallReg(MicroReg reg, CallConvKind callConv) override;
    void encodeJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries) override;
    void encodeJump(MicroJump& jump, MicroCond cpuCond, MicroOpBits opBits) override;
    void encodePatchJump(const MicroJump& jump, uint64_t offsetDestination) override;
    void encodePatchJump(const MicroJump& jump) override;
    void encodeJumpReg(MicroReg reg) override;
    void encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits) override;
    void encodeLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits) override;
    void encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits) override;
    void encodeLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc) override;
    void encodeLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc) override;
    void encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc) override;
    void encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc) override;
    void encodeLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits) override;
    void encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc) override;
    void encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc) override;
    void encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue) override;
    void encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue) override;
    void encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits) override;
    void encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits) override;
    void encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits) override;
    void encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits) override;
    void encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits) override;
    void encodeCmpRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits) override;
    void encodeSetCondReg(MicroReg reg, MicroCond cpuCond) override;
    void encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits) override;
    void encodeClearReg(MicroReg reg, MicroOpBits opBits) override;
    void encodeOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits) override;
    void encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits) override;
    void encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits) override;
    void encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits) override;
    void encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits) override;
    void encodeOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits) override;
    void encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOp op, MicroOpBits opBits) override;
    void encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits) override;
};

SWC_END_NAMESPACE();

