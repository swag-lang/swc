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
        Add,
        And,
        BitScanForward,
        BitScanReverse,
        BitwiseNot,
        ByteSwap,
        CompareExchange,
        ConvertFloatToFloat,
        ConvertFloatToInt,
        ConvertIntToFloat,
        ConvertUIntToFloat64,
        DivideSigned,
        DivideUnsigned,
        Exchange,
        FloatAdd,
        FloatAnd,
        FloatDivide,
        FloatMax,
        FloatMin,
        FloatMultiply,
        FloatSqrt,
        FloatSubtract,
        FloatXor,
        LoadEffectiveAddress,
        ModuloSigned,
        ModuloUnsigned,
        Move,
        MoveSignExtend,
        MultiplyAdd,
        MultiplySigned,
        MultiplyUnsigned,
        Negate,
        Or,
        PopCount,
        RotateLeft,
        RotateRight,
        ShiftArithmeticLeft,
        ShiftArithmeticRight,
        ShiftLeft,
        ShiftRight,
        Subtract,
        Xor,
    };

    enum class Cond : uint8_t
    {
        Above,
        AboveOrEqual,
        Below,
        BelowOrEqual,
        Equal,
        EvenParity,
        Greater,
        GreaterOrEqual,
        Less,
        LessOrEqual,
        NotAbove,
        NotEqual,
        NotEvenParity,
        NotParity,
        Overflow,
        Parity,
    };

    enum class CondJump : uint8_t
    {
        Above,
        AboveOrEqual,
        Below,
        BelowOrEqual,
        Greater,
        GreaterOrEqual,
        Less,
        LessOrEqual,
        NotOverflow,
        NotParity,
        NotZero,
        Parity,
        Sign,
        Unconditional,
        Zero,
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
