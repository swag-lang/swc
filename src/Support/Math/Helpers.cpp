#include "pch.h"
#include "Support/Math/Helpers.h"
#include "Support/Math/ApFloat.h"
#include "Support/Report/DiagnosticDef.h"

SWC_BEGIN_NAMESPACE();
class ApFloat;

namespace Math
{
    void mul64X64(uint64_t a, uint64_t b, uint64_t& lo, uint64_t& hi)
    {
#ifdef __SIZEOF_INT128__
        __uint128_t r = (__uint128_t) a * b;
        lo            = (uint64_t) r;
        hi            = (uint64_t) (r >> 64);

#elif defined(_MSC_VER) && defined(_M_X64)
        lo = _umul128(a, b, &hi);

#else
        uint64_t ha = a >> 32, hb = b >> 32;
        uint64_t la = (uint32_t) a, lb = (uint32_t) b;
        uint64_t hi_tmp, lo_tmp;

        uint64_t rh  = ha * hb;
        uint64_t rm0 = ha * lb;
        uint64_t rm1 = hb * la;
        uint64_t rl  = la * lb;

        uint64_t t = rl + (rm0 << 32);
        uint64_t c = t < rl;
        lo_tmp     = t + (rm1 << 32);
        c += lo_tmp < t;
        hi_tmp = rh + (rm0 >> 32) + (rm1 >> 32) + c;

        lo = lo_tmp;
        hi = hi_tmp;
#endif
    }

    void div128X64(uint64_t hi, uint64_t lo, uint64_t d, uint64_t& q, uint64_t& r)
    {
        SWC_ASSERT(d != 0);

#ifdef __SIZEOF_INT128__
        // Fast path using native 128-bit integer.
        __uint128_t num  = (static_cast<__uint128_t>(hi) << 64) | lo;
        __uint128_t q128 = num / d;
        __uint128_t r128 = num % d;

        // For (2^128-1) / (2^64) the quotient is < 2^64, so it fits.
        q = static_cast<uint64_t>(q128);
        r = static_cast<uint64_t>(r128);

#elif defined(_MSC_VER) && defined(_M_X64)
        q = _udiv128(hi, lo, d, &r);

#else
        // Portable fallback: bit-by-bit restoring division on 128 bits.
        //
        // Conceptually divides (hi<<64 | lo) by d.
        // We maintain 'rem' as the running remainder (up to 64 bits),
        // and shift in bits from 'lo' high-to-low, just like standard
        // long division.
        uint64_t rem   = hi;
        uint64_t qWord = 0;

        for (int bit = 63; bit >= 0; --bit)
        {
            rem = (rem << 1) | ((lo >> bit) & 1u);
            qWord <<= 1;
            if (rem >= d)
            {
                rem -= d;
                qWord |= 1u;
            }
        }

        q = qWord;
        r = rem;
#endif
    }

    ApsInt bitCastToApInt(const ApFloat& src, bool isUnsigned)
    {
        const uint32_t bw = src.bitWidth();

        if (bw == 32)
        {
            const float f = src.asFloat();
            uint32_t    u = 0;
            std::memcpy(&u, &f, sizeof(u));
            return ApsInt(u, 32, isUnsigned);
        }

        if (bw == 64)
        {
            const double d = src.asDouble();
            int64_t      u = 0;
            std::memcpy(&u, &d, sizeof(u));
            return ApsInt(u, 64, isUnsigned);
        }

        SWC_UNREACHABLE();
    }

    ApFloat bitCastToApFloat(const ApsInt& src, uint32_t floatBits)
    {
        const uint64_t raw = src.asI64();

        if (floatBits == 32)
        {
            const uint32_t u = static_cast<uint32_t>(raw);
            float          f = 0.0f;
            std::memcpy(&f, &u, sizeof(f));
            return ApFloat(f);
        }

        if (floatBits == 64)
        {
            const uint64_t u = raw;
            double         d = 0.0;
            std::memcpy(&d, &u, sizeof(d));
            return ApFloat(d);
        }

        SWC_UNREACHABLE();
    }

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
