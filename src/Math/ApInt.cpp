#include "pch.h"
#include "Math/ApInt.h"
#include "Math/Hash.h"
#include "Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

ApInt::ApInt() :
    ApInt(MAX_BITS)
{
}

ApInt::ApInt(uint32_t bitWidth) :
    bitWidth_(bitWidth),
    numWords_(computeNumWords(bitWidth))
{
    SWC_ASSERT(bitWidth <= MAX_BITS);
    clearWords();
    normalize();
}

ApInt::ApInt(uint64_t value, uint32_t bitWidth) :
    bitWidth_(bitWidth),
    numWords_(computeNumWords(bitWidth))
{
    SWC_ASSERT(bitWidth <= MAX_BITS);
    clearWords();
    words_[0] = value;
    normalize();
}

ApInt::ApInt(const void* data, uint32_t sizeInBytes, uint32_t bitWidth) :
    bitWidth_(bitWidth),
    numWords_(computeNumWords(bitWidth))
{
    SWC_ASSERT(bitWidth <= MAX_BITS);
    clearWords();
    memcpy(words_, data, std::min(sizeInBytes, static_cast<uint32_t>(sizeof(words_))));
    normalize();
}

uint64_t ApInt::as64() const
{
    const uint32_t maxBits   = std::min<uint32_t>(bitWidth_, 64);
    const uint32_t wordCount = (maxBits + WORD_BITS - 1) / WORD_BITS;

    uint64_t result = 0;

    // Copy low bits from ApInt.
    for (uint32_t i = 0; i < wordCount; ++i)
    {
        uint64_t       w        = words_[i];
        const uint32_t bitIndex = i * WORD_BITS;

        if (bitIndex + WORD_BITS > maxBits)
        {
            const uint32_t validBits = maxBits - bitIndex;
            if (validBits < WORD_BITS)
            {
                const uint64_t mask = (uint64_t{1} << validBits) - 1;
                w &= mask;
            }
        }

        result |= (w << bitIndex);
    }

    return result;
}

int64_t ApInt::as64Signed() const
{
    uint64_t result = as64();

    if (isNegative() && bitWidth_ < 64)
    {
        const uint32_t signBitIndex = bitWidth_ - 1;
        const uint64_t lowMask      = (uint64_t{1} << (signBitIndex + 1)) - 1;
        const uint64_t highMask     = ~lowMask;
        result |= highMask;
    }

    return std::bit_cast<int64_t>(result);
}

bool ApInt::same(const ApInt& other) const
{
    if (bitWidth_ != other.bitWidth_)
        return false;
    SWC_ASSERT(numWords_ == other.numWords_);
    return std::equal(words_, words_ + numWords_, other.words_);
}

int ApInt::compare(const ApInt& other) const
{
    SWC_ASSERT(bitWidth_ == other.bitWidth_);
    SWC_ASSERT(numWords_ == other.numWords_);

    for (int i = static_cast<int>(numWords_) - 1; i >= 0; --i)
    {
        const uint64_t a = words_[static_cast<uint32_t>(i)];
        const uint64_t b = other.words_[static_cast<uint32_t>(i)];
        if (a < b)
            return -1;
        if (a > b)
            return 1;
    }

    return 0;
}

uint32_t ApInt::hash() const
{
    uint32_t h = Math::hash(bitWidth_);
    for (uint32_t i = 0; i < numWords_; ++i)
        h = Math::hashCombine(h, words_[i]);
    return h;
}

bool ApInt::isZero() const
{
    return std::all_of(words_, words_ + numWords_, [](uint64_t w) { return w == 0; });
}

void ApInt::setZero()
{
    clearWords();
}

void ApInt::logicalShiftLeft(uint64_t amount, bool& overflow)
{
    overflow = false;

    if (amount == 0)
        return;

    if (amount >= bitWidth_)
    {
        overflow = !isZero();
        setZero();
        return;
    }

    const uint64_t wordShift = amount / WORD_BITS;
    const uint64_t bitShift  = amount % WORD_BITS;

    if (wordShift > 0)
    {
        // Any bits shifted out of range?
        for (uint64_t i = numWords_ - wordShift; i < numWords_; ++i)
        {
            if (words_[i] != 0)
            {
                overflow = true;
                break;
            }
        }

        for (uint64_t i = numWords_; i-- > wordShift;)
            words_[i] = words_[i - wordShift];
        for (uint64_t i = 0; i < wordShift; ++i)
            words_[i] = 0;
    }

    if (bitShift > 0)
    {
        uint64_t carry = 0;
        for (uint64_t i = 0; i < numWords_; ++i)
        {
            const uint64_t newCarry = words_[i] >> (WORD_BITS - bitShift);
            words_[i]               = (words_[i] << bitShift) | carry;
            carry                   = newCarry;
        }

        if (carry != 0)
            overflow = true;
    }

    // IMPORTANT: for non-multiple-of-64 widths, shifting can spill into unused
    // bits of the last word. Flag overflow BEFORE normalize masks them away.
    if (hasTopBitsOverflow())
        overflow = true;

    normalize();
}

