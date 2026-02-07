// ReSharper disable CommentTypo
#include "pch.h"
#include "Backend/MachineCode/Encoder/X64/X64Encoder.h"
#include "Backend/Diagnostics/BackendReport.h"
#include "Backend/MachineCode/Encoder/MicroOps/MicroInstruction.h"

SWC_BEGIN_NAMESPACE();

enum class ModRmMode : uint8_t
{
    Memory         = 0b00,
    Displacement8  = 0b01,
    Displacement32 = 0b10,
    Register       = 0b11,
};

constexpr auto REX_REG_NONE  = static_cast<CpuReg>(255);
constexpr auto MODRM_REG_0   = static_cast<CpuReg>(254);
constexpr auto MODRM_REG_1   = static_cast<CpuReg>(253);
constexpr auto MODRM_REG_2   = static_cast<CpuReg>(252);
constexpr auto MODRM_REG_3   = static_cast<CpuReg>(251);
constexpr auto MODRM_REG_4   = static_cast<CpuReg>(250);
constexpr auto MODRM_REG_5   = static_cast<CpuReg>(249);
constexpr auto MODRM_REG_6   = static_cast<CpuReg>(248);
constexpr auto MODRM_REG_7   = static_cast<CpuReg>(247);
constexpr auto MODRM_REG_SIB = static_cast<CpuReg>(246);

constexpr uint8_t MODRM_RM_SIB = 0b100;
constexpr uint8_t MODRM_RM_RIP = 0b101;

constexpr uint8_t SIB_NO_BASE = 0b101;

enum class X64Reg : uint8_t
{
    Rax  = 0b000000,
    Rbx  = 0b000011,
    Rcx  = 0b000001,
    Rdx  = 0b000010,
    Rsp  = 0b000100,
    Rbp  = 0b000101,
    Rsi  = 0b000110,
    Rdi  = 0b000111,
    R8   = 0b001000,
    R9   = 0b001001,
    R10  = 0b001010,
    R11  = 0b001011,
    R12  = 0b001100,
    R13  = 0b001101,
    R14  = 0b001110,
    R15  = 0b001111,
    Xmm0 = 0b100000,
    Xmm1 = 0b100001,
    Xmm2 = 0b100010,
    Xmm3 = 0b100011,
    Rip  = 0b110000
};

namespace
{
    CpuReg x64Reg2CpuReg(X64Reg reg)
    {
        switch (reg)
        {
            case X64Reg::Rax:
                return CpuReg::Rax;
            case X64Reg::Rbx:
                return CpuReg::Rbx;
            case X64Reg::Rcx:
                return CpuReg::Rcx;
            case X64Reg::Rdx:
                return CpuReg::Rdx;
            case X64Reg::Rsp:
                return CpuReg::Rsp;
            case X64Reg::Rbp:
                return CpuReg::Rbp;
            case X64Reg::Rsi:
                return CpuReg::Rsi;
            case X64Reg::Rdi:
                return CpuReg::Rdi;
            case X64Reg::R8:
                return CpuReg::R8;
            case X64Reg::R9:
                return CpuReg::R9;
            case X64Reg::R10:
                return CpuReg::R10;
            case X64Reg::R11:
                return CpuReg::R11;
            case X64Reg::R12:
                return CpuReg::R12;
            case X64Reg::R13:
                return CpuReg::R13;
            case X64Reg::R14:
                return CpuReg::R14;
            case X64Reg::R15:
                return CpuReg::R15;
            case X64Reg::Xmm0:
                return CpuReg::Xmm0;
            case X64Reg::Xmm1:
                return CpuReg::Xmm1;
            case X64Reg::Xmm2:
                return CpuReg::Xmm2;
            case X64Reg::Xmm3:
                return CpuReg::Xmm3;
            case X64Reg::Rip:
                return CpuReg::Rip;

            default:
                SWC_ASSERT(false);
                return CpuReg::Rax;
        }
    }

    X64Reg cpuRegToX64Reg(CpuReg reg)
    {
        switch (reg)
        {
            case CpuReg::Rax:
                return X64Reg::Rax;
            case CpuReg::Rbx:
                return X64Reg::Rbx;
            case CpuReg::Rcx:
                return X64Reg::Rcx;
            case CpuReg::Rdx:
                return X64Reg::Rdx;
            case CpuReg::Rsp:
                return X64Reg::Rsp;
            case CpuReg::Rbp:
                return X64Reg::Rbp;
            case CpuReg::Rsi:
                return X64Reg::Rsi;
            case CpuReg::Rdi:
                return X64Reg::Rdi;
            case CpuReg::R8:
                return X64Reg::R8;
            case CpuReg::R9:
                return X64Reg::R9;
            case CpuReg::R10:
                return X64Reg::R10;
            case CpuReg::R11:
                return X64Reg::R11;
            case CpuReg::R12:
                return X64Reg::R12;
            case CpuReg::R13:
                return X64Reg::R13;
            case CpuReg::R14:
                return X64Reg::R14;
            case CpuReg::R15:
                return X64Reg::R15;
            case CpuReg::Xmm0:
                return X64Reg::Xmm0;
            case CpuReg::Xmm1:
                return X64Reg::Xmm1;
            case CpuReg::Xmm2:
                return X64Reg::Xmm2;
            case CpuReg::Xmm3:
                return X64Reg::Xmm3;
            case CpuReg::Rip:
                return X64Reg::Rip;
            default:
                SWC_ASSERT(false);
                return X64Reg::Rax;
        }
    }

    uint8_t encodeReg(CpuReg reg)
    {
        switch (reg)
        {
            case REX_REG_NONE:
            case MODRM_REG_0:
                return 0;
            case MODRM_REG_1:
                return 1;
            case MODRM_REG_2:
                return 2;
            case MODRM_REG_3:
                return 3;
            case MODRM_REG_4:
                return 4;
            case MODRM_REG_5:
                return 5;
            case MODRM_REG_6:
                return 6;
            case MODRM_REG_7:
                return 7;
            case MODRM_REG_SIB:
                return MODRM_RM_SIB;
            default:
                return static_cast<uint8_t>(cpuRegToX64Reg(reg)) & 0b11111;
        }
    }

    bool canEncode8(uint64_t value, OpBits opBits)
    {
        return value <= 0x7F ||
               (opBits == OpBits::B16 && value >= 0xFF80) ||
               (opBits == OpBits::B32 && value >= 0xFFFFFF80) ||
               (opBits == OpBits::B64 && value >= 0xFFFFFFFFFFFFFF80);
    }

    uint8_t getRex(bool w, bool r, bool x, bool b)
    {
        uint8_t rex = 0x40;
        if (w) // 64 bits
            rex |= 8;
        if (r) // extended MODRM.reg
            rex |= 4;
        if (x) // extended SIB.index
            rex |= 2;
        if (b) // extended MODRM.rm
            rex |= 1;
        return rex;
    }

    // Addressing mode
    uint8_t getModRm(ModRmMode mod, uint8_t reg, uint8_t rm)
    {
        const auto result = static_cast<uint32_t>(mod) << 6 | ((reg & 0b111) << 3) | (rm & 0b111);
        return static_cast<uint8_t>(result);
    }

    uint8_t getModRm(ModRmMode mod, CpuReg reg, uint8_t rm)
    {
        return getModRm(mod, encodeReg(reg), rm);
    }

    void emitPrefixF64(Store& store, OpBits opBits)
    {
        if (opBits == OpBits::B64)
            store.push_u8(0x66);
    }

    void emitSIB(Store& store, uint8_t scale, uint8_t index, uint8_t base)
    {
        const uint8_t value = static_cast<uint8_t>(scale << 6) | static_cast<uint8_t>(index << 3) | base;
        store.push_u8(value);
    }

    void emitRex(Store& store, OpBits opBits, CpuReg reg0 = REX_REG_NONE, CpuReg reg1 = REX_REG_NONE)
    {
        if (opBits == OpBits::B16)
            store.push_u8(0x66);

        const bool b1 = (reg0 >= CpuReg::R8 && reg0 <= CpuReg::R15);
        const bool b2 = (reg1 >= CpuReg::R8 && reg1 <= CpuReg::R15);
        if (opBits == OpBits::B64 ||
            b1 || b2 ||
            reg0 == CpuReg::Rsi || reg1 == CpuReg::Rsi ||
            reg0 == CpuReg::Rdi || reg1 == CpuReg::Rdi)
        {
            const auto value = getRex(opBits == OpBits::B64, b1, false, b2);
            store.push_u8(value);
        }
    }

