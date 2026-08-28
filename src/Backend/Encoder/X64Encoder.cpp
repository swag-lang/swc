#include "pch.h"
#include "Backend/Encoder/X64Encoder.h"
#include "Backend/Micro/MicroInstr.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

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

namespace
{
    // MicroReg numbering follows the compiler ABI; these values are the actual x64
    // encoding bits. Keep the two maps explicit so calling conventions can evolve
    // independently from instruction encoding.
    enum class ModRmMode : uint8_t
    {
        Memory         = 0b00,
        Displacement8  = 0b01,
        Displacement32 = 0b10,
        Register       = 0b11,
    };

    enum class X64Reg : uint8_t
    {
        Rax   = 0b000000,
        Rbx   = 0b000011,
        Rcx   = 0b000001,
        Rdx   = 0b000010,
        Rsp   = 0b000100,
        Rbp   = 0b000101,
        Rsi   = 0b000110,
        Rdi   = 0b000111,
        R8    = 0b001000,
        R9    = 0b001001,
        R10   = 0b001010,
        R11   = 0b001011,
        R12   = 0b001100,
        R13   = 0b001101,
        R14   = 0b001110,
        R15   = 0b001111,
        Xmm0  = 0b100000,
        Xmm1  = 0b100001,
        Xmm2  = 0b100010,
        Xmm3  = 0b100011,
        Xmm4  = 0b100100,
        Xmm5  = 0b100101,
        Xmm6  = 0b100110,
        Xmm7  = 0b100111,
        Xmm8  = 0b101000,
        Xmm9  = 0b101001,
        Xmm10 = 0b101010,
        Xmm11 = 0b101011,
        Xmm12 = 0b101100,
        Xmm13 = 0b101101,
        Xmm14 = 0b101110,
        Xmm15 = 0b101111,
        Rip   = 0b110000
    };

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
        X64Reg::Xmm4,
        X64Reg::Xmm5,
        X64Reg::Xmm6,
        X64Reg::Xmm7,
        X64Reg::Xmm8,
        X64Reg::Xmm9,
        X64Reg::Xmm10,
        X64Reg::Xmm11,
        X64Reg::Xmm12,
        X64Reg::Xmm13,
        X64Reg::Xmm14,
        X64Reg::Xmm15,
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
            case X64Reg::Xmm4:
                return MicroReg::floatReg(4);
            case X64Reg::Xmm5:
                return MicroReg::floatReg(5);
            case X64Reg::Xmm6:
                return MicroReg::floatReg(6);
            case X64Reg::Xmm7:
                return MicroReg::floatReg(7);
            case X64Reg::Xmm8:
                return MicroReg::floatReg(8);
            case X64Reg::Xmm9:
                return MicroReg::floatReg(9);
            case X64Reg::Xmm10:
                return MicroReg::floatReg(10);
            case X64Reg::Xmm11:
                return MicroReg::floatReg(11);
            case X64Reg::Xmm12:
                return MicroReg::floatReg(12);
            case X64Reg::Xmm13:
                return MicroReg::floatReg(13);
            case X64Reg::Xmm14:
                return MicroReg::floatReg(14);
            case X64Reg::Xmm15:
                return MicroReg::floatReg(15);
            case X64Reg::Rip:
                return MicroReg::instructionPointer();
            default:
                SWC_UNREACHABLE();
        }
    }

    std::string_view x64RegName(X64Reg reg)
    {
        switch (reg)
        {
            case X64Reg::Rax:
                return "rax";
            case X64Reg::Rbx:
                return "rbx";
            case X64Reg::Rcx:
                return "rcx";
            case X64Reg::Rdx:
                return "rdx";
            case X64Reg::Rsp:
                return "rsp";
            case X64Reg::Rbp:
                return "rbp";
            case X64Reg::Rsi:
                return "rsi";
            case X64Reg::Rdi:
                return "rdi";
            case X64Reg::R8:
                return "r8";
            case X64Reg::R9:
                return "r9";
            case X64Reg::R10:
                return "r10";
            case X64Reg::R11:
                return "r11";
            case X64Reg::R12:
                return "r12";
            case X64Reg::R13:
                return "r13";
            case X64Reg::R14:
                return "r14";
            case X64Reg::R15:
                return "r15";
            case X64Reg::Xmm0:
                return "xmm0";
            case X64Reg::Xmm1:
                return "xmm1";
            case X64Reg::Xmm2:
                return "xmm2";
            case X64Reg::Xmm3:
                return "xmm3";
            case X64Reg::Xmm4:
                return "xmm4";
            case X64Reg::Xmm5:
                return "xmm5";
            case X64Reg::Xmm6:
                return "xmm6";
            case X64Reg::Xmm7:
                return "xmm7";
            case X64Reg::Xmm8:
                return "xmm8";
            case X64Reg::Xmm9:
                return "xmm9";
            case X64Reg::Xmm10:
                return "xmm10";
            case X64Reg::Xmm11:
                return "xmm11";
            case X64Reg::Xmm12:
                return "xmm12";
            case X64Reg::Xmm13:
                return "xmm13";
            case X64Reg::Xmm14:
                return "xmm14";
            case X64Reg::Xmm15:
                return "xmm15";
            case X64Reg::Rip:
                return "rip";
            default:
                return "?";
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

        SWC_UNREACHABLE();
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
        // Micro immediates are stored unsigned, so negative signed immediates arrive in
        // two's-complement form. Accept the low positive range and the sign-extended
        // high range for the requested operand width.
        return value <= 0x7F ||
               (opBits == MicroOpBits::B16 && value >= 0xFF80) ||
               (opBits == MicroOpBits::B32 && value >= 0xFFFFFF80) ||
               (opBits == MicroOpBits::B64 && value >= 0xFFFFFFFFFFFFFF80);
    }

    bool canEncodeSigned8(uint64_t value)
    {
        return value <= 0x7F || value >= 0xFFFFFFFFFFFFFF80;
    }

    bool canEncodeSigned32(uint64_t value)
    {
        return value <= 0x7FFFFFFF || value >= 0xFFFFFFFF80000000;
    }

    bool canEncodeOpImmediate(uint64_t value, MicroOpBits opBits)
    {
        if (opBits == MicroOpBits::B8)
            return value <= 0xFF;
        if (opBits == MicroOpBits::B16)
            return value <= 0xFFFF;
        if (opBits == MicroOpBits::B32)
            return value <= 0xFFFFFFFF;
        if (opBits == MicroOpBits::B64)
            return canEncodeSigned32(value);
        return false;
    }

    bool canEncodeOpImmediate(const ApInt& value, MicroOpBits opBits)
    {
        if (!value.fit64())
            return false;
        return canEncodeOpImmediate(value.as64(), opBits);
    }

    // The immediate an operand carries, wide or not, measured against the width it encodes at.
    bool immediateFitsOperand(const MicroInstrOperand& op, MicroOpBits opBits)
    {
        return op.hasWideImmediateValue() ? canEncodeOpImmediate(op.wideImmediateValue(), opBits) : canEncodeOpImmediate(op.valueU64, opBits);
    }

    // The four widths every integer form encodes. Anything else has to be normalized first, so
    // this records the issue and answers whether the caller should stop.
    bool requireStandardIntOpBits(MicroConformanceIssue& outIssue, MicroOpBits opBits, uint8_t operandIndex, MicroOpBits normalized = MicroOpBits::B64)
    {
        if (opBits == MicroOpBits::B8 || opBits == MicroOpBits::B16 || opBits == MicroOpBits::B32 || opBits == MicroOpBits::B64)
            return false;

        outIssue.kind             = MicroConformanceIssueKind::NormalizeOpBits;
        outIssue.operandIndex     = operandIndex;
        outIssue.normalizedOpBits = normalized;
        return true;
    }

    uint64_t immediateToU64(const ApInt& value)
    {
        SWC_INTERNAL_CHECK(value.fit64());
        return value.as64();
    }

    bool isShiftImmediateOp(MicroOp op)
    {
        return op == MicroOp::RotateLeft ||
               op == MicroOp::RotateRight ||
               op == MicroOp::ShiftArithmeticLeft ||
               op == MicroOp::ShiftArithmeticRight ||
               op == MicroOp::ShiftLeft ||
               op == MicroOp::ShiftRight;
    }

    bool requiresRegImmRewrite(MicroOp op)
    {
        return op == MicroOp::DivideUnsigned ||
               op == MicroOp::DivideSigned ||
               op == MicroOp::ModuloUnsigned ||
               op == MicroOp::ModuloSigned ||
               op == MicroOp::MultiplyUnsigned ||
               op == MicroOp::MultiplyHighSigned ||
               op == MicroOp::MultiplyHighUnsigned;
    }

    bool supportsOpBinaryRegImm(MicroOp op)
    {
        return op == MicroOp::FloatRound ||
               op == MicroOp::Xor ||
               op == MicroOp::Or ||
               op == MicroOp::And ||
               op == MicroOp::Add ||
               op == MicroOp::Subtract ||
               op == MicroOp::MultiplySigned ||
               op == MicroOp::ShiftLeft ||
               op == MicroOp::ShiftArithmeticLeft ||
               op == MicroOp::ShiftRight ||
               op == MicroOp::RotateLeft ||
               op == MicroOp::RotateRight ||
               op == MicroOp::ShiftArithmeticRight;
    }

    bool supportsOpBinaryMemImm(MicroOp op)
    {
        return op == MicroOp::Xor ||
               op == MicroOp::Or ||
               op == MicroOp::And ||
               op == MicroOp::Add ||
               op == MicroOp::Subtract ||
               op == MicroOp::ShiftLeft ||
               op == MicroOp::ShiftArithmeticLeft ||
               op == MicroOp::ShiftRight ||
               op == MicroOp::RotateLeft ||
               op == MicroOp::RotateRight ||
               op == MicroOp::ShiftArithmeticRight;
    }

    bool supportsOpBinaryMemReg(MicroOp op)
    {
        return op == MicroOp::Xor ||
               op == MicroOp::Or ||
               op == MicroOp::And ||
               op == MicroOp::Add ||
               op == MicroOp::Subtract ||
               op == MicroOp::ShiftLeft ||
               op == MicroOp::ShiftArithmeticLeft ||
               op == MicroOp::ShiftRight ||
               op == MicroOp::RotateLeft ||
               op == MicroOp::RotateRight ||
               op == MicroOp::ShiftArithmeticRight;
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
        const uint32_t result = static_cast<uint32_t>(mod) << 6 | ((reg & 0b111) << 3) | (rm & 0b111);
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

        // REX is required for 64-bit operands, extended registers, and the byte-register
        // hole (sil/dil/spl/bpl) even when the instruction itself is 8-bit.
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

        // rbp/r13 cannot encode bare [base] with mod=00; rsp/r12 always require SIB.
        // Centralize those x64 quirks here so instruction encoders can request a
        // logical [base + offset] form without duplicating addressing edge cases.
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
        else if (canEncodeSigned8(memOffset))
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

            SWC_ASSERT(canEncodeSigned32(memOffset));
            emitValue(store, memOffset, MicroOpBits::B32);
        }
    }

    void emitModRm(PagedStore& store, uint64_t memOffset, MicroReg reg, MicroReg memReg)
    {
        emitModRm(store, memOffset, encodeReg(reg), memReg);
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

    uint8_t x64RegNumber(X64Reg reg)
    {
        return static_cast<uint8_t>((isExtendedReg(reg) ? 8 : 0) | encodeReg(reg));
    }

    // pp replaces the mandatory prefix byte the legacy encoding would have
    // emitted ahead of the 0F escape.
    uint8_t vexPrefixBits(uint8_t mandatoryPrefix)
    {
        switch (mandatoryPrefix)
        {
            case 0x66:
                return 0b01;
            case 0xF3:
                return 0b10;
            case 0xF2:
                return 0b11;
            default:
                return 0b00;
        }
    }

    // Opcode maps reachable through a VEX prefix; the value is the mmmmm field.
    constexpr uint8_t VEX_MAP_0F   = 1;
    constexpr uint8_t VEX_MAP_0F38 = 2;
    constexpr uint8_t VEX_MAP_0F3A = 3;

    // VEX prefix for the 128-bit forms this encoder emits: L = 0, W = 0, and
    // the opcode map named explicitly. The two-byte C5 form only exists for
    // the 0F map, so the other maps always take the three-byte form. The
    // R/X/B/vvvv fields are stored inverted, which is why every one of them
    // is written as its complement.
    void emitVex(PagedStore& store, uint8_t mandatoryPrefix, uint8_t map, X64Reg dst, X64Reg src1, X64Reg src2)
    {
        const uint8_t pp     = vexPrefixBits(mandatoryPrefix);
        const uint8_t vvvv   = static_cast<uint8_t>(~x64RegNumber(src1) & 0x0F);
        const bool    extDst = isExtendedReg(dst);
        const bool    extSrc = isExtendedReg(src2);

        if (map == VEX_MAP_0F && !extSrc)
        {
            store.pushU8(0xC5);
            store.pushU8(static_cast<uint8_t>((extDst ? 0 : 0x80) | (vvvv << 3) | pp));
            return;
        }

        // Three-byte form: X is unused, B covers the r/m register, and mmmmm
        // names the opcode map.
        store.pushU8(0xC4);
        store.pushU8(static_cast<uint8_t>((extDst ? 0 : 0x80) | 0x40 | (extSrc ? 0 : 0x20) | map));
        store.pushU8(static_cast<uint8_t>((vvvv << 3) | pp));
    }

    struct VecOpEncoding
    {
        uint8_t map;
        uint8_t prefix;
        uint8_t opcode;
    };

    // Opcode selection for the packed forms whose ModRM carries plain
    // registers. The same entry serves the destructive legacy SSE shape where
    // one is still emitted and the VEX shape. The shift-by-immediate group is
    // keyed separately (vecShiftImmEncoding) because it carries an opcode
    // extension instead of a destination in ModRM.reg.
    VecOpEncoding vecOpEncoding(MicroOp op)
    {
        switch (op)
        {
            case MicroOp::VecAdd8: return {VEX_MAP_0F, 0x66, 0xFC};
            case MicroOp::VecAdd16: return {VEX_MAP_0F, 0x66, 0xFD};
            case MicroOp::VecAdd32: return {VEX_MAP_0F, 0x66, 0xFE};
            case MicroOp::VecAdd64: return {VEX_MAP_0F, 0x66, 0xD4};
            case MicroOp::VecSub8: return {VEX_MAP_0F, 0x66, 0xF8};
            case MicroOp::VecSub16: return {VEX_MAP_0F, 0x66, 0xF9};
            case MicroOp::VecSub32: return {VEX_MAP_0F, 0x66, 0xFA};
            case MicroOp::VecSub64: return {VEX_MAP_0F, 0x66, 0xFB};
            case MicroOp::VecMul16: return {VEX_MAP_0F, 0x66, 0xD5};
            case MicroOp::VecMul32: return {VEX_MAP_0F38, 0x66, 0x40};
            case MicroOp::VecMulU32Wide: return {VEX_MAP_0F, 0x66, 0xF4};
            case MicroOp::VecSatAddS8: return {VEX_MAP_0F, 0x66, 0xEC};
            case MicroOp::VecSatAddS16: return {VEX_MAP_0F, 0x66, 0xED};
            case MicroOp::VecSatAddU8: return {VEX_MAP_0F, 0x66, 0xDC};
            case MicroOp::VecSatAddU16: return {VEX_MAP_0F, 0x66, 0xDD};
            case MicroOp::VecSatSubS8: return {VEX_MAP_0F, 0x66, 0xE8};
            case MicroOp::VecSatSubS16: return {VEX_MAP_0F, 0x66, 0xE9};
            case MicroOp::VecSatSubU8: return {VEX_MAP_0F, 0x66, 0xD8};
            case MicroOp::VecSatSubU16: return {VEX_MAP_0F, 0x66, 0xD9};
            case MicroOp::VecAvgU8: return {VEX_MAP_0F, 0x66, 0xE0};
            case MicroOp::VecAvgU16: return {VEX_MAP_0F, 0x66, 0xE3};
            case MicroOp::VecMaddS16: return {VEX_MAP_0F, 0x66, 0xF5};
            case MicroOp::VecMaddUBS16: return {VEX_MAP_0F38, 0x66, 0x04};
            case MicroOp::VecSadU8: return {VEX_MAP_0F, 0x66, 0xF6};
            case MicroOp::VecAnd: return {VEX_MAP_0F, 0x66, 0xDB};
            case MicroOp::VecAndNot: return {VEX_MAP_0F, 0x66, 0xDF};
            case MicroOp::VecOr: return {VEX_MAP_0F, 0x66, 0xEB};
            case MicroOp::VecXor: return {VEX_MAP_0F, 0x66, 0xEF};
            case MicroOp::VecMinS8: return {VEX_MAP_0F38, 0x66, 0x38};
            case MicroOp::VecMinS16: return {VEX_MAP_0F, 0x66, 0xEA};
            case MicroOp::VecMinS32: return {VEX_MAP_0F38, 0x66, 0x39};
            case MicroOp::VecMinU8: return {VEX_MAP_0F, 0x66, 0xDA};
            case MicroOp::VecMinU16: return {VEX_MAP_0F38, 0x66, 0x3A};
            case MicroOp::VecMinU32: return {VEX_MAP_0F38, 0x66, 0x3B};
            case MicroOp::VecMaxS8: return {VEX_MAP_0F38, 0x66, 0x3C};
            case MicroOp::VecMaxS16: return {VEX_MAP_0F, 0x66, 0xEE};
            case MicroOp::VecMaxS32: return {VEX_MAP_0F38, 0x66, 0x3D};
            case MicroOp::VecMaxU8: return {VEX_MAP_0F, 0x66, 0xDE};
            case MicroOp::VecMaxU16: return {VEX_MAP_0F38, 0x66, 0x3E};
            case MicroOp::VecMaxU32: return {VEX_MAP_0F38, 0x66, 0x3F};
            case MicroOp::VecCmpEq8: return {VEX_MAP_0F, 0x66, 0x74};
            case MicroOp::VecCmpEq16: return {VEX_MAP_0F, 0x66, 0x75};
            case MicroOp::VecCmpEq32: return {VEX_MAP_0F, 0x66, 0x76};
            case MicroOp::VecCmpEq64: return {VEX_MAP_0F38, 0x66, 0x29};
            case MicroOp::VecCmpGtS8: return {VEX_MAP_0F, 0x66, 0x64};
            case MicroOp::VecCmpGtS16: return {VEX_MAP_0F, 0x66, 0x65};
            case MicroOp::VecCmpGtS32: return {VEX_MAP_0F, 0x66, 0x66};
            case MicroOp::VecCmpGtS64: return {VEX_MAP_0F38, 0x66, 0x37};
            case MicroOp::VecPackSS16: return {VEX_MAP_0F, 0x66, 0x63};
            case MicroOp::VecPackSS32: return {VEX_MAP_0F, 0x66, 0x6B};
            case MicroOp::VecPackUS16: return {VEX_MAP_0F, 0x66, 0x67};
            case MicroOp::VecPackUS32: return {VEX_MAP_0F38, 0x66, 0x2B};
            case MicroOp::VecUnpackLo8: return {VEX_MAP_0F, 0x66, 0x60};
            case MicroOp::VecUnpackLo16: return {VEX_MAP_0F, 0x66, 0x61};
            case MicroOp::VecUnpackLo32: return {VEX_MAP_0F, 0x66, 0x62};
            case MicroOp::VecUnpackLo64: return {VEX_MAP_0F, 0x66, 0x6C};
            case MicroOp::VecUnpackHi8: return {VEX_MAP_0F, 0x66, 0x68};
            case MicroOp::VecUnpackHi16: return {VEX_MAP_0F, 0x66, 0x69};
            case MicroOp::VecUnpackHi32: return {VEX_MAP_0F, 0x66, 0x6A};
            case MicroOp::VecUnpackHi64: return {VEX_MAP_0F, 0x66, 0x6D};
            case MicroOp::VecPermB: return {VEX_MAP_0F38, 0x66, 0x00};
            case MicroOp::VecBlendVB: return {VEX_MAP_0F3A, 0x66, 0x4C};
            case MicroOp::VecAddF32: return {VEX_MAP_0F, 0x00, 0x58};
            case MicroOp::VecAddF64: return {VEX_MAP_0F, 0x66, 0x58};
            case MicroOp::VecSubF32: return {VEX_MAP_0F, 0x00, 0x5C};
            case MicroOp::VecSubF64: return {VEX_MAP_0F, 0x66, 0x5C};
            case MicroOp::VecMulF32: return {VEX_MAP_0F, 0x00, 0x59};
            case MicroOp::VecMulF64: return {VEX_MAP_0F, 0x66, 0x59};
            case MicroOp::VecDivF32: return {VEX_MAP_0F, 0x00, 0x5E};
            case MicroOp::VecDivF64: return {VEX_MAP_0F, 0x66, 0x5E};
            case MicroOp::VecMinF32: return {VEX_MAP_0F, 0x00, 0x5D};
            case MicroOp::VecMinF64: return {VEX_MAP_0F, 0x66, 0x5D};
            case MicroOp::VecMaxF32: return {VEX_MAP_0F, 0x00, 0x5F};
            case MicroOp::VecMaxF64: return {VEX_MAP_0F, 0x66, 0x5F};
            case MicroOp::VecAbsS8: return {VEX_MAP_0F38, 0x66, 0x1C};
            case MicroOp::VecAbsS16: return {VEX_MAP_0F38, 0x66, 0x1D};
            case MicroOp::VecAbsS32: return {VEX_MAP_0F38, 0x66, 0x1E};
            case MicroOp::VecWidenLoS8: return {VEX_MAP_0F38, 0x66, 0x20};
            case MicroOp::VecWidenLoS16: return {VEX_MAP_0F38, 0x66, 0x23};
            case MicroOp::VecWidenLoS32: return {VEX_MAP_0F38, 0x66, 0x25};
            case MicroOp::VecWidenLoU8: return {VEX_MAP_0F38, 0x66, 0x30};
            case MicroOp::VecWidenLoU16: return {VEX_MAP_0F38, 0x66, 0x33};
            case MicroOp::VecWidenLoU32: return {VEX_MAP_0F38, 0x66, 0x35};
            case MicroOp::VecSqrtF32: return {VEX_MAP_0F, 0x00, 0x51};
            case MicroOp::VecSqrtF64: return {VEX_MAP_0F, 0x66, 0x51};
            case MicroOp::VecTruncF32ToS32: return {VEX_MAP_0F, 0xF3, 0x5B};
            case MicroOp::VecMoveMaskB: return {VEX_MAP_0F, 0x66, 0xD7};
            case MicroOp::VecMoveMaskF32: return {VEX_MAP_0F, 0x00, 0x50};
            case MicroOp::VecMoveMaskF64: return {VEX_MAP_0F, 0x66, 0x50};
            case MicroOp::VecRoundF32: return {VEX_MAP_0F3A, 0x66, 0x08};
            case MicroOp::VecRoundF64: return {VEX_MAP_0F3A, 0x66, 0x09};
            case MicroOp::VecCmpF32: return {VEX_MAP_0F, 0x00, 0xC2};
            case MicroOp::VecCmpF64: return {VEX_MAP_0F, 0x66, 0xC2};
            case MicroOp::VecShufF32: return {VEX_MAP_0F, 0x00, 0xC6};
            case MicroOp::VecAlignR: return {VEX_MAP_0F3A, 0x66, 0x0F};
            case MicroOp::VecShiftLeftV16: return {VEX_MAP_0F, 0x66, 0xF1};
            case MicroOp::VecShiftLeftV32: return {VEX_MAP_0F, 0x66, 0xF2};
            case MicroOp::VecShiftLeftV64: return {VEX_MAP_0F, 0x66, 0xF3};
            case MicroOp::VecShiftRightV16: return {VEX_MAP_0F, 0x66, 0xD1};
            case MicroOp::VecShiftRightV32: return {VEX_MAP_0F, 0x66, 0xD2};
            case MicroOp::VecShiftRightV64: return {VEX_MAP_0F, 0x66, 0xD3};
            case MicroOp::VecShiftRightAV16: return {VEX_MAP_0F, 0x66, 0xE1};
            case MicroOp::VecShiftRightAV32: return {VEX_MAP_0F, 0x66, 0xE2};
            default:
                SWC_INTERNAL_ERROR();
        }
        return {};
    }

    // The packed shift-by-immediate group: the opcode byte names the lane
    // width, the operation rides in ModRM.reg as an opcode extension.
    bool vecShiftImmEncoding(MicroOp op, uint8_t& outOpcode, uint8_t& outModRmReg)
    {
        switch (op)
        {
            case MicroOp::VecShiftLeft16:
                outOpcode   = 0x71;
                outModRmReg = MODRM_REG_6;
                return true;
            case MicroOp::VecShiftRight16:
                outOpcode   = 0x71;
                outModRmReg = MODRM_REG_2;
                return true;
            case MicroOp::VecShiftRightA16:
                outOpcode   = 0x71;
                outModRmReg = MODRM_REG_4;
                return true;
            case MicroOp::VecShiftLeft32:
                outOpcode   = 0x72;
                outModRmReg = MODRM_REG_6;
                return true;
            case MicroOp::VecShiftRight32:
                outOpcode   = 0x72;
                outModRmReg = MODRM_REG_2;
                return true;
            case MicroOp::VecShiftRightA32:
                outOpcode   = 0x72;
                outModRmReg = MODRM_REG_4;
                return true;
            case MicroOp::VecShiftLeft64:
                outOpcode   = 0x73;
                outModRmReg = MODRM_REG_6;
                return true;
            case MicroOp::VecShiftRight64:
                outOpcode   = 0x73;
                outModRmReg = MODRM_REG_2;
                return true;
            case MicroOp::VecShiftLeftBytes:
                outOpcode   = 0x73;
                outModRmReg = MODRM_REG_7;
                return true;
            case MicroOp::VecShiftRightBytes:
                outOpcode   = 0x73;
                outModRmReg = MODRM_REG_3;
                return true;
            default:
                return false;
        }
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
            case MicroOp::Compare:
                return 0x39;
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
            case MicroOp::FloatRound:
                return 0x0A;
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
            case MicroOp::Test:
                return 0x85;
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
                SWC_UNREACHABLE();
        }
    }

    uint8_t getX64RegMemOpCode(MicroOp op)
    {
        switch (op)
        {
            case MicroOp::Add:
            case MicroOp::And:
            case MicroOp::Or:
            case MicroOp::Subtract:
            case MicroOp::Xor:
            case MicroOp::Compare:
                return getX64OpCode(op) + 2;
            case MicroOp::Move:
                return getX64OpCode(op) - 2;
            default:
                SWC_UNREACHABLE();
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

// ============================================================================

std::string X64Encoder::formatRegisterName(MicroReg reg) const
{
    if (!reg.isValid())
        return "inv";

    if (reg.isNoBase())
        return "nobase";

    if (reg.isVirtualInt())
        return std::format("v{}", reg.index());
    if (reg.isVirtualFloat())
        return std::format("vf{}", reg.index());

    if (reg.isInt() || reg.isFloat() || reg.isInstructionPointer())
        return std::string(x64RegName(microRegToX64Reg(reg)));

    return std::format("reg#{}", reg.packed);
}

X64Encoder::X64Encoder(TaskContext& ctx) :
    Encoder(ctx),
    unwind_(X64Unwind::create(ctx.compiler().cmdLine().targetOs))
{
}

void X64Encoder::buildUnwindInfo(ByteArray& outUnwindInfo) const
{
    SWC_ASSERT(unwind_);
    unwind_->buildInfo(outUnwindInfo, size());
}

void X64Encoder::setUnwindFrameRegister(const MicroReg reg)
{
    SWC_ASSERT(unwind_);
    unwind_->setFrameRegister(reg);
}

void X64Encoder::onInstructionEncoded(const MicroInstr& inst, const MicroInstrOperand* ops, const uint32_t codeStartOffset, const uint32_t codeEndOffset)
{
    SWC_ASSERT(unwind_);
    unwind_->onInstructionEncoded(inst, ops, codeStartOffset, codeEndOffset);
}

// ============================================================================

void X64Encoder::updateRegUseDef(const MicroInstr& inst, const MicroInstrOperand* ops, MicroInstrUseDef& info) const
{
    if (!ops)
        return;

    if (inst.op == MicroInstrOpcode::VecGatherS32)
    {
        // VPGATHERDD destroys its mask. XMM15 is a late encoder scratch, and
        // announcing the clobber makes register allocation preserve any live value.
        info.addDef(x64RegToMicroReg(X64Reg::Xmm15));
        return;
    }

    const MicroReg stackReg = stackPointerReg();
    switch (inst.op)
    {
        case MicroInstrOpcode::Push:
            info.addUseDef(stackReg);
            return;

        case MicroInstrOpcode::Pop:
            info.addUseDef(stackReg);
            return;

        default:
            break;
    }

    auto microOp             = MicroOp::Add;
    bool shiftUsesFixedCount = false;
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

    if (microOp == MicroOp::RotateLeft ||
        microOp == MicroOp::RotateRight ||
        microOp == MicroOp::ShiftArithmeticLeft ||
        microOp == MicroOp::ShiftArithmeticRight ||
        microOp == MicroOp::ShiftLeft ||
        microOp == MicroOp::ShiftRight)
    {
        const MicroReg rcxReg = x64RegToMicroReg(X64Reg::Rcx);
        if (inst.op == MicroInstrOpcode::OpBinaryRegReg)
            shiftUsesFixedCount = ops[1].reg == rcxReg;
        else if (inst.op == MicroInstrOpcode::OpBinaryMemReg)
            shiftUsesFixedCount = ops[1].reg == rcxReg;
    }

    switch (microOp)
    {
        case MicroOp::RotateLeft:
        case MicroOp::RotateRight:
        case MicroOp::ShiftArithmeticLeft:
        case MicroOp::ShiftArithmeticRight:
        case MicroOp::ShiftLeft:
        case MicroOp::ShiftRight:
            if (shiftUsesFixedCount)
                info.addUse(x64RegToMicroReg(X64Reg::Rcx));
            break;
        case MicroOp::MultiplySigned:
        {
            // B8 signed multiply uses one-operand IMUL (no two-operand 8-bit form exists),
            // which requires RAX and clobbers RDX, like MultiplyUnsigned.
            const MicroOpBits opBits = (inst.op == MicroInstrOpcode::OpBinaryRegImm || inst.op == MicroInstrOpcode::OpBinaryMemImm)
                                           ? ops[1].opBits
                                           : ops[2].opBits;
            if (opBits == MicroOpBits::B8)
            {
                info.addUseDef(x64RegToMicroReg(X64Reg::Rax));
                info.addDef(x64RegToMicroReg(X64Reg::Rdx));
            }
            break;
        }
        case MicroOp::MultiplyUnsigned:
        case MicroOp::MultiplyHighSigned:
        case MicroOp::MultiplyHighUnsigned:
            info.addUseDef(x64RegToMicroReg(X64Reg::Rax));
            info.addDef(x64RegToMicroReg(X64Reg::Rdx));
            break;
        case MicroOp::DivideUnsigned:
        case MicroOp::ModuloUnsigned:
        case MicroOp::DivideSigned:
        case MicroOp::ModuloSigned:
            info.addUseDef(x64RegToMicroReg(X64Reg::Rax));
            info.addUseDef(x64RegToMicroReg(X64Reg::Rdx));
            break;
        default:
            break;
    }
}

bool X64Encoder::queryConformanceIssue(MicroConformanceIssue& outIssue, const MicroInstr& inst, const MicroInstrOperand* ops) const
{
    outIssue = {};
    if (!ops)
        return false;

    // Contract with Legalize: every issue reported here must be rewritten before byte
    // emission. The encode* functions can then assume remaining instruction forms are
    // representable on x64.
    ///////////////////////////////////////////
    if (inst.op == MicroInstrOpcode::OpBinaryRegReg)
    {
        const MicroOp op = ops[3].microOp;

        if (isShiftImmediateOp(op))
        {
            const MicroReg rcxReg = x64RegToMicroReg(X64Reg::Rcx);
            if (ops[1].reg != rcxReg)
            {
                outIssue.kind         = MicroConformanceIssueKind::RewriteRegRegOperandToFixedReg;
                outIssue.operandIndex = 1;
                outIssue.requiredReg  = rcxReg;
                return true;
            }
        }

        const bool isB8SignedMul = op == MicroOp::MultiplySigned && ops[2].opBits == MicroOpBits::B8;
        if (op == MicroOp::MultiplyUnsigned ||
            isB8SignedMul ||
            op == MicroOp::MultiplyHighSigned ||
            op == MicroOp::MultiplyHighUnsigned ||
            op == MicroOp::DivideUnsigned ||
            op == MicroOp::DivideSigned ||
            op == MicroOp::ModuloUnsigned ||
            op == MicroOp::ModuloSigned)
        {
            const MicroReg raxReg = x64RegToMicroReg(X64Reg::Rax);
            const MicroReg rdxReg = x64RegToMicroReg(X64Reg::Rdx);
            if (ops[0].reg != raxReg)
            {
                outIssue.kind         = MicroConformanceIssueKind::RewriteRegRegOperandToFixedReg;
                outIssue.operandIndex = 0;
                outIssue.requiredReg  = raxReg;
                return true;
            }

            if ((op == MicroOp::DivideUnsigned ||
                 op == MicroOp::DivideSigned ||
                 op == MicroOp::ModuloUnsigned ||
                 op == MicroOp::ModuloSigned) &&
                ops[1].reg == rdxReg)
            {
                outIssue.kind         = MicroConformanceIssueKind::RewriteRegRegOperandAwayFromFixedReg;
                outIssue.operandIndex = 1;
                outIssue.forbiddenReg = rdxReg;
                return true;
            }
        }
    }

    ///////////////////////////////////////////
    if (inst.op == MicroInstrOpcode::OpBinaryRegMem)
    {
        const MicroOp op = ops[3].microOp;

        if (requireStandardIntOpBits(outIssue, ops[2].opBits, 2))
            return true;

        const bool isB8SignedMul = op == MicroOp::MultiplySigned && ops[2].opBits == MicroOpBits::B8;
        if (op == MicroOp::MultiplyUnsigned || isB8SignedMul)
        {
            const MicroReg raxReg = x64RegToMicroReg(X64Reg::Rax);
            if (ops[0].reg != raxReg)
            {
                outIssue.kind         = MicroConformanceIssueKind::RewriteRegRegOperandToFixedReg;
                outIssue.operandIndex = 0;
                outIssue.requiredReg  = raxReg;
                return true;
            }
        }
    }

    ///////////////////////////////////////////
    if (inst.op == MicroInstrOpcode::OpBinaryMemReg)
    {
        const MicroOp op = ops[3].microOp;

        if (requireStandardIntOpBits(outIssue, ops[2].opBits, 2))
            return true;

        if (!ops[0].reg.isInt() || !ops[1].reg.isInt() || !supportsOpBinaryMemReg(op))
        {
            outIssue.kind = MicroConformanceIssueKind::RewriteMemRegToRegReg;
            return true;
        }

        if (isShiftImmediateOp(op))
        {
            const MicroReg rcxReg = x64RegToMicroReg(X64Reg::Rcx);
            if (ops[1].reg != rcxReg)
            {
                outIssue.kind         = MicroConformanceIssueKind::RewriteRegRegOperandToFixedReg;
                outIssue.operandIndex = 1;
                outIssue.requiredReg  = rcxReg;
                return true;
            }
        }
    }

    ///////////////////////////////////////////
    if (inst.op == MicroInstrOpcode::OpTernaryRegRegReg)
    {
        const MicroOp op = ops[4].microOp;
        if (op == MicroOp::CompareExchange)
        {
            const MicroReg raxReg = x64RegToMicroReg(X64Reg::Rax);
            if (ops[0].reg != raxReg)
            {
                outIssue.kind         = MicroConformanceIssueKind::RewriteRegRegOperandToFixedReg;
                outIssue.operandIndex = 0;
                outIssue.requiredReg  = raxReg;
                return true;
            }

            if (ops[1].reg == raxReg)
            {
                outIssue.kind         = MicroConformanceIssueKind::RewriteRegRegOperandAwayFromFixedReg;
                outIssue.operandIndex = 1;
                outIssue.forbiddenReg = raxReg;
                return true;
            }

            if (ops[2].reg == raxReg)
            {
                outIssue.kind         = MicroConformanceIssueKind::RewriteRegRegOperandAwayFromFixedReg;
                outIssue.operandIndex = 2;
                outIssue.forbiddenReg = raxReg;
                return true;
            }
        }
    }

    ///////////////////////////////////////////
    if (inst.op == MicroInstrOpcode::LoadRegImm || inst.op == MicroInstrOpcode::LoadRegPtrImm || inst.op == MicroInstrOpcode::LoadRegPtrReloc)
    {
        if (ops[0].reg.isAnyFloat())
        {
            outIssue.kind = MicroConformanceIssueKind::RewriteLoadFloatRegImm;
            return true;
        }

        if (requireStandardIntOpBits(outIssue, ops[1].opBits, 1))
            return true;

        const bool     immediateIsWide = ops[2].hasWideImmediateValue();
        const bool     immediateFits64 = !immediateIsWide || ops[2].wideImmediateValue().fit64();
        const uint64_t immediateU64 =
            immediateIsWide && immediateFits64 ? ops[2].wideImmediateValue().as64() : ops[2].valueU64;

        if (ops[1].opBits == MicroOpBits::B8 &&
            ((!immediateFits64 && immediateIsWide) || immediateU64 > 0xFF))
        {
            outIssue.kind          = MicroConformanceIssueKind::ClampImmediate;
            outIssue.operandIndex  = 2;
            outIssue.valueLimitU64 = 0xFF;
            return true;
        }

        if (ops[1].opBits == MicroOpBits::B16 &&
            ((!immediateFits64 && immediateIsWide) || immediateU64 > 0xFFFF))
        {
            outIssue.kind          = MicroConformanceIssueKind::ClampImmediate;
            outIssue.operandIndex  = 2;
            outIssue.valueLimitU64 = 0xFFFF;
            return true;
        }

        if (ops[1].opBits == MicroOpBits::B32 &&
            ((!immediateFits64 && immediateIsWide) || immediateU64 > 0xFFFFFFFF))
        {
            outIssue.kind          = MicroConformanceIssueKind::ClampImmediate;
            outIssue.operandIndex  = 2;
            outIssue.valueLimitU64 = 0xFFFFFFFF;
            return true;
        }
    }

    ///////////////////////////////////////////
    if (inst.op == MicroInstrOpcode::OpBinaryRegImm)
    {
        // The packed shift forms are emitted by the vectorizer already in their
        // exact encodable shape (float register, B128, imm8 count); the scalar
        // normalizations below would corrupt them.
        if (isVecMicroOp(ops[2].microOp))
            return false;

        if (requireStandardIntOpBits(outIssue, ops[1].opBits, 1))
            return true;

        const bool isB8SignedMulImm = ops[2].microOp == MicroOp::MultiplySigned && ops[1].opBits == MicroOpBits::B8;
        if (!supportsOpBinaryRegImm(ops[2].microOp) || requiresRegImmRewrite(ops[2].microOp) || isB8SignedMulImm)
        {
            outIssue.kind        = MicroConformanceIssueKind::RewriteRegImmToRegReg;
            outIssue.requiredReg = x64RegToMicroReg(X64Reg::Rax);
            if (ops[2].microOp == MicroOp::DivideUnsigned ||
                ops[2].microOp == MicroOp::DivideSigned ||
                ops[2].microOp == MicroOp::ModuloUnsigned ||
                ops[2].microOp == MicroOp::ModuloSigned)
            {
                outIssue.forbiddenReg = x64RegToMicroReg(X64Reg::Rdx);
            }
            return true;
        }

        if (isShiftImmediateOp(ops[2].microOp))
        {
            const bool immediateIsWide = ops[3].hasWideImmediateValue();
            if ((!immediateIsWide && ops[3].valueU64 <= 0x7F) ||
                (immediateIsWide && ops[3].wideImmediateValue().fit64() && ops[3].wideImmediateValue().as64() <= 0x7F))
                return false;

            outIssue.kind          = MicroConformanceIssueKind::ClampImmediate;
            outIssue.operandIndex  = 3;
            outIssue.valueLimitU64 = 0x7F;
            return true;
        }

        const bool immediateIsEncodable = immediateFitsOperand(ops[3], ops[1].opBits);
        if (!immediateIsEncodable)
        {
            outIssue.kind = MicroConformanceIssueKind::RewriteRegImmToRegReg;
            return true;
        }
    }

    ///////////////////////////////////////////
    // Both compare-with-immediate forms answer the same two questions; only the operand carrying
    // the immediate moves, because the memory form spends two operands on its address.
    if (inst.op == MicroInstrOpcode::CmpRegImm || inst.op == MicroInstrOpcode::CmpMemImm)
    {
        if (requireStandardIntOpBits(outIssue, ops[1].opBits, 1))
            return true;

        const uint32_t immediateIndex = inst.op == MicroInstrOpcode::CmpRegImm ? 2 : 3;
        if (!immediateFitsOperand(ops[immediateIndex], ops[1].opBits))
        {
            outIssue.kind = MicroConformanceIssueKind::RewriteRegImmToRegReg;
            return true;
        }
    }

    ///////////////////////////////////////////
    if (inst.op == MicroInstrOpcode::OpBinaryMemImm)
    {
        if (requireStandardIntOpBits(outIssue, ops[1].opBits, 1))
            return true;

        if (!supportsOpBinaryMemImm(ops[2].microOp))
        {
            outIssue.kind = MicroConformanceIssueKind::RewriteRegImmToRegReg;
            return true;
        }

        if (isShiftImmediateOp(ops[2].microOp))
        {
            const bool immediateIsWide = ops[4].hasWideImmediateValue();
            if ((!immediateIsWide && ops[4].valueU64 <= 0x7F) ||
                (immediateIsWide && ops[4].wideImmediateValue().fit64() && ops[4].wideImmediateValue().as64() <= 0x7F))
                return false;

            outIssue.kind          = MicroConformanceIssueKind::ClampImmediate;
            outIssue.operandIndex  = 4;
            outIssue.valueLimitU64 = 0x7F;
            return true;
        }

        const bool immediateIsEncodable = immediateFitsOperand(ops[4], ops[1].opBits);
        if (!immediateIsEncodable)
        {
            outIssue.kind = MicroConformanceIssueKind::RewriteRegImmToRegReg;
            return true;
        }
    }

    ///////////////////////////////////////////
    if (inst.op == MicroInstrOpcode::JumpCond || inst.op == MicroInstrOpcode::JumpCondImm)
    {
        if (ops[1].opBits != MicroOpBits::B8 && ops[1].opBits != MicroOpBits::B32)
        {
            outIssue.kind             = MicroConformanceIssueKind::NormalizeOpBits;
            outIssue.operandIndex     = 1;
            outIssue.normalizedOpBits = MicroOpBits::B32;
            return true;
        }

        return false;
    }

    ///////////////////////////////////////////
    if (inst.op == MicroInstrOpcode::LoadMemImm)
    {
        if (ops[1].opBits == MicroOpBits::B128 || ops[1].opBits == MicroOpBits::Zero)
        {
            outIssue.kind             = MicroConformanceIssueKind::NormalizeOpBits;
            outIssue.operandIndex     = 1;
            outIssue.normalizedOpBits = MicroOpBits::B64;
            return true;
        }

        const bool immediateIsEncodable = immediateFitsOperand(ops[3], ops[1].opBits);
        if (ops[1].opBits == MicroOpBits::B64 && !immediateIsEncodable)
        {
            outIssue.kind = MicroConformanceIssueKind::SplitLoadMemImm64;
            return true;
        }

        if (!immediateIsEncodable)
        {
            outIssue.kind         = MicroConformanceIssueKind::ClampImmediate;
            outIssue.operandIndex = 3;
            switch (ops[1].opBits)
            {
                case MicroOpBits::B8:
                    outIssue.valueLimitU64 = 0xFF;
                    return true;
                case MicroOpBits::B16:
                    outIssue.valueLimitU64 = 0xFFFF;
                    return true;
                case MicroOpBits::B32:
                    outIssue.valueLimitU64 = 0xFFFFFFFF;
                    return true;
                default:
                    outIssue.kind             = MicroConformanceIssueKind::NormalizeOpBits;
                    outIssue.operandIndex     = 1;
                    outIssue.normalizedOpBits = MicroOpBits::B64;
                    return true;
            }
        }
    }

    ///////////////////////////////////////////
    if (inst.op == MicroInstrOpcode::LoadAmcMemImm)
    {
        const bool immediateIsEncodable = immediateFitsOperand(ops[7], ops[4].opBits);
        if (ops[4].opBits == MicroOpBits::B64 && !immediateIsEncodable)
        {
            outIssue.kind = MicroConformanceIssueKind::SplitLoadAmcMemImm64;
            return true;
        }

        if (!immediateIsEncodable)
        {
            outIssue.kind         = MicroConformanceIssueKind::ClampImmediate;
            outIssue.operandIndex = 7;
            switch (ops[4].opBits)
            {
                case MicroOpBits::B8:
                    outIssue.valueLimitU64 = 0xFF;
                    return true;
                case MicroOpBits::B16:
                    outIssue.valueLimitU64 = 0xFFFF;
                    return true;
                case MicroOpBits::B32:
                    outIssue.valueLimitU64 = 0xFFFFFFFF;
                    return true;
                default:
                    outIssue.kind             = MicroConformanceIssueKind::NormalizeOpBits;
                    outIssue.operandIndex     = 4;
                    outIssue.normalizedOpBits = MicroOpBits::B64;
                    return true;
            }
        }
    }

    ///////////////////////////////////////////
    if (inst.op == MicroInstrOpcode::LoadAddrAmcRegMem)
    {
        const uint64_t mulValue = ops[5].valueU64;
        if (mulValue != 1 && mulValue != 2 && mulValue != 4 && mulValue != 8)
        {
            outIssue.kind = MicroConformanceIssueKind::RewriteLoadAddrAmcScale;
            return true;
        }
    }

    return false;
}

void X64Encoder::encodePush(MicroReg reg)
{
    const auto x64Reg = microRegToX64Reg(reg);
    if (isExtendedReg(x64Reg))
        store_.pushU8(getRex(false, false, false, true));
    emitCpuOp(store_, 0x50, reg);
}

void X64Encoder::encodePop(MicroReg reg)
{
    const auto x64Reg = microRegToX64Reg(reg);
    if (isExtendedReg(x64Reg))
        store_.pushU8(getRex(false, false, false, true));
    emitCpuOp(store_, 0x58, reg);
}

void X64Encoder::encodeRet()
{
    emitCpuOp(store_, 0xC3);
}

// ============================================================================

void X64Encoder::encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits)
{
    if (regDst.isFloat() && regSrc.isFloat())
    {
        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, MicroOpBits::Zero, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x10);
        emitModRm(store_, regDst, regSrc);
    }
    else if (regDst.isFloat())
    {
        emitPrefixF64(store_, MicroOpBits::B64);
        emitRex(store_, opBits, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x6E);
        emitModRm(store_, regDst, regSrc);
    }
    else if (regSrc.isFloat())
    {
        emitPrefixF64(store_, MicroOpBits::B64);
        emitRex(store_, opBits, regSrc, regDst);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x7E);
        emitModRm(store_, regSrc, regDst);
    }
    else
    {
        const auto x64Src = microRegToX64Reg(regSrc);
        const auto x64Dst = microRegToX64Reg(regDst);

        if (opBits == MicroOpBits::B16)
            store_.pushU8(0x66);

        const bool rexR         = isExtendedReg(x64Src);
        const bool rexB         = isExtendedReg(x64Dst);
        const bool needsByteRex = opBits == MicroOpBits::B8 && (needsRexForByteReg(x64Src) || needsRexForByteReg(x64Dst));
        if (opBits == MicroOpBits::B64 || rexR || rexB || needsByteRex)
            store_.pushU8(getRex(opBits == MicroOpBits::B64, rexR, false, rexB));

        emitSpecCpuOp(store_, getX64RegMemOpCode(MicroOp::Move), opBits);
        emitModRm(store_, regSrc, regDst);
    }
}

