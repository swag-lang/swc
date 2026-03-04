#pragma once
#include "Backend/Encoder/Encoder.h"

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

    bool        buildUnwindInfo(std::vector<std::byte>& outUnwindInfo) const override;
    std::string formatRegisterName(MicroReg reg) const override;
    MicroReg    stackPointerReg() const override { return MicroReg::intReg(4); }

private:
    enum class UnwindOpKind : uint8_t
    {
        PushNonVol,
        AllocateStack,
        SetFramePointer,
        SaveNonVol,
    };

    struct UnwindOp
    {
        UnwindOpKind kind        = UnwindOpKind::PushNonVol;
        uint8_t      codeOffset  = 0;
        uint8_t      reg         = 0;
        uint32_t     stackSize   = 0;
        uint32_t     stackOffset = 0;
    };

    uint64_t currentOffset() const override { return store_.size(); }
    void     updateRegUseDef(const MicroInstr& inst, const MicroInstrOperand* ops, MicroInstrUseDef& info) const override;
    bool     queryConformanceIssue(MicroConformanceIssue& outIssue, const MicroInstr& inst, const MicroInstrOperand* ops) const override;
    void     onInstructionEncoded(const MicroInstr& inst, const MicroInstrOperand* ops, uint32_t codeStartOffset, uint32_t codeEndOffset) override;

    bool        tryTrackUnwindPush(const MicroInstrOperand* ops, uint32_t codeEndOffset);
    bool        tryTrackUnwindAllocateStack(const MicroInstrOperand* ops, uint32_t codeEndOffset);
    bool        tryTrackUnwindSetFramePointer(const MicroInstr& inst, const MicroInstrOperand* ops, uint32_t codeEndOffset);
    bool        tryTrackUnwindSaveNonVol(const MicroInstrOperand* ops, uint32_t codeEndOffset);
    static bool tryMapWindowsUnwindReg(uint8_t& outReg, MicroReg reg);
    void        closeUnwindProlog();
    bool        canTrackUnwindInstruction(uint32_t codeEndOffset);

    void encodePush(MicroReg reg) override;
    void encodePop(MicroReg reg) override;
    void encodeNop() override;
    void encodeBreakpoint() override;
    void encodeAssertTrap() override;
    void encodeRet() override;
    void encodeCallLocal(Symbol* targetSymbol, CallConvKind callConv) override;
    void encodeCallExtern(Symbol* targetSymbol, uint64_t targetAddress, CallConvKind callConv) override;
    void encodeCallReg(MicroReg reg, CallConvKind callConv) override;
    void encodeJump(MicroJump& jump, MicroCond cpuCond, MicroOpBits opBits) override;
    void encodePatchJump(const MicroJump& jump, uint64_t offsetDestination) override;
    void encodePatchJump(const MicroJump& jump) override;
    void encodeJumpReg(MicroReg reg) override;
    void encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits) override;
    void encodeLoadRegImm(MicroReg reg, const ApInt& value, MicroOpBits opBits) override;
    void encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits) override;
    void encodeLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc) override;
    void encodeLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc) override;
    void encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc) override;
    void encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc) override;
    void encodeLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits) override;
    void encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc) override;
    void encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc) override;
    void encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, const ApInt& value, MicroOpBits opBitsValue) override;
    void encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue) override;
    void encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits) override;
    void encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, const ApInt& value, MicroOpBits opBits) override;
    void encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits) override;
    void encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits) override;
    void encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, const ApInt& value, MicroOpBits opBits) override;
    void encodeCmpRegImm(MicroReg reg, const ApInt& value, MicroOpBits opBits) override;
    void encodeSetCondReg(MicroReg reg, MicroCond cpuCond) override;
    void encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits) override;
    void encodeClearReg(MicroReg reg, MicroOpBits opBits) override;
    void encodeOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits) override;
    void encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits) override;
    void encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits) override;
    void encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits) override;
    void encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits) override;
    void encodeOpBinaryRegImm(MicroReg reg, const ApInt& valueInt, MicroOp op, MicroOpBits opBits) override;
    void encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, const ApInt& valueInt, MicroOp op, MicroOpBits opBits) override;
    void encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits) override;

    bool                  unwindPrologClosed_       = false;
    bool                  unwindPrologInvalid_      = false;
    bool                  unwindHasFrameRegister_   = false;
    uint8_t               unwindPrologSize_         = 0;
    uint8_t               unwindFrameRegister_      = 0;
    uint8_t               unwindFrameOffsetInSlots_ = 0;
    std::vector<UnwindOp> unwindOps_;
};

SWC_END_NAMESPACE();
