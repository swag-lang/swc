#include "pch.h"
#include "Sema/APInt.h"
#include "Core/hash.h"

SWC_BEGIN_NAMESPACE()

ApInt::ApInt() :
    ApInt(MAX_BITS, false)
{
}

ApInt::ApInt(uint16_t bitWidth, bool negative) :
    bitWidth_(bitWidth),
    numWords_(computeNumWords(bitWidth)),
    negative_(negative)
{
    SWC_ASSERT(bitWidth <= MAX_BITS);
    clearWords();
    normalize();
}

ApInt::ApInt(size_t value, uint16_t bitWidth, bool negative) :
    bitWidth_(bitWidth),
    numWords_(computeNumWords(bitWidth)),
    negative_(negative)
{
    SWC_ASSERT(bitWidth <= MAX_BITS);
    clearWords();
    words_[0] = value;
    normalize();
}

uint8_t ApInt::computeNumWords(uint32_t bitWidth)
{
    SWC_ASSERT(bitWidth > 0 && bitWidth <= MAX_BITS);
    const auto n = (bitWidth + WORD_BITS - 1) / WORD_BITS;
    SWC_ASSERT(n > 0 && n <= 255);
    return static_cast<uint8_t>(n);
}

void ApInt::clearWords()
{
    std::fill_n(words_, numWords_, size_t{0});
}

bool ApInt::isZero() const
{
    for (size_t i = 0; i < numWords_; ++i)
    {
        if (words_[i] != 0)
            return false;
    }
    return true;
}

void ApInt::normalize()
{
    if (bitWidth_ == 0)
        return;

    const size_t usedBitsInLastWord = bitWidth_ % WORD_BITS;
    if (usedBitsInLastWord != 0)
    {
        const size_t mask = (static_cast<size_t>(1) << usedBitsInLastWord) - 1;
        words_[numWords_ - 1] &= mask;
    }
}

size_t ApInt::getNative() const
{
    SWC_ASSERT(isNative());
    if (bitWidth_ < WORD_BITS)
    {
        const size_t mask = (static_cast<size_t>(1) << bitWidth_) - 1;
        return words_[0] & mask;
    }

    return words_[0];
}

bool ApInt::equals(const ApInt& other) const
{
    if (bitWidth_ != other.bitWidth_ || negative_ != other.negative_)
        return false;

    SWC_ASSERT(numWords_ == other.numWords_);
    return std::equal(words_, words_ + numWords_, other.words_);
}

void ApInt::resetToZero()
{
    clearWords();
    negative_ = false;
}

void ApInt::setNegative(bool isNeg)
{
    // Zero can never be negative
    if (isZero())
    {
        negative_ = false;
        return;
    }

    negative_ = isNeg;
}

size_t ApInt::hash() const
{
    auto h = std::hash<int>()(bitWidth_);
    for (size_t i = 0; i < numWords_; ++i)
        h = hash_combine(h, words_[i]);
    return h;
}

void ApInt::bitwiseOr(size_t rhs)
{
    if (numWords_ == 0 || rhs == 0)
        return;

    words_[0] |= rhs;
    normalize();
}

void ApInt::logicalShiftLeft(size_t amount, bool& overflow)
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

    const size_t wordShift = amount / WORD_BITS;
    const size_t bitShift  = amount % WORD_BITS;

    // Word-shift overflow check: words that will be completely shifted out
    if (wordShift > 0)
    {
        for (size_t i = numWords_ - wordShift; i < numWords_; ++i)
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
        for (size_t i = numWords_; i-- > wordShift;)
            words_[i] = words_[i - wordShift];
        for (size_t i = 0; i < wordShift; ++i)
            words_[i] = 0;
    }

    // Bit shift with carry
    if (bitShift > 0)
    {
        size_t carry = 0;
        for (size_t i = 0; i < numWords_; ++i)
        {
            const size_t newCarry = words_[i] >> (WORD_BITS - bitShift);
            words_[i]             = (words_[i] << bitShift) | carry;
            carry                 = newCarry;
        }

        if (carry != 0)
            overflow = true;
    }

    normalize();
}