void X64Encoder::encodeLoadRegImm(MicroReg reg, const ApInt& value, MicroOpBits opBits)
{
    SWC_INTERNAL_CHECK(!reg.isFloat());
    const uint64_t valueU64 = immediateToU64(value);

    if (opBits == MicroOpBits::B8)
    {
        emitRex(store_, opBits, MicroReg{}, reg);
        emitCpuOp(store_, 0xB0, reg);
        emitValue(store_, valueU64, opBits);
    }
    else
    {
        emitRex(store_, opBits, MicroReg{}, reg);
        emitCpuOp(store_, 0xB8, reg);
        emitValue(store_, valueU64, opBits);
    }
}

void X64Encoder::encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits)
{
    SWC_ASSERT(!memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));

    // Instruction-pointer-relative form: a constant, or a global living in
    // the proximity arena. The displacement is left at zero and a Relative32
    // relocation fills in the distance once both the code and the target have
    // addresses; ModRM mode 00 with rm 101 is what selects it, so the four
    // bytes are mandatory even when the distance ends up small.
    if (memReg.isInstructionPointer())
    {
        SWC_ASSERT(memOffset == 0);
        if (reg.isFloat())
        {
            emitSpecF64(store_, 0xF3, opBits);
            emitRex(store_, MicroOpBits::Zero, reg, memReg);
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x10);
        }
        else
        {
            emitRex(store_, opBits, reg, memReg);
            emitSpecCpuOp(store_, MicroOp::Move, opBits);
        }
        emitModRm(store_, ModRmMode::Memory, reg, MODRM_RM_RIP);
        store_.pushU32(0);
        return;
    }

    if (reg.isFloat())
    {
        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, MicroOpBits::Zero, reg, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x10);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else
    {
        emitRex(store_, opBits, reg, memReg);
        emitSpecCpuOp(store_, MicroOp::Move, opBits);
        emitModRm(store_, memOffset, reg, memReg);
    }
}

