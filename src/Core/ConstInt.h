// ReSharper disable CppInconsistentNaming
#pragma once

SWC_BEGIN_NAMESPACE()

template<std::size_t BITS>
class ConstInt
{
    static_assert(BITS >= 1, "Bits must be >= 1");

public:
    using Word = std::uint64_t;

    static constexpr std::size_t BIT_COUNT        = BITS;
    static constexpr std::size_t WORD_BITS        = 64;
    static constexpr std::size_t NUM_WORDS        = (BITS + WORD_BITS - 1) / WORD_BITS;
    static constexpr std::size_t USED_BITS_IN_TOP = ((BITS - 1) % WORD_BITS) + 1;
    static constexpr Word        TOP_MASK         = (USED_BITS_IN_TOP == 64) ? ~static_cast<Word>(0) : ((static_cast<Word>(1) << USED_BITS_IN_TOP) - static_cast<Word>(1));

    constexpr ConstInt() = default;

    constexpr explicit ConstInt(std::uint64_t x)
    {
        assign(x);
    }

    constexpr explicit ConstInt(const std::array<Word, NUM_WORDS>& src) :
        limbs_(src)
    {
        normalize();
    }

    constexpr void assign(std::uint64_t x) noexcept
    {
        limbs_.fill(0);
        limbs_[0] = x;
        normalize();
    }

    constexpr void assign(const std::array<Word, NUM_WORDS>& src) noexcept
    {
        limbs_ = src;
        normalize();
    }

    constexpr const std::array<Word, NUM_WORDS>& data() const
    {
        return limbs_;
    }

    constexpr std::uint64_t to_uint64() const
    {
        return limbs_[0];
    }

    constexpr bool fits_in_uint64() const
    {
        if constexpr (BITS <= 64)
            return true;
        for (std::size_t i = 1; i < NUM_WORDS; ++i)
            if (limbs_[i] != 0)
                return false;
        return true;
    }

    constexpr bool is_zero() const
    {
        for (std::size_t i = 0; i < NUM_WORDS; ++i)
            if (limbs_[i] != 0)
                return false;
        return true;
    }

    constexpr bool get_bit(std::size_t index) const
    {
        if (index >= BITS)
            return false;
        std::size_t wi = index / WORD_BITS;
        std::size_t bi = index % WORD_BITS;
        return (limbs_[wi] >> bi) & static_cast<Word>(1);
    }

    constexpr void set_bit(std::size_t index, bool value)
    {
        if (index >= BITS)
            return;
        std::size_t       wi   = index / WORD_BITS;
        const std::size_t bi   = index % WORD_BITS;
        Word              mask = static_cast<Word>(1) << bi;
        if (value)
            limbs_[wi] |= mask;
        else
            limbs_[wi] &= ~mask;
        if (wi == NUM_WORDS - 1)
        {
            normalize();
        }
    }

    constexpr bool equals(const ConstInt& other) const
    {
        for (std::size_t i = 0; i < NUM_WORDS; ++i)
            if (limbs_[i] != other.limbs_[i])
                return false;
        return true;
    }

    constexpr bool less_than(const ConstInt& other) const
    {
        for (std::size_t i = NUM_WORDS; i-- > 0;)
        {
            if (limbs_[i] < other.limbs_[i])
                return true;
            if (limbs_[i] > other.limbs_[i])
                return false;
        }
        return false;
    }

    constexpr bool less_equal(const ConstInt& other) const
    {
        return !other.less_than(*this);
    }

    constexpr bool greater_than(const ConstInt& other) const
    {
        return other.less_than(*this);
    }

    constexpr bool greater_equal(const ConstInt& other) const
    {
        return !less_than(other);
    }

