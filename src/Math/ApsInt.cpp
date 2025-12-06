#include "pch.h"
#include "Math/ApsInt.h"
#include "Math/Hash.h"

SWC_BEGIN_NAMESPACE()

uint32_t ApsInt::hash() const
{
    uint32_t h = ApInt::hash();
    h          = Math::hashCombine(h, unsigned_);
    return h;
}

ApsInt ApsInt::minValue(uint32_t bitWidth, bool isUnsigned)
{
    return isUnsigned ? ApsInt(ApInt::minValue(bitWidth), true) : ApsInt(minSignedValue(bitWidth), false);
}

ApsInt ApsInt::maxValue(uint32_t bitWidth, bool isUnsigned)
{
    return isUnsigned ? ApsInt(ApInt::maxValue(bitWidth), true) : ApsInt(maxSignedValue(bitWidth), false);
}

void ApsInt::resize(uint32_t newBits)
{
    if (unsigned_)
        resizeUnsigned(newBits);
    else
        resizeSigned(newBits);
}

bool ApsInt::same(const ApsInt& other) const
{
    if (unsigned_ != other.unsigned_)
        return false;
    return ApInt::same(other);
}

int ApsInt::compare(const ApsInt& other) const
{
    if (unsigned_ != other.unsigned_)
        return unsigned_ ? -1 : 1;
    return ApInt::compare(other);
}

bool ApsInt::eq(const ApsInt& rhs) const
{
    SWC_ASSERT(unsigned_ == rhs.unsigned_);
    return ApInt::eq(rhs);
}

bool ApsInt::lt(const ApsInt& rhs) const
{
    SWC_ASSERT(unsigned_ == rhs.unsigned_);
    return unsigned_ ? ult(rhs) : slt(rhs);
}

bool ApsInt::le(const ApsInt& rhs) const
{
    SWC_ASSERT(unsigned_ == rhs.unsigned_);
    return unsigned_ ? ule(rhs) : sle(rhs);
}

bool ApsInt::gt(const ApsInt& rhs) const
{
    SWC_ASSERT(unsigned_ == rhs.unsigned_);
    return unsigned_ ? ugt(rhs) : sgt(rhs);
}

bool ApsInt::ge(const ApsInt& rhs) const
{
    SWC_ASSERT(unsigned_ == rhs.unsigned_);
    return unsigned_ ? uge(rhs) : sge(rhs);
}

Utf8 ApsInt::toString() const
{
    if (unsigned_)
        return ApInt::toString();
    return toSignedString();
}

namespace
{
    ApInt& toAp(ApsInt& v)
    {
        return static_cast<ApInt&>(v);
    }

    const ApInt& toAp(const ApsInt& v)
    {
        return static_cast<const ApInt&>(v);
    }
}

void ApsInt::add(const ApsInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    SWC_ASSERT(unsigned_ == rhs.unsigned_);

    if (unsigned_)
    {
        ApInt::add(rhs, overflow);
        return;
    }

    // Signed two's-complement add.
    const bool lhsNeg = isNegative();
    const bool rhsNeg = rhs.isNegative();

    bool unsignedOverflow = false;
    ApInt::add(rhs, unsignedOverflow);

    const bool resNeg         = isNegative();
    const bool signedOverflow = (lhsNeg == rhsNeg) && (resNeg != lhsNeg);
    overflow                  = unsignedOverflow || signedOverflow;
}

void ApsInt::sub(const ApsInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    SWC_ASSERT(unsigned_ == rhs.unsigned_);

    if (unsigned_)
    {
        ApInt::sub(rhs, overflow);
        return;
    }

    // Signed subtraction: a - b.
    const bool lhsNeg = isNegative();
    const bool rhsNeg = rhs.isNegative();

    bool unsignedOverflow = false;
    ApInt::sub(rhs, unsignedOverflow);

    const bool resNeg         = isNegative();
    const bool signedOverflow = (lhsNeg != rhsNeg) && (resNeg != lhsNeg);
    overflow                  = unsignedOverflow || signedOverflow;
}

