#include "pch.h"
#include "Backend/MachineCode/Encoder/X64Encoder.h"
#include "Backend/MachineCode/Micro/MicroInstr.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

enum class ModRmMode : uint8_t
{
    Memory         = 0b00,
    Displacement8  = 0b01,
    Displacement32 = 0b10,
    Register       = 0b11,
};

constexpr uint8_t MODRM_REG_0 = 0;
constexpr uint8_t MODRM_REG_1 = 1;
constexpr uint8_t MODRM_REG_2 = 2;
constexpr uint8_t MODRM_REG_3 = 3;
constexpr uint8_t MODRM_REG_4 = 4;
constexpr uint8_t MODRM_REG_5 = 5;
constexpr uint8_t MODRM_REG_6 = 6;
constexpr uint8_t MODRM_REG_7 = 7;

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
    constexpr X64Reg K_INT_REG_MAP[] = {
        X64Reg::Rax,
        X64Reg::Rbx,
        X64Reg::Rcx,
        X64Reg::Rdx,
        X64Reg::Rsp,
        X64Reg::Rbp,
        X64Reg::Rsi,
        X64Reg::Rdi,
        X64Reg::R8,
        X64Reg::R9,
        X64Reg::R10,
        X64Reg::R11,
        X64Reg::R12,
        X64Reg::R13,
        X64Reg::R14,
        X64Reg::R15,
    };

    constexpr X64Reg K_FLOAT_REG_MAP[] = {
        X64Reg::Xmm0,
        X64Reg::Xmm1,
        X64Reg::Xmm2,
        X64Reg::Xmm3,
    };

    constexpr size_t K_INT_REG_COUNT   = std::size(K_INT_REG_MAP);
    constexpr size_t K_FLOAT_REG_COUNT = std::size(K_FLOAT_REG_MAP);

    MicroReg x64RegToMicroReg(X64Reg reg)
    {
        switch (reg)
        {
            case X64Reg::Rax:
                return MicroReg::intReg(0);
            case X64Reg::Rbx:
                return MicroReg::intReg(1);
            case X64Reg::Rcx:
                return MicroReg::intReg(2);
            case X64Reg::Rdx:
                return MicroReg::intReg(3);
            case X64Reg::Rsp:
                return MicroReg::intReg(4);
            case X64Reg::Rbp:
                return MicroReg::intReg(5);
            case X64Reg::Rsi:
                return MicroReg::intReg(6);
            case X64Reg::Rdi:
                return MicroReg::intReg(7);
            case X64Reg::R8:
                return MicroReg::intReg(8);
            case X64Reg::R9:
                return MicroReg::intReg(9);
            case X64Reg::R10:
                return MicroReg::intReg(10);
            case X64Reg::R11:
                return MicroReg::intReg(11);
            case X64Reg::R12:
                return MicroReg::intReg(12);
            case X64Reg::R13:
                return MicroReg::intReg(13);
            case X64Reg::R14:
                return MicroReg::intReg(14);
            case X64Reg::R15:
                return MicroReg::intReg(15);
            case X64Reg::Xmm0:
                return MicroReg::floatReg(0);
            case X64Reg::Xmm1:
                return MicroReg::floatReg(1);
            case X64Reg::Xmm2:
                return MicroReg::floatReg(2);
            case X64Reg::Xmm3:
                return MicroReg::floatReg(3);
            case X64Reg::Rip:
                return MicroReg::instructionPointer();
            default:
                SWC_ASSERT(false);
                return MicroReg::invalid();
        }
    }

    X64Reg microRegToX64Reg(MicroReg reg)
    {
        if (reg.isInstructionPointer())
            return X64Reg::Rip;

        if (reg.isInt())
        {
            SWC_ASSERT(reg.index() < K_INT_REG_COUNT);
            return K_INT_REG_MAP[reg.index()];
        }

        if (reg.isFloat())
        {
            SWC_ASSERT(reg.index() < K_FLOAT_REG_COUNT);
            return K_FLOAT_REG_MAP[reg.index()];
        }

        SWC_ASSERT(false);
        return X64Reg::Rax;
    }

    bool isExtendedReg(X64Reg reg)
    {
        return (static_cast<uint8_t>(reg) & 0b001000) != 0;
    }

    bool needsRexForByteReg(X64Reg reg)
    {
        return reg == X64Reg::Rsi || reg == X64Reg::Rdi || reg == X64Reg::Rsp || reg == X64Reg::Rbp;
    }

    uint8_t encodeReg(X64Reg reg)
    {
        return static_cast<uint8_t>(reg) & 0b111;
    }

    uint8_t encodeReg(MicroReg reg)
    {
        return encodeReg(microRegToX64Reg(reg));
    }

    bool canEncode8(uint64_t value, MicroOpBits opBits)
    {
        return value <= 0x7F ||
               (opBits == MicroOpBits::B16 && value >= 0xFF80) ||
               (opBits == MicroOpBits::B32 && value >= 0xFFFFFF80) ||
               (opBits == MicroOpBits::B64 && value >= 0xFFFFFFFFFFFFFF80);
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

    uint8_t getModRm(ModRmMode mod, uint8_t reg, uint8_t rm)
    {
        const auto result = static_cast<uint32_t>(mod) << 6 | ((reg & 0b111) << 3) | (rm & 0b111);
        return static_cast<uint8_t>(result);
    }

    void emitPrefixF64(PagedStore& store, MicroOpBits opBits)
    {
        if (opBits == MicroOpBits::B64)
            store.pushU8(0x66);
    }

    void emitSib(PagedStore& store, uint8_t scale, uint8_t index, uint8_t base)
    {
        const uint8_t value = static_cast<uint8_t>(scale << 6) | static_cast<uint8_t>(index << 3) | base;
        store.pushU8(value);
    }

    void emitRex(PagedStore& store, MicroOpBits opBits, MicroReg reg0 = {}, MicroReg reg1 = {})
    {
        if (opBits == MicroOpBits::B16)
            store.pushU8(0x66);

        const bool hasReg0 = reg0.isValid() && !reg0.isNoBase();
        const bool hasReg1 = reg1.isValid() && !reg1.isNoBase();

        const auto x64Reg0 = hasReg0 ? microRegToX64Reg(reg0) : X64Reg::Rax;
        const auto x64Reg1 = hasReg1 ? microRegToX64Reg(reg1) : X64Reg::Rax;

        const bool b1 = hasReg0 && isExtendedReg(x64Reg0);
        const bool b2 = hasReg1 && isExtendedReg(x64Reg1);
        if (opBits == MicroOpBits::B64 ||
            b1 || b2 ||
            (hasReg0 && needsRexForByteReg(x64Reg0)) ||
            (hasReg1 && needsRexForByteReg(x64Reg1)))
        {
            const auto value = getRex(opBits == MicroOpBits::B64, b1, false, b2);
            store.pushU8(value);
        }
    }

    void emitValue(PagedStore& store, uint64_t value, MicroOpBits opBits)
    {
        if (opBits == MicroOpBits::B8)
            store.pushU8(static_cast<uint8_t>(value));
        else if (opBits == MicroOpBits::B16)
            store.pushU16(static_cast<uint16_t>(value));
        else if (opBits == MicroOpBits::B32)
            store.pushU32(static_cast<uint32_t>(value));
        else
            store.pushU64(value);
    }

    void emitModRm(PagedStore& store, ModRmMode mod, uint8_t reg, uint8_t rm)
    {
        const auto value = getModRm(mod, reg, rm);
        store.pushU8(value);
    }

    void emitModRm(PagedStore& store, ModRmMode mod, MicroReg reg, uint8_t rm)
    {
        emitModRm(store, mod, encodeReg(reg), rm);
    }

    void emitModRm(PagedStore& store, uint8_t reg, MicroReg rm)
    {
        emitModRm(store, ModRmMode::Register, reg, encodeReg(rm));
    }

    void emitModRm(PagedStore& store, MicroReg reg, MicroReg memReg)
    {
        emitModRm(store, ModRmMode::Register, encodeReg(reg), encodeReg(memReg));
    }

    void emitModRm(PagedStore& store, uint64_t memOffset, uint8_t reg, MicroReg memReg)
    {
        const auto memX64 = microRegToX64Reg(memReg);

        if (memOffset == 0 && memX64 != X64Reg::R13 && memX64 != X64Reg::Rbp)
        {
            if (memX64 == X64Reg::Rsp || memX64 == X64Reg::R12)
            {
                const auto modRm = getModRm(ModRmMode::Memory, reg, MODRM_RM_SIB);
                store.pushU8(modRm);
                emitSib(store, 0, MODRM_RM_SIB, encodeReg(memX64) & 0b111);
            }
            else
            {
                const auto modRm = getModRm(ModRmMode::Memory, reg, encodeReg(memX64));
                store.pushU8(modRm);
            }
        }
        else if (memOffset <= 0x7F)
        {
            if (memX64 == X64Reg::Rsp || memX64 == X64Reg::R12)
            {
                const auto modRm = getModRm(ModRmMode::Displacement8, reg, MODRM_RM_SIB);
                store.pushU8(modRm);
                emitSib(store, 0, MODRM_RM_SIB, encodeReg(memX64) & 0b111);
            }
            else
            {
                const auto modRm = getModRm(ModRmMode::Displacement8, reg, encodeReg(memX64));
                store.pushU8(modRm);
            }

            emitValue(store, memOffset, MicroOpBits::B8);
        }
        else
        {
            if (memX64 == X64Reg::Rsp || memX64 == X64Reg::R12)
            {
                const auto modRm = getModRm(ModRmMode::Displacement32, reg, MODRM_RM_SIB);
                store.pushU8(modRm);
                emitSib(store, 0, MODRM_RM_SIB, encodeReg(memX64) & 0b111);
            }
            else
            {
                const auto modRm = getModRm(ModRmMode::Displacement32, reg, encodeReg(memX64));
                store.pushU8(modRm);
            }

            SWC_ASSERT(memOffset <= 0x7FFFFFFF);
            emitValue(store, memOffset, MicroOpBits::B32);
        }
    }

    void emitModRm(PagedStore& store, uint64_t memOffset, MicroReg reg, MicroReg memReg)
    {
        const auto memX64 = microRegToX64Reg(memReg);

        if (memOffset == 0 && memX64 != X64Reg::R13 && memX64 != X64Reg::Rbp)
        {
            if (memX64 == X64Reg::Rsp || memX64 == X64Reg::R12)
            {
                const auto modRm = getModRm(ModRmMode::Memory, encodeReg(reg), MODRM_RM_SIB);
                store.pushU8(modRm);
                emitSib(store, 0, MODRM_RM_SIB, encodeReg(memX64) & 0b111);
            }
            else
            {
                const auto modRm = getModRm(ModRmMode::Memory, encodeReg(reg), encodeReg(memX64));
                store.pushU8(modRm);
            }
        }
        else if (memOffset <= 0x7F)
        {
            if (memX64 == X64Reg::Rsp || memX64 == X64Reg::R12)
            {
                const auto modRm = getModRm(ModRmMode::Displacement8, encodeReg(reg), MODRM_RM_SIB);
                store.pushU8(modRm);
                emitSib(store, 0, MODRM_RM_SIB, encodeReg(memX64) & 0b111);
            }
            else
            {
                const auto modRm = getModRm(ModRmMode::Displacement8, encodeReg(reg), encodeReg(memX64));
                store.pushU8(modRm);
            }

            emitValue(store, memOffset, MicroOpBits::B8);
        }
        else
        {
            if (memX64 == X64Reg::Rsp || memX64 == X64Reg::R12)
            {
                const auto modRm = getModRm(ModRmMode::Displacement32, encodeReg(reg), MODRM_RM_SIB);
                store.pushU8(modRm);
                emitSib(store, 0, MODRM_RM_SIB, encodeReg(memX64) & 0b111);
            }
            else
            {
                const auto modRm = getModRm(ModRmMode::Displacement32, encodeReg(reg), encodeReg(memX64));
                store.pushU8(modRm);
            }

            SWC_ASSERT(memOffset <= 0x7FFFFFFF);
            emitValue(store, memOffset, MicroOpBits::B32);
        }
    }

    void emitSpecB8(PagedStore& store, uint8_t value, MicroOpBits opBits)
    {
        if (opBits == MicroOpBits::B8)
            store.pushU8(value & ~1);
        else
            store.pushU8(value);
    }

    void emitSpecF64(PagedStore& store, uint8_t value, MicroOpBits opBits)
    {
        if (opBits == MicroOpBits::B64)
            store.pushU8(value & ~1);
        else if (opBits == MicroOpBits::B32)
            store.pushU8(value);
    }

    uint8_t getX64OpCode(MicroOp op)
    {
        switch (op)
        {
            case MicroOp::Add:
                return 0x01;
            case MicroOp::Or:
                return 0x09;
            case MicroOp::And:
                return 0x21;
            case MicroOp::Subtract:
                return 0x29;
            case MicroOp::ConvertIntToFloat:
                return 0x2A;
            case MicroOp::ConvertUIntToFloat64:
                return 0x2B;
            case MicroOp::ConvertFloatToInt:
                return 0x2C;
            case MicroOp::Xor:
                return 0x31;
            case MicroOp::FloatSqrt:
                return 0x51;
            case MicroOp::FloatAnd:
                return 0x54;
            case MicroOp::FloatXor:
                return 0x57;
            case MicroOp::FloatAdd:
                return 0x58;
            case MicroOp::FloatMultiply:
                return 0x59;
            case MicroOp::ConvertFloatToFloat:
                return 0x5A;
            case MicroOp::FloatSubtract:
                return 0x5C;
            case MicroOp::FloatMin:
                return 0x5D;
            case MicroOp::FloatDivide:
                return 0x5E;
            case MicroOp::FloatMax:
                return 0x5F;
            case MicroOp::MoveSignExtend:
                return 0x63;
            case MicroOp::Exchange:
                return 0x87;
            case MicroOp::Move:
                return 0x8B;
            case MicroOp::LoadEffectiveAddress:
                return 0x8D;
            case MicroOp::Negate:
                return 0x9F;
            case MicroOp::ByteSwap:
                return 0xB0;
            case MicroOp::PopCount:
                return 0xB8;
            case MicroOp::BitScanForward:
                return 0xBC;
            case MicroOp::BitScanReverse:
                return 0xBD;
            case MicroOp::MultiplyUnsigned:
                return 0xC0;
            case MicroOp::MultiplySigned:
                return 0xC1;
            case MicroOp::RotateLeft:
                return 0xC7;
            case MicroOp::RotateRight:
                return 0xC8;
            case MicroOp::ShiftLeft:
                return 0xE0;
            case MicroOp::ShiftRight:
                return 0xE8;
            case MicroOp::ShiftArithmeticLeft:
                return 0xF0;
            case MicroOp::DivideUnsigned:
                return 0xF1;
            case MicroOp::ModuloUnsigned:
                return 0xF3;
            case MicroOp::BitwiseNot:
                return 0xF7;
            case MicroOp::ShiftArithmeticRight:
                return 0xF8;
            case MicroOp::DivideSigned:
                return 0xF9;
            case MicroOp::CompareExchange:
                return 0xFA;
            case MicroOp::ModuloSigned:
                return 0xFB;
            case MicroOp::MultiplyAdd:
                return 0xFC;
            default:
                SWC_ASSERT(false);
                return 0;
        }
    }

    void emitCpuOp(PagedStore& store, MicroOp op)
    {
        store.pushU8(getX64OpCode(op));
    }

    void emitCpuOp(PagedStore& store, uint8_t op)
    {
        store.pushU8(op);
    }

    void emitCpuOp(PagedStore& store, uint8_t op, MicroReg reg)
    {
        store.pushU8(op | (encodeReg(reg) & 0b111));
    }

    void emitSpecCpuOp(PagedStore& store, MicroOp op, MicroOpBits opBits)
    {
        emitSpecB8(store, getX64OpCode(op), opBits);
    }

    void emitSpecCpuOp(PagedStore& store, uint8_t op, MicroOpBits opBits)
    {
        emitSpecB8(store, op, opBits);
    }
}

