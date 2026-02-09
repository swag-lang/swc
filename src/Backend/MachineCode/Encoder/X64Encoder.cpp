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

constexpr auto REX_REG_NONE  = static_cast<Micro::Reg>(255);
constexpr auto MODRM_REG_0   = static_cast<Micro::Reg>(254);
constexpr auto MODRM_REG_1   = static_cast<Micro::Reg>(253);
constexpr auto MODRM_REG_2   = static_cast<Micro::Reg>(252);
constexpr auto MODRM_REG_3   = static_cast<Micro::Reg>(251);
constexpr auto MODRM_REG_4   = static_cast<Micro::Reg>(250);
constexpr auto MODRM_REG_5   = static_cast<Micro::Reg>(249);
constexpr auto MODRM_REG_6   = static_cast<Micro::Reg>(248);
constexpr auto MODRM_REG_7   = static_cast<Micro::Reg>(247);
constexpr auto MODRM_REG_SIB = static_cast<Micro::Reg>(246);

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
    Micro::Reg x64Reg2CpuReg(X64Reg reg)
    {
        switch (reg)
        {
            case X64Reg::Rax:
                return Micro::Reg::Rax;
            case X64Reg::Rbx:
                return Micro::Reg::Rbx;
            case X64Reg::Rcx:
                return Micro::Reg::Rcx;
            case X64Reg::Rdx:
                return Micro::Reg::Rdx;
            case X64Reg::Rsp:
                return Micro::Reg::Rsp;
            case X64Reg::Rbp:
                return Micro::Reg::Rbp;
            case X64Reg::Rsi:
                return Micro::Reg::Rsi;
            case X64Reg::Rdi:
                return Micro::Reg::Rdi;
            case X64Reg::R8:
                return Micro::Reg::R8;
            case X64Reg::R9:
                return Micro::Reg::R9;
            case X64Reg::R10:
                return Micro::Reg::R10;
            case X64Reg::R11:
                return Micro::Reg::R11;
            case X64Reg::R12:
                return Micro::Reg::R12;
            case X64Reg::R13:
                return Micro::Reg::R13;
            case X64Reg::R14:
                return Micro::Reg::R14;
            case X64Reg::R15:
                return Micro::Reg::R15;
            case X64Reg::Xmm0:
                return Micro::Reg::Xmm0;
            case X64Reg::Xmm1:
                return Micro::Reg::Xmm1;
            case X64Reg::Xmm2:
                return Micro::Reg::Xmm2;
            case X64Reg::Xmm3:
                return Micro::Reg::Xmm3;
            case X64Reg::Rip:
                return Micro::Reg::Rip;

            default:
                SWC_ASSERT(false);
                return Micro::Reg::Rax;
        }
    }

    X64Reg cpuRegToX64Reg(Micro::Reg reg)
    {
        switch (reg)
        {
            case Micro::Reg::Rax:
                return X64Reg::Rax;
            case Micro::Reg::Rbx:
                return X64Reg::Rbx;
            case Micro::Reg::Rcx:
                return X64Reg::Rcx;
            case Micro::Reg::Rdx:
                return X64Reg::Rdx;
            case Micro::Reg::Rsp:
                return X64Reg::Rsp;
            case Micro::Reg::Rbp:
                return X64Reg::Rbp;
            case Micro::Reg::Rsi:
                return X64Reg::Rsi;
            case Micro::Reg::Rdi:
                return X64Reg::Rdi;
            case Micro::Reg::R8:
                return X64Reg::R8;
            case Micro::Reg::R9:
                return X64Reg::R9;
            case Micro::Reg::R10:
                return X64Reg::R10;
            case Micro::Reg::R11:
                return X64Reg::R11;
            case Micro::Reg::R12:
                return X64Reg::R12;
            case Micro::Reg::R13:
                return X64Reg::R13;
            case Micro::Reg::R14:
                return X64Reg::R14;
            case Micro::Reg::R15:
                return X64Reg::R15;
            case Micro::Reg::Xmm0:
                return X64Reg::Xmm0;
            case Micro::Reg::Xmm1:
                return X64Reg::Xmm1;
            case Micro::Reg::Xmm2:
                return X64Reg::Xmm2;
            case Micro::Reg::Xmm3:
                return X64Reg::Xmm3;
            case Micro::Reg::Rip:
                return X64Reg::Rip;
            default:
                SWC_ASSERT(false);
                return X64Reg::Rax;
        }
    }

    uint8_t encodeReg(Micro::Reg reg)
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

    bool canEncode8(uint64_t value, Micro::OpBits opBits)
    {
        return value <= 0x7F ||
               (opBits == Micro::OpBits::B16 && value >= 0xFF80) ||
               (opBits == Micro::OpBits::B32 && value >= 0xFFFFFF80) ||
               (opBits == Micro::OpBits::B64 && value >= 0xFFFFFFFFFFFFFF80);
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

    uint8_t getModRm(ModRmMode mod, Micro::Reg reg, uint8_t rm)
    {
        return getModRm(mod, encodeReg(reg), rm);
    }

    void emitPrefixF64(Store& store, Micro::OpBits opBits)
    {
        if (opBits == Micro::OpBits::B64)
            store.pushU8(0x66);
    }

    void emitSIB(Store& store, uint8_t scale, uint8_t index, uint8_t base)
    {
        const uint8_t value = static_cast<uint8_t>(scale << 6) | static_cast<uint8_t>(index << 3) | base;
        store.pushU8(value);
    }

    void emitRex(Store& store, Micro::OpBits opBits, Micro::Reg reg0 = REX_REG_NONE, Micro::Reg reg1 = REX_REG_NONE)
    {
        if (opBits == Micro::OpBits::B16)
            store.pushU8(0x66);

        const bool b1 = (reg0 >= Micro::Reg::R8 && reg0 <= Micro::Reg::R15);
        const bool b2 = (reg1 >= Micro::Reg::R8 && reg1 <= Micro::Reg::R15);
        if (opBits == Micro::OpBits::B64 ||
            b1 || b2 ||
            reg0 == Micro::Reg::Rsi || reg1 == Micro::Reg::Rsi ||
            reg0 == Micro::Reg::Rdi || reg1 == Micro::Reg::Rdi ||
            reg0 == Micro::Reg::Rsp || reg1 == Micro::Reg::Rsp ||
            reg0 == Micro::Reg::Rbp || reg1 == Micro::Reg::Rbp)
        {
            const auto value = getRex(opBits == Micro::OpBits::B64, b1, false, b2);
            store.pushU8(value);
        }
    }

    void emitValue(Store& store, uint64_t value, Micro::OpBits opBits)
    {
        if (opBits == Micro::OpBits::B8)
            store.pushU8(static_cast<uint8_t>(value));
        else if (opBits == Micro::OpBits::B16)
            store.pushU16(static_cast<uint16_t>(value));
        else if (opBits == Micro::OpBits::B32)
            store.pushU32(static_cast<uint32_t>(value));
        else
            store.pushU64(value);
    }

    void emitModRm(Store& store, ModRmMode mod, Micro::Reg reg, uint8_t rm)
    {
        const auto value = getModRm(mod, reg, rm);
        store.pushU8(value);
    }

    void emitModRm(Store& store, Micro::Reg reg, Micro::Reg memReg)
    {
        emitModRm(store, ModRmMode::Register, reg, encodeReg(memReg));
    }

    void emitModRm(Store& store, uint64_t memOffset, Micro::Reg reg, Micro::Reg memReg)
    {
        if (memOffset == 0 && memReg != Micro::Reg::R13 && memReg != Micro::Reg::Rbp)
        {
            if (memReg == Micro::Reg::Rsp || memReg == Micro::Reg::R12)
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
            if (memReg == Micro::Reg::Rsp || memReg == Micro::Reg::R12)
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

            emitValue(store, memOffset, Micro::OpBits::B8);
        }
        else
        {
            if (memReg == Micro::Reg::Rsp || memReg == Micro::Reg::R12)
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
            emitValue(store, memOffset, Micro::OpBits::B32);
        }
    }

    void emitSpecB8(Store& store, uint8_t value, Micro::OpBits opBits)
    {
        if (opBits == Micro::OpBits::B8)
            store.pushU8(value & ~1);
        else
            store.pushU8(value);
    }

    void emitSpecF64(Store& store, uint8_t value, Micro::OpBits opBits)
    {
        if (opBits == Micro::OpBits::B64)
            store.pushU8(value & ~1);
        else if (opBits == Micro::OpBits::B32)
            store.pushU8(value);
    }

    uint8_t getX64OpCode(Micro::Op op)
    {
        switch (op)
        {
            case Micro::Op::Add:
                return 0x01;
            case Micro::Op::Or:
                return 0x09;
            case Micro::Op::And:
                return 0x21;
            case Micro::Op::Subtract:
                return 0x29;
            case Micro::Op::ConvertIntToFloat:
                return 0x2A;
            case Micro::Op::ConvertUIntToFloat64:
                return 0x2B;
            case Micro::Op::ConvertFloatToInt:
                return 0x2C;
            case Micro::Op::Xor:
                return 0x31;
            case Micro::Op::FloatSqrt:
                return 0x51;
            case Micro::Op::FloatAnd:
                return 0x54;
            case Micro::Op::FloatXor:
                return 0x57;
            case Micro::Op::FloatAdd:
                return 0x58;
            case Micro::Op::FloatMultiply:
                return 0x59;
            case Micro::Op::ConvertFloatToFloat:
                return 0x5A;
            case Micro::Op::FloatSubtract:
                return 0x5C;
            case Micro::Op::FloatMin:
                return 0x5D;
            case Micro::Op::FloatDivide:
                return 0x5E;
            case Micro::Op::FloatMax:
                return 0x5F;
            case Micro::Op::MoveSignExtend:
                return 0x63;
            case Micro::Op::Exchange:
                return 0x87;
            case Micro::Op::Move:
                return 0x8B;
            case Micro::Op::LoadEffectiveAddress:
                return 0x8D;
            case Micro::Op::Negate:
                return 0x9F;
            case Micro::Op::ByteSwap:
                return 0xB0;
            case Micro::Op::PopCount:
                return 0xB8;
            case Micro::Op::BitScanForward:
                return 0xBC;
            case Micro::Op::BitScanReverse:
                return 0xBD;
            case Micro::Op::MultiplyUnsigned:
                return 0xC0;
            case Micro::Op::MultiplySigned:
                return 0xC1;
            case Micro::Op::RotateLeft:
                return 0xC7;
            case Micro::Op::RotateRight:
                return 0xC8;
            case Micro::Op::ShiftLeft:
                return 0xE0;
            case Micro::Op::ShiftRight:
                return 0xE8;
            case Micro::Op::ShiftArithmeticLeft:
                return 0xF0;
            case Micro::Op::DivideUnsigned:
                return 0xF1;
            case Micro::Op::ModuloUnsigned:
                return 0xF3;
            case Micro::Op::BitwiseNot:
                return 0xF7;
            case Micro::Op::ShiftArithmeticRight:
                return 0xF8;
            case Micro::Op::DivideSigned:
                return 0xF9;
            case Micro::Op::CompareExchange:
                return 0xFA;
            case Micro::Op::ModuloSigned:
                return 0xFB;
            case Micro::Op::MultiplyAdd:
                return 0xFC;
            default:
                SWC_ASSERT(false);
                return 0;
        }
    }

    void emitCpuOp(Store& store, Micro::Op op)
    {
        store.pushU8(getX64OpCode(op));
    }

    void emitCpuOp(Store& store, uint8_t op)
    {
        store.pushU8(op);
    }

    void emitCpuOp(Store& store, uint8_t op, Micro::Reg reg)
    {
        store.pushU8(op | (encodeReg(reg) & 0b111));
    }

    void emitSpecCpuOp(Store& store, Micro::Op op, Micro::OpBits opBits)
    {
        emitSpecB8(store, getX64OpCode(op), opBits);
    }

    void emitSpecCpuOp(Store& store, uint8_t op, Micro::OpBits opBits)
    {
        emitSpecB8(store, op, opBits);
    }
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeLoadSymbolRelocAddress(Micro::Reg reg, uint32_t symbolIndex, uint32_t offset, EmitFlags emitFlags)
{
    emitRex(store_, Micro::OpBits::B64, reg);
    emitCpuOp(store_, 0x8D); // LEA
    emitModRm(store_, ModRmMode::Memory, reg, MODRM_RM_RIP);
    addSymbolRelocation(store_.size() - textSectionOffset_, symbolIndex, IMAGE_REL_AMD64_REL32);
    store_.pushU32(offset);
    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeLoadSymRelocValue(Micro::Reg reg, uint32_t symbolIndex, uint32_t offset, Micro::OpBits opBits, EmitFlags emitFlags)
{
    if (Micro::isFloat(reg))
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
        SWC_ASSERT(opBits == Micro::OpBits::B64);
        emitRex(store_, opBits, REX_REG_NONE, reg);
        emitCpuOp(store_, 0xB8, reg); // MOV
        addSymbolRelocation(store_.size() - textSectionOffset_, symbolIndex, IMAGE_REL_AMD64_ADDR64);
        store_.pushU64(offset);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        SWC_ASSERT(opBits == Micro::OpBits::B64);
        emitRex(store_, opBits, reg);
        emitCpuOp(store_, 0x8B); // MOV
        emitModRm(store_, ModRmMode::Memory, reg, MODRM_RM_RIP);
        addSymbolRelocation(store_.size() - textSectionOffset_, symbolIndex, IMAGE_REL_AMD64_REL32);
        store_.pushU32(offset);
    }

    return EncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodePush(Micro::Reg reg, EmitFlags emitFlags)
{
    emitRex(store_, Micro::OpBits::Zero, REX_REG_NONE, reg);
    emitCpuOp(store_, 0x50, reg);
    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodePop(Micro::Reg reg, EmitFlags emitFlags)
{
    emitRex(store_, Micro::OpBits::Zero, REX_REG_NONE, reg);
    emitCpuOp(store_, 0x58, reg);
    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeRet(EmitFlags emitFlags)
{
    emitCpuOp(store_, 0xC3);
    return EncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeLoadRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::OpBits opBits, EmitFlags emitFlags)
{
    if (Micro::isFloat(regDst) && Micro::isFloat(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitSpecF64(store_, 0xF3, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x10);
        emitModRm(store_, regDst, regSrc);
    }
    else if (Micro::isFloat(regDst))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitPrefixF64(store_, Micro::OpBits::B64);
        emitRex(store_, opBits, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x6E);
        emitModRm(store_, regDst, regSrc);
    }
    else if (Micro::isFloat(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitPrefixF64(store_, Micro::OpBits::B64);
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

EncodeResult X64Encoder::encodeLoadRegImm(Micro::Reg reg, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags)
{
    if (Micro::isFloat(reg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Right2Cst;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (opBits == Micro::OpBits::B8)
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

EncodeResult X64Encoder::encodeLoadRegMem(Micro::Reg reg, Micro::Reg memReg, uint64_t memOffset, Micro::OpBits opBits, EmitFlags emitFlags)
{
    if (Micro::isFloat(memReg))
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

    if (Micro::isFloat(reg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, Micro::OpBits::Zero, reg, memReg);
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

EncodeResult X64Encoder::encodeLoadZeroExtendRegMem(Micro::Reg reg, Micro::Reg memReg, uint64_t memOffset, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);

    if (Micro::isFloat(memReg))
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

    if (numBitsSrc == Micro::OpBits::B8 && (numBitsDst == Micro::OpBits::B32 || numBitsDst == Micro::OpBits::B64))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, reg, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB6);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else if (numBitsSrc == Micro::OpBits::B16 && (numBitsDst == Micro::OpBits::B32 || numBitsDst == Micro::OpBits::B64))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, reg, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB7);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else if (numBitsSrc == Micro::OpBits::B32 && numBitsDst == Micro::OpBits::B64)
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

EncodeResult X64Encoder::encodeLoadZeroExtendRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);

    if (Micro::isFloat(regDst) || Micro::isFloat(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (numBitsSrc == Micro::OpBits::B8 && (numBitsDst == Micro::OpBits::B32 || numBitsDst == Micro::OpBits::B64))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB6);
        emitModRm(store_, regDst, regSrc);
    }
    else if (numBitsSrc == Micro::OpBits::B16 && (numBitsDst == Micro::OpBits::B32 || numBitsDst == Micro::OpBits::B64))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, Micro::OpBits::B64, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB7);
        emitModRm(store_, regDst, regSrc);
    }
    else if (numBitsSrc == Micro::OpBits::B32 && numBitsDst == Micro::OpBits::B64)
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

EncodeResult X64Encoder::encodeLoadSignedExtendRegMem(Micro::Reg reg, Micro::Reg memReg, uint64_t memOffset, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);

    if (Micro::isFloat(memReg))
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

    if (numBitsSrc == Micro::OpBits::B8)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, reg, memReg);
        store_.pushU8(0x0F);
        store_.pushU8(0xBE);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else if (numBitsSrc == Micro::OpBits::B16)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, reg, memReg);
        store_.pushU8(0x0F);
        store_.pushU8(0xBF);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else if (numBitsSrc == Micro::OpBits::B32)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        SWC_ASSERT(numBitsDst == Micro::OpBits::B64);
        emitRex(store_, Micro::OpBits::B64, reg, memReg);
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

EncodeResult X64Encoder::encodeLoadSignedExtendRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::OpBits numBitsDst, Micro::OpBits numBitsSrc, EmitFlags emitFlags)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);

    if (Micro::isFloat(regDst) || Micro::isFloat(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (numBitsSrc == Micro::OpBits::B8)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xBE);
        emitModRm(store_, regDst, regSrc);
    }
    else if (numBitsSrc == Micro::OpBits::B16)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xBF);
        emitModRm(store_, regDst, regSrc);
    }
    else if (numBitsSrc == Micro::OpBits::B32 && numBitsDst == Micro::OpBits::B64)
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

EncodeResult X64Encoder::encodeLoadAddressRegMem(Micro::Reg reg, Micro::Reg memReg, uint64_t memOffset, Micro::OpBits opBits, EmitFlags emitFlags)
{
    if (emitFlags.has(EMIT_CAN_ENCODE))
    {
        if (opBits != Micro::OpBits::B64)
            return EncodeResult::NotSupported;
    }

    if (Micro::isFloat(memReg))
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

    if (memReg == Micro::Reg::Rip)
    {
        SWC_ASSERT(memOffset == 0);
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, Micro::OpBits::B64, reg, memReg);
        emitCpuOp(store_, 0x8D);
        emitModRm(store_, ModRmMode::Memory, reg, MODRM_RM_RIP);
    }
    else if (memOffset == 0)
    {
        emitLoadRegReg(reg, memReg, Micro::OpBits::B64);
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, Micro::OpBits::B64, reg, memReg);
        emitCpuOp(store_, 0x8D);
        emitModRm(store_, memOffset, reg, memReg);
    }

    return EncodeResult::Zero;
}