    void emitValue(Store& store, uint64_t value, OpBits opBits)
    {
        if (opBits == OpBits::B8)
            store.push_u8(static_cast<uint8_t>(value));
        else if (opBits == OpBits::B16)
            store.push_u16(static_cast<uint16_t>(value));
        else if (opBits == OpBits::B32)
            store.push_u32(static_cast<uint32_t>(value));
        else
            store.push_u64(value);
    }

    void emitModRm(Store& store, ModRmMode mod, CpuReg reg, uint8_t rm)
    {
        const auto value = getModRm(mod, reg, rm);
        store.push_u8(value);
    }

    void emitModRm(Store& store, CpuReg reg, CpuReg memReg)
    {
        emitModRm(store, ModRmMode::Register, reg, encodeReg(memReg));
    }

    void emitModRm(Store& store, uint64_t memOffset, CpuReg reg, CpuReg memReg)
    {
        if (memOffset == 0 && memReg != CpuReg::R13)
        {
            if (memReg == CpuReg::Rsp || memReg == CpuReg::R12)
            {
                const auto modRm = getModRm(ModRmMode::Memory, reg, MODRM_RM_SIB);
                store.push_u8(modRm);
                emitSIB(store, 0, MODRM_RM_SIB, encodeReg(memReg) & 0b111);
            }
            else
            {
                const auto modRm = getModRm(ModRmMode::Memory, reg, encodeReg(memReg));
                store.push_u8(modRm);
            }
        }
        else if (memOffset <= 0x7F)
        {
            if (memReg == CpuReg::Rsp || memReg == CpuReg::R12)
            {
                const auto modRm = getModRm(ModRmMode::Displacement8, reg, MODRM_RM_SIB);
                store.push_u8(modRm);
                emitSIB(store, 0, MODRM_RM_SIB, encodeReg(memReg) & 0b111);
            }
            else
            {
                const auto modRm = getModRm(ModRmMode::Displacement8, reg, encodeReg(memReg));
                store.push_u8(modRm);
            }

            emitValue(store, memOffset, OpBits::B8);
        }
        else
        {
            if (memReg == CpuReg::Rsp || memReg == CpuReg::R12)
            {
                const auto modRm = getModRm(ModRmMode::Displacement32, reg, MODRM_RM_SIB);
                store.push_u8(modRm);
                emitSIB(store, 0, MODRM_RM_SIB, encodeReg(memReg) & 0b111);
            }
            else
            {
                const auto modRm = getModRm(ModRmMode::Displacement32, reg, encodeReg(memReg));
                store.push_u8(modRm);
            }

            SWC_ASSERT(memOffset <= 0x7FFFFFFF);
            emitValue(store, memOffset, OpBits::B32);
        }
    }

    void emitSpecB8(Store& store, uint8_t value, OpBits opBits)
    {
        if (opBits == OpBits::B8)
            store.push_u8(value & ~1);
        else
            store.push_u8(value);
    }

    void emitSpecF64(Store& store, uint8_t value, OpBits opBits)
    {
        if (opBits == OpBits::B64)
            store.push_u8(value & ~1);
        else if (opBits == OpBits::B32)
            store.push_u8(value);
    }

    void emitCpuOp(Store& store, CpuOp op)
    {
        store.push_u8(static_cast<uint8_t>(op));
    }

    void emitCpuOp(Store& store, uint8_t op)
    {
        store.push_u8(op);
    }

    void emitCpuOp(Store& store, uint8_t op, CpuReg reg)
    {
        store.push_u8(op | (encodeReg(reg) & 0b111));
    }

    void emitSpecCpuOp(Store& store, CpuOp op, OpBits opBits)
    {
        emitSpecB8(store, static_cast<uint8_t>(op), opBits);
    }

    void emitSpecCpuOp(Store& store, uint8_t op, OpBits opBits)
    {
        emitSpecB8(store, op, opBits);
    }
}

/////////////////////////////////////////////////////////////////////

CpuEncodeResult X64Encoder::encodeLoadSymbolRelocAddress(CpuReg reg, uint32_t symbolIndex, uint32_t offset, CpuEmitFlags emitFlags)
{
    emitRex(store_, OpBits::B64, reg);
    emitCpuOp(store_, 0x8D); // LEA
    emitModRm(store_, ModRmMode::Memory, reg, MODRM_RM_RIP);
    addSymbolRelocation(store_.size() - textSectionOffset_, symbolIndex, IMAGE_REL_AMD64_REL32);
    store_.push_u32(offset);
    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeLoadSymRelocValue(CpuReg reg, uint32_t symbolIndex, uint32_t offset, OpBits opBits, CpuEmitFlags emitFlags)
{
    if (isFloat(reg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitSpecF64(store_, 0xF3, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x10);
        emitModRm(store_, ModRmMode::Memory, reg, MODRM_RM_RIP);
        addSymbolRelocation(store_.size() - textSectionOffset_, symbolIndex, IMAGE_REL_AMD64_REL32);
        store_.push_u32(offset);
    }
    else if (emitFlags.has(EMIT_B64))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        SWC_ASSERT(opBits == OpBits::B64);
        emitRex(store_, opBits, REX_REG_NONE, reg);
        emitCpuOp(store_, 0xB8, reg); // MOV
        addSymbolRelocation(store_.size() - textSectionOffset_, symbolIndex, IMAGE_REL_AMD64_ADDR64);
        store_.push_u64(offset);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        SWC_ASSERT(opBits == OpBits::B64);
        emitRex(store_, opBits, reg);
        emitCpuOp(store_, 0x8B); // MOV
        emitModRm(store_, ModRmMode::Memory, reg, MODRM_RM_RIP);
        addSymbolRelocation(store_.size() - textSectionOffset_, symbolIndex, IMAGE_REL_AMD64_REL32);
        store_.push_u32(offset);
    }

    return CpuEncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

CpuEncodeResult X64Encoder::encodePush(CpuReg reg, CpuEmitFlags emitFlags)
{
    emitRex(store_, OpBits::Zero, REX_REG_NONE, reg);
    emitCpuOp(store_, 0x50, reg);
    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodePop(CpuReg reg, CpuEmitFlags emitFlags)
{
    emitRex(store_, OpBits::Zero, REX_REG_NONE, reg);
    emitCpuOp(store_, 0x58, reg);
    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeRet(CpuEmitFlags emitFlags)
{
    emitCpuOp(store_, 0xC3);
    return CpuEncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

CpuEncodeResult X64Encoder::encodeLoadRegReg(CpuReg regDst, CpuReg regSrc, OpBits opBits, CpuEmitFlags emitFlags)
{
    if (isFloat(regDst) && isFloat(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitSpecF64(store_, 0xF3, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x10);
        emitModRm(store_, regDst, regSrc);
    }
    else if (isFloat(regDst))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitPrefixF64(store_, OpBits::B64);
        emitRex(store_, opBits, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x6E);
        emitModRm(store_, regDst, regSrc);
    }
    else if (isFloat(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitPrefixF64(store_, OpBits::B64);
        emitRex(store_, opBits, regSrc, regDst);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x7E);
        emitModRm(store_, regSrc, regDst);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, regSrc, regDst);
        emitSpecCpuOp(store_, 0x89, opBits);
        emitModRm(store_, regSrc, regDst);
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeLoadRegImm(CpuReg reg, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags)
{
    if (isFloat(reg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Right2Cst;
        Report::internalError(module_, "emitLoadRegImm, cannot encode");
    }
    else if (opBits == OpBits::B8)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, reg);
        emitCpuOp(store_, 0xB0, reg);
        emitValue(store_, value, opBits);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, reg);
        emitCpuOp(store_, 0xB8, reg);
        emitValue(store_, value, opBits);
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeLoadRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits opBits, CpuEmitFlags emitFlags)
{
    if (isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeLoadRegMem, cannot encode");
    }
    else if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeLoadRegMem, cannot encode");
    }
    else if (isFloat(reg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, OpBits::Zero, reg, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x10);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, reg, memReg);
        emitSpecCpuOp(store_, 0x8B, opBits);
        emitModRm(store_, memOffset, reg, memReg);
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeLoadZeroExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);

    if (isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeLoadZeroExtendRegMem, cannot encode");
    }
    else if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeLoadZeroExtendRegMem, cannot encode");
    }
    else if (numBitsSrc == OpBits::B8 && (numBitsDst == OpBits::B32 || numBitsDst == OpBits::B64))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, numBitsDst, reg, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB6);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else if (numBitsSrc == OpBits::B16 && (numBitsDst == OpBits::B32 || numBitsDst == OpBits::B64))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, numBitsDst, reg, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB7);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else if (numBitsSrc == OpBits::B32 && numBitsDst == OpBits::B64)
    {
        return encodeLoadRegMem(reg, memReg, memOffset, numBitsSrc, emitFlags);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeLoadZeroExtendRegMem, cannot encode");
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeLoadZeroExtendRegReg(CpuReg regDst, CpuReg regSrc, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);

    if (isFloat(regDst) || isFloat(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeLoadZeroExtendRegReg, cannot encode");
    }
    else if (numBitsSrc == OpBits::B8 && (numBitsDst == OpBits::B32 || numBitsDst == OpBits::B64))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, numBitsDst, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB6);
        emitModRm(store_, regDst, regSrc);
    }
    else if (numBitsSrc == OpBits::B16 && (numBitsDst == OpBits::B32 || numBitsDst == OpBits::B64))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, OpBits::B64, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB7);
        emitModRm(store_, regDst, regSrc);
    }
    else if (numBitsSrc == OpBits::B32 && numBitsDst == OpBits::B64)
    {
        return encodeLoadRegReg(regDst, regSrc, numBitsSrc, emitFlags);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeLoadZeroExtendRegReg, cannot encode");
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeLoadSignedExtendRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);

    if (isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeLoadSignedExtendRegMem, cannot encode");
    }
    else if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeLoadSignedExtendRegMem, cannot encode");
    }
    else if (numBitsSrc == OpBits::B8)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, numBitsDst, reg, memReg);
        store_.push_u8(0x0F);
        store_.push_u8(0xBE);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else if (numBitsSrc == OpBits::B16)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, numBitsDst, reg, memReg);
        store_.push_u8(0x0F);
        store_.push_u8(0xBF);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else if (numBitsSrc == OpBits::B32)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        SWC_ASSERT(numBitsDst == OpBits::B64);
        emitRex(store_, OpBits::B64, reg, memReg);
        emitCpuOp(store_, 0x63);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeLoadSignedExtendRegMem, cannot encode");
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeLoadSignedExtendRegReg(CpuReg regDst, CpuReg regSrc, OpBits numBitsDst, OpBits numBitsSrc, CpuEmitFlags emitFlags)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);

    if (isFloat(regDst) || isFloat(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeLoadSignedExtendRegReg, cannot encode");
    }
    else if (numBitsSrc == OpBits::B8)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, numBitsDst, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xBE);
        emitModRm(store_, regDst, regSrc);
    }
    else if (numBitsSrc == OpBits::B16)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, numBitsDst, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xBF);
        emitModRm(store_, regDst, regSrc);
    }
    else if (numBitsSrc == OpBits::B32 && numBitsDst == OpBits::B64)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, numBitsDst, regDst, regSrc);
        emitCpuOp(store_, 0x63);
        emitModRm(store_, regDst, regSrc);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeLoadSignedExtendRegReg, cannot encode");
    }

    return CpuEncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