void X64Encoder::encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);
    SWC_ASSERT(!memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));

    if (numBitsSrc == MicroOpBits::B8 && (numBitsDst == MicroOpBits::B16 || numBitsDst == MicroOpBits::B32 || numBitsDst == MicroOpBits::B64))
    {
        emitRex(store_, numBitsDst, reg, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB6);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else if (numBitsSrc == MicroOpBits::B16 && (numBitsDst == MicroOpBits::B32 || numBitsDst == MicroOpBits::B64))
    {
        emitRex(store_, numBitsDst, reg, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB7);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else if (numBitsSrc == MicroOpBits::B32 && numBitsDst == MicroOpBits::B64)
    {
        return encodeLoadRegMem(reg, memReg, memOffset, numBitsSrc);
    }
    else
    {
        SWC_INTERNAL_ERROR();
    }
}

void X64Encoder::encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);
    SWC_ASSERT(!regDst.isFloat());
    SWC_ASSERT(!regSrc.isFloat() || (numBitsSrc == MicroOpBits::B32 && numBitsDst == MicroOpBits::B64));

    if (numBitsSrc == MicroOpBits::B8 && (numBitsDst == MicroOpBits::B16 || numBitsDst == MicroOpBits::B32 || numBitsDst == MicroOpBits::B64))
    {
        emitRex(store_, numBitsDst, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB6);
        emitModRm(store_, regDst, regSrc);
    }
    else if (numBitsSrc == MicroOpBits::B16 && (numBitsDst == MicroOpBits::B32 || numBitsDst == MicroOpBits::B64))
    {
        emitRex(store_, MicroOpBits::B64, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB7);
        emitModRm(store_, regDst, regSrc);
    }
    else if (numBitsSrc == MicroOpBits::B32 && numBitsDst == MicroOpBits::B64)
    {
        return encodeLoadRegReg(regDst, regSrc, numBitsSrc);
    }
    else
    {
        SWC_INTERNAL_ERROR();
    }
}

