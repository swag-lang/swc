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

    void   set(float value);
    void   set(double value);
    void   set(const ApInt& mantissa, int64_t exponent10);
    void   set(const ApsInt& value, uint32_t targetBits, bool& exact, bool& overflow);
    float  asFloat() const;
    double asDouble() const;

    bool   same(const ApFloat& other) const;
    size_t hash() const;

    uint32_t bitWidth() const { return bitWidth_; }
    void     negate();

    bool eq(const ApFloat& rhs) const;
};

SWC_END_NAMESPACE()
