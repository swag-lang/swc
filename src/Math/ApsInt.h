#pragma once
#include "Math/ApInt.h"

SWC_BEGIN_NAMESPACE()

class ApsInt : public ApInt
{
protected:
    static constexpr uint64_t ZERO      = 0;
    static constexpr uint64_t ONE       = 1;
    bool                      unsigned_ = false;

public:
    ApsInt() = delete;

    explicit ApsInt(int32_t value) :
        ApInt(value)
    {
    }

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
    void setSigned(bool isSigned) { unsigned_ = !isSigned; }

    void    add(const ApsInt& rhs, bool& overflow);
    void    sub(const ApsInt& rhs, bool& overflow);
    void    mul(const ApsInt& rhs, bool& overflow);
    int64_t div(const ApsInt& rhs, bool& overflow);

    bool     same(const ApsInt& other) const;
    int      compare(const ApsInt& other) const;
    uint32_t hash() const;

    static ApsInt minValue(uint32_t bitWidth, bool isUnsigned);
    static ApsInt maxValue(uint32_t bitWidth, bool isUnsigned);

    void resize(uint32_t newBits);

    bool eq(const ApsInt& rhs) const;
    bool lt(const ApsInt& rhs) const;
    bool le(const ApsInt& rhs) const;
    bool gt(const ApsInt& rhs) const;
    bool ge(const ApsInt& rhs) const;

    Utf8 toString() const;
};

SWC_END_NAMESPACE()
