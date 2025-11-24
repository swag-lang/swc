#include <utility>

#include "pch.h"

#include "Core/hash.h"
#include "Math/ApFloat.h"

SWC_BEGIN_NAMESPACE()

ApFloat::ApFloat() :
    words_{0},
    bitWidth_(64),
    expWidth_(11),
    mantissaWidth_(52),
    numWords_(computeNumWords(bitWidth_))
{
    clearWords(); // +0.0 by default
}

ApFloat::ApFloat(uint16_t expWidth, uint16_t mantissaWidth) :
    words_{0},
    bitWidth_(1u + expWidth + mantissaWidth),
    expWidth_(expWidth),
    mantissaWidth_(mantissaWidth),
    numWords_(computeNumWords(bitWidth_))
{
    SWC_ASSERT(bitWidth_ <= MAX_BITS);
    clearWords();
}

ApFloat::ApFloat(double value) :
    ApFloat()
{
    fromDouble(value);
}

ApFloat::ApFloat(double value, uint16_t expWidth, uint16_t mantissaWidth) :
    ApFloat(expWidth, mantissaWidth)
{
    fromDouble(value);
}

uint8_t ApFloat::computeNumWords(uint32_t bitWidth)
{
    SWC_ASSERT(bitWidth > 0 && bitWidth <= MAX_BITS);
    return static_cast<uint8_t>((bitWidth + WORD_BITS - 1u) / WORD_BITS);
}

void ApFloat::clearWords()
{
    std::fill_n(words_, numWords_, size_t{0});
}

uint64_t ApFloat::getStorage() const
{
    uint64_t           value    = 0;
    constexpr uint64_t wordMask = (WORD_BITS >= 64) ? ~0 : ((1 << WORD_BITS) - 1ull);

    for (uint8_t i = 0; i < numWords_; ++i)
    {
        const uint64_t w = static_cast<uint64_t>(words_[i]) & wordMask;
        value |= (w << (i * WORD_BITS));
    }

    return value;
}

void ApFloat::setStorage(uint64_t value)
{
    constexpr uint64_t wordMask = (WORD_BITS >= 64) ? ~0 : ((1 << WORD_BITS) - 1ull);
    for (uint8_t i = 0; i < numWords_; ++i)
        words_[i] = static_cast<size_t>((value >> (i * WORD_BITS)) & wordMask);
    for (uint8_t i = numWords_; i < MAX_WORDS; ++i)
        words_[i] = 0;
}

uint64_t ApFloat::getMantissaMask() const
{
    if (mantissaWidth_ == 0)
        return 0;
    if (mantissaWidth_ >= 64)
        return ~0;
    return (1 << mantissaWidth_) - 1ull;
}

uint64_t ApFloat::getExponentMask() const
{
    if (expWidth_ == 0)
        return 0;
    if (expWidth_ >= 64)
        return ~0;
    return ((1 << expWidth_) - 1ull) << mantissaWidth_;
}

uint64_t ApFloat::getSignMask() const
{
    if (bitWidth_ == 0)
        return 0;
    return 1 << (bitWidth_ - 1u);
}

bool ApFloat::isNegative() const
{
    const uint64_t storage = getStorage();
    return (storage & getSignMask()) != 0;
}

void ApFloat::setNegative(bool isNegative)
{
    uint64_t       storage  = getStorage();
    const uint64_t signMask = getSignMask();

    if (isNegative)
        storage |= signMask;
    else
        storage &= ~signMask;

    setStorage(storage);
}

ApFloat::Category ApFloat::getCategory() const
{
    const uint64_t storage      = getStorage();
    const uint64_t mantissaMask = getMantissaMask();
    const uint64_t exponentMask = getExponentMask();

    const uint64_t mantissa = storage & mantissaMask;
    const uint64_t exponent = (storage & exponentMask) >> mantissaWidth_;

    const uint64_t maxExponent = (expWidth_ == 0) ? 0 : ((1 << expWidth_) - 1ull);

    if (expWidth_ == 0)
    {
        // No exponent -> treat this as a fixed-point-like encoding; we'll say:
        // zero if mantissa is 0, otherwise Normal.
        return (mantissa == 0) ? Category::Zero : Category::Normal;
    }

    if (exponent == 0)
    {
        if (mantissa == 0)
            return Category::Zero;
        return Category::Subnormal;
    }

    if (exponent == maxExponent)
    {
        if (mantissa == 0)
            return Category::Inf;
        return Category::NaN;
    }

    return Category::Normal;
}