namespace
{
    EncodeResult encodeAmcImm(Store& store, Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsBaseMul, uint64_t value, Micro::OpBits opBitsValue, EmitFlags emitFlags)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (mulValue != 1 && mulValue != 2 && mulValue != 4 && mulValue != 8)
                return EncodeResult::NotSupported;
            if (opBitsBaseMul != Micro::OpBits::B32 && opBitsBaseMul != Micro::OpBits::B64)
                return EncodeResult::NotSupported;
            if (addValue > 0x7FFFFFFF)
                return EncodeResult::NotSupported;
            if (value > 0x7FFFFFFF)
                return EncodeResult::NotSupported;
            if (Micro::isFloat(regBase) || Micro::isFloat(regMul))
                return EncodeResult::NotSupported;
            if (opBitsBaseMul != Micro::OpBits::B64 && (regBase == Micro::Reg::Rsp || regMul == Micro::Reg::Rsp))
                return EncodeResult::NotSupported;
            if (regMul == Micro::Reg::Rsp && mulValue != 1)
                return EncodeResult::NotSupported;
            return EncodeResult::Zero;
        }

        if (regMul == Micro::Reg::Rsp)
        {
            SWC_ASSERT(mulValue == 1);
            std::swap(regMul, regBase);
        }

        // Prefixes
        if (opBitsValue == Micro::OpBits::B16)
            store.pushU8(0x66);

        // REX prefix
        const bool b1 = (regMul >= Micro::Reg::R8 && regMul <= Micro::Reg::R15);
        const bool b2 = (regBase >= Micro::Reg::R8 && regBase <= Micro::Reg::R15);
        if (opBitsValue == Micro::OpBits::B64 || b1 || b2)
        {
            const auto val = getRex(opBitsValue == Micro::OpBits::B64, false, b1, b2);
            store.pushU8(val);
        }

        // OpCode
        emitSpecCpuOp(store, 0xC7, opBitsValue);

        // ModRM
        if (regBase == Micro::Reg::R13)
            emitModRm(store, addValue <= 0x7F ? ModRmMode::Displacement8 : ModRmMode::Displacement32, MODRM_REG_0, MODRM_RM_SIB);
        else if (addValue == 0 || regBase == Micro::Reg::Max)
            emitModRm(store, ModRmMode::Memory, MODRM_REG_0, MODRM_RM_SIB);
        else
            emitModRm(store, addValue <= 0x7F ? ModRmMode::Displacement8 : ModRmMode::Displacement32, MODRM_REG_0, MODRM_RM_SIB);

        // SIB
        SWC_ASSERT(mulValue == 1 || mulValue == 2 || mulValue == 4 || mulValue == 8);
        const auto scale = static_cast<uint8_t>(log2(mulValue));
        if (regBase == Micro::Reg::Max)
        {
            emitSIB(store, scale, encodeReg(regMul) & 0b111, SIB_NO_BASE);
            emitValue(store, addValue, Micro::OpBits::B32);
        }
        else
        {
            emitSIB(store, scale, encodeReg(regMul) & 0b111, encodeReg(regBase) & 0b111);
            if (regBase == Micro::Reg::R13 || addValue != 0)
                emitValue(store, addValue, addValue <= 0x7F ? Micro::OpBits::B8 : Micro::OpBits::B32);
        }

        // Value
        emitValue(store, value, std::min(opBitsValue, Micro::OpBits::B32));
        return EncodeResult::Zero;
    }

    EncodeResult encodeAmcReg(Store& store, Micro::Reg reg, Micro::OpBits opBitsReg, Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsBaseMul, Micro::Op op, EmitFlags emitFlags, bool mr)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (mulValue != 1 && mulValue != 2 && mulValue != 4 && mulValue != 8)
                return EncodeResult::NotSupported;
            if (op == Micro::Op::LoadEffectiveAddress && opBitsReg == Micro::OpBits::B8)
                return EncodeResult::NotSupported;
            if (opBitsBaseMul != Micro::OpBits::B32 && opBitsBaseMul != Micro::OpBits::B64)
                return EncodeResult::NotSupported;
            if (addValue > 0x7FFFFFFF)
                return EncodeResult::NotSupported;
            if (Micro::isFloat(regBase) || Micro::isFloat(regMul))
                return EncodeResult::NotSupported;
            if (Micro::isFloat(reg) && op == Micro::Op::LoadEffectiveAddress)
                return EncodeResult::NotSupported;
            if (Micro::isFloat(reg) && op == Micro::Op::MoveSignExtend)
                return EncodeResult::NotSupported;
            if (Micro::isFloat(reg) && opBitsReg != Micro::OpBits::B32 && opBitsReg != Micro::OpBits::B64)
                return EncodeResult::NotSupported;
            if (opBitsBaseMul != Micro::OpBits::B64 && (regBase == Micro::Reg::Rsp || regMul == Micro::Reg::Rsp))
                return EncodeResult::NotSupported;
            if (regMul == Micro::Reg::Rsp && mulValue != 1)
                return EncodeResult::NotSupported;
            return EncodeResult::Zero;
        }

        if (regMul == Micro::Reg::Rsp)
        {
            SWC_ASSERT(mulValue == 1);
            std::swap(regMul, regBase);
        }

        // Prefixes
        if (opBitsBaseMul == Micro::OpBits::B32)
            store.pushU8(0x67);
        if (opBitsReg == Micro::OpBits::B16 || Micro::isFloat(reg))
            store.pushU8(0x66);

        // REX prefix
        const bool b0      = (reg >= Micro::Reg::R8 && reg <= Micro::Reg::R15);
        const bool b1      = (regMul >= Micro::Reg::R8 && regMul <= Micro::Reg::R15);
        const bool b2      = (regBase >= Micro::Reg::R8 && regBase <= Micro::Reg::R15);
        const bool needRex = opBitsReg == Micro::OpBits::B64 || reg == Micro::Reg::Rsi || reg == Micro::Reg::Rdi || reg == Micro::Reg::Rsp || reg == Micro::Reg::Rbp;
        if (needRex || b0 || b1 || b2)
        {
            const auto value = getRex(opBitsReg == Micro::OpBits::B64, b0, b1, b2);
            store.pushU8(value);
        }

        // Opcode
        switch (op)
        {
            case Micro::Op::LoadEffectiveAddress:
                emitSpecCpuOp(store, 0x8D, opBitsReg);
                break;
            case Micro::Op::MoveSignExtend:
                emitSpecCpuOp(store, 0x63, opBitsReg);
                break;
            case Micro::Op::Move:
                if (Micro::isFloat(reg))
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
        if (regBase == Micro::Reg::R13)
            emitModRm(store, addValue <= 0x7F ? ModRmMode::Displacement8 : ModRmMode::Displacement32, reg, MODRM_RM_SIB);
        else if (addValue == 0 || regBase == Micro::Reg::Max)
            emitModRm(store, ModRmMode::Memory, reg, MODRM_RM_SIB);
        else
            emitModRm(store, addValue <= 0x7F ? ModRmMode::Displacement8 : ModRmMode::Displacement32, reg, MODRM_RM_SIB);

        // SIB
        SWC_ASSERT(mulValue == 1 || mulValue == 2 || mulValue == 4 || mulValue == 8);
        const auto scale = static_cast<uint8_t>(log2(mulValue));
        if (regBase == Micro::Reg::Max)
        {
            emitSIB(store, scale, encodeReg(regMul) & 0b111, SIB_NO_BASE);
            emitValue(store, addValue, Micro::OpBits::B32);
        }
        else
        {
            emitSIB(store, scale, encodeReg(regMul) & 0b111, encodeReg(regBase) & 0b111);
            if (regBase == Micro::Reg::R13 || addValue != 0)
                emitValue(store, addValue, addValue <= 0x7F ? Micro::OpBits::B8 : Micro::OpBits::B32);
        }

        return EncodeResult::Zero;
    }
}

