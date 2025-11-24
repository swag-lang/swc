#pragma once

SWC_BEGIN_NAMESPACE()

class ApInt
{
    static constexpr unsigned MAX_BITS = 64;
    static_assert(MAX_BITS <= 255, "ApInt is only supported up to 255 bits");
    static constexpr size_t WORD_BITS = sizeof(size_t) * 8;
    static constexpr size_t MAX_WORDS = (MAX_BITS + WORD_BITS - 1) / WORD_BITS;

    size_t   words_[MAX_WORDS];
    uint16_t bitWidth_;
    uint8_t  numWords_;
    bool     negative_;

    void           clearWords();
    static uint8_t computeNumWords(uint32_t bitWidth);
    void           normalize();
    bool           hasTopBitsOverflow() const;

public:
    explicit ApInt();
    explicit ApInt(uint16_t bitWidth, bool negative);
    explicit ApInt(size_t value, uint16_t bitWidth, bool negative);

    uint16_t getBitWidth() const { return bitWidth_; }
    bool     isNegative() const { return negative_; }
    bool     isNative() const { return numWords_ == 1; }
    size_t   getNative() const;

    bool equals(const ApInt& other) const;
    bool isZero() const;
    void resetToZero();
    void setNegative(bool isNeg);
    bool testBit(size_t bitIndex) const;
    void setBit(size_t bitIndex);

    void     bitwiseOr(size_t rhs);
    void     logicalShiftLeft(size_t amount, bool& overflow);
    void     logicalShiftRight(size_t amount);
    void     add(size_t v, bool& overflow);
    void     mul(size_t v, bool& overflow);
    uint32_t div(uint32_t v);
    void     mulPow5(uint32_t exp, bool& overflow);

    size_t hash() const;
};

SWC_END_NAMESPACE()
