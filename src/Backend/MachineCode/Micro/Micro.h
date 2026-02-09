#pragma once

SWC_BEGIN_NAMESPACE();

enum class MicroOpBits : uint8_t
{
    Zero = 0,
    B8   = 8,
    B16  = 16,
    B32  = 32,
    B64  = 64,
    B128 = 128,
};

enum class MicroRegKind : uint8_t
{
    Invalid,
    Int,
    Float,
    Special,
};

enum class MicroRegSpecial : uint8_t
{
    InstructionPointer,
    NoBase,
};

struct MicroReg
{
    uint16_t packed = 0;

    constexpr MicroReg() = default;
    constexpr MicroReg(MicroRegKind kind, uint8_t index) :
        packed(static_cast<uint16_t>(static_cast<uint16_t>(kind) << 8 | index))
    {
    }

    constexpr MicroRegKind kind() const { return static_cast<MicroRegKind>((packed >> 8) & 0xFF); }
    constexpr uint8_t      index() const { return static_cast<uint8_t>(packed & 0xFF); }

    constexpr bool isValid() const { return kind() != MicroRegKind::Invalid; }
    constexpr bool isInt() const { return kind() == MicroRegKind::Int; }
    constexpr bool isFloat() const { return kind() == MicroRegKind::Float; }
    constexpr bool isSpecial() const { return kind() == MicroRegKind::Special; }

    constexpr bool isInstructionPointer() const { return isSpecial() && index() == static_cast<uint8_t>(MicroRegSpecial::InstructionPointer); }
    constexpr bool isNoBase() const { return isSpecial() && index() == static_cast<uint8_t>(MicroRegSpecial::NoBase); }

    static constexpr MicroReg invalid() { return MicroReg(MicroRegKind::Invalid, 0); }
    static constexpr MicroReg intReg(uint8_t index) { return MicroReg(MicroRegKind::Int, index); }
    static constexpr MicroReg floatReg(uint8_t index) { return MicroReg(MicroRegKind::Float, index); }
    static constexpr MicroReg instructionPointer() { return MicroReg(MicroRegKind::Special, static_cast<uint8_t>(MicroRegSpecial::InstructionPointer)); }
    static constexpr MicroReg noBase() { return MicroReg(MicroRegKind::Special, static_cast<uint8_t>(MicroRegSpecial::NoBase)); }

    constexpr bool operator==(const MicroReg& other) const { return packed == other.packed; }
    constexpr bool operator!=(const MicroReg& other) const { return packed != other.packed; }
};

enum class MicroOp : uint8_t
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

enum class MicroCond : uint8_t
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

enum class MicroCondJump : uint8_t
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

enum class MicroSymbolKind
{
    Function,
    Extern,
    Custom,
    Constant,
};

class MicroRegSet
{
public:
    void add(MicroReg reg)
    {
        if (!reg.isValid())
            return;
        const auto idx = regSetIndex(reg);
        if (idx < bits_.size())
            bits_.set(idx);
    }

    bool has(MicroReg reg) const
    {
        if (!reg.isValid())
            return false;
        const auto idx = regSetIndex(reg);
        return idx < bits_.size() && bits_.test(idx);
    }

    void clear() { bits_.reset(); }

private:
    static constexpr size_t K_REG_CLASS_STRIDE = 32;
    static constexpr size_t regSetIndex(MicroReg reg)
    {
        return static_cast<size_t>(static_cast<uint8_t>(reg.kind())) * K_REG_CLASS_STRIDE + reg.index();
    }

    std::bitset<128> bits_{};
};

struct MicroJump
{
    void*       patchOffsetAddr = nullptr;
    uint64_t    offsetStart     = 0;
    MicroOpBits opBits          = MicroOpBits::Zero;
};

struct MicroLabelToSolve
{
    uint32_t  ipDest = 0;
    MicroJump jump{};
};

struct MicroSymbol
{
    IdentifierRef   name;
    MicroSymbolKind kind  = MicroSymbolKind::Custom;
    uint32_t        value = 0;
    uint32_t        index = 0;
};

struct MicroFunction
{
    uint32_t                       symbolIndex  = 0;
    uint32_t                       startAddress = 0;
    std::vector<MicroLabelToSolve> labelsToSolve;
};

inline uint32_t getNumBits(MicroOpBits opBits)
{
    switch (opBits)
    {
        case MicroOpBits::B8: return 8;
        case MicroOpBits::B16: return 16;
        case MicroOpBits::B32: return 32;
        case MicroOpBits::B64: return 64;
        default: return 0;
    }
}

SWC_END_NAMESPACE();