EncodeResult X64Encoder::encodeLoadAmcRegMem(Micro::Reg regDst, Micro::OpBits opBitsDst, Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsSrc, EmitFlags emitFlags)
{
    return encodeAmcReg(store_, regDst, opBitsDst, regBase, regMul, mulValue, addValue, opBitsSrc, Micro::Op::Move, emitFlags, false);
}

EncodeResult X64Encoder::encodeLoadAmcMemReg(Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsBaseMul, Micro::Reg regSrc, Micro::OpBits opBitsSrc, EmitFlags emitFlags)
{
    return encodeAmcReg(store_, regSrc, opBitsSrc, regBase, regMul, mulValue, addValue, opBitsBaseMul, Micro::Op::Move, emitFlags, true);
}

EncodeResult X64Encoder::encodeLoadAmcMemImm(Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsBaseMul, uint64_t value, Micro::OpBits opBitsValue, EmitFlags emitFlags)
{
    return encodeAmcImm(store_, regBase, regMul, mulValue, addValue, opBitsBaseMul, value, opBitsValue, emitFlags);
}

EncodeResult X64Encoder::encodeLoadAddressAmcRegMem(Micro::Reg regDst, Micro::OpBits opBitsDst, Micro::Reg regBase, Micro::Reg regMul, uint64_t mulValue, uint64_t addValue, Micro::OpBits opBitsValue, EmitFlags emitFlags)
{
    return encodeAmcReg(store_, regDst, opBitsDst, regBase, regMul, mulValue, addValue, opBitsValue, Micro::Op::LoadEffectiveAddress, emitFlags, false);
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeLoadMemReg(Micro::Reg memReg, uint64_t memOffset, Micro::Reg reg, Micro::OpBits opBits, EmitFlags emitFlags)
{
    if (Micro::isFloat(memReg))
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

    if (Micro::isFloat(reg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, Micro::OpBits::Zero, reg, memReg);
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

EncodeResult X64Encoder::encodeLoadMemImm(Micro::Reg memReg, uint64_t memOffset, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags)
{
    if (Micro::isFloat(memReg))
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

    if (opBits == Micro::OpBits::B128)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Right2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (opBits == Micro::OpBits::B64 && value > 0x7FFFFFFF && value >> 32 != 0xFFFFFFFF)
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
    emitValue(store_, value, std::min(opBits, Micro::OpBits::B32));

    return EncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeClearReg(Micro::Reg reg, Micro::OpBits opBits, EmitFlags emitFlags)
{
    if (emitFlags.has(EMIT_CAN_ENCODE))
        return EncodeResult::Zero;

    if (Micro::isFloat(reg))
    {
        emitPrefixF64(store_, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, Micro::Op::FloatXor);
        emitModRm(store_, reg, reg);
    }
    else
    {
        emitRex(store_, opBits, reg, reg);
        emitSpecCpuOp(store_, Micro::Op::Xor, opBits);
        emitModRm(store_, reg, reg);
    }

    return EncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeSetCondReg(Micro::Reg reg, Micro::Cond cpuCond, EmitFlags emitFlags)
{
    if (emitFlags.has(EMIT_CAN_ENCODE))
        return EncodeResult::Zero;

    emitRex(store_, Micro::OpBits::B8, REX_REG_NONE, reg);
    emitCpuOp(store_, 0x0F);

    switch (cpuCond)
    {
        case Micro::Cond::Above:
            emitCpuOp(store_, 0x97);
            break;
        case Micro::Cond::Overflow:
            emitCpuOp(store_, 0x90);
            break;
        case Micro::Cond::AboveOrEqual:
            emitCpuOp(store_, 0x93);
            break;
        case Micro::Cond::Greater:
            emitCpuOp(store_, 0x9F);
            break;
        case Micro::Cond::NotEqual:
            emitCpuOp(store_, 0x95);
            break;
        case Micro::Cond::NotAbove:
            emitCpuOp(store_, 0x96);
            break;
        case Micro::Cond::Below:
            emitCpuOp(store_, 0x92);
            break;
        case Micro::Cond::BelowOrEqual:
            emitCpuOp(store_, 0x96);
            break;
        case Micro::Cond::Equal:
            emitCpuOp(store_, 0x94);
            break;
        case Micro::Cond::GreaterOrEqual:
            emitCpuOp(store_, 0x9D);
            break;
        case Micro::Cond::Less:
            emitCpuOp(store_, 0x9C);
            break;
        case Micro::Cond::LessOrEqual:
            emitCpuOp(store_, 0x9E);
            break;
        case Micro::Cond::Parity:
            emitCpuOp(store_, 0x9A);
            break;
        case Micro::Cond::NotParity:
            emitCpuOp(store_, 0x9B);
            break;
        default:
            SWC_ASSERT(false);
            break;
    }

    emitModRm(store_, MODRM_REG_0, reg);
    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeLoadCondRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::Cond setType, Micro::OpBits opBits, EmitFlags emitFlags)
{
    if (emitFlags.has(EMIT_CAN_ENCODE))
        return EncodeResult::Zero;

    opBits = std::max(opBits, Micro::OpBits::B32);
    emitRex(store_, opBits, regDst, regSrc);
    emitCpuOp(store_, 0x0F);

    switch (setType)
    {
        case Micro::Cond::Below:
            emitCpuOp(store_, 0x42);
            break;
        case Micro::Cond::Equal:
            emitCpuOp(store_, 0x44);
            break;
        case Micro::Cond::Greater:
            emitCpuOp(store_, 0x4F);
            break;
        case Micro::Cond::Less:
            emitCpuOp(store_, 0x4C);
            break;
        case Micro::Cond::BelowOrEqual:
            emitCpuOp(store_, 0x46);
            break;
        case Micro::Cond::GreaterOrEqual:
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

EncodeResult X64Encoder::encodeCmpRegReg(Micro::Reg reg0, Micro::Reg reg1, Micro::OpBits opBits, EmitFlags emitFlags)
{
    if (Micro::isFloat(reg0))
    {
        if (Micro::isInt(reg1))
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
            if (Micro::isFloat(reg1))
                return EncodeResult::NotSupported;
            return EncodeResult::Zero;
        }

        emitRex(store_, opBits, reg1, reg0);
        emitSpecCpuOp(store_, 0x39, opBits);
        emitModRm(store_, reg1, reg0);
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeCmpRegImm(Micro::Reg reg, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags)
{
    if (Micro::isFloat(reg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (opBits == Micro::OpBits::B8)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, reg);
        emitCpuOp(store_, 0x80);
        emitModRm(store_, MODRM_REG_7, reg);
        emitValue(store_, value, Micro::OpBits::B8);
    }
    else if (canEncode8(value, opBits))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, reg);
        emitCpuOp(store_, 0x83);
        emitModRm(store_, MODRM_REG_7, reg);
        emitValue(store_, value, Micro::OpBits::B8);
    }
    else if ((opBits != Micro::OpBits::B64 || value <= 0x7FFFFFFF))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, reg);
        emitCpuOp(store_, 0x81);
        emitModRm(store_, MODRM_REG_7, reg);
        emitValue(store_, value, std::min(opBits, Micro::OpBits::B32));
    }
    else
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Right2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeCmpMemReg(Micro::Reg memReg, uint64_t memOffset, Micro::Reg reg, Micro::OpBits opBits, EmitFlags emitFlags)
{
    if (Micro::isFloat(memReg))
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

    if (Micro::isFloat(reg))
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

EncodeResult X64Encoder::encodeCmpMemImm(Micro::Reg memReg, uint64_t memOffset, uint64_t value, Micro::OpBits opBits, EmitFlags emitFlags)
{
    if (Micro::isFloat(memReg))
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

    if (opBits == Micro::OpBits::B8)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, memReg);
        emitCpuOp(store_, 0x80);
        emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        emitValue(store_, value, Micro::OpBits::B8);
    }
    else if (canEncode8(value, opBits))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, memReg);
        emitCpuOp(store_, 0x83);
        emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        emitValue(store_, value, Micro::OpBits::B8);
    }
    else if (value <= 0x7FFFFFFF)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, memReg);
        emitCpuOp(store_, 0x81);
        emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        emitValue(store_, value, opBits == Micro::OpBits::B16 ? opBits : Micro::OpBits::B32);
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

EncodeResult X64Encoder::encodeOpUnaryMem(Micro::Reg memReg, uint64_t memOffset, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)
{
    if (Micro::isFloat(memReg))
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
    if (op == Micro::Op::BitwiseNot)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits);
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, memOffset, MODRM_REG_2, memReg);
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::Negate)
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