void ApInt::logicalShiftRight(uint64_t amount)
{
    if (amount == 0 || isZero())
        return;

    const uint64_t wordShift = amount / WORD_BITS;
    const uint64_t bitShift  = amount % WORD_BITS;

    if (wordShift >= numWords_)
    {
        setZero();
        return;
    }

    if (wordShift > 0)
    {
        for (uint32_t i = 0; i < numWords_ - static_cast<uint32_t>(wordShift); ++i)
            words_[i] = words_[i + wordShift];
        for (uint32_t i = static_cast<uint32_t>(numWords_ - wordShift); i < numWords_; ++i)
            words_[i] = 0;
    }

    if (bitShift > 0)
    {
        uint64_t carry = 0;
        for (int i = static_cast<int>(numWords_) - 1; i >= 0; --i)
        {
            const uint64_t newCarry = words_[i] << (WORD_BITS - bitShift);
            words_[i]               = (words_[i] >> bitShift) | carry;
            carry                   = newCarry;
        }
    }

    normalize();
}

void ApInt::arithmeticShiftRight(uint64_t amount)
{
    if (amount == 0)
        return;

    const bool sign = isSignBitSet();

    // Shift by >= width: the result is 0 for non-negative, -1 for negative.
    if (amount >= bitWidth_)
    {
        if (sign)
            setAllBits();
        else
            setZero();
        return;
    }

    // Non-negative: same as logical shift.
    if (!sign)
    {
        logicalShiftRight(amount);
        return;
    }

    const uint64_t wordShift = amount / WORD_BITS;
    const uint64_t bitShift  = amount % WORD_BITS;

    // Whole-word shift down, fill the top with all-ones (sign extension).
    if (wordShift > 0)
    {
        if (wordShift >= numWords_)
        {
            setAllBits();
            return;
        }

        const uint32_t ws = static_cast<uint32_t>(wordShift);

        for (uint32_t i = 0; i < numWords_ - ws; ++i)
            words_[i] = words_[i + ws];

        for (uint32_t i = numWords_ - ws; i < numWords_; ++i)
            words_[i] = ~0ull;
    }

    // Intra-word shift with sign-fill into the top word.
    if (bitShift > 0)
    {
        // How many bits are actually used in the top word?
        uint32_t topUsed = bitWidth_ % WORD_BITS;
        if (topUsed == 0)
            topUsed = WORD_BITS;

        // Insert ones into the highest 'bitShift' bits of the *used* region of the top word.
        uint64_t carry;
        if (topUsed == 64)
        {
            carry = ~0ull << (64 - bitShift);
        }
        else
        {
            // safe because amount < bitWidth_ => bitShift <= topUsed
            carry = ((uint64_t{1} << bitShift) - 1) << (topUsed - bitShift);
        }

        for (int i = static_cast<int>(numWords_) - 1; i >= 0; --i)
        {
            const uint64_t newCarry = words_[static_cast<uint32_t>(i)] << (WORD_BITS - bitShift);
            words_[static_cast<uint32_t>(i)] =
                (words_[static_cast<uint32_t>(i)] >> bitShift) | carry;
            carry = newCarry;
        }
    }

    normalize();
}

void ApInt::add(uint64_t v, bool& overflow)
{
    SWC_ASSERT(numWords_);
    overflow = false;

    if (v == 0)
        return;

    uint64_t carry = v;
    for (uint64_t i = 0; i < numWords_; ++i)
    {
        const uint64_t oldWord  = words_[i];
        const uint64_t sum      = oldWord + carry;
        const uint64_t newCarry = (sum < oldWord) ? 1 : 0;
        words_[i]               = sum;
        carry                   = newCarry;
    }

    overflow = carry != 0 || hasTopBitsOverflow();
    normalize();
}

