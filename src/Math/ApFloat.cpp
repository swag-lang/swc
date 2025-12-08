#include "pch.h"
#include "Math/ApFloat.h"
#include "Math/ApsInt.h"
#include "Math/Hash.h"

SWC_BEGIN_NAMESPACE()

ApFloat::ApFloat() :
    bitWidth_(64),
    value_{.f64 = 0}
{
}

ApFloat::ApFloat(double value) :
    bitWidth_(64),
    value_{.f64 = value}
{
}

ApFloat::ApFloat(float value) :
    bitWidth_(32),
    value_{.f32 = value}
{
}

void ApFloat::set(float value)
{
    bitWidth_  = 32;
    value_.f32 = value;
}

void ApFloat::set(double value)
{
    bitWidth_  = 64;
    value_.f64 = value;
}

void ApFloat::set(const ApInt& mantissa, int64_t exponent10)
{
    bitWidth_ = 64;

    if (mantissa.isZero())
    {
        value_.f64 = 0.0;
        return;
    }

    const uint32_t bw = mantissa.bitWidth();

    // First, accumulate the unsigned value from bits.
    long double v = 0.0;
    for (uint32_t i = 0; i < bw; ++i)
    {
        if (mantissa.testBit(i))
            v += std::ldexp(1.0L, static_cast<int>(i)); // adds 2^i
    }

    // Apply decimal exponent: mantissa * 10^exponent10
    const long double scale = std::pow(10.0L, static_cast<long double>(exponent10));
    const long double res   = v * scale;

    // Store as double
    value_.f64 = static_cast<double>(res);
}

void ApFloat::set(const ApsInt& value, uint32_t targetBits, bool& exact, bool& overflow)
{
    exact    = false;
    overflow = false;

    // Sanity check: only 32/64 bits supported for now
    SWC_ASSERT(targetBits == 32 || targetBits == 64);

    // Handle zero early
    if (value.isZero())
    {
        if (targetBits == 32)
            set(0.0f);
        else
            set(0.0);
        exact = true;
        return;
    }

    // Work with absolute value to accumulate magnitude
    ApsInt absVal      = value;
    bool   absOverflow = false;
    absVal.abs(absOverflow);
    if (absOverflow)
    {
        // Abs overflow shouldn't normally happen for arbitrary-precision but be safe.
        overflow = true;
        if (targetBits == 32)
            set(std::numeric_limits<float>::infinity());
        else
            set(std::numeric_limits<double>::infinity());
        return;
    }

    const bool isNegative = !value.isUnsigned() && value.isNegative();

    // Accumulate |value| into a long double using its bits: sum( 2^i for each set bit i)
    const uint32_t bw  = absVal.bitWidth();
    long double    mag = 0.0L;
    for (uint32_t i = 0; i < bw; ++i)
    {
        if (absVal.testBit(i))
            mag += std::ldexp(1.0L, static_cast<int>(i)); // adds 2^i
    }

    const long double ldVal = isNegative ? -mag : mag;

    // Now convert long double to the target float type, checking for overflow and exactness
    if (targetBits == 32)
    {
        constexpr long double maxF = std::numeric_limits<float>::max();
        constexpr long double minF = -maxF;

        // Overflow if outside finite float range or already non-finite
        overflow = !std::isfinite(ldVal) || ldVal > maxF || ldVal < minF;
        if (overflow)
        {
            // Store signed infinity as a placeholder; caller should treat this as an error.
            constexpr float inf = std::numeric_limits<float>::infinity();
            set(isNegative ? -inf : inf);
            return;
        }

        const float f = static_cast<float>(ldVal);
        set(f);

        const long double back = f;
        exact                  = (back == ldVal);
        return;
    }

    // targetBits == 64
    constexpr long double maxD = std::numeric_limits<double>::max();
    constexpr long double minD = -maxD;

    overflow = !std::isfinite(ldVal) || ldVal > maxD || ldVal < minD;
    if (overflow)
    {
        constexpr double inf = std::numeric_limits<double>::infinity();
        set(isNegative ? -inf : inf);
        return;
    }

    const double d = static_cast<double>(ldVal);
    set(d);

    const long double back = d;
    exact                  = (back == ldVal);
}

