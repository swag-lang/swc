#pragma once
SWC_BEGIN_NAMESPACE()

template<size_t N>
class ConstantInt
{
    static constexpr size_t WORD_BITS = sizeof(size_t) * 8;
    static constexpr size_t MAX_WORDS = (N + WORD_BITS - 1) / WORD_BITS;

    size_t words_[MAX_WORDS];

    void normalize()
    {
        const size_t usedBitsInLastWord = N % WORD_BITS;
        if (usedBitsInLastWord != 0)
        {
            const size_t mask = (static_cast<size_t>(1) << usedBitsInLastWord) - 1;
            words_[MAX_WORDS - 1] &= mask;
        }
    }

public:
    ConstantInt()
    {
        std::fill(std::begin(words_), std::end(words_), static_cast<size_t>(0));
        normalize();
    }

    explicit ConstantInt(size_t value)
    {
        std::fill(std::begin(words_), std::end(words_), static_cast<size_t>(0));
        words_[0] = value;
        normalize();
    }

    // “Native” means: fits in one machine word
    static constexpr bool isNative()
    {
        return MAX_WORDS == 1;
    }

    // Return the value as a single native machine word.
    // Only valid when isNative() == true, i.e., MAX_WORDS == 1.
    size_t getNative() const
    {
        static_assert(MAX_WORDS == 1, "getNative() is only valid when ConstantInt<N> fits in a single native word");

        // Optionally, assert the high words are zero for safety in debug builds
        if constexpr (N < WORD_BITS)
        {
            // Extra paranoia: mask off unused bits (normalize() already does this)
            const size_t mask = (static_cast<size_t>(1) << N) - 1;
            return words_[0] & mask;
        }
        else
        {
            return words_[0];
        }
    }

    ConstantInt& operator<<=(size_t shiftAmount)
    {
        if (shiftAmount == 0)
            return *this;

        if (shiftAmount >= N)
        {
            std::fill(std::begin(words_), std::end(words_), static_cast<size_t>(0));
            return *this;
        }

        const size_t wordShift = shiftAmount / WORD_BITS;
        const size_t bitShift  = shiftAmount % WORD_BITS;

        // 1. Handle word shift
        if (wordShift > 0)
        {
            for (size_t i = MAX_WORDS; i-- > wordShift;)
                words_[i] = words_[i - wordShift];
            for (size_t i = 0; i < wordShift; ++i)
                words_[i] = 0;
        }

        // 2. Handle bit shift with carry
        if (bitShift > 0)
        {
            size_t carry = 0;
            for (size_t i = wordShift; i < MAX_WORDS; ++i)
            {
                const size_t nextCarry = words_[i] >> (WORD_BITS - bitShift);
                words_[i]              = (words_[i] << bitShift) | carry;
                carry                  = nextCarry;
            }
        }

        normalize();
        return *this;
    }

    ConstantInt& operator|=(size_t rhs)
    {
        words_[0] |= rhs;
        normalize();
        return *this;
    }
};

SWC_END_NAMESPACE()