void X64Encoder::encodeLoadSignedExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);
    SWC_ASSERT(!memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));

    if (numBitsSrc == MicroOpBits::B8)
    {
        emitRex(store_, numBitsDst, reg, memReg);
        store_.pushU8(0x0F);
        store_.pushU8(0xBE);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else if (numBitsSrc == MicroOpBits::B16)
    {
        emitRex(store_, numBitsDst, reg, memReg);
        store_.pushU8(0x0F);
        store_.pushU8(0xBF);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else if (numBitsSrc == MicroOpBits::B32)
    {
        SWC_ASSERT(numBitsDst == MicroOpBits::B64);
        emitRex(store_, MicroOpBits::B64, reg, memReg);
        emitCpuOp(store_, MicroOp::MoveSignExtend);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else
    {
        SWC_INTERNAL_ERROR();
    }
}

void X64Encoder::encodeLoadSignedExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);
    SWC_ASSERT(!(regDst.isFloat() || regSrc.isFloat()));

    if (numBitsSrc == MicroOpBits::B8)
    {
        emitRex(store_, numBitsDst, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xBE);
        emitModRm(store_, regDst, regSrc);
    }
    else if (numBitsSrc == MicroOpBits::B16)
    {
        emitRex(store_, numBitsDst, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xBF);
        emitModRm(store_, regDst, regSrc);
    }
    else if (numBitsSrc == MicroOpBits::B32 && numBitsDst == MicroOpBits::B64)
    {
        emitRex(store_, numBitsDst, regDst, regSrc);
        emitCpuOp(store_, MicroOp::MoveSignExtend);
        emitModRm(store_, regDst, regSrc);
    }
    else
    {
        SWC_INTERNAL_ERROR();
    }
}

// ============================================================================

void X64Encoder::encodeLoadAddressRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits)
{
    SWC_ASSERT(!memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));

    if (memReg.isInstructionPointer())
    {
        SWC_ASSERT(memOffset == 0);
        emitRex(store_, MicroOpBits::B64, reg, memReg);
        emitCpuOp(store_, MicroOp::LoadEffectiveAddress);
        emitModRm(store_, ModRmMode::Memory, reg, MODRM_RM_RIP);
    }
    else if (memOffset == 0)
    {
        encodeLoadRegReg(reg, memReg, MicroOpBits::B64);
    }
    else
    {
        emitRex(store_, MicroOpBits::B64, reg, memReg);
        emitCpuOp(store_, MicroOp::LoadEffectiveAddress);
        emitModRm(store_, memOffset, reg, memReg);
    }
}

