#pragma once

SWC_BEGIN_NAMESPACE()

class ApInt
{
    static constexpr unsigned MAX_BITS = 64;
    static_assert(MAX_BITS <= 255, "ApInt is only supported up to 255 bits");
    static constexpr uint64_t WORD_BITS = sizeof(uint64_t) * 8;
    static constexpr uint64_t MAX_WORDS = (MAX_BITS + WORD_BITS - 1) / WORD_BITS;
    static constexpr uint64_t ZERO      = 0;
    static constexpr uint64_t ONE       = 1;

    uint64_t words_[MAX_WORDS];
    uint32_t bitWidth_;
    uint32_t numWords_;

    void            clearWords();
    static uint32_t computeNumWords(uint32_t bitWidth);
    void            normalize();
    bool            hasTopBitsOverflow() const;

public:
    explicit ApInt();
    explicit ApInt(uint32_t bitWidth);
    explicit ApInt(uint64_t value, uint32_t bitWidth);

    uint32_t bitWidth() const { return bitWidth_; }
    bool     fits64() const;
    uint64_t to64() const;

    bool     equals(const ApInt& other) const;
    int      compare(const ApInt& other) const;
    uint64_t hash() const;

    bool     isZero() const;
    void     resetToZero();
    bool     testBit(uint64_t bitIndex) const;
    void     clearBit(uint64_t bitIndex);
    void     setBit(uint64_t bitIndex);
    bool     isSignBitSet() const;
    bool     isSignBitClear() const;
    bool     isNegative() const;
    bool     isNonNegative() const;
    bool     isStrictlyPositive() const;
    bool     isNonPositive() const;
    uint64_t getSignBit() const;

    void     bitwiseOr(uint64_t rhs);
    void     logicalShiftLeft(uint64_t amount, bool& overflow);
    void     logicalShiftRight(uint64_t amount);
    void     add(uint64_t v, bool& overflow);
    void     mul(uint64_t v, bool& overflow);
    uint64_t div(uint64_t v);
};

SWC_END_NAMESPACE()
