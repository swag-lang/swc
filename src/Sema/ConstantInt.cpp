#include "pch.h"
#include "Sema/ConstantInt.h"

SWC_BEGIN_NAMESPACE()

ConstantInt::ConstantInt(uint8_t bitWidth) :
    bitWidth_(bitWidth),
    numWords_(computeNumWords(bitWidth))
{
    std::ranges::fill(words_, 0);
    normalize();
}

ConstantInt::ConstantInt(uint8_t bitWidth, size_t value) :
    bitWidth_(bitWidth),
    numWords_(computeNumWords(bitWidth))
{
    std::ranges::fill(words_, 0);
    words_[0] = value;
    normalize();
}

size_t ConstantInt::computeNumWords(uint8_t bitWidth)
{
    assert(bitWidth > 0 && bitWidth <= MAX_BITS);
    return (bitWidth + WORD_BITS - 1) / WORD_BITS;
}

void ConstantInt::normalize()
{
    if (bitWidth_ == 0)
        return;

    const size_t usedBitsInLastWord = bitWidth_ % WORD_BITS;
    if (usedBitsInLastWord != 0)
    {
        const size_t mask = (1 << usedBitsInLastWord) - 1;
        words_[numWords_ - 1] &= mask;
    }
}

size_t ConstantInt::getNative() const
{
    assert(isNative() && "getNative() only valid when value fits in one word");

    if (bitWidth_ < WORD_BITS)
    {
        const size_t mask = (1 << bitWidth_) - 1;
        return words_[0] & mask;
    }
    return words_[0];
}

bool ConstantInt::equals(const ConstantInt& other) const
{
    if (bitWidth_ != other.bitWidth_)
        return false;

    assert(numWords_ == other.numWords_);

    for (size_t i = 0; i < numWords_; ++i)
    {
        if (words_[i] != other.words_[i])
            return false;
    }
    return true;
}

void ConstantInt::bitwiseOr(size_t rhs)
{
    if (numWords_ == 0)
        return;

    words_[0] |= rhs;
    normalize();
}

void ConstantInt::shiftLeft(size_t amount, bool& overflow)
{
    overflow = false;

    if (amount == 0)
        return;

    if (amount >= bitWidth_)
    {
        // Everything is shifted out: overflow if any bit was set
        for (size_t i = 0; i < numWords_; ++i)
        {
            if (words_[i] != 0)
            {
                overflow = true;
                break;
            }
        }

        std::fill_n(words_, numWords_, 0);
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

SWC_END_NAMESPACE()
