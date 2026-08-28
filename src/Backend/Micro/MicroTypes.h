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
        case 16:
            return MicroOpBits::B128;
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
        case 128:
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

    // 128-bit packed operations on the float register file. Everything from
    // VecAdd32 to the end of the enum is a packed operation: isVecMicroOp is a
    // range test, so a new scalar operation goes before VecAdd32 and a new
    // packed one after it. The bitwise forms are lane-agnostic; the other
    // forms name their lane width and signedness where the instruction cares.
    // Shifts and rounds take an immediate; VecShuffle32 is the four-lane
    // permute (pshufd).
    VecAdd32,
    VecAnd,
    VecOr,
    VecShiftLeft32,
    VecShiftRight32,
    VecShuffle32,
    VecSub32,
    VecXor,

    // Packed integer arithmetic, three-operand only (OpBinaryRegRegReg).
    VecAdd8,
    VecAdd16,
    VecAdd64,
    VecSub8,
    VecSub16,
    VecSub64,
    VecMul16,
    VecMul32,
    VecMulU32Wide,
    VecSatAddS8,
    VecSatAddS16,
    VecSatAddU8,
    VecSatAddU16,
    VecSatSubS8,
    VecSatSubS16,
    VecSatSubU8,
    VecSatSubU16,
    VecAvgU8,
    VecAvgU16,
    VecMaddS16,
    VecMaddUBS16,
    VecSadU8,
    VecAndNot,

    // Packed integer min/max (OpBinaryRegRegReg).
    VecMinS8,
    VecMinS16,
    VecMinS32,
    VecMinU8,
    VecMinU16,
    VecMinU32,
    VecMaxS8,
    VecMaxS16,
    VecMaxS32,
    VecMaxU8,
    VecMaxU16,
    VecMaxU32,

    // Packed integer compares, producing all-ones/all-zeros lanes
    // (OpBinaryRegRegReg). Greater-than exists only in signed form; unsigned
    // compares are synthesized by biasing the sign bit.
    VecCmpEq8,
    VecCmpEq16,
    VecCmpEq32,
    VecCmpEq64,
    VecCmpGtS8,
    VecCmpGtS16,
    VecCmpGtS32,
    VecCmpGtS64,

    // Saturating narrowing packs and lane interleaves (OpBinaryRegRegReg).
    // Pack lane widths name the SOURCE lanes; VecPermB is the dynamic byte
    // table lookup (pshufb).
    VecPackSS16,
    VecPackSS32,
    VecPackUS16,
    VecPackUS32,
    VecUnpackLo8,
    VecUnpackLo16,
    VecUnpackLo32,
    VecUnpackLo64,
    VecUnpackHi8,
    VecUnpackHi16,
    VecUnpackHi32,
    VecUnpackHi64,
    VecPermB,
    // Byte blend through the sign bit of every mask byte (vpblendvb): an
    // OpTernaryRegRegReg whose first register is both the destination and the
    // lanes kept where the mask is clear, the second the lanes taken where it
    // is set, and the third the mask.
    VecBlendVB,

    // Packed float arithmetic (OpBinaryRegRegReg).
    VecAddF32,
    VecAddF64,
    VecSubF32,
    VecSubF64,
    VecMulF32,
    VecMulF64,
    VecDivF32,
    VecDivF64,
    VecMinF32,
    VecMinF64,
    VecMaxF32,
    VecMaxF64,

    // Packed unary forms, non-destructive (VecUnaryRegReg). The widen forms
    // extend the low eight/four/two lanes to double width; the movemask forms
    // write the lane sign bits into an integer register.
    VecAbsS8,
    VecAbsS16,
    VecAbsS32,
    VecWidenLoS8,
    VecWidenLoS16,
    VecWidenLoS32,
    VecWidenLoU8,
    VecWidenLoU16,
    VecWidenLoU32,
    VecSqrtF32,
    VecSqrtF64,
    VecTruncF32ToS32,
    VecMoveMaskB,
    VecMoveMaskF32,
    VecMoveMaskF64,

    // Packed shifts by immediate (OpBinaryRegRegImm). The byte shifts move
    // whole bytes across the register (pslldq/psrldq); the A forms are
    // arithmetic right shifts, which the hardware has only for 16/32-bit
    // lanes. VecRoundF32/F64 carry the rounding mode in the immediate.
    VecShiftLeft16,
    VecShiftLeft64,
    VecShiftRight16,
    VecShiftRight64,
    VecShiftRightA16,
    VecShiftRightA32,
    VecShiftLeftBytes,
    VecShiftRightBytes,
    VecRoundF32,
    VecRoundF64,

    // Packed forms taking two sources and an immediate
    // (OpTernaryRegRegRegImm): the float compare carries a predicate,
    // VecShufF32 a four-lane control over both sources, and VecAlignR a byte
    // offset into their concatenation, the first source above the second.
    VecCmpF32,
    VecCmpF64,
    VecShufF32,
    VecAlignR,

    // Packed shifts by a variable count (OpBinaryRegRegReg): every lane
    // shifts by the value in the low 64 bits of the second source.
    VecShiftLeftV16,
    VecShiftLeftV32,
    VecShiftLeftV64,
    VecShiftRightV16,
    VecShiftRightV32,
    VecShiftRightV64,
    VecShiftRightAV16,
    VecShiftRightAV32,
};

// True for the 128-bit packed operations: they run on the float register
// file, ignore the CPU flags, and keep their immediate operands verbatim (a
// shift count, a rounding mode, a shuffle control), so scalar rewrites must
// leave them alone. Every operation from VecAdd32 on is packed - see the
// enum's layout comment.
inline bool isVecMicroOp(const MicroOp op)
{
    return op >= MicroOp::VecAdd32;
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
