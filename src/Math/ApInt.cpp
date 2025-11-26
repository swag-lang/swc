#include "pch.h"
#include "Math/APInt.h"
#include "Core/hash.h"

SWC_BEGIN_NAMESPACE()

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

uint32_t ApInt::computeNumWords(uint32_t bitWidth)
{
    SWC_ASSERT(bitWidth > 0 && bitWidth <= MAX_BITS);
    return static_cast<uint32_t>((bitWidth + WORD_BITS - 1) / WORD_BITS);
}

void ApInt::clearWords()
{
    std::fill_n(words_, numWords_, ZERO);
}

bool ApInt::isZero() const
{
    return std::all_of(words_, words_ + numWords_, [](uint64_t w) { return w == 0; });
}

void ApInt::normalize()
{
    if (bitWidth_ == 0)
        return;

    const uint64_t usedBitsInLastWord = bitWidth_ % WORD_BITS;
    if (usedBitsInLastWord != 0)
    {
        const uint64_t mask = (ONE << usedBitsInLastWord) - 1;
        words_[numWords_ - 1] &= mask;
    }
}

bool ApInt::fits64() const
{
    for (uint32_t i = 1; i < numWords_; ++i)
    {
        if (words_[i] != 0)
            return false;
    }

    return true;
}

uint64_t ApInt::to64() const
{
    SWC_ASSERT(fits64());

    if (bitWidth_ < WORD_BITS)
    {
        const uint64_t mask = (ONE << bitWidth_) - 1;
        return words_[0] & mask;
    }

    return words_[0];
}

void ApInt::resetToZero()
{
    clearWords();
}

bool ApInt::sameValue(const ApInt& i1, const ApInt& i2)
{
    if (i1.bitWidth_ != i2.bitWidth_)
        return false;
    SWC_ASSERT(i1.numWords_ == i2.numWords_);
    return std::equal(i1.words_, i1.words_ + i1.numWords_, i2.words_);
}

int ApInt::compareValues(const ApInt& i1, const ApInt& i2)
{
    SWC_ASSERT(i1.bitWidth_ == i2.bitWidth_);
    SWC_ASSERT(i1.numWords_ == i2.numWords_);

    for (int i = static_cast<int>(i1.numWords_) - 1; i >= 0; --i)
    {
        const uint64_t a = i1.words_[static_cast<uint32_t>(i)];
        const uint64_t b = i2.words_[static_cast<uint32_t>(i)];
        if (a < b)
            return -1;
        if (a > b)
            return 1;
    }

    return 0;
}

bool ApInt::same(const ApInt& other) const
{
    if (bitWidth_ != other.bitWidth_)
        return false;
    return sameValue(other, *this);
}

