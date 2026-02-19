#include "pch.h"
#include "Backend/Encoder/X64Encoder.h"
#include "Backend/Micro/MicroInstr.h"
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

    bool isShiftImmediateOp(MicroOp op)
    {
        return op == MicroOp::ShiftLeft || op == MicroOp::ShiftRight || op == MicroOp::ShiftArithmeticRight;
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
        else if (canEncodeSigned8(memOffset))
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

            SWC_ASSERT(canEncodeSigned32(memOffset));
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

// ============================================================================

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

bool X64Encoder::queryConformanceIssue(MicroConformanceIssue& outIssue, const MicroInstr& inst, const MicroInstrOperand* ops) const
{
    outIssue = {};
    if (!ops)
        return false;

    ///////////////////////////////////////////
    if (inst.op == MicroInstrOpcode::LoadRegImm || inst.op == MicroInstrOpcode::LoadRegPtrImm)
    {
        if (ops[0].reg.isFloat())
        {
            outIssue.kind = MicroConformanceIssueKind::RewriteLoadFloatRegImm;
            return true;
        }

        if (ops[1].opBits != MicroOpBits::B8 &&
            ops[1].opBits != MicroOpBits::B16 &&
            ops[1].opBits != MicroOpBits::B32 &&
            ops[1].opBits != MicroOpBits::B64)
        {
            outIssue.kind             = MicroConformanceIssueKind::NormalizeOpBits;
            outIssue.operandIndex     = 1;
            outIssue.normalizedOpBits = MicroOpBits::B64;
            return true;
        }

        if (ops[1].opBits == MicroOpBits::B8 && ops[2].valueU64 > 0xFF)
        {
            outIssue.kind          = MicroConformanceIssueKind::ClampImmediate;
            outIssue.operandIndex  = 2;
            outIssue.valueLimitU64 = 0xFF;
            return true;
        }

        if (ops[1].opBits == MicroOpBits::B16 && ops[2].valueU64 > 0xFFFF)
        {
            outIssue.kind          = MicroConformanceIssueKind::ClampImmediate;
            outIssue.operandIndex  = 2;
            outIssue.valueLimitU64 = 0xFFFF;
            return true;
        }

        if (ops[1].opBits == MicroOpBits::B32 && ops[2].valueU64 > 0xFFFFFFFF)
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
        if (!isShiftImmediateOp(ops[2].microOp))
            return false;

        if (ops[3].valueU64 <= 0x7F)
            return false;

        outIssue.kind          = MicroConformanceIssueKind::ClampImmediate;
        outIssue.operandIndex  = 3;
        outIssue.valueLimitU64 = 0x7F;
        return true;
    }

    ///////////////////////////////////////////
    if (inst.op == MicroInstrOpcode::OpBinaryMemImm)
    {
        if (!isShiftImmediateOp(ops[2].microOp))
            return false;

        if (ops[4].valueU64 <= 0x7F)
            return false;

        outIssue.kind          = MicroConformanceIssueKind::ClampImmediate;
        outIssue.operandIndex  = 4;
        outIssue.valueLimitU64 = 0x7F;
        return true;
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

        if (ops[1].opBits == MicroOpBits::B64 && !canEncodeOpImmediate(ops[3].valueU64, ops[1].opBits))
        {
            outIssue.kind = MicroConformanceIssueKind::SplitLoadMemImm64;
            return true;
        }

        if (!canEncodeOpImmediate(ops[3].valueU64, ops[1].opBits))
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
        if (ops[4].opBits == MicroOpBits::B64 && !canEncodeOpImmediate(ops[7].valueU64, ops[4].opBits))
        {
            outIssue.kind = MicroConformanceIssueKind::SplitLoadAmcMemImm64;
            return true;
        }

        if (!canEncodeOpImmediate(ops[7].valueU64, ops[4].opBits))
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

    return false;
}

void X64Encoder::encodePush(MicroReg reg)
{
    emitRex(store_, MicroOpBits::Zero, MicroReg{}, reg);
    emitCpuOp(store_, 0x50, reg);
    return;
}

void X64Encoder::encodePop(MicroReg reg)
{
    emitRex(store_, MicroOpBits::Zero, MicroReg{}, reg);
    emitCpuOp(store_, 0x58, reg);
    return;
}

void X64Encoder::encodeRet()
{
    emitCpuOp(store_, 0xC3);
    return;
}

// ============================================================================

void X64Encoder::encodeLoadRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits opBits)
{
    if (regDst.isFloat() && regSrc.isFloat())
    {
        emitSpecF64(store_, 0xF3, opBits);
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
        emitRex(store_, opBits, regSrc, regDst);
        emitSpecCpuOp(store_, 0x89, opBits);
        emitModRm(store_, regSrc, regDst);
    }

    return;
}

void X64Encoder::encodeLoadRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits)
{
    SWC_INTERNAL_CHECK(!reg.isFloat());

    if (opBits == MicroOpBits::B8)
    {
        emitRex(store_, opBits, MicroReg{}, reg);
        emitCpuOp(store_, 0xB0, reg);
        emitValue(store_, value, opBits);
    }
    else
    {
        emitRex(store_, opBits, MicroReg{}, reg);
        emitCpuOp(store_, 0xB8, reg);
        emitValue(store_, value, opBits);
    }

    return;
}