namespace
{
    void encodeAmcImm(PagedStore& store, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, const ApInt& value, MicroOpBits opBitsValue)
    {
        SWC_UNUSED(opBitsBaseMul);
        SWC_INTERNAL_CHECK(canEncodeSigned32(addValue));
        const uint64_t valueU64 = immediateToU64(value);

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

        const bool needsForcedDisplacement = !baseIsNoBase && (baseX64 == X64Reg::R13 || baseX64 == X64Reg::Rbp);

        // ModRM
        if (needsForcedDisplacement)
            emitModRm(store, canEncodeSigned8(addValue) ? ModRmMode::Displacement8 : ModRmMode::Displacement32, MODRM_REG_0, MODRM_RM_SIB);
        else if (addValue == 0 || baseIsNoBase)
            emitModRm(store, ModRmMode::Memory, MODRM_REG_0, MODRM_RM_SIB);
        else
            emitModRm(store, canEncodeSigned8(addValue) ? ModRmMode::Displacement8 : ModRmMode::Displacement32, MODRM_REG_0, MODRM_RM_SIB);

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
            if (needsForcedDisplacement || addValue != 0)
                emitValue(store, addValue, canEncodeSigned8(addValue) ? MicroOpBits::B8 : MicroOpBits::B32);
        }

        // Value
        emitValue(store, valueU64, std::min(opBitsValue, MicroOpBits::B32));
    }

    // cmp [base + index*scale + disp], imm — same SIB machinery as
    // encodeAmcImm, with the compare opcode family (0x80 /7 ib, 0x83 /7 ib,
    // 0x81 /7 iw/id) instead of the move. Addressing is always 64-bit here.
    void encodeAmcCmpImm(PagedStore& store, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, const ApInt& value, MicroOpBits opBitsValue)
    {
        SWC_INTERNAL_CHECK(canEncodeSigned32(addValue));
        const uint64_t valueU64 = immediateToU64(value);

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
        MicroOpBits immBits = MicroOpBits::B8;
        if (opBitsValue == MicroOpBits::B8)
        {
            store.pushU8(0x80);
        }
        else if (canEncode8(valueU64, opBitsValue))
        {
            store.pushU8(0x83);
        }
        else if (canEncodeOpImmediate(valueU64, opBitsValue))
        {
            store.pushU8(0x81);
            immBits = opBitsValue == MicroOpBits::B16 ? MicroOpBits::B16 : MicroOpBits::B32;
        }
        else
        {
            SWC_INTERNAL_ERROR();
        }

        const bool needsForcedDisplacement = !baseIsNoBase && (baseX64 == X64Reg::R13 || baseX64 == X64Reg::Rbp);

        // ModRM
        if (needsForcedDisplacement)
            emitModRm(store, canEncodeSigned8(addValue) ? ModRmMode::Displacement8 : ModRmMode::Displacement32, MODRM_REG_7, MODRM_RM_SIB);
        else if (addValue == 0 || baseIsNoBase)
            emitModRm(store, ModRmMode::Memory, MODRM_REG_7, MODRM_RM_SIB);
        else
            emitModRm(store, canEncodeSigned8(addValue) ? ModRmMode::Displacement8 : ModRmMode::Displacement32, MODRM_REG_7, MODRM_RM_SIB);

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
            if (needsForcedDisplacement || addValue != 0)
                emitValue(store, addValue, canEncodeSigned8(addValue) ? MicroOpBits::B8 : MicroOpBits::B32);
        }

        // Value
        emitValue(store, valueU64, immBits);
    }

    void encodeAmcReg(PagedStore& store, MicroReg reg, MicroOpBits opBitsReg, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroOp op, bool mr, MicroOpBits zeroExtSrcBits = MicroOpBits::Zero)
    {
        SWC_INTERNAL_CHECK(canEncodeSigned32(addValue));

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
        if (reg.isFloat() && opBitsReg == MicroOpBits::B128)
            store.pushU8(0xF3); // movdqu (128-bit) - mandatory prefix, not the 0x66 of movd/movq
        else if (opBitsReg == MicroOpBits::B16 || reg.isFloat())
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
                emitSpecCpuOp(store, MicroOp::LoadEffectiveAddress, opBitsReg);
                break;
            case MicroOp::MoveSignExtend:
                emitSpecCpuOp(store, MicroOp::MoveSignExtend, opBitsReg);
                break;
            case MicroOp::Move:
                if (zeroExtSrcBits != MicroOpBits::Zero)
                {
                    // Indexed movzx: 0F B6 (byte source) / 0F B7 (word source);
                    // the destination width rides the prefixes emitted above.
                    SWC_ASSERT(!mr && !reg.isFloat());
                    SWC_ASSERT(zeroExtSrcBits == MicroOpBits::B8 || zeroExtSrcBits == MicroOpBits::B16);
                    emitCpuOp(store, 0x0F);
                    emitCpuOp(store, zeroExtSrcBits == MicroOpBits::B8 ? 0xB6 : 0xB7);
                }
                else if (reg.isFloat())
                {
                    emitCpuOp(store, 0x0F);
                    if (opBitsReg == MicroOpBits::B128)
                        emitCpuOp(store, mr ? 0x7F : 0x6F); // movdqu store/load (128-bit)
                    else
                        emitCpuOp(store, mr ? 0x7E : 0x6E); // movd/movq store/load (32/64-bit)
                }
                else
                {
                    emitSpecCpuOp(store, mr ? getX64RegMemOpCode(MicroOp::Move) : getX64OpCode(MicroOp::Move), opBitsReg);
                }
                break;
            default:
                SWC_UNREACHABLE();
        }

        const bool needsForcedDisplacement = !baseIsNoBase && (baseX64 == X64Reg::R13 || baseX64 == X64Reg::Rbp);

        // ModRM
        if (needsForcedDisplacement)
            emitModRm(store, canEncodeSigned8(addValue) ? ModRmMode::Displacement8 : ModRmMode::Displacement32, reg, MODRM_RM_SIB);
        else if (addValue == 0 || baseIsNoBase)
            emitModRm(store, ModRmMode::Memory, reg, MODRM_RM_SIB);
        else
            emitModRm(store, canEncodeSigned8(addValue) ? ModRmMode::Displacement8 : ModRmMode::Displacement32, reg, MODRM_RM_SIB);

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
            if (needsForcedDisplacement || addValue != 0)
                emitValue(store, addValue, canEncodeSigned8(addValue) ? MicroOpBits::B8 : MicroOpBits::B32);
        }
    }
}

void X64Encoder::encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc)
{
    return encodeAmcReg(store_, regDst, opBitsDst, regBase, regMul, mulValue, addValue, opBitsSrc, MicroOp::Move, false);
}

void X64Encoder::encodeVecGatherS32(MicroReg regDst, MicroReg baseReg, MicroReg indicesReg)
{
    SWC_ASSERT(regDst.isFloat());
    SWC_ASSERT(baseReg.isInt());
    SWC_ASSERT(indicesReg.isFloat());

    const X64Reg     dstX64     = microRegToX64Reg(regDst);
    const X64Reg     baseX64    = microRegToX64Reg(baseReg);
    const X64Reg     indicesX64 = microRegToX64Reg(indicesReg);
    constexpr X64Reg K_MASK     = X64Reg::Xmm15;
    SWC_ASSERT(dstX64 != K_MASK && indicesX64 != K_MASK && dstX64 != indicesX64);

    // VPGATHERDD clears every mask lane it consumes, so rebuild an all-ones
    // mask for each operation: vpcmpeqd xmm15, xmm15, xmm15.
    emitVex(store_, 0x66, VEX_MAP_0F, K_MASK, K_MASK, K_MASK);
    store_.pushU8(0x76);
    emitModRm(store_, x64RegToMicroReg(K_MASK), x64RegToMicroReg(K_MASK));

    // VEX.128.66.0F38.W0 90 /r with VSIB addressing. Unlike an ordinary
    // ModRM/SIB load, VEX.X extends the vector index and VEX.B extends the
    // integer base.
    const uint8_t pp   = vexPrefixBits(0x66);
    const uint8_t vvvv = static_cast<uint8_t>(~x64RegNumber(K_MASK) & 0x0F);
    store_.pushU8(0xC4);
    store_.pushU8(static_cast<uint8_t>((isExtendedReg(dstX64) ? 0 : 0x80) |
                                       (isExtendedReg(indicesX64) ? 0 : 0x40) |
                                       (isExtendedReg(baseX64) ? 0 : 0x20) |
                                       VEX_MAP_0F38));
    store_.pushU8(static_cast<uint8_t>((vvvv << 3) | pp));
    store_.pushU8(0x90);

    const bool needsDisplacement = (encodeReg(baseX64) & 0b111) == 0b101;
    emitModRm(store_, needsDisplacement ? ModRmMode::Displacement8 : ModRmMode::Memory, encodeReg(dstX64), MODRM_RM_SIB);
    emitSib(store_, 2, encodeReg(indicesX64) & 0b111, encodeReg(baseX64) & 0b111);
    if (needsDisplacement)
        store_.pushU8(0);
}

void X64Encoder::encodeLoadSignedExtendAmcRegMem(MicroReg regDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits numBitsDst, MicroOpBits numBitsSrc)
{
    // Indexed movsxd: load a 32-bit dword from [base + index*scale + disp] and
    // sign-extend it into a 64-bit register. encodeAmcReg's MoveSignExtend path
    // emits the 0x63 opcode (dword->qword), so only b32->b64 is supported; the
    // 32-bit source width is implicit in the opcode. The base/index addressing is
    // 64-bit on this target (no 0x67 prefix).
    SWC_ASSERT(numBitsDst == MicroOpBits::B64 && numBitsSrc == MicroOpBits::B32);
    return encodeAmcReg(store_, regDst, MicroOpBits::B64, regBase, regMul, mulValue, addValue, MicroOpBits::B64, MicroOp::MoveSignExtend, false);
}

void X64Encoder::encodeLoadZeroExtendAmcRegMem(MicroReg regDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits numBitsDst, MicroOpBits numBitsSrc)
{
    // Indexed movzx: load a byte or word from [base + index*scale + disp] and
    // zero-extend it into a 32- or 64-bit register.
    SWC_ASSERT(numBitsDst == MicroOpBits::B32 || numBitsDst == MicroOpBits::B64);
    SWC_ASSERT(numBitsSrc == MicroOpBits::B8 || numBitsSrc == MicroOpBits::B16);
    return encodeAmcReg(store_, regDst, numBitsDst, regBase, regMul, mulValue, addValue, MicroOpBits::B64, MicroOp::Move, false, numBitsSrc);
}

void X64Encoder::encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc)
{
    return encodeAmcReg(store_, regSrc, opBitsSrc, regBase, regMul, mulValue, addValue, opBitsBaseMul, MicroOp::Move, true);
}

void X64Encoder::encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, const ApInt& value, MicroOpBits opBitsValue)
{
    return encodeAmcImm(store_, regBase, regMul, mulValue, addValue, opBitsBaseMul, value, opBitsValue);
}

void X64Encoder::encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue)
{
    return encodeAmcReg(store_, regDst, opBitsDst, regBase, regMul, mulValue, addValue, opBitsValue, MicroOp::LoadEffectiveAddress, false);
}

void X64Encoder::encodeCmpAmcImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, const ApInt& value, MicroOpBits opBits)
{
    SWC_ASSERT(!regBase.isFloat() && !regMul.isFloat());
    return encodeAmcCmpImm(store_, regBase, regMul, mulValue, addValue, value, opBits);
}

// ============================================================================

// movdqu xmm, m128   (F3 0F 6F /r) : unaligned 128-bit packed load.
void X64Encoder::encodeLoadVecRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits)
{
    SWC_ASSERT(opBits == MicroOpBits::B128 && regDst.isFloat() && !memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));
    emitCpuOp(store_, 0xF3);
    emitRex(store_, MicroOpBits::Zero, regDst, memReg);
    emitCpuOp(store_, 0x0F);
    emitCpuOp(store_, 0x6F);
    emitModRm(store_, memOffset, regDst, memReg);
}

// movdqu m128, xmm   (F3 0F 7F /r) : unaligned 128-bit packed store.
void X64Encoder::encodeStoreVecMemReg(MicroReg memReg, uint64_t memOffset, MicroReg regSrc, MicroOpBits opBits)
{
    SWC_ASSERT(opBits == MicroOpBits::B128 && regSrc.isFloat() && !memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));
    emitCpuOp(store_, 0xF3);
    emitRex(store_, MicroOpBits::Zero, regSrc, memReg);
    emitCpuOp(store_, 0x0F);
    emitCpuOp(store_, 0x7F);
    emitModRm(store_, memOffset, regSrc, memReg);
}

// pshufd xmm, xmm, imm8   (66 0F 70 /r ib) : four-lane 32-bit permute.
void X64Encoder::encodeVecShuffleRegRegImm(MicroReg regDst, MicroReg regSrc, uint64_t control, MicroOpBits opBits)
{
    SWC_ASSERT(opBits == MicroOpBits::B128 && regDst.isFloat() && regSrc.isFloat());
    SWC_ASSERT(control <= 0xFF);
    emitCpuOp(store_, 0x66);
    emitRex(store_, MicroOpBits::Zero, regDst, regSrc);
    emitCpuOp(store_, 0x0F);
    emitCpuOp(store_, 0x70);
    emitModRm(store_, regDst, regSrc);
    emitValue(store_, control, MicroOpBits::B8);
}

void X64Encoder::encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits)
{
    SWC_ASSERT(!memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));

    // Instruction-pointer-relative store, to a global living in the proximity
    // arena. Same shape as the RIP-relative load: zero displacement patched by
    // a Relative32 relocation, and the four bytes are the instruction's tail.
    if (memReg.isInstructionPointer())
    {
        SWC_ASSERT(memOffset == 0);
        if (reg.isFloat())
        {
            emitSpecF64(store_, 0xF3, opBits);
            emitRex(store_, MicroOpBits::Zero, reg, memReg);
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x11);
        }
        else
        {
            emitRex(store_, opBits, reg, memReg);
            emitSpecCpuOp(store_, getX64RegMemOpCode(MicroOp::Move), opBits);
        }
        emitModRm(store_, ModRmMode::Memory, reg, MODRM_RM_RIP);
        store_.pushU32(0);
        return;
    }

    if (reg.isFloat())
    {
        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, MicroOpBits::Zero, reg, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x11);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else
    {
        emitRex(store_, opBits, reg, memReg);
        emitSpecCpuOp(store_, getX64RegMemOpCode(MicroOp::Move), opBits);
        emitModRm(store_, memOffset, reg, memReg);
    }
}