bool ApFloat::isZero() const
{
    return getCategory() == Category::Zero;
}

bool ApFloat::isInf() const
{
    return getCategory() == Category::Inf;
}

bool ApFloat::isNaN() const
{
    return getCategory() == Category::NaN;
}

bool ApFloat::isSubnormal() const
{
    return getCategory() == Category::Subnormal;
}

bool ApFloat::isNormal() const
{
    return getCategory() == Category::Normal;
}

bool ApFloat::isFinite() const
{
    const Category c = getCategory();
    return c == Category::Zero ||
           c == Category::Normal ||
           c == Category::Subnormal;
}

void ApFloat::resetToZero(bool negative)
{
    clearWords();
    if (negative)
    {
        const uint64_t storage = getSignMask();
        setStorage(storage);
    }
}

void ApFloat::fromDouble(double value)
{
    // Handle NaN
    if (std::isnan(value))
    {
        // sign = 0, exponent all ones, mantissa non-zero
        constexpr uint64_t signBit     = 0;
        const uint64_t     maxExponent = (expWidth_ == 0) ? 0 : ((1 << expWidth_) - 1ull);
        constexpr uint64_t mantissa    = 1ull; // minimal quiet NaN payload

        uint64_t storage = 0;
        storage |= (mantissa & getMantissaMask());
        storage |= (maxExponent << mantissaWidth_);
        storage |= (signBit << (bitWidth_ - 1u));

        setStorage(storage);
        return;
    }

    const bool sign = std::signbit(value) != 0;

    // Handle zero (preserve sign)
    if (value == 0.0)
    {
        resetToZero(sign);
        return;
    }

    // Handle infinities
    if (std::isinf(value))
    {
        const uint64_t signBit     = sign ? 1ull : 0ull;
        const uint64_t maxExponent = (expWidth_ == 0) ? 0 : ((1 << expWidth_) - 1ull);

        uint64_t storage = 0;
        storage |= (maxExponent << mantissaWidth_);
        storage |= (signBit << (bitWidth_ - 1u));

        setStorage(storage);
        return;
    }

    // Finite, non-zero
    const double absVal = std::fabs(value);

    // frexp: absVal = m * 2^e, m in [0.5, 1)
    int    e = 0;
    double m = std::frexp(absVal, &e);

    // Normalize to [1, 2)
    m *= 2.0;
    e -= 1;

    // m = 1 + fraction, fraction in [0, 1)
    const double  fraction = m - 1.0;
    const double  scale    = std::ldexp(1.0, mantissaWidth_); // 2^mantissaWidth_
    const double  scaled   = fraction * scale;
    const int64_t rounded  = static_cast<int64_t>(std::llround(scaled));

    const uint64_t maxMant = getMantissaMask();
    uint64_t       mantissa;

    // Handle rounding overflow (e.g. 0.11111... rounding up to 1.000...)
    if (std::cmp_greater(rounded, maxMant))
    {
        mantissa = 0;
        e += 1;
    }
    else
    {
        mantissa = static_cast<uint64_t>(rounded) & maxMant;
    }

    // Compute biased exponent
    if (expWidth_ == 0)
    {
        // Degenerate format: no exponent. Just store mantissa and sign, ignore scale.
        uint64_t signBit = sign ? 1ull : 0ull;
        uint64_t storage = 0;
        storage |= (mantissa & getMantissaMask());
        storage |= (signBit << (bitWidth_ - 1u));
        setStorage(storage);
        return;
    }

    const int32_t  bias        = (static_cast<int32_t>(1 << (expWidth_ - 1u)) - 1);
    int64_t        expField    = static_cast<int64_t>(e) + bias;
    const uint64_t maxExponent = (static_cast<uint64_t>(1) << expWidth_) - 1ull;
    const uint64_t signBit     = sign ? 1ull : 0ull;

    // Underflow into subnormal or zero
    if (expField <= 0)
    {
        // If it's way too small, flush to zero
        if (expField < -static_cast<int64_t>(mantissaWidth_))
        {
            resetToZero(sign);
            return;
        }

        // Subnormal: exponentField = 0, incorporate implicit leading 1 into mantissa
        const int shift = 1 - static_cast<int>(expField); // how much to shift right

        const uint64_t fullMant = (1 << mantissaWidth_) | mantissa; // leading 1
        if (shift >= static_cast<int>(mantissaWidth_ + 1))
        {
            mantissa = 0;
        }
        else
        {
            mantissa = fullMant >> shift;
        }

        expField = 0;
    }
    else if (std::cmp_greater_equal(expField, maxExponent))
    {
        // Overflow -> Inf
        uint64_t storage = 0;
        storage |= (maxExponent << mantissaWidth_);
        storage |= (signBit << (bitWidth_ - 1u));
        setStorage(storage);
        return;
    }

    // Normal case
    uint64_t storage = 0;
    storage |= (mantissa & getMantissaMask());
    storage |= (static_cast<uint64_t>(expField) << mantissaWidth_);
    storage |= (signBit << (bitWidth_ - 1u));

    setStorage(storage);
}

