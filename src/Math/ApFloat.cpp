#include "pch.h"
#include "Math/ApFloat.h"
#include "Core/hash.h"

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

// @temp
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

size_t ApFloat::hash() const
{
    auto h = std::hash<int>()(static_cast<int>(bitWidth_));
    switch (bitWidth_)
    {
        case 32:
            h = hash_combine(h, std::bit_cast<uint32_t>(value_.f32));
            break;
        case 64:
            h = hash_combine(h, std::bit_cast<uint64_t>(value_.f64));
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

SWC_END_NAMESPACE()