void X64Encoder::encodeLoadRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits opBits)
{
    SWC_ASSERT(!memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));

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
        emitSpecCpuOp(store_, 0x8B, opBits);
        emitModRm(store_, memOffset, reg, memReg);
    }

    return;
}

void X64Encoder::encodeLoadZeroExtendRegMem(MicroReg reg, MicroReg memReg, uint64_t memOffset, MicroOpBits numBitsDst, MicroOpBits numBitsSrc)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);
    SWC_ASSERT(!memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));

    if (numBitsSrc == MicroOpBits::B8 && (numBitsDst == MicroOpBits::B32 || numBitsDst == MicroOpBits::B64))
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

    return;
}

void X64Encoder::encodeLoadZeroExtendRegReg(MicroReg regDst, MicroReg regSrc, MicroOpBits numBitsDst, MicroOpBits numBitsSrc)
{
    SWC_ASSERT(numBitsSrc != numBitsDst);
    SWC_ASSERT(!(regDst.isFloat() || regSrc.isFloat()));

    if (numBitsSrc == MicroOpBits::B8 && (numBitsDst == MicroOpBits::B32 || numBitsDst == MicroOpBits::B64))
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

    return;
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
        emitCpuOp(store_, 0x63);
        emitModRm(store_, memOffset, reg, memReg);
    }
    else
    {
        SWC_INTERNAL_ERROR();
    }

    return;
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
        emitCpuOp(store_, 0x63);
        emitModRm(store_, regDst, regSrc);
    }
    else
    {
        SWC_INTERNAL_ERROR();
    }

    return;
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
        emitCpuOp(store_, 0x8D);
        emitModRm(store_, ModRmMode::Memory, reg, MODRM_RM_RIP);
    }
    else if (memOffset == 0)
    {
        encodeLoadRegReg(reg, memReg, MicroOpBits::B64);
    }
    else
    {
        emitRex(store_, MicroOpBits::B64, reg, memReg);
        emitCpuOp(store_, 0x8D);
        emitModRm(store_, memOffset, reg, memReg);
    }

    return;
}

namespace
{
    void encodeAmcImm(PagedStore& store, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue)
    {
        SWC_UNUSED(opBitsBaseMul);
        SWC_INTERNAL_CHECK(canEncodeSigned32(addValue));

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
            emitModRm(store, canEncodeSigned8(addValue) ? ModRmMode::Displacement8 : ModRmMode::Displacement32, MODRM_REG_0, MODRM_RM_SIB);
        else if (addValue == 0 || baseIsNoBase)
            emitModRm(store, ModRmMode::Memory, MODRM_REG_0, MODRM_RM_SIB);
        else
            emitModRm(store, canEncodeSigned8(addValue) ? ModRmMode::Displacement8 : ModRmMode::Displacement32, MODRM_REG_0, MODRM_RM_SIB);

        // SIB
        SWC_ASSERT(mulValue == 1 || mulValue == 2 || mulValue == 4 || mulValue == 8);
        const uint8_t scale = static_cast<uint8_t>(log2(mulValue));
        if (baseIsNoBase)
        {
            emitSib(store, scale, encodeReg(mulX64) & 0b111, SIB_NO_BASE);
            emitValue(store, addValue, MicroOpBits::B32);
        }
        else
        {
            emitSib(store, scale, encodeReg(mulX64) & 0b111, encodeReg(baseX64) & 0b111);
            if (baseX64 == X64Reg::R13 || addValue != 0)
                emitValue(store, addValue, canEncodeSigned8(addValue) ? MicroOpBits::B8 : MicroOpBits::B32);
        }

        // Value
        emitValue(store, value, std::min(opBitsValue, MicroOpBits::B32));
        return;
    }