double ApFloat::toDouble() const
{
    const uint64_t storage      = getStorage();
    const uint64_t mantissaMask = getMantissaMask();
    const uint64_t exponentMask = getExponentMask();
    const uint64_t signMask     = getSignMask();

    const uint64_t mantissa = storage & mantissaMask;
    const uint64_t exponent = (storage & exponentMask) >> mantissaWidth_;
    const bool     sign     = (storage & signMask) != 0;

    if (expWidth_ == 0)
    {
        // No exponent, treat as fixed point in [0, 1)
        double frac = 0.0;
        if (mantissaWidth_ > 0)
        {
            double scale = std::ldexp(1.0, mantissaWidth_);
            frac         = static_cast<double>(mantissa) / scale;
        }
        return sign ? -frac : frac;
    }

    const uint64_t maxExponent = (1 << expWidth_) - 1ull;
    const int32_t  bias        = (static_cast<int32_t>(1 << (expWidth_ - 1u)) - 1);

    if (exponent == 0)
    {
        if (mantissa == 0)
        {
            // Signed zero
            return sign ? -0.0 : 0.0;
        }

        // Subnormal: exponent = 1 - bias, significand = 0.f
        const double scale = std::ldexp(1.0, mantissaWidth_);
        const double frac  = static_cast<double>(mantissa) / scale;
        const int    e     = 1 - bias;

        const double value = std::ldexp(frac, e);
        return sign ? -value : value;
    }

    if (exponent == maxExponent)
    {
        if (mantissa == 0)
            return sign ? -std::numeric_limits<double>::infinity() : std::numeric_limits<double>::infinity();
        return std::numeric_limits<double>::quiet_NaN();
    }

    // Normal: exponent in (0, maxExponent)
    const double scale = std::ldexp(1.0, mantissaWidth_);
    const double frac  = static_cast<double>(mantissa) / scale; // [0, 1)
    const double sig   = 1.0 + frac;                            // [1, 2)

    const int    e     = static_cast<int>(exponent) - bias;
    const double value = std::ldexp(sig, e);

    return sign ? -value : value;
}

bool ApFloat::equals(const ApFloat& other) const
{
    // If formats differ, not equal
    if (bitWidth_ != other.bitWidth_ ||
        expWidth_ != other.expWidth_ ||
        mantissaWidth_ != other.mantissaWidth_ ||
        numWords_ != other.numWords_)
    {
        return false;
    }

    // IEEE-like semantics: NaN is never equal (even to itself)
    if (isNaN() || other.isNaN())
        return false;

    for (uint8_t i = 0; i < numWords_; ++i)
    {
        if (words_[i] != other.words_[i])
            return false;
    }

    return true;
}

size_t ApFloat::hash() const
{
    auto h = std::hash<int>()(bitWidth_);
    h      = hash_combine(h, expWidth_);
    h      = hash_combine(h, mantissaWidth_);
    for (size_t i = 0; i < numWords_; ++i)
        h = hash_combine(h, words_[i]);
    return h;
}

SWC_END_NAMESPACE()