/////////////////////////////////////////////////////////////////////

void X64Encoder::updateRegUseDef(const MicroInstr& inst, const MicroInstrOperand* ops, MicroInstrUseDef& info) const
{
    if (!ops)
        return;

    auto microOp = MicroOp::Add;
    switch (inst.op)
    {
        case MicroInstrOpcode::OpBinaryRegReg:
        case MicroInstrOpcode::OpBinaryRegMem:
        case MicroInstrOpcode::OpBinaryMemReg:
            microOp = ops[3].microOp;
            break;
        case MicroInstrOpcode::OpBinaryRegImm:
        case MicroInstrOpcode::OpBinaryMemImm:
            microOp = ops[2].microOp;
            break;
        default:
            return;
    }

    switch (microOp)
    {
        case MicroOp::RotateLeft:
        case MicroOp::RotateRight:
        case MicroOp::ShiftArithmeticLeft:
        case MicroOp::ShiftArithmeticRight:
        case MicroOp::ShiftLeft:
        case MicroOp::ShiftRight:
            info.addUse(x64RegToMicroReg(X64Reg::Rcx));
            break;
        case MicroOp::MultiplyUnsigned:
        case MicroOp::DivideUnsigned:
        case MicroOp::ModuloUnsigned:
        case MicroOp::DivideSigned:
        case MicroOp::ModuloSigned:
            info.addUse(x64RegToMicroReg(X64Reg::Rdx));
            info.addDef(x64RegToMicroReg(X64Reg::Rdx));
            break;
        default:
            break;
    }
}

