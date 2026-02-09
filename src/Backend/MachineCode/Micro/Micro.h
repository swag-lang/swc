#pragma once
#include "Backend/MachineCode/Micro/MicroReg.h"

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