uint64_t ApInt::hash() const
{
    auto h = std::hash<int>()(static_cast<int>(bitWidth_));
    for (uint64_t i = 0; i < numWords_; ++i)
        h = hash_combine(h, words_[i]);
    return h;
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

void ApInt::logicalShiftLeft(uint64_t amount, bool& overflow)
{
    overflow = false;

    if (amount == 0)
        return;

    if (amount >= bitWidth_)
    {
        // Everything is shifted out: overflow if any bit was set
        overflow = !isZero();
        resetToZero();
        return;
    }

    const uint64_t wordShift = amount / WORD_BITS;
    const uint64_t bitShift  = amount % WORD_BITS;

    // Word-shift overflow check: words that will be completely shifted out
    if (wordShift > 0)
    {
        for (uint64_t i = numWords_ - wordShift; i < numWords_; ++i)
        {
            if (words_[i] != 0)
            {
                overflow = true;
                break;
            }
        }
    }

    // Word shift
    if (wordShift > 0)
    {
        for (uint64_t i = numWords_; i-- > wordShift;)
            words_[i] = words_[i - wordShift];
        for (uint64_t i = 0; i < wordShift; ++i)
            words_[i] = 0;
    }

    // Bit shift with carry
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
        resetToZero();
        return;
    }

    if (wordShift > 0)
    {
        for (uint32_t i = 0; i < numWords_ - wordShift; ++i)
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

namespace
{
    void mulWordFull(uint64_t x, uint64_t y, uint64_t carryIn, uint64_t& outLow, uint64_t& outHigh)
    {
        const uint64_t a = x;
        const uint64_t b = y;

        const uint64_t aHi = a >> 32;
        const uint64_t aLo = static_cast<uint32_t>(a);
        const uint64_t bHi = b >> 32;
        const uint64_t bLo = static_cast<uint32_t>(b);

        const uint64_t p0 = aLo * bLo;
        const uint64_t p1 = aLo * bHi;
        const uint64_t p2 = aHi * bLo;
        const uint64_t p3 = aHi * bHi;

        // Compose 128-bit product (high: p3 + ..., low: low64)
        const uint64_t mid  = (p0 >> 32) + (p1 & 0xffffffffull) + (p2 & 0xffffffffull);
        uint64_t       high = p3 + (p1 >> 32) + (p2 >> 32) + (mid >> 32);
        uint64_t       low  = (p0 & 0xffffffffull) | (mid << 32);

        // Add carryIn to low, adjust high on overflow
        low += carryIn;
        if (low < carryIn)
            ++high;

        outLow  = low;
        outHigh = high;
    }
}

void ApInt::mul(uint64_t v, bool& overflow)
{
    SWC_ASSERT(numWords_);
    overflow = false;

    if (v == 0)
    {
        resetToZero();
        return;
    }

    uint64_t carry = 0;
    for (uint64_t i = 0; i < numWords_; ++i)
    {
        uint64_t low  = 0;
        uint64_t high = 0;
        mulWordFull(words_[i], v, carry, low, high);
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
        const uint64_t word  = words_[i];
        uint64_t       qWord = 0;

        // Bit-by-bit long division in base 2, from MSB to LSB of this word
        for (int bit = static_cast<int>(WORD_BITS) - 1; bit >= 0; --bit)
        {
            // Bring down the next bit
            rem = (rem << 1) | ((word >> bit) & ONE);

            // Shift quotient and test if we can subtract divisor
            qWord <<= 1;
            if (rem >= v)
            {
                rem -= v;
                qWord |= 1;
            }
        }

        words_[i] = qWord;
    }

    normalize();
    return rem;
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
    for (uint32_t i = 0; i < bitWidth_; ++i)
        setBit(i);
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

namespace
{
    ApInt makeMinValue(uint32_t bitWidth)
    {
        ApInt result(bitWidth);
        result.resetToZero();
        return result;
    }

    ApInt makeMinSignedValue(uint32_t bitWidth)
    {
        ApInt result(bitWidth);
        result.resetToZero();
        result.setBit(bitWidth - 1);
        return result;
    }

    ApInt makeMaxValue(uint32_t bitWidth)
    {
        ApInt result(bitWidth);
        result.setAllBits();
        return result;
    }

    ApInt makeMaxSignedValue(uint32_t bitWidth)
    {
        ApInt result(bitWidth);
        result.setAllBits();
        result.clearBit(bitWidth - 1);
        return result;
    }
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

ApInt ApInt::minSignedValue(uint32_t bitWidth)
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
        case 128: return U128;
        default: return makeMaxValue(bitWidth);
    }
}

ApInt ApInt::maxSignedValue(uint32_t bitWidth)
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
        case 128: return S128;
        default: return makeMaxSignedValue(bitWidth);
    }
}

bool ApInt::eq(const ApInt& rhs) const
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    return sameValue(*this, rhs);
}

bool ApInt::ne(const ApInt& rhs) const
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    return !sameValue(*this, rhs);
}

bool ApInt::ult(const ApInt& rhs) const
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    return compareValues(*this, rhs) < 0;
}

bool ApInt::ule(const ApInt& rhs) const
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    return compareValues(*this, rhs) <= 0;
}

bool ApInt::ugt(const ApInt& rhs) const
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    return compareValues(*this, rhs) > 0;
}

bool ApInt::uge(const ApInt& rhs) const
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    return compareValues(*this, rhs) >= 0;
}

bool ApInt::slt(const ApInt& rhs) const
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);

    const bool thisNeg = isNegative();
    const bool rhsNeg  = rhs.isNegative();

    if (thisNeg != rhsNeg)
        return thisNeg;

    // Same signs: Use unsigned comparison but reverse the result if both are negative.
    const int result = compareValues(*this, rhs);
    return thisNeg ? (result > 0) : (result < 0);
}

