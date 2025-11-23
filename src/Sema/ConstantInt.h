#pragma once
SWC_BEGIN_NAMESPACE()

template<size_t N, bool SIGNED>
class ConstantInt
{
    static_assert(N > 0, "Zero-bit ConstantInt is not supported");

    static constexpr size_t WORD_BITS      = sizeof(size_t) * 8;
    static constexpr size_t MAX_WORDS      = (N + WORD_BITS - 1) / WORD_BITS;
    static constexpr size_t ZERO           = 0;
    static constexpr size_t ONE            = 1;
    static constexpr size_t SIGN_BIT_INDEX = N - 1;

    size_t words_[MAX_WORDS];

    static constexpr size_t nativeMask()
    {
        if constexpr (N >= WORD_BITS)
            return ~ZERO;
        else
            return (ONE << N) - 1;
    }

    void normalize();

public:
    ConstantInt();
    explicit ConstantInt(size_t value);

    static constexpr bool isNative() { return MAX_WORDS == 1; }
    size_t                getNative() const;

    void setZero();
    void shiftLeft(size_t shiftAmount, bool& overflow);
    void bitwiseOr(size_t rhs);
    bool equals(const ConstantInt& other) const;

    bool isNegative() const
    {
        if constexpr (!SIGNED)
            return false;
        return (words_[MAX_WORDS - 1] >> (SIGN_BIT_INDEX % WORD_BITS)) & 1;
    }
};

using ConstantIntS8  = ConstantInt<8, true>;
using ConstantIntS16 = ConstantInt<16, true>;
using ConstantIntS32 = ConstantInt<32, true>;
using ConstantIntS64 = ConstantInt<64, true>;
using ConstantIntU8  = ConstantInt<8, false>;
using ConstantIntU16 = ConstantInt<16, false>;
using ConstantIntU32 = ConstantInt<32, false>;
using ConstantIntU64 = ConstantInt<64, false>;

SWC_END_NAMESPACE()