void X64Encoder::encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, const ApInt& value, MicroOpBits opBits)
{
    SWC_ASSERT(!memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));
    SWC_INTERNAL_CHECK(opBits != MicroOpBits::B128);
    uint64_t valueU64 = immediateToU64(value);

    if (!canEncodeOpImmediate(valueU64, opBits))
    {
        if (opBits == MicroOpBits::B64)
        {
            const auto lowU32  = static_cast<uint32_t>(valueU64 & 0xFFFFFFFFu);
            const auto highU32 = static_cast<uint32_t>((valueU64 >> 32) & 0xFFFFFFFFu);
            encodeLoadMemImm(memReg, memOffset, ApInt(lowU32, 64), MicroOpBits::B32);
            encodeLoadMemImm(memReg, memOffset + 4, ApInt(highU32, 64), MicroOpBits::B32);
            return;
        }

        if (opBits == MicroOpBits::B8)
            valueU64 &= 0xFF;
        else if (opBits == MicroOpBits::B16)
            valueU64 &= 0xFFFF;
        else if (opBits == MicroOpBits::B32)
            valueU64 &= 0xFFFFFFFF;
    }

    emitRex(store_, opBits, MicroReg{}, memReg);
    emitSpecB8(store_, 0xC7, opBits);
    emitModRm(store_, memOffset, MODRM_REG_0, memReg);
    emitValue(store_, valueU64, std::min(opBits, MicroOpBits::B32));
}

// ============================================================================

void X64Encoder::encodeClearReg(MicroReg reg, MicroOpBits opBits)
{
    if (reg.isFloat())
    {
        emitPrefixF64(store_, opBits);
        emitRex(store_, MicroOpBits::Zero, reg, reg);
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
}

// ============================================================================

void X64Encoder::encodeSetCondReg(MicroReg reg, MicroCond cpuCond)
{
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
            SWC_UNREACHABLE();
    }

    emitModRm(store_, MODRM_REG_0, reg);
}

void X64Encoder::encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits)
{
    opBits = std::max(opBits, MicroOpBits::B32);
    emitRex(store_, opBits, regDst, regSrc);
    emitCpuOp(store_, 0x0F);

    switch (setType)
    {
        case MicroCond::Overflow:
            emitCpuOp(store_, 0x40);
            break;
        case MicroCond::NotOverflow:
            emitCpuOp(store_, 0x41);
            break;
        case MicroCond::Below:
            emitCpuOp(store_, 0x42);
            break;
        case MicroCond::AboveOrEqual:
            emitCpuOp(store_, 0x43);
            break;
        case MicroCond::Equal:
        case MicroCond::Zero:
            emitCpuOp(store_, 0x44);
            break;
        case MicroCond::NotEqual:
        case MicroCond::NotZero:
            emitCpuOp(store_, 0x45);
            break;
        case MicroCond::BelowOrEqual:
        case MicroCond::NotAbove:
            emitCpuOp(store_, 0x46);
            break;
        case MicroCond::Above:
            emitCpuOp(store_, 0x47);
            break;
        case MicroCond::Sign:
            emitCpuOp(store_, 0x48);
            break;
        case MicroCond::Parity:
        case MicroCond::EvenParity:
            emitCpuOp(store_, 0x4A);
            break;
        case MicroCond::NotParity:
        case MicroCond::NotEvenParity:
            emitCpuOp(store_, 0x4B);
            break;
        case MicroCond::Less:
            emitCpuOp(store_, 0x4C);
            break;
        case MicroCond::GreaterOrEqual:
            emitCpuOp(store_, 0x4D);
            break;
        case MicroCond::LessOrEqual:
            emitCpuOp(store_, 0x4E);
            break;
        case MicroCond::Greater:
            emitCpuOp(store_, 0x4F);
            break;
        default:
            SWC_UNREACHABLE();
    }

    emitModRm(store_, regDst, regSrc);
}

// ============================================================================

void X64Encoder::encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits)
{
    if (reg0.isFloat())
    {
        SWC_ASSERT(!reg1.isInt());

        emitPrefixF64(store_, opBits);
        emitRex(store_, MicroOpBits::Zero, reg0, reg1);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x2F);
        emitModRm(store_, reg0, reg1);
    }
    else
    {
        emitRex(store_, opBits, reg1, reg0);
        emitSpecCpuOp(store_, MicroOp::Compare, opBits);
        emitModRm(store_, reg1, reg0);
    }
}

void X64Encoder::encodeCmpRegImm(MicroReg reg, const ApInt& value, MicroOpBits opBits)
{
    SWC_ASSERT(!reg.isFloat());
    const uint64_t valueU64 = immediateToU64(value);

    if (valueU64 == 0)
    {
        SWC_ASSERT(reg.isInt());
        emitRex(store_, opBits, reg, reg);
        emitSpecCpuOp(store_, MicroOp::Test, opBits);
        emitModRm(store_, reg, reg);
        return;
    }

    if (opBits == MicroOpBits::B8)
    {
        emitRex(store_, opBits, MicroReg{}, reg);
        emitCpuOp(store_, 0x80);
        emitModRm(store_, MODRM_REG_7, reg);
        emitValue(store_, valueU64, MicroOpBits::B8);
    }
    else if (canEncode8(valueU64, opBits))
    {
        emitRex(store_, opBits, MicroReg{}, reg);
        emitCpuOp(store_, 0x83);
        emitModRm(store_, MODRM_REG_7, reg);
        emitValue(store_, valueU64, MicroOpBits::B8);
    }
    else if (canEncodeOpImmediate(valueU64, opBits))
    {
        emitRex(store_, opBits, MicroReg{}, reg);
        emitCpuOp(store_, 0x81);
        emitModRm(store_, MODRM_REG_7, reg);
        emitValue(store_, valueU64, std::min(opBits, MicroOpBits::B32));
    }
    else
    {
        SWC_INTERNAL_ERROR();
    }
}

void X64Encoder::encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits)
{
    SWC_ASSERT(!memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));
    SWC_ASSERT(!reg.isFloat());

    emitRex(store_, opBits, reg, memReg);
    emitSpecCpuOp(store_, MicroOp::Compare, opBits);
    emitModRm(store_, memOffset, reg, memReg);
}

void X64Encoder::encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, const ApInt& value, MicroOpBits opBits)
{
    SWC_ASSERT(!memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));
    const uint64_t valueU64 = immediateToU64(value);

    if (opBits == MicroOpBits::B8)
    {
        emitRex(store_, opBits, MicroReg{}, memReg);
        emitCpuOp(store_, 0x80);
        emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        emitValue(store_, valueU64, MicroOpBits::B8);
    }
    else if (canEncode8(valueU64, opBits))
    {
        emitRex(store_, opBits, MicroReg{}, memReg);
        emitCpuOp(store_, 0x83);
        emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        emitValue(store_, valueU64, MicroOpBits::B8);
    }
    else if (canEncodeOpImmediate(valueU64, opBits))
    {
        emitRex(store_, opBits, MicroReg{}, memReg);
        emitCpuOp(store_, 0x81);
        emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        emitValue(store_, valueU64, opBits == MicroOpBits::B16 ? opBits : MicroOpBits::B32);
    }
    else
    {
        SWC_INTERNAL_ERROR();
    }
}

// ============================================================================

void X64Encoder::encodeOpUnaryMem(MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits)
{
    SWC_ASSERT(!memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));

    ///////////////////////////////////////////
    if (op == MicroOp::BitwiseNot)
    {
        emitRex(store_, opBits);
        emitSpecCpuOp(store_, MicroOp::BitwiseNot, opBits);
        emitModRm(store_, memOffset, MODRM_REG_2, memReg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Negate)
    {
        emitRex(store_, opBits);
        emitSpecCpuOp(store_, MicroOp::BitwiseNot, opBits);
        emitModRm(store_, memOffset, MODRM_REG_3, memReg);
    }

    ///////////////////////////////////////////

    else
    {
        SWC_INTERNAL_ERROR();
    }
}

void X64Encoder::encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits)
{
    ///////////////////////////////////////////

    if (op == MicroOp::BitwiseNot)
    {
        emitRex(store_, opBits, MicroReg{}, reg);
        emitSpecCpuOp(store_, MicroOp::BitwiseNot, opBits);
        emitModRm(store_, MODRM_REG_2, reg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Negate)
    {
        SWC_ASSERT(!reg.isFloat());

        emitRex(store_, opBits, MicroReg{}, reg);
        emitSpecCpuOp(store_, MicroOp::BitwiseNot, opBits);
        emitModRm(store_, MODRM_REG_3, reg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::ByteSwap)
    {
        if (opBits == MicroOpBits::B16)
        {
            // rol r16, 8  (C1 /0 ib)
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0xC1);
            emitModRm(store_, MODRM_REG_0, reg);
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
        SWC_INTERNAL_ERROR();
    }
}

void X64Encoder::encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits)
{
    SWC_ASSERT(!memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));

    ///////////////////////////////////////////
    // Float arithmetic reads memory directly, exactly as the register form does
    // but with a memory ModRM. Without this the operand has to be loaded into a
    // register first, which is a whole extra instruction every time a value
    // comes from a spill slot.
    if (regDst.isFloat())
    {
        if (op != MicroOp::FloatSqrt && op != MicroOp::FloatAnd && op != MicroOp::FloatXor)
        {
            emitSpecF64(store_, 0xF3, opBits);
            emitRex(store_, MicroOpBits::Zero, regDst, memReg);
        }
        else
        {
            emitPrefixF64(store_, opBits);
            emitRex(store_, MicroOpBits::Zero, regDst, memReg);
        }

        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, op);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Add)
    {
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, getX64RegMemOpCode(op), opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Subtract)
    {
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, getX64RegMemOpCode(op), opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::And)
    {
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, getX64RegMemOpCode(op), opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Or)
    {
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, getX64RegMemOpCode(op), opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Xor)
    {
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, getX64RegMemOpCode(op), opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::MultiplySigned)
    {
        if (opBits == MicroOpBits::B8)
        {
            // One-operand IMUL r/m8 from memory: AL * [mem] -> AX, OF correct for s8.
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitSpecCpuOp(store_, MicroOp::BitwiseNot, opBits);
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
        }
        else
        {
            emitRex(store_, opBits, regDst, memReg);
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0xAF);
            emitModRm(store_, memOffset, regDst, memReg);
        }
    }

    ///////////////////////////////////////////

    else
    {
        SWC_INTERNAL_ERROR();
    }
}

