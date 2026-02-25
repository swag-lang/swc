#pragma once
#include "Support/Math/ApFloat.h"
#include "Support/Math/ApsInt.h"

SWC_BEGIN_NAMESPACE();
enum class DiagnosticId;

namespace Math
{
    enum class FoldStatus : uint8_t
    {
        Ok,
        Unsupported,
        DivisionByZero,
        Overflow,
        NegativeShift,
        InvalidArgument,
    };

    enum class FoldUnaryOp : uint8_t
    {
        Plus,
        Minus,
        BitwiseNot,
    };

    enum class FoldBinaryOp : uint8_t
    {
        Add,
        Subtract,
        Multiply,
        Divide,
        Modulo,
        BitwiseAnd,
        BitwiseOr,
        BitwiseXor,
        ShiftLeft,
        ShiftRight,
        ShiftArithmeticRight,
    };

    enum class FoldIntrinsicUnaryFloatOp : uint8_t
    {
        Sqrt,
        Sin,
        Cos,
        Tan,
        Sinh,
        Cosh,
        Tanh,
        ASin,
        ACos,
        ATan,
        Log,
        Log2,
        Log10,
        Floor,
        Ceil,
        Trunc,
        Round,
        Abs,
        Exp,
        Exp2,
    };

    enum class FoldIntrinsicBinaryFloatOp : uint8_t
    {
        ATan2,
        Pow,
    };

    enum class FoldIntrinsicTernaryFloatOp : uint8_t
    {
        MulAdd,
    };

    struct FoldBinaryIntOptions
    {
        bool     clampShiftCount     = false;
        bool     ignoreShiftOverflow = false;
        uint32_t shiftBitWidth       = 0;
    };

    void mul64X64(uint64_t a, uint64_t b, uint64_t& lo, uint64_t& hi);
    void div128X64(uint64_t hi, uint64_t lo, uint64_t d, uint64_t& q, uint64_t& r);

    ApFloat bitCastToApFloat(const ApsInt& src, uint32_t floatBits);
    ApsInt  bitCastToApInt(const ApFloat& src, bool isUnsigned);

    DiagnosticId foldStatusDiagnosticId(FoldStatus status);
    bool         isSafetyError(FoldStatus status);
    bool         requiresNonZeroRhs(FoldBinaryOp op);
    FoldStatus   foldUnaryInt(ApsInt& outResult, const ApsInt& value, FoldUnaryOp op);
    FoldStatus   foldUnaryFloat(ApFloat& outResult, const ApFloat& value, FoldUnaryOp op);
    FoldStatus   foldBinaryInt(ApsInt& outResult, const ApsInt& left, const ApsInt& right, FoldBinaryOp op, const FoldBinaryIntOptions& options = {});
    FoldStatus   foldBinaryFloat(ApFloat& outResult, const ApFloat& left, const ApFloat& right, FoldBinaryOp op);
    FoldStatus   foldIntrinsicUnaryFloat(double& outResult, double value, FoldIntrinsicUnaryFloatOp op);
    FoldStatus   foldIntrinsicBinaryFloat(double& outResult, double left, double right, FoldIntrinsicBinaryFloatOp op);
    FoldStatus   foldIntrinsicTernaryFloat(double& outResult, double first, double second, double third, FoldIntrinsicTernaryFloatOp op);

    static constexpr uint32_t alignUpU32(uint32_t v, uint32_t a) noexcept
    {
        if (!a)
            return v;

        const uint32_t rem = v % a;
        if (!rem)
            return v;

        return v + a - rem;
    }

    static constexpr uint64_t alignUpU64(uint64_t v, uint64_t a) noexcept
    {
        if (!a)
            return v;

        const uint64_t rem = v % a;
        if (!rem)
            return v;

        return v + a - rem;
    }
}

SWC_END_NAMESPACE();