    constexpr ConstInt add_wrapped(const ConstInt& other) const
    {
        ConstInt r;
        Word     carry = 0;
        for (std::size_t i = 0; i < NUM_WORDS; ++i)
        {
            Word tmp    = limbs_[i] + carry;
            Word sum    = tmp + other.limbs_[i];
            carry       = (tmp < carry) || (sum < other.limbs_[i]);
            r.limbs_[i] = sum;
        }
        r.normalize();
        return r;
    }

    constexpr ConstInt add(const ConstInt& other, bool& overflow) const
    {
        ConstInt r;
        Word     carry = 0;

        overflow = false;

        for (std::size_t i = 0; i < NUM_WORDS; ++i)
        {
            Word t   = limbs_[i] + carry;
            Word sum = t + other.limbs_[i];

            const bool c = (t < carry) || (sum < other.limbs_[i]);
            carry        = c ? static_cast<Word>(1) : static_cast<Word>(0);

            r.limbs_[i] = sum;
        }

        if (carry != 0)
            overflow = true;

        const Word top   = r.limbs_[NUM_WORDS - 1];
        const Word extra = top & ~TOP_MASK;
        if (extra != 0)
            overflow = true;

        r.normalize();
        return r;
    }

    constexpr ConstInt sub_wrapped(const ConstInt& other) const
    {
        ConstInt r;
        Word     borrow = 0;
        for (std::size_t i = 0; i < NUM_WORDS; ++i)
        {
            Word bi     = other.limbs_[i] + borrow;
            Word diff   = limbs_[i] - bi;
            borrow      = (limbs_[i] < bi) ? static_cast<Word>(1) : static_cast<Word>(0);
            r.limbs_[i] = diff;
        }
        r.normalize();
        return r;
    }

    constexpr ConstInt sub(const ConstInt& other, bool& overflow) const
    {
        overflow = less_than(other);

        ConstInt r;
        Word     borrow = 0;

        for (std::size_t i = 0; i < NUM_WORDS; ++i)
        {
            Word bi   = other.limbs_[i] + borrow;
            Word diff = limbs_[i] - bi;

            borrow      = (limbs_[i] < bi) ? static_cast<Word>(1) : static_cast<Word>(0);
            r.limbs_[i] = diff;
        }

        r.normalize();
        return r;
    }

    constexpr ConstInt mul_wrapped(const ConstInt& other) const
    {
        ConstInt r;
        if (is_zero() || other.is_zero())
        {
            return r;
        }

        std::array<Word, 2 * NUM_WORDS> tmp{};
        full_mul(*this, other, tmp);

        for (std::size_t i = 0; i < NUM_WORDS; ++i)
        {
            r.limbs_[i] = tmp[i];
        }
        r.normalize();
        return r;
    }

    constexpr ConstInt mul(const ConstInt& other, bool& overflow) const
    {
        overflow = false;

        if (is_zero() || other.is_zero())
        {
            return ConstInt(0);
        }

        std::array<Word, 2 * NUM_WORDS> tmp{};
        full_mul(*this, other, tmp);

        for (std::size_t i = NUM_WORDS; i < 2 * NUM_WORDS; ++i)
        {
            if (tmp[i] != 0)
            {
                overflow = true;
                break;
            }
        }

        const Word top   = tmp[NUM_WORDS - 1];
        const Word extra = top & ~TOP_MASK;
        if (extra != 0)
            overflow = true;

        ConstInt r;
        for (std::size_t i = 0; i < NUM_WORDS; ++i)
        {
            r.limbs_[i] = tmp[i];
        }

        r.normalize();
        return r;
    }

    constexpr ConstInt bit_and(const ConstInt& other) const
    {
        ConstInt r;
        for (std::size_t i = 0; i < NUM_WORDS; ++i)
            r.limbs_[i] = limbs_[i] & other.limbs_[i];
        r.normalize();
        return r;
    }

    constexpr ConstInt bit_or(const ConstInt& other) const
    {
        ConstInt r;
        for (std::size_t i = 0; i < NUM_WORDS; ++i)
            r.limbs_[i] = limbs_[i] | other.limbs_[i];
        r.normalize();
        return r;
    }

