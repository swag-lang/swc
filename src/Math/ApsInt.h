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
    ApsInt() = default;

    explicit ApsInt(int64_t value, uint32_t bitWidth, bool isUnsigned) :
        ApInt(std::bit_cast<uint64_t>(value), bitWidth),
        unsigned_(isUnsigned)
    {
    }

    explicit ApsInt(const ApInt& value, bool isUnsigned) :
        ApInt(value),
        unsigned_(isUnsigned)
    {
    }

    explicit ApsInt(uint32_t bitWidth, bool isUnsigned) :
        ApInt(bitWidth),
        unsigned_(isUnsigned)
    {
    }

    static ApsInt makeSigned32(int32_t val) { return ApsInt(val, 32, false); }
    static ApsInt makeSigned64(int64_t val) { return ApsInt(val, 64, false); }
    static ApsInt makeUnsigned32(uint32_t val) { return ApsInt(val, 32, true); }
    static ApsInt makeUnsigned64(uint64_t val) { return ApsInt(val, 64, true); }

    bool isUnsigned() const { return unsigned_; }
    void setUnsigned(bool isUnsigned) { unsigned_ = isUnsigned; }
    void setSigned(bool isSigned) { unsigned_ = !isSigned; }

    void    add(const ApsInt& rhs, bool& overflow);
    void    sub(const ApsInt& rhs, bool& overflow);
    void    mul(const ApsInt& rhs, bool& overflow);
    int64_t div(const ApsInt& rhs, bool& overflow);
    void    mod(const ApsInt& rhs, bool& overflow);
    void    shiftLeft(uint64_t amount, bool& overflow);
    void    shiftRight(uint64_t amount);

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

    Utf8    toString() const;
    bool    fits64() const;
    int64_t asI64() const;
};

SWC_END_NAMESPACE()