    void encodeAmcReg(PagedStore& store, MicroReg reg, MicroOpBits opBitsReg, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroOp op, bool mr)
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
            emitModRm(store, canEncodeSigned8(addValue) ? ModRmMode::Displacement8 : ModRmMode::Displacement32, reg, MODRM_RM_SIB);
        else if (addValue == 0 || baseIsNoBase)
            emitModRm(store, ModRmMode::Memory, reg, MODRM_RM_SIB);
        else
            emitModRm(store, canEncodeSigned8(addValue) ? ModRmMode::Displacement8 : ModRmMode::Displacement32, reg, MODRM_RM_SIB);

        // SIB
        SWC_ASSERT(mulValue == 1 || mulValue == 2 || mulValue == 4 || mulValue == 8);
        const uint8_t scale = static_cast<uint8_t>(log2(mulValue));
        if (baseIsNoBase)
        {
            emitSib(store, scale, encodeReg(mulX64) & 0b111, SIB_NO_BASE);
            emitValue(store, addValue, MicroOpBits::B32);
        }
        else
        {
            emitSib(store, scale, encodeReg(mulX64) & 0b111, encodeReg(baseX64) & 0b111);
            if (baseX64 == X64Reg::R13 || addValue != 0)
                emitValue(store, addValue, canEncodeSigned8(addValue) ? MicroOpBits::B8 : MicroOpBits::B32);
        }

        return;
    }
}

void X64Encoder::encodeLoadAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsSrc)
{
    return encodeAmcReg(store_, regDst, opBitsDst, regBase, regMul, mulValue, addValue, opBitsSrc, MicroOp::Move, false);
}

void X64Encoder::encodeLoadAmcMemReg(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, MicroReg regSrc, MicroOpBits opBitsSrc)
{
    return encodeAmcReg(store_, regSrc, opBitsSrc, regBase, regMul, mulValue, addValue, opBitsBaseMul, MicroOp::Move, true);
}

void X64Encoder::encodeLoadAmcMemImm(MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsBaseMul, uint64_t value, MicroOpBits opBitsValue)
{
    return encodeAmcImm(store_, regBase, regMul, mulValue, addValue, opBitsBaseMul, value, opBitsValue);
}

void X64Encoder::encodeLoadAddressAmcRegMem(MicroReg regDst, MicroOpBits opBitsDst, MicroReg regBase, MicroReg regMul, uint64_t mulValue, uint64_t addValue, MicroOpBits opBitsValue)
{
    return encodeAmcReg(store_, regDst, opBitsDst, regBase, regMul, mulValue, addValue, opBitsValue, MicroOp::LoadEffectiveAddress, false);
}

// ============================================================================

void X64Encoder::encodeLoadMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits)
{
    SWC_ASSERT(!memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));

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
        emitSpecCpuOp(store_, 0x89, opBits);
        emitModRm(store_, memOffset, reg, memReg);
    }

    return;
}

void X64Encoder::encodeLoadMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits)
{
    SWC_ASSERT(!memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));
    SWC_INTERNAL_CHECK(opBits != MicroOpBits::B128);

    if (!canEncodeOpImmediate(value, opBits))
    {
        if (opBits == MicroOpBits::B64)
        {
            const uint32_t lowU32  = static_cast<uint32_t>(value & 0xFFFFFFFFu);
            const uint32_t highU32 = static_cast<uint32_t>((value >> 32) & 0xFFFFFFFFu);
            encodeLoadMemImm(memReg, memOffset, lowU32, MicroOpBits::B32);
            encodeLoadMemImm(memReg, memOffset + 4, highU32, MicroOpBits::B32);
            return;
        }

        if (opBits == MicroOpBits::B8)
            value &= 0xFF;
        else if (opBits == MicroOpBits::B16)
            value &= 0xFFFF;
        else if (opBits == MicroOpBits::B32)
            value &= 0xFFFFFFFF;
    }

    emitRex(store_, opBits, MicroReg{}, memReg);
    emitSpecB8(store_, 0xC7, opBits);
    emitModRm(store_, memOffset, MODRM_REG_0, memReg);
    emitValue(store_, value, std::min(opBits, MicroOpBits::B32));

    return;
}

