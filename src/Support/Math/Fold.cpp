#include "pch.h"
#include "Support/Math/Fold.h"
#include "Support/Report/DiagnosticDef.h"

SWC_BEGIN_NAMESPACE();

namespace Math
{
    DiagnosticId foldStatusDiagnosticId(FoldStatus status)
    {
        switch (status)
        {
            case FoldStatus::DivisionByZero:
                return DiagnosticId::safety_err_division_zero;

            case FoldStatus::Overflow:
                return DiagnosticId::safety_err_integer_overflow;

            case FoldStatus::NegativeShift:
                return DiagnosticId::safety_err_negative_shift;

            case FoldStatus::InvalidArgument:
                return DiagnosticId::safety_err_invalid_argument;

            default:
                return DiagnosticId::None;
        }
    }

    bool isSafetyError(FoldStatus status)
    {
        return foldStatusDiagnosticId(status) != DiagnosticId::None;
    }

    bool requiresNonZeroRhs(FoldBinaryOp op)
    {
        switch (op)
        {
            case FoldBinaryOp::Divide:
            case FoldBinaryOp::Modulo:
                return true;

            default:
                return false;
        }
    }

    FoldStatus foldUnaryInt(ApsInt& outResult, const ApsInt& value, FoldUnaryOp op)
    {
        outResult = value;
        switch (op)
        {
            case FoldUnaryOp::Plus:
                outResult.setUnsigned(true);
                return FoldStatus::Ok;

            case FoldUnaryOp::Minus:
            {
                bool overflow = false;
                outResult.negate(overflow);
                if (overflow)
                    return FoldStatus::Overflow;
                outResult.setUnsigned(false);
                return FoldStatus::Ok;
            }

            case FoldUnaryOp::BitwiseNot:
                outResult.invertAllBits();
                return FoldStatus::Ok;

            default:
                return FoldStatus::Unsupported;
        }
    }

    FoldStatus foldUnaryFloat(ApFloat& outResult, const ApFloat& value, FoldUnaryOp op)
    {
        outResult = value;
        switch (op)
        {
            case FoldUnaryOp::Plus:
                return FoldStatus::Ok;

            case FoldUnaryOp::Minus:
                outResult.negate();
                return FoldStatus::Ok;

            default:
                return FoldStatus::Unsupported;
        }
    }

    namespace
    {
        FoldStatus computeShiftAmount(uint64_t& outAmount, const ApsInt& right, const FoldBinaryIntOptions& options)
        {
            if (right.isNegative())
                return FoldStatus::NegativeShift;

            if (!right.fits64())
            {
                if (!options.clampShiftCount || options.shiftBitWidth == 0)
                {
                    if (options.ignoreShiftOverflow)
                    {
                        outAmount = 0;
                        return FoldStatus::Ok;
                    }

                    return FoldStatus::Overflow;
                }

                outAmount = options.shiftBitWidth - 1;
                return FoldStatus::Ok;
            }

            outAmount = static_cast<uint64_t>(right.asI64());
            if (options.clampShiftCount && options.shiftBitWidth != 0)
                outAmount = std::min<uint64_t>(outAmount, options.shiftBitWidth - 1);
            return FoldStatus::Ok;
        }
    }

    FoldStatus foldBinaryInt(ApsInt& outResult, const ApsInt& left, const ApsInt& right, FoldBinaryOp op, const FoldBinaryIntOptions& options)
    {
        outResult = left;
        if (op != FoldBinaryOp::ShiftArithmeticRight && outResult.isUnsigned() != right.isUnsigned())
            return FoldStatus::Unsupported;

        bool overflow = false;
        switch (op)
        {
            case FoldBinaryOp::Add:
                outResult.add(right, overflow);
                break;

            case FoldBinaryOp::Subtract:
                outResult.sub(right, overflow);
                break;

            case FoldBinaryOp::Multiply:
                outResult.mul(right, overflow);
                break;

            case FoldBinaryOp::Divide:
                if (right.isZero())
                    return FoldStatus::DivisionByZero;
                outResult.div(right, overflow);
                break;

            case FoldBinaryOp::Modulo:
                if (right.isZero())
                    return FoldStatus::DivisionByZero;
                outResult.mod(right, overflow);
                break;

            case FoldBinaryOp::BitwiseAnd:
                outResult.bitwiseAnd(right);
                break;

            case FoldBinaryOp::BitwiseOr:
                outResult.bitwiseOr(right);
                break;

            case FoldBinaryOp::BitwiseXor:
                outResult.bitwiseXor(right);
                break;

            case FoldBinaryOp::ShiftLeft:
            {
                uint64_t         shiftAmount = 0;
                const FoldStatus shiftStatus = computeShiftAmount(shiftAmount, right, options);
                if (shiftStatus != FoldStatus::Ok)
                    return shiftStatus;
                outResult.shiftLeft(shiftAmount, overflow);
                break;
            }

            case FoldBinaryOp::ShiftRight:
            {
                uint64_t         shiftAmount = 0;
                const FoldStatus shiftStatus = computeShiftAmount(shiftAmount, right, options);
                if (shiftStatus != FoldStatus::Ok)
                    return shiftStatus;
                outResult.shiftRight(shiftAmount);
                break;
            }

            case FoldBinaryOp::ShiftArithmeticRight:
            {
                uint64_t         shiftAmount = 0;
                const FoldStatus shiftStatus = computeShiftAmount(shiftAmount, right, options);
                if (shiftStatus != FoldStatus::Ok)
                    return shiftStatus;

                const bool wasUnsigned = outResult.isUnsigned();
                outResult.setSigned(true);
                outResult.shiftRight(shiftAmount);
                outResult.setUnsigned(wasUnsigned);
                break;
            }

            default:
                return FoldStatus::Unsupported;
        }

        if (overflow)
        {
            if (options.ignoreShiftOverflow && op == FoldBinaryOp::ShiftLeft)
                return FoldStatus::Ok;
            return FoldStatus::Overflow;
        }

        return FoldStatus::Ok;
    }

