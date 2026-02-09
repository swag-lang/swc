#include "pch.h"
#include "Backend/MachineCode/Encoder/X64Encoder.h"
#include "Backend/MachineCode/Micro/MicroInstruction.h"
#include "Wmf/Module.h"

SWC_BEGIN_NAMESPACE();

enum class ModRmMode : uint8_t
{
    Memory         = 0b00,
    Displacement8  = 0b01,
    Displacement32 = 0b10,
    Register       = 0b11,
};

constexpr auto REX_REG_NONE  = static_cast<Cpu::Reg>(255);
constexpr auto MODRM_REG_0   = static_cast<Cpu::Reg>(254);
constexpr auto MODRM_REG_1   = static_cast<Cpu::Reg>(253);
constexpr auto MODRM_REG_2   = static_cast<Cpu::Reg>(252);
constexpr auto MODRM_REG_3   = static_cast<Cpu::Reg>(251);
constexpr auto MODRM_REG_4   = static_cast<Cpu::Reg>(250);
constexpr auto MODRM_REG_5   = static_cast<Cpu::Reg>(249);
constexpr auto MODRM_REG_6   = static_cast<Cpu::Reg>(248);
constexpr auto MODRM_REG_7   = static_cast<Cpu::Reg>(247);
constexpr auto MODRM_REG_SIB = static_cast<Cpu::Reg>(246);

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
    Cpu::Reg x64Reg2CpuReg(X64Reg reg)
    {
        switch (reg)
        {
            case X64Reg::Rax:
                return Cpu::Reg::Rax;
            case X64Reg::Rbx:
                return Cpu::Reg::Rbx;
            case X64Reg::Rcx:
                return Cpu::Reg::Rcx;
            case X64Reg::Rdx:
                return Cpu::Reg::Rdx;
            case X64Reg::Rsp:
                return Cpu::Reg::Rsp;
            case X64Reg::Rbp:
                return Cpu::Reg::Rbp;
            case X64Reg::Rsi:
                return Cpu::Reg::Rsi;
            case X64Reg::Rdi:
                return Cpu::Reg::Rdi;
            case X64Reg::R8:
                return Cpu::Reg::R8;
            case X64Reg::R9:
                return Cpu::Reg::R9;
            case X64Reg::R10:
                return Cpu::Reg::R10;
            case X64Reg::R11:
                return Cpu::Reg::R11;
            case X64Reg::R12:
                return Cpu::Reg::R12;
            case X64Reg::R13:
                return Cpu::Reg::R13;
            case X64Reg::R14:
                return Cpu::Reg::R14;
            case X64Reg::R15:
                return Cpu::Reg::R15;
            case X64Reg::Xmm0:
                return Cpu::Reg::Xmm0;
            case X64Reg::Xmm1:
                return Cpu::Reg::Xmm1;
            case X64Reg::Xmm2:
                return Cpu::Reg::Xmm2;
            case X64Reg::Xmm3:
                return Cpu::Reg::Xmm3;
            case X64Reg::Rip:
                return Cpu::Reg::Rip;

            default:
                SWC_ASSERT(false);
                return Cpu::Reg::Rax;
        }
    }

    X64Reg cpuRegToX64Reg(Cpu::Reg reg)
    {
        switch (reg)
        {
            case Cpu::Reg::Rax:
                return X64Reg::Rax;
            case Cpu::Reg::Rbx:
                return X64Reg::Rbx;
            case Cpu::Reg::Rcx:
                return X64Reg::Rcx;
            case Cpu::Reg::Rdx:
                return X64Reg::Rdx;
            case Cpu::Reg::Rsp:
                return X64Reg::Rsp;
            case Cpu::Reg::Rbp:
                return X64Reg::Rbp;
            case Cpu::Reg::Rsi:
                return X64Reg::Rsi;
            case Cpu::Reg::Rdi:
                return X64Reg::Rdi;
            case Cpu::Reg::R8:
                return X64Reg::R8;
            case Cpu::Reg::R9:
                return X64Reg::R9;
            case Cpu::Reg::R10:
                return X64Reg::R10;
            case Cpu::Reg::R11:
                return X64Reg::R11;
            case Cpu::Reg::R12:
                return X64Reg::R12;
            case Cpu::Reg::R13:
                return X64Reg::R13;
            case Cpu::Reg::R14:
                return X64Reg::R14;
            case Cpu::Reg::R15:
                return X64Reg::R15;
            case Cpu::Reg::Xmm0:
                return X64Reg::Xmm0;
            case Cpu::Reg::Xmm1:
                return X64Reg::Xmm1;
            case Cpu::Reg::Xmm2:
                return X64Reg::Xmm2;
            case Cpu::Reg::Xmm3:
                return X64Reg::Xmm3;
            case Cpu::Reg::Rip:
                return X64Reg::Rip;
            default:
                SWC_ASSERT(false);
                return X64Reg::Rax;
        }
    }

    uint8_t encodeReg(Cpu::Reg reg)
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

    bool canEncode8(uint64_t value, Cpu::OpBits opBits)
    {
        return value <= 0x7F ||
               (opBits == Cpu::OpBits::B16 && value >= 0xFF80) ||
               (opBits == Cpu::OpBits::B32 && value >= 0xFFFFFF80) ||
               (opBits == Cpu::OpBits::B64 && value >= 0xFFFFFFFFFFFFFF80);
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

    uint8_t getModRm(ModRmMode mod, Cpu::Reg reg, uint8_t rm)
    {
        return getModRm(mod, encodeReg(reg), rm);
    }

    void emitPrefixF64(Store& store, Cpu::OpBits opBits)
    {
        if (opBits == Cpu::OpBits::B64)
            store.pushU8(0x66);
    }

    void emitSIB(Store& store, uint8_t scale, uint8_t index, uint8_t base)
    {
        const uint8_t value = static_cast<uint8_t>(scale << 6) | static_cast<uint8_t>(index << 3) | base;
        store.pushU8(value);
    }

    void emitRex(Store& store, Cpu::OpBits opBits, Cpu::Reg reg0 = REX_REG_NONE, Cpu::Reg reg1 = REX_REG_NONE)
    {
        if (opBits == Cpu::OpBits::B16)
            store.pushU8(0x66);

        const bool b1 = (reg0 >= Cpu::Reg::R8 && reg0 <= Cpu::Reg::R15);
        const bool b2 = (reg1 >= Cpu::Reg::R8 && reg1 <= Cpu::Reg::R15);
        if (opBits == Cpu::OpBits::B64 ||
            b1 || b2 ||
            reg0 == Cpu::Reg::Rsi || reg1 == Cpu::Reg::Rsi ||
            reg0 == Cpu::Reg::Rdi || reg1 == Cpu::Reg::Rdi ||
            reg0 == Cpu::Reg::Rsp || reg1 == Cpu::Reg::Rsp ||
            reg0 == Cpu::Reg::Rbp || reg1 == Cpu::Reg::Rbp)
        {
            const auto value = getRex(opBits == Cpu::OpBits::B64, b1, false, b2);
            store.pushU8(value);
        }
    }

    void emitValue(Store& store, uint64_t value, Cpu::OpBits opBits)
    {
        if (opBits == Cpu::OpBits::B8)
            store.pushU8(static_cast<uint8_t>(value));
        else if (opBits == Cpu::OpBits::B16)
            store.pushU16(static_cast<uint16_t>(value));
        else if (opBits == Cpu::OpBits::B32)
            store.pushU32(static_cast<uint32_t>(value));
        else
            store.pushU64(value);
    }

    void emitModRm(Store& store, ModRmMode mod, Cpu::Reg reg, uint8_t rm)
    {
        const auto value = getModRm(mod, reg, rm);
        store.pushU8(value);
    }

    void emitModRm(Store& store, Cpu::Reg reg, Cpu::Reg memReg)
    {
        emitModRm(store, ModRmMode::Register, reg, encodeReg(memReg));
    }

    void emitModRm(Store& store, uint64_t memOffset, Cpu::Reg reg, Cpu::Reg memReg)
    {
        if (memOffset == 0 && memReg != Cpu::Reg::R13 && memReg != Cpu::Reg::Rbp)
        {
            if (memReg == Cpu::Reg::Rsp || memReg == Cpu::Reg::R12)
            {
                const auto modRm = getModRm(ModRmMode::Memory, reg, MODRM_RM_SIB);
                store.pushU8(modRm);
                emitSIB(store, 0, MODRM_RM_SIB, encodeReg(memReg) & 0b111);
            }
            else
            {
                const auto modRm = getModRm(ModRmMode::Memory, reg, encodeReg(memReg));
                store.pushU8(modRm);
            }
        }
        else if (memOffset <= 0x7F)
        {
            if (memReg == Cpu::Reg::Rsp || memReg == Cpu::Reg::R12)
            {
                const auto modRm = getModRm(ModRmMode::Displacement8, reg, MODRM_RM_SIB);
                store.pushU8(modRm);
                emitSIB(store, 0, MODRM_RM_SIB, encodeReg(memReg) & 0b111);
            }
            else
            {
                const auto modRm = getModRm(ModRmMode::Displacement8, reg, encodeReg(memReg));
                store.pushU8(modRm);
            }

            emitValue(store, memOffset, Cpu::OpBits::B8);
        }
        else
        {
            if (memReg == Cpu::Reg::Rsp || memReg == Cpu::Reg::R12)
            {
                const auto modRm = getModRm(ModRmMode::Displacement32, reg, MODRM_RM_SIB);
                store.pushU8(modRm);
                emitSIB(store, 0, MODRM_RM_SIB, encodeReg(memReg) & 0b111);
            }
            else
            {
                const auto modRm = getModRm(ModRmMode::Displacement32, reg, encodeReg(memReg));
                store.pushU8(modRm);
            }

            SWC_ASSERT(memOffset <= 0x7FFFFFFF);
            emitValue(store, memOffset, Cpu::OpBits::B32);
        }
    }

    void emitSpecB8(Store& store, uint8_t value, Cpu::OpBits opBits)
    {
        if (opBits == Cpu::OpBits::B8)
            store.pushU8(value & ~1);
        else
            store.pushU8(value);
    }

    void emitSpecF64(Store& store, uint8_t value, Cpu::OpBits opBits)
    {
        if (opBits == Cpu::OpBits::B64)
            store.pushU8(value & ~1);
        else if (opBits == Cpu::OpBits::B32)
            store.pushU8(value);
    }

    void emitCpuOp(Store& store, Cpu::Op op)
    {
        store.pushU8(static_cast<uint8_t>(op));
    }

    void emitCpuOp(Store& store, uint8_t op)
    {
        store.pushU8(op);
    }

    void emitCpuOp(Store& store, uint8_t op, Cpu::Reg reg)
    {
        store.pushU8(op | (encodeReg(reg) & 0b111));
    }

    void emitSpecCpuOp(Store& store, Cpu::Op op, Cpu::OpBits opBits)
    {
        emitSpecB8(store, static_cast<uint8_t>(op), opBits);
    }

    void emitSpecCpuOp(Store& store, uint8_t op, Cpu::OpBits opBits)
    {
        emitSpecB8(store, op, opBits);
    }
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeLoadSymbolRelocAddress(Cpu::Reg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags)
{
    emitRex(store_, Cpu::OpBits::B64, reg);
    emitCpuOp(store_, 0x8D); // LEA
    emitModRm(store_, ModRmMode::Memory, reg, MODRM_RM_RIP);
    addSymbolRelocation(store_.size() - textSectionOffset_, symbolIndex, IMAGE_REL_AMD64_REL32);
    store_.pushU32(offset);
    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeLoadSymRelocValue(Cpu::Reg reg, uint32_t symbolIndex, uint32_t offset, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    if (Cpu::isFloat(reg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitSpecF64(store_, 0xF3, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x10);
        emitModRm(store_, ModRmMode::Memory, reg, MODRM_RM_RIP);
        addSymbolRelocation(store_.size() - textSectionOffset_, symbolIndex, IMAGE_REL_AMD64_REL32);
        store_.pushU32(offset);
    }
    else if (emitFlags.has(EMIT_B64))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        SWC_ASSERT(opBits == Cpu::OpBits::B64);
        emitRex(store_, opBits, REX_REG_NONE, reg);
        emitCpuOp(store_, 0xB8, reg); // MOV
        addSymbolRelocation(store_.size() - textSectionOffset_, symbolIndex, IMAGE_REL_AMD64_ADDR64);
        store_.pushU64(offset);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        SWC_ASSERT(opBits == Cpu::OpBits::B64);
        emitRex(store_, opBits, reg);
        emitCpuOp(store_, 0x8B); // MOV
        emitModRm(store_, ModRmMode::Memory, reg, MODRM_RM_RIP);
        addSymbolRelocation(store_.size() - textSectionOffset_, symbolIndex, IMAGE_REL_AMD64_REL32);
        store_.pushU32(offset);
    }

    return EncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodePush(Cpu::Reg reg, EmitFlags emitFlags)
{
    emitRex(store_, Cpu::OpBits::Zero, REX_REG_NONE, reg);
    emitCpuOp(store_, 0x50, reg);
    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodePop(Cpu::Reg reg, EmitFlags emitFlags)
{
    emitRex(store_, Cpu::OpBits::Zero, REX_REG_NONE, reg);
    emitCpuOp(store_, 0x58, reg);
    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeRet(EmitFlags emitFlags)
{
    emitCpuOp(store_, 0xC3);
    return EncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeLoadRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    if (Cpu::isFloat(regDst) && Cpu::isFloat(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitSpecF64(store_, 0xF3, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x10);
        emitModRm(store_, regDst, regSrc);
    }
    else if (Cpu::isFloat(regDst))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitPrefixF64(store_, Cpu::OpBits::B64);
        emitRex(store_, opBits, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x6E);
        emitModRm(store_, regDst, regSrc);
    }
    else if (Cpu::isFloat(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitPrefixF64(store_, Cpu::OpBits::B64);
        emitRex(store_, opBits, regSrc, regDst);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x7E);
        emitModRm(store_, regSrc, regDst);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regSrc, regDst);
        emitSpecCpuOp(store_, 0x89, opBits);
        emitModRm(store_, regSrc, regDst);
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeLoadRegImm(Cpu::Reg reg, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    if (Cpu::isFloat(reg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Right2Cst;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (opBits == Cpu::OpBits::B8)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, reg);
        emitCpuOp(store_, 0xB0, reg);
        emitValue(store_, value, opBits);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, reg);
        emitCpuOp(store_, 0xB8, reg);
        emitValue(store_, value, opBits);
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeLoadRegMem(Cpu::Reg reg, Cpu::Reg memReg, uint64_t memOffset, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    if (Cpu::isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (Cpu::isFloat(reg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, Cpu::OpBits::Zero, reg, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x10);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, reg, memReg);
        emitSpecCpuOp(store_, 0x8B, opBits);
        emitModRm(store_, memOffset, reg, memReg);
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeLoadZeroExtendRegMem(Cpu::Reg reg, Cpu::Reg memReg, uint64_t memOffset, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);

    if (Cpu::isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (numBitsSrc == Cpu::OpBits::B8 && (numBitsDst == Cpu::OpBits::B32 || numBitsDst == Cpu::OpBits::B64))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, reg, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB6);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else if (numBitsSrc == Cpu::OpBits::B16 && (numBitsDst == Cpu::OpBits::B32 || numBitsDst == Cpu::OpBits::B64))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, reg, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB7);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else if (numBitsSrc == Cpu::OpBits::B32 && numBitsDst == Cpu::OpBits::B64)
    {
        return encodeLoadRegMem(reg, memReg, memOffset, numBitsSrc, emitFlags);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeLoadZeroExtendRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);

    if (Cpu::isFloat(regDst) || Cpu::isFloat(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (numBitsSrc == Cpu::OpBits::B8 && (numBitsDst == Cpu::OpBits::B32 || numBitsDst == Cpu::OpBits::B64))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB6);
        emitModRm(store_, regDst, regSrc);
    }
    else if (numBitsSrc == Cpu::OpBits::B16 && (numBitsDst == Cpu::OpBits::B32 || numBitsDst == Cpu::OpBits::B64))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, Cpu::OpBits::B64, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB7);
        emitModRm(store_, regDst, regSrc);
    }
    else if (numBitsSrc == Cpu::OpBits::B32 && numBitsDst == Cpu::OpBits::B64)
    {
        return encodeLoadRegReg(regDst, regSrc, numBitsSrc, emitFlags);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeLoadSignedExtendRegMem(Cpu::Reg reg, Cpu::Reg memReg, uint64_t memOffset, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);

    if (Cpu::isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (numBitsSrc == Cpu::OpBits::B8)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, reg, memReg);
        store_.pushU8(0x0F);
        store_.pushU8(0xBE);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else if (numBitsSrc == Cpu::OpBits::B16)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, reg, memReg);
        store_.pushU8(0x0F);
        store_.pushU8(0xBF);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else if (numBitsSrc == Cpu::OpBits::B32)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        SWC_ASSERT(numBitsDst == Cpu::OpBits::B64);
        emitRex(store_, Cpu::OpBits::B64, reg, memReg);
        emitCpuOp(store_, 0x63);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeLoadSignedExtendRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::OpBits numBitsDst, Cpu::OpBits numBitsSrc, EmitFlags emitFlags)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);

    if (Cpu::isFloat(regDst) || Cpu::isFloat(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (numBitsSrc == Cpu::OpBits::B8)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xBE);
        emitModRm(store_, regDst, regSrc);
    }
    else if (numBitsSrc == Cpu::OpBits::B16)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xBF);
        emitModRm(store_, regDst, regSrc);
    }
    else if (numBitsSrc == Cpu::OpBits::B32 && numBitsDst == Cpu::OpBits::B64)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, regDst, regSrc);
        emitCpuOp(store_, 0x63);
        emitModRm(store_, regDst, regSrc);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeLoadAddressRegMem(Cpu::Reg reg, Cpu::Reg memReg, uint64_t memOffset, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    if (emitFlags.has(EMIT_CAN_ENCODE))
    {
        if (opBits != Cpu::OpBits::B64)
            return EncodeResult::NotSupported;
    }

    if (Cpu::isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memReg == Cpu::Reg::Rip)
    {
        SWC_ASSERT(memOffset == 0);
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, Cpu::OpBits::B64, reg, memReg);
        emitCpuOp(store_, 0x8D);
        emitModRm(store_, ModRmMode::Memory, reg, MODRM_RM_RIP);
    }
    else if (memOffset == 0)
    {
        emitLoadRegReg(reg, memReg, Cpu::OpBits::B64);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, Cpu::OpBits::B64, reg, memReg);
        emitCpuOp(store_, 0x8D);
        emitModRm(store_, memOffset, reg, memReg);
    }

    return EncodeResult::Zero;
}

