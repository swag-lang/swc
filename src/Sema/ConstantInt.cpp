#include "pch.h"
#include "Sema/ConstantInt.h"

SWC_BEGIN_NAMESPACE()

template class ConstantInt<8, true>;
template class ConstantInt<16, true>;
template class ConstantInt<32, true>;
template class ConstantInt<64, true>;
template class ConstantInt<8, false>;
template class ConstantInt<16, false>;
template class ConstantInt<32, false>;
template class ConstantInt<64, false>;

template<size_t N, bool SIGNED>
void ConstantInt<N, SIGNED>::normalize()
{
    if constexpr (MAX_WORDS == 1)
    {
        if constexpr (N < WORD_BITS)
            words_[0] &= nativeMask();
    }
    else
    {
        const size_t usedBitsInLastWord = N % WORD_BITS;
        if (usedBitsInLastWord != 0)
        {
            const size_t mask = (ONE << usedBitsInLastWord) - 1;
            words_[MAX_WORDS - 1] &= mask;
        }
    }
}

template<size_t N, bool SIGNED>
ConstantInt<N, SIGNED>::ConstantInt()
{
    setZero();
}

template<size_t N, bool SIGNED>
void ConstantInt<N, SIGNED>::setZero()
{
    if constexpr (MAX_WORDS == 1)
        words_[0] = ZERO;
    else
    {
        std::fill(std::begin(words_), std::end(words_), static_cast<size_t>(0));
        normalize();
    }
}

template<size_t N, bool SIGNED>
ConstantInt<N, SIGNED>::ConstantInt(size_t value)
{
    std::fill(std::begin(words_), std::end(words_), static_cast<size_t>(0));

    if constexpr (MAX_WORDS == 1)
    {
        if constexpr (N < WORD_BITS)
            words_[0] = value & nativeMask();
        else
            words_[0] = value;
    }
    else
    {
        words_[0] = value;
        normalize();
    }
}

template<size_t N, bool SIGNED>
size_t ConstantInt<N, SIGNED>::getNative() const
{
    static_assert(MAX_WORDS == 1, "getNative() is only valid when ConstantInt<N> fits in a single native word");
    if constexpr (N < WORD_BITS)
        return words_[0] & nativeMask();
    else
        return words_[0];
}

template<size_t N, bool SIGNED>
void ConstantInt<N, SIGNED>::shiftLeft(size_t shiftAmount, bool& overflow)
{
    overflow = false;

    if (shiftAmount == 0)
        return;

    if (shiftAmount >= N)
    {
        overflow = (words_[0] != 0);
        setZero();
        return;
    }

    // Native fast path
    if constexpr (MAX_WORDS == 1)
    {
        if constexpr (N < WORD_BITS)
        {
            const size_t before   = words_[0];
            const size_t shifted  = before << shiftAmount;
            const size_t lostMask = nativeMask() << (N - shiftAmount);

            overflow  = (before & lostMask) != 0;
            words_[0] = shifted & nativeMask();
        }
        else
        {
            const size_t before = words_[0];
            overflow            = (shiftAmount > 0) && (before >> (WORD_BITS - shiftAmount)) != 0;
            words_[0] <<= shiftAmount;
        }
    }

    // Multi-word big-int path
    else
    {
        const size_t wordShift = shiftAmount / WORD_BITS;
        const size_t bitShift  = shiftAmount % WORD_BITS;

        // Word-shift overflow check
        for (size_t i = MAX_WORDS - wordShift; i < MAX_WORDS; ++i)
            if (words_[i] != 0)
                overflow = true;

        // Perform word shift
        if (wordShift > 0)
        {
            for (size_t i = MAX_WORDS; i-- > wordShift;)
                words_[i] = words_[i - wordShift];
            for (size_t i = 0; i < wordShift; ++i)
                words_[i] = 0;
        }

        if (bitShift > 0)
        {
            size_t carry = 0;
            for (size_t i = 0; i < MAX_WORDS; ++i)
            {
                const size_t newCarry = (words_[i] >> (WORD_BITS - bitShift));
                words_[i]             = (words_[i] << bitShift) | carry;
                carry                 = newCarry;
            }

            if (carry != 0)
                overflow = true;
        }

        normalize();
    }
}

template<size_t N, bool SIGNED>
void ConstantInt<N, SIGNED>::bitwiseOr(size_t rhs)
{
    if constexpr (MAX_WORDS == 1)
    {
        if constexpr (N < WORD_BITS)
            words_[0] = (words_[0] | rhs) & nativeMask();
        else
            words_[0] |= rhs;
    }
    else
    {
        words_[0] |= rhs;
        normalize();
    }
}

template<size_t N, bool SIGNED>
bool ConstantInt<N, SIGNED>::equals(const ConstantInt& other) const
{
    if constexpr (MAX_WORDS == 1)
    {
        return (words_[0] == other.words_[0]);
    }
    else
    {
        for (size_t i = 0; i < MAX_WORDS; ++i)
        {
            if (words_[i] != other.words_[i])
                return false;
        }

        return true;
    }
}

SWC_END_NAMESPACE()