EncodeResult X64Encoder::encodeLoadSymbolRelocAddress(MicroReg reg, uint32_t symbolIndex, uint32_t offset, EncodeFlags emitFlags)
{
    emitRex(store_, MicroOpBits::B64, reg);
    emitCpuOp(store_, 0x8D); // LEA
    emitModRm(store_, ModRmMode::Memory, reg, MODRM_RM_RIP);
    addSymbolRelocation(store_.size() - textSectionOffset_, symbolIndex, IMAGE_REL_AMD64_REL32);
    store_.pushU32(offset);
    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeLoadSymRelocValue(MicroReg reg, uint32_t symbolIndex, uint32_t offset, MicroOpBits opBits, EncodeFlags emitFlags)
{
    if (reg.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitSpecF64(store_, 0xF3, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x10);
        emitModRm(store_, ModRmMode::Memory, reg, MODRM_RM_RIP);
        addSymbolRelocation(store_.size() - textSectionOffset_, symbolIndex, IMAGE_REL_AMD64_REL32);
        store_.pushU32(offset);
    }
    else if (emitFlags.has(EncodeFlagsE::B64))
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        SWC_ASSERT(opBits == MicroOpBits::B64);
        emitRex(store_, opBits, MicroReg{}, reg);
        emitCpuOp(store_, 0xB8, reg); // MOV
        addSymbolRelocation(store_.size() - textSectionOffset_, symbolIndex, IMAGE_REL_AMD64_ADDR64);
        store_.pushU64(offset);
    }
    else
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        SWC_ASSERT(opBits == MicroOpBits::B64);
        emitRex(store_, opBits, reg);
        emitCpuOp(store_, 0x8B); // MOV
        emitModRm(store_, ModRmMode::Memory, reg, MODRM_RM_RIP);
        addSymbolRelocation(store_.size() - textSectionOffset_, symbolIndex, IMAGE_REL_AMD64_REL32);
        store_.pushU32(offset);
    }

    return EncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodePush(MicroReg reg, EncodeFlags emitFlags)
{
    emitRex(store_, MicroOpBits::Zero, MicroReg{}, reg);
    emitCpuOp(store_, 0x50, reg);
    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodePop(MicroReg reg, EncodeFlags emitFlags)
{
    emitRex(store_, MicroOpBits::Zero, MicroReg{}, reg);
    emitCpuOp(store_, 0x58, reg);
    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeRet(EncodeFlags emitFlags)
{
    emitCpuOp(store_, 0xC3);
    return EncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits, EncodeFlags emitFlags)
{
    if (regDst.isFloat() && regSrc.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitSpecF64(store_, 0xF3, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x10);
        emitModRm(store_, regDst, regSrc);
    }
    else if (regDst.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitPrefixF64(store_, MicroOpBits::B64);
        emitRex(store_, opBits, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x6E);
        emitModRm(store_, regDst, regSrc);
    }
    else if (regSrc.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitPrefixF64(store_, MicroOpBits::B64);
        emitRex(store_, opBits, regSrc, regDst);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x7E);
        emitModRm(store_, regSrc, regDst);
    }
    else
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regSrc, regDst);
        emitSpecCpuOp(store_, 0x89, opBits);
        emitModRm(store_, regSrc, regDst);
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    if (reg.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Right2Cst;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (opBits == MicroOpBits::B8)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits, MicroReg{}, reg);
        emitCpuOp(store_, 0xB0, reg);
        emitValue(store_, value, opBits);
    }
    else
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits, MicroReg{}, reg);
        emitCpuOp(store_, 0xB8, reg);
        emitValue(store_, value, opBits);
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags)
{
    if (memReg.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (reg.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, MicroOpBits::Zero, reg, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x10);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits, reg, memReg);
        emitSpecCpuOp(store_, 0x8B, opBits);
        emitModRm(store_, memOffset, reg, memReg);
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);

    if (memReg.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (numBitsSrc == MicroOpBits::B8 && (numBitsDst == MicroOpBits::B32 || numBitsDst == MicroOpBits::B64))
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, reg, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB6);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else if (numBitsSrc == MicroOpBits::B16 && (numBitsDst == MicroOpBits::B32 || numBitsDst == MicroOpBits::B64))
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, reg, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB7);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else if (numBitsSrc == MicroOpBits::B32 && numBitsDst == MicroOpBits::B64)
    {
        return encodeLoadRegMem(reg, memReg, memOffset, numBitsSrc, emitFlags);
    }
    else
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);

    if (regDst.isFloat() || regSrc.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (numBitsSrc == MicroOpBits::B8 && (numBitsDst == MicroOpBits::B32 || numBitsDst == MicroOpBits::B64))
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB6);
        emitModRm(store_, regDst, regSrc);
    }
    else if (numBitsSrc == MicroOpBits::B16 && (numBitsDst == MicroOpBits::B32 || numBitsDst == MicroOpBits::B64))
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, MicroOpBits::B64, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB7);
        emitModRm(store_, regDst, regSrc);
    }
    else if (numBitsSrc == MicroOpBits::B32 && numBitsDst == MicroOpBits::B64)
    {
        return encodeLoadRegReg(regDst, regSrc, numBitsSrc, emitFlags);
    }
    else
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);

    if (memReg.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (numBitsSrc == MicroOpBits::B8)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, reg, memReg);
        store_.pushU8(0x0F);
        store_.pushU8(0xBE);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else if (numBitsSrc == MicroOpBits::B16)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, reg, memReg);
        store_.pushU8(0x0F);
        store_.pushU8(0xBF);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else if (numBitsSrc == MicroOpBits::B32)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        SWC_ASSERT(numBitsDst == MicroOpBits::B64);
        emitRex(store_, MicroOpBits::B64, reg, memReg);
        emitCpuOp(store_, 0x63);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc, EncodeFlags emitFlags)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);

    if (regDst.isFloat() || regSrc.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (numBitsSrc == MicroOpBits::B8)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xBE);
        emitModRm(store_, regDst, regSrc);
    }
    else if (numBitsSrc == MicroOpBits::B16)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xBF);
        emitModRm(store_, regDst, regSrc);
    }
    else if (numBitsSrc == MicroOpBits::B32 && numBitsDst == MicroOpBits::B64)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, numBitsDst, regDst, regSrc);
        emitCpuOp(store_, 0x63);
        emitModRm(store_, regDst, regSrc);
    }
    else
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits, EncodeFlags emitFlags)
{
    if (emitFlags.has(EncodeFlagsE::CanEncode))
    {
        if (opBits != MicroOpBits::B64)
            return EncodeResult::NotSupported;
    }

    if (memReg.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memReg.isInstructionPointer())
    {
        SWC_ASSERT(memOffset == 0);
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, MicroOpBits::B64, reg, memReg);
        emitCpuOp(store_, 0x8D);
        emitModRm(store_, ModRmMode::Memory, reg, MODRM_RM_RIP);
    }
    else if (memOffset == 0)
    {
        emitLoadRegReg(reg, memReg, MicroOpBits::B64);
    }
    else
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, MicroOpBits::B64, reg, memReg);
        emitCpuOp(store_, 0x8D);
        emitModRm(store_, memOffset, reg, memReg);
    }

    return EncodeResult::Zero;
}

