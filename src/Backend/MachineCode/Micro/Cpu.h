#pragma once

SWC_BEGIN_NAMESPACE();

namespace Cpu
{
    enum class OpBits : uint8_t
    {
        Zero = 0,
        B8   = 8,
        B16  = 16,
        B32  = 32,
        B64  = 64,
        B128 = 128,
    };

    enum class Reg : uint8_t
    {
        Rax,
        Rbx,
        Rcx,
        Rdx,
        Rsp,
        Rbp,
        Rsi,
        Rdi,
        R8,
        R9,
        R10,
        R11,
        R12,
        R13,
        R14,
        R15,
        Xmm0,
        Xmm1,
        Xmm2,
        Xmm3,
        Rip,
        Max,
    };

    enum class Op : uint8_t
    {
        ADD      = 0x01,
        OR       = 0x09,
        AND      = 0x21,
        SUB      = 0x29,
        CVTI2F   = 0x2A,
        CVTU2F64 = 0x2B,
        CVTF2I   = 0x2C,
        XOR      = 0x31,
        FSQRT    = 0x51,
        FAND     = 0x54,
        FXOR     = 0x57,
        FADD     = 0x58,
        FMUL     = 0x59,
        CVTF2F   = 0x5A,
        FSUB     = 0x5C,
        FMIN     = 0x5D,
        FDIV     = 0x5E,
        FMAX     = 0x5F,
        MOVSXD   = 0x63,
        XCHG     = 0x87,
        MOV      = 0x8B,
        LEA      = 0x8D,
        NEG      = 0x9F,
        BSWAP    = 0xB0,
        POPCNT   = 0xB8,
        BSF      = 0xBC,
        BSR      = 0xBD,
        MUL      = 0xC0,
        IMUL     = 0xC1,
        ROL      = 0xC7,
        ROR      = 0xC8,
        SHL      = 0xE0,
        SHR      = 0xE8,
        SAL      = 0xF0,
        DIV      = 0xF1,
        MOD      = 0xF3,
        NOT      = 0xF7,
        SAR      = 0xF8,
        IDIV     = 0xF9,
        CMPXCHG  = 0xFA,
        IMOD     = 0xFB,
        MULADD   = 0xFC,
    };

    enum class Cond : uint8_t
    {
        Above,
        Overflow,
        AboveOrEqual,
        Greater,
        Below,
        BelowOrEqual,
        Equal,
        GreaterOrEqual,
        Less,
        LessOrEqual,
        NotAbove,
        NotEqual,
        Parity,
        NotParity,
        EvenParity,
        NotEvenParity,
    };

    enum class CondJump : uint8_t
    {
        JumpNotOverflow,
        JumpNotZero,
        JumpZero,
        JumpLess,
        JumpLessOrEqual,
        JumpBelow,
        JumpBelowOrEqual,
        JumpGreaterOrEqual,
        JumpAboveOrEqual,
        JumpGreater,
        JumpAbove,
        JumpParity,
        JumpSign,
        JumpNotParity,
        JumpUnconditional,
    };

    enum class SymbolKind
    {
        Function,
        Extern,
        Custom,
        Constant,
    };

    class RegSet
    {
    public:
        void add(Cpu::Reg reg)
        {
            const auto idx = static_cast<size_t>(reg);
            if (idx < bits_.size())
                bits_.set(idx);
        }

        bool has(Cpu::Reg reg) const
        {
            const auto idx = static_cast<size_t>(reg);
            return idx < bits_.size() && bits_.test(idx);
        }

        void clear() { bits_.reset(); }

    private:
        std::bitset<64> bits_{};
    };

    struct Jump
    {
        void*       patchOffsetAddr = nullptr;
        uint64_t    offsetStart     = 0;
        Cpu::OpBits opBits          = Cpu::OpBits::Zero;
    };

    struct LabelToSolve
    {
        uint32_t  ipDest = 0;
        Cpu::Jump jump{};
    };

    struct Symbol
    {
        IdentifierRef   name;
        Cpu::SymbolKind kind  = Cpu::SymbolKind::Custom;
        uint32_t        value = 0;
        uint32_t        index = 0;
    };

    struct Function
    {
        uint32_t                       symbolIndex  = 0;
        uint32_t                       startAddress = 0;
        std::vector<Cpu::LabelToSolve> labelsToSolve;
    };

    inline bool isFloat(Reg reg)
    {
        return reg >= Reg::Xmm0 && reg <= Reg::Xmm3;
    }

    inline bool isInt(Reg reg)
    {
        return !isFloat(reg);
    }

    inline uint32_t getNumBits(OpBits opBits)
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
}

SWC_END_NAMESPACE();