namespace
{
    EncodeResult encodeAmcImm(Store& store, Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsBaseMul, uint64_t value, Cpu::OpBits opBitsValue, EmitFlags emitFlags)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (mulValue != 1 && mulValue != 2 && mulValue != 4 && mulValue != 8)
                return EncodeResult::NotSupported;
            if (opBitsBaseMul != Cpu::OpBits::B32 && opBitsBaseMul != Cpu::OpBits::B64)
                return EncodeResult::NotSupported;
            if (addValue > 0x7FFFFFFF)
                return EncodeResult::NotSupported;
            if (value > 0x7FFFFFFF)
                return EncodeResult::NotSupported;
            if (Cpu::isFloat(regBase) || Cpu::isFloat(regMul))
                return EncodeResult::NotSupported;
            if (opBitsBaseMul != Cpu::OpBits::B64 && (regBase == Cpu::Reg::Rsp || regMul == Cpu::Reg::Rsp))
                return EncodeResult::NotSupported;
            if (regMul == Cpu::Reg::Rsp && mulValue != 1)
                return EncodeResult::NotSupported;
            return EncodeResult::Zero;
        }

        if (regMul == Cpu::Reg::Rsp)
        {
            SWC_ASSERT(mulValue == 1);
            std::swap(regMul, regBase);
        }

        // Prefixes
        if (opBitsValue == Cpu::OpBits::B16)
            store.pushU8(0x66);

        // REX prefix
        const bool b1 = (regMul >= Cpu::Reg::R8 && regMul <= Cpu::Reg::R15);
        const bool b2 = (regBase >= Cpu::Reg::R8 && regBase <= Cpu::Reg::R15);
        if (opBitsValue == Cpu::OpBits::B64 || b1 || b2)
        {
            const auto val = getRex(opBitsValue == Cpu::OpBits::B64, false, b1, b2);
            store.pushU8(val);
        }

        // OpCode
        emitSpecCpuOp(store, 0xC7, opBitsValue);

        // ModRM
        if (regBase == Cpu::Reg::R13)
            emitModRm(store, addValue <= 0x7F ? ModRmMode::Displacement8 : ModRmMode::Displacement32, MODRM_REG_0, MODRM_RM_SIB);
        else if (addValue == 0 || regBase == Cpu::Reg::Max)
            emitModRm(store, ModRmMode::Memory, MODRM_REG_0, MODRM_RM_SIB);
        else
            emitModRm(store, addValue <= 0x7F ? ModRmMode::Displacement8 : ModRmMode::Displacement32, MODRM_REG_0, MODRM_RM_SIB);

        // SIB
        SWC_ASSERT(mulValue == 1 || mulValue == 2 || mulValue == 4 || mulValue == 8);
        const auto scale = static_cast<uint8_t>(log2(mulValue));
        if (regBase == Cpu::Reg::Max)
        {
            emitSIB(store, scale, encodeReg(regMul) & 0b111, SIB_NO_BASE);
            emitValue(store, addValue, Cpu::OpBits::B32);
        }
        else
        {
            emitSIB(store, scale, encodeReg(regMul) & 0b111, encodeReg(regBase) & 0b111);
            if (regBase == Cpu::Reg::R13 || addValue != 0)
                emitValue(store, addValue, addValue <= 0x7F ? Cpu::OpBits::B8 : Cpu::OpBits::B32);
        }

        // Value
        emitValue(store, value, std::min(opBitsValue, Cpu::OpBits::B32));
        return EncodeResult::Zero;
    }

    EncodeResult encodeAmcReg(Store& store, Cpu::Reg reg, Cpu::OpBits opBitsReg, Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsBaseMul, Cpu::Op op, EmitFlags emitFlags, bool mr)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (mulValue != 1 && mulValue != 2 && mulValue != 4 && mulValue != 8)
                return EncodeResult::NotSupported;
            if (op == Cpu::Op::LEA && opBitsReg == Cpu::OpBits::B8)
                return EncodeResult::NotSupported;
            if (opBitsBaseMul != Cpu::OpBits::B32 && opBitsBaseMul != Cpu::OpBits::B64)
                return EncodeResult::NotSupported;
            if (addValue > 0x7FFFFFFF)
                return EncodeResult::NotSupported;
            if (Cpu::isFloat(regBase) || Cpu::isFloat(regMul))
                return EncodeResult::NotSupported;
            if (Cpu::isFloat(reg) && op == Cpu::Op::LEA)
                return EncodeResult::NotSupported;
            if (Cpu::isFloat(reg) && op == Cpu::Op::MOVSXD)
                return EncodeResult::NotSupported;
            if (Cpu::isFloat(reg) && opBitsReg != Cpu::OpBits::B32 && opBitsReg != Cpu::OpBits::B64)
                return EncodeResult::NotSupported;
            if (opBitsBaseMul != Cpu::OpBits::B64 && (regBase == Cpu::Reg::Rsp || regMul == Cpu::Reg::Rsp))
                return EncodeResult::NotSupported;
            if (regMul == Cpu::Reg::Rsp && mulValue != 1)
                return EncodeResult::NotSupported;
            return EncodeResult::Zero;
        }

        if (regMul == Cpu::Reg::Rsp)
        {
            SWC_ASSERT(mulValue == 1);
            std::swap(regMul, regBase);
        }

        // Prefixes
        if (opBitsBaseMul == Cpu::OpBits::B32)
            store.pushU8(0x67);
        if (opBitsReg == Cpu::OpBits::B16 || Cpu::isFloat(reg))
            store.pushU8(0x66);

        // REX prefix
        const bool b0      = (reg >= Cpu::Reg::R8 && reg <= Cpu::Reg::R15);
        const bool b1      = (regMul >= Cpu::Reg::R8 && regMul <= Cpu::Reg::R15);
        const bool b2      = (regBase >= Cpu::Reg::R8 && regBase <= Cpu::Reg::R15);
        const bool needRex = opBitsReg == Cpu::OpBits::B64 || reg == Cpu::Reg::Rsi || reg == Cpu::Reg::Rdi || reg == Cpu::Reg::Rsp || reg == Cpu::Reg::Rbp;
        if (needRex || b0 || b1 || b2)
        {
            const auto value = getRex(opBitsReg == Cpu::OpBits::B64, b0, b1, b2);
            store.pushU8(value);
        }

        // Opcode
        switch (op)
        {
            case Cpu::Op::LEA:
                emitSpecCpuOp(store, 0x8D, opBitsReg);
                break;
            case Cpu::Op::MOVSXD:
                emitSpecCpuOp(store, 0x63, opBitsReg);
                break;
            case Cpu::Op::MOV:
                if (Cpu::isFloat(reg))
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
        if (regBase == Cpu::Reg::R13)
            emitModRm(store, addValue <= 0x7F ? ModRmMode::Displacement8 : ModRmMode::Displacement32, reg, MODRM_RM_SIB);
        else if (addValue == 0 || regBase == Cpu::Reg::Max)
            emitModRm(store, ModRmMode::Memory, reg, MODRM_RM_SIB);
        else
            emitModRm(store, addValue <= 0x7F ? ModRmMode::Displacement8 : ModRmMode::Displacement32, reg, MODRM_RM_SIB);

        // SIB
        SWC_ASSERT(mulValue == 1 || mulValue == 2 || mulValue == 4 || mulValue == 8);
        const auto scale = static_cast<uint8_t>(log2(mulValue));
        if (regBase == Cpu::Reg::Max)
        {
            emitSIB(store, scale, encodeReg(regMul) & 0b111, SIB_NO_BASE);
            emitValue(store, addValue, Cpu::OpBits::B32);
        }
        else
        {
            emitSIB(store, scale, encodeReg(regMul) & 0b111, encodeReg(regBase) & 0b111);
            if (regBase == Cpu::Reg::R13 || addValue != 0)
                emitValue(store, addValue, addValue <= 0x7F ? Cpu::OpBits::B8 : Cpu::OpBits::B32);
        }

        return EncodeResult::Zero;
    }
}