namespace
{
    EncodeResult encodeAmcImm(PagedStore& store, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue, EncodeFlags emitFlags)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
        {
            if (mulValue != 1 && mulValue != 2 && mulValue != 4 && mulValue != 8)
                return EncodeResult::NotSupported;
            if (opBitsBaseMul != MicroOpBits::B32 && opBitsBaseMul != MicroOpBits::B64)
                return EncodeResult::NotSupported;
            if (addValue > 0x7FFFFFFF)
                return EncodeResult::NotSupported;
            if (value > 0x7FFFFFFF)
                return EncodeResult::NotSupported;
            if (regBase.isFloat() || regMul.isFloat())
                return EncodeResult::NotSupported;
            const bool baseIsNoBase = regBase.isNoBase();
            const auto mulX64       = microRegToX64Reg(regMul);
            const auto baseX64      = baseIsNoBase ? X64Reg::Rax : microRegToX64Reg(regBase);
            if (baseIsNoBase && mulX64 == X64Reg::Rsp)
                return EncodeResult::NotSupported;
            if (opBitsBaseMul != MicroOpBits::B64 && ((!baseIsNoBase && baseX64 == X64Reg::Rsp) || mulX64 == X64Reg::Rsp))
                return EncodeResult::NotSupported;
            if (mulX64 == X64Reg::Rsp && mulValue != 1)
                return EncodeResult::NotSupported;
            return EncodeResult::Zero;
        }

        const bool baseIsNoBase = regBase.isNoBase();
        auto       baseX64      = baseIsNoBase ? X64Reg::Rax : microRegToX64Reg(regBase);
        auto       mulX64       = microRegToX64Reg(regMul);
        if (mulX64 == X64Reg::Rsp)
        {
            SWC_ASSERT(mulValue == 1);
            std::swap(regMul, regBase);
            baseX64 = microRegToX64Reg(regBase);
            mulX64  = microRegToX64Reg(regMul);
        }

        // Prefixes
        if (opBitsValue == MicroOpBits::B16)
            store.pushU8(0x66);

        // REX prefix
        const bool b1 = isExtendedReg(mulX64);
        const bool b2 = !baseIsNoBase && isExtendedReg(baseX64);
        if (opBitsValue == MicroOpBits::B64 || b1 || b2)
        {
            const auto val = getRex(opBitsValue == MicroOpBits::B64, false, b1, b2);
            store.pushU8(val);
        }

        // OpCode
        emitSpecCpuOp(store, 0xC7, opBitsValue);

        // ModRM
        if (!baseIsNoBase && baseX64 == X64Reg::R13)
            emitModRm(store, addValue <= 0x7F ? ModRmMode::Displacement8 : ModRmMode::Displacement32, MODRM_REG_0, MODRM_RM_SIB);
        else if (addValue == 0 || baseIsNoBase)
            emitModRm(store, ModRmMode::Memory, MODRM_REG_0, MODRM_RM_SIB);
        else
            emitModRm(store, addValue <= 0x7F ? ModRmMode::Displacement8 : ModRmMode::Displacement32, MODRM_REG_0, MODRM_RM_SIB);

        // SIB
        SWC_ASSERT(mulValue == 1 || mulValue == 2 || mulValue == 4 || mulValue == 8);
        const auto scale = static_cast<uint8_t>(log2(mulValue));
        if (baseIsNoBase)
        {
            emitSib(store, scale, encodeReg(mulX64) & 0b111, SIB_NO_BASE);
            emitValue(store, addValue, MicroOpBits::B32);
        }
        else
        {
            emitSib(store, scale, encodeReg(mulX64) & 0b111, encodeReg(baseX64) & 0b111);
            if (baseX64 == X64Reg::R13 || addValue != 0)
                emitValue(store, addValue, addValue <= 0x7F ? MicroOpBits::B8 : MicroOpBits::B32);
        }

        // Value
        emitValue(store, value, std::min(opBitsValue, MicroOpBits::B32));
        return EncodeResult::Zero;
    }

    EncodeResult encodeAmcReg(PagedStore& store, MicroReg reg, MicroOpBits opBitsReg, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroOp op, EncodeFlags emitFlags, bool mr)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
        {
            if (mulValue != 1 && mulValue != 2 && mulValue != 4 && mulValue != 8)
                return EncodeResult::NotSupported;
            if (op == MicroOp::LoadEffectiveAddress && opBitsReg == MicroOpBits::B8)
                return EncodeResult::NotSupported;
            if (opBitsBaseMul != MicroOpBits::B32 && opBitsBaseMul != MicroOpBits::B64)
                return EncodeResult::NotSupported;
            if (addValue > 0x7FFFFFFF)
                return EncodeResult::NotSupported;
            if (regBase.isFloat() || regMul.isFloat())
                return EncodeResult::NotSupported;
            if (reg.isFloat() && op == MicroOp::LoadEffectiveAddress)
                return EncodeResult::NotSupported;
            if (reg.isFloat() && op == MicroOp::MoveSignExtend)
                return EncodeResult::NotSupported;
            if (reg.isFloat() && opBitsReg != MicroOpBits::B32 && opBitsReg != MicroOpBits::B64)
                return EncodeResult::NotSupported;
            const bool baseIsNoBase = regBase.isNoBase();
            const auto mulX64       = microRegToX64Reg(regMul);
            const auto baseX64      = baseIsNoBase ? X64Reg::Rax : microRegToX64Reg(regBase);
            if (baseIsNoBase && mulX64 == X64Reg::Rsp)
                return EncodeResult::NotSupported;
            if (opBitsBaseMul != MicroOpBits::B64 && ((!baseIsNoBase && baseX64 == X64Reg::Rsp) || mulX64 == X64Reg::Rsp))
                return EncodeResult::NotSupported;
            if (mulX64 == X64Reg::Rsp && mulValue != 1)
                return EncodeResult::NotSupported;
            return EncodeResult::Zero;
        }

        const bool baseIsNoBase = regBase.isNoBase();
        auto       baseX64      = baseIsNoBase ? X64Reg::Rax : microRegToX64Reg(regBase);
        auto       mulX64       = microRegToX64Reg(regMul);
        const auto regX64       = microRegToX64Reg(reg);
        if (mulX64 == X64Reg::Rsp)
        {
            SWC_ASSERT(mulValue == 1);
            std::swap(regMul, regBase);
            baseX64 = microRegToX64Reg(regBase);
            mulX64  = microRegToX64Reg(regMul);
        }

        // Prefixes
        if (opBitsBaseMul == MicroOpBits::B32)
            store.pushU8(0x67);
        if (opBitsReg == MicroOpBits::B16 || reg.isFloat())
            store.pushU8(0x66);

        // REX prefix
        const bool b0      = isExtendedReg(regX64);
        const bool b1      = isExtendedReg(mulX64);
        const bool b2      = !baseIsNoBase && isExtendedReg(baseX64);
        const bool needRex = opBitsReg == MicroOpBits::B64 || needsRexForByteReg(regX64);
        if (needRex || b0 || b1 || b2)
        {
            const auto value = getRex(opBitsReg == MicroOpBits::B64, b0, b1, b2);
            store.pushU8(value);
        }

        // Opcode
        switch (op)
        {
            case MicroOp::LoadEffectiveAddress:
                emitSpecCpuOp(store, 0x8D, opBitsReg);
                break;
            case MicroOp::MoveSignExtend:
                emitSpecCpuOp(store, 0x63, opBitsReg);
                break;
            case MicroOp::Move:
                if (reg.isFloat())
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
        if (!baseIsNoBase && baseX64 == X64Reg::R13)
            emitModRm(store, addValue <= 0x7F ? ModRmMode::Displacement8 : ModRmMode::Displacement32, reg, MODRM_RM_SIB);
        else if (addValue == 0 || baseIsNoBase)
            emitModRm(store, ModRmMode::Memory, reg, MODRM_RM_SIB);
        else
            emitModRm(store, addValue <= 0x7F ? ModRmMode::Displacement8 : ModRmMode::Displacement32, reg, MODRM_RM_SIB);

        // SIB
        SWC_ASSERT(mulValue == 1 || mulValue == 2 || mulValue == 4 || mulValue == 8);
        const auto scale = static_cast<uint8_t>(log2(mulValue));
        if (baseIsNoBase)
        {
            emitSib(store, scale, encodeReg(mulX64) & 0b111, SIB_NO_BASE);
            emitValue(store, addValue, MicroOpBits::B32);
        }
        else
        {
            emitSib(store, scale, encodeReg(mulX64) & 0b111, encodeReg(baseX64) & 0b111);
            if (baseX64 == X64Reg::R13 || addValue != 0)
                emitValue(store, addValue, addValue <= 0x7F ? MicroOpBits::B8 : MicroOpBits::B32);
        }

        return EncodeResult::Zero;
    }
}

