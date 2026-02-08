#pragma once
#include "Backend/MachineCode/Encoder/Core/CpuAbstraction.h"
#include "Runtime/Runtime.h"
#include "Support/Core/Store.h"

SWC_BEGIN_NAMESPACE();

struct MicroInstruction;
struct Module;
struct CallConv;

struct BuildParameters
{
    Module*                       module   = nullptr;
    Runtime::BuildCfgBackendOptim optLevel = Runtime::BuildCfgBackendOptim::O0;
};

enum class EncodeResult : uint32_t
{
    Zero,
    Left2Reg,
    Left2Rax,
    Right2Reg,
    Right2Rcx,
    Right2Cst,
    ForceZero32,
    NotSupported,
};

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

    virtual EncodeResult encodeLoadSymbolRelocAddress(CpuReg reg, uint32_t symbolIndex, uint32_t offset, CpuEmitFlags emitFlags)                                                                      = 0;
    virtual EncodeResult encodeLoadSymRelocValue(CpuReg reg, uint32_t symbolIndex, uint32_t offset, OpBits opBits, CpuEmitFlags emitFlags)                                                            = 0;
    virtual EncodeResult encodePush(CpuReg reg, CpuEmitFlags emitFlags)                                                                                                                               = 0;
    virtual EncodeResult encodePop(CpuReg reg, CpuEmitFlags emitFlags)                                                                                                                                = 0;
    virtual EncodeResult encodeNop(CpuEmitFlags emitFlags)                                                                                                                                            = 0;
    virtual EncodeResult encodeRet(CpuEmitFlags emitFlags)                                                                                                                                            = 0;
    virtual EncodeResult encodeCallLocal(const Utf8& symbolName, const CallConv* callConv, CpuEmitFlags emitFlags)                                                                                    = 0;
    virtual EncodeResult encodeCallExtern(const Utf8& symbolName, const CallConv* callConv, CpuEmitFlags emitFlags)                                                                                   = 0;
    virtual EncodeResult encodeCallReg(CpuReg reg, const CallConv* callConv, CpuEmitFlags emitFlags)                                                                                                  = 0;
    virtual EncodeResult encodeJumpTable(CpuReg tableReg, CpuReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, CpuEmitFlags emitFlags)                                     = 0;
    virtual EncodeResult encodeJump(CpuJump& jump, CpuCondJump jumpType, OpBits opBits, CpuEmitFlags emitFlags)                                                                                       = 0;
    virtual EncodeResult encodePatchJump(const CpuJump& jump, uint64_t offsetDestination, CpuEmitFlags emitFlags)                                                                                     = 0;
    virtual EncodeResult encodePatchJump(const CpuJump& jump, CpuEmitFlags emitFlags)                                                                                                                 = 0;
    virtual EncodeResult encodeJumpReg(CpuReg reg, CpuEmitFlags emitFlags)                                                                                                                            = 0;
    virtual EncodeResult encodeLoadRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits opBits, CpuEmitFlags emitFlags)                                                                       = 0;
    virtual EncodeResult encodeLoadRegImm(CpuReg reg, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags)                                                                                          = 0;
    virtual EncodeResult encodeLoadRegReg(CpuReg regDst, CpuReg regSrc, OpBits opBits, CpuEmitFlags emitFlags)                                                                                        = 0;
    virtual EncodeResult encodeLoadSignedExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags)                                    = 0;
    virtual EncodeResult encodeLoadSignedExtendRegReg(CpuReg regDst, CpuReg regSrc, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags)                                                     = 0;
    virtual EncodeResult encodeLoadZeroExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags)                                      = 0;
    virtual EncodeResult encodeLoadZeroExtendRegReg(CpuReg regDst, CpuReg regSrc, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags)                                                       = 0;
    virtual EncodeResult encodeLoadAddressRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits opBits, CpuEmitFlags emitFlags)                                                                = 0;
    virtual EncodeResult encodeLoadAmcRegMem(CpuReg regDst, OpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsSrc, CpuEmitFlags emitFlags)          = 0;
    virtual EncodeResult encodeLoadAmcMemReg(CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsBaseMul, CpuReg regSrc, OpBits opBitsSrc, CpuEmitFlags emitFlags)      = 0;
    virtual EncodeResult encodeLoadAmcMemImm(CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsBaseMul, uint64_t value, OpBits opBitsValue, CpuEmitFlags emitFlags)   = 0;
    virtual EncodeResult encodeLoadAddressAmcRegMem(CpuReg regDst, OpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsValue, CpuEmitFlags emitFlags) = 0;
    virtual EncodeResult encodeLoadMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, OpBits opBits, CpuEmitFlags emitFlags)                                                                       = 0;
    virtual EncodeResult encodeLoadMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags)                                                                   = 0;
    virtual EncodeResult encodeCmpRegReg(CpuReg reg0, CpuReg reg1, OpBits opBits, CpuEmitFlags emitFlags)                                                                                             = 0;
    virtual EncodeResult encodeCmpMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, OpBits opBits, CpuEmitFlags emitFlags)                                                                        = 0;
    virtual EncodeResult encodeCmpMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags)                                                                    = 0;
    virtual EncodeResult encodeCmpRegImm(CpuReg reg, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags)                                                                                           = 0;
    virtual EncodeResult encodeSetCondReg(CpuReg reg, CpuCond cpuCond, CpuEmitFlags emitFlags)                                                                                                        = 0;
    virtual EncodeResult encodeLoadCondRegReg(CpuReg regDst, CpuReg regSrc, CpuCond setType, OpBits opBits, CpuEmitFlags emitFlags)                                                                   = 0;
    virtual EncodeResult encodeClearReg(CpuReg reg, OpBits opBits, CpuEmitFlags emitFlags)                                                                                                            = 0;
    virtual EncodeResult encodeOpUnaryMem(CpuReg memReg, uint64_t memOffset, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                                         = 0;
    virtual EncodeResult encodeOpUnaryReg(CpuReg reg, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                                                                = 0;
    virtual EncodeResult encodeOpBinaryRegReg(CpuReg regDst, CpuReg regSrc, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                                          = 0;
    virtual EncodeResult encodeOpBinaryRegMem(CpuReg regDst, CpuReg memReg, uint64_t memOffset, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                      = 0;
    virtual EncodeResult encodeOpBinaryMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                         = 0;
    virtual EncodeResult encodeOpBinaryRegImm(CpuReg reg, uint64_t value, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                                            = 0;
    virtual EncodeResult encodeOpBinaryMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                     = 0;
    virtual EncodeResult encodeOpTernaryRegRegReg(CpuReg reg0, CpuReg reg1, CpuReg reg2, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)                                                             = 0;

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