EncodeResult X64Encoder::encodeLoadAmcRegMem(Cpu::Reg regDst, Cpu::OpBits opBitsDst, Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsSrc, EmitFlags emitFlags)
{
    return encodeAmcReg(store_, regDst, opBitsDst, regBase, regMul, mulValue, addValue, opBitsSrc, Cpu::Op::MOV, emitFlags, false);
}

EncodeResult X64Encoder::encodeLoadAmcMemReg(Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsBaseMul, Cpu::Reg regSrc, Cpu::OpBits opBitsSrc, EmitFlags emitFlags)
{
    return encodeAmcReg(store_, regSrc, opBitsSrc, regBase, regMul, mulValue, addValue, opBitsBaseMul, Cpu::Op::MOV, emitFlags, true);
}

EncodeResult X64Encoder::encodeLoadAmcMemImm(Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsBaseMul, uint64_t value, Cpu::OpBits opBitsValue, EmitFlags emitFlags)
{
    return encodeAmcImm(store_, regBase, regMul, mulValue, addValue, opBitsBaseMul, value, opBitsValue, emitFlags);
}

EncodeResult X64Encoder::encodeLoadAddressAmcRegMem(Cpu::Reg regDst, Cpu::OpBits opBitsDst, Cpu::Reg regBase, Cpu::Reg regMul, uint64_t mulValue, uint64_t addValue, Cpu::OpBits opBitsValue, EmitFlags emitFlags)
{
    return encodeAmcReg(store_, regDst, opBitsDst, regBase, regMul, mulValue, addValue, opBitsValue, Cpu::Op::LEA, emitFlags, false);
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeLoadMemReg(Cpu::Reg memReg, uint64_t memOffset, Cpu::Reg reg, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    if (Cpu::isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (Cpu::isFloat(reg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, Cpu::OpBits::Zero, reg, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x11);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, reg, memReg);
        emitSpecCpuOp(store_, 0x89, opBits);
        emitModRm(store_, memOffset, reg, memReg);
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeLoadMemImm(Cpu::Reg memReg, uint64_t memOffset, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    if (Cpu::isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (opBits == Cpu::OpBits::B128)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Right2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (opBits == Cpu::OpBits::B64 && value > 0x7FFFFFFF && value >> 32 != 0xFFFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Right2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (emitFlags.has(EMIT_CAN_ENCODE))
        return EncodeResult::Zero;
    emitRex(store_, opBits, REX_REG_NONE, memReg);
    emitSpecB8(store_, 0xC7, opBits);
    emitModRm(store_, memOffset, MODRM_REG_0, memReg);
    emitValue(store_, value, std::min(opBits, Cpu::OpBits::B32));

    return EncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeClearReg(Cpu::Reg reg, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    if (emitFlags.has(EMIT_CAN_ENCODE))
        return EncodeResult::Zero;

    if (Cpu::isFloat(reg))
    {
        emitPrefixF64(store_, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, Cpu::Op::FXOR);
        emitModRm(store_, reg, reg);
    }
    else
    {
        emitRex(store_, opBits, reg, reg);
        emitSpecCpuOp(store_, Cpu::Op::XOR, opBits);
        emitModRm(store_, reg, reg);
    }

    return EncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeSetCondReg(Cpu::Reg reg, Cpu::Cond cpuCond, EmitFlags emitFlags)
{
    if (emitFlags.has(EMIT_CAN_ENCODE))
        return EncodeResult::Zero;

    emitRex(store_, Cpu::OpBits::B8, REX_REG_NONE, reg);
    emitCpuOp(store_, 0x0F);

    switch (cpuCond)
    {
        case Cpu::Cond::A:
            emitCpuOp(store_, 0x97);
            break;
        case Cpu::Cond::O:
            emitCpuOp(store_, 0x90);
            break;
        case Cpu::Cond::AE:
            emitCpuOp(store_, 0x93);
            break;
        case Cpu::Cond::G:
            emitCpuOp(store_, 0x9F);
            break;
        case Cpu::Cond::NE:
            emitCpuOp(store_, 0x95);
            break;
        case Cpu::Cond::NA:
            emitCpuOp(store_, 0x96);
            break;
        case Cpu::Cond::B:
            emitCpuOp(store_, 0x92);
            break;
        case Cpu::Cond::BE:
            emitCpuOp(store_, 0x96);
            break;
        case Cpu::Cond::E:
            emitCpuOp(store_, 0x94);
            break;
        case Cpu::Cond::GE:
            emitCpuOp(store_, 0x9D);
            break;
        case Cpu::Cond::L:
            emitCpuOp(store_, 0x9C);
            break;
        case Cpu::Cond::LE:
            emitCpuOp(store_, 0x9E);
            break;
        case Cpu::Cond::P:
            emitCpuOp(store_, 0x9A);
            break;
        case Cpu::Cond::NP:
            emitCpuOp(store_, 0x9B);
            break;
        default:
            SWC_ASSERT(false);
            break;
    }

    emitModRm(store_, MODRM_REG_0, reg);
    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeLoadCondRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::Cond setType, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    if (emitFlags.has(EMIT_CAN_ENCODE))
        return EncodeResult::Zero;

    opBits = std::max(opBits, Cpu::OpBits::B32);
    emitRex(store_, opBits, regDst, regSrc);
    emitCpuOp(store_, 0x0F);

    switch (setType)
    {
        case Cpu::Cond::B:
            emitCpuOp(store_, 0x42);
            break;
        case Cpu::Cond::E:
            emitCpuOp(store_, 0x44);
            break;
        case Cpu::Cond::G:
            emitCpuOp(store_, 0x4F);
            break;
        case Cpu::Cond::L:
            emitCpuOp(store_, 0x4C);
            break;
        case Cpu::Cond::BE:
            emitCpuOp(store_, 0x46);
            break;
        case Cpu::Cond::GE:
            emitCpuOp(store_, 0x4D);
            break;
        default:
            SWC_ASSERT(false);
            break;
    }

    emitModRm(store_, regDst, regSrc);
    return EncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeCmpRegReg(Cpu::Reg reg0, Cpu::Reg reg1, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    if (Cpu::isFloat(reg0))
    {
        if (Cpu::isInt(reg1))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }

        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitPrefixF64(store_, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x2F);
        emitModRm(store_, reg0, reg1);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (Cpu::isFloat(reg1))
                return EncodeResult::NotSupported;
            return EncodeResult::Zero;
        }

        emitRex(store_, opBits, reg1, reg0);
        emitSpecCpuOp(store_, 0x39, opBits);
        emitModRm(store_, reg1, reg0);
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeCmpRegImm(Cpu::Reg reg, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    if (Cpu::isFloat(reg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (opBits == Cpu::OpBits::B8)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, reg);
        emitCpuOp(store_, 0x80);
        emitModRm(store_, MODRM_REG_7, reg);
        emitValue(store_, value, Cpu::OpBits::B8);
    }
    else if (canEncode8(value, opBits))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, reg);
        emitCpuOp(store_, 0x83);
        emitModRm(store_, MODRM_REG_7, reg);
        emitValue(store_, value, Cpu::OpBits::B8);
    }
    else if ((opBits != Cpu::OpBits::B64 || value <= 0x7FFFFFFF))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, reg);
        emitCpuOp(store_, 0x81);
        emitModRm(store_, MODRM_REG_7, reg);
        emitValue(store_, value, std::min(opBits, Cpu::OpBits::B32));
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Right2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeCmpMemReg(Cpu::Reg memReg, uint64_t memOffset, Cpu::Reg reg, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    if (Cpu::isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (Cpu::isFloat(reg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Left2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (emitFlags.has(EMIT_CAN_ENCODE))
        return EncodeResult::Zero;
    emitRex(store_, opBits, reg, memReg);
    emitSpecCpuOp(store_, 0x39, opBits);
    emitModRm(store_, memOffset, reg, memReg);

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeCmpMemImm(Cpu::Reg memReg, uint64_t memOffset, uint64_t value, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    if (Cpu::isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (opBits == Cpu::OpBits::B8)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, memReg);
        emitCpuOp(store_, 0x80);
        emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        emitValue(store_, value, Cpu::OpBits::B8);
    }
    else if (canEncode8(value, opBits))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, memReg);
        emitCpuOp(store_, 0x83);
        emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        emitValue(store_, value, Cpu::OpBits::B8);
    }
    else if (value <= 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, memReg);
        emitCpuOp(store_, 0x81);
        emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        emitValue(store_, value, opBits == Cpu::OpBits::B16 ? opBits : Cpu::OpBits::B32);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Right2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeOpUnaryMem(Cpu::Reg memReg, uint64_t memOffset, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    if (Cpu::isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////
    if (op == Cpu::Op::NOT)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits);
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, memOffset, MODRM_REG_2, memReg);
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::NEG)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits);
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, memOffset, MODRM_REG_3, memReg);
    }

    ///////////////////////////////////////////

    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeOpUnaryReg(Cpu::Reg reg, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    if (emitFlags.has(EMIT_CAN_ENCODE))
    {
        if (Cpu::isFloat(reg))
            return EncodeResult::NotSupported;
        return EncodeResult::Zero;
    }

    ///////////////////////////////////////////

    if (op == Cpu::Op::NOT)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, reg);
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, MODRM_REG_2, reg);
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::NEG)
    {
        if (Cpu::isFloat(reg))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::NotSupported;
            SWC_INTERNAL_ERROR(ctx());
        }

        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, reg);
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, MODRM_REG_3, reg);
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::BSWAP)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        if (opBits == Cpu::OpBits::B16)
        {
            // rol ax, 0x8
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0xC1);
            emitCpuOp(store_, 0xC0);
            emitValue(store_, 0x08, Cpu::OpBits::B8);
        }
        else
        {
            SWC_ASSERT(opBits == Cpu::OpBits::B16 || opBits == Cpu::OpBits::B32 || opBits == Cpu::OpBits::B64);
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0xC8, reg);
        }
    }

    ///////////////////////////////////////////

    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeOpBinaryRegMem(Cpu::Reg regDst, Cpu::Reg memReg, uint64_t memOffset, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    if (Cpu::isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////
    if (op == Cpu::Op::ADD)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x03, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::SUB)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x2B, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::AND)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x23, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::OR)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x0B, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::XOR)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x33, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::IMUL)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        if (opBits == Cpu::OpBits::B8)
            emitLoadSignedExtendRegReg(regDst, regDst, Cpu::OpBits::B32, opBits);
        emitRex(store_, opBits, regDst, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xAF);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Right2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeOpBinaryRegReg(Cpu::Reg regDst, Cpu::Reg regSrc, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    ///////////////////////////////////////////

    if (op == Cpu::Op::CVTU2F64)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////
    if (Cpu::isFloat(regDst) && Cpu::isInt(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (op != Cpu::Op::CVTI2F && op != Cpu::Op::CVTU2F64)
                return EncodeResult::NotSupported;
            return EncodeResult::Zero;
        }

        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, emitFlags.has(EMIT_B64) ? Cpu::OpBits::B64 : Cpu::OpBits::B32, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, op);
        emitModRm(store_, regDst, regSrc);
    }

    else if (Cpu::isInt(regDst) && Cpu::isFloat(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (op != Cpu::Op::CVTF2I)
                return EncodeResult::NotSupported;
            return EncodeResult::Zero;
        }

        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, emitFlags.has(EMIT_B64) ? Cpu::OpBits::B64 : Cpu::OpBits::B32, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, op);
        emitModRm(store_, regDst, regSrc);
    }

    else if (Cpu::isFloat(regDst) && Cpu::isFloat(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;

        if (op != Cpu::Op::FSQRT && op != Cpu::Op::FAND && op != Cpu::Op::FXOR)
        {
            emitSpecF64(store_, 0xF3, opBits);
            emitRex(store_, emitFlags.has(EMIT_B64) ? Cpu::OpBits::B64 : Cpu::OpBits::B32, regDst, regSrc);
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

    else if (op == Cpu::Op::DIV ||
             op == Cpu::Op::IDIV ||
             op == Cpu::Op::MOD ||
             op == Cpu::Op::IMOD)
    {
        const auto rax = x64Reg2CpuReg(X64Reg::Rax);
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (cpuRegToX64Reg(regDst) != X64Reg::Rax)
                return EncodeResult::Left2Rax;
            if (cpuRegToX64Reg(regSrc) == X64Reg::Rax)
                return EncodeResult::NotSupported;
            if (cpuRegToX64Reg(regSrc) == X64Reg::Rdx)
                return EncodeResult::NotSupported;

            return EncodeResult::Zero;
        }

        if ((op == Cpu::Op::IDIV || op == Cpu::Op::IMOD) && opBits == Cpu::OpBits::B8)
            emitLoadSignedExtendRegReg(rax, rax, Cpu::OpBits::B32, Cpu::OpBits::B8);
        else if (opBits == Cpu::OpBits::B8)
            emitLoadZeroExtendRegReg(rax, rax, Cpu::OpBits::B32, Cpu::OpBits::B8);
        else if (op == Cpu::Op::DIV || op == Cpu::Op::MOD)
            emitClearReg(x64Reg2CpuReg(X64Reg::Rdx), opBits);
        else
        {
            emitRex(store_, opBits);
            emitCpuOp(store_, 0x99); // cdq
        }

        emitRex(store_, opBits, rax, regSrc);
        emitSpecCpuOp(store_, 0xF7, opBits);
        if (op == Cpu::Op::DIV || op == Cpu::Op::MOD)
            emitModRm(store_, MODRM_REG_6, regSrc);
        else if (op == Cpu::Op::IDIV || op == Cpu::Op::IMOD)
            emitModRm(store_, MODRM_REG_7, regSrc);

        if ((op == Cpu::Op::MOD || op == Cpu::Op::IMOD) && opBits == Cpu::OpBits::B8)
            emitOpBinaryRegImm(rax, 8, Cpu::Op::SHR, Cpu::OpBits::B32, emitFlags); // AH => AL
        else if (op == Cpu::Op::MOD || op == Cpu::Op::IMOD)
            emitLoadRegReg(rax, x64Reg2CpuReg(X64Reg::Rdx), opBits);
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::MUL)
    {
        const auto rax = x64Reg2CpuReg(X64Reg::Rax);
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (cpuRegToX64Reg(regDst) != X64Reg::Rax)
                return EncodeResult::Left2Rax;
            if (cpuRegToX64Reg(regSrc) == X64Reg::Rax)
                return EncodeResult::NotSupported;
            if (cpuRegToX64Reg(regSrc) == X64Reg::Rdx)
                return EncodeResult::NotSupported;

            return EncodeResult::Zero;
        }

        emitRex(store_, opBits, rax, regSrc);
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, MODRM_REG_4, regSrc);
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::IMUL)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;

        if (opBits == Cpu::OpBits::B8)
        {
            emitLoadSignedExtendRegReg(regDst, regDst, Cpu::OpBits::B32, opBits);
            emitLoadSignedExtendRegReg(regSrc, regSrc, Cpu::OpBits::B32, opBits);
        }

        emitRex(store_, opBits, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xAF);
        emitModRm(store_, regDst, regSrc);
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::ROL ||
             op == Cpu::Op::ROR ||
             op == Cpu::Op::SAL ||
             op == Cpu::Op::SAR ||
             op == Cpu::Op::SHL ||
             op == Cpu::Op::SHR)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (cpuRegToX64Reg(regSrc) != X64Reg::Rcx)
            {
                SWC_ASSERT(x64Reg2CpuReg(X64Reg::Rcx) == Cpu::Reg::Rcx);
                return EncodeResult::Right2Rcx;
            }

            return EncodeResult::Zero;
        }

        SWC_ASSERT(cpuRegToX64Reg(regSrc) == X64Reg::Rcx);
        emitRex(store_, opBits, REX_REG_NONE, regDst);
        emitSpecCpuOp(store_, 0xD3, opBits);
        if (op == Cpu::Op::ROL)
            emitModRm(store_, MODRM_REG_0, regDst);
        else if (op == Cpu::Op::ROR)
            emitModRm(store_, MODRM_REG_1, regDst);
        else if (op == Cpu::Op::SAL || op == Cpu::Op::SHL)
            emitModRm(store_, MODRM_REG_4, regDst);
        else if (op == Cpu::Op::SAR)
            emitModRm(store_, MODRM_REG_7, regDst);
        else if (op == Cpu::Op::SHR)
            emitModRm(store_, MODRM_REG_5, regDst);
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::ADD ||
             op == Cpu::Op::SUB ||
             op == Cpu::Op::XOR ||
             op == Cpu::Op::AND ||
             op == Cpu::Op::OR)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regSrc, regDst);
        emitSpecCpuOp(store_, op, opBits);
        emitModRm(store_, regSrc, regDst);
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::XCHG)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regSrc, regDst);
        emitSpecCpuOp(store_, 0x87, opBits);
        emitModRm(store_, regSrc, regDst);
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::BSF || op == Cpu::Op::BSR)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (opBits == Cpu::OpBits::B8)
                return EncodeResult::ForceZero32;
            return EncodeResult::Zero;
        }

        emitRex(store_, opBits, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, op == Cpu::Op::BSF ? 0xBC : 0xBD);
        emitModRm(store_, regDst, regSrc);
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::POPCNT)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (opBits == Cpu::OpBits::B8)
                return EncodeResult::ForceZero32;
            return EncodeResult::Zero;
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
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeOpBinaryMemReg(Cpu::Reg memReg, uint64_t memOffset, Cpu::Reg reg, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    if (Cpu::isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////

    if (Cpu::isFloat(reg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Left2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////
    if (op == Cpu::Op::DIV ||
        op == Cpu::Op::IDIV ||
        op == Cpu::Op::MOD ||
        op == Cpu::Op::IMOD ||
        op == Cpu::Op::IMUL ||
        op == Cpu::Op::MUL)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Left2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::SAR ||
             op == Cpu::Op::SHR ||
             op == Cpu::Op::SHL)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (cpuRegToX64Reg(reg) != X64Reg::Rcx)
            {
                SWC_ASSERT(x64Reg2CpuReg(X64Reg::Rcx) == Cpu::Reg::Rcx);
                return EncodeResult::Right2Rcx;
            }

            return EncodeResult::Zero;
        }

        if (emitFlags.has(EMIT_LOCK))
            store_.pushU8(0xF0);
        emitRex(store_, opBits, REX_REG_NONE, memReg);
        emitSpecCpuOp(store_, 0xD3, opBits);
        if (op == Cpu::Op::SHL)
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
        else if (op == Cpu::Op::SAR)
            emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        else if (op == Cpu::Op::SHR)
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
    }

    ///////////////////////////////////////////

    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        if (emitFlags.has(EMIT_LOCK))
            store_.pushU8(0xF0);
        emitRex(store_, opBits, reg, memReg);
        emitSpecCpuOp(store_, op, opBits);
        emitModRm(store_, memOffset, reg, memReg);
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeOpBinaryRegImm(Cpu::Reg reg, uint64_t value, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    ///////////////////////////////////////////

    if (op == Cpu::Op::XOR)
    {
        if (opBits == Cpu::OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_6, reg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_6, reg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_6, reg);
            emitValue(store_, value, std::min(opBits, Cpu::OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::OR)
    {
        if (opBits == Cpu::OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_1, reg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_1, reg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_1, reg);
            emitValue(store_, value, std::min(opBits, Cpu::OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::AND)
    {
        if (opBits == Cpu::OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_4, reg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_4, reg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_4, reg);
            emitValue(store_, value, std::min(opBits, Cpu::OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::ADD)
    {
        if (value == 1 && !emitFlags.has(EMIT_OVERFLOW) && buildParams_.optLevel >= Runtime::BuildCfgBackendOptim::O1)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitSpecCpuOp(store_, 0xFF, opBits);
            emitModRm(store_, MODRM_REG_0, reg);
        }
        else if (opBits == Cpu::OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_0, reg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_0, reg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_0, reg);
            emitValue(store_, value, std::min(opBits, Cpu::OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::SUB)
    {
        if (value == 1 && !emitFlags.has(EMIT_OVERFLOW) && buildParams_.optLevel >= Runtime::BuildCfgBackendOptim::O1)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitSpecCpuOp(store_, 0xFF, opBits);
            emitModRm(store_, MODRM_REG_1, reg);
        }
        else if (opBits == Cpu::OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_5, reg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_5, reg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_5, reg);
            emitValue(store_, value, std::min(opBits, Cpu::OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::MOD ||
             op == Cpu::Op::IMOD ||
             op == Cpu::Op::DIV ||
             op == Cpu::Op::IDIV ||
             op == Cpu::Op::MUL)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Right2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::IMUL)
    {
        if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            if (opBits == Cpu::OpBits::B8)
                emitLoadSignedExtendRegReg(reg, reg, Cpu::OpBits::B32, opBits);
            emitRex(store_, opBits, reg, reg);
            emitCpuOp(store_, 0x6B);
            emitModRm(store_, reg, reg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            if (opBits == Cpu::OpBits::B8 || opBits == Cpu::OpBits::B16)
                emitLoadSignedExtendRegReg(reg, reg, Cpu::OpBits::B32, opBits);
            emitRex(store_, opBits, reg, reg);
            emitCpuOp(store_, 0x69);
            emitModRm(store_, reg, reg);
            emitValue(store_, value, Cpu::OpBits::B32);
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::SHL)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;

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
            emitValue(store_, std::min(static_cast<uint32_t>(value), Cpu::getNumBits(opBits) - 1), Cpu::OpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::SHR)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;

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
            emitValue(store_, std::min(static_cast<uint32_t>(value), Cpu::getNumBits(opBits) - 1), Cpu::OpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::SAR)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;

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
            emitValue(store_, std::min(static_cast<uint32_t>(value), Cpu::getNumBits(opBits) - 1), Cpu::OpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeOpBinaryMemImm(Cpu::Reg memReg, uint64_t memOffset, uint64_t value, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    if (Cpu::isFloat(memReg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////

    if (op == Cpu::Op::IMOD ||
        op == Cpu::Op::MOD ||
        op == Cpu::Op::DIV ||
        op == Cpu::Op::IDIV ||
        op == Cpu::Op::IMUL ||
        op == Cpu::Op::MUL)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Right2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////
    if (op == Cpu::Op::SAR)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;

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
            emitValue(store_, std::min(static_cast<uint32_t>(value), Cpu::getNumBits(opBits) - 1), Cpu::OpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::SHR)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;

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
            emitValue(store_, std::min(static_cast<uint32_t>(value), Cpu::getNumBits(opBits) - 1), Cpu::OpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::SHL)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;

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
            emitValue(store_, std::min(static_cast<uint32_t>(value), Cpu::getNumBits(opBits) - 1), Cpu::OpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::ADD)
    {
        if (value == 1 && !emitFlags.has(EMIT_OVERFLOW) && buildParams_.optLevel >= Runtime::BuildCfgBackendOptim::O1)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitSpecCpuOp(store_, 0xFF, opBits);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
        }
        else if (opBits == Cpu::OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
            emitValue(store_, value, std::min(opBits, Cpu::OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::SUB)
    {
        if (value == 1 && !emitFlags.has(EMIT_OVERFLOW) && buildParams_.optLevel >= Runtime::BuildCfgBackendOptim::O1)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitSpecCpuOp(store_, 0xFF, opBits);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
        }
        else if (opBits == Cpu::OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
            emitValue(store_, value, std::min(opBits, Cpu::OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::OR)
    {
        if (opBits == Cpu::OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
            emitValue(store_, value, std::min(opBits, Cpu::OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::AND)
    {
        if (opBits == Cpu::OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
            emitValue(store_, value, std::min(opBits, Cpu::OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::XOR)
    {
        if (opBits == Cpu::OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_6, memReg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_6, memReg);
            emitValue(store_, value, Cpu::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_6, memReg);
            emitValue(store_, value, std::min(opBits, Cpu::OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else
    {
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeOpTernaryRegRegReg(Cpu::Reg reg0, Cpu::Reg reg1, Cpu::Reg reg2, Cpu::Op op, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    ///////////////////////////////////////////

    if (op == Cpu::Op::MULADD)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (Cpu::isFloat(reg0) != Cpu::isFloat(reg1) || Cpu::isFloat(reg0) != Cpu::isFloat(reg2))
                return EncodeResult::NotSupported;
            if (!Cpu::isFloat(reg0))
                return EncodeResult::NotSupported;
            return EncodeResult::Zero;
        }

        SWC_ASSERT(Cpu::isFloat(reg0) && Cpu::isFloat(reg1) && Cpu::isFloat(reg2));
        emitSpecF64(store_, 0xF3, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, Cpu::Op::FMUL);
        emitModRm(store_, reg0, reg1);

        emitSpecF64(store_, 0xF3, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, Cpu::Op::FADD);
        emitModRm(store_, reg0, reg2);
    }

    ///////////////////////////////////////////

    else if (op == Cpu::Op::CMPXCHG)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (cpuRegToX64Reg(reg0) != X64Reg::Rax)
            {
                return EncodeResult::Left2Rax;
            }

            return EncodeResult::Zero;
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
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeJumpTable(Cpu::Reg tableReg, Cpu::Reg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags)
{
    const auto [offsetTableConstant, addrConstant] = buildParams_.module->constantSegment.reserveSpan<uint32_t>(numEntries);
    emitLoadSymRelocAddress(tableReg, symCsIndex_, offsetTableConstant);

    // 'movsxd' table, dword ptr [table + offset*4]
    encodeAmcReg(store_, tableReg, Cpu::OpBits::B64, tableReg, offsetReg, 4, 0, Cpu::OpBits::B64, Cpu::Op::MOVSXD, emitFlags, false);

    const auto startIdx = store_.size();
    emitLoadSymRelocAddress(offsetReg, cpuFct_->symbolIndex, store_.size() - cpuFct_->startAddress);
    const auto patchPtr = reinterpret_cast<uint32_t*>(store_.seekPtr()) - 1;
    emitOpBinaryRegReg(offsetReg, tableReg, Cpu::Op::ADD, Cpu::OpBits::B64, emitFlags);
    emitJumpReg(offsetReg);
    const auto endIdx = store_.size();
    *patchPtr += endIdx - startIdx;

    const auto tableCompiler = buildParams_.module->compilerSegment.ptr<int32_t>(offsetTable);
    const auto currentOffset = static_cast<int32_t>(store_.size());

    Cpu::LabelToSolve label;
    for (uint32_t idx = 0; idx < numEntries; idx++)
    {
        label.ipDest               = tableCompiler[idx] + currentIp + 1;
        label.jump.opBits          = Cpu::OpBits::B32;
        label.jump.offsetStart     = currentOffset;
        label.jump.patchOffsetAddr = addrConstant + idx;
        cpuFct_->labelsToSolve.push_back(label);
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeJump(Cpu::Jump& jump, Cpu::CondJump jumpType, Cpu::OpBits opBits, EmitFlags emitFlags)
{
    SWC_ASSERT(opBits == Cpu::OpBits::B8 || opBits == Cpu::OpBits::B32);

    if (opBits == Cpu::OpBits::B8)
    {
        switch (jumpType)
        {
            case Cpu::CondJump::JumpNotOverflow:
                emitCpuOp(store_, 0x71);
                break;
            case Cpu::CondJump::JumpBelow:
                emitCpuOp(store_, 0x72);
                break;
            case Cpu::CondJump::JumpAboveOrEqual:
                emitCpuOp(store_, 0x73);
                break;
            case Cpu::CondJump::JumpZero:
                emitCpuOp(store_, 0x74);
                break;
            case Cpu::CondJump::JumpNotZero:
                emitCpuOp(store_, 0x75);
                break;
            case Cpu::CondJump::JumpBelowOrEqual:
                emitCpuOp(store_, 0x76);
                break;
            case Cpu::CondJump::JumpAbove:
                store_.pushU8(0x77);
                break;
            case Cpu::CondJump::JumpSign:
                emitCpuOp(store_, 0x78);
                break;
            case Cpu::CondJump::JumpParity:
                emitCpuOp(store_, 0x7A);
                break;
            case Cpu::CondJump::JumpNotParity:
                emitCpuOp(store_, 0x7B);
                break;
            case Cpu::CondJump::JumpLess:
                emitCpuOp(store_, 0x7C);
                break;
            case Cpu::CondJump::JumpGreaterOrEqual:
                emitCpuOp(store_, 0x7D);
                break;
            case Cpu::CondJump::JumpLessOrEqual:
                emitCpuOp(store_, 0x7E);
                break;
            case Cpu::CondJump::JumpGreater:
                emitCpuOp(store_, 0x7F);
                break;
            case Cpu::CondJump::JumpUnconditional:
                emitCpuOp(store_, 0xEB);
                break;
            default:
                SWC_ASSERT(false);
                break;
        }

        store_.pushU8(0);

        jump.patchOffsetAddr = store_.seekPtr() - 1;
        jump.offsetStart     = store_.size();
        jump.opBits          = opBits;
        return EncodeResult::Zero;
    }

    switch (jumpType)
    {
        case Cpu::CondJump::JumpNotOverflow:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x81);
            break;
        case Cpu::CondJump::JumpBelow:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x82);
            break;
        case Cpu::CondJump::JumpAboveOrEqual:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x83);
            break;
        case Cpu::CondJump::JumpZero:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x84);
            break;
        case Cpu::CondJump::JumpNotZero:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x85);
            break;
        case Cpu::CondJump::JumpBelowOrEqual:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x86);
            break;
        case Cpu::CondJump::JumpAbove:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x87);
            break;
        case Cpu::CondJump::JumpParity:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8A);
            break;
        case Cpu::CondJump::JumpSign:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x88);
            break;
        case Cpu::CondJump::JumpNotParity:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8B);
            break;
        case Cpu::CondJump::JumpLess:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8C);
            break;
        case Cpu::CondJump::JumpGreaterOrEqual:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8D);
            break;
        case Cpu::CondJump::JumpLessOrEqual:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8E);
            break;
        case Cpu::CondJump::JumpGreater:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8F);
            break;
        case Cpu::CondJump::JumpUnconditional:
            emitCpuOp(store_, 0xE9);
            break;
        default:
            SWC_ASSERT(false);
            break;
    }

    store_.pushU32(0);

    jump.patchOffsetAddr = store_.seekPtr() - sizeof(uint32_t);
    jump.offsetStart     = store_.size();
    jump.opBits          = opBits;
    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodePatchJump(const Cpu::Jump& jump, uint64_t offsetDestination, EmitFlags emitFlags)
{
    const int32_t offset = static_cast<int32_t>(offsetDestination - jump.offsetStart);
    if (jump.opBits == Cpu::OpBits::B8)
    {
        SWC_ASSERT(offset >= -128 && offset <= 127);
        *static_cast<uint8_t*>(jump.patchOffsetAddr) = static_cast<int8_t>(offset);
    }
    else
    {
        *static_cast<uint32_t*>(jump.patchOffsetAddr) = static_cast<int32_t>(offset);
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodePatchJump(const Cpu::Jump& jump, EmitFlags emitFlags)
{
    return encodePatchJump(jump, store_.size(), emitFlags);
}

EncodeResult X64Encoder::encodeJumpReg(Cpu::Reg reg, EmitFlags emitFlags)
{
    emitRex(store_, Cpu::OpBits::Zero, REX_REG_NONE, reg);
    emitCpuOp(store_, 0xFF);
    emitModRm(store_, ModRmMode::Register, MODRM_REG_4, encodeReg(reg));
    return EncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeCallExtern(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)
{
    emitCpuOp(store_, 0xFF);
    emitModRm(store_, ModRmMode::Memory, MODRM_REG_2, MODRM_RM_RIP);

    const auto callSym = getOrAddSymbol(symbolName, Cpu::SymbolKind::Extern);
    addSymbolRelocation(store_.size() - textSectionOffset_, callSym->index, IMAGE_REL_AMD64_REL32);
    store_.pushU32(0);
    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeCallLocal(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)
{
    emitCpuOp(store_, 0xE8);

    const auto callSym = getOrAddSymbol(symbolName, Cpu::SymbolKind::Extern);
    if (callSym->kind == Cpu::SymbolKind::Function)
    {
        store_.pushS32(static_cast<int32_t>(callSym->value + textSectionOffset_ - (store_.size() + 4)));
    }
    else
    {
        addSymbolRelocation(store_.size() - textSectionOffset_, callSym->index, IMAGE_REL_AMD64_REL32);
        store_.pushU32(0);
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeCallReg(Cpu::Reg reg, const CallConv* callConv, EmitFlags emitFlags)
{
    emitRex(store_, Cpu::OpBits::Zero, REX_REG_NONE, reg);
    emitCpuOp(store_, 0xFF);
    emitModRm(store_, MODRM_REG_2, reg);
    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeNop(EmitFlags emitFlags)
{
    emitCpuOp(store_, 0x90);
    return EncodeResult::Zero;
}

Cpu::RegSet X64Encoder::getReadRegisters(const MicroInstruction& inst)
{
    auto result = Encoder::getReadRegisters(inst);

    if (inst.op == MicroOp::OpBinaryRI ||
        inst.op == MicroOp::OpBinaryRR ||
        inst.op == MicroOp::OpBinaryMI ||
        inst.op == MicroOp::OpBinaryRM ||
        inst.op == MicroOp::OpBinaryMR)
    {
        auto cpuOp = Cpu::Op::ADD;
        switch (inst.op)
        {
            case MicroOp::OpBinaryRI:
                cpuOp = inst.ops[2].cpuOp;
                break;
            case MicroOp::OpBinaryRR:
                cpuOp = inst.ops[3].cpuOp;
                break;
            case MicroOp::OpBinaryMI:
                cpuOp = inst.ops[2].cpuOp;
                break;
            case MicroOp::OpBinaryRM:
            case MicroOp::OpBinaryMR:
                cpuOp = inst.ops[3].cpuOp;
                break;
            default:
                break;
        }

        if (cpuOp == Cpu::Op::ROL ||
            cpuOp == Cpu::Op::ROR ||
            cpuOp == Cpu::Op::SAL ||
            cpuOp == Cpu::Op::SAR ||
            cpuOp == Cpu::Op::SHL ||
            cpuOp == Cpu::Op::SHR)
        {
            result.add(x64Reg2CpuReg(X64Reg::Rcx));
        }
        else if (cpuOp == Cpu::Op::MUL ||
                 cpuOp == Cpu::Op::DIV ||
                 cpuOp == Cpu::Op::MOD ||
                 cpuOp == Cpu::Op::IDIV ||
                 cpuOp == Cpu::Op::IMOD)
        {
            result.add(x64Reg2CpuReg(X64Reg::Rdx));
        }
    }

    return result;
}

Cpu::RegSet X64Encoder::getWriteRegisters(const MicroInstruction& inst)
{
    auto result = Encoder::getWriteRegisters(inst);

    if (inst.op == MicroOp::OpBinaryRI ||
        inst.op == MicroOp::OpBinaryRR ||
        inst.op == MicroOp::OpBinaryMI ||
        inst.op == MicroOp::OpBinaryRM ||
        inst.op == MicroOp::OpBinaryMR)
    {
        auto cpuOp = Cpu::Op::ADD;
        switch (inst.op)
        {
            case MicroOp::OpBinaryRI:
                cpuOp = inst.ops[2].cpuOp;
                break;
            case MicroOp::OpBinaryRR:
                cpuOp = inst.ops[3].cpuOp;
                break;
            case MicroOp::OpBinaryMI:
                cpuOp = inst.ops[2].cpuOp;
                break;
            case MicroOp::OpBinaryRM:
            case MicroOp::OpBinaryMR:
                cpuOp = inst.ops[3].cpuOp;
                break;
            default:
                break;
        }

        if (cpuOp == Cpu::Op::MUL ||
            cpuOp == Cpu::Op::DIV ||
            cpuOp == Cpu::Op::MOD ||
            cpuOp == Cpu::Op::IDIV ||
            cpuOp == Cpu::Op::IMOD)
        {
            result.add(x64Reg2CpuReg(X64Reg::Rdx));
        }
    }

    return result;
}

SWC_END_NAMESPACE();