    constexpr ConstInt bit_xor(const ConstInt& other) const
    {
        ConstInt r;
        for (std::size_t i = 0; i < NUM_WORDS; ++i)
            r.limbs_[i] = limbs_[i] ^ other.limbs_[i];
        r.normalize();
        return r;
    }

    constexpr ConstInt bit_not() const
    {
        ConstInt r;
        for (std::size_t i = 0; i < NUM_WORDS; ++i)
            r.limbs_[i] = ~limbs_[i];
        r.normalize();
        return r;
    }

    constexpr ConstInt shl_wrapped(std::size_t shift) const
    {
        if (shift == 0)
            return *this;
        if (shift >= BITS)
            return ConstInt(0);

        ConstInt          r;
        const std::size_t word_shift = shift / WORD_BITS;
        std::size_t       bit_shift  = shift % WORD_BITS;

        for (std::size_t i = NUM_WORDS; i-- > 0;)
        {
            Word val = 0;
            if (i >= word_shift)
            {
                val = limbs_[i - word_shift] << bit_shift;
                if (bit_shift && i > word_shift)
                {
                    val |= limbs_[i - word_shift - 1] >> (WORD_BITS - bit_shift);
                }
            }
            r.limbs_[i] = val;
        }

        r.normalize();
        return r;
    }

    constexpr ConstInt shl(const std::size_t shift, bool& overflow) const
    {
        overflow = false;

        // Shifting by >= BITS always overflows
        if (shift >= BITS)
        {
            overflow = true;
            return ConstInt(0); // UB to use the returned value
        }

        ConstInt r;

        const std::size_t word_shift = shift / WORD_BITS;
        const std::size_t bit_shift  = shift % WORD_BITS;

        // Detect overflow from bits being shifted out
        if (bit_shift != 0)
        {
            const std::size_t drop_word = NUM_WORDS - 1 - word_shift;
            if (drop_word < NUM_WORDS)
            {
                // high bits being shifted out of the highest retained word
                const Word lost = limbs_[drop_word] >> (WORD_BITS - bit_shift);
                if (lost != 0)
                    overflow = true;
            }
        }

        // Bits shifted completely beyond storage also overflow
        for (std::size_t i = NUM_WORDS - word_shift; i < NUM_WORDS; ++i)
        {
            if (limbs_[i] != 0)
                overflow = true;
        }

        // Perform the wrapped shift
        for (std::size_t i = NUM_WORDS; i-- > 0;)
        {
            Word v = 0;

            if (i >= word_shift)
            {
                v = limbs_[i - word_shift] << bit_shift;

                if (bit_shift != 0 && i > word_shift)
                {
                    v |= limbs_[i - word_shift - 1] >> (WORD_BITS - bit_shift);
                }
            }

            r.limbs_[i] = v;
        }

        // Even after the valid shift, extra bits above the allowed range also overflow
        const Word top   = r.limbs_[NUM_WORDS - 1];
        const Word extra = top & ~TOP_MASK;
        if (extra != 0)
            overflow = true;

        r.normalize();
        return r;
    }

    constexpr ConstInt shr(std::size_t shift) const
    {
        if (shift == 0)
            return *this;
        if (shift >= BITS)
            return ConstInt(0);

        ConstInt          r;
        const std::size_t word_shift = shift / WORD_BITS;
        std::size_t       bit_shift  = shift % WORD_BITS;

        for (std::size_t i = 0; i < NUM_WORDS; ++i)
        {
            Word val = 0;
            if (i + word_shift < NUM_WORDS)
            {
                val = limbs_[i + word_shift] >> bit_shift;
                if (bit_shift && i + word_shift + 1 < NUM_WORDS)
                {
                    val |= limbs_[i + word_shift + 1]
                           << (WORD_BITS - bit_shift);
                }
            }
            r.limbs_[i] = val;
        }
        r.normalize();
        return r;
    }