bool ApFloat::isZero() const
{
    switch (bitWidth_)
    {
        case 32:
            // Treat both +0.0f and -0.0f as zero
            return value_.f32 == 0.0f;
        case 64:
            // Treat both +0.0 and -0.0 as zero
            return value_.f64 == 0.0;
        default:
            SWC_UNREACHABLE();
    }
}

void ApFloat::setZero()
{
    switch (bitWidth_)
    {
        case 32:
            value_.f32 = 0.0f;
            break;
        case 64:
            value_.f64 = 0.0;
            break;
        default:
            SWC_UNREACHABLE();
    }
}

bool ApFloat::isNaN() const
{
    switch (bitWidth_)
    {
        case 32:
            return std::isnan(value_.f32);
        case 64:
            return std::isnan(value_.f64);
        default:
            SWC_UNREACHABLE();
    }
}

bool ApFloat::isInfinity() const
{
    switch (bitWidth_)
    {
        case 32:
            return std::isinf(value_.f32);
        case 64:
            return std::isinf(value_.f64);
        default:
            SWC_UNREACHABLE();
    }
}

bool ApFloat::isFinite() const
{
    switch (bitWidth_)
    {
        case 32:
            return std::isfinite(value_.f32);
        case 64:
            return std::isfinite(value_.f64);
        default:
            SWC_UNREACHABLE();
    }
}

bool ApFloat::isNegative() const
{
    switch (bitWidth_)
    {
        case 32:
            return std::signbit(value_.f32) != 0;
        case 64:
            return std::signbit(value_.f64) != 0;
        default:
            SWC_UNREACHABLE();
    }
}

void ApFloat::setNaN()
{
    switch (bitWidth_)
    {
        case 32:
            value_.f32 = std::numeric_limits<float>::quiet_NaN();
            break;
        case 64:
            value_.f64 = std::numeric_limits<double>::quiet_NaN();
            break;
        default:
            SWC_UNREACHABLE();
    }
}

void ApFloat::setInfinity(bool negative)
{
    switch (bitWidth_)
    {
        case 32:
        {
            constexpr float inf = std::numeric_limits<float>::infinity();
            value_.f32          = negative ? -inf : inf;
            break;
        }
        case 64:
        {
            constexpr double inf = std::numeric_limits<double>::infinity();
            value_.f64           = negative ? -inf : inf;
            break;
        }
        default:
            SWC_UNREACHABLE();
    }
}

float ApFloat::asFloat() const
{
    if (bitWidth_ == 32)
        return value_.f32;
    if (bitWidth_ == 64)
        return static_cast<float>(value_.f64);
    SWC_UNREACHABLE();
}

double ApFloat::asDouble() const
{
    if (bitWidth_ == 32)
        return value_.f32;
    if (bitWidth_ == 64)
        return value_.f64;
    SWC_UNREACHABLE();
}

bool ApFloat::same(const ApFloat& other) const
{
    if (bitWidth_ != other.bitWidth_)
        return false;
    switch (bitWidth_)
    {
        case 32:
            return std::bit_cast<uint32_t>(value_.f32) == std::bit_cast<uint32_t>(other.value_.f32);
        case 64:
            return std::bit_cast<uint64_t>(value_.f64) == std::bit_cast<uint64_t>(other.value_.f64);
        default:
            SWC_UNREACHABLE();
    }
}

int ApFloat::compare(const ApFloat& other) const
{
    SWC_ASSERT(bitWidth_ == other.bitWidth_);
    switch (bitWidth_)
    {
        case 32:
            return value_.f32 < other.value_.f32 ? -1 : (value_.f32 > other.value_.f32 ? 1 : 0);
        case 64:
            return value_.f64 < other.value_.f64 ? -1 : (value_.f64 > other.value_.f64 ? 1 : 0);
        default:
            SWC_UNREACHABLE();
    }
}

