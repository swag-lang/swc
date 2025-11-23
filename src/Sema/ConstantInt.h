#pragma once
#include <algorithm>
#include <cassert>

SWC_BEGIN_NAMESPACE()

class ConstantInt
{
    static constexpr unsigned MAX_BITS  = 256; // adjust as needed
    static constexpr size_t   WORD_BITS = sizeof(size_t) * 8;
    static constexpr size_t   MAX_WORDS = (MAX_BITS + WORD_BITS - 1) / WORD_BITS;

    unsigned bitWidth_;         // logical bit width (1..MAX_BITS)
    size_t   numWords_;         // how many words are used (derived from bitWidth_)
    size_t   words_[MAX_WORDS]; // least significant word at index 0

    static size_t computeNumWords(unsigned bitWidth)
    {
        assert(bitWidth > 0 && bitWidth <= MAX_BITS);
        return (bitWidth + WORD_BITS - 1) / WORD_BITS;
    }

    void normalize()
    {
        if (bitWidth_ == 0)
            return;

        const size_t usedBitsInLastWord = bitWidth_ % WORD_BITS;
        if (usedBitsInLastWord != 0)
        {
            const size_t mask = (size_t(1) << usedBitsInLastWord) - 1;
            words_[numWords_ - 1] &= mask;
        }
    }

public:
    // -------------------------
    // Constructors
    // -------------------------

    ConstantInt() = default;

    // Construct zero with a given bitWidth (must be <= MAX_BITS)
    explicit ConstantInt(unsigned bitWidth) :
        bitWidth_(bitWidth),
        numWords_(computeNumWords(bitWidth))
    {
        std::ranges::fill(words_, size_t(0));
        normalize();
    }

    // Construct from a native value (truncated to bitWidth)
    ConstantInt(unsigned bitWidth, size_t value) :
        bitWidth_(bitWidth),
        numWords_(computeNumWords(bitWidth))
    {
        std::fill(std::begin(words_), std::end(words_), size_t(0));
        words_[0] = value;
        normalize();
    }

    unsigned getBitWidth() const { return bitWidth_; }

    // -------------------------
    // Native helpers
    // -------------------------

    bool isNative() const
    {
        return numWords_ == 1;
    }

    size_t getNative() const
    {
        assert(isNative() && "getNative() only valid when value fits in one word");

        if (bitWidth_ < WORD_BITS)
        {
            const size_t mask = (size_t(1) << bitWidth_) - 1;
            return words_[0] & mask;
        }
        return words_[0];
    }

    // -------------------------
    // Equality
    // -------------------------

    bool equals(const ConstantInt& other) const
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

    // -------------------------
    // Bitwise OR with native value
    // -------------------------

    void bitwiseOr(size_t rhs)
    {
        if (numWords_ == 0)
            return;

        words_[0] |= rhs;
        normalize();
    }

    // -------------------------
    // Shift left with overflow flag
    // -------------------------

    void shiftLeft(size_t amount, bool& overflow)
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
            std::fill(words_, words_ + numWords_, size_t(0));
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

        // 1. Word shift
        if (wordShift > 0)
        {
            for (size_t i = numWords_; i-- > wordShift;)
                words_[i] = words_[i - wordShift];

            for (size_t i = 0; i < wordShift; ++i)
                words_[i] = 0;
        }

        // 2. Bit shift with carry
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
};

SWC_END_NAMESPACE()