    constexpr void div_mod(const ConstInt& divisor, ConstInt& quotient, ConstInt& remainder, bool& div_by_zero) const
    {
        div_by_zero = false;

        if (divisor.is_zero())
        {
            quotient    = ConstInt(0);
            remainder   = ConstInt(0);
            div_by_zero = true;
            return;
        }

        if (this->is_zero())
        {
            quotient  = ConstInt(0);
            remainder = ConstInt(0);
            return;
        }

        if constexpr (NUM_WORDS == 1)
        {
            const Word usedMask = (USED_BITS_IN_TOP == 64) ? ~static_cast<Word>(0) : ((static_cast<Word>(1) << USED_BITS_IN_TOP) - 1);

            const Word a = limbs_[0] & usedMask;
            const Word b = divisor.limbs_[0] & usedMask;

            Word q = a / b;
            Word r = a % b;

            quotient  = ConstInt(q);
            remainder = ConstInt(r);
        }
        else
        {
            ConstInt q(0);
            ConstInt r(0);

            for (std::size_t i = BITS; i-- > 0;)
            {
                r = r.shl_wrapped(1);
                if (get_bit(i))
                {
                    r.set_bit(0, true);
                }
                if (!r.less_than(divisor))
                {
                    r = r.sub_wrapped(divisor);
                    q.set_bit(i, true);
                }
            }

            quotient  = q;
            remainder = r;
        }
    }

    constexpr ConstInt div(const ConstInt& divisor, bool& div_by_zero) const
    {
        ConstInt q, r;
        div_mod(divisor, q, r, div_by_zero);
        return q;
    }

    constexpr ConstInt mod(const ConstInt& divisor, bool& div_by_zero) const
    {
        ConstInt q, r;
        div_mod(divisor, q, r, div_by_zero);
        return r;
    }

private:
    std::array<Word, NUM_WORDS> limbs_;

    constexpr void normalize()
    {
        limbs_[NUM_WORDS - 1] &= TOP_MASK;
    }

    static constexpr void full_mul(const ConstInt& a, const ConstInt& b, std::array<Word, 2 * NUM_WORDS>& out)
    {
        constexpr std::size_t numDigits  = 2 * NUM_WORDS;
        constexpr std::size_t prodDigits = 2 * numDigits;

        std::array<std::uint32_t, numDigits>  a32{};
        std::array<std::uint32_t, numDigits>  b32{};
        std::array<std::uint32_t, prodDigits> c32{};

        for (std::size_t i = 0; i < NUM_WORDS; ++i)
        {
            a32[2 * i]     = static_cast<std::uint32_t>(a.limbs_[i] & 0xffffffffu);
            a32[2 * i + 1] = static_cast<std::uint32_t>(a.limbs_[i] >> 32);

            b32[2 * i]     = static_cast<std::uint32_t>(b.limbs_[i] & 0xffffffffu);
            b32[2 * i + 1] = static_cast<std::uint32_t>(b.limbs_[i] >> 32);
        }

        for (std::size_t i = 0; i < numDigits; ++i)
        {
            std::uint64_t carry = 0;
            for (std::size_t j = 0; j < numDigits; ++j)
            {
                std::size_t         idx = i + j;
                const std::uint64_t acc = static_cast<std::uint64_t>(c32[idx]) + static_cast<std::uint64_t>(a32[i]) * static_cast<std::uint64_t>(b32[j]) + carry;
                c32[idx]                = static_cast<std::uint32_t>(acc & 0xffffffffu);
                carry                   = acc >> 32;
            }

            c32[i + numDigits] = static_cast<std::uint32_t>(carry);
        }

        for (std::size_t k = 0; k < 2 * NUM_WORDS; ++k)
        {
            out[k] = static_cast<std::uint64_t>(c32[2 * k]) | (static_cast<std::uint64_t>(c32[2 * k + 1]) << 32);
        }
    }
};

SWC_END_NAMESPACE()
