#pragma once
#include "Math/ApInt.h"

SWC_BEGIN_NAMESPACE()

class ApsInt : public ApInt
{
    static constexpr uint64_t ZERO      = 0;
    static constexpr uint64_t ONE       = 1;
    bool                      isSigned_ = false;

public:
    ApsInt() = delete;

    explicit ApsInt(bool isSigned) :
        isSigned_(isSigned)
    {
    }

    explicit ApsInt(uint32_t bitWidth, bool isSigned) :
        ApInt(bitWidth),
        isSigned_(isSigned)
    {
    }

    bool     isSigned() const { return isSigned_; }
    bool     equals(const ApsInt& other) const;
    uint64_t hash() const;

    static ApsInt getMinValue(uint32_t bitWidth, bool isSigned);
    static ApsInt getMaxValue(uint32_t bitWidth, bool isSigned);
    ApsInt        getMinValue() const;
    ApsInt        getMaxValue() const;
};

SWC_END_NAMESPACE()