void X64Encoder::encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits)
{
    ///////////////////////////////////////////

    SWC_ASSERT(op != MicroOp::ConvertUIntToFloat64);

    ///////////////////////////////////////////
    // 128-bit packed integer forms (SSE2): 66 0F <op> /r with the destination
    // in the reg field. The lane width is carried by the operation itself;
    // opBits is the full vector width. Only the 0F-map 66-prefixed operations
    // have this destructive legacy shape; everything else goes through the
    // VEX three-operand form.
    if (isVecMicroOp(op))
    {
        SWC_ASSERT(opBits == MicroOpBits::B128 && regDst.isFloat() && regSrc.isFloat());

        const VecOpEncoding enc = vecOpEncoding(op);
        SWC_ASSERT(enc.map == VEX_MAP_0F && enc.prefix == 0x66);
        emitCpuOp(store_, 0x66);
        emitRex(store_, MicroOpBits::Zero, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, enc.opcode);
        emitModRm(store_, regDst, regSrc);
        return;
    }

    ///////////////////////////////////////////
    if (regDst.isFloat() && regSrc.isInt())
    {
        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, opBits, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, op);
        emitModRm(store_, regDst, regSrc);
    }

    else if (regDst.isInt() && regSrc.isFloat())
    {
        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, opBits, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, op);
        emitModRm(store_, regDst, regSrc);
    }

    else if (regDst.isFloat() && regSrc.isFloat())
    {
        if (op != MicroOp::FloatSqrt && op != MicroOp::FloatAnd && op != MicroOp::FloatXor)
        {
            emitSpecF64(store_, 0xF3, opBits);
            emitRex(store_, opBits, regDst, regSrc);
        }
        else
        {
            emitPrefixF64(store_, opBits);
            emitRex(store_, MicroOpBits::Zero, regDst, regSrc);
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
        if ((op == MicroOp::DivideSigned || op == MicroOp::ModuloSigned) && opBits == MicroOpBits::B8)
            encodeLoadSignedExtendRegReg(rax, rax, MicroOpBits::B32, MicroOpBits::B8);
        else if (opBits == MicroOpBits::B8)
            encodeLoadZeroExtendRegReg(rax, rax, MicroOpBits::B32, MicroOpBits::B8);
        else if (op == MicroOp::DivideUnsigned || op == MicroOp::ModuloUnsigned)
            encodeClearReg(x64RegToMicroReg(X64Reg::Rdx), opBits);
        else
        {
            emitRex(store_, opBits);
            emitCpuOp(store_, 0x99); // cdq
        }

        emitRex(store_, opBits, rax, regSrc);
        emitSpecCpuOp(store_, MicroOp::BitwiseNot, opBits);
        if (op == MicroOp::DivideUnsigned || op == MicroOp::ModuloUnsigned)
            emitModRm(store_, MODRM_REG_6, regSrc);
        else if (op == MicroOp::DivideSigned || op == MicroOp::ModuloSigned)
            emitModRm(store_, MODRM_REG_7, regSrc);

        if ((op == MicroOp::ModuloUnsigned || op == MicroOp::ModuloSigned) && opBits == MicroOpBits::B8)
            encodeOpBinaryRegImm(rax, ApInt(8, 64), MicroOp::ShiftRight, MicroOpBits::B32); // AH => AL
        else if (op == MicroOp::ModuloUnsigned || op == MicroOp::ModuloSigned)
            encodeLoadRegReg(rax, x64RegToMicroReg(X64Reg::Rdx), opBits);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::MultiplyUnsigned)
    {
        const auto rax = x64RegToMicroReg(X64Reg::Rax);
        emitRex(store_, opBits, rax, regSrc);
        emitSpecCpuOp(store_, MicroOp::BitwiseNot, opBits);
        emitModRm(store_, MODRM_REG_4, regSrc);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::MultiplyHighSigned || op == MicroOp::MultiplyHighUnsigned)
    {
        // One-operand MUL/IMUL leaves the high half in RDX; the result contract of
        // the micro op is RAX, so move it there, like ModuloUnsigned does.
        SWC_ASSERT(opBits == MicroOpBits::B32 || opBits == MicroOpBits::B64);
        const auto rax = x64RegToMicroReg(X64Reg::Rax);
        emitRex(store_, opBits, rax, regSrc);
        emitSpecCpuOp(store_, MicroOp::BitwiseNot, opBits);
        emitModRm(store_, op == MicroOp::MultiplyHighUnsigned ? MODRM_REG_4 : MODRM_REG_5, regSrc);
        encodeLoadRegReg(rax, x64RegToMicroReg(X64Reg::Rdx), opBits);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::MultiplySigned)
    {
        if (opBits == MicroOpBits::B8)
        {
            // Two-operand IMUL has no 8-bit form. Use one-operand IMUL r/m8 (F6 /5):
            // AL * r/m8 -> AX, with OF=1 when the result doesn't fit in s8.
            const auto rax = x64RegToMicroReg(X64Reg::Rax);
            emitRex(store_, opBits, rax, regSrc);
            emitSpecCpuOp(store_, MicroOp::BitwiseNot, opBits);
            emitModRm(store_, MODRM_REG_5, regSrc);
        }
        else
        {
            emitRex(store_, opBits, regDst, regSrc);
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0xAF);
            emitModRm(store_, regDst, regSrc);
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::RotateLeft ||
             op == MicroOp::RotateRight ||
             op == MicroOp::ShiftArithmeticLeft ||
             op == MicroOp::ShiftArithmeticRight ||
             op == MicroOp::ShiftLeft ||
             op == MicroOp::ShiftRight)
    {
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
        emitRex(store_, opBits, regSrc, regDst);
        emitSpecCpuOp(store_, op, opBits);
        emitModRm(store_, regSrc, regDst);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Exchange)
    {
        emitRex(store_, opBits, regSrc, regDst);
        emitSpecCpuOp(store_, MicroOp::Exchange, opBits);
        emitModRm(store_, regSrc, regDst);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::BitScanForward || op == MicroOp::BitScanReverse)
    {
        if (opBits == MicroOpBits::B8)
        {
            encodeLoadZeroExtendRegReg(regDst, regSrc, MicroOpBits::B16, MicroOpBits::B8);
            emitRex(store_, MicroOpBits::B16, regDst, regDst);
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, op);
            emitModRm(store_, regDst, regDst);
        }
        else
        {
            emitRex(store_, opBits, regDst, regSrc);
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, op);
            emitModRm(store_, regDst, regSrc);
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::PopCount)
    {
        if (opBits == MicroOpBits::B8)
        {
            encodeLoadZeroExtendRegReg(regDst, regSrc, MicroOpBits::B16, MicroOpBits::B8);
            emitCpuOp(store_, 0xF3);
            emitRex(store_, MicroOpBits::B16, regDst, regDst);
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, MicroOp::PopCount);
            emitModRm(store_, regDst, regDst);
        }
        else
        {
            emitCpuOp(store_, 0xF3);
            emitRex(store_, opBits, regDst, regSrc);
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, MicroOp::PopCount);
            emitModRm(store_, regDst, regSrc);
        }
    }

    ///////////////////////////////////////////

    else
    {
        SWC_INTERNAL_ERROR();
    }
}

void X64Encoder::encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits)
{
    SWC_ASSERT(!memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));
    SWC_ASSERT(!reg.isFloat());
    SWC_ASSERT(!(op == MicroOp::DivideUnsigned || op == MicroOp::DivideSigned || op == MicroOp::ModuloUnsigned || op == MicroOp::ModuloSigned || op == MicroOp::MultiplySigned || op == MicroOp::MultiplyUnsigned || op == MicroOp::MultiplyHighSigned || op == MicroOp::MultiplyHighUnsigned));

    ///////////////////////////////////////////

    if (op == MicroOp::RotateLeft ||
        op == MicroOp::RotateRight ||
        op == MicroOp::ShiftArithmeticLeft ||
        op == MicroOp::ShiftArithmeticRight ||
        op == MicroOp::ShiftRight ||
        op == MicroOp::ShiftLeft)
    {
        SWC_ASSERT(microRegToX64Reg(reg) == X64Reg::Rcx);
        emitRex(store_, opBits, MicroReg{}, memReg);
        emitSpecCpuOp(store_, 0xD3, opBits);
        if (op == MicroOp::RotateLeft)
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
        else if (op == MicroOp::RotateRight)
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
        else if (op == MicroOp::ShiftArithmeticLeft || op == MicroOp::ShiftLeft)
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
        else if (op == MicroOp::ShiftArithmeticRight)
            emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        else if (op == MicroOp::ShiftRight)
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
    }

    ///////////////////////////////////////////

    else
    {
        emitRex(store_, opBits, reg, memReg);
        emitSpecCpuOp(store_, op, opBits);
        emitModRm(store_, memOffset, reg, memReg);
    }
}

void X64Encoder::encodeOpBinaryRegImm(MicroReg reg, const ApInt& valueInt, MicroOp op, MicroOpBits opBits)
{
    const uint64_t value = immediateToU64(valueInt);

    ///////////////////////////////////////////
    // pslld/psrld xmm, imm8 (66 0F 72 /6|/2 ib): packed 32-bit lane shift by
    // an immediate count.
    if (op == MicroOp::VecShiftLeft32 || op == MicroOp::VecShiftRight32)
    {
        SWC_ASSERT(opBits == MicroOpBits::B128 && reg.isFloat());
        SWC_ASSERT(value <= 31);
        emitCpuOp(store_, 0x66);
        emitRex(store_, MicroOpBits::Zero, MicroReg{}, reg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x72);
        emitModRm(store_, op == MicroOp::VecShiftLeft32 ? MODRM_REG_6 : MODRM_REG_2, reg);
        emitValue(store_, value, MicroOpBits::B8);
        return;
    }

    ///////////////////////////////////////////

    if (op == MicroOp::FloatRound)
    {
        SWC_ASSERT(reg.isFloat());
        SWC_ASSERT(opBits == MicroOpBits::B32 || opBits == MicroOpBits::B64);
        SWC_ASSERT(value <= 0x03);
        emitCpuOp(store_, 0x66);
        emitRex(store_, opBits, reg, reg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x3A);
        emitCpuOp(store_, opBits == MicroOpBits::B64 ? 0x0B : 0x0A);
        emitModRm(store_, reg, reg);
        emitValue(store_, value, MicroOpBits::B8);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Xor)
    {
        if (opBits == MicroOpBits::B8)
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_6, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_6, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncodeOpImmediate(value, opBits))
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_6, reg);
            emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
        }
        else
        {
            SWC_INTERNAL_ERROR();
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Or)
    {
        if (opBits == MicroOpBits::B8)
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_1, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_1, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncodeOpImmediate(value, opBits))
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_1, reg);
            emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
        }
        else
        {
            SWC_INTERNAL_ERROR();
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::And)
    {
        if (opBits == MicroOpBits::B8)
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_4, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_4, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncodeOpImmediate(value, opBits))
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_4, reg);
            emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
        }
        else
        {
            SWC_INTERNAL_ERROR();
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Add)
    {
        if (opBits == MicroOpBits::B8)
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_0, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_0, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncodeOpImmediate(value, opBits))
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_0, reg);
            emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
        }
        else
        {
            SWC_INTERNAL_ERROR();
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Subtract)
    {
        if (opBits == MicroOpBits::B8)
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, MODRM_REG_5, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, MODRM_REG_5, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncodeOpImmediate(value, opBits))
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, MODRM_REG_5, reg);
            emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
        }
        else
        {
            SWC_INTERNAL_ERROR();
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::ModuloUnsigned ||
             op == MicroOp::ModuloSigned ||
             op == MicroOp::DivideUnsigned ||
             op == MicroOp::DivideSigned ||
             op == MicroOp::MultiplyUnsigned ||
             op == MicroOp::MultiplyHighSigned ||
             op == MicroOp::MultiplyHighUnsigned)
    {
        SWC_ASSERT(!(op == MicroOp::ModuloUnsigned || op == MicroOp::ModuloSigned || op == MicroOp::DivideUnsigned || op == MicroOp::DivideSigned || op == MicroOp::MultiplyUnsigned || op == MicroOp::MultiplyHighSigned || op == MicroOp::MultiplyHighUnsigned));
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::MultiplySigned)
    {
        if (canEncode8(value, opBits))
        {
            if (opBits == MicroOpBits::B8)
                encodeLoadSignedExtendRegReg(reg, reg, MicroOpBits::B32, opBits);
            emitRex(store_, opBits, reg, reg);
            emitCpuOp(store_, 0x6B);
            emitModRm(store_, reg, reg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncodeOpImmediate(value, opBits))
        {
            // The immediate is written as four bytes, so the multiply has to be
            // encoded at 32 bits: at 16 the operand-size prefix would have the
            // decoder read only two of them and take the rest for the next
            // instruction. Widening the operand first is what makes that sound -
            // the low half of the product is the same either way.
            MicroOpBits encodeBits = opBits;
            if (opBits == MicroOpBits::B8 || opBits == MicroOpBits::B16)
            {
                encodeLoadSignedExtendRegReg(reg, reg, MicroOpBits::B32, opBits);
                encodeBits = MicroOpBits::B32;
            }

            emitRex(store_, encodeBits, reg, reg);
            emitCpuOp(store_, 0x69);
            emitModRm(store_, reg, reg);
            emitValue(store_, value, MicroOpBits::B32);
        }
        else
        {
            SWC_INTERNAL_ERROR();
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::ShiftLeft)
    {
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

    else if (op == MicroOp::ShiftArithmeticLeft)
    {
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

    else if (op == MicroOp::RotateLeft)
    {
        SWC_ASSERT(value <= 0x7F);
        if (value == 1)
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitSpecCpuOp(store_, 0xD1, opBits);
            emitModRm(store_, MODRM_REG_0, reg);
        }
        else
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitSpecCpuOp(store_, 0xC1, opBits);
            emitModRm(store_, MODRM_REG_0, reg);
            emitValue(store_, std::min(static_cast<uint32_t>(value), getNumBits(opBits) - 1), MicroOpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::RotateRight)
    {
        SWC_ASSERT(value <= 0x7F);
        if (value == 1)
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitSpecCpuOp(store_, 0xD1, opBits);
            emitModRm(store_, MODRM_REG_1, reg);
        }
        else
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitSpecCpuOp(store_, 0xC1, opBits);
            emitModRm(store_, MODRM_REG_1, reg);
            emitValue(store_, std::min(static_cast<uint32_t>(value), getNumBits(opBits) - 1), MicroOpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::ShiftArithmeticRight)
    {
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
        SWC_INTERNAL_ERROR();
    }
}

void X64Encoder::encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, const ApInt& valueInt, MicroOp op, MicroOpBits opBits)
{
    const uint64_t value = immediateToU64(valueInt);
    SWC_ASSERT(!memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));
    SWC_ASSERT(!(op == MicroOp::ModuloSigned || op == MicroOp::ModuloUnsigned || op == MicroOp::DivideUnsigned || op == MicroOp::DivideSigned || op == MicroOp::MultiplySigned || op == MicroOp::MultiplyUnsigned));

    ///////////////////////////////////////////
    if (op == MicroOp::ShiftArithmeticRight)
    {
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

    else if (op == MicroOp::ShiftArithmeticLeft)
    {
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

    else if (op == MicroOp::ShiftRight)
    {
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

    else if (op == MicroOp::RotateLeft)
    {
        if (value == 1)
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitSpecCpuOp(store_, 0xD1, opBits);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
        }
        else
        {
            SWC_ASSERT(value <= 0x7F);
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitSpecCpuOp(store_, 0xC1, opBits);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
            emitValue(store_, std::min(static_cast<uint32_t>(value), getNumBits(opBits) - 1), MicroOpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::RotateRight)
    {
        if (value == 1)
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitSpecCpuOp(store_, 0xD1, opBits);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
        }
        else
        {
            SWC_ASSERT(value <= 0x7F);
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitSpecCpuOp(store_, 0xC1, opBits);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
            emitValue(store_, std::min(static_cast<uint32_t>(value), getNumBits(opBits) - 1), MicroOpBits::B8);
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::ShiftLeft)
    {
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
        if (opBits == MicroOpBits::B8)
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncodeOpImmediate(value, opBits))
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
            emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
        }
        else
        {
            SWC_INTERNAL_ERROR();
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Subtract)
    {
        if (opBits == MicroOpBits::B8)
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncodeOpImmediate(value, opBits))
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_5, memReg);
            emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
        }
        else
        {
            SWC_INTERNAL_ERROR();
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Or)
    {
        if (opBits == MicroOpBits::B8)
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncodeOpImmediate(value, opBits))
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
            emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
        }
        else
        {
            SWC_INTERNAL_ERROR();
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::And)
    {
        if (opBits == MicroOpBits::B8)
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncodeOpImmediate(value, opBits))
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_4, memReg);
            emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
        }
        else
        {
            SWC_INTERNAL_ERROR();
        }
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Xor)
    {
        if (opBits == MicroOpBits::B8)
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x80);
            emitModRm(store_, memOffset, MODRM_REG_6, memReg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncode8(value, opBits))
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x83);
            emitModRm(store_, memOffset, MODRM_REG_6, memReg);
            emitValue(store_, value, MicroOpBits::B8);
        }
        else if (canEncodeOpImmediate(value, opBits))
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitCpuOp(store_, 0x81);
            emitModRm(store_, memOffset, MODRM_REG_6, memReg);
            emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
        }
        else
        {
            SWC_INTERNAL_ERROR();
        }
    }

    ///////////////////////////////////////////

    else
    {
        SWC_INTERNAL_ERROR();
    }
}

