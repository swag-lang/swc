#pragma once

SWC_BEGIN_NAMESPACE();

namespace Micro
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

    enum class RegKind : uint8_t
    {
        Invalid,
        Int,
        Float,
        Special,
    };

    enum class RegSpecial : uint8_t
    {
        InstructionPointer,
        NoBase,
    };

    struct Reg
    {
        uint16_t packed = 0;

        constexpr Reg() = default;
        constexpr Reg(RegKind kind, uint8_t index) :
            packed(static_cast<uint16_t>(static_cast<uint16_t>(kind) << 8 | index))
        {
        }

        constexpr RegKind kind() const { return static_cast<RegKind>((packed >> 8) & 0xFF); }
        constexpr uint8_t index() const { return static_cast<uint8_t>(packed & 0xFF); }

        constexpr bool isValid() const { return kind() != RegKind::Invalid; }
        constexpr bool isInt() const { return kind() == RegKind::Int; }
        constexpr bool isFloat() const { return kind() == RegKind::Float; }
        constexpr bool isSpecial() const { return kind() == RegKind::Special; }

        constexpr bool isInstructionPointer() const { return isSpecial() && index() == static_cast<uint8_t>(RegSpecial::InstructionPointer); }
        constexpr bool isNoBase() const { return isSpecial() && index() == static_cast<uint8_t>(RegSpecial::NoBase); }

        static constexpr Reg invalid() { return Reg(RegKind::Invalid, 0); }
        static constexpr Reg intReg(uint8_t index) { return Reg(RegKind::Int, index); }
        static constexpr Reg floatReg(uint8_t index) { return Reg(RegKind::Float, index); }
        static constexpr Reg instructionPointer() { return Reg(RegKind::Special, static_cast<uint8_t>(RegSpecial::InstructionPointer)); }
        static constexpr Reg noBase() { return Reg(RegKind::Special, static_cast<uint8_t>(RegSpecial::NoBase)); }

        constexpr bool operator==(const Reg& other) const { return packed == other.packed; }
        constexpr bool operator!=(const Reg& other) const { return packed != other.packed; }
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
        void add(Reg reg)
        {
            if (!reg.isValid())
                return;
            const auto idx = regSetIndex(reg);
            if (idx < bits_.size())
                bits_.set(idx);
        }

        bool has(Reg reg) const
        {
            if (!reg.isValid())
                return false;
            const auto idx = regSetIndex(reg);
            return idx < bits_.size() && bits_.test(idx);
        }

        void clear() { bits_.reset(); }

    private:
        static constexpr size_t K_REG_CLASS_STRIDE = 32;
        static constexpr size_t regSetIndex(Reg reg)
        {
            return static_cast<size_t>(static_cast<uint8_t>(reg.kind())) * K_REG_CLASS_STRIDE + reg.index();
        }

        std::bitset<128> bits_{};
    };

    struct Jump
    {
        void*    patchOffsetAddr = nullptr;
        uint64_t offsetStart     = 0;
        OpBits   opBits          = OpBits::Zero;
    };

    struct LabelToSolve
    {
        uint32_t ipDest = 0;
        Jump     jump{};
    };

    struct Symbol
    {
        IdentifierRef name;
        SymbolKind    kind  = SymbolKind::Custom;
        uint32_t      value = 0;
        uint32_t      index = 0;
    };

    struct Function
    {
        uint32_t                  symbolIndex  = 0;
        uint32_t                  startAddress = 0;
        std::vector<LabelToSolve> labelsToSolve;
    };

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
