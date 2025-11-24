#pragma once

SWC_BEGIN_NAMESPACE()

class ApFloat
{
    static constexpr unsigned MAX_BITS = 64;
    static_assert(MAX_BITS <= 255, "ApFloat is only supported up to 255 bits");
    static constexpr size_t WORD_BITS = sizeof(size_t) * 8;
    static constexpr size_t MAX_WORDS = (MAX_BITS + WORD_BITS - 1) / WORD_BITS;

public:
    enum class Category : uint8_t
    {
        Zero,
        Normal,
        Subnormal,
        Inf,
        NaN
    };

private:
    size_t   words_[MAX_WORDS];
    uint16_t bitWidth_;
    uint16_t expWidth_;
    uint16_t mantissaWidth_;
    uint8_t  numWords_;

    void           clearWords();
    static uint8_t computeNumWords(uint32_t bitWidth);

    uint64_t getStorage() const;
    void     setStorage(uint64_t value);

    uint64_t getMantissaMask() const;
    uint64_t getExponentMask() const;
    uint64_t getSignMask() const;

public:
    // Constructors
    /// Default: 64-bit IEEE-like layout (1 sign, 11 exponent, 52 mantissa)
    explicit ApFloat();

    /// Custom format, value initialized to +0
    explicit ApFloat(uint16_t expWidth, uint16_t mantissaWidth);

    /// From double using the default format
    explicit ApFloat(double value);

    /// From double using a custom format
    explicit ApFloat(double value, uint16_t expWidth, uint16_t mantissaWidth);

    // Format and storage info
    uint16_t getBitWidth() const { return bitWidth_; }
    uint16_t getExponentWidth() const { return expWidth_; }
    uint16_t getMantissaWidth() const { return mantissaWidth_; }
    uint8_t  getNumWords() const { return numWords_; }

    // Sign / category
    bool isNegative() const;
    void setNegative(bool isNegative);

    Category getCategory() const;
    bool     isZero() const;
    bool     isInf() const;
    bool     isNaN() const;
    bool     isSubnormal() const;
    bool     isNormal() const;
    bool     isFinite() const;

    // Reset
    void resetToZero(bool negative = false);

    // Conversions
    void   fromDouble(double value);
    double toDouble() const;

    // Comparisons & utilities
    bool   equals(const ApFloat& other) const;
    size_t hash() const;
};

SWC_END_NAMESPACE()