CpuEncodeResult X64Encoder::encodeLoadAddressRegMem(CpuReg reg, CpuReg memReg, uint64_t memOffset, OpBits opBits, CpuEmitFlags emitFlags)
{
    if (emitFlags.has(EMIT_CAN_ENCODE))
    {
        if (opBits != OpBits::B64)
            return CpuEncodeResult::NotSupported;
    }

    if (isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeLoadAddressRegMem, cannot encode");
    }
    else if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeLoadAddressRegMem, cannot encode");
    }
    else if (memReg == CpuReg::Rip)
    {
        SWC_ASSERT(memOffset == 0);
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, OpBits::B64, reg, memReg);
        emitCpuOp(store_, 0x8D);
        emitModRm(store_, ModRmMode::Memory, reg, MODRM_RM_RIP);
    }
    else if (memOffset == 0)
    {
        emitLoadRegReg(reg, memReg, OpBits::B64);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, OpBits::B64, reg, memReg);
        emitCpuOp(store_, 0x8D);
        emitModRm(store_, memOffset, reg, memReg);
    }

    return CpuEncodeResult::Zero;
}

namespace
{
    CpuEncodeResult encodeAmcImm(Store& store, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsBaseMul, uint64_t value, OpBits opBitsValue, CpuEmitFlags emitFlags)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (mulValue != 1 && mulValue != 2 && mulValue != 4 && mulValue != 8)
                return CpuEncodeResult::NotSupported;
            if (opBitsBaseMul != OpBits::B32 && opBitsBaseMul != OpBits::B64)
                return CpuEncodeResult::NotSupported;
            if (addValue > 0x7FFFFFFF)
                return CpuEncodeResult::NotSupported;
            if (value > 0x7FFFFFFF)
                return CpuEncodeResult::NotSupported;
            if (CpuEncoder::isFloat(regBase) || CpuEncoder::isFloat(regMul))
                return CpuEncodeResult::NotSupported;
            if (opBitsBaseMul != OpBits::B64 && (regBase == CpuReg::Rsp || regMul == CpuReg::Rsp))
                return CpuEncodeResult::NotSupported;
            if (regMul == CpuReg::Rsp && mulValue != 1)
                return CpuEncodeResult::NotSupported;
            return CpuEncodeResult::Zero;
        }

        if (regMul == CpuReg::Rsp)
        {
            SWC_ASSERT(mulValue == 1);
            std::swap(regMul, regBase);
        }

        // Prefixes
        if (opBitsValue == OpBits::B16)
            store.push_u8(0x66);

        // REX prefix
        const bool b1 = (regMul >= CpuReg::R8 && regMul <= CpuReg::R15);
        const bool b2 = (regBase >= CpuReg::R8 && regBase <= CpuReg::R15);
        if (opBitsValue == OpBits::B64 || b1 || b2)
        {
            const auto val = getRex(opBitsValue == OpBits::B64, false, b1, b2);
            store.push_u8(val);
        }

        // OpCode
        emitSpecCpuOp(store, 0xC7, opBitsValue);

        // ModRM
        if (regBase == CpuReg::R13)
            emitModRm(store, addValue <= 0x7F ? ModRmMode::Displacement8 : ModRmMode::Displacement32, MODRM_REG_0, MODRM_RM_SIB);
        else if (addValue == 0 || regBase == CpuReg::Max)
            emitModRm(store, ModRmMode::Memory, MODRM_REG_0, MODRM_RM_SIB);
        else
            emitModRm(store, addValue <= 0x7F ? ModRmMode::Displacement8 : ModRmMode::Displacement32, MODRM_REG_0, MODRM_RM_SIB);

        // SIB
        SWC_ASSERT(mulValue == 1 || mulValue == 2 || mulValue == 4 || mulValue == 8);
        const auto scale = static_cast<uint8_t>(log2(mulValue));
        if (regBase == CpuReg::Max)
        {
            emitSIB(store, scale, encodeReg(regMul) & 0b111, SIB_NO_BASE);
            emitValue(store, addValue, OpBits::B32);
        }
        else
        {
            emitSIB(store, scale, encodeReg(regMul) & 0b111, encodeReg(regBase) & 0b111);
            if (regBase == CpuReg::R13 || addValue != 0)
                emitValue(store, addValue, addValue <= 0x7F ? OpBits::B8 : OpBits::B32);
        }

        // Value
        emitValue(store, value, std::min(opBitsValue, OpBits::B32));
        return CpuEncodeResult::Zero;
    }

    CpuEncodeResult encodeAmcReg(Store& store, CpuReg reg, OpBits opBitsReg, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsBaseMul, CpuOp op, CpuEmitFlags emitFlags, bool mr)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (mulValue != 1 && mulValue != 2 && mulValue != 4 && mulValue != 8)
                return CpuEncodeResult::NotSupported;
            if (op == CpuOp::LEA && opBitsReg == OpBits::B8)
                return CpuEncodeResult::NotSupported;
            if (opBitsBaseMul != OpBits::B32 && opBitsBaseMul != OpBits::B64)
                return CpuEncodeResult::NotSupported;
            if (addValue > 0x7FFFFFFF)
                return CpuEncodeResult::NotSupported;
            if (CpuEncoder::isFloat(regBase) || CpuEncoder::isFloat(regMul))
                return CpuEncodeResult::NotSupported;
            if (CpuEncoder::isFloat(reg) && op == CpuOp::LEA)
                return CpuEncodeResult::NotSupported;
            if (CpuEncoder::isFloat(reg) && op == CpuOp::MOVSXD)
                return CpuEncodeResult::NotSupported;
            if (CpuEncoder::isFloat(reg) && opBitsReg != OpBits::B32 && opBitsReg != OpBits::B64)
                return CpuEncodeResult::NotSupported;
            if (opBitsBaseMul != OpBits::B64 && (regBase == CpuReg::Rsp || regMul == CpuReg::Rsp))
                return CpuEncodeResult::NotSupported;
            if (regMul == CpuReg::Rsp && mulValue != 1)
                return CpuEncodeResult::NotSupported;
            return CpuEncodeResult::Zero;
        }

        if (regMul == CpuReg::Rsp)
        {
            SWC_ASSERT(mulValue == 1);
            std::swap(regMul, regBase);
        }

        // Prefixes
        if (opBitsBaseMul == OpBits::B32)
            store.push_u8(0x67);
        if (opBitsReg == OpBits::B16 || CpuEncoder::isFloat(reg))
            store.push_u8(0x66);

        // REX prefix
        const bool b0      = (reg >= CpuReg::R8 && reg <= CpuReg::R15);
        const bool b1      = (regMul >= CpuReg::R8 && regMul <= CpuReg::R15);
        const bool b2      = (regBase >= CpuReg::R8 && regBase <= CpuReg::R15);
        const bool needREX = opBitsReg == OpBits::B64 || reg == CpuReg::Rsi || reg == CpuReg::Rdi || reg == CpuReg::Rbp;
        if (needREX || b0 || b1 || b2)
        {
            const auto value = getRex(opBitsReg == OpBits::B64, b0, b1, b2);
            store.push_u8(value);
        }

        // Opcode
        switch (op)
        {
            case CpuOp::LEA:
                emitSpecCpuOp(store, 0x8D, opBitsReg);
                break;
            case CpuOp::MOVSXD:
                emitSpecCpuOp(store, 0x63, opBitsReg);
                break;
            case CpuOp::MOV:
                if (CpuEncoder::isFloat(reg))
                {
                    emitCpuOp(store, 0x0F);
                    emitCpuOp(store, mr ? 0x7E : 0x6E);
                }
                else
                {
                    emitSpecCpuOp(store, mr ? 0x89 : 0x8B, opBitsReg);
                }
                break;
            default:
                SWC_ASSERT(false);
                break;
        }

        // ModRM
        if (regBase == CpuReg::R13)
            emitModRm(store, addValue <= 0x7F ? ModRmMode::Displacement8 : ModRmMode::Displacement32, reg, MODRM_RM_SIB);
        else if (addValue == 0 || regBase == CpuReg::Max)
            emitModRm(store, ModRmMode::Memory, reg, MODRM_RM_SIB);
        else
            emitModRm(store, addValue <= 0x7F ? ModRmMode::Displacement8 : ModRmMode::Displacement32, reg, MODRM_RM_SIB);

        // SIB
        SWC_ASSERT(mulValue == 1 || mulValue == 2 || mulValue == 4 || mulValue == 8);
        const auto scale = static_cast<uint8_t>(log2(mulValue));
        if (regBase == CpuReg::Max)
        {
            emitSIB(store, scale, encodeReg(regMul) & 0b111, SIB_NO_BASE);
            emitValue(store, addValue, OpBits::B32);
        }
        else
        {
            emitSIB(store, scale, encodeReg(regMul) & 0b111, encodeReg(regBase) & 0b111);
            if (regBase == CpuReg::R13 || addValue != 0)
                emitValue(store, addValue, addValue <= 0x7F ? OpBits::B8 : OpBits::B32);
        }

        return CpuEncodeResult::Zero;
    }
}