// ============================================================================

void X64Encoder::encodeClearReg(MicroReg reg, MicroOpBits opBits)
{
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

    return;
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
            SWC_ASSERT(false);
            break;
    }

    emitModRm(store_, MODRM_REG_0, reg);
    return;
}

void X64Encoder::encodeLoadCondRegReg(MicroReg regDst, MicroReg regSrc, MicroCond setType, MicroOpBits opBits)
{
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
    return;
}

// ============================================================================

void X64Encoder::encodeCmpRegReg(MicroReg reg0, MicroReg reg1, MicroOpBits opBits)
{
    if (reg0.isFloat())
    {
        SWC_ASSERT(!reg1.isInt());

        emitPrefixF64(store_, opBits);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0x2F);
        emitModRm(store_, reg0, reg1);
    }
    else
    {
        emitRex(store_, opBits, reg1, reg0);
        emitSpecCpuOp(store_, 0x39, opBits);
        emitModRm(store_, reg1, reg0);
    }

    return;
}

void X64Encoder::encodeCmpRegImm(MicroReg reg, uint64_t value, MicroOpBits opBits)
{
    SWC_ASSERT(!reg.isFloat());

    if (opBits == MicroOpBits::B8)
    {
        emitRex(store_, opBits, MicroReg{}, reg);
        emitCpuOp(store_, 0x80);
        emitModRm(store_, MODRM_REG_7, reg);
        emitValue(store_, value, MicroOpBits::B8);
    }
    else if (canEncode8(value, opBits))
    {
        emitRex(store_, opBits, MicroReg{}, reg);
        emitCpuOp(store_, 0x83);
        emitModRm(store_, MODRM_REG_7, reg);
        emitValue(store_, value, MicroOpBits::B8);
    }
    else if (canEncodeOpImmediate(value, opBits))
    {
        emitRex(store_, opBits, MicroReg{}, reg);
        emitCpuOp(store_, 0x81);
        emitModRm(store_, MODRM_REG_7, reg);
        emitValue(store_, value, std::min(opBits, MicroOpBits::B32));
    }
    else
    {
        SWC_INTERNAL_ERROR();
    }

    return;
}

void X64Encoder::encodeCmpMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOpBits opBits)
{
    SWC_ASSERT(!memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));
    SWC_ASSERT(!reg.isFloat());

    emitRex(store_, opBits, reg, memReg);
    emitSpecCpuOp(store_, 0x39, opBits);
    emitModRm(store_, memOffset, reg, memReg);

    return;
}

void X64Encoder::encodeCmpMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOpBits opBits)
{
    SWC_ASSERT(!memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));

    if (opBits == MicroOpBits::B8)
    {
        emitRex(store_, opBits, MicroReg{}, memReg);
        emitCpuOp(store_, 0x80);
        emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        emitValue(store_, value, MicroOpBits::B8);
    }
    else if (canEncode8(value, opBits))
    {
        emitRex(store_, opBits, MicroReg{}, memReg);
        emitCpuOp(store_, 0x83);
        emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        emitValue(store_, value, MicroOpBits::B8);
    }
    else if (canEncodeOpImmediate(value, opBits))
    {
        emitRex(store_, opBits, MicroReg{}, memReg);
        emitCpuOp(store_, 0x81);
        emitModRm(store_, memOffset, MODRM_REG_7, memReg);
        emitValue(store_, value, opBits == MicroOpBits::B16 ? opBits : MicroOpBits::B32);
    }
    else
    {
        SWC_INTERNAL_ERROR();
    }

    return;
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
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, memOffset, MODRM_REG_2, memReg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Negate)
    {
        emitRex(store_, opBits);
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, memOffset, MODRM_REG_3, memReg);
    }

    ///////////////////////////////////////////

    else
    {
        SWC_INTERNAL_ERROR();
    }

    return;
}

