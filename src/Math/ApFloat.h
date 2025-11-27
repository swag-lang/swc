#pragma once
#include "ApInt.h"

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
    float  toFloat() const;
    double toDouble() const;

    bool     same(const ApFloat& other) const;
    size_t   hash() const;
    uint32_t bitWidth() const { return bitWidth_; }
};

SWC_END_NAMESPACE()