EncodeResult X64Encoder::encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc, EncodeFlags emitFlags)
{
    return encodeAmcReg(store_, regDst, opBitsDst, regBase, regMul, mulValue, addValue, opBitsSrc, MicroOp::Move, emitFlags, false);
}

EncodeResult X64Encoder::encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc, EncodeFlags emitFlags)
{
    return encodeAmcReg(store_, regSrc, opBitsSrc, regBase, regMul, mulValue, addValue, opBitsBaseMul, MicroOp::Move, emitFlags, true);
}

EncodeResult X64Encoder::encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue, EncodeFlags emitFlags)
{
    return encodeAmcImm(store_, regBase, regMul, mulValue, addValue, opBitsBaseMul, value, opBitsValue, emitFlags);
}

EncodeResult X64Encoder::encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue, EncodeFlags emitFlags)
{
    return encodeAmcReg(store_, regDst, opBitsDst, regBase, regMul, mulValue, addValue, opBitsValue, MicroOp::LoadEffectiveAddress, emitFlags, false);
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)
{
    if (memReg.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (reg.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, MicroOpBits::Zero, reg, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x11);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits, reg, memReg);
        emitSpecCpuOp(store_, 0x89, opBits);
        emitModRm(store_, memOffset, reg, memReg);
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    if (memReg.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (opBits == MicroOpBits::B128)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Right2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (opBits == MicroOpBits::B64 && value > 0x7FFFFFFF && value >> 32 != 0xFFFFFFFF)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Right2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (emitFlags.has(EncodeFlagsE::CanEncode))
        return EncodeResult::Zero;
    emitRex(store_, opBits, MicroReg{}, memReg);
    emitSpecB8(store_, 0xC7, opBits);
    emitModRm(store_, memOffset, MODRM_REG_0, memReg);
    emitValue(store_, value, std::min(opBits, MicroOpBits::B32));

    return EncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeClearReg(MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)
{
    if (emitFlags.has(EncodeFlagsE::CanEncode))
        return EncodeResult::Zero;

    if (reg.isFloat())
    {
        emitPrefixF64(store_, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, MicroOp::FloatXor);
        emitModRm(store_, reg, reg);
    }
    else
    {
        emitRex(store_, opBits, reg, reg);
        emitSpecCpuOp(store_, MicroOp::Xor, opBits);
        emitModRm(store_, reg, reg);
    }

    return EncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeSetCondReg(MicroReg reg, MicroCond cpuCond, EncodeFlags emitFlags)
{
    if (emitFlags.has(EncodeFlagsE::CanEncode))
        return EncodeResult::Zero;

    emitRex(store_, MicroOpBits::B8, MicroReg{}, reg);
    emitCpuOp(store_, 0x0F);

    switch (cpuCond)
    {
        case MicroCond::Above:
            emitCpuOp(store_, 0x97);
            break;
        case MicroCond::Overflow:
            emitCpuOp(store_, 0x90);
            break;
        case MicroCond::AboveOrEqual:
            emitCpuOp(store_, 0x93);
            break;
        case MicroCond::Greater:
            emitCpuOp(store_, 0x9F);
            break;
        case MicroCond::NotEqual:
            emitCpuOp(store_, 0x95);
            break;
        case MicroCond::NotAbove:
            emitCpuOp(store_, 0x96);
            break;
        case MicroCond::Below:
            emitCpuOp(store_, 0x92);
            break;
        case MicroCond::BelowOrEqual:
            emitCpuOp(store_, 0x96);
            break;
        case MicroCond::Equal:
            emitCpuOp(store_, 0x94);
            break;
        case MicroCond::GreaterOrEqual:
            emitCpuOp(store_, 0x9D);
            break;
        case MicroCond::Less:
            emitCpuOp(store_, 0x9C);
            break;
        case MicroCond::LessOrEqual:
            emitCpuOp(store_, 0x9E);
            break;
        case MicroCond::Parity:
            emitCpuOp(store_, 0x9A);
            break;
        case MicroCond::NotParity:
            emitCpuOp(store_, 0x9B);
            break;
        default:
            SWC_ASSERT(false);
            break;
    }

    emitModRm(store_, MODRM_REG_0, reg);
    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits, EncodeFlags emitFlags)
{
    if (emitFlags.has(EncodeFlagsE::CanEncode))
        return EncodeResult::Zero;

    opBits = std::max(opBits, MicroOpBits::B32);
    emitRex(store_, opBits, regDst, regSrc);
    emitCpuOp(store_, 0x0F);

    switch (setType)
    {
        case MicroCond::Below:
            emitCpuOp(store_, 0x42);
            break;
        case MicroCond::Equal:
            emitCpuOp(store_, 0x44);
            break;
        case MicroCond::Greater:
            emitCpuOp(store_, 0x4F);
            break;
        case MicroCond::Less:
            emitCpuOp(store_, 0x4C);
            break;
        case MicroCond::BelowOrEqual:
            emitCpuOp(store_, 0x46);
            break;
        case MicroCond::GreaterOrEqual:
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

EncodeResult X64Encoder::encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits, EncodeFlags emitFlags)
{
    if (reg0.isFloat())
    {
        if (reg1.isInt())
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }

        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitPrefixF64(store_, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x2F);
        emitModRm(store_, reg0, reg1);
    }
    else
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
        {
            if (reg1.isFloat())
                return EncodeResult::NotSupported;
            return EncodeResult::Zero;
        }

        emitRex(store_, opBits, reg1, reg0);
        emitSpecCpuOp(store_, 0x39, opBits);
        emitModRm(store_, reg1, reg0);
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeCmpRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    if (reg.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (opBits == MicroOpBits::B8)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits, MicroReg{}, reg);
        emitCpuOp(store_, 0x80);
        emitModRm(store_, MODRM_REG_7, reg);
        emitValue(store_, value, MicroOpBits::B8);
    }
    else if (canEncode8(value, opBits))
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits, MicroReg{}, reg);
        emitCpuOp(store_, 0x83);
        emitModRm(store_, MODRM_REG_7, reg);
        emitValue(store_, value, MicroOpBits::B8);
    }
    else if ((opBits != MicroOpBits::B64 || value <= 0x7FFFFFFF))
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits, MicroReg{}, reg);
        emitCpuOp(store_, 0x81);
        emitModRm(store_, MODRM_REG_7, reg);
        emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
    }
    else
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Right2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits, EncodeFlags emitFlags)
{
    if (memReg.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (reg.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Left2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (emitFlags.has(EncodeFlagsE::CanEncode))
        return EncodeResult::Zero;
    emitRex(store_, opBits, reg, memReg);
    emitSpecCpuOp(store_, 0x39, opBits);
    emitModRm(store_, memOffset, reg, memReg);

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits, EncodeFlags emitFlags)
{
    if (memReg.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (opBits == MicroOpBits::B8)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits, MicroReg{}, memReg);
        emitCpuOp(store_, 0x80);
        emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        emitValue(store_, value, MicroOpBits::B8);
    }
    else if (canEncode8(value, opBits))
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits, MicroReg{}, memReg);
        emitCpuOp(store_, 0x83);
        emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        emitValue(store_, value, MicroOpBits::B8);
    }
    else if (value <= 0x7FFFFFFF)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits, MicroReg{}, memReg);
        emitCpuOp(store_, 0x81);
        emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        emitValue(store_, value, opBits == MicroOpBits::B16 ? opBits : MicroOpBits::B32);
    }
    else
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Right2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    if (memReg.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////
    if (op == MicroOp::BitwiseNot)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits);
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, memOffset, MODRM_REG_2, memReg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Negate)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits);
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, memOffset, MODRM_REG_3, memReg);
    }

    ///////////////////////////////////////////

    else
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    if (emitFlags.has(EncodeFlagsE::CanEncode))
    {
        if (reg.isFloat())
            return EncodeResult::NotSupported;
        return EncodeResult::Zero;
    }

    ///////////////////////////////////////////

    if (op == MicroOp::BitwiseNot)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits, MicroReg{}, reg);
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, MODRM_REG_2, reg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Negate)
    {
        if (reg.isFloat())
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::NotSupported;
            SWC_INTERNAL_ERROR(ctx());
        }

        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits, MicroReg{}, reg);
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, MODRM_REG_3, reg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::ByteSwap)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        if (opBits == MicroOpBits::B16)
        {
            // rol ax, 0x8
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0xC1);
            emitCpuOp(store_, 0xC0);
            emitValue(store_, 0x08, MicroOpBits::B8);
        }
        else
        {
            SWC_ASSERT(opBits == MicroOpBits::B16 || opBits == MicroOpBits::B32 || opBits == MicroOpBits::B64);
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0xC8, reg);
        }
    }

    ///////////////////////////////////////////

    else
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    if (memReg.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////
    if (op == MicroOp::Add)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x03, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Subtract)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x2B, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::And)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x23, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Or)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x0B, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Xor)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x33, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::MultiplySigned)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        if (opBits == MicroOpBits::B8)
            emitLoadSignedExtendRegReg(regDst, regDst, MicroOpBits::B32, opBits);
        emitRex(store_, opBits, regDst, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xAF);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Right2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    ///////////////////////////////////////////

    if (op == MicroOp::ConvertUIntToFloat64)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////
    if (regDst.isFloat() && regSrc.isInt())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
        {
            if (op != MicroOp::ConvertIntToFloat && op != MicroOp::ConvertUIntToFloat64)
                return EncodeResult::NotSupported;
            return EncodeResult::Zero;
        }

        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, emitFlags.has(EncodeFlagsE::B64) ? MicroOpBits::B64 : MicroOpBits::B32, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, op);
        emitModRm(store_, regDst, regSrc);
    }

    else if (regDst.isInt() && regSrc.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
        {
            if (op != MicroOp::ConvertFloatToInt)
                return EncodeResult::NotSupported;
            return EncodeResult::Zero;
        }

        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, emitFlags.has(EncodeFlagsE::B64) ? MicroOpBits::B64 : MicroOpBits::B32, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, op);
        emitModRm(store_, regDst, regSrc);
    }

    else if (regDst.isFloat() && regSrc.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;

        if (op != MicroOp::FloatSqrt && op != MicroOp::FloatAnd && op != MicroOp::FloatXor)
        {
            emitSpecF64(store_, 0xF3, opBits);
            emitRex(store_, emitFlags.has(EncodeFlagsE::B64) ? MicroOpBits::B64 : MicroOpBits::B32, regDst, regSrc);
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

    else if (op == MicroOp::DivideUnsigned ||
             op == MicroOp::DivideSigned ||
             op == MicroOp::ModuloUnsigned ||
             op == MicroOp::ModuloSigned)
    {
        const auto rax = x64RegToMicroReg(X64Reg::Rax);
        if (emitFlags.has(EncodeFlagsE::CanEncode))
        {
            if (microRegToX64Reg(regDst) != X64Reg::Rax)
                return EncodeResult::Left2Rax;
            if (microRegToX64Reg(regSrc) == X64Reg::Rax)
                return EncodeResult::NotSupported;
            if (microRegToX64Reg(regSrc) == X64Reg::Rdx)
                return EncodeResult::NotSupported;

            return EncodeResult::Zero;
        }

        if ((op == MicroOp::DivideSigned || op == MicroOp::ModuloSigned) && opBits == MicroOpBits::B8)
            emitLoadSignedExtendRegReg(rax, rax, MicroOpBits::B32, MicroOpBits::B8);
        else if (opBits == MicroOpBits::B8)
            emitLoadZeroExtendRegReg(rax, rax, MicroOpBits::B32, MicroOpBits::B8);
        else if (op == MicroOp::DivideUnsigned || op == MicroOp::ModuloUnsigned)
            emitClearReg(x64RegToMicroReg(X64Reg::Rdx), opBits);
        else
        {
            emitRex(store_, opBits);
            emitCpuOp(store_, 0x99); // cdq
        }

        emitRex(store_, opBits, rax, regSrc);
        emitSpecCpuOp(store_, 0xF7, opBits);
        if (op == MicroOp::DivideUnsigned || op == MicroOp::ModuloUnsigned)
            emitModRm(store_, MODRM_REG_6, regSrc);
        else if (op == MicroOp::DivideSigned || op == MicroOp::ModuloSigned)
            emitModRm(store_, MODRM_REG_7, regSrc);

        if ((op == MicroOp::ModuloUnsigned || op == MicroOp::ModuloSigned) && opBits == MicroOpBits::B8)
            emitOpBinaryRegImm(rax, 8, MicroOp::ShiftRight, MicroOpBits::B32, emitFlags); // AH => AL
        else if (op == MicroOp::ModuloUnsigned || op == MicroOp::ModuloSigned)
            emitLoadRegReg(rax, x64RegToMicroReg(X64Reg::Rdx), opBits);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::MultiplyUnsigned)
    {
        const auto rax = x64RegToMicroReg(X64Reg::Rax);
        if (emitFlags.has(EncodeFlagsE::CanEncode))
        {
            if (microRegToX64Reg(regDst) != X64Reg::Rax)
                return EncodeResult::Left2Rax;
            if (microRegToX64Reg(regSrc) == X64Reg::Rax)
                return EncodeResult::NotSupported;
            if (microRegToX64Reg(regSrc) == X64Reg::Rdx)
                return EncodeResult::NotSupported;

            return EncodeResult::Zero;
        }

        emitRex(store_, opBits, rax, regSrc);
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, MODRM_REG_4, regSrc);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::MultiplySigned)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;

        if (opBits == MicroOpBits::B8)
        {
            emitLoadSignedExtendRegReg(regDst, regDst, MicroOpBits::B32, opBits);
            emitLoadSignedExtendRegReg(regSrc, regSrc, MicroOpBits::B32, opBits);
        }

        emitRex(store_, opBits, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xAF);
        emitModRm(store_, regDst, regSrc);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::RotateLeft ||
             op == MicroOp::RotateRight ||
             op == MicroOp::ShiftArithmeticLeft ||
             op == MicroOp::ShiftArithmeticRight ||
             op == MicroOp::ShiftLeft ||
             op == MicroOp::ShiftRight)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
        {
            if (microRegToX64Reg(regSrc) != X64Reg::Rcx)
            {
                SWC_ASSERT(x64RegToMicroReg(X64Reg::Rcx) == MicroReg::intReg(2));
                return EncodeResult::Right2Rcx;
            }

            return EncodeResult::Zero;
        }

        SWC_ASSERT(microRegToX64Reg(regSrc) == X64Reg::Rcx);
        emitRex(store_, opBits, MicroReg{}, regDst);
        emitSpecCpuOp(store_, 0xD3, opBits);
        if (op == MicroOp::RotateLeft)
            emitModRm(store_, MODRM_REG_0, regDst);
        else if (op == MicroOp::RotateRight)
            emitModRm(store_, MODRM_REG_1, regDst);
        else if (op == MicroOp::ShiftArithmeticLeft || op == MicroOp::ShiftLeft)
            emitModRm(store_, MODRM_REG_4, regDst);
        else if (op == MicroOp::ShiftArithmeticRight)
            emitModRm(store_, MODRM_REG_7, regDst);
        else if (op == MicroOp::ShiftRight)
            emitModRm(store_, MODRM_REG_5, regDst);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Add ||
             op == MicroOp::Subtract ||
             op == MicroOp::Xor ||
             op == MicroOp::And ||
             op == MicroOp::Or)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regSrc, regDst);
        emitSpecCpuOp(store_, op, opBits);
        emitModRm(store_, regSrc, regDst);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Exchange)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        emitRex(store_, opBits, regSrc, regDst);
        emitSpecCpuOp(store_, 0x87, opBits);
        emitModRm(store_, regSrc, regDst);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::BitScanForward || op == MicroOp::BitScanReverse)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
        {
            if (opBits == MicroOpBits::B8)
                return EncodeResult::ForceZero32;
            return EncodeResult::Zero;
        }

        emitRex(store_, opBits, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, op == MicroOp::BitScanForward ? 0xBC : 0xBD);
        emitModRm(store_, regDst, regSrc);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::PopCount)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
        {
            if (opBits == MicroOpBits::B8)
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
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    if (memReg.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////

    if (reg.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Left2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////
    if (op == MicroOp::DivideUnsigned ||
        op == MicroOp::DivideSigned ||
        op == MicroOp::ModuloUnsigned ||
        op == MicroOp::ModuloSigned ||
        op == MicroOp::MultiplySigned ||
        op == MicroOp::MultiplyUnsigned)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Left2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::ShiftArithmeticRight ||
             op == MicroOp::ShiftRight ||
             op == MicroOp::ShiftLeft)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
        {
            if (microRegToX64Reg(reg) != X64Reg::Rcx)
            {
                SWC_ASSERT(x64RegToMicroReg(X64Reg::Rcx) == MicroReg::intReg(2));
                return EncodeResult::Right2Rcx;
            }

            return EncodeResult::Zero;
        }

        if (emitFlags.has(EncodeFlagsE::Lock))
            store_.pushU8(0xF0);
        emitRex(store_, opBits, MicroReg{}, memReg);
        emitSpecCpuOp(store_, 0xD3, opBits);
        if (op == MicroOp::ShiftLeft)
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
        else if (op == MicroOp::ShiftArithmeticRight)
            emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        else if (op == MicroOp::ShiftRight)
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
    }

    ///////////////////////////////////////////

    else
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;
        if (emitFlags.has(EncodeFlagsE::Lock))
            store_.pushU8(0xF0);
        emitRex(store_, opBits, reg, memReg);
        emitSpecCpuOp(store_, op, opBits);
        emitModRm(store_, memOffset, reg, memReg);
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    ///////////////////////////////////////////

    if (op == MicroOp::Xor)
    {
        if (opBits == MicroOpBits::B8)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_6, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_6, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_6, reg);
            emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
        }
        else
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Or)
    {
        if (opBits == MicroOpBits::B8)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_1, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_1, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_1, reg);
            emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
        }
        else
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::And)
    {
        if (opBits == MicroOpBits::B8)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_4, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_4, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_4, reg);
            emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
        }
        else
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Add)
    {
        if (value == 1 && !emitFlags.has(EncodeFlagsE::Overflow) && ctx().compiler().buildCfg().backendOptimize >= Runtime::BuildCfgBackendOptim::O1)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, reg);
            emitSpecCpuOp(store_, 0xFF, opBits);
            emitModRm(store_, MODRM_REG_0, reg);
        }
        else if (opBits == MicroOpBits::B8)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_0, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_0, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_0, reg);
            emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
        }
        else
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Subtract)
    {
        if (value == 1 && !emitFlags.has(EncodeFlagsE::Overflow) && ctx().compiler().buildCfg().backendOptimize >= Runtime::BuildCfgBackendOptim::O1)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, reg);
            emitSpecCpuOp(store_, 0xFF, opBits);
            emitModRm(store_, MODRM_REG_1, reg);
        }
        else if (opBits == MicroOpBits::B8)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_5, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_5, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_5, reg);
            emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
        }
        else
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::ModuloUnsigned ||
             op == MicroOp::ModuloSigned ||
             op == MicroOp::DivideUnsigned ||
             op == MicroOp::DivideSigned ||
             op == MicroOp::MultiplyUnsigned)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Right2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::MultiplySigned)
    {
        if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            if (opBits == MicroOpBits::B8)
                emitLoadSignedExtendRegReg(reg, reg, MicroOpBits::B32, opBits);
            emitRex(store_, opBits, reg, reg);
            emitCpuOp(store_, 0x6B);
            emitModRm(store_, reg, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            if (opBits == MicroOpBits::B8 || opBits == MicroOpBits::B16)
                emitLoadSignedExtendRegReg(reg, reg, MicroOpBits::B32, opBits);
            emitRex(store_, opBits, reg, reg);
            emitCpuOp(store_, 0x69);
            emitModRm(store_, reg, reg);
            emitValue(store_, value, MicroOpBits::B32);
        }
        else
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::ShiftLeft)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;

        SWC_ASSERT(value <= 0x7F);
        if (value == 1)
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitSpecCpuOp(store_, 0xD1, opBits);
            emitModRm(store_, MODRM_REG_4, reg);
        }
        else
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitSpecCpuOp(store_, 0xC1, opBits);
            emitModRm(store_, MODRM_REG_4, reg);
            emitValue(store_, std::min(static_cast<uint32_t>(value), getNumBits(opBits) - 1), MicroOpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::ShiftRight)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;

        SWC_ASSERT(value <= 0x7F);
        if (value == 1)
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitSpecCpuOp(store_, 0xD1, opBits);
            emitModRm(store_, MODRM_REG_5, reg);
        }
        else
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitSpecCpuOp(store_, 0xC1, opBits);
            emitModRm(store_, MODRM_REG_5, reg);
            emitValue(store_, std::min(static_cast<uint32_t>(value), getNumBits(opBits) - 1), MicroOpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::ShiftArithmeticRight)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;

        SWC_ASSERT(value <= 0x7F);
        if (value == 1)
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitSpecCpuOp(store_, 0xD1, opBits);
            emitModRm(store_, MODRM_REG_7, reg);
        }
        else
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitSpecCpuOp(store_, 0xC1, opBits);
            emitModRm(store_, MODRM_REG_7, reg);
            emitValue(store_, std::min(static_cast<uint32_t>(value), getNumBits(opBits) - 1), MicroOpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    if (memReg.isFloat())
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    if (memOffset > 0x7FFFFFFF)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::NotSupported;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////

    if (op == MicroOp::ModuloSigned ||
        op == MicroOp::ModuloUnsigned ||
        op == MicroOp::DivideUnsigned ||
        op == MicroOp::DivideSigned ||
        op == MicroOp::MultiplySigned ||
        op == MicroOp::MultiplyUnsigned)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Right2Reg;
        SWC_INTERNAL_ERROR(ctx());
    }

    ///////////////////////////////////////////
    if (op == MicroOp::ShiftArithmeticRight)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;

        if (value == 1)
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitSpecCpuOp(store_, 0xD1, opBits);
            emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        }
        else
        {
            SWC_ASSERT(value <= 0x7F);
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitSpecCpuOp(store_, 0xC1, opBits);
            emitModRm(store_, memOffset, MODRM_REG_7, memReg);
            emitValue(store_, std::min(static_cast<uint32_t>(value), getNumBits(opBits) - 1), MicroOpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::ShiftRight)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;

        if (value == 1)
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitSpecCpuOp(store_, 0xD1, opBits);
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
        }
        else
        {
            SWC_ASSERT(value <= 0x7F);
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitSpecCpuOp(store_, 0xC1, opBits);
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
            emitValue(store_, std::min(static_cast<uint32_t>(value), getNumBits(opBits) - 1), MicroOpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::ShiftLeft)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
            return EncodeResult::Zero;

        if (value == 1)
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitSpecCpuOp(store_, 0xD1, opBits);
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
        }
        else
        {
            SWC_ASSERT(value <= 0x7F);
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitSpecCpuOp(store_, 0xC1, opBits);
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
            emitValue(store_, std::min(static_cast<uint32_t>(value), getNumBits(opBits) - 1), MicroOpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Add)
    {
        if (value == 1 && !emitFlags.has(EncodeFlagsE::Overflow) && ctx().compiler().buildCfg().backendOptimize >= Runtime::BuildCfgBackendOptim::O1)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitSpecCpuOp(store_, 0xFF, opBits);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
        }
        else if (opBits == MicroOpBits::B8)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
            emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
        }
        else
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Subtract)
    {
        if (value == 1 && !emitFlags.has(EncodeFlagsE::Overflow) && ctx().compiler().buildCfg().backendOptimize >= Runtime::BuildCfgBackendOptim::O1)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitSpecCpuOp(store_, 0xFF, opBits);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
        }
        else if (opBits == MicroOpBits::B8)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
            emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
        }
        else
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Or)
    {
        if (opBits == MicroOpBits::B8)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
            emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
        }
        else
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::And)
    {
        if (opBits == MicroOpBits::B8)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
            emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
        }
        else
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Right2Reg;
            SWC_INTERNAL_ERROR(ctx());
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Xor)
    {
        if (opBits == MicroOpBits::B8)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_6, memReg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_6, memReg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (value <= 0x7FFFFFFF)
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
                return EncodeResult::Zero;
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_6, memReg);
            emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
        }
        else
        {
            if (emitFlags.has(EncodeFlagsE::CanEncode))
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

EncodeResult X64Encoder::encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits, EncodeFlags emitFlags)
{
    ///////////////////////////////////////////

    if (op == MicroOp::MultiplyAdd)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
        {
            if (reg0.isFloat() != reg1.isFloat() || reg0.isFloat() != reg2.isFloat())
                return EncodeResult::NotSupported;
            if (!reg0.isFloat())
                return EncodeResult::NotSupported;
            return EncodeResult::Zero;
        }

        SWC_ASSERT(reg0.isFloat() && reg1.isFloat() && reg2.isFloat());
        emitSpecF64(store_, 0xF3, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, MicroOp::FloatMultiply);
        emitModRm(store_, reg0, reg1);

        emitSpecF64(store_, 0xF3, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, MicroOp::FloatAdd);
        emitModRm(store_, reg0, reg2);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::CompareExchange)
    {
        if (emitFlags.has(EncodeFlagsE::CanEncode))
        {
            if (microRegToX64Reg(reg0) != X64Reg::Rax)
            {
                return EncodeResult::Left2Rax;
            }

            return EncodeResult::Zero;
        }

        SWC_ASSERT(microRegToX64Reg(reg0) == X64Reg::Rax);

        if (emitFlags.has(EncodeFlagsE::Lock))
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

EncodeResult X64Encoder::encodeJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries, EncodeFlags emitFlags)
{
    auto&       compiler = ctx().compiler();
    const auto [offsetTableConstant, addrConstant] = compiler.constantSegment().reserveSpan<uint32_t>(numEntries);
    emitLoadSymRelocAddress(tableReg, symCsIndex_, offsetTableConstant);

    // 'movsxd' table, dword ptr [table + offset*4]
    encodeAmcReg(store_, tableReg, MicroOpBits::B64, tableReg, offsetReg, 4, 0, MicroOpBits::B64, MicroOp::MoveSignExtend, emitFlags, false);

    const auto startIdx = store_.size();
    emitLoadSymRelocAddress(offsetReg, cpuFct_->symbolIndex, store_.size() - cpuFct_->startAddress);
    const auto patchPtr = reinterpret_cast<uint32_t*>(store_.seekPtr()) - 1;
    emitOpBinaryRegReg(offsetReg, tableReg, MicroOp::Add, MicroOpBits::B64, emitFlags);
    emitJumpReg(offsetReg);
    const auto endIdx = store_.size();
    *patchPtr += endIdx - startIdx;

    const auto tableCompiler = compiler.compilerSegment().ptr<int32_t>(offsetTable);
    const auto currentOffset = static_cast<int32_t>(store_.size());

    EncoderJumpLabel label;
    for (uint32_t idx = 0; idx < numEntries; idx++)
    {
        label.ipDest               = tableCompiler[idx] + currentIp + 1;
        label.jump.opBits          = MicroOpBits::B32;
        label.jump.offsetStart     = currentOffset;
        label.jump.patchOffsetAddr = addrConstant + idx;
        cpuFct_->labelsToSolve.push_back(label);
    }

    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeJump(MicroJump& jump, MicroCondJump jumpType, MicroOpBits opBits, EncodeFlags emitFlags)
{
    SWC_ASSERT(opBits == MicroOpBits::B8 || opBits == MicroOpBits::B32);

    if (opBits == MicroOpBits::B8)
    {
        switch (jumpType)
        {
            case MicroCondJump::NotOverflow:
                emitCpuOp(store_, 0x71);
                break;
            case MicroCondJump::Below:
                emitCpuOp(store_, 0x72);
                break;
            case MicroCondJump::AboveOrEqual:
                emitCpuOp(store_, 0x73);
                break;
            case MicroCondJump::Zero:
                emitCpuOp(store_, 0x74);
                break;
            case MicroCondJump::NotZero:
                emitCpuOp(store_, 0x75);
                break;
            case MicroCondJump::BelowOrEqual:
                emitCpuOp(store_, 0x76);
                break;
            case MicroCondJump::Above:
                store_.pushU8(0x77);
                break;
            case MicroCondJump::Sign:
                emitCpuOp(store_, 0x78);
                break;
            case MicroCondJump::Parity:
                emitCpuOp(store_, 0x7A);
                break;
            case MicroCondJump::NotParity:
                emitCpuOp(store_, 0x7B);
                break;
            case MicroCondJump::Less:
                emitCpuOp(store_, 0x7C);
                break;
            case MicroCondJump::GreaterOrEqual:
                emitCpuOp(store_, 0x7D);
                break;
            case MicroCondJump::LessOrEqual:
                emitCpuOp(store_, 0x7E);
                break;
            case MicroCondJump::Greater:
                emitCpuOp(store_, 0x7F);
                break;
            case MicroCondJump::Unconditional:
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
        case MicroCondJump::NotOverflow:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x81);
            break;
        case MicroCondJump::Below:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x82);
            break;
        case MicroCondJump::AboveOrEqual:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x83);
            break;
        case MicroCondJump::Zero:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x84);
            break;
        case MicroCondJump::NotZero:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x85);
            break;
        case MicroCondJump::BelowOrEqual:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x86);
            break;
        case MicroCondJump::Above:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x87);
            break;
        case MicroCondJump::Parity:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8A);
            break;
        case MicroCondJump::Sign:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x88);
            break;
        case MicroCondJump::NotParity:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8B);
            break;
        case MicroCondJump::Less:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8C);
            break;
        case MicroCondJump::GreaterOrEqual:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8D);
            break;
        case MicroCondJump::LessOrEqual:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8E);
            break;
        case MicroCondJump::Greater:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8F);
            break;
        case MicroCondJump::Unconditional:
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