void ApInt::mul(uint64_t v, bool& overflow)
{
    SWC_ASSERT(numWords_);
    overflow = false;

    if (v == 0)
    {
        setZero();
        return;
    }

    uint64_t carry = 0;
    for (uint64_t i = 0; i < numWords_; ++i)
    {
        uint64_t low  = 0;
        uint64_t high = 0;

        Math::mul64X64(words_[i], v, low, high);
        low += carry;
        if (low < carry)
            ++high;

        words_[i] = low;
        carry     = high;
    }

    overflow = carry != 0 || hasTopBitsOverflow();
    normalize();
}

uint64_t ApInt::div(uint64_t v)
{
    SWC_ASSERT(v != 0);

    if (isZero())
        return 0;

    uint64_t rem = 0;

    for (int i = static_cast<int>(numWords_) - 1; i >= 0; --i)
    {
        uint64_t qWord = 0;
        Math::div128X64(rem, words_[i], v, qWord, rem);
        words_[i] = qWord;
    }

    normalize();
    return rem;
}

void ApInt::add(const ApInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    SWC_ASSERT(numWords_ == rhs.numWords_);

    overflow       = false;
    uint64_t carry = 0;

    for (uint32_t i = 0; i < numWords_; ++i)
    {
        const uint64_t a = words_[i];
        const uint64_t b = rhs.words_[i];

        const uint64_t sum1   = a + b;
        const uint64_t carry1 = (sum1 < a);

        const uint64_t sum2   = sum1 + carry;
        const uint64_t carry2 = (sum2 < sum1);

        words_[i] = sum2;
        carry     = carry1 | carry2;
    }

    overflow = (carry != 0) || hasTopBitsOverflow();
    normalize();
}

void ApInt::sub(const ApInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    SWC_ASSERT(numWords_ == rhs.numWords_);

    overflow        = false;
    uint64_t borrow = 0;

    for (uint32_t i = 0; i < numWords_; ++i)
    {
        const uint64_t a = words_[i];
        const uint64_t b = rhs.words_[i];
        const uint64_t t = b + borrow;

        const uint64_t result = a - t;
        borrow                = (a < t);

        words_[i] = result;
    }

    overflow = (borrow != 0);
    normalize();
}

void ApInt::mul(const ApInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    SWC_ASSERT(numWords_ == rhs.numWords_);

    const uint32_t n = numWords_;
    overflow         = false;

    SWC_ASSERT(2 * n <= 2 * static_cast<uint32_t>(MAX_WORDS));
    uint64_t tmp[2 * MAX_WORDS] = {};

    for (uint32_t i = 0; i < n; ++i)
    {
        uint64_t carry = 0;

        for (uint32_t j = 0; j < n; ++j)
        {
            uint64_t low = 0, high = 0;
            Math::mul64X64(words_[i], rhs.words_[j], low, high);

            const uint64_t old = tmp[i + j];
            uint64_t       sum = old + low;
            const uint64_t c1  = (sum < old);
            sum += carry;
            const uint64_t c2 = (sum < carry);
            tmp[i + j]        = sum;
            carry             = high + c1 + c2;
        }

        // Propagate carry correctly across tmp[i+n] (tmp limb can overflow)
        uint32_t k = i + n;
        uint64_t c = carry;
        while (c != 0 && k < 2 * MAX_WORDS)
        {
            const uint64_t old = tmp[k];
            tmp[k] += c;
            c = (tmp[k] < old) ? 1 : 0;
            ++k;
        }

        // If we ran out of space (shouldn't with sizing), treat as overflow.
        if (c != 0)
            overflow = true;
    }

    for (uint32_t i = 0; i < n; ++i)
        words_[i] = tmp[i];

    for (uint32_t i = n; i < 2 * n; ++i)
        if (tmp[i] != 0)
            overflow = true;

    if (hasTopBitsOverflow())
        overflow = true;

    normalize();
}

ApInt ApInt::div(const ApInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    SWC_ASSERT(!rhs.isZero());

    // Fast path: divisor fits in 64 -> remainder fits 64, but we still return full ApInt.
    if (rhs.fit64())
    {
        const uint64_t rem64 = div(rhs.as64());
        ApInt          rem(bitWidth_);
        rem.setZero();
        rem.words_[0] = rem64;
        rem.normalize();
        return rem;
    }

    const uint32_t totalBits = bitWidth_;

    ApInt rem(bitWidth_);
    rem.setZero();

    const ApInt divisor(rhs);
    ApInt       quotient(bitWidth_);
    quotient.setZero();

    for (int bit = static_cast<int>(totalBits) - 1; bit >= 0; --bit)
    {
        rem.logicalShiftLeft(1, overflow);
        if (overflow)
            return ApInt(bitWidth_);

        if (testBit(static_cast<uint64_t>(bit)))
            rem.words_[0] |= 1;

        if (!rem.ult(divisor))
        {
            rem.sub(divisor, overflow);
            if (overflow)
                return ApInt(bitWidth_);
            quotient.setBit(static_cast<uint64_t>(bit));
        }
    }

    *this = quotient;
    rem.normalize();
    return rem;
}

