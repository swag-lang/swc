#pragma once
#include "Backend/MachineCode/Encoder/Core/CpuAbstraction.h"

SWC_BEGIN_NAMESPACE();

struct MicroInstruction;

class CpuEncoder
{
public:
    virtual ~CpuEncoder() = default;

    static bool isFloat(CpuReg reg) { return reg >= CpuReg::Xmm0 && reg <= CpuReg::Xmm3; }
    static bool isInt(CpuReg reg) { return !isFloat(reg); }

    static uint32_t getNumBits(OpBits opBits)
    {
        switch (opBits)
        {
            case OpBits::B8: return 8;
            case OpBits::B16: return 16;
            case OpBits::B32: return 32;
            case OpBits::B64: return 64;
            default: return 0;
        }
    }

    virtual RegisterSet getReadRegisters(const MicroInstruction&) { return {}; }
    virtual RegisterSet getWriteRegisters(const MicroInstruction&) { return {}; }

    virtual CpuEncodeResult encodeLoadSymbolRelocAddress(CpuReg reg, uint32_t symbolIndex, uint32_t offset, CpuEmitFlags emitFlags)                                                                      = 0;
    virtual CpuEncodeResult encodeLoadSymRelocValue(CpuReg reg, uint32_t symbolIndex, uint32_t offset, OpBits opBits, CpuEmitFlags emitFlags)                                                            = 0;
    virtual CpuEncodeResult encodePush(CpuReg reg, CpuEmitFlags emitFlags)                                                                                                                               = 0;
    virtual CpuEncodeResult encodePop(CpuReg reg, CpuEmitFlags emitFlags)                                                                                                                                = 0;
    virtual CpuEncodeResult encodeNop(CpuEmitFlags emitFlags)                                                                                                                                            = 0;
    virtual CpuEncodeResult encodeRet(CpuEmitFlags emitFlags)                                                                                                                                            = 0;
    virtual CpuEncodeResult encodeCallLocal(const Utf8& symbolName, const CallConv* callConv, CpuEmitFlags emitFlags)                                                                                    = 0;
    virtual CpuEncodeResult encodeCallExtern(const Utf8& symbolName, const CallConv* callConv, CpuEmitFlags emitFlags)                                                                                   = 0;
    virtual CpuEncodeResult encodeCallReg(CpuReg reg, const CallConv* callConv, CpuEmitFlags emitFlags)                                                                                                  = 0;
    virtual CpuEncodeResult encodeJumpTable(CpuReg tableReg, CpuReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, CpuEmitFlags emitFlags)                                     = 0;
    virtual CpuEncodeResult encodeJump(CpuJump& jump, CpuCondJump jumpType, OpBits opBits, CpuEmitFlags emitFlags)                                                                                       = 0;
    virtual CpuEncodeResult encodePatchJump(const CpuJump& jump, uint64_t offsetDestination, CpuEmitFlags emitFlags)                                                                                     = 0;
    virtual CpuEncodeResult encodePatchJump(const CpuJump& jump, CpuEmitFlags emitFlags)                                                                                                                 = 0;
    virtual CpuEncodeResult encodeJumpReg(CpuReg reg, CpuEmitFlags emitFlags)                                                                                                                            = 0;
    virtual CpuEncodeResult encodeLoadRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits opBits, CpuEmitFlags emitFlags)                                                                       = 0;
    virtual CpuEncodeResult encodeLoadRegImm(CpuReg reg, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags)                                                                                          = 0;
    virtual CpuEncodeResult encodeLoadRegReg(CpuReg regDst, CpuReg regSrc, OpBits opBits, CpuEmitFlags emitFlags)                                                                                        = 0;
    virtual CpuEncodeResult encodeLoadSignedExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags)                                    = 0;
    virtual CpuEncodeResult encodeLoadSignedExtendRegReg(CpuReg regDst, CpuReg regSrc, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags)                                                     = 0;
    virtual CpuEncodeResult encodeLoadZeroExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags)                                      = 0;
    virtual CpuEncodeResult encodeLoadZeroExtendRegReg(CpuReg regDst, CpuReg regSrc, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags)                                                       = 0;
    virtual CpuEncodeResult encodeLoadAddressRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits opBits, CpuEmitFlags emitFlags)                                                                = 0;
    virtual CpuEncodeResult encodeLoadAmcRegMem(CpuReg regDst, OpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsSrc, CpuEmitFlags emitFlags)          = 0;
    virtual CpuEncodeResult encodeLoadAmcMemReg(CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsBaseMul, CpuReg regSrc, OpBits opBitsSrc, CpuEmitFlags emitFlags)      = 0;
    virtual CpuEncodeResult encodeLoadAmcMemImm(CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsBaseMul, uint64_t value, OpBits opBitsValue, CpuEmitFlags emitFlags)   = 0;
    virtual CpuEncodeResult encodeLoadAddressAmcRegMem(CpuReg regDst, OpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsValue, CpuEmitFlags emitFlags) = 0;
    virtual CpuEncodeResult encodeLoadMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, OpBits opBits, CpuEmitFlags emitFlags)                                                                       = 0;
    virtual CpuEncodeResult encodeLoadMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags)                                                                   = 0;
    virtual CpuEncodeResult encodeCmpRegReg(CpuReg reg0, CpuReg reg1, OpBits opBits, CpuEmitFlags emitFlags)                                                                                             = 0;
    virtual CpuEncodeResult encodeCmpMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, OpBits opBits, CpuEmitFlags emitFlags)                                                                        = 0;
    virtual CpuEncodeResult encodeCmpMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags)                                                                    = 0;
    virtual CpuEncodeResult encodeCmpRegImm(CpuReg reg, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags)                                                                                           = 0;
    virtual CpuEncodeResult encodeSetCondReg(CpuReg reg, CpuCond cpuCond, CpuEmitFlags emitFlags)                                                                                                        = 0;
    virtual CpuEncodeResult encodeLoadCondRegReg(CpuReg regDst, CpuReg regSrc, CpuCond setType, OpBits opBits, CpuEmitFlags emitFlags)                                                                   = 0;
    virtual CpuEncodeResult encodeClearReg(CpuReg reg, OpBits opBits, CpuEmitFlags emitFlags)                                                                                                            = 0;
    virtual CpuEncodeResult encodeOpUnaryMem(CpuReg memReg, uint64_t memOffset, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                                         = 0;
    virtual CpuEncodeResult encodeOpUnaryReg(CpuReg reg, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                                                                = 0;
    virtual CpuEncodeResult encodeOpBinaryRegReg(CpuReg regDst, CpuReg regSrc, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                                          = 0;
    virtual CpuEncodeResult encodeOpBinaryRegMem(CpuReg regDst, CpuReg memReg, uint64_t memOffset, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                      = 0;
    virtual CpuEncodeResult encodeOpBinaryMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                         = 0;
    virtual CpuEncodeResult encodeOpBinaryRegImm(CpuReg reg, uint64_t value, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                                            = 0;
    virtual CpuEncodeResult encodeOpBinaryMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                     = 0;
    virtual CpuEncodeResult encodeOpTernaryRegRegReg(CpuReg reg0, CpuReg reg1, CpuReg reg2, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                             = 0;

    void        emitLoadSymRelocAddress(CpuReg reg, uint32_t symbolIndex, uint32_t offset, CpuEmitFlags emitFlags = EMIT_ZERO);
    void        emitJumpReg(CpuReg reg, CpuEmitFlags emitFlags = EMIT_ZERO);
    void        emitOpBinaryRegReg(CpuReg regDst, CpuReg regSrc, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags = EMIT_ZERO);
    void        emitOpBinaryRegImm(CpuReg reg, uint64_t value, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags = EMIT_ZERO);
    void        emitLoadRegReg(CpuReg regDst, CpuReg regSrc, OpBits opBits, CpuEmitFlags emitFlags = EMIT_ZERO);
    void        emitLoadRegImm(CpuReg reg, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags = EMIT_ZERO);
    void        emitLoadSignedExtendRegReg(CpuReg regDst, CpuReg regSrc, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags = EMIT_ZERO);
    void        emitLoadZeroExtendRegReg(CpuReg regDst, CpuReg regSrc, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags = EMIT_ZERO);
    void        emitClearReg(CpuReg reg, OpBits opBits, CpuEmitFlags emitFlags = EMIT_ZERO);
    CpuSymbol*  getOrAddSymbol(const Utf8& name, CpuSymbolKind kind);
    static void addSymbolRelocation(uint32_t, uint32_t, uint16_t);

protected:
    Store           store_;
    BuildParameters buildParams_;
    Module*         module_            = nullptr;
    CpuFunction*    cpuFct_            = nullptr;
    uint32_t        symCsIndex_        = 0;
    uint32_t        textSectionOffset_ = 0;

private:
    std::vector<CpuSymbol> symbols_;
};

SWC_END_NAMESPACE();