EncodeResult X64Encoder::encodePatchJump(const MicroJump& jump, uint64_t offsetDestination, EncodeFlags emitFlags)
{
    const int32_t offset = static_cast<int32_t>(offsetDestination - jump.offsetStart);
    if (jump.opBits == MicroOpBits::B8)
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

EncodeResult X64Encoder::encodePatchJump(const MicroJump& jump, EncodeFlags emitFlags)
{
    return encodePatchJump(jump, store_.size(), emitFlags);
}

EncodeResult X64Encoder::encodeJumpReg(MicroReg reg, EncodeFlags emitFlags)
{
    emitRex(store_, MicroOpBits::Zero, MicroReg{}, reg);
    emitCpuOp(store_, 0xFF);
    emitModRm(store_, ModRmMode::Register, MODRM_REG_4, encodeReg(reg));
    return EncodeResult::Zero;
}

/////////////////////////////////////////////////////////////////////

EncodeResult X64Encoder::encodeCallExtern(IdentifierRef symbolName, CallConvKind callConv, EncodeFlags emitFlags)
{
    emitCpuOp(store_, 0xFF);
    emitModRm(store_, ModRmMode::Memory, MODRM_REG_2, MODRM_RM_RIP);

    const auto callSym = getOrAddSymbol(symbolName, EncoderSymbolKind::Extern);
    addSymbolRelocation(store_.size() - textSectionOffset_, callSym->index, IMAGE_REL_AMD64_REL32);
    store_.pushU32(0);
    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeCallLocal(IdentifierRef symbolName, CallConvKind callConv, EncodeFlags emitFlags)
{
    emitCpuOp(store_, 0xE8);

    const auto callSym = getOrAddSymbol(symbolName, EncoderSymbolKind::Extern);
    if (callSym->kind == EncoderSymbolKind::Function)
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

EncodeResult X64Encoder::encodeCallReg(MicroReg reg, CallConvKind callConv, EncodeFlags emitFlags)
{
    emitRex(store_, MicroOpBits::Zero, MicroReg{}, reg);
    emitCpuOp(store_, 0xFF);
    emitModRm(store_, MODRM_REG_2, reg);
    return EncodeResult::Zero;
}

EncodeResult X64Encoder::encodeNop(EncodeFlags emitFlags)
{
    emitCpuOp(store_, 0x90);
    return EncodeResult::Zero;
}

SWC_END_NAMESPACE();
