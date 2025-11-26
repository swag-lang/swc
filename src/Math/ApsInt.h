#pragma once
#include "Math/ApInt.h"

SWC_BEGIN_NAMESPACE()

class ApsInt : public ApInt
{
    static constexpr uint64_t ZERO        = 0;
    static constexpr uint64_t ONE         = 1;
    bool                      isUnsigned_ = false;

public:
    ApsInt() = delete;

    explicit ApsInt(const ApInt& value, bool isUnSigned) :
        ApInt(value),
        isUnsigned_(isUnSigned)
    {
    }

    explicit ApsInt(bool isUnSigned) :
        isUnsigned_(isUnSigned)
    {
    }

    explicit ApsInt(uint32_t bitWidth, bool isUnSigned) :
        ApInt(bitWidth),
        isUnsigned_(isUnSigned)
    {
    }

    bool isUnsigned() const { return isUnsigned_; }
    void setUnsigned(bool isUnSigned) { isUnsigned_ = isUnSigned; }

    static bool compareValues(const ApsInt& i1, const ApsInt& i2);
    static bool isSameValue(const ApsInt& i1, const ApsInt& i2);

    uint64_t hash() const;

    static ApsInt getMinValue(uint32_t bitWidth, bool isUnsigned);
    static ApsInt getMaxValue(uint32_t bitWidth, bool isUnsigned);
};

SWC_END_NAMESPACE()