void ApInt::mod(const ApInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    SWC_ASSERT(!rhs.isZero());

    // div(rhs) overwrites *this with quotient, returns the remainder.
    const ApInt rem = div(rhs, overflow);

    // Install the remainder back into *this.
    *this = rem;
}

void ApInt::modSigned(const ApInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    SWC_ASSERT(!rhs.isZero());

    // divSigned overwrites *this with quotient and returns the signed remainder as ApInt.
    const ApInt signedRem = divSigned(rhs, overflow);

    // On signed overflow (min / -1), we define the remainder as 0 and signal overflow.
    if (overflow)
    {
        setZero();
        return;
    }

    *this = signedRem;
}

void ApInt::addSigned(const ApInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);

    const bool lhsNeg = isNegative();
    const bool rhsNeg = rhs.isNegative();

    bool unsignedOverflow = false;
    add(rhs, unsignedOverflow);

    const bool resNeg = isNegative();
    overflow          = (lhsNeg == rhsNeg) && (resNeg != lhsNeg);
}

void ApInt::subSigned(const ApInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);

    const bool lhsNeg = isNegative();
    const bool rhsNeg = rhs.isNegative();

    bool unsignedOverflow = false;
    sub(rhs, unsignedOverflow);

    const bool resNeg = isNegative();
    overflow          = (lhsNeg != rhsNeg) && (resNeg != lhsNeg);
}

void ApInt::clearWords()
{
    std::fill_n(words_, numWords_, ZERO);
}

uint32_t ApInt::computeNumWords(uint32_t bitWidth)
{
    SWC_ASSERT(bitWidth > 0 && bitWidth <= MAX_BITS);
    return static_cast<uint32_t>((bitWidth + WORD_BITS - 1) / WORD_BITS);
}

void ApInt::normalize()
{
    const uint64_t usedBitsInLastWord = bitWidth_ % WORD_BITS;
    if (usedBitsInLastWord != 0)
    {
        const uint64_t mask = (ONE << usedBitsInLastWord) - 1;
        words_[numWords_ - 1] &= mask;
    }
}

bool ApInt::hasTopBitsOverflow() const
{
    SWC_ASSERT(numWords_ && bitWidth_);

    const uint64_t usedBitsInLastWord = bitWidth_ % WORD_BITS;
    if (usedBitsInLastWord == 0)
        return false;

    const uint64_t mask = (ONE << usedBitsInLastWord) - 1;
    const uint64_t last = words_[numWords_ - 1];
    return (last & ~mask) != 0;
}

namespace
{
    void makeMagnitude(ApInt& v, bool isNeg)
    {
        if (!isNeg)
            return;

        v.invertAllBits();
        bool dummyOverflow = false;
        v.add(1, dummyOverflow);
    }

    ApInt makeMinValue(uint32_t bitWidth)
    {
        if (!bitWidth)
            bitWidth = ApInt::maxBitWidth();

        ApInt result(bitWidth);
        result.setZero();
        return result;
    }

    ApInt makeMinSignedValue(uint32_t bitWidth)
    {
        if (!bitWidth)
            bitWidth = ApInt::maxBitWidth();

        ApInt result(bitWidth);
        result.setZero();
        result.setBit(bitWidth - 1);
        return result;
    }

    ApInt makeMaxValue(uint32_t bitWidth)
    {
        if (!bitWidth)
            bitWidth = ApInt::maxBitWidth();

        ApInt result(bitWidth);
        result.setAllBits();
        return result;
    }

    ApInt makeMaxSignedValue(uint32_t bitWidth)
    {
        if (!bitWidth)
            bitWidth = ApInt::maxBitWidth();

        ApInt result(bitWidth);
        result.setAllBits();
        result.clearBit(bitWidth - 1);
        return result;
    }
}