bool ApInt::sle(const ApInt& rhs) const
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);

    const bool thisNeg = isNegative();
    const bool rhsNeg  = rhs.isNegative();

    if (thisNeg != rhsNeg)
        return thisNeg;

    // Same signs: Use unsigned comparison but reverse the result for a negative case.
    const int result = compareValues(*this, rhs);
    return thisNeg ? (result >= 0) : (result <= 0);
}

bool ApInt::sgt(const ApInt& rhs) const
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);

    const bool thisNeg = isNegative();
    const bool rhsNeg  = rhs.isNegative();

    if (thisNeg != rhsNeg)
        return !thisNeg;

    // Same signs: Use unsigned comparison but reverse the result for a negative case.
    const int result = compareValues(*this, rhs);
    return thisNeg ? (result < 0) : (result > 0);
}

bool ApInt::sge(const ApInt& rhs) const
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);

    const bool thisNeg = isNegative();
    const bool rhsNeg  = rhs.isNegative();

    if (thisNeg != rhsNeg)
    {
        return !thisNeg;
    }

    // Same signs: Use unsigned comparison but reverse the result for a negative case.
    const int result = compareValues(*this, rhs);
    return thisNeg ? (result <= 0) : (result >= 0);
}

void ApInt::shrink(uint32_t newBitWidth)
{
    SWC_ASSERT(newBitWidth > 0);
    SWC_ASSERT(newBitWidth <= bitWidth_);

    if (newBitWidth == bitWidth_)
        return;

    const uint32_t newNumWords = computeNumWords(newBitWidth);

    // Update bitWidth and word count
    bitWidth_ = newBitWidth;
    numWords_ = newNumWords;

    // Mask off unused high bits of the last word
    normalize();
}

// In-place zero-extend or truncate.
void ApInt::resizeUnsigned(uint32_t newBitWidth)
{
    SWC_ASSERT(newBitWidth > 0);

    if (newBitWidth == bitWidth_)
        return;

    const uint32_t oldBitWidth = bitWidth_;
    const uint32_t oldNumWords = numWords_;
    const uint32_t newNumWords = computeNumWords(newBitWidth);

    if (newBitWidth < oldBitWidth)
    {
        // Truncation: just shrink metadata and mask the new top word.
        bitWidth_ = newBitWidth;
        numWords_ = newNumWords;
        normalize();
        return;
    }

    // Zero-extension.
    // Make sure any newly used words are cleared.
    if (newNumWords > oldNumWords)
        std::fill(words_ + oldNumWords, words_ + newNumWords, ZERO);

    bitWidth_ = newBitWidth;
    numWords_ = newNumWords;

    // Ensure bits above newBitWidth are cleared in the last word.
    normalize();
}

// In-place sign-extend or truncate.
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
        // Truncation: same as unsigned; sign is not preserved when shrinking.
        bitWidth_ = newBitWidth;
        numWords_ = newNumWords;
        normalize();
        return;
    }

    // Extension.
    const bool sign = isSignBitSet();

    if (!sign)
    {
        // Positive value: sign extension == zero extension.
        if (newNumWords > oldNumWords)
            std::fill(words_ + oldNumWords, words_ + newNumWords, ZERO);
    }
    else
    {
        // Negative value: replicate sign bit into the new high bits.

        const uint32_t usedBitsInLastWord = oldBitWidth % WORD_BITS;
        const uint32_t lastWordIndex      = oldNumWords - 1;

        // If the old type didn't use the entire last word, fill the remaining bits
        // in that word with 1s (they become part of the extended sign region).
        if (usedBitsInLastWord != 0)
        {
            const uint64_t mask = ~((ONE << usedBitsInLastWord) - 1); // bits [usedBitsInLastWord .. 63] = 1
            words_[lastWordIndex] |= mask;
        }

        // Any additional whole words that become newly visible should be all 1s.
        for (uint32_t i = oldNumWords; i < newNumWords; ++i)
            words_[i] = ~0ull;
    }

    bitWidth_ = newBitWidth;
    numWords_ = newNumWords;

    // Clear bits above the new bit width in the top word.
    normalize();
}

SWC_END_NAMESPACE()