EncodeResult X64Encoder::encodeOpUnaryReg(Micro::Reg reg, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)
{
    if (emitFlags.has(EMIT_CAN_ENCODE))
    {
        if (Micro::isFloat(reg))
            return EncodeResult::NotSupported;
        return EncodeResult::Zero;
    }

    ///////////////////////////////////////////

    if (op == Micro::Op::BitwiseNot)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, REX_REG_NONE, reg);
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, MODRM_REG_2, reg);
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::Negate)
    {
        if (Micro::isFloat(reg))
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

    else if (op == Micro::Op::ByteSwap)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        if (opBits == Micro::OpBits::B16)
        {
            // rol ax, 0x8
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0xC1);
            emitCpuOp(store_, 0xC0);
            emitValue(store_, 0x08, Micro::OpBits::B8);
        }
        else
        {
            SWC_ASSERT(opBits == Micro::OpBits::B16 || opBits == Micro::OpBits::B32 || opBits == Micro::OpBits::B64);
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

EncodeResult X64Encoder::encodeOpBinaryRegMem(Micro::Reg regDst, Micro::Reg memReg, uint64_t memOffset, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)
{
    if (Micro::isFloat(memReg))
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
    if (op == Micro::Op::Add)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x03, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::Subtract)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x2B, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::And)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x23, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::Or)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x0B, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::Xor)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x33, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::MultiplySigned)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        if (opBits == Micro::OpBits::B8)
            emitLoadSignedExtendRegReg(regDst, regDst, Micro::OpBits::B32, opBits);
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