CpuEncodeResult X64Encoder::encodeLoadAmcRegMem(CpuReg regDst, OpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsSrc, CpuEmitFlags emitFlags)
{
    return encodeAmcReg(store_, regDst, opBitsDst, regBase, regMul, mulValue, addValue, opBitsSrc, CpuOp::MOV, emitFlags, false);
}

CpuEncodeResult X64Encoder::encodeLoadAmcMemReg(CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsBaseMul, CpuReg regSrc, OpBits opBitsSrc, CpuEmitFlags emitFlags)
{
    return encodeAmcReg(store_, regSrc, opBitsSrc, regBase, regMul, mulValue, addValue, opBitsBaseMul, CpuOp::MOV, emitFlags, true);
}

CpuEncodeResult X64Encoder::encodeLoadAmcMemImm(CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsBaseMul, uint64_t value, OpBits opBitsValue, CpuEmitFlags emitFlags)
{
    return encodeAmcImm(store_, regBase, regMul, mulValue, addValue, opBitsBaseMul, value, opBitsValue, emitFlags);
}

CpuEncodeResult X64Encoder::encodeLoadAddressAmcRegMem(CpuReg regDst, OpBits opBitsDst, CpuReg regBase, CpuReg regMul, uint64_t mulValue, uint64_t addValue, OpBits opBitsValue, CpuEmitFlags emitFlags)
{
    return encodeAmcReg(store_, regDst, opBitsDst, regBase, regMul, mulValue, addValue, opBitsValue, CpuOp::LEA, emitFlags, false);
}

/////////////////////////////////////////////////////////////////////

CpuEncodeResult X64Encoder::encodeLoadMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, OpBits opBits, CpuEmitFlags emitFlags)
{
    if (isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeLoadRegMem, cannot encode");
    }
    else if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeLoadMemReg, cannot encode");
    }
    else if (isFloat(reg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, OpBits::Zero, reg, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x11);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, reg, memReg);
        emitSpecCpuOp(store_, 0x89, opBits);
        emitModRm(store_, memOffset, reg, memReg);
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeLoadMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags)
{
    if (isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeLoadMemImm, cannot encode");
    }
    else if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeLoadMemImm, cannot encode");
    }
    else if (opBits == OpBits::B128)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Right2Reg;
        Report::internalError(module_, "encodeLoadMemImm, cannot encode");
    }
    else if (opBits == OpBits::B64 && value > 0x7FFFFFFF && value >> 32 != 0xFFFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Right2Reg;
        Report::internalError(module_, "encodeLoadMemImm, cannot encode");
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, memReg);
        emitSpecB8(store_, 0xC7, opBits);
        emitModRm(store_, memOffset, MODRM_REG_0, memReg);
        emitValue(store_, value, std::min(opBits, OpBits::B32));
    }

    return CpuEncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