void ApsInt::mul(const ApsInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    SWC_ASSERT(unsigned_ == rhs.unsigned_);

    if (unsigned_)
    {
        ApInt::mul(rhs, overflow);
        return;
    }

    const uint32_t w = bitWidth_;
    SWC_ASSERT(w > 0);

    const bool lhsNeg    = isNegative();
    const bool rhsNeg    = rhs.isNegative();
    const bool resultNeg = lhsNeg ^ rhsNeg;

    // --- 1) Compute magnitudes |lhs| and |rhs| in the same width ---

    ApInt magLhs = *this;
    ApInt magRhs = rhs;

    auto makeMagnitude = [](ApInt& v, bool isNeg) {
        if (!isNeg)
            return;
        // Two's complement magnitude: |x| = (~x + 1) for negative x.
        v.invertAllBits();
        bool dummyOverflow = false;
        v.add(1, dummyOverflow); // ignore: we're treating as unsigned magnitude
    };

    makeMagnitude(magLhs, lhsNeg);
    makeMagnitude(magRhs, rhsNeg);

    // --- 2) Unsigned multiply of magnitudes in w bits ---

    bool unsignedOverflow = false;
    magLhs.mul(magRhs, unsignedOverflow); // magLhs now holds |lhs * rhs| mod 2^w

    // --- 3) Detect signed overflow ---

    overflow = false;

    // max positive signed value:  0b0111...111 =  2^(w-1) - 1
    const ApInt limitPos = maxSignedValue(w);

    // pattern 1000...000 = 2^(w-1), magnitude of min signed value
    const ApInt limitNeg = minSignedValue(w);

    if (!resultNeg)
    {
        // Positive result: |prod| must be <= 2^(w-1)-1.
        if (unsignedOverflow || magLhs.ugt(limitPos))
            overflow = true;
    }
    else
    {
        // Negative result: |prod| must be <= 2^(w-1).
        if (unsignedOverflow || magLhs.ugt(limitNeg))
            overflow = true;
    }

    // --- 4) Apply sign and store result (mod 2^w) in *this ---

    if (resultNeg)
    {
        // prod = -|prod|  in two's complement, in-place, width w.
        ApInt negProd = magLhs;
        negProd.invertAllBits();
        bool dummyOverflow = false;
        negProd.add(1, dummyOverflow); // ignore overflow; arithmetic is modulo 2^w
        toAp(*this) = negProd;
    }
    else
    {
        // prod = |prod|
        toAp(*this) = magLhs;
    }
}

// Return value is signed remainder (same sign as dividend for a signed case).
// overflow is set for the single true signed overflow case: min / -1.
int64_t ApsInt::div(const ApsInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    SWC_ASSERT(unsigned_ == rhs.unsigned_);
    SWC_ASSERT(!rhs.isZero());

    overflow = false;

    if (unsigned_)
    {
        // Unsigned division uses ApInt's semantics.
        const uint64_t rem = toAp(*this).div(toAp(rhs));

        // No overflow possible in unsigned division (aside from div-by-zero, asserted above).
        overflow = false;

        // The remainder is non-negative and < divisor; fit into int64_t is guaranteed
        // as long as your types stay <= 63 bits. Assert to be safe.
        SWC_ASSERT(rem <= static_cast<uint64_t>(std::numeric_limits<int64_t>::max()));
        return static_cast<int64_t>(rem);
    }

    // Signed division.
    const bool lhsNeg    = isNegative();
    const bool rhsNeg    = rhs.isNegative();
    const bool resultNeg = lhsNeg ^ rhsNeg;

    // Detect the single signed overflow case: MIN / -1
    // (result would be +2^(w-1), which can't be represented).
    const ApsInt minVal = minValue(bitWidth_, /*isUnsigned*/ false);
    const ApsInt minusOne(toAp(ApsInt::maxValue(bitWidth_, false)), false); // not used; build properly below

    // Build -1 of this signed width.
    ApsInt negOne(bitWidth_, false);
    toAp(negOne).setAllBits(); // all ones is -1 in two's complement.

    if (!unsigned_ && same(minVal) && rhs.same(negOne))
    {
        // Overflow: leave *this as-is or set to minVal; here we keep minVal.
        overflow = true;
        // Quotient is mathematically +2^(w-1), not representable; we keep minVal.
        return 0; // the remainder is 0 in that case.
    }

    // Work on magnitudes using ApInt. We treat the underlying bits as two's
    // complement and compute |x| via (~x + 1) for negatives. For minSigned
    // this gives the correct magnitude as an *unsigned* value.
    ApInt magLhs = toAp(*this);
    ApInt magRhs = toAp(rhs);

    auto makeMagnitude = [](ApInt& v, bool isNeg) {
        if (!isNeg)
            return;

        v.invertAllBits();
        bool dummyOverflow = false;
        v.add(1, dummyOverflow); // ignore overflow: we're treating it as unsigned magnitude.
    };

    makeMagnitude(magLhs, lhsNeg);
    makeMagnitude(magRhs, rhsNeg);

    // Unsigned magnitude division: magLhs = magLhs / magRhs, remMag is remainder >= 0.
    const uint64_t remMag = magLhs.div(magRhs);

    // magLhs now holds magnitude of quotient. Apply sign to quotient.
    if (resultNeg)
    {
        magLhs.invertAllBits();
        bool dummyOverflow = false;
        magLhs.add(1, dummyOverflow); // again, overflow here would mean we exceeded width,
                                      // which can't happen except in the MIN/-1 case we already handled.
    }

    // Write quotient back.
    toAp(*this) = magLhs;

    // Build signed remainder: same sign as original dividend (C/C++ semantics).
    int64_t signedRem = 0;
    if (remMag == 0)
    {
        signedRem = 0;
    }
    else if (!lhsNeg)
    {
        // Positive dividend => positive remainder.
        SWC_ASSERT(remMag <= static_cast<uint64_t>(std::numeric_limits<int64_t>::max()));
        signedRem = static_cast<int64_t>(remMag);
    }
    else
    {
        // Negative dividend => negative remainder.
        SWC_ASSERT(remMag <= static_cast<uint64_t>(std::numeric_limits<int64_t>::max()));
        signedRem = -static_cast<int64_t>(remMag);
    }

    // No further overflow possible here.
    overflow = false;
    return signedRem;
}

SWC_END_NAMESPACE()
