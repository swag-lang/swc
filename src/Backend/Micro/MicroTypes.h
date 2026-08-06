#pragma once
#include "Support/Report/Assert.h"

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

inline uint64_t getBitsMask(MicroOpBits opBits)
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

inline uint32_t getNumBytes(MicroOpBits opBits)
{
    return getNumBits(opBits) / 8;
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
    FloatRound,
    FloatSqrt,
    FloatSubtract,
    FloatXor,
    LoadEffectiveAddress,
    ModuloSigned,
    ModuloUnsigned,
    Move,
    MoveSignExtend,
    MultiplyAdd,
    MultiplyHighSigned,
    MultiplyHighUnsigned,
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

    // 128-bit packed integer operations on the float register file (SSE2).
    // Appended after the scalar operations to keep prior enum values stable.
    // The bitwise forms are lane-agnostic; the arithmetic and shift forms name
    // their lane width. Shifts take an immediate count; VecShuffle32 is the
    // four-lane permute (pshufd) and lives on its own opcode because it is the
    // only non-destructive reg/reg/imm shape in the instruction set.
    VecAdd32,
    VecAnd,
    VecOr,
    VecShiftLeft32,
    VecShiftRight32,
    VecShuffle32,
    VecSub32,
    VecXor,
};

// True for the 128-bit packed operations, which only the auto-vectorizer
// creates: they run on the float register file, ignore the CPU flags, and
// keep their immediate operands verbatim (a shift count or a shuffle
// control), so scalar rewrites must leave them alone.
inline bool isVecMicroOp(const MicroOp op)
{
    switch (op)
    {
        case MicroOp::VecAdd32:
        case MicroOp::VecAnd:
        case MicroOp::VecOr:
        case MicroOp::VecShiftLeft32:
        case MicroOp::VecShiftRight32:
        case MicroOp::VecShuffle32:
        case MicroOp::VecSub32:
        case MicroOp::VecXor:
            return true;

        default:
            return false;
    }
}

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