void X64Encoder::encodeOpUnaryReg(MicroReg reg, MicroOp op, MicroOpBits opBits)
{
    ///////////////////////////////////////////

    if (op == MicroOp::BitwiseNot)
    {
        emitRex(store_, opBits, MicroReg{}, reg);
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, MODRM_REG_2, reg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Negate)
    {
        SWC_ASSERT(!reg.isFloat());

        emitRex(store_, opBits, MicroReg{}, reg);
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, MODRM_REG_3, reg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::ByteSwap)
    {
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
        SWC_INTERNAL_ERROR();
    }

    return;
}

void X64Encoder::encodeOpBinaryRegMem(MicroReg regDst, MicroReg memReg, uint64_t memOffset, MicroOp op, MicroOpBits opBits)
{
    SWC_ASSERT(!memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));

    ///////////////////////////////////////////
    if (op == MicroOp::Add)
    {
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x03, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Subtract)
    {
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x2B, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::And)
    {
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x23, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Or)
    {
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x0B, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::Xor)
    {
        emitRex(store_, opBits, regDst, memReg);
        emitSpecCpuOp(store_, 0x33, opBits);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::MultiplySigned)
    {
        if (opBits == MicroOpBits::B8)
            encodeLoadSignedExtendRegReg(regDst, regDst, MicroOpBits::B32, opBits);
        emitRex(store_, opBits, regDst, memReg);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xAF);
        emitModRm(store_, memOffset, regDst, memReg);
    }

    ///////////////////////////////////////////

    else
    {
        SWC_INTERNAL_ERROR();
    }

    return;
}

void X64Encoder::encodeOpBinaryRegReg(MicroReg regDst, MicroReg regSrc, MicroOp op, MicroOpBits opBits)
{
    ///////////////////////////////////////////

    SWC_ASSERT(op != MicroOp::ConvertUIntToFloat64);

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
        emitSpecCpuOp(store_, 0xF7, opBits);
        if (op == MicroOp::DivideUnsigned || op == MicroOp::ModuloUnsigned)
            emitModRm(store_, MODRM_REG_6, regSrc);
        else if (op == MicroOp::DivideSigned || op == MicroOp::ModuloSigned)
            emitModRm(store_, MODRM_REG_7, regSrc);

        if ((op == MicroOp::ModuloUnsigned || op == MicroOp::ModuloSigned) && opBits == MicroOpBits::B8)
            encodeOpBinaryRegImm(rax, 8, MicroOp::ShiftRight, MicroOpBits::B32); // AH => AL
        else if (op == MicroOp::ModuloUnsigned || op == MicroOp::ModuloSigned)
            encodeLoadRegReg(rax, x64RegToMicroReg(X64Reg::Rdx), opBits);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::MultiplyUnsigned)
    {
        const auto rax = x64RegToMicroReg(X64Reg::Rax);
        emitRex(store_, opBits, rax, regSrc);
        emitSpecCpuOp(store_, 0xF7, opBits);
        emitModRm(store_, MODRM_REG_4, regSrc);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::MultiplySigned)
    {
        if (opBits == MicroOpBits::B8)
        {
            encodeLoadSignedExtendRegReg(regDst, regDst, MicroOpBits::B32, opBits);
            encodeLoadSignedExtendRegReg(regSrc, regSrc, MicroOpBits::B32, opBits);
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
        emitSpecCpuOp(store_, 0x87, opBits);
        emitModRm(store_, regSrc, regDst);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::BitScanForward || op == MicroOp::BitScanReverse)
    {
        emitRex(store_, opBits, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, op == MicroOp::BitScanForward ? 0xBC : 0xBD);
        emitModRm(store_, regDst, regSrc);
    }

    ///////////////////////////////////////////

    else if (op == MicroOp::PopCount)
    {
        emitCpuOp(store_, 0xF3);
        emitRex(store_, opBits, regDst, regSrc);
        emitCpuOp(store_, 0x0F);
        emitCpuOp(store_, 0xB8);
        emitModRm(store_, regDst, regSrc);
    }

    ///////////////////////////////////////////

    else
    {
        SWC_INTERNAL_ERROR();
    }

    return;
}

