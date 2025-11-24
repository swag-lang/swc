#include "pch.h"

#include "ApInt.h"
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
    bitWidth_(static_cast<uint32_t>(1u + expWidth + mantissaWidth)),
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
    std::fill_n(words_, numWords_, static_cast<size_t>(0));
}

uint64_t ApFloat::getStorage() const
{
    static_assert(WORD_BITS > 0 && WORD_BITS <= 64, "WORD_BITS must be in (0, 64].");
    constexpr uint64_t wordMask = (WORD_BITS == 64) ? std::numeric_limits<uint64_t>::max() : (std::numeric_limits<uint64_t>::max() >> (64 - WORD_BITS));

    uint64_t value = 0;
    for (uint8_t i = 0; i < numWords_; ++i)
    {
        const uint64_t w     = static_cast<uint64_t>(words_[i]) & wordMask;
        const uint32_t shift = static_cast<uint32_t>(i) * static_cast<uint32_t>(WORD_BITS);
        if (shift < 64u) // guard against undefined behavior if numWords_ > 64/WORD_BITS
            value |= (w << shift);
    }

    return value;
}

void ApFloat::setStorage(uint64_t value)
{
    static_assert(WORD_BITS > 0 && WORD_BITS <= 64, "WORD_BITS must be in (0, 64].");
    constexpr uint64_t wordMask = (WORD_BITS == 64) ? std::numeric_limits<uint64_t>::max() : (std::numeric_limits<uint64_t>::max() >> (64 - WORD_BITS));

    for (uint8_t i = 0; i < numWords_; ++i)
    {
        const uint32_t shift = static_cast<uint32_t>(i) * static_cast<uint32_t>(WORD_BITS);
        if (shift < 64u)
            words_[i] = static_cast<size_t>((value >> shift) & wordMask);
        else
            words_[i] = 0;
    }
    for (uint8_t i = numWords_; i < MAX_WORDS; ++i)
        words_[i] = 0;
}

uint64_t ApFloat::getMantissaMask() const
{
    if (mantissaWidth_ == 0)
        return 0;
    if (mantissaWidth_ >= 64)
        return std::numeric_limits<uint64_t>::max();
    return (uint64_t{1} << mantissaWidth_) - 1ull;
}

uint64_t ApFloat::getExponentMask() const
{
    if (expWidth_ == 0)
        return 0;
    if (expWidth_ >= 64)
        return std::numeric_limits<uint64_t>::max() & ~getMantissaMask();

    const uint64_t expBits = (uint64_t{1} << expWidth_) - 1ull;
    return (expBits << mantissaWidth_);
}