void ApInt::mulSigned(const ApInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);

    const uint32_t w = bitWidth_;
    SWC_ASSERT(w > 0);

    const bool lhsNeg    = isNegative();
    const bool rhsNeg    = rhs.isNegative();
    const bool resultNeg = lhsNeg ^ rhsNeg;

    ApInt magLhs = *this;
    ApInt magRhs = rhs;

    makeMagnitude(magLhs, lhsNeg);
    makeMagnitude(magRhs, rhsNeg);

    bool unsignedOverflow = false;
    magLhs.mul(magRhs, unsignedOverflow);

    overflow = false;

    const ApInt limitPos = maxValueSigned(w);
    const ApInt limitNeg = minValueSigned(w);

    if (!resultNeg)
    {
        if (unsignedOverflow || magLhs.ugt(limitPos))
            overflow = true;
    }
    else
    {
        // magnitude must be <= |minSigned|, which equals minSigned in unsigned space (only top bit set).
        if (unsignedOverflow || magLhs.ugt(limitNeg))
            overflow = true;
    }

    if (resultNeg)
    {
        ApInt negProd = magLhs;
        negProd.invertAllBits();
        bool dummyOverflow = false;
        negProd.add(1, dummyOverflow);
        *this = negProd;
    }
    else
    {
        *this = magLhs;
    }
}

// Return value is signed remainder (same sign as dividend), as a full ApInt.
// overflow is set for the single true signed overflow case: minSigned / -1.
ApInt ApInt::divSigned(const ApInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    SWC_ASSERT(!rhs.isZero());

    overflow = false;

    const bool lhsNeg    = isNegative();
    const bool rhsNeg    = rhs.isNegative();
    const bool resultNeg = lhsNeg ^ rhsNeg;

    const ApInt minVal = minValueSigned(bitWidth_);

    ApInt negOne(bitWidth_);
    negOne.setAllBits();

    if (same(minVal) && rhs.same(negOne))
    {
        overflow = true;
        return ApInt(bitWidth_);
    }

    ApInt magLhs = *this;
    ApInt magRhs = rhs;

    makeMagnitude(magLhs, lhsNeg);
    makeMagnitude(magRhs, rhsNeg);

    // Divide magnitudes (unsigned). This overwrites magLhs with quotient and returns remainder.
    ApInt remMag = magLhs.div(magRhs, overflow);
    if (overflow)
        return ApInt(bitWidth_);

    // Apply sign to quotient.
    if (resultNeg)
    {
        magLhs.invertAllBits();
        bool dummyOverflow = false;
        magLhs.add(1, dummyOverflow);
    }
    *this = magLhs;

    // Apply sign to remainder: the signed remainder has the same sign as dividend (lhs).
    if (!remMag.isZero() && lhsNeg)
    {
        remMag.invertAllBits();
        bool dummyOverflow = false;
        remMag.add(1, dummyOverflow);
    }

    remMag.normalize();
    return remMag;
}

void ApInt::bitwiseOr(uint64_t rhs)
{
    SWC_ASSERT(numWords_ && bitWidth_);
    if (rhs == 0)
        return;

    if (bitWidth_ < WORD_BITS)
    {
        const uint64_t mask = (ONE << bitWidth_) - 1;
        rhs &= mask;
    }

    words_[0] |= rhs;
    normalize();
}

void ApInt::bitwiseOr(const ApInt& rhs)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    SWC_ASSERT(numWords_ == rhs.numWords_);

    for (uint32_t i = 0; i < numWords_; ++i)
        words_[i] |= rhs.words_[i];

    normalize();
}

void ApInt::bitwiseAnd(const ApInt& rhs)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    SWC_ASSERT(numWords_ == rhs.numWords_);

    for (uint32_t i = 0; i < numWords_; ++i)
        words_[i] &= rhs.words_[i];

    normalize();
}

void ApInt::bitwiseXor(const ApInt& rhs)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    SWC_ASSERT(numWords_ == rhs.numWords_);

    for (uint32_t i = 0; i < numWords_; ++i)
        words_[i] ^= rhs.words_[i];

    normalize();
}

bool ApInt::testBit(uint64_t bitIndex) const
{
    SWC_ASSERT(bitIndex < bitWidth_);
    const uint64_t wordIndex = bitIndex / WORD_BITS;
    const uint64_t bitInWord = bitIndex % WORD_BITS;
    SWC_ASSERT(wordIndex < numWords_);
    return (words_[wordIndex] >> bitInWord) & 1;
}

void ApInt::setBit(uint64_t bitIndex)
{
    SWC_ASSERT(bitIndex < bitWidth_);
    const uint64_t wordIndex = bitIndex / WORD_BITS;
    const uint64_t bitInWord = bitIndex % WORD_BITS;
    SWC_ASSERT(wordIndex < numWords_);
    words_[wordIndex] |= (ONE << bitInWord);
}