CpuEncodeResult X64Encoder::encodeClearReg(CpuReg reg, OpBits opBits, CpuEmitFlags emitFlags)
{
    if (emitFlags.has(EMIT_CAN_ENCODE))
        return CpuEncodeResult::Zero;

    if (isFloat(reg))
    {
        emitPrefixF64(store_, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, CpuOp::FXOR);
        emitModRm(store_, reg, reg);
    }
    else
    {
        emitRex(store_, opBits, reg, reg);
        emitSpecCpuOp(store_, CpuOp::XOR, opBits);
        emitModRm(store_, reg, reg);
    }

    return CpuEncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

CpuEncodeResult X64Encoder::encodeSetCondReg(CpuReg reg, CpuCond cpuCond, CpuEmitFlags emitFlags)
{
    if (emitFlags.has(EMIT_CAN_ENCODE))
        return CpuEncodeResult::Zero;

    emitRex(store_, OpBits::B8, REX_REG_NONE, reg);
    emitCpuOp(store_, 0x0F);

    switch (cpuCond)
    {
        case CpuCond::A:
            emitCpuOp(store_, 0x97);
            break;
        case CpuCond::O:
            emitCpuOp(store_, 0x90);
            break;
        case CpuCond::AE:
            emitCpuOp(store_, 0x93);
            break;
        case CpuCond::G:
            emitCpuOp(store_, 0x9F);
            break;
        case CpuCond::NE:
            emitCpuOp(store_, 0x95);
            break;
        case CpuCond::NA:
            emitCpuOp(store_, 0x96);
            break;
        case CpuCond::B:
            emitCpuOp(store_, 0x92);
            break;
        case CpuCond::BE:
            emitCpuOp(store_, 0x96);
            break;
        case CpuCond::E:
            emitCpuOp(store_, 0x94);
            break;
        case CpuCond::GE:
            emitCpuOp(store_, 0x9D);
            break;
        case CpuCond::L:
            emitCpuOp(store_, 0x9C);
            break;
        case CpuCond::LE:
            emitCpuOp(store_, 0x9E);
            break;
        case CpuCond::P:
            emitCpuOp(store_, 0x9A);
            break;
        case CpuCond::NP:
            emitCpuOp(store_, 0x9B);
            break;
        default:
            SWC_ASSERT(false);
            break;
    }

    emitModRm(store_, MODRM_REG_0, reg);
    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeLoadCondRegReg(CpuReg regDst, CpuReg regSrc, CpuCond setType, OpBits opBits, CpuEmitFlags emitFlags)
{
    if (emitFlags.has(EMIT_CAN_ENCODE))
        return CpuEncodeResult::Zero;

    opBits = std::max(opBits, OpBits::B32);
    emitRex(store_, opBits, regDst, regSrc);
    emitCpuOp(store_, 0x0F);

    switch (setType)
    {
        case CpuCond::B:
            emitCpuOp(store_, 0x42);
            break;
        case CpuCond::E:
            emitCpuOp(store_, 0x44);
            break;
        case CpuCond::G:
            emitCpuOp(store_, 0x4F);
            break;
        case CpuCond::L:
            emitCpuOp(store_, 0x4C);
            break;
        case CpuCond::BE:
            emitCpuOp(store_, 0x46);
            break;
        case CpuCond::GE:
            emitCpuOp(store_, 0x4D);
            break;
        default:
            SWC_ASSERT(false);
            break;
    }

    emitModRm(store_, regDst, regSrc);
    return CpuEncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

CpuEncodeResult X64Encoder::encodeCmpRegReg(CpuReg reg0, CpuReg reg1, OpBits opBits, CpuEmitFlags emitFlags)
{
    if (isFloat(reg0))
    {
        if (isInt(reg1))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Right2Reg;
            Report::internalError(module_, "encodeCmpRegReg, cannot encode");
        }

        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitPrefixF64(store_, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x2F);
        emitModRm(store_, reg0, reg1);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (isFloat(reg1))
                return CpuEncodeResult::NotSupported;
            return CpuEncodeResult::Zero;
        }

        emitRex(store_, opBits, reg1, reg0);
        emitSpecCpuOp(store_, 0x39, opBits);
        emitModRm(store_, reg1, reg0);
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeCmpRegImm(CpuReg reg, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags)
{
    if (isFloat(reg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeCmpRegImm, cannot encode");
    }
    else if (opBits == OpBits::B8)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, reg);
        emitCpuOp(store_, 0x80);
        emitModRm(store_, MODRM_REG_7, reg);
        emitValue(store_, value, OpBits::B8);
    }
    else if (canEncode8(value, opBits))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, reg);
        emitCpuOp(store_, 0x83);
        emitModRm(store_, MODRM_REG_7, reg);
        emitValue(store_, value, OpBits::B8);
    }
    else if ((opBits != OpBits::B64 || value <= 0x7FFFFFFF))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, reg);
        emitCpuOp(store_, 0x81);
        emitModRm(store_, MODRM_REG_7, reg);
        emitValue(store_, value, std::min(opBits, OpBits::B32));
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Right2Reg;
        Report::internalError(module_, "encodeCmpRegImm, cannot encode");
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeCmpMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, OpBits opBits, CpuEmitFlags emitFlags)
{
    if (isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeCmpMemReg, cannot encode");
    }
    else if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeCmpMemReg, cannot encode");
    }
    else if (isFloat(reg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Left2Reg;
        Report::internalError(module_, "encodeCmpMemReg, cannot encode");
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, reg, memReg);
        emitSpecCpuOp(store_, 0x39, opBits);
        emitModRm(store_, memOffset, reg, memReg);
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeCmpMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, OpBits opBits, CpuEmitFlags emitFlags)
{
    if (isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeCmpMemImm, cannot encode");
    }
    else if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeCmpMemImm, cannot encode");
    }
    else if (opBits == OpBits::B8)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, memReg);
        emitCpuOp(store_, 0x80);
        emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        emitValue(store_, value, OpBits::B8);
    }
    else if (canEncode8(value, opBits))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, memReg);
        emitCpuOp(store_, 0x83);
        emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        emitValue(store_, value, OpBits::B8);
    }
    else if (value <= 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, memReg);
        emitCpuOp(store_, 0x81);
        emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        emitValue(store_, value, opBits == OpBits::B16 ? opBits : OpBits::B32);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Right2Reg;
        Report::internalError(module_, "encodeCmpRegImm, cannot encode");
    }

    return CpuEncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