EncodeResult X64Encoder::encodeOpBinaryRegReg(Micro::Reg regDst, Micro::Reg regSrc, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)
{
    ///////////////////////////////////////////

    if (op == Micro::Op::ConvertUIntToFloat64)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////
    if (Micro::isFloat(regDst) && Micro::isInt(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (op != Micro::Op::ConvertIntToFloat && op != Micro::Op::ConvertUIntToFloat64)
                return EncodeResult::NotSupported;
            return EncodeResult::Zero;
        }

        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, emitFlags.has(EMIT_B64) ? Micro::OpBits::B64 : Micro::OpBits::B32, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, op);
        emitModRm(store_, regDst, regSrc);
    }

    else if (Micro::isInt(regDst) && Micro::isFloat(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (op != Micro::Op::ConvertFloatToInt)
                return EncodeResult::NotSupported;
            return EncodeResult::Zero;
        }

        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, emitFlags.has(EMIT_B64) ? Micro::OpBits::B64 : Micro::OpBits::B32, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, op);
        emitModRm(store_, regDst, regSrc);
    }

    else if (Micro::isFloat(regDst) && Micro::isFloat(regSrc))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;

        if (op != Micro::Op::FloatSqrt && op != Micro::Op::FloatAnd && op != Micro::Op::FloatXor)
        {
            emitSpecF64(store_, 0xF3, opBits);
            emitRex(store_, emitFlags.has(EMIT_B64) ? Micro::OpBits::B64 : Micro::OpBits::B32, regDst, regSrc);
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

    else if (op == Micro::Op::DivideUnsigned ||
             op == Micro::Op::DivideSigned ||
             op == Micro::Op::ModuloUnsigned ||
             op == Micro::Op::ModuloSigned)
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

        if ((op == Micro::Op::DivideSigned || op == Micro::Op::ModuloSigned) && opBits == Micro::OpBits::B8)
            emitLoadSignedExtendRegReg(rax, rax, Micro::OpBits::B32, Micro::OpBits::B8);
        else if (opBits == Micro::OpBits::B8)
            emitLoadZeroExtendRegReg(rax, rax, Micro::OpBits::B32, Micro::OpBits::B8);
        else if (op == Micro::Op::DivideUnsigned || op == Micro::Op::ModuloUnsigned)
            emitClearReg(x64Reg2CpuReg(X64Reg::Rdx), opBits);
        else
        {
            emitRex(store_, opBits);
            emitCpuOp(store_, 0x99); // cdq
        }

        emitRex(store_, opBits, rax, regSrc);
        emitSpecCpuOp(store_, 0xF7, opBits);
        if (op == Micro::Op::DivideUnsigned || op == Micro::Op::ModuloUnsigned)
            emitModRm(store_, MODRM_REG_6, regSrc);
        else if (op == Micro::Op::DivideSigned || op == Micro::Op::ModuloSigned)
            emitModRm(store_, MODRM_REG_7, regSrc);

        if ((op == Micro::Op::ModuloUnsigned || op == Micro::Op::ModuloSigned) && opBits == Micro::OpBits::B8)
            emitOpBinaryRegImm(rax, 8, Micro::Op::ShiftRight, Micro::OpBits::B32, emitFlags); // AH => AL
        else if (op == Micro::Op::ModuloUnsigned || op == Micro::Op::ModuloSigned)
            emitLoadRegReg(rax, x64Reg2CpuReg(X64Reg::Rdx), opBits);
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::MultiplyUnsigned)
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

    else if (op == Micro::Op::MultiplySigned)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;

        if (opBits == Micro::OpBits::B8)
        {
            emitLoadSignedExtendRegReg(regDst, regDst, Micro::OpBits::B32, opBits);
            emitLoadSignedExtendRegReg(regSrc, regSrc, Micro::OpBits::B32, opBits);
        }

        emitRex(store_, opBits, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xAF);
        emitModRm(store_, regDst, regSrc);
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::RotateLeft ||
             op == Micro::Op::RotateRight ||
             op == Micro::Op::ShiftArithmeticLeft ||
             op == Micro::Op::ShiftArithmeticRight ||
             op == Micro::Op::ShiftLeft ||
             op == Micro::Op::ShiftRight)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (cpuRegToX64Reg(regSrc) != X64Reg::Rcx)
            {
                SWC_ASSERT(x64Reg2CpuReg(X64Reg::Rcx) == Micro::Reg::Rcx);
                return EncodeResult::Right2Rcx;
            }

            return EncodeResult::Zero;
        }

        SWC_ASSERT(cpuRegToX64Reg(regSrc) == X64Reg::Rcx);
        emitRex(store_, opBits, REX_REG_NONE, regDst);
        emitSpecCpuOp(store_, 0xD3, opBits);
        if (op == Micro::Op::RotateLeft)
            emitModRm(store_, MODRM_REG_0, regDst);
        else if (op == Micro::Op::RotateRight)
            emitModRm(store_, MODRM_REG_1, regDst);
        else if (op == Micro::Op::ShiftArithmeticLeft || op == Micro::Op::ShiftLeft)
            emitModRm(store_, MODRM_REG_4, regDst);
        else if (op == Micro::Op::ShiftArithmeticRight)
            emitModRm(store_, MODRM_REG_7, regDst);
        else if (op == Micro::Op::ShiftRight)
            emitModRm(store_, MODRM_REG_5, regDst);
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::Add ||
             op == Micro::Op::Subtract ||
             op == Micro::Op::Xor ||
             op == Micro::Op::And ||
             op == Micro::Op::Or)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regSrc, regDst);
        emitSpecCpuOp(store_, op, opBits);
        emitModRm(store_, regSrc, regDst);
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::Exchange)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regSrc, regDst);
        emitSpecCpuOp(store_, 0x87, opBits);
        emitModRm(store_, regSrc, regDst);
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::BitScanForward || op == Micro::Op::BitScanReverse)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (opBits == Micro::OpBits::B8)
                return EncodeResult::ForceZero32;
            return EncodeResult::Zero;
        }

        emitRex(store_, opBits, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, op == Micro::Op::BitScanForward ? 0xBC : 0xBD);
        emitModRm(store_, regDst, regSrc);
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::PopCount)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (opBits == Micro::OpBits::B8)
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

