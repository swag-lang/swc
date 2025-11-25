#pragma once
#include "Math/ApInt.h"

SWC_BEGIN_NAMESPACE()

class ApsInt : public ApInt
{
    bool isSigned_ = false;

public:
    ApsInt() = delete;

    explicit ApsInt(bool isSigned) :
        ApInt(),
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
};

SWC_END_NAMESPACE()