void ApInt::setAllBits()
{
    std::fill_n(words_, numWords_, ~ZERO);
    normalize();
}

void ApInt::invertAllBits()
{
    for (uint32_t i = 0; i < numWords_; ++i)
        words_[i] = ~words_[i];
    normalize();
}

void ApInt::clearBit(uint64_t bitIndex)
{
    SWC_ASSERT(bitIndex < bitWidth_);
    const uint64_t wordIndex = bitIndex / WORD_BITS;
    const uint64_t bitInWord = bitIndex % WORD_BITS;
    SWC_ASSERT(wordIndex < numWords_);
    words_[wordIndex] &= ~(ONE << bitInWord);
}

bool ApInt::isSignBitSet() const
{
    SWC_ASSERT(bitWidth_ > 0);
    const uint64_t msb = bitWidth_ - 1;
    return testBit(msb);
}

bool ApInt::isSignBitClear() const
{
    return !isSignBitSet();
}

bool ApInt::isNegative() const
{
    return isSignBitSet();
}

bool ApInt::isNonNegative() const
{
    return !isSignBitSet();
}

bool ApInt::isStrictlyPositive() const
{
    return isNonNegative() && !isZero();
}

bool ApInt::isNonPositive() const
{
    return isNegative() || isZero();
}

uint64_t ApInt::getSignBit() const
{
    return isSignBitSet() ? ONE : ZERO;
}

void ApInt::setSignBit(bool isNegative)
{
    const uint64_t signIndex = bitWidth_ - 1;
    if (isNegative)
        setBit(signIndex);
    else
        clearBit(signIndex);
}

ApInt ApInt::minValue(uint32_t bitWidth)
{
    static const ApInt U8   = makeMinValue(8);
    static const ApInt U16  = makeMinValue(16);
    static const ApInt U32  = makeMinValue(32);
    static const ApInt U64  = makeMinValue(64);
    static const ApInt U128 = makeMinValue(128);

    switch (bitWidth)
    {
        case 8: return U8;
        case 16: return U16;
        case 32: return U32;
        case 64: return U64;
        case 128: return U128;
        default: return makeMinValue(bitWidth);
    }
}

ApInt ApInt::minValueSigned(uint32_t bitWidth)
{
    static const ApInt S8   = makeMinSignedValue(8);
    static const ApInt S16  = makeMinSignedValue(16);
    static const ApInt S32  = makeMinSignedValue(32);
    static const ApInt S64  = makeMinSignedValue(64);
    static const ApInt S128 = makeMinSignedValue(128);

    switch (bitWidth)
    {
        case 8: return S8;
        case 16: return S16;
        case 32: return S32;
        case 64: return S64;
        case 128: return S128;
        default: return makeMinSignedValue(bitWidth);
    }
}

ApInt ApInt::maxValue(uint32_t bitWidth)
{
    static const ApInt U8   = makeMaxValue(8);
    static const ApInt U16  = makeMaxValue(16);
    static const ApInt U32  = makeMaxValue(32);
    static const ApInt U64  = makeMaxValue(64);
    static const ApInt U128 = makeMaxValue(128);

    switch (bitWidth)
    {
        case 8: return U8;
        case 16: return U16;
        case 32: return U32;
        case 64: return U64;
        case 0: [[fallthrough]];
        case 128: return U128;
        default: return makeMaxValue(bitWidth);
    }
}

ApInt ApInt::maxValueSigned(uint32_t bitWidth)
{
    static const ApInt S8   = makeMaxSignedValue(8);
    static const ApInt S16  = makeMaxSignedValue(16);
    static const ApInt S32  = makeMaxSignedValue(32);
    static const ApInt S64  = makeMaxSignedValue(64);
    static const ApInt S128 = makeMaxSignedValue(128);

    switch (bitWidth)
    {
        case 8: return S8;
        case 16: return S16;
        case 32: return S32;
        case 64: return S64;
        case 0: [[fallthrough]];
        case 128: return S128;
        default: return makeMaxSignedValue(bitWidth);
    }
}

bool ApInt::eq(const ApInt& rhs) const
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    return same(rhs);
}

bool ApInt::ne(const ApInt& rhs) const
{
    return !eq(rhs);
}

bool ApInt::ult(const ApInt& rhs) const
{
    return compare(rhs) < 0;
}

bool ApInt::ule(const ApInt& rhs) const
{
    return !rhs.ult(*this);
}

bool ApInt::ugt(const ApInt& rhs) const
{
    return rhs.ult(*this);
}

bool ApInt::uge(const ApInt& rhs) const
{
    return !ult(rhs);
}