EncodeResult X64Encoder::encodeOpBinaryMemReg(Micro::Reg memReg, uint64_t memOffset, Micro::Reg reg, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)
{
    if (Micro::isFloat(memReg))
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

    if (Micro::isFloat(reg))
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Left2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////
    if (op == Micro::Op::DivideUnsigned ||
        op == Micro::Op::DivideSigned ||
        op == Micro::Op::ModuloUnsigned ||
        op == Micro::Op::ModuloSigned ||
        op == Micro::Op::MultiplySigned ||
        op == Micro::Op::MultiplyUnsigned)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Left2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::ShiftArithmeticRight ||
             op == Micro::Op::ShiftRight ||
             op == Micro::Op::ShiftLeft)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (cpuRegToX64Reg(reg) != X64Reg::Rcx)
            {
                SWC_ASSERT(x64Reg2CpuReg(X64Reg::Rcx) == Micro::Reg::Rcx);
                return EncodeResult::Right2Rcx;
            }

            return EncodeResult::Zero;
        }

        if (emitFlags.has(EMIT_LOCK))
            store_.pushU8(0xF0);
        emitRex(store_, opBits, REX_REG_NONE, memReg);
        emitSpecCpuOp(store_, 0xD3, opBits);
        if (op == Micro::Op::ShiftLeft)
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
        else if (op == Micro::Op::ShiftArithmeticRight)
            emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        else if (op == Micro::Op::ShiftRight)
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