    FoldStatus foldBinaryFloat(ApFloat& outResult, const ApFloat& left, const ApFloat& right, FoldBinaryOp op)
    {
        outResult = left;
        switch (op)
        {
            case FoldBinaryOp::Add:
                outResult.add(right);
                return FoldStatus::Ok;

            case FoldBinaryOp::Subtract:
                outResult.sub(right);
                return FoldStatus::Ok;

            case FoldBinaryOp::Multiply:
                outResult.mul(right);
                return FoldStatus::Ok;

            case FoldBinaryOp::Divide:
                if (right.isZero())
                    return FoldStatus::DivisionByZero;
                outResult.div(right);
                return FoldStatus::Ok;

            default:
                return FoldStatus::Unsupported;
        }
    }

    FoldStatus foldIntrinsicUnaryFloat(double& outResult, double value, FoldIntrinsicUnaryFloatOp op)
    {
        switch (op)
        {
            case FoldIntrinsicUnaryFloatOp::Sqrt:
                if (value < 0.0)
                    return FoldStatus::InvalidArgument;
                outResult = std::sqrt(value);
                break;

            case FoldIntrinsicUnaryFloatOp::Sin:
                outResult = std::sin(value);
                break;

            case FoldIntrinsicUnaryFloatOp::Cos:
                outResult = std::cos(value);
                break;

            case FoldIntrinsicUnaryFloatOp::Tan:
                outResult = std::tan(value);
                break;

            case FoldIntrinsicUnaryFloatOp::Sinh:
                outResult = std::sinh(value);
                break;

            case FoldIntrinsicUnaryFloatOp::Cosh:
                outResult = std::cosh(value);
                break;

            case FoldIntrinsicUnaryFloatOp::Tanh:
                outResult = std::tanh(value);
                break;

            case FoldIntrinsicUnaryFloatOp::ASin:
                if (value < -1.0 || value > 1.0)
                    return FoldStatus::InvalidArgument;
                outResult = std::asin(value);
                break;

            case FoldIntrinsicUnaryFloatOp::ACos:
                if (value < -1.0 || value > 1.0)
                    return FoldStatus::InvalidArgument;
                outResult = std::acos(value);
                break;

            case FoldIntrinsicUnaryFloatOp::ATan:
                outResult = std::atan(value);
                break;

            case FoldIntrinsicUnaryFloatOp::Log:
                if (value <= 0.0)
                    return FoldStatus::InvalidArgument;
                outResult = std::log(value);
                break;

            case FoldIntrinsicUnaryFloatOp::Log2:
                if (value <= 0.0)
                    return FoldStatus::InvalidArgument;
                outResult = std::log2(value);
                break;

            case FoldIntrinsicUnaryFloatOp::Log10:
                if (value <= 0.0)
                    return FoldStatus::InvalidArgument;
                outResult = std::log10(value);
                break;

            case FoldIntrinsicUnaryFloatOp::Floor:
                outResult = std::floor(value);
                break;

            case FoldIntrinsicUnaryFloatOp::Ceil:
                outResult = std::ceil(value);
                break;

            case FoldIntrinsicUnaryFloatOp::Trunc:
                outResult = std::trunc(value);
                break;

            case FoldIntrinsicUnaryFloatOp::Round:
                outResult = std::round(value);
                break;

            case FoldIntrinsicUnaryFloatOp::Abs:
                outResult = std::fabs(value);
                break;

            case FoldIntrinsicUnaryFloatOp::Exp:
                outResult = std::exp(value);
                break;

            case FoldIntrinsicUnaryFloatOp::Exp2:
                outResult = std::exp2(value);
                break;

            default:
                return FoldStatus::Unsupported;
        }

        if (std::isnan(outResult))
            return FoldStatus::InvalidArgument;
        return FoldStatus::Ok;
    }

    FoldStatus foldIntrinsicBinaryFloat(double& outResult, double left, double right, FoldIntrinsicBinaryFloatOp op)
    {
        switch (op)
        {
            case FoldIntrinsicBinaryFloatOp::ATan2:
                outResult = std::atan2(left, right);
                return FoldStatus::Ok;

            case FoldIntrinsicBinaryFloatOp::Pow:
                outResult = std::pow(left, right);
                if (std::isnan(outResult))
                    return FoldStatus::InvalidArgument;
                return FoldStatus::Ok;

            default:
                return FoldStatus::Unsupported;
        }
    }

    FoldStatus foldIntrinsicTernaryFloat(double& outResult, double first, double second, double third, FoldIntrinsicTernaryFloatOp op)
    {
        switch (op)
        {
            case FoldIntrinsicTernaryFloatOp::MulAdd:
                outResult = std::fma(first, second, third);
                return FoldStatus::Ok;

            default:
                return FoldStatus::Unsupported;
        }
    }
}

SWC_END_NAMESPACE();