uint32_t ApFloat::hash() const
{
    uint32_t h = Math::hash(bitWidth_);
    switch (bitWidth_)
    {
        case 32:
            h = Math::hashCombine(h, std::bit_cast<uint32_t>(value_.f32));
            break;
        case 64:
            h = Math::hashCombine(h, std::bit_cast<uint64_t>(value_.f64));
            break;
        default:
            SWC_UNREACHABLE();
    }

    return h;
}

void ApFloat::negate()
{
    switch (bitWidth_)
    {
        case 32:
            value_.f32 = -value_.f32;
            break;
        case 64:
            value_.f64 = -value_.f64;
            break;
        default:
            SWC_UNREACHABLE();
    }
}

void ApFloat::add(const ApFloat& rhs)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);

    switch (bitWidth_)
    {
        case 32:
            value_.f32 += rhs.value_.f32;
            break;
        case 64:
            value_.f64 += rhs.value_.f64;
            break;
        default:
            SWC_UNREACHABLE();
    }
}

void ApFloat::sub(const ApFloat& rhs)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);

    switch (bitWidth_)
    {
        case 32:
            value_.f32 -= rhs.value_.f32;
            break;
        case 64:
            value_.f64 -= rhs.value_.f64;
            break;
        default:
            SWC_UNREACHABLE();
    }
}

void ApFloat::mul(const ApFloat& rhs)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);

    switch (bitWidth_)
    {
        case 32:
            value_.f32 *= rhs.value_.f32;
            break;
        case 64:
            value_.f64 *= rhs.value_.f64;
            break;
        default:
            SWC_UNREACHABLE();
    }
}

void ApFloat::div(const ApFloat& rhs)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);

    switch (bitWidth_)
    {
        case 32:
            SWC_ASSERT(rhs.value_.f32 != 0.0f);
            value_.f32 /= rhs.value_.f32;
            break;
        case 64:
            SWC_ASSERT(rhs.value_.f64 != 0.0f);
            value_.f64 /= rhs.value_.f64;
            break;
        default:
            SWC_UNREACHABLE();
    }
}

bool ApFloat::eq(const ApFloat& rhs) const
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    switch (bitWidth_)
    {
        case 32:
            return value_.f32 == rhs.value_.f32;
        case 64:
            return value_.f64 == rhs.value_.f64;
        default:
            SWC_UNREACHABLE();
    }
}

bool ApFloat::ne(const ApFloat& rhs) const
{
    return !eq(rhs);
}

bool ApFloat::lt(const ApFloat& rhs) const
{
    return compare(rhs) < 0;
}

bool ApFloat::le(const ApFloat& rhs) const
{
    return !rhs.lt(*this);
}

bool ApFloat::gt(const ApFloat& rhs) const
{
    return rhs.lt(*this);
}

bool ApFloat::ge(const ApFloat& rhs) const
{
    return !lt(rhs);
}

Utf8 ApFloat::toString() const
{
    switch (bitWidth_)
    {
        case 32:
        {
            // Handle special values
            if (std::isnan(value_.f32))
                return "nan";
            if (std::isinf(value_.f32))
                return value_.f32 > 0 ? "inf" : "-inf";
            if (value_.f32 == 0.0f && std::signbit(value_.f32))
                return "-0";

            std::array<char, 64> buffer;
            auto [ptr, ec] = std::to_chars(buffer.data(), buffer.data() + buffer.size(), value_.f32, std::chars_format::general);
            SWC_ASSERT(ec == std::errc());
            return Utf8{buffer.data(), static_cast<size_t>(ptr - buffer.data())};
        }
        case 64:
        {
            // Handle special values
            if (std::isnan(value_.f64))
                return "nan";
            if (std::isinf(value_.f64))
                return value_.f64 > 0 ? "inf" : "-inf";
            if (value_.f64 == 0.0 && std::signbit(value_.f64))
                return "-0";

            std::array<char, 64> buffer;
            auto [ptr, ec] = std::to_chars(buffer.data(), buffer.data() + buffer.size(), value_.f64, std::chars_format::general);
            SWC_ASSERT(ec == std::errc());
            return Utf8{buffer.data(), static_cast<size_t>(ptr - buffer.data())};
        }
        default:
            SWC_UNREACHABLE();
    }
}