uint64_t ApFloat::getSignMask() const
{
    if (bitWidth_ == 0)
        return 0;

    // We assume bitWidth_ <= 64 here.
    SWC_ASSERT(bitWidth_ <= 64);
    return (uint64_t{1} << static_cast<uint32_t>(bitWidth_ - 1u));
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

    const uint64_t maxExponent = (expWidth_ == 0) ? 0 : ((uint64_t{1} << expWidth_) - 1ull);

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
        const uint64_t     maxExponent = (expWidth_ == 0) ? 0 : ((uint64_t{1} << expWidth_) - 1ull);
        constexpr uint64_t mantissa    = 1ull; // minimal quiet NaN payload

        uint64_t storage = 0;
        storage |= (mantissa & getMantissaMask());
        storage |= (maxExponent << mantissaWidth_);
        storage |= (signBit << (bitWidth_ - 1u));

        setStorage(storage);
        return;
    }

    const bool sign = (std::signbit(value) != 0);

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
        const uint64_t maxExponent = (expWidth_ == 0) ? 0 : ((uint64_t{1} << expWidth_) - 1ull);

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
    const double  scale    = std::ldexp(1.0, static_cast<int>(mantissaWidth_)); // 2^mantissaWidth_
    const double  scaled   = fraction * scale;
    const int64_t rounded  = static_cast<int64_t>(std::llround(scaled));

    const uint64_t maxMantissa = getMantissaMask();
    uint64_t       mantissa;

    // Handle rounding overflow (e.g., 0.11111... rounding up to 1.000...)
    if (std::cmp_greater(rounded, static_cast<int64_t>(maxMantissa)))
    {
        mantissa = 0;
        e += 1;
    }
    else
    {
        mantissa = static_cast<uint64_t>(rounded) & maxMantissa;
    }

    // Compute biased exponent
    if (expWidth_ == 0)
    {
        // Degenerate format: no exponent. Just store mantissa and sign, ignore scale.
        const uint64_t signBit = sign ? 1ull : 0ull;
        uint64_t       storage = 0;
        storage |= (mantissa & getMantissaMask());
        storage |= (signBit << (bitWidth_ - 1u));
        setStorage(storage);
        return;
    }

    const int32_t bias =
        static_cast<int32_t>((uint64_t{1} << (expWidth_ - 1u)) - 1ull);
    int64_t        expField    = static_cast<int64_t>(e) + static_cast<int64_t>(bias);
    const uint64_t maxExponent = (uint64_t{1} << expWidth_) - 1ull;
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

        const uint64_t fullMantissa = (uint64_t{1} << mantissaWidth_) | mantissa; // leading 1
        if (std::cmp_greater_equal(shift, mantissaWidth_ + 1u))
        {
            mantissa = 0;
        }
        else
        {
            mantissa = fullMantissa >> shift;
        }

        expField = 0;
    }
    else if (std::cmp_greater_equal(expField, static_cast<int64_t>(maxExponent)))
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
            const double scale = std::ldexp(1.0, static_cast<int>(mantissaWidth_));
            frac               = static_cast<double>(mantissa) / scale;
        }
        return sign ? -frac : frac;
    }

    const uint64_t maxExponent = (uint64_t{1} << expWidth_) - 1ull;
    const int32_t  bias        = static_cast<int32_t>((uint64_t{1} << (expWidth_ - 1u)) - 1ull);

    if (exponent == 0)
    {
        if (mantissa == 0)
        {
            // Signed zero
            return sign ? -0.0 : 0.0;
        }

        // Subnormal: exponent = 1 - bias, significand = 0.f
        const double scale = std::ldexp(1.0, static_cast<int>(mantissaWidth_));
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
    const double scale = std::ldexp(1.0, static_cast<int>(mantissaWidth_));
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

namespace
{
    void mulPow5(ApInt& apInt, uint32_t exp, bool& overflow)
    {
        for (uint32_t i = 0; i < exp; ++i)
        {
            apInt.mul(5u, overflow);
            if (overflow)
                return;
        }
    }
}

void ApFloat::fromDecimal(const ApInt& decimalSig, int64_t decimalExp10, bool& overflow)
{
    overflow = false;

    // 1) Zero shortcut
    if (decimalSig.isZero())
    {
        resetToZero(false);
        return;
    }

    // Assume positive literal here; sign handled outside via unary '-'
    const bool negative = false;

    const uint32_t mantissaBits = mantissaWidth_;   // e.g. 52
    const uint32_t expBits      = expWidth_;

    // We only support IEEE-like formats with an exponent field.
    SWC_ASSERT(expBits > 0 && expBits <= 31);

    // We will pack at most (mantissaBits + 1 + guardBits) bits into a 64-bit integer.
    // guardBits = 2, so require mantissaBits <= 61.
    SWC_ASSERT(mantissaBits + 3u <= 64u);

    const uint32_t precision = mantissaBits + 1u; // include hidden 1

    const int32_t expBias =
        static_cast<int32_t>((uint32_t(1) << (expBits - 1u)) - 1u);

    // 2) Build an integer N and a binary exponent exp2 such that:
    //      V ≈ N * 2^exp2
    //
    // Adjust by 10^decimalExp10 = 2^k * 5^k (or its reciprocal).

    ApInt n = decimalSig; // copy
    n.setNegative(false); // magnitude only

    int64_t exp2 = 0;

    bool bigOver         = false;
    bool fracLostFromDiv = false; // track fractional loss from /5

    if (decimalExp10 > 0)
    {
        // Multiply by 10^k = 2^k * 5^k
        mulPow5(n, static_cast<uint32_t>(decimalExp10), bigOver);
        if (bigOver)
        {
            // Overflow during integer scaling -> +INF
            overflow = true;
            const uint64_t signField    = negative ? getSignMask() : 0u;
            const uint64_t exponentAll  = getExponentMask(); // all exponent bits = 1, mantissa = 0
            const uint64_t infBits      = signField | exponentAll;
            setStorage(infBits);
            return;
        }
        exp2 += decimalExp10;
    }
    else if (decimalExp10 < 0)
    {
        // Divide by 10^(-k) = 2^(-k) * 5^(-k).
        const uint32_t k = static_cast<uint32_t>(-decimalExp10);
        for (uint32_t i = 0; i < k; ++i)
        {
            const uint32_t rem = n.div(5u);
            if (rem != 0)
            {
                // We lost some fraction in decimal; remember this for rounding.
                fracLostFromDiv = true;
            }
        }
        // Account for 2^(-k) in the binary exponent.
        exp2 -= k;
    }

    // 3) Find the position of the highest set bit of N (floor(log2(N)))
    int32_t msbIndex = -1;
    for (int i = static_cast<int>(n.getBitWidth()) - 1; i >= 0; --i)
    {
        if (n.testBit(static_cast<size_t>(i)))
        {
            msbIndex = i;
            break;
        }
    }

    SWC_ASSERT(msbIndex >= 0);

    // Value is approximately N * 2^exp2, with msbIndex the top bit of N.
    // Unbiased exponent:
    //   E = msbIndex + exp2
    int64_t e = static_cast<int64_t>(msbIndex) + exp2;

    // 4) Build a scaled mantissa with a couple of guard bits for rounding.
    //
    // We want (precision + guardBits) bits at the top of 'scaled'.
    constexpr uint32_t guardBits  = 2;
    const uint32_t     targetBits = precision + guardBits;
    const int32_t      shiftForMsb =
        msbIndex - static_cast<int32_t>(targetBits - 1u);

    ApInt scaled = n; // copy

    // Track bits we lose if we shift right (sticky for rounding)
    bool stickyFromShift = false;
    if (shiftForMsb > 0)
    {
        const int maxBit =
            std::min<int>(shiftForMsb, static_cast<int>(n.getBitWidth()));
        for (int i = 0; i < maxBit; ++i)
        {
            if (n.testBit(static_cast<size_t>(i)))
            {
                stickyFromShift = true;
                break;
            }
        }
    }

    if (shiftForMsb > 0)
    {
        // Shift right: lose bits that we already accounted for in stickyFromShift.
        scaled.logicalShiftRight(static_cast<size_t>(shiftForMsb));
    }
    else if (shiftForMsb < 0)
    {
        bool over = false;
        scaled.logicalShiftLeft(static_cast<size_t>(-shiftForMsb), over);
        if (over)
        {
            // If we overflow here, it's effectively an exponent increase.
            // For simplicity, treat as overflow to +INF.
            overflow = true;
            const uint64_t signField   = negative ? getSignMask() : 0u;
            const uint64_t exponentAll = getExponentMask();
            const uint64_t infBits     = signField | exponentAll;
            setStorage(infBits);
            return;
        }
    }

    // Adjust exponent by any right shift of the integer.
    e += shiftForMsb;

    // Extract the scaled value into a 64-bit integer.
    SWC_ASSERT(scaled.getBitWidth() <= 64);
    const uint64_t mWithGuards = static_cast<uint64_t>(scaled.toNative());

    // Overall sticky: from decimal /5 loss + from integer right shift.
    const bool sticky = fracLostFromDiv || stickyFromShift;

    // 5) Round to 'precision' bits (mantissa+1) using guard bits.
    //
    // Layout in mWithGuards (from MSB):
    //   [precision bits][guard][round]
    //
    // We'll keep 'precision' bits and look at guard+round+sticky.

    const uint64_t maskPrecision =
        (precision >= 64)
            ? ~static_cast<uint64_t>(0)
            : ((static_cast<uint64_t>(1) << precision) - 1u);

    uint64_t       mainBits  = (mWithGuards >> guardBits) & maskPrecision;
    const uint64_t roundBits = mWithGuards & ((static_cast<uint64_t>(1) << guardBits) - 1u);

    const bool guardBit = (roundBits >> (guardBits - 1u)) & 1u;
    const bool roundBit = (roundBits >> (guardBits - 2u)) & 1u; // guardBits == 2

    const uint64_t lowerMask =
        (guardBits > 1u)
            ? ((static_cast<uint64_t>(1) << (guardBits - 2u)) - 1u)
            : 0u;
    const bool anyTail = sticky || ((roundBits & lowerMask) != 0);

    // Round-to-nearest, ties-to-even:
    bool increment = false;
    if (guardBit)
    {
        if (roundBit || anyTail || (mainBits & 1u))
            increment = true;
    }

    if (increment)
    {
        mainBits += 1u;
        // If mantissa overflowed (1.111..1 + ulp = 10.000..0),
        // renormalize and bump exponent.
        if (mainBits >> precision)
        {
            mainBits >>= 1;
            e += 1;
        }
    }

    // 6) Handle exponent range.
    //
    // For expBits bits in the exponent field:
    //   biased exponent range: 0 .. (2^expBits - 1)
    //   0  -> zero/subnormal
    //   max -> INF/NaN
    //   finite normals use 1 .. max-1
    //
    // So the largest finite biased exponent is (2^expBits - 2).
    const uint64_t maxBiased = (static_cast<uint64_t>(1) << expBits) - 1u;
    const int64_t  maxFiniteBiasedExp = static_cast<int64_t>(maxBiased - 1u); // 2^expBits - 2

    const int64_t unbiasedE = e;
    const int64_t biasedE   = unbiasedE + expBias;

    if (biasedE > maxFiniteBiasedExp)
    {
        // Overflow to +INF
        overflow = true;
        const uint64_t signField   = negative ? getSignMask() : 0u;
        const uint64_t exponentAll = getExponentMask();
        const uint64_t infBits     = signField | exponentAll;
        setStorage(infBits);
        return;
    }

    if (biasedE <= 0)
    {
        // Underflow to zero or subnormal.
        // Current implementation: flush to signed zero (no subnormals).
        resetToZero(negative);
        return;
    }

    // 7) Normal number.
    const uint64_t storedMantissaMask =
        (mantissaBits == 64)
            ? ~static_cast<uint64_t>(0)
            : ((static_cast<uint64_t>(1) << mantissaBits) - 1u);

    const uint64_t storedMantissa = mainBits & storedMantissaMask;
    const uint64_t storedExponent = static_cast<uint64_t>(biasedE);

    const uint64_t signField     = negative ? getSignMask() : 0u;
    const uint64_t exponentField = (storedExponent << mantissaBits) & getExponentMask();
    const uint64_t mantissaField = storedMantissa & getMantissaMask();

    const uint64_t finalBits = signField | exponentField | mantissaField;
    setStorage(finalBits);
}


SWC_END_NAMESPACE()
