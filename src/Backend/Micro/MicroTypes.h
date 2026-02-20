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

inline MicroOpBits microOpBitsFromChunkSize(uint32_t chunkSize)
{
    switch (chunkSize)
    {
        case 1:
            return MicroOpBits::B8;
        case 2:
            return MicroOpBits::B16;
        case 4:
            return MicroOpBits::B32;
        case 8:
            return MicroOpBits::B64;
        default:
            SWC_UNREACHABLE();
    }
}

inline MicroOpBits microOpBitsFromBitWidth(uint32_t bitWidth)
{
    switch (bitWidth)
    {
        case 8:
        case 16:
        case 32:
        case 64:
            return microOpBitsFromChunkSize(bitWidth / 8);
        default:
            return MicroOpBits::Zero;
    }
}

inline uint64_t getOpBitsMask(MicroOpBits opBits)
{
    switch (opBits)
    {
        case MicroOpBits::B8:
            return 0xFF;
        case MicroOpBits::B16:
            return 0xFFFF;
        case MicroOpBits::B32:
            return 0xFFFFFFFF;
        case MicroOpBits::B64:
            return 0xFFFFFFFFFFFFFFFF;
        default:
            return 0;
    }
}

inline uint32_t getNumBits(MicroOpBits opBits)
{
    return static_cast<uint32_t>(opBits);
}

enum class MicroOp : uint8_t
{
    Add,
    And,
    BitScanForward,
    BitScanReverse,
    BitwiseNot,
    ByteSwap,
    Compare,
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
    Test,
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
    NotOverflow,
    NotParity,
    Overflow,
    Parity,
    Sign,
    Unconditional,
    Zero,
    NotZero,
};

struct MicroJump
{
    void*       patchOffsetAddr = nullptr;
    uint64_t    offsetStart     = 0;
    MicroOpBits opBits          = MicroOpBits::Zero;
    bool        valid           = false;
};

SWC_END_NAMESPACE();
