#pragma once

SWC_BEGIN_NAMESPACE()

class ConstantInt
{
    static constexpr unsigned MAX_BITS  = 256;
    static constexpr size_t   WORD_BITS = sizeof(size_t) * 8;
    static constexpr size_t   MAX_WORDS = (MAX_BITS + WORD_BITS - 1) / WORD_BITS;

    unsigned bitWidth_;
    size_t   numWords_;
    size_t   words_[MAX_WORDS];

    static size_t computeNumWords(uint32_t bitWidth);
    void          normalize();

public:
    explicit ConstantInt(uint32_t bitWidth = MAX_BITS);
    explicit ConstantInt(uint32_t bitWidth, size_t value);

    unsigned getBitWidth() const { return bitWidth_; }

    bool   isNative() const { return numWords_ == 1; }
    size_t getNative() const;

    bool equals(const ConstantInt& other) const;
    void bitwiseOr(size_t rhs);
    void shiftLeft(size_t amount, bool& overflow);
};

SWC_END_NAMESPACE()
