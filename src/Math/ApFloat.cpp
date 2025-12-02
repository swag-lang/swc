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

ApFloat::ApFloat(float value) :
    bitWidth_(32),
    value_{.f32 = value}
{
}

ApFloat::ApFloat(double value) :
    bitWidth_(64),
    value_{.f64 = value}
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

size_t ApFloat::hash() const
{
    auto h = std::hash<int>()(static_cast<int>(bitWidth_));
    switch (bitWidth_)
    {
        case 32:
            h = Math::hash_combine(h, std::bit_cast<uint32_t>(value_.f32));
            break;
        case 64:
            h = Math::hash_combine(h, std::bit_cast<uint64_t>(value_.f64));
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

SWC_END_NAMESPACE()