CpuEncodeResult X64Encoder::encodeOpUnaryMem(CpuReg memReg, uint64_t memOffset, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)
{
    if (isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeOpUnaryMem, cannot encode");
    }
    else if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeOpUnaryMem, cannot encode");
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::NOT)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits);
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, memOffset, MODRM_REG_2, memReg);
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::NEG)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits);
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, memOffset, MODRM_REG_3, memReg);
    }

    ///////////////////////////////////////////

    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeOpUnaryMem, cannot encode");
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeOpUnaryReg(CpuReg reg, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)
{
    if (emitFlags.has(EMIT_CAN_ENCODE))
    {
        if (isFloat(reg))
            return CpuEncodeResult::NotSupported;
        return CpuEncodeResult::Zero;
    }

    ///////////////////////////////////////////

    if (op == CpuOp::NOT)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, reg);
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, MODRM_REG_2, reg);
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::NEG)
    {
        if (isFloat(reg))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::NotSupported;
            Report::internalError(module_, "encodeOpUnaryReg, cannot encode");
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitSpecCpuOp(store_, 0xF7, opBits);
            emitModRm(store_, MODRM_REG_3, reg);
        }
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::BSWAP)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        if (opBits == OpBits::B16)
        {
            // rol ax, 0x8
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0xC1);
            emitCpuOp(store_, 0xC0);
            emitValue(store_, 0x08, OpBits::B8);
        }
        else
        {
            SWC_ASSERT(opBits == OpBits::B16 || opBits == OpBits::B32 || opBits == OpBits::B64);
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0xC8, reg);
        }
    }

    ///////////////////////////////////////////

    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeOpUnaryReg, cannot encode");
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeOpBinaryRegMem(CpuReg regDst, CpuReg memReg, uint64_t memOffset, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)
{
    if (isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeOpBinaryRegMem, cannot encode");
    }
    else if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeOpBinaryRegMem, cannot encode");
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::ADD)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x03, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::SUB)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x2B, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::AND)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x23, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::OR)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x0B, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::XOR)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x33, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::IMUL)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        if (opBits == OpBits::B8)
            emitLoadSignedExtendRegReg(regDst, regDst, OpBits::B32, opBits);
        emitRex(store_, opBits, regDst, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xAF);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Right2Reg;
        Report::internalError(module_, "encodeOpBinaryRegMem, cannot encode");
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeOpBinaryRegReg(CpuReg regDst, CpuReg regSrc, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)
{
    ///////////////////////////////////////////

    if (op == CpuOp::CVTU2F64)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeOpBinaryRegReg, cannot encode");
    }

    ///////////////////////////////////////////

    else if (isFloat(regDst) && isInt(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (op != CpuOp::CVTI2F && op != CpuOp::CVTU2F64)
                return CpuEncodeResult::NotSupported;
            return CpuEncodeResult::Zero;
        }

        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, emitFlags.has(EMIT_B64) ? OpBits::B64 : OpBits::B32, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, op);
        emitModRm(store_, regDst, regSrc);
    }

    else if (isInt(regDst) && isFloat(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (op != CpuOp::CVTF2I)
                return CpuEncodeResult::NotSupported;
            return CpuEncodeResult::Zero;
        }

        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, emitFlags.has(EMIT_B64) ? OpBits::B64 : OpBits::B32, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, op);
        emitModRm(store_, regDst, regSrc);
    }

    else if (isFloat(regDst) && isFloat(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;

        if (op != CpuOp::FSQRT && op != CpuOp::FAND && op != CpuOp::FXOR)
        {
            emitSpecF64(store_, 0xF3, opBits);
            emitRex(store_, emitFlags.has(EMIT_B64) ? OpBits::B64 : OpBits::B32, regDst, regSrc);
        }
        else
        {
            emitPrefixF64(store_, opBits);
        }

        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, op);
        emitModRm(store_, regDst, regSrc);
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::DIV ||
             op == CpuOp::IDIV ||
             op == CpuOp::MOD ||
             op == CpuOp::IMOD)
    {
        const auto rax = x64Reg2CpuReg(X64Reg::Rax);
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (cpuRegToX64Reg(regDst) != X64Reg::Rax)
                return CpuEncodeResult::Left2Rax;
            if (cpuRegToX64Reg(regSrc) == X64Reg::Rax)
                return CpuEncodeResult::NotSupported;
            if (cpuRegToX64Reg(regSrc) == X64Reg::Rdx)
                return CpuEncodeResult::NotSupported;

            return CpuEncodeResult::Zero;
        }

        if ((op == CpuOp::IDIV || op == CpuOp::IMOD) && opBits == OpBits::B8)
            emitLoadSignedExtendRegReg(rax, rax, OpBits::B32, OpBits::B8);
        else if (opBits == OpBits::B8)
            emitLoadZeroExtendRegReg(rax, rax, OpBits::B32, OpBits::B8);
        else if (op == CpuOp::DIV || op == CpuOp::MOD)
            emitClearReg(x64Reg2CpuReg(X64Reg::Rdx), opBits);
        else
        {
            emitRex(store_, opBits);
            emitCpuOp(store_, 0x99); // cdq
        }

        emitRex(store_, opBits, rax, regSrc);
        emitSpecCpuOp(store_, 0xF7, opBits);
        if (op == CpuOp::DIV || op == CpuOp::MOD)
            emitModRm(store_, MODRM_REG_6, regSrc);
        else if (op == CpuOp::IDIV || op == CpuOp::IMOD)
            emitModRm(store_, MODRM_REG_7, regSrc);

        if ((op == CpuOp::MOD || op == CpuOp::IMOD) && opBits == OpBits::B8)
            emitOpBinaryRegImm(rax, 8, CpuOp::SHR, OpBits::B32, emitFlags); // AH => AL
        else if (op == CpuOp::MOD || op == CpuOp::IMOD)
            emitLoadRegReg(rax, x64Reg2CpuReg(X64Reg::Rdx), opBits);
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::MUL)
    {
        const auto rax = x64Reg2CpuReg(X64Reg::Rax);
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (cpuRegToX64Reg(regDst) != X64Reg::Rax)
                return CpuEncodeResult::Left2Rax;
            if (cpuRegToX64Reg(regSrc) == X64Reg::Rax)
                return CpuEncodeResult::NotSupported;
            if (cpuRegToX64Reg(regSrc) == X64Reg::Rdx)
                return CpuEncodeResult::NotSupported;

            return CpuEncodeResult::Zero;
        }

        emitRex(store_, opBits, rax, regSrc);
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, MODRM_REG_4, regSrc);
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::IMUL)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;

        if (opBits == OpBits::B8)
        {
            emitLoadSignedExtendRegReg(regDst, regDst, OpBits::B32, opBits);
            emitLoadSignedExtendRegReg(regSrc, regSrc, OpBits::B32, opBits);
        }

        emitRex(store_, opBits, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xAF);
        emitModRm(store_, regDst, regSrc);
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::ROL ||
             op == CpuOp::ROR ||
             op == CpuOp::SAL ||
             op == CpuOp::SAR ||
             op == CpuOp::SHL ||
             op == CpuOp::SHR)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (cpuRegToX64Reg(regSrc) != X64Reg::Rcx)
            {
                SWC_ASSERT(x64Reg2CpuReg(X64Reg::Rcx) == CpuReg::Rcx);
                return CpuEncodeResult::Right2Rcx;
            }

            return CpuEncodeResult::Zero;
        }

        SWC_ASSERT(cpuRegToX64Reg(regSrc) == X64Reg::Rcx);
        emitRex(store_, opBits, REX_REG_NONE, regDst);
        emitSpecCpuOp(store_, 0xD3, opBits);
        if (op == CpuOp::ROL)
            emitModRm(store_, MODRM_REG_0, regDst);
        else if (op == CpuOp::ROR)
            emitModRm(store_, MODRM_REG_1, regDst);
        else if (op == CpuOp::SAL || op == CpuOp::SHL)
            emitModRm(store_, MODRM_REG_4, regDst);
        else if (op == CpuOp::SAR)
            emitModRm(store_, MODRM_REG_7, regDst);
        else if (op == CpuOp::SHR)
            emitModRm(store_, MODRM_REG_5, regDst);
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::ADD ||
             op == CpuOp::SUB ||
             op == CpuOp::XOR ||
             op == CpuOp::AND ||
             op == CpuOp::OR)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, regSrc, regDst);
        emitSpecCpuOp(store_, op, opBits);
        emitModRm(store_, regSrc, regDst);
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::XCHG)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        emitRex(store_, opBits, regSrc, regDst);
        emitSpecCpuOp(store_, 0x87, opBits);
        emitModRm(store_, regSrc, regDst);
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::BSF || op == CpuOp::BSR)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (opBits == OpBits::B8)
                return CpuEncodeResult::ForceZero32;
            return CpuEncodeResult::Zero;
        }

        emitRex(store_, opBits, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, op == CpuOp::BSF ? 0xBC : 0xBD);
        emitModRm(store_, regDst, regSrc);
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::POPCNT)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (opBits == OpBits::B8)
                return CpuEncodeResult::ForceZero32;
            return CpuEncodeResult::Zero;
        }
        emitCpuOp(store_, 0xF3);
        emitRex(store_, opBits, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB8);
        emitModRm(store_, regDst, regSrc);
    }

    ///////////////////////////////////////////

    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeOpBinaryRegReg, cannot encode");
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeOpBinaryMemReg(CpuReg memReg, uint64_t memOffset, CpuReg reg, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)
{
    if (isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeOpBinaryMemReg, cannot encode");
    }
    else if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeOpBinaryMemReg, cannot encode");
    }

    ///////////////////////////////////////////

    if (isFloat(reg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Left2Reg;
        Report::internalError(module_, "encodeOpBinaryMemReg, cannot encode");
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::DIV ||
             op == CpuOp::IDIV ||
             op == CpuOp::MOD ||
             op == CpuOp::IMOD ||
             op == CpuOp::IMUL ||
             op == CpuOp::MUL)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Left2Reg;
        Report::internalError(module_, "encodeOpBinaryMemReg, cannot encode");
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::SAR ||
             op == CpuOp::SHR ||
             op == CpuOp::SHL)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (cpuRegToX64Reg(reg) != X64Reg::Rcx)
            {
                SWC_ASSERT(x64Reg2CpuReg(X64Reg::Rcx) == CpuReg::Rcx);
                return CpuEncodeResult::Right2Rcx;
            }

            return CpuEncodeResult::Zero;
        }

        if (emitFlags.has(EMIT_LOCK))
            store_.push_u8(0xF0);
        emitRex(store_, opBits, REX_REG_NONE, memReg);
        emitSpecCpuOp(store_, 0xD3, opBits);
        if (op == CpuOp::SHL)
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
        else if (op == CpuOp::SAR)
            emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        else if (op == CpuOp::SHR)
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
    }

    ///////////////////////////////////////////

    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;
        if (emitFlags.has(EMIT_LOCK))
            store_.push_u8(0xF0);
        emitRex(store_, opBits, reg, memReg);
        emitSpecCpuOp(store_, op, opBits);
        emitModRm(store_, memOffset, reg, memReg);
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeOpBinaryRegImm(CpuReg reg, uint64_t value, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)
{
    ///////////////////////////////////////////

    if (op == CpuOp::XOR)
    {
        if (opBits == OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_6, reg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_6, reg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_6, reg);
            emitValue(store_, value, std::min(opBits, OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Right2Reg;
            Report::internalError(module_, "encodeOpBinaryRegImm, cannot encode");
        }
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::OR)
    {
        if (opBits == OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_1, reg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_1, reg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_1, reg);
            emitValue(store_, value, std::min(opBits, OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Right2Reg;
            Report::internalError(module_, "encodeOpBinaryRegImm, cannot encode");
        }
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::AND)
    {
        if (opBits == OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_4, reg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_4, reg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_4, reg);
            emitValue(store_, value, std::min(opBits, OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Right2Reg;
            Report::internalError(module_, "encodeOpBinaryRegImm, cannot encode");
        }
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::ADD)
    {
        if (value == 1 && !emitFlags.has(EMIT_OVERFLOW) && optLevel_ >= BuildCfgBackendOptim::O1)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitSpecCpuOp(store_, 0xFF, opBits);
            emitModRm(store_, MODRM_REG_0, reg);
        }
        else if (opBits == OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_0, reg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_0, reg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_0, reg);
            emitValue(store_, value, std::min(opBits, OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Right2Reg;
            Report::internalError(module_, "encodeOpBinaryRegImm, cannot encode");
        }
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::SUB)
    {
        if (value == 1 && !emitFlags.has(EMIT_OVERFLOW) && optLevel_ >= BuildCfgBackendOptim::O1)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitSpecCpuOp(store_, 0xFF, opBits);
            emitModRm(store_, MODRM_REG_1, reg);
        }
        else if (opBits == OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_5, reg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_5, reg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_5, reg);
            emitValue(store_, value, std::min(opBits, OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Right2Reg;
            Report::internalError(module_, "encodeOpBinaryRegImm, cannot encode");
        }
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::MOD ||
             op == CpuOp::IMOD ||
             op == CpuOp::DIV ||
             op == CpuOp::IDIV ||
             op == CpuOp::MUL)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Right2Reg;
        Report::internalError(module_, "encodeOpBinaryRegImm, cannot encode");
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::IMUL)
    {
        if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            if (opBits == OpBits::B8)
                emitLoadSignedExtendRegReg(reg, reg, OpBits::B32, opBits);
            emitRex(store_, opBits, reg, reg);
            emitCpuOp(store_, 0x6B);
            emitModRm(store_, reg, reg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            if (opBits == OpBits::B8 || opBits == OpBits::B16)
                emitLoadSignedExtendRegReg(reg, reg, OpBits::B32, opBits);
            emitRex(store_, opBits, reg, reg);
            emitCpuOp(store_, 0x69);
            emitModRm(store_, reg, reg);
            emitValue(store_, value, OpBits::B32);
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Right2Reg;
            Report::internalError(module_, "encodeOpBinaryRegImm, cannot encode");
        }
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::SHL)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;

        SWC_ASSERT(value <= 0x7F);
        if (value == 1)
        {
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitSpecCpuOp(store_, 0xD1, opBits);
            emitModRm(store_, MODRM_REG_4, reg);
        }
        else
        {
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitSpecCpuOp(store_, 0xC1, opBits);
            emitModRm(store_, MODRM_REG_4, reg);
            emitValue(store_, std::min(static_cast<uint32_t>(value), BackendEncoder::getNumBits(opBits) - 1), OpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::SHR)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;

        SWC_ASSERT(value <= 0x7F);
        if (value == 1)
        {
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitSpecCpuOp(store_, 0xD1, opBits);
            emitModRm(store_, MODRM_REG_5, reg);
        }
        else
        {
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitSpecCpuOp(store_, 0xC1, opBits);
            emitModRm(store_, MODRM_REG_5, reg);
            emitValue(store_, std::min(static_cast<uint32_t>(value), BackendEncoder::getNumBits(opBits) - 1), OpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::SAR)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;

        SWC_ASSERT(value <= 0x7F);
        if (value == 1)
        {
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitSpecCpuOp(store_, 0xD1, opBits);
            emitModRm(store_, MODRM_REG_7, reg);
        }
        else
        {
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitSpecCpuOp(store_, 0xC1, opBits);
            emitModRm(store_, MODRM_REG_7, reg);
            emitValue(store_, std::min(static_cast<uint32_t>(value), BackendEncoder::getNumBits(opBits) - 1), OpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeOpBinaryRegImm, cannot encode");
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeOpBinaryMemImm(CpuReg memReg, uint64_t memOffset, uint64_t value, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)
{
    if (isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeOpBinaryMemImm, cannot encode");
    }
    else if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::NotSupported;
        Report::internalError(module_, "encodeOpBinaryMemImm, cannot encode");
    }

    ///////////////////////////////////////////

    if (op == CpuOp::IMOD ||
        op == CpuOp::MOD ||
        op == CpuOp::DIV ||
        op == CpuOp::IDIV ||
        op == CpuOp::IMUL ||
        op == CpuOp::MUL)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Right2Reg;
        Report::internalError(module_, "encodeOpBinaryMemImm, cannot encode");
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::SAR)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;

        if (value == 1)
        {
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitSpecCpuOp(store_, 0xD1, opBits);
            emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        }
        else
        {
            SWC_ASSERT(value <= 0x7F);
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitSpecCpuOp(store_, 0xC1, opBits);
            emitModRm(store_, memOffset, MODRM_REG_7, memReg);
            emitValue(store_, std::min(static_cast<uint32_t>(value), BackendEncoder::getNumBits(opBits) - 1), OpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::SHR)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;

        if (value == 1)
        {
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitSpecCpuOp(store_, 0xD1, opBits);
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
        }
        else
        {
            SWC_ASSERT(value <= 0x7F);
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitSpecCpuOp(store_, 0xC1, opBits);
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
            emitValue(store_, std::min(static_cast<uint32_t>(value), BackendEncoder::getNumBits(opBits) - 1), OpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::SHL)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return CpuEncodeResult::Zero;

        if (value == 1)
        {
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitSpecCpuOp(store_, 0xD1, opBits);
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
        }
        else
        {
            SWC_ASSERT(value <= 0x7F);
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitSpecCpuOp(store_, 0xC1, opBits);
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
            emitValue(store_, std::min(static_cast<uint32_t>(value), BackendEncoder::getNumBits(opBits) - 1), OpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::ADD)
    {
        if (value == 1 && !emitFlags.has(EMIT_OVERFLOW) && optLevel_ >= BuildCfgBackendOptim::O1)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitSpecCpuOp(store_, 0xFF, opBits);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
        }
        else if (opBits == OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
            emitValue(store_, value, std::min(opBits, OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Right2Reg;
            Report::internalError(module_, "encodeOpBinaryMemImm, cannot encode");
        }
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::SUB)
    {
        if (value == 1 && !emitFlags.has(EMIT_OVERFLOW) && optLevel_ >= BuildCfgBackendOptim::O1)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitSpecCpuOp(store_, 0xFF, opBits);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
        }
        else if (opBits == OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
            emitValue(store_, value, std::min(opBits, OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Right2Reg;
            Report::internalError(module_, "encodeOpBinaryMemImm, cannot encode");
        }
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::OR)
    {
        if (opBits == OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
            emitValue(store_, value, std::min(opBits, OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Right2Reg;
            Report::internalError(module_, "encodeOpBinaryMemImm, cannot encode");
        }
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::AND)
    {
        if (opBits == OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
            emitValue(store_, value, std::min(opBits, OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Right2Reg;
            Report::internalError(module_, "encodeOpBinaryMemImm, cannot encode");
        }
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::XOR)
    {
        if (opBits == OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_6, memReg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_6, memReg);
            emitValue(store_, value, OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_6, memReg);
            emitValue(store_, value, std::min(opBits, OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return CpuEncodeResult::Right2Reg;
            Report::internalError(module_, "encodeOpBinaryMemImm, cannot encode");
        }
    }

    ///////////////////////////////////////////

    else
    {
        Report::internalError(module_, "encodeOpBinaryMemImm, cannot encode");
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeOpTernaryRegRegReg(CpuReg reg0, CpuReg reg1, CpuReg reg2, CpuOp op, OpBits opBits, CpuEmitFlags emitFlags)
{
    ///////////////////////////////////////////

    if (op == CpuOp::MULADD)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (isFloat(reg0) != isFloat(reg1) || isFloat(reg0) != isFloat(reg2))
                return CpuEncodeResult::NotSupported;
            if (!isFloat(reg0))
                return CpuEncodeResult::NotSupported;
            return CpuEncodeResult::Zero;
        }

        SWC_ASSERT(isFloat(reg0) && isFloat(reg1) && isFloat(reg2));
        emitSpecF64(store_, 0xF3, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, CpuOp::FMUL);
        emitModRm(store_, reg0, reg1);

        emitSpecF64(store_, 0xF3, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, CpuOp::FADD);
        emitModRm(store_, reg0, reg2);
    }

    ///////////////////////////////////////////

    else if (op == CpuOp::CMPXCHG)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (cpuRegToX64Reg(reg0) != X64Reg::Rax)
            {
                return CpuEncodeResult::Left2Rax;
            }

            return CpuEncodeResult::Zero;
        }

        SWC_ASSERT(cpuRegToX64Reg(reg0) == X64Reg::Rax);

        if (emitFlags.has(EMIT_LOCK))
            emitCpuOp(store_, 0xF0);
        emitRex(store_, opBits, reg2, reg1);
        emitCpuOp(store_, 0x0F);
        emitSpecCpuOp(store_, 0xB1, opBits);
        emitModRm(store_, 0, reg2, reg1);
    }

    ///////////////////////////////////////////

    else
    {
        Report::internalError(module_, "encodeOpTernaryRegRegReg, cannot encode");
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeJumpTable(CpuReg tableReg, CpuReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, CpuEmitFlags emitFlags)
{
    const auto [offsetTableConstant, addrConstant] = buildParams_.module->constantSegment.reserveSpan<uint32_t>(numEntries);
    emitLoadSymRelocAddress(tableReg, symCsIndex_, offsetTableConstant);

    // movsxd table, dword ptr [table + offset*4]
    encodeAmcReg(store_, tableReg, OpBits::B64, tableReg, offsetReg, 4, 0, OpBits::B64, CpuOp::MOVSXD, emitFlags, false);

    const auto startIdx = store_.size();
    emitLoadSymRelocAddress(offsetReg, cpuFct_->symbolIndex, store_.size() - cpuFct_->startAddress);
    const auto patchPtr = reinterpret_cast<uint32_t*>(store_.seek_ptr()) - 1;
    emitOpBinaryRegReg(offsetReg, tableReg, CpuOp::ADD, OpBits::B64, emitFlags);
    emitJumpReg(offsetReg);
    const auto endIdx = store_.size();
    *patchPtr += endIdx - startIdx;

    const auto tableCompiler = buildParams_.module->compilerSegment.ptr<int32_t>(offsetTable);
    const auto currentOffset = static_cast<int32_t>(store_.size());

    CpuLabelToSolve label;
    for (uint32_t idx = 0; idx < numEntries; idx++)
    {
        label.ipDest               = tableCompiler[idx] + currentIp + 1;
        label.jump.opBits          = OpBits::B32;
        label.jump.offsetStart     = currentOffset;
        label.jump.patchOffsetAddr = addrConstant + idx;
        cpuFct_->labelsToSolve.push_back(label);
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeJump(CpuJump& jump, CpuCondJump jumpType, OpBits opBits, CpuEmitFlags emitFlags)
{
    SWC_ASSERT(opBits == OpBits::B8 || opBits == OpBits::B32);

    if (opBits == OpBits::B8)
    {
        switch (jumpType)
        {
            case CpuCondJump::JNO:
                emitCpuOp(store_, 0x71);
                break;
            case CpuCondJump::JB:
                emitCpuOp(store_, 0x72);
                break;
            case CpuCondJump::JAE:
                emitCpuOp(store_, 0x73);
                break;
            case CpuCondJump::JZ:
                emitCpuOp(store_, 0x74);
                break;
            case CpuCondJump::JNZ:
                emitCpuOp(store_, 0x75);
                break;
            case CpuCondJump::JBE:
                emitCpuOp(store_, 0x76);
                break;
            case CpuCondJump::JA:
                store_.push_u8(0x77);
                break;
            case CpuCondJump::JS:
                emitCpuOp(store_, 0x78);
                break;
            case CpuCondJump::JP:
                emitCpuOp(store_, 0x7A);
                break;
            case CpuCondJump::JNP:
                emitCpuOp(store_, 0x7B);
                break;
            case CpuCondJump::JL:
                emitCpuOp(store_, 0x7C);
                break;
            case CpuCondJump::JGE:
                emitCpuOp(store_, 0x7D);
                break;
            case CpuCondJump::JLE:
                emitCpuOp(store_, 0x7E);
                break;
            case CpuCondJump::JG:
                emitCpuOp(store_, 0x7F);
                break;
            case CpuCondJump::JUMP:
                emitCpuOp(store_, 0xEB);
                break;
            default:
                SWC_ASSERT(false);
                break;
        }

        store_.push_u8(0);

        jump.patchOffsetAddr = store_.seek_ptr() - 1;
        jump.offsetStart     = store_.size();
        jump.opBits          = opBits;
        return CpuEncodeResult::Zero;
    }

    switch (jumpType)
    {
        case CpuCondJump::JNO:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x81);
            break;
        case CpuCondJump::JB:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x82);
            break;
        case CpuCondJump::JAE:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x83);
            break;
        case CpuCondJump::JZ:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x84);
            break;
        case CpuCondJump::JNZ:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x85);
            break;
        case CpuCondJump::JBE:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x86);
            break;
        case CpuCondJump::JA:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x87);
            break;
        case CpuCondJump::JP:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8A);
            break;
        case CpuCondJump::JS:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x88);
            break;
        case CpuCondJump::JNP:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8B);
            break;
        case CpuCondJump::JL:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8C);
            break;
        case CpuCondJump::JGE:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8D);
            break;
        case CpuCondJump::JLE:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8E);
            break;
        case CpuCondJump::JG:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8F);
            break;
        case CpuCondJump::JUMP:
            emitCpuOp(store_, 0xE9);
            break;
        default:
            SWC_ASSERT(false);
            break;
    }

    store_.push_u32(0);

    jump.patchOffsetAddr = store_.seek_ptr() - sizeof(uint32_t);
    jump.offsetStart     = store_.size();
    jump.opBits          = opBits;
    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodePatchJump(const CpuJump& jump, uint64_t offsetDestination, CpuEmitFlags emitFlags)
{
    const int32_t offset = static_cast<int32_t>(offsetDestination - jump.offsetStart);
    if (jump.opBits == OpBits::B8)
    {
        SWC_ASSERT(offset >= -127 && offset <= 128);
        *static_cast<uint8_t*>(jump.patchOffsetAddr) = static_cast<int8_t>(offset);
    }
    else
    {
        *static_cast<uint32_t*>(jump.patchOffsetAddr) = static_cast<int32_t>(offset);
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodePatchJump(const CpuJump& jump, CpuEmitFlags emitFlags)
{
    return encodePatchJump(jump, store_.size(), emitFlags);
}

CpuEncodeResult X64Encoder::encodeJumpReg(CpuReg reg, CpuEmitFlags emitFlags)
{
    emitRex(store_, OpBits::Zero, REX_REG_NONE, reg);
    emitCpuOp(store_, 0xFF);
    emitModRm(store_, ModRmMode::Register, MODRM_REG_4, encodeReg(reg));
    return CpuEncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

CpuEncodeResult X64Encoder::encodeCallExtern(const Utf8& symbolName, const CallConv* callConv, CpuEmitFlags emitFlags)
{
    emitCpuOp(store_, 0xFF);
    emitModRm(store_, ModRmMode::Memory, MODRM_REG_2, MODRM_RM_RIP);

    const auto callSym = getOrAddSymbol(symbolName, CpuSymbolKind::Extern);
    addSymbolRelocation(store_.size() - textSectionOffset_, callSym->index, IMAGE_REL_AMD64_REL32);
    store_.push_u32(0);
    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeCallLocal(const Utf8& symbolName, const CallConv* callConv, CpuEmitFlags emitFlags)
{
    emitCpuOp(store_, 0xE8);

    const auto callSym = getOrAddSymbol(symbolName, CpuSymbolKind::Extern);
    if (callSym->kind == CpuSymbolKind::Function)
    {
        store_.push_s32(static_cast<int32_t>(callSym->value + textSectionOffset_ - (store_.size() + 4)));
    }
    else
    {
        addSymbolRelocation(store_.size() - textSectionOffset_, callSym->index, IMAGE_REL_AMD64_REL32);
        store_.push_u32(0);
    }

    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeCallReg(CpuReg reg, const CallConv* callConv, CpuEmitFlags emitFlags)
{
    emitRex(store_, OpBits::Zero, REX_REG_NONE, reg);
    emitCpuOp(store_, 0xFF);
    emitModRm(store_, MODRM_REG_2, reg);
    return CpuEncodeResult::Zero;
}

CpuEncodeResult X64Encoder::encodeNop(CpuEmitFlags emitFlags)
{
    emitCpuOp(store_, 0x90);
    return CpuEncodeResult::Zero;
}

RegisterSet X64Encoder::getReadRegisters(const MicroInstruction& inst)
{
    auto result = CpuEncoder::getReadRegisters(inst);

    if (inst.op == MicroOp::OpBinaryRi ||
        inst.op == MicroOp::OpBinaryRr ||
        inst.op == MicroOp::OpBinaryMi ||
        inst.op == MicroOp::OpBinaryRm ||
        inst.op == MicroOp::OpBinaryMr)
    {
        if (inst.cpuOp == CpuOp::ROL ||
            inst.cpuOp == CpuOp::ROR ||
            inst.cpuOp == CpuOp::SAL ||
            inst.cpuOp == CpuOp::SAR ||
            inst.cpuOp == CpuOp::SHL ||
            inst.cpuOp == CpuOp::SHR)
        {
            result.add(x64Reg2CpuReg(X64Reg::Rcx));
        }
        else if (inst.cpuOp == CpuOp::MUL ||
                 inst.cpuOp == CpuOp::DIV ||
                 inst.cpuOp == CpuOp::MOD ||
                 inst.cpuOp == CpuOp::IDIV ||
                 inst.cpuOp == CpuOp::IMOD)
        {
            result.add(x64Reg2CpuReg(X64Reg::Rdx));
        }
    }

    return result;
}

RegisterSet X64Encoder::getWriteRegisters(const MicroInstruction& inst)
{
    auto result = CpuEncoder::getWriteRegisters(inst);

    if (inst.op == MicroOp::OpBinaryRi ||
        inst.op == MicroOp::OpBinaryRr ||
        inst.op == MicroOp::OpBinaryMi ||
        inst.op == MicroOp::OpBinaryRm ||
        inst.op == MicroOp::OpBinaryMr)
    {
        if (inst.cpuOp == CpuOp::MUL ||
            inst.cpuOp == CpuOp::DIV ||
            inst.cpuOp == CpuOp::MOD ||
            inst.cpuOp == CpuOp::IDIV ||
            inst.cpuOp == CpuOp::IMOD)
        {
            result.add(x64Reg2CpuReg(X64Reg::Rdx));
        }
    }

    return result;
}

SWC_END_NAMESPACE();