EncodeResult X64Encoder::encodeOpBinaryRegImm(Micro::Reg reg, uint64_t value, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)
{
    ///////////////////////////////////////////

    if (op == Micro::Op::Xor)
    {
        if (opBits == Micro::OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_6, reg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_6, reg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_6, reg);
            emitValue(store_, value, std::min(opBits, Micro::OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::Or)
    {
        if (opBits == Micro::OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_1, reg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_1, reg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_1, reg);
            emitValue(store_, value, std::min(opBits, Micro::OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::And)
    {
        if (opBits == Micro::OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_4, reg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_4, reg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_4, reg);
            emitValue(store_, value, std::min(opBits, Micro::OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::Add)
    {
        if (value == 1 && !emitFlags.has(EMIT_OVERFLOW) && buildParams_.optLevel >= Runtime::BuildCfgBackendOptim::O1)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitSpecCpuOp(store_, 0xFF, opBits);
            emitModRm(store_, MODRM_REG_0, reg);
        }
        else if (opBits == Micro::OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_0, reg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_0, reg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_0, reg);
            emitValue(store_, value, std::min(opBits, Micro::OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::Subtract)
    {
        if (value == 1 && !emitFlags.has(EMIT_OVERFLOW) && buildParams_.optLevel >= Runtime::BuildCfgBackendOptim::O1)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitSpecCpuOp(store_, 0xFF, opBits);
            emitModRm(store_, MODRM_REG_1, reg);
        }
        else if (opBits == Micro::OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_5, reg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_5, reg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_5, reg);
            emitValue(store_, value, std::min(opBits, Micro::OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::ModuloUnsigned ||
             op == Micro::Op::ModuloSigned ||
             op == Micro::Op::DivideUnsigned ||
             op == Micro::Op::DivideSigned ||
             op == Micro::Op::MultiplyUnsigned)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Right2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::MultiplySigned)
    {
        if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            if (opBits == Micro::OpBits::B8)
                emitLoadSignedExtendRegReg(reg, reg, Micro::OpBits::B32, opBits);
            emitRex(store_, opBits, reg, reg);
            emitCpuOp(store_, 0x6B);
            emitModRm(store_, reg, reg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            if (opBits == Micro::OpBits::B8 || opBits == Micro::OpBits::B16)
                emitLoadSignedExtendRegReg(reg, reg, Micro::OpBits::B32, opBits);
            emitRex(store_, opBits, reg, reg);
            emitCpuOp(store_, 0x69);
            emitModRm(store_, reg, reg);
            emitValue(store_, value, Micro::OpBits::B32);
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::ShiftLeft)
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
            emitValue(store_, std::min(static_cast<uint32_t>(value), Micro::getNumBits(opBits) - 1), Micro::OpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::ShiftRight)
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
            emitValue(store_, std::min(static_cast<uint32_t>(value), Micro::getNumBits(opBits) - 1), Micro::OpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::ShiftArithmeticRight)
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
            emitValue(store_, std::min(static_cast<uint32_t>(value), Micro::getNumBits(opBits) - 1), Micro::OpBits::B8);
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

EncodeResult X64Encoder::encodeOpBinaryMemImm(Micro::Reg memReg, uint64_t memOffset, uint64_t value, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)
{
    if (Micro::isFloat(memReg))
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

    if (op == Micro::Op::ModuloSigned ||
        op == Micro::Op::ModuloUnsigned ||
        op == Micro::Op::DivideUnsigned ||
        op == Micro::Op::DivideSigned ||
        op == Micro::Op::MultiplySigned ||
        op == Micro::Op::MultiplyUnsigned)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
            return EncodeResult::Right2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////
    if (op == Micro::Op::ShiftArithmeticRight)
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
            emitValue(store_, std::min(static_cast<uint32_t>(value), Micro::getNumBits(opBits) - 1), Micro::OpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::ShiftRight)
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
            emitValue(store_, std::min(static_cast<uint32_t>(value), Micro::getNumBits(opBits) - 1), Micro::OpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::ShiftLeft)
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
            emitValue(store_, std::min(static_cast<uint32_t>(value), Micro::getNumBits(opBits) - 1), Micro::OpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::Add)
    {
        if (value == 1 && !emitFlags.has(EMIT_OVERFLOW) && buildParams_.optLevel >= Runtime::BuildCfgBackendOptim::O1)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitSpecCpuOp(store_, 0xFF, opBits);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
        }
        else if (opBits == Micro::OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
            emitValue(store_, value, std::min(opBits, Micro::OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::Subtract)
    {
        if (value == 1 && !emitFlags.has(EMIT_OVERFLOW) && buildParams_.optLevel >= Runtime::BuildCfgBackendOptim::O1)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitSpecCpuOp(store_, 0xFF, opBits);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
        }
        else if (opBits == Micro::OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
            emitValue(store_, value, std::min(opBits, Micro::OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::Or)
    {
        if (opBits == Micro::OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
            emitValue(store_, value, std::min(opBits, Micro::OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::And)
    {
        if (opBits == Micro::OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
            emitValue(store_, value, std::min(opBits, Micro::OpBits::B32));
        }
        else
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::Xor)
    {
        if (opBits == Micro::OpBits::B8)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_6, memReg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_6, memReg);
            emitValue(store_, value, Micro::OpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EMIT_CAN_ENCODE))
                return EncodeResult::Zero;
            emitRex(store_, opBits, REX_REG_NONE, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_6, memReg);
            emitValue(store_, value, std::min(opBits, Micro::OpBits::B32));
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

EncodeResult X64Encoder::encodeOpTernaryRegRegReg(Micro::Reg reg0, Micro::Reg reg1, Micro::Reg reg2, Micro::Op op, Micro::OpBits opBits, EmitFlags emitFlags)
{
    ///////////////////////////////////////////

    if (op == Micro::Op::MultiplyAdd)
    {
        if (emitFlags.has(EMIT_CAN_ENCODE))
        {
            if (Micro::isFloat(reg0) != Micro::isFloat(reg1) || Micro::isFloat(reg0) != Micro::isFloat(reg2))
                return EncodeResult::NotSupported;
            if (!Micro::isFloat(reg0))
                return EncodeResult::NotSupported;
            return EncodeResult::Zero;
        }

        SWC_ASSERT(Micro::isFloat(reg0) && Micro::isFloat(reg1) && Micro::isFloat(reg2));
        emitSpecF64(store_, 0xF3, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, Micro::Op::FloatMultiply);
        emitModRm(store_, reg0, reg1);

        emitSpecF64(store_, 0xF3, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, Micro::Op::FloatAdd);
        emitModRm(store_, reg0, reg2);
    }

    ///////////////////////////////////////////

    else if (op == Micro::Op::CompareExchange)
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

EncodeResult X64Encoder::encodeJumpTable(Micro::Reg tableReg, Micro::Reg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EmitFlags emitFlags)
{
    const auto [offsetTableConstant, addrConstant] = buildParams_.module->constantSegment.reserveSpan<uint32_t>(numEntries);
    emitLoadSymRelocAddress(tableReg, symCsIndex_, offsetTableConstant);

    // 'movsxd' table, dword ptr [table + offset*4]
    encodeAmcReg(store_, tableReg, Micro::OpBits::B64, tableReg, offsetReg, 4, 0, Micro::OpBits::B64, Micro::Op::MoveSignExtend, emitFlags, false);

    const auto startIdx = store_.size();
    emitLoadSymRelocAddress(offsetReg, cpuFct_->symbolIndex, store_.size() - cpuFct_->startAddress);
    const auto patchPtr = reinterpret_cast<uint32_t*>(store_.seekPtr()) - 1;
    emitOpBinaryRegReg(offsetReg, tableReg, Micro::Op::Add, Micro::OpBits::B64, emitFlags);
    emitJumpReg(offsetReg);
    const auto endIdx = store_.size();
    *patchPtr += endIdx - startIdx;

    const auto tableCompiler = buildParams_.module->compilerSegment.ptr<int32_t>(offsetTable);
    const auto currentOffset = static_cast<int32_t>(store_.size());

    Micro::LabelToSolve label;
    for (uint32_t idx = 0; idx < numEntries; idx++)
    {
        label.ipDest               = tableCompiler[idx] + currentIp + 1;
        label.jump.opBits          = Micro::OpBits::B32;
        label.jump.offsetStart     = currentOffset;
        label.jump.patchOffsetAddr = addrConstant + idx;
        cpuFct_->labelsToSolve.push_back(label);
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeJump(Micro::Jump& jump, Micro::CondJump jumpType, Micro::OpBits opBits, EmitFlags emitFlags)
{
    SWC_ASSERT(opBits == Micro::OpBits::B8 || opBits == Micro::OpBits::B32);

    if (opBits == Micro::OpBits::B8)
    {
        switch (jumpType)
        {
            case Micro::CondJump::NotOverflow:
                emitCpuOp(store_, 0x71);
                break;
            case Micro::CondJump::Below:
                emitCpuOp(store_, 0x72);
                break;
            case Micro::CondJump::AboveOrEqual:
                emitCpuOp(store_, 0x73);
                break;
            case Micro::CondJump::Zero:
                emitCpuOp(store_, 0x74);
                break;
            case Micro::CondJump::NotZero:
                emitCpuOp(store_, 0x75);
                break;
            case Micro::CondJump::BelowOrEqual:
                emitCpuOp(store_, 0x76);
                break;
            case Micro::CondJump::Above:
                store_.pushU8(0x77);
                break;
            case Micro::CondJump::Sign:
                emitCpuOp(store_, 0x78);
                break;
            case Micro::CondJump::Parity:
                emitCpuOp(store_, 0x7A);
                break;
            case Micro::CondJump::NotParity:
                emitCpuOp(store_, 0x7B);
                break;
            case Micro::CondJump::Less:
                emitCpuOp(store_, 0x7C);
                break;
            case Micro::CondJump::GreaterOrEqual:
                emitCpuOp(store_, 0x7D);
                break;
            case Micro::CondJump::LessOrEqual:
                emitCpuOp(store_, 0x7E);
                break;
            case Micro::CondJump::Greater:
                emitCpuOp(store_, 0x7F);
                break;
            case Micro::CondJump::Unconditional:
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
        case Micro::CondJump::NotOverflow:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x81);
            break;
        case Micro::CondJump::Below:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x82);
            break;
        case Micro::CondJump::AboveOrEqual:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x83);
            break;
        case Micro::CondJump::Zero:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x84);
            break;
        case Micro::CondJump::NotZero:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x85);
            break;
        case Micro::CondJump::BelowOrEqual:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x86);
            break;
        case Micro::CondJump::Above:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x87);
            break;
        case Micro::CondJump::Parity:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8A);
            break;
        case Micro::CondJump::Sign:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x88);
            break;
        case Micro::CondJump::NotParity:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8B);
            break;
        case Micro::CondJump::Less:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8C);
            break;
        case Micro::CondJump::GreaterOrEqual:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8D);
            break;
        case Micro::CondJump::LessOrEqual:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8E);
            break;
        case Micro::CondJump::Greater:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8F);
            break;
        case Micro::CondJump::Unconditional:
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

EncodeResult X64Encoder::encodePatchJump(const Micro::Jump& jump, uint64_t offsetDestination, EmitFlags emitFlags)
{
    const int32_t offset = static_cast<int32_t>(offsetDestination - jump.offsetStart);
    if (jump.opBits == Micro::OpBits::B8)
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

EncodeResult X64Encoder::encodePatchJump(const Micro::Jump& jump, EmitFlags emitFlags)
{
    return encodePatchJump(jump, store_.size(), emitFlags);
}

EncodeResult X64Encoder::encodeJumpReg(Micro::Reg reg, EmitFlags emitFlags)
{
    emitRex(store_, Micro::OpBits::Zero, REX_REG_NONE, reg);
    emitCpuOp(store_, 0xFF);
    emitModRm(store_, ModRmMode::Register, MODRM_REG_4, encodeReg(reg));
    return EncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeCallExtern(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)
{
    emitCpuOp(store_, 0xFF);
    emitModRm(store_, ModRmMode::Memory, MODRM_REG_2, MODRM_RM_RIP);

    const auto callSym = getOrAddSymbol(symbolName, Micro::SymbolKind::Extern);
    addSymbolRelocation(store_.size() - textSectionOffset_, callSym->index, IMAGE_REL_AMD64_REL32);
    store_.pushU32(0);
    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeCallLocal(IdentifierRef symbolName, const CallConv* callConv, EmitFlags emitFlags)
{
    emitCpuOp(store_, 0xE8);

    const auto callSym = getOrAddSymbol(symbolName, Micro::SymbolKind::Extern);
    if (callSym->kind == Micro::SymbolKind::Function)
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

EncodeResult X64Encoder::encodeCallReg(Micro::Reg reg, const CallConv* callConv, EmitFlags emitFlags)
{
    emitRex(store_, Micro::OpBits::Zero, REX_REG_NONE, reg);
    emitCpuOp(store_, 0xFF);
    emitModRm(store_, MODRM_REG_2, reg);
    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeNop(EmitFlags emitFlags)
{
    emitCpuOp(store_, 0x90);
    return EncodeResult::Zero;
}

Micro::RegSet X64Encoder::getReadRegisters(const MicroInstruction& inst)
{
    auto result = Encoder::getReadRegisters(inst);

    if (inst.op == MicroInstructionKind::OpBinaryRI ||
        inst.op == MicroInstructionKind::OpBinaryRR ||
        inst.op == MicroInstructionKind::OpBinaryMI ||
        inst.op == MicroInstructionKind::OpBinaryRM ||
        inst.op == MicroInstructionKind::OpBinaryMR)
    {
        auto cpuOp = Micro::Op::Add;
        switch (inst.op)
        {
            case MicroInstructionKind::OpBinaryRI:
                cpuOp = inst.ops[2].cpuOp;
                break;
            case MicroInstructionKind::OpBinaryRR:
                cpuOp = inst.ops[3].cpuOp;
                break;
            case MicroInstructionKind::OpBinaryMI:
                cpuOp = inst.ops[2].cpuOp;
                break;
            case MicroInstructionKind::OpBinaryRM:
            case MicroInstructionKind::OpBinaryMR:
                cpuOp = inst.ops[3].cpuOp;
                break;
            default:
                break;
        }

        if (cpuOp == Micro::Op::RotateLeft ||
            cpuOp == Micro::Op::RotateRight ||
            cpuOp == Micro::Op::ShiftArithmeticLeft ||
            cpuOp == Micro::Op::ShiftArithmeticRight ||
            cpuOp == Micro::Op::ShiftLeft ||
            cpuOp == Micro::Op::ShiftRight)
        {
            result.add(x64Reg2CpuReg(X64Reg::Rcx));
        }
        else if (cpuOp == Micro::Op::MultiplyUnsigned ||
                 cpuOp == Micro::Op::DivideUnsigned ||
                 cpuOp == Micro::Op::ModuloUnsigned ||
                 cpuOp == Micro::Op::DivideSigned ||
                 cpuOp == Micro::Op::ModuloSigned)
        {
            result.add(x64Reg2CpuReg(X64Reg::Rdx));
        }
    }

    return result;
}

Micro::RegSet X64Encoder::getWriteRegisters(const MicroInstruction& inst)
{
    auto result = Encoder::getWriteRegisters(inst);

    if (inst.op == MicroInstructionKind::OpBinaryRI ||
        inst.op == MicroInstructionKind::OpBinaryRR ||
        inst.op == MicroInstructionKind::OpBinaryMI ||
        inst.op == MicroInstructionKind::OpBinaryRM ||
        inst.op == MicroInstructionKind::OpBinaryMR)
    {
        auto cpuOp = Micro::Op::Add;
        switch (inst.op)
        {
            case MicroInstructionKind::OpBinaryRI:
                cpuOp = inst.ops[2].cpuOp;
                break;
            case MicroInstructionKind::OpBinaryRR:
                cpuOp = inst.ops[3].cpuOp;
                break;
            case MicroInstructionKind::OpBinaryMI:
                cpuOp = inst.ops[2].cpuOp;
                break;
            case MicroInstructionKind::OpBinaryRM:
            case MicroInstructionKind::OpBinaryMR:
                cpuOp = inst.ops[3].cpuOp;
                break;
            default:
                break;
        }

        if (cpuOp == Micro::Op::MultiplyUnsigned ||
            cpuOp == Micro::Op::DivideUnsigned ||
            cpuOp == Micro::Op::ModuloUnsigned ||
            cpuOp == Micro::Op::DivideSigned ||
            cpuOp == Micro::Op::ModuloSigned)
        {
            result.add(x64Reg2CpuReg(X64Reg::Rdx));
        }
    }

    return result;
}

SWC_END_NAMESPACE();


