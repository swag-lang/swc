#pragma once
#include "Math/ApInt.h"
#include "Math/ApsInt.h"

SWC_BEGIN_NAMESPACE()

class ApFloat
{
    static constexpr unsigned MAX_BITS = 64;

    uint32_t bitWidth_;
    union
    {
        float  f32;
        double f64;
    } value_;

public:
    ApFloat();
    explicit ApFloat(double value);
    explicit ApFloat(float value);

    void set(float value);
    void set(double value);
    void set(const ApInt& mantissa, int64_t exponent10);
    void set(const ApsInt& value, uint32_t targetBits, bool& exact, bool& overflow);
    bool isZero() const;

    void setZero();
    bool isNaN() const;
    bool isInfinity() const;
    bool isFinite() const;
    bool isNegative() const;
    void setNaN();
    void setInfinity(bool negative);

    float  asFloat() const;
    double asDouble() const;

    bool     same(const ApFloat& other) const;
    int      compare(const ApFloat& other) const;
    uint32_t hash() const;

    uint32_t bitWidth() const { return bitWidth_; }
    void     negate();
    void     add(const ApFloat& rhs);
    void     sub(const ApFloat& rhs);
    void     mul(const ApFloat& rhs);
    void     div(const ApFloat& rhs);

    bool eq(const ApFloat& rhs) const;
    bool ne(const ApFloat& rhs) const;
    bool lt(const ApFloat& rhs) const;
    bool le(const ApFloat& rhs) const;
    bool gt(const ApFloat& rhs) const;
    bool ge(const ApFloat& rhs) const;

    Utf8    toString() const;
    ApsInt  toInt(uint32_t targetBits, bool isUnsigned, bool& isExact, bool& overflow) const;
    ApFloat convertTo(uint32_t targetBits, bool& isExact, bool& overflow) const;
};

SWC_END_NAMESPACE()
