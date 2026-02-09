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

inline uint32_t getEncoderNumBits(MicroOpBits opBits)
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

struct MicroJump
{
    void*       patchOffsetAddr = nullptr;
    uint64_t    offsetStart     = 0;
    MicroOpBits opBits          = MicroOpBits::Zero;
};

SWC_END_NAMESPACE();
