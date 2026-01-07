#include "pch.h"
#include "Math/ApFloat.h"
#include "Math/ApsInt.h"
#include "Math/Hash.h"

SWC_BEGIN_NAMESPACE();

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
    if (targetBits == 0)
        targetBits = 64;
    SWC_ASSERT(targetBits == 32 || targetBits == 64);

    exact    = false;
    overflow = false; // no float/double overflow with 64-bit ints

    if (value.isZero())
    {
        if (targetBits == 32)
            set(0.0f);
        else
            set(0.0);
        exact = true;
        return;
    }

    const uint64_t bits = value.asI64();

    if (value.isUnsigned())
    {
        const uint64_t u = bits;
        if (targetBits == 32)
        {
            const float f = static_cast<float>(u);
            set(f);
            exact = (static_cast<uint64_t>(f) == u);
        }
        else
        {
            const double d = static_cast<double>(u);
            set(d);
            exact = (static_cast<uint64_t>(d) == u);
        }
    }
    else
    {
        const int64_t s = static_cast<int64_t>(bits);
        if (targetBits == 32)
        {
            const float f = static_cast<float>(s);
            set(f);
            exact = (static_cast<int64_t>(f) == s);
        }
        else
        {
            const double d = static_cast<double>(s);
            set(d);
            exact = (static_cast<int64_t>(d) == s);
        }
    }
}

bool ApFloat::isZero() const
{
    switch (bitWidth_)
    {
        case 32:
            return value_.f32 == 0.0f;
        case 64:
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

    // NaN / Inf => overflow
    if (!isFinite())
    {
        overflow = true;
        return ApsInt::minValue(targetBits, isUnsigned);
    }

    // Get scalar as double (float->double is exact).
    const double v         = asDouble();
    const double truncated = std::trunc(v);

    if (truncated != v)
        isExact = false;

    // Unsigned case
    if (isUnsigned)
    {
        if (truncated < 0.0 || truncated > static_cast<double>(std::numeric_limits<uint64_t>::max()))
        {
            overflow = true;
            return ApsInt::minValue(targetBits, isUnsigned);
        }

        const uint64_t u = static_cast<uint64_t>(truncated);

        if (targetBits < 64)
        {
            const uint64_t maxTarget = (uint64_t{1} << targetBits) - 1;
            if (u > maxTarget)
            {
                overflow = true;
                return ApsInt::minValue(targetBits, isUnsigned);
            }
        }

        // Assuming ApsInt takes a 64-bit value encoded in int64_t when isUnsigned=true.
        return ApsInt(std::bit_cast<int64_t>(u), targetBits, true);
    }

    // Signed case
    if (truncated < static_cast<double>(std::numeric_limits<int64_t>::min()) ||
        truncated > static_cast<double>(std::numeric_limits<int64_t>::max()))
    {
        overflow = true;
        return ApsInt::minValue(targetBits, isUnsigned);
    }

    const int64_t s = static_cast<int64_t>(truncated);

    if (targetBits < 63)
    {
        const int64_t minTarget = -(int64_t{1} << (targetBits - 1));
        const int64_t maxTarget = (int64_t{1} << (targetBits - 1)) - 1;
        if (s < minTarget || s > maxTarget)
        {
            overflow = true;
            return ApsInt::minValue(targetBits, isUnsigned);
        }
    }

    return ApsInt(s, targetBits, false);
}

ApFloat ApFloat::toFloat(uint32_t targetBits, bool& isExact, bool& overflow) const
{
    SWC_ASSERT(targetBits == 32 || targetBits == 64);
    SWC_ASSERT(bitWidth_ == 32 || bitWidth_ == 64);

    overflow = false;

    if (bitWidth_ == targetBits)
    {
        isExact = true;
        return *this;
    }

    ApFloat result;

    if (bitWidth_ == 32 && targetBits == 64)
    {
        const double d = value_.f32;
        result.set(d);
        isExact = true;
    }
    else if (bitWidth_ == 64 && targetBits == 32)
    {
        const float f = static_cast<float>(value_.f64);
        result.set(f);
        isExact = static_cast<double>(f) == value_.f64;
    }
    else
    {
        SWC_UNREACHABLE();
    }

    return result;
}

uint32_t ApFloat::minBits() const
{
    SWC_ASSERT(bitWidth_ == 32 || bitWidth_ == 64);

    // If we're already 32-bit, that's the minimum we support.
    if (bitWidth_ == 32)
        return 32;

    const double d = value_.f64;

    // NaN and Inf exist in both float and double.
    if (std::isnan(d))
        return 32;
    if (std::isinf(d))
        return 32;

    // Preserve -0 exactly (signbit matters, but the round-trip test below also works).
    // Check whether the value round-trips through float unchanged.
    const float  f  = static_cast<float>(d);
    const double rt = f;

    if (rt == d)
    {
        // Covers normal/subnormal/zero (including -0) that are exactly representable.
        // Also covers values that don't overflow/underflow in float.
        return 32;
    }

    return 64;
}

SWC_END_NAMESPACE();
