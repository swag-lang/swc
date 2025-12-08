#pragma once

SWC_BEGIN_NAMESPACE()

class ApInt
{
protected:
    static constexpr unsigned MAX_BITS = 128;
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
    ApInt();
    explicit ApInt(uint32_t bitWidth);
    explicit ApInt(uint64_t value, uint32_t bitWidth);

    uint32_t bitWidth() const { return bitWidth_; }
    bool     fits64() const;
    bool     fitsSigned64() const;
    uint64_t asU64() const;

    bool     same(const ApInt& other) const;
    int      compare(const ApInt& other) const;
    uint32_t hash() const;

    bool     isZero() const;
    void     setZero();
    bool     testBit(uint64_t bitIndex) const;
    void     clearBit(uint64_t bitIndex);
    void     setBit(uint64_t bitIndex);
    void     setAllBits();
    void     invertAllBits();
    bool     isSignBitSet() const;
    bool     isSignBitClear() const;
    bool     isNegative() const;
    bool     isNonNegative() const;
    bool     isStrictlyPositive() const;
    bool     isNonPositive() const;
    uint64_t getSignBit() const;
    void     setSignBit(bool isNegative);

    void bitwiseOr(uint64_t rhs);
    void bitwiseOr(const ApInt& rhs);
    void bitwiseAnd(const ApInt& rhs);
    void bitwiseXor(const ApInt& rhs);
    void logicalShiftLeft(uint64_t amount, bool& overflow);
    void logicalShiftRight(uint64_t amount);
    void arithmeticShiftRight(uint64_t amount);
    void abs(bool& overflow);
    void negate(bool& overflow);

    void     add(uint64_t v, bool& overflow);
    void     mul(uint64_t v, bool& overflow);
    uint64_t div(uint64_t v);

    void     add(const ApInt& rhs, bool& overflow);
    void     sub(const ApInt& rhs, bool& overflow);
    void     mul(const ApInt& rhs, bool& overflow);
    uint64_t div(const ApInt& rhs);
    void     mod(const ApInt& rhs);
    void     modSigned(const ApInt& rhs, bool& overflow);

    void    addSigned(const ApInt& rhs, bool& overflow);
    void    subSigned(const ApInt& rhs, bool& overflow);
    void    mulSigned(const ApInt& rhs, bool& overflow);
    int64_t divSigned(const ApInt& rhs, bool& overflow);

    static ApInt minValue(uint32_t bitWidth);
    static ApInt minSignedValue(uint32_t bitWidth);
    static ApInt maxValue(uint32_t bitWidth);
    static ApInt maxSignedValue(uint32_t bitWidth);

    bool eq(const ApInt& rhs) const;
    bool ne(const ApInt& rhs) const;
    bool ult(const ApInt& rhs) const;
    bool ule(const ApInt& rhs) const;
    bool ugt(const ApInt& rhs) const;
    bool uge(const ApInt& rhs) const;
    bool slt(const ApInt& rhs) const;
    bool sle(const ApInt& rhs) const;
    bool sgt(const ApInt& rhs) const;
    bool sge(const ApInt& rhs) const;

    void shrink(uint32_t newBitWidth);
    void resizeUnsigned(uint32_t newBitWidth);
    void resizeSigned(uint32_t newBitWidth);

    Utf8 toString() const;
    Utf8 toSignedString() const;
};

SWC_END_NAMESPACE()