namespace
{
    void mulWordFull(size_t x, size_t y, size_t carryIn, size_t& outLow, size_t& outHigh)
    {
        using U64 = uint64_t;
        using U32 = uint32_t;

        const U64 a = static_cast<U64>(x);
        const U64 b = static_cast<U64>(y);

        const U64 a_hi = a >> 32;
        const U64 a_lo = static_cast<U32>(a);
        const U64 b_hi = b >> 32;
        const U64 b_lo = static_cast<U32>(b);

        const U64 p0 = a_lo * b_lo; // 64-bit
        const U64 p1 = a_lo * b_hi; // 64-bit
        const U64 p2 = a_hi * b_lo; // 64-bit
        const U64 p3 = a_hi * b_hi; // 64-bit

        // Compose 128-bit product (high: p3 + ..., low: low64)
        const U64 mid  = (p0 >> 32) + (p1 & 0xffffffffull) + (p2 & 0xffffffffull);
        U64       high = p3 + (p1 >> 32) + (p2 >> 32) + (mid >> 32);
        U64       low  = (p0 & 0xffffffffull) | (mid << 32);

        // Add carryIn to low, adjust high on overflow
        low += static_cast<U64>(carryIn);
        if (low < static_cast<U64>(carryIn))
            ++high;

        outLow  = static_cast<size_t>(low);
        outHigh = static_cast<size_t>(high);
    }
}

bool ApInt::hasTopBitsOverflow() const
{
    if (bitWidth_ == 0 || numWords_ == 0)
        return false;

    const size_t usedBitsInLastWord = bitWidth_ % WORD_BITS;
    if (usedBitsInLastWord == 0)
        return false; // the entire last word is used

    const size_t mask = (static_cast<size_t>(1) << usedBitsInLastWord) - 1;
    const size_t last = words_[numWords_ - 1];
    return (last & ~mask) != 0;
}

void ApInt::add(size_t v, bool& overflow)
{
    overflow = false;

    if (v == 0 || numWords_ == 0)
        return;

    // Fast path for native-sized integers
    if (numWords_ == 1)
    {
        const size_t old = words_[0];
        const size_t sum = old + v;

        if (sum < old)
            overflow = true; // word overflow

        words_[0] = sum;

        // Bit-width overflow (if bitWidth_ < WORD_BITS)
        overflow = hasTopBitsOverflow();
        normalize();
        return;
    }

    size_t carry = v;

    // First word: add full v; later words: carry is 0 or 1
    for (size_t i = 0; i < numWords_ && carry != 0; ++i)
    {
        const size_t old = words_[i];
        const size_t sum = old + carry;

        // Unsigned add overflow detection
        if (sum < old)
            carry = 1;
        else
            carry = 0;

        words_[i] = sum;
    }

    if (carry != 0)
        overflow = true; // ran out of words

    overflow = hasTopBitsOverflow();
    normalize();
}

void ApInt::mul(size_t v, bool& overflow)
{
    overflow = false;

    if (numWords_ == 0)
        return;

    if (v == 0 || isZero())
    {
        resetToZero();
        return;
    }

    // Fast path for single-word value
    if (numWords_ == 1)
    {
        size_t low  = 0;
        size_t high = 0;
        mulWordFull(words_[0], v, 0, low, high);

        words_[0] = low;

        if (high != 0)
            overflow = true;

        overflow = hasTopBitsOverflow();
        normalize();
        return;
    }

    // General multi-word multiplication by scalar v
    size_t carry = 0;

    for (size_t i = 0; i < numWords_; ++i)
    {
        size_t low  = 0;
        size_t high = 0;
        mulWordFull(words_[i], v, carry, low, high);
        words_[i] = low;
        carry     = high;
    }

    if (carry != 0)
        overflow = true;

    overflow = hasTopBitsOverflow();
    normalize();
}

SWC_END_NAMESPACE()