void X64Encoder::encodeOpBinaryRegRegReg(MicroReg regDst, MicroReg regSrc1, MicroReg regSrc2, MicroOp op, MicroOpBits opBits)
{
    SWC_ASSERT(regDst.isFloat() && regSrc1.isFloat() && regSrc2.isFloat());

    // 128-bit packed: the VEX form of the same legacy encoding the two-operand
    // shape uses, with the untouched source named in vvvv instead of having to
    // be copied into the destination first.
    if (isVecMicroOp(op))
    {
        SWC_ASSERT(opBits == MicroOpBits::B128);
        const VecOpEncoding enc = vecOpEncoding(op);
        emitVex(store_, enc.prefix, enc.map, microRegToX64Reg(regDst), microRegToX64Reg(regSrc1), microRegToX64Reg(regSrc2));
        emitCpuOp(store_, enc.opcode);
        emitModRm(store_, regDst, regSrc2);
        return;
    }

    SWC_ASSERT(opBits == MicroOpBits::B32 || opBits == MicroOpBits::B64);

    // Same mandatory prefix the two-operand form would carry: F2/F3 select the
    // scalar arithmetic shapes, 66/none the bitwise ones.
    const bool    isBitwise       = op == MicroOp::FloatAnd || op == MicroOp::FloatXor;
    const uint8_t mandatoryPrefix = isBitwise ? (opBits == MicroOpBits::B64 ? 0x66 : 0x00)
                                              : (opBits == MicroOpBits::B64 ? 0xF2 : 0xF3);

    // No 0F byte: the VEX prefix already carries the escape.
    emitVex(store_, mandatoryPrefix, VEX_MAP_0F, microRegToX64Reg(regDst), microRegToX64Reg(regSrc1), microRegToX64Reg(regSrc2));
    emitCpuOp(store_, op);
    emitModRm(store_, regDst, regSrc2);
}

void X64Encoder::encodeOpBinaryRegRegImm(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits, uint64_t value)
{
    SWC_ASSERT(opBits == MicroOpBits::B128 && regDst.isFloat() && regSrc.isFloat());
    SWC_ASSERT(value <= 0xFF);

    // vroundps/vroundpd xmm1, xmm2, imm8 (VEX.128.66.0F3A 08|09 /r ib): plain
    // destination-in-reg shape, vvvv unused.
    if (op == MicroOp::VecRoundF32 || op == MicroOp::VecRoundF64)
    {
        const VecOpEncoding enc = vecOpEncoding(op);
        emitVex(store_, enc.prefix, enc.map, microRegToX64Reg(regDst), X64Reg::Rax, microRegToX64Reg(regSrc));
        emitCpuOp(store_, enc.opcode);
        emitModRm(store_, regDst, regSrc);
        emitValue(store_, value, MicroOpBits::B8);
        return;
    }

    // The shift-by-immediate group (VEX.NDD.128.66.0F 71|72|73 /n ib) puts its
    // opcode extension in the ModRM.reg field, so the destination travels in
    // vvvv and the source in r/m - the reverse of the three-operand
    // arithmetic form.
    uint8_t    opcode   = 0;
    uint8_t    modRmReg = 0;
    const bool isShift  = vecShiftImmEncoding(op, opcode, modRmReg);
    SWC_ASSERT(isShift);
    emitVex(store_, 0x66, VEX_MAP_0F, X64Reg::Rax, microRegToX64Reg(regDst), microRegToX64Reg(regSrc));
    emitCpuOp(store_, opcode);
    emitModRm(store_, modRmReg, regSrc);
    emitValue(store_, value, MicroOpBits::B8);
}

void X64Encoder::encodeVecUnaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits)
{
    SWC_ASSERT(opBits == MicroOpBits::B128 && regSrc.isFloat());
    // The movemask forms write lane sign bits into an integer register; every
    // other packed unary writes a float one. vvvv is unused in all of them.
    SWC_ASSERT(regDst.isFloat() || op == MicroOp::VecMoveMaskB || op == MicroOp::VecMoveMaskF32 || op == MicroOp::VecMoveMaskF64);

    const VecOpEncoding enc = vecOpEncoding(op);
    emitVex(store_, enc.prefix, enc.map, microRegToX64Reg(regDst), X64Reg::Rax, microRegToX64Reg(regSrc));
    emitCpuOp(store_, enc.opcode);
    emitModRm(store_, regDst, regSrc);
}

void X64Encoder::encodeOpTernaryRegRegRegImm(MicroReg regDst, MicroReg regSrc1, MicroReg regSrc2, MicroOp op, MicroOpBits opBits, uint64_t value)
{
    // Two sources and a trailing immediate: vcmpps/vcmppd carry a predicate
    // and answer all-ones/all-zeros lanes, vshufps a four-lane control, and
    // vpalignr a byte offset into the concatenation of both sources.
    SWC_ASSERT(op == MicroOp::VecCmpF32 || op == MicroOp::VecCmpF64 || op == MicroOp::VecShufF32 || op == MicroOp::VecAlignR);
    SWC_ASSERT(opBits == MicroOpBits::B128 && regDst.isFloat() && regSrc1.isFloat() && regSrc2.isFloat());
    SWC_ASSERT(value <= 0xFF);

    const VecOpEncoding enc = vecOpEncoding(op);
    emitVex(store_, enc.prefix, enc.map, microRegToX64Reg(regDst), microRegToX64Reg(regSrc1), microRegToX64Reg(regSrc2));
    emitCpuOp(store_, enc.opcode);
    emitModRm(store_, regDst, regSrc2);
    emitValue(store_, value, MicroOpBits::B8);
}

void X64Encoder::encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits)
{
    // vpblendvb xmm1, xmm2, xmm3, xmm4 (VEX.128.66.0F3A 4C /r /is4): the
    // destination doubles as the first source in vvvv, the second source
    // rides in r/m, and the mask register sits in the high nibble of the
    // trailing immediate.
    if (isVecMicroOp(op))
    {
        SWC_ASSERT(op == MicroOp::VecBlendVB);
        SWC_ASSERT(opBits == MicroOpBits::B128 && reg0.isFloat() && reg1.isFloat() && reg2.isFloat());
        const VecOpEncoding enc = vecOpEncoding(op);
        emitVex(store_, enc.prefix, enc.map, microRegToX64Reg(reg0), microRegToX64Reg(reg0), microRegToX64Reg(reg1));
        emitCpuOp(store_, enc.opcode);
        emitModRm(store_, reg0, reg1);
        emitValue(store_, static_cast<uint64_t>(x64RegNumber(microRegToX64Reg(reg2))) << 4, MicroOpBits::B8);
        return;
    }

    ///////////////////////////////////////////

    if (op == MicroOp::MultiplyAdd)
    {
        SWC_ASSERT(reg0.isFloat() && reg1.isFloat() && reg2.isFloat());
        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, MicroOpBits::Zero, reg0, reg1);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, MicroOp::FloatMultiply);
        emitModRm(store_, reg0, reg1);

        emitSpecF64(store_, 0xF3, opBits);
        emitRex(store_, MicroOpBits::Zero, reg0, reg2);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, MicroOp::FloatAdd);
        emitModRm(store_, reg0, reg2);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::CompareExchange)
    {
        SWC_ASSERT(microRegToX64Reg(reg0) == X64Reg::Rax);

        emitCpuOp(store_, 0xF0);
        emitRex(store_, opBits, reg2, reg1);
        emitCpuOp(store_, 0x0F);
        emitSpecCpuOp(store_, 0xB1, opBits);
        emitModRm(store_, 0, reg2, reg1);
    }

    ///////////////////////////////////////////

    else
    {
        SWC_INTERNAL_ERROR();
    }
}

void X64Encoder::encodeJump(MicroJump& jump, MicroCond cpuCond, MicroOpBits opBits)
{
    SWC_ASSERT(opBits == MicroOpBits::B8 || opBits == MicroOpBits::B32);

    if (opBits == MicroOpBits::B8)
    {
        switch (cpuCond)
        {
            case MicroCond::NotOverflow:
                emitCpuOp(store_, 0x71);
                break;
            case MicroCond::Below:
                emitCpuOp(store_, 0x72);
                break;
            case MicroCond::AboveOrEqual:
                emitCpuOp(store_, 0x73);
                break;
            case MicroCond::Zero:
                emitCpuOp(store_, 0x74);
                break;
            case MicroCond::Equal:
                emitCpuOp(store_, 0x74);
                break;
            case MicroCond::NotZero:
                emitCpuOp(store_, 0x75);
                break;
            case MicroCond::NotEqual:
                emitCpuOp(store_, 0x75);
                break;
            case MicroCond::BelowOrEqual:
                emitCpuOp(store_, 0x76);
                break;
            case MicroCond::Above:
                store_.pushU8(0x77);
                break;
            case MicroCond::Sign:
                emitCpuOp(store_, 0x78);
                break;
            case MicroCond::Parity:
                emitCpuOp(store_, 0x7A);
                break;
            case MicroCond::NotParity:
                emitCpuOp(store_, 0x7B);
                break;
            case MicroCond::Less:
                emitCpuOp(store_, 0x7C);
                break;
            case MicroCond::GreaterOrEqual:
                emitCpuOp(store_, 0x7D);
                break;
            case MicroCond::LessOrEqual:
                emitCpuOp(store_, 0x7E);
                break;
            case MicroCond::Greater:
                emitCpuOp(store_, 0x7F);
                break;
            case MicroCond::Unconditional:
                emitCpuOp(store_, 0xEB);
                break;
            default:
                SWC_UNREACHABLE();
        }

        store_.pushU8(0);

        jump.patchOffsetAddr = store_.seekPtr() - 1;
        jump.offsetStart     = store_.size();
        jump.opBits          = opBits;
        return;
    }

    switch (cpuCond)
    {
        case MicroCond::NotOverflow:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x81);
            break;
        case MicroCond::Below:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x82);
            break;
        case MicroCond::AboveOrEqual:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x83);
            break;
        case MicroCond::Zero:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x84);
            break;
        case MicroCond::Equal:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x84);
            break;
        case MicroCond::NotZero:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x85);
            break;
        case MicroCond::NotEqual:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x85);
            break;
        case MicroCond::BelowOrEqual:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x86);
            break;
        case MicroCond::Above:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x87);
            break;
        case MicroCond::Parity:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8A);
            break;
        case MicroCond::Sign:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x88);
            break;
        case MicroCond::NotParity:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8B);
            break;
        case MicroCond::Less:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8C);
            break;
        case MicroCond::GreaterOrEqual:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8D);
            break;
        case MicroCond::LessOrEqual:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8E);
            break;
        case MicroCond::Greater:
            emitCpuOp(store_, 0x0F);
            emitCpuOp(store_, 0x8F);
            break;
        case MicroCond::Unconditional:
            emitCpuOp(store_, 0xE9);
            break;
        default:
            SWC_UNREACHABLE();
    }

    store_.pushU32(0);

    jump.patchOffsetAddr = store_.seekPtr() - sizeof(uint32_t);
    jump.offsetStart     = store_.size();
    jump.opBits          = opBits;
}

void X64Encoder::encodePatchJump(const MicroJump& jump, uint64_t offsetDestination)
{
    const auto offset = static_cast<int32_t>(offsetDestination - jump.offsetStart);
    if (jump.opBits == MicroOpBits::B8)
    {
        SWC_ASSERT(offset >= -128 && offset <= 127);
        *static_cast<uint8_t*>(jump.patchOffsetAddr) = static_cast<int8_t>(offset);
    }
    else
    {
        *static_cast<uint32_t*>(jump.patchOffsetAddr) = static_cast<int32_t>(offset);
    }
}

void X64Encoder::encodePatchJump(const MicroJump& jump)
{
    return encodePatchJump(jump, store_.size());
}

void X64Encoder::encodeJumpReg(MicroReg reg)
{
    emitRex(store_, MicroOpBits::Zero, MicroReg{}, reg);
    emitCpuOp(store_, 0xFF);
    emitModRm(store_, ModRmMode::Register, MODRM_REG_4, encodeReg(reg));
}

// ============================================================================

void X64Encoder::encodeCallExtern(Symbol* targetSymbol, uint64_t targetAddress, CallConvKind callConv)
{
    // External address calls are lowered as mov target -> temp, then indirect call.
    SWC_UNUSED(targetSymbol);
    const CallConv& conv = CallConv::get(callConv);
    encodeLoadRegImm(conv.intReturn, ApInt(targetAddress, 64), MicroOpBits::B64);
    encodeCallReg(conv.intReturn, callConv);
}

void X64Encoder::encodeCallLocal(Symbol* targetSymbol, CallConvKind callConv)
{
    // Local calls use E8 + relocation patched later by the linker/JIT relocation pass.
    SWC_UNUSED(targetSymbol);
    SWC_UNUSED(callConv);

    emitCpuOp(store_, 0xE8);
    store_.pushU32(0);
}

void X64Encoder::encodeCallReg(MicroReg reg, CallConvKind callConv)
{
    // FF /2 encodes `call r/m64`.
    SWC_UNUSED(callConv);
    emitRex(store_, MicroOpBits::Zero, MicroReg{}, reg);
    emitCpuOp(store_, 0xFF);
    emitModRm(store_, MODRM_REG_2, reg);
}

void X64Encoder::encodeNop()
{
    emitCpuOp(store_, 0x90);
}

void X64Encoder::encodeBreakpoint()
{
    emitCpuOp(store_, 0xCC);
}

SWC_END_NAMESPACE();
