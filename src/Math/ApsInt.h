#pragma once
#include "Math/ApInt.h"

SWC_BEGIN_NAMESPACE()

class ApsInt : public ApInt
{
    static constexpr uint64_t ZERO      = 0;
    static constexpr uint64_t ONE       = 1;
    bool                      unsigned_ = false;

public:
    ApsInt() = delete;

    explicit ApsInt(const ApInt& value, bool isUnSigned) :
        ApInt(value),
        unsigned_(isUnSigned)
    {
    }

    explicit ApsInt(bool isUnSigned) :
        unsigned_(isUnSigned)
    {
    }

    explicit ApsInt(uint32_t bitWidth, bool isUnSigned) :
        ApInt(bitWidth),
        unsigned_(isUnSigned)
    {
    }

    bool isUnsigned() const { return unsigned_; }
    void setUnsigned(bool isUnSigned) { unsigned_ = isUnSigned; }

    static bool compareValues(const ApsInt& i1, const ApsInt& i2);
    static bool isSameValue(const ApsInt& i1, const ApsInt& i2);

    uint64_t hash() const;
    bool     same(const ApsInt& other) const;

    static ApsInt minValue(uint32_t bitWidth, bool isUnsigned);
    static ApsInt maxValue(uint32_t bitWidth, bool isUnsigned);

    void resize(uint32_t newBits)
    {
        if (unsigned_)
            resizeUnsigned(newBits);
        else
            resizeSigned(newBits);
    }

    bool operator<(const ApsInt& rhs) const
    {
        SWC_ASSERT(unsigned_ == rhs.unsigned_);
        return unsigned_ ? ult(rhs) : slt(rhs);
    }

    bool operator>(const ApsInt& rhs) const
    {
        SWC_ASSERT(unsigned_ == rhs.unsigned_);
        return unsigned_ ? ugt(rhs) : sgt(rhs);
    }

    bool operator<=(const ApsInt& rhs) const
    {
        SWC_ASSERT(unsigned_ == rhs.unsigned_);
        return unsigned_ ? ule(rhs) : sle(rhs);
    }

    bool operator>=(const ApsInt& rhs) const
    {
        SWC_ASSERT(unsigned_ == rhs.unsigned_);
        return unsigned_ ? uge(rhs) : sge(rhs);
    }

    bool operator==(const ApsInt& rhs) const
    {
        SWC_ASSERT(unsigned_ == rhs.unsigned_);
        return eq(rhs);
    }

    bool operator!=(const ApsInt& rhs) const
    {
        return ne(rhs);
    }
};

SWC_END_NAMESPACE()