bool ApInt::slt(const ApInt& rhs) const
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    const bool lhsNeg = isNegative();
    const bool rhsNeg = rhs.isNegative();
    if (lhsNeg != rhsNeg)
        return lhsNeg;
    return compare(rhs) < 0;
}

bool ApInt::sle(const ApInt& rhs) const
{
    return !rhs.slt(*this);
}

bool ApInt::sgt(const ApInt& rhs) const
{
    return rhs.slt(*this);
}

bool ApInt::sge(const ApInt& rhs) const
{
    return !slt(rhs);
}

void ApInt::shrink(uint32_t newBitWidth)
{
    SWC_ASSERT(newBitWidth > 0);
    SWC_ASSERT(newBitWidth <= bitWidth_);

    if (newBitWidth == bitWidth_)
        return;

    const uint32_t newNumWords = computeNumWords(newBitWidth);

    bitWidth_ = newBitWidth;
    numWords_ = newNumWords;

    normalize();
}

void ApInt::resize(uint32_t newBitWidth)
{
    SWC_ASSERT(newBitWidth > 0);

    if (newBitWidth == bitWidth_)
        return;

    const uint32_t oldBitWidth = bitWidth_;
    const uint32_t oldNumWords = numWords_;
    const uint32_t newNumWords = computeNumWords(newBitWidth);

    if (newBitWidth < oldBitWidth)
    {
        shrink(newBitWidth);
        return;
    }

    if (newNumWords > oldNumWords)
        std::fill(words_ + oldNumWords, words_ + newNumWords, ZERO);

    bitWidth_ = newBitWidth;
    numWords_ = newNumWords;

    normalize();
}

void ApInt::resizeSigned(uint32_t newBitWidth)
{
    SWC_ASSERT(newBitWidth > 0);

    if (newBitWidth == bitWidth_)
        return;

    const uint32_t oldBitWidth = bitWidth_;
    const uint32_t oldNumWords = numWords_;
    const uint32_t newNumWords = computeNumWords(newBitWidth);

    if (newBitWidth < oldBitWidth)
    {
        shrink(newBitWidth);
        return;
    }

    const bool sign = isSignBitSet();

    if (!sign)
    {
        if (newNumWords > oldNumWords)
            std::fill(words_ + oldNumWords, words_ + newNumWords, ZERO);
    }
    else
    {
        const uint32_t usedBitsInLastWord = oldBitWidth % WORD_BITS;
        const uint32_t lastWordIndex      = oldNumWords - 1;

        if (usedBitsInLastWord != 0)
        {
            const uint64_t mask = ~((ONE << usedBitsInLastWord) - 1);
            words_[lastWordIndex] |= mask;
        }

        for (uint32_t i = oldNumWords; i < newNumWords; ++i)
            words_[i] = ~0ull;
    }

    bitWidth_ = newBitWidth;
    numWords_ = newNumWords;

    normalize();
}

void ApInt::abs(bool& overflow)
{
    overflow = false;
    if (!isNegative())
        return;
    invertAllBits();
    add(1, overflow);
}

void ApInt::negate(bool& overflow)
{
    overflow = false;

    if (isZero())
        return;

    // Detect minimum signed value (which cannot be negated in-range).
    if (same(minValueSigned(bitWidth_)))
    {
        overflow = true;
        return;
    }

    invertAllBits();
    add(1, overflow);
}

Utf8 ApInt::toString() const
{
    if (isZero())
        return "0";

    ApInt       tmp(*this);
    std::string result;

    while (!tmp.isZero())
    {
        const uint64_t rem = tmp.div(10);
        SWC_ASSERT(rem < 10);
        result.push_back(static_cast<char>('0' + rem));
    }

    std::ranges::reverse(result);
    return result;
}

Utf8 ApInt::toSignedString() const
{
    if (isZero())
        return "0";

    if (isNonNegative())
        return toString();

    // Simplify: detect min signed directly
    if (same(minValueSigned(bitWidth_)))
    {
        // min signed = 1 << (bitWidth-1) in magnitude, printed as "-(1<<...)" in decimal
        ApInt mag(bitWidth_);
        mag.setZero();
        mag.setBit(bitWidth_ - 1);

        std::string digits;
        while (!mag.isZero())
        {
            const uint64_t rem = mag.div(10);
            SWC_ASSERT(rem < 10);
            digits.push_back(static_cast<char>('0' + rem));
        }
        std::ranges::reverse(digits);
        return "-" + digits;
    }

    ApInt mag = *this;
    bool  ov  = false;
    mag.abs(ov);
    SWC_ASSERT(!ov);

    std::string digits;
    while (!mag.isZero())
    {
        const uint64_t rem = mag.div(10);
        SWC_ASSERT(rem < 10);
        digits.push_back(static_cast<char>('0' + rem));
    }

    std::ranges::reverse(digits);
    return "-" + digits;
}