ApsInt ApFloat::toInt(uint32_t targetBits, bool isUnsigned, bool& isExact, bool& overflow) const
{
    isExact  = true;
    overflow = false;

    SWC_ASSERT(targetBits > 0);

    // NaN / Inf => overflow
    if (!isFinite())
    {
        overflow = true;
        return ApsInt::minValue(targetBits, isUnsigned);
    }

    // Use ApFloat's own representation to get a scalar value.
    long double v;
    switch (bitWidth_)
    {
        case 32:
            v = static_cast<long double>(value_.f32);
            break;
        case 64:
            v = static_cast<long double>(value_.f64);
            break;
        default:
            SWC_UNREACHABLE();
    }

    // Truncate toward zero
    const long double truncated = std::trunc(v);
    if (truncated != v)
        isExact = false;

    // Unsigned target cannot represent negative values
    if (isUnsigned && truncated < 0.0L)
    {
        overflow = true;
        return ApsInt::minValue(targetBits, isUnsigned);
    }

    // We’ll only go through host 64-bit integers for now.
    // If the magnitude doesn't fit in 64 bits, treat as overflow.
    if (isUnsigned)
    {
        constexpr long double maxU64 = static_cast<long double>(std::numeric_limits<uint64_t>::max());
        if (truncated < 0.0L || truncated > maxU64)
        {
            overflow = true;
            return ApsInt::minValue(targetBits, isUnsigned);
        }

        const uint64_t u = static_cast<uint64_t>(truncated);

        // Now check against the target bit width.
        if (targetBits < 64)
        {
            const uint64_t maxTarget = (targetBits == 64) ? std::numeric_limits<uint64_t>::max() : ((uint64_t{1} << targetBits) - 1);
            if (u > maxTarget)
            {
                overflow = true;
                return ApsInt::minValue(targetBits, isUnsigned);
            }
        }

        return ApsInt(std::bit_cast<int64_t>(u), targetBits, true);
    }

    constexpr long double minI64 = static_cast<long double>(std::numeric_limits<int64_t>::min());
    constexpr long double maxI64 = static_cast<long double>(std::numeric_limits<int64_t>::max());

    if (truncated < minI64 || truncated > maxI64)
    {
        overflow = true;
        return ApsInt::minValue(targetBits, isUnsigned);
    }

    const int64_t s = static_cast<int64_t>(truncated);

    // Check against the target signed range if targetBits <= 63.
    if (targetBits < 63)
    {
        const int64_t minTarget = -(static_cast<int64_t>(1) << (targetBits - 1));
        const int64_t maxTarget = (static_cast<int64_t>(1) << (targetBits - 1)) - 1;
        if (s < minTarget || s > maxTarget)
        {
            overflow = true;
            return ApsInt::minValue(targetBits, isUnsigned);
        }
    }

    return ApsInt(s, targetBits, false);
}

ApFloat ApFloat::convertTo(uint32_t targetBits, bool& isExact, bool& overflow) const
{
    isExact  = true;
    overflow = false;

    SWC_ASSERT(targetBits == 32 || targetBits == 64);

    if (bitWidth_ == targetBits)
        return *this;

    ApFloat result;

    // Represent the original value in long double for comparison.
    long double orig;
    switch (bitWidth_)
    {
        case 32:
            orig = static_cast<long double>(value_.f32);
            break;
        case 64:
            orig = static_cast<long double>(value_.f64);
            break;
        default:
            SWC_UNREACHABLE();
    }

    if (targetBits == 32)
    {
        float v;
        if (bitWidth_ == 32)
            v = value_.f32;
        else
            v = static_cast<float>(value_.f64);

        result.set(v);

        const long double back = static_cast<long double>(v);
        isExact                = (back == orig);
    }
    else // targetBits == 64
    {
        double v;
        if (bitWidth_ == 64)
            v = value_.f64;
        else // 32 -> 64
            v = static_cast<double>(value_.f32);

        result.set(v);

        const long double back = static_cast<long double>(v);
        isExact                = (back == orig);
    }

    overflow = false;
    return result;
}

SWC_END_NAMESPACE()