void X64Encoder::encodeOpBinaryMemReg(MicroReg memReg, uint64_t memOffset, MicroReg reg, MicroOp op, MicroOpBits opBits)
{
    SWC_ASSERT(!memReg.isFloat());
    SWC_INTERNAL_CHECK(canEncodeSigned32(memOffset));
    SWC_ASSERT(!reg.isFloat());
    SWC_ASSERT(!(op == MicroOp::DivideUnsigned || op == MicroOp::DivideSigned || op == MicroOp::ModuloUnsigned || op == MicroOp::ModuloSigned || op == MicroOp::MultiplySigned || op == MicroOp::MultiplyUnsigned));

    ///////////////////////////////////////////

    if (op == MicroOp::ShiftArithmeticRight ||
        op == MicroOp::ShiftRight ||
        op == MicroOp::ShiftLeft)
    {
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
        emitRex(store_, opBits, reg, memReg);
        emitSpecCpuOp(store_, op, opBits);
        emitModRm(store_, memOffset, reg, memReg);
    }

    return;
}

void X64Encoder::encodeOpBinaryRegImm(MicroReg reg, uint64_t value, MicroOp op, MicroOpBits opBits)
{
    ///////////////////////////////////////////

    if (op == MicroOp::Xor)
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
        if (value == 1 && backendBuildCfg().optimizeLevel >= Runtime::BuildCfgBackendOptim::O1)
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitSpecCpuOp(store_, 0xFF, opBits);
            emitModRm(store_, MODRM_REG_0, reg);
        }
        else if (opBits == MicroOpBits::B8)
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
        if (value == 1 && backendBuildCfg().optimizeLevel >= Runtime::BuildCfgBackendOptim::O1)
        {
            emitRex(store_, opBits, MicroReg{}, reg);
            emitSpecCpuOp(store_, 0xFF, opBits);
            emitModRm(store_, MODRM_REG_1, reg);
        }
        else if (opBits == MicroOpBits::B8)
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
             op == MicroOp::MultiplyUnsigned)
    {
        SWC_ASSERT(!(op == MicroOp::ModuloUnsigned || op == MicroOp::ModuloSigned || op == MicroOp::DivideUnsigned || op == MicroOp::DivideSigned || op == MicroOp::MultiplyUnsigned));
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
            if (opBits == MicroOpBits::B8 || opBits == MicroOpBits::B16)
                encodeLoadSignedExtendRegReg(reg, reg, MicroOpBits::B32, opBits);
            emitRex(store_, opBits, reg, reg);
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

    return;
}

void X64Encoder::encodeOpBinaryMemImm(MicroReg memReg, uint64_t memOffset, uint64_t value, MicroOp op, MicroOpBits opBits)
{
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
        if (value == 1 && backendBuildCfg().optimizeLevel >= Runtime::BuildCfgBackendOptim::O1)
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitSpecCpuOp(store_, 0xFF, opBits);
            emitModRm(store_, memOffset, MODRM_REG_0, memReg);
        }
        else if (opBits == MicroOpBits::B8)
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
        if (value == 1 && backendBuildCfg().optimizeLevel >= Runtime::BuildCfgBackendOptim::O1)
        {
            emitRex(store_, opBits, MicroReg{}, memReg);
            emitSpecCpuOp(store_, 0xFF, opBits);
            emitModRm(store_, memOffset, MODRM_REG_1, memReg);
        }
        else if (opBits == MicroOpBits::B8)
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

    return;
}