namespace
{
    uint32_t roundUpToStdWidth(uint32_t bits)
    {
        SWC_ASSERT(bits > 0);
        bits = std::min(bits, ApInt::maxBitWidth());

        uint32_t w = 8;
        while (w < bits && w < ApInt::maxBitWidth())
            w <<= 1;

        return (w > ApInt::maxBitWidth()) ? ApInt::maxBitWidth() : w;
    }
}

bool ApInt::fit64() const
{
    if (bitWidth_ <= 64)
        return true;
    return minBits() <= 64;
}

bool ApInt::fit64Signed() const
{
    if (bitWidth_ <= 64)
        return true;
    return minBitsSigned() <= 64;
}

uint32_t ApInt::minBits() const
{
    SWC_ASSERT(bitWidth_ > 0 && numWords_ > 0);

    // Find highest non-zero word.
    for (int wi = static_cast<int>(numWords_) - 1; wi >= 0; --wi)
    {
        uint64_t w = words_[static_cast<uint32_t>(wi)];

        // Mask off unused bits in the top word (if any).
        if (static_cast<uint32_t>(wi) == numWords_ - 1)
        {
            const uint32_t used = bitWidth_ % WORD_BITS;
            if (used != 0)
            {
                const uint64_t mask = (uint64_t{1} << used) - 1;
                w &= mask;
            }
        }

        if (w != 0)
        {
            const uint32_t msbInWord = 63u - static_cast<uint32_t>(std::countl_zero(w));
            const uint32_t bitIndex  = static_cast<uint32_t>(wi) * WORD_BITS + msbInWord;
            const uint32_t rawBits   = std::min(bitIndex + 1, bitWidth_);
            return roundUpToStdWidth(std::max<uint32_t>(rawBits, 1u));
        }
    }

    // Value is 0 => raw bits = 1 => std width = 8
    return 8;
}

uint32_t ApInt::minBitsSigned() const
{
    SWC_ASSERT(bitWidth_ > 0 && numWords_ > 0);

    const bool sign = isSignBitSet();

    // Remove redundant sign-extension: find the highest bit that differs from the sign fill.
    for (int wi = static_cast<int>(numWords_) - 1; wi >= 0; --wi)
    {
        uint64_t w    = words_[static_cast<uint32_t>(wi)];
        uint64_t fill = sign ? ~uint64_t{0} : uint64_t{0};

        // Top word may have unused bits; ignore them for signed-min calculation.
        if (static_cast<uint32_t>(wi) == numWords_ - 1)
        {
            const uint32_t used = bitWidth_ % WORD_BITS;
            if (used != 0)
            {
                const uint64_t mask = (uint64_t{1} << used) - 1;
                w &= mask;
                fill &= mask;
            }
        }

        const uint64_t diff = w ^ fill;
        if (diff != 0)
        {
            const uint32_t msbInWord = 63u - static_cast<uint32_t>(std::countl_zero(diff));
            const uint32_t bitIndex  = static_cast<uint32_t>(wi) * WORD_BITS + msbInWord;

            // One extra bit above the highest differing bit to carry the sign.
            uint32_t rawBits = bitIndex + 2;
            rawBits          = std::max<uint32_t>(rawBits, 1u);
            rawBits          = std::min<uint32_t>(rawBits, bitWidth_);
            return roundUpToStdWidth(rawBits);
        }
    }

    // All bits are just sign-extension: 0 or -1 => rawBits = 1 => std width = 8
    return 8;
}

bool ApInt::isPowerOf2() const
{
    // By convention, treat only non-negative, non-zero values as powers of two.
    if (isZero())
        return false;

    bool foundOneBit = false;

    for (uint32_t i = 0; i < numWords_; ++i)
    {
        const uint64_t w = words_[i];

        if (w == 0)
            continue;

        // If w has more than one bit set, it's not a power of two.
        if (w & (w - 1))
            return false;

        // If we already saw a non-zero word before, then the combined
        // value has more than one-bit set overall.
        if (foundOneBit)
            return false;

        foundOneBit = true;
    }

    // Must have found exactly one bit set in the entire number.
    return foundOneBit;
}

SWC_END_NAMESPACE();
