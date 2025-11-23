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

size_t ApInt::hash() const
{
    auto h = std::hash<int>()(bitWidth_);
    for (size_t i = 0; i < numWords_; ++i)
        h = hash_combine(h, words_[i]);
    return h;
}

SWC_END_NAMESPACE()