void X64Encoder::encodeOpTernaryRegRegReg(MicroReg reg0, MicroReg reg1, MicroReg reg2, MicroOp op, MicroOpBits opBits)
{
    ///////////////////////////////////////////

    if (op == MicroOp::MultiplyAdd)
    {
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
        SWC_ASSERT(microRegToX64Reg(reg0) == X64Reg::Rax);

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

    return;
}

void X64Encoder::encodeJumpTable(MicroReg tableReg, MicroReg offsetReg, int32_t currentIp, uint32_t offsetTable, uint32_t numEntries)
{
    auto& compiler                                 = ctx().compiler();
    const auto [offsetTableConstant, addrConstant] = compiler.constantSegment().reserveSpan<uint32_t>(numEntries);
    auto emitRelocAddressLoad                      = [&](MicroReg reg, uint32_t symbolIndex, uint32_t offset) {
        emitRex(store_, MicroOpBits::B64, reg);
        emitCpuOp(store_, 0x8D);
        emitModRm(store_, ModRmMode::Memory, reg, MODRM_RM_RIP);
        addSymbolRelocation(store_.size() - textSectionOffset_, symbolIndex, IMAGE_REL_AMD64_REL32);
        store_.pushU32(offset);
    };
    emitRelocAddressLoad(tableReg, symCsIndex_, offsetTableConstant);

    // 'movsxd' table, dword ptr [table + offset*4]
    encodeAmcReg(store_, tableReg, MicroOpBits::B64, tableReg, offsetReg, 4, 0, MicroOpBits::B64, MicroOp::MoveSignExtend, false);

    const auto startIdx = store_.size();
    emitRelocAddressLoad(offsetReg, cpuFct_->symbolIndex, store_.size() - cpuFct_->startAddress);
    uint8_t* patchPtr = store_.seekPtr() - sizeof(uint32_t);
    encodeOpBinaryRegReg(offsetReg, tableReg, MicroOp::Add, MicroOpBits::B64);
    encodeJumpReg(offsetReg);
    const auto endIdx     = store_.size();
    uint32_t   patchValue = 0;
    std::memcpy(&patchValue, patchPtr, sizeof(patchValue));
    patchValue += endIdx - startIdx;
    std::memcpy(patchPtr, &patchValue, sizeof(patchValue));

    const auto    tableCompiler = compiler.compilerSegment().ptr<int32_t>(offsetTable);
    const int32_t currentOffset = static_cast<int32_t>(store_.size());

    EncoderJumpLabel label;
    for (uint32_t idx = 0; idx < numEntries; idx++)
    {
        label.ipDest               = tableCompiler[idx] + currentIp + 1;
        label.jump.opBits          = MicroOpBits::B32;
        label.jump.offsetStart     = currentOffset;
        label.jump.patchOffsetAddr = addrConstant + idx;
        cpuFct_->labelsToSolve.push_back(label);
    }

    return;
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
                SWC_ASSERT(false);
                break;
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
            SWC_ASSERT(false);
            break;
    }

    store_.pushU32(0);

    jump.patchOffsetAddr = store_.seekPtr() - sizeof(uint32_t);
    jump.offsetStart     = store_.size();
    jump.opBits          = opBits;
    return;
}

void X64Encoder::encodePatchJump(const MicroJump& jump, uint64_t offsetDestination)
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

    return;
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
    return;
}

// ============================================================================

void X64Encoder::encodeCallExtern(Symbol* targetSymbol, uint64_t targetAddress, CallConvKind callConv)
{
    // External address calls are lowered as mov target -> temp, then indirect call.
    SWC_UNUSED(targetSymbol);
    const CallConv& conv = CallConv::get(callConv);
    encodeLoadRegImm(conv.intReturn, targetAddress, MicroOpBits::B64);
    encodeCallReg(conv.intReturn, callConv);
    return;
}

void X64Encoder::encodeCallLocal(Symbol* targetSymbol, CallConvKind callConv)
{
    // Local calls use E8 + relocation patched later by the linker/JIT relocation pass.
    SWC_UNUSED(targetSymbol);
    SWC_UNUSED(callConv);

    emitCpuOp(store_, 0xE8);
    store_.pushU32(0);
    return;
}

void X64Encoder::encodeCallReg(MicroReg reg, CallConvKind callConv)
{
    // FF /2 encodes `call r/m64`.
    SWC_UNUSED(callConv);
    emitRex(store_, MicroOpBits::Zero, MicroReg{}, reg);
    emitCpuOp(store_, 0xFF);
    emitModRm(store_, MODRM_REG_2, reg);
    return;
}

void X64Encoder::encodeNop()
{
    emitCpuOp(store_, 0x90);
    return;
}

SWC_END_NAMESPACE();
