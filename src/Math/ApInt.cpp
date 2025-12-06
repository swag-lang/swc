#include "pch.h"
#include "Math/ApInt.h"
#include "Math/Hash.h"
#include "Math/Helpers.h"

SWC_BEGIN_NAMESPACE()

void ApInt::clearWords()
{
    std::fill_n(words_, numWords_, ZERO);
}

uint32_t ApInt::computeNumWords(uint32_t bitWidth)
{
    SWC_ASSERT(bitWidth > 0 && bitWidth <= MAX_BITS);
    return static_cast<uint32_t>((bitWidth + WORD_BITS - 1) / WORD_BITS);
}

void ApInt::normalize()
{
    if (bitWidth_ == 0)
        return;

    const uint64_t usedBitsInLastWord = bitWidth_ % WORD_BITS;
    if (usedBitsInLastWord != 0)
    {
        const uint64_t mask = (ONE << usedBitsInLastWord) - 1;
        words_[numWords_ - 1] &= mask;
    }
}

bool ApInt::hasTopBitsOverflow() const
{
    SWC_ASSERT(numWords_ && bitWidth_);

    const uint64_t usedBitsInLastWord = bitWidth_ % WORD_BITS;
    if (usedBitsInLastWord == 0)
        return false;

    const uint64_t mask = (ONE << usedBitsInLastWord) - 1;
    const uint64_t last = words_[numWords_ - 1];
    return (last & ~mask) != 0;
}

ApInt::ApInt() :
    ApInt(MAX_BITS)
{
}

ApInt::ApInt(uint32_t bitWidth) :
    bitWidth_(bitWidth),
    numWords_(computeNumWords(bitWidth))
{
    SWC_ASSERT(bitWidth <= MAX_BITS);
    clearWords();
    normalize();
}

ApInt::ApInt(uint64_t value, uint32_t bitWidth) :
    bitWidth_(bitWidth),
    numWords_(computeNumWords(bitWidth))
{
    SWC_ASSERT(bitWidth <= MAX_BITS);
    clearWords();
    words_[0] = value;
    normalize();
}

ApInt::ApInt(int32_t value) :
    bitWidth_(32),
    numWords_(computeNumWords(32))
{
    clearWords();
    words_[0] = std::bit_cast<uint64_t>(static_cast<int64_t>(value));
    normalize();
}

bool ApInt::fits64() const
{
    for (uint32_t i = 1; i < numWords_; ++i)
    {
        if (words_[i] != 0)
            return false;
    }

    return true;
}

uint64_t ApInt::asU64() const
{
    SWC_ASSERT(fits64());

    if (bitWidth_ < WORD_BITS)
    {
        const uint64_t mask = (ONE << bitWidth_) - 1;
        return words_[0] & mask;
    }

    return words_[0];
}

bool ApInt::same(const ApInt& other) const
{
    if (bitWidth_ != other.bitWidth_)
        return false;
    SWC_ASSERT(numWords_ == other.numWords_);
    return std::equal(words_, words_ + numWords_, other.words_);
}

int ApInt::compare(const ApInt& other) const
{
    SWC_ASSERT(bitWidth_ == other.bitWidth_);
    SWC_ASSERT(numWords_ == other.numWords_);

    for (int i = static_cast<int>(numWords_) - 1; i >= 0; --i)
    {
        const uint64_t a = words_[static_cast<uint32_t>(i)];
        const uint64_t b = other.words_[static_cast<uint32_t>(i)];
        if (a < b)
            return -1;
        if (a > b)
            return 1;
    }

    return 0;
}

uint32_t ApInt::hash() const
{
    uint32_t h = Math::hash(bitWidth_);
    for (uint64_t i = 0; i < numWords_; ++i)
        h = Math::hashCombine(h, words_[i]);
    return h;
}

bool ApInt::isZero() const
{
    return std::all_of(words_, words_ + numWords_, [](uint64_t w) { return w == 0; });
}

void ApInt::setZero()
{
    clearWords();
}

void ApInt::logicalShiftLeft(uint64_t amount, bool& overflow)
{
    overflow = false;

    if (amount == 0)
        return;

    if (amount >= bitWidth_)
    {
        // Everything is shifted out: overflow if any bit was set
        overflow = !isZero();
        setZero();
        return;
    }

    const uint64_t wordShift = amount / WORD_BITS;
    const uint64_t bitShift  = amount % WORD_BITS;

    // Word-shift overflow check: words that will be completely shifted out
    if (wordShift > 0)
    {
        for (uint64_t i = numWords_ - wordShift; i < numWords_; ++i)
        {
            if (words_[i] != 0)
            {
                overflow = true;
                break;
            }
        }
    }

    // Word shift
    if (wordShift > 0)
    {
        for (uint64_t i = numWords_; i-- > wordShift;)
            words_[i] = words_[i - wordShift];
        for (uint64_t i = 0; i < wordShift; ++i)
            words_[i] = 0;
    }

    // Bit shift with carry
    if (bitShift > 0)
    {
        uint64_t carry = 0;
        for (uint64_t i = 0; i < numWords_; ++i)
        {
            const uint64_t newCarry = words_[i] >> (WORD_BITS - bitShift);
            words_[i]               = (words_[i] << bitShift) | carry;
            carry                   = newCarry;
        }

        if (carry != 0)
            overflow = true;
    }

    normalize();
}

void ApInt::logicalShiftRight(uint64_t amount)
{
    if (amount == 0 || isZero())
        return;

    const uint64_t wordShift = amount / WORD_BITS;
    const uint64_t bitShift  = amount % WORD_BITS;

    if (wordShift >= numWords_)
    {
        setZero();
        return;
    }

    if (wordShift > 0)
    {
        for (uint32_t i = 0; i < numWords_ - wordShift; ++i)
            words_[i] = words_[i + wordShift];
        for (uint32_t i = static_cast<uint32_t>(numWords_ - wordShift); i < numWords_; ++i)
            words_[i] = 0;
    }

    if (bitShift > 0)
    {
        uint64_t carry = 0;
        for (int i = static_cast<int>(numWords_) - 1; i >= 0; --i)
        {
            const uint64_t newCarry = words_[i] << (WORD_BITS - bitShift);
            words_[i]               = (words_[i] >> bitShift) | carry;
            carry                   = newCarry;
        }
    }

    normalize();
}

void ApInt::add(uint64_t v, bool& overflow)
{
    SWC_ASSERT(numWords_);
    overflow = false;

    if (v == 0)
        return;

    uint64_t carry = v;
    for (uint64_t i = 0; i < numWords_; ++i)
    {
        const uint64_t oldWord  = words_[i];
        const uint64_t sum      = oldWord + carry;
        const uint64_t newCarry = (sum < oldWord) ? 1 : 0;
        words_[i]               = sum;
        carry                   = newCarry;
    }

    overflow = carry != 0 || hasTopBitsOverflow();
    normalize();
}

void ApInt::mul(uint64_t v, bool& overflow)
{
    SWC_ASSERT(numWords_);
    overflow = false;

    if (v == 0)
    {
        setZero();
        return;
    }

    uint64_t carry = 0;
    for (uint64_t i = 0; i < numWords_; ++i)
    {
        uint64_t low  = 0;
        uint64_t high = 0;

        Math::mul64X64(words_[i], v, low, high);
        carry += carry;
        if (carry < carry)
            ++high;

        words_[i] = low;
        carry     = high;
    }

    overflow = carry != 0 || hasTopBitsOverflow();
    normalize();
}

uint64_t ApInt::div(uint64_t v)
{
    SWC_ASSERT(v != 0);

    if (isZero())
        return 0;

    uint64_t rem = 0;
    for (int i = static_cast<int>(numWords_) - 1; i >= 0; --i)
    {
        const uint64_t word  = words_[i];
        uint64_t       qWord = 0;

        // Bit-by-bit long division in base 2, from MSB to LSB of this word
        for (int bit = static_cast<int>(WORD_BITS) - 1; bit >= 0; --bit)
        {
            // Bring down the next bit
            rem = (rem << 1) | ((word >> bit) & ONE);

            // Shift quotient and test if we can subtract divisor
            qWord <<= 1;
            if (rem >= v)
            {
                rem -= v;
                qWord |= 1;
            }
        }

        words_[i] = qWord;
    }

    normalize();
    return rem;
}

void ApInt::add(const ApInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    SWC_ASSERT(numWords_ == rhs.numWords_);

    overflow       = false;
    uint64_t carry = 0;

    for (uint32_t i = 0; i < numWords_; ++i)
    {
        const uint64_t a = words_[i];
        const uint64_t b = rhs.words_[i];

        const uint64_t sum1   = a + b;
        const uint64_t carry1 = (sum1 < a);

        const uint64_t sum2   = sum1 + carry;
        const uint64_t carry2 = (sum2 < sum1);

        words_[i] = sum2;
        carry     = carry1 | carry2;
    }

    overflow = (carry != 0) || hasTopBitsOverflow();
    normalize();
}

void ApInt::sub(const ApInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    SWC_ASSERT(numWords_ == rhs.numWords_);

    overflow        = false;
    uint64_t borrow = 0;

    for (uint32_t i = 0; i < numWords_; ++i)
    {
        const uint64_t a = words_[i];
        const uint64_t b = rhs.words_[i];
        const uint64_t t = b + borrow;

        const uint64_t result = a - t;
        borrow                = (a < t);

        words_[i] = result;
    }

    overflow = (borrow != 0);
    normalize();
}

void ApInt::mul(const ApInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    SWC_ASSERT(numWords_ == rhs.numWords_);

    const uint32_t n = numWords_;
    overflow         = false;

    SWC_ASSERT(2 * n <= 2 * static_cast<uint32_t>(MAX_WORDS));
    uint64_t tmp[2 * MAX_WORDS] = {};

    for (uint32_t i = 0; i < n; ++i)
    {
        uint64_t carry = 0;

        for (uint32_t j = 0; j < n; ++j)
        {
            uint64_t low = 0, high = 0;
            Math::mul64X64(words_[i], rhs.words_[j], low, high);

            // add low + carry + tmp[i + j]
            const uint64_t old = tmp[i + j];
            const uint64_t sum = old + low + carry;

            // detect carries
            const uint64_t c1 = (sum < old);
            const uint64_t c2 = (sum < low);

            tmp[i + j] = sum;
            carry      = high + c1 + c2;
        }

        tmp[i + n] += carry;
    }

    // copy lower n limbs into this ApInt
    for (uint32_t i = 0; i < n; ++i)
        words_[i] = tmp[i];

    // overflow if upper n limbs nonzero OR top bits overflow width
    for (uint32_t i = n; i < 2 * n; ++i)
        if (tmp[i] != 0)
            overflow = true;

    if (hasTopBitsOverflow())
        overflow = true;

    normalize();
}

uint64_t ApInt::div(const ApInt& rhs)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    SWC_ASSERT(!rhs.isZero());

    // If divisor fits in 64 bits, use the optimized version.
    if (rhs.fits64())
        return div(rhs.asU64());

    const uint32_t totalBits = bitWidth_;

    // remainder stored as same width ApInt
    ApInt rem(bitWidth_);
    rem.setZero();

    const ApInt divisor(rhs);
    ApInt       quotient(bitWidth_);
    quotient.setZero();

    // bit-by-bit long division
    for (int bit = static_cast<int>(totalBits) - 1; bit >= 0; --bit)
    {
        // rem <<= 1
        bool ov = false;
        rem.logicalShiftLeft(1, ov);

        // bring next bit from dividend
        if (testBit(bit))
            rem.words_[0] |= 1; // MSB shift already done

        // if rem >= divisor -> quotient bit = 1, rem -= divisor
        if (!rem.ult(divisor))
        {
            rem.sub(divisor, ov);
            quotient.setBit(bit);
        }
    }

    // write quotient back to this ApInt
    *this = quotient;

    // return the remainder as 64-bit (assert it fits)
    SWC_ASSERT(rem.fits64());
    return rem.asU64();
}

void ApInt::addSigned(const ApInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);

    // Signed two's-complement add.
    const bool lhsNeg = isNegative();
    const bool rhsNeg = rhs.isNegative();

    bool unsignedOverflow = false;
    ApInt::add(rhs, unsignedOverflow);

    const bool resNeg         = isNegative();
    const bool signedOverflow = (lhsNeg == rhsNeg) && (resNeg != lhsNeg);
    overflow                  = unsignedOverflow || signedOverflow;
}

void ApInt::subSigned(const ApInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);

    // Signed subtraction: a - b.
    const bool lhsNeg = isNegative();
    const bool rhsNeg = rhs.isNegative();

    bool unsignedOverflow = false;
    sub(rhs, unsignedOverflow);

    const bool resNeg         = isNegative();
    const bool signedOverflow = (lhsNeg != rhsNeg) && (resNeg != lhsNeg);
    overflow                  = unsignedOverflow || signedOverflow;
}

void ApInt::mulSigned(const ApInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);

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
        // prod = -|prod| in two's complement, in-place, width w.
        ApInt negProd = magLhs;
        negProd.invertAllBits();
        bool dummyOverflow = false;
        negProd.add(1, dummyOverflow); // ignore overflow; arithmetic is modulo 2^w
        *this = negProd;
    }
    else
    {
        // prod = |prod|
        *this = magLhs;
    }
}

// Return value is signed remainder (same sign as dividend for a signed case).
// overflow is set for the single true signed overflow case: min / -1.
int64_t ApInt::divSigned(const ApInt& rhs, bool& overflow)
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    SWC_ASSERT(!rhs.isZero());

    overflow = false;

    // Signed division.
    const bool lhsNeg    = isNegative();
    const bool rhsNeg    = rhs.isNegative();
    const bool resultNeg = lhsNeg ^ rhsNeg;

    // Detect the single signed overflow case: MIN / -1
    // (result would be +2^(w-1), which can't be represented).
    const ApInt minVal = minValue(bitWidth_);

    // Build -1 of this signed width.
    ApInt negOne(bitWidth_);
    negOne.setAllBits(); // all ones is -1 in two's complement.

    if (same(minVal) && rhs.same(negOne))
    {
        // Overflow: leave *this as-is or set to minVal; here we keep minVal.
        overflow = true;
        // Quotient is mathematically +2^(w-1), not representable; we keep minVal.
        return 0; // the remainder is 0 in that case.
    }

    // Work on magnitudes using ApInt. We treat the underlying bits as two's
    // complement and compute |x| via (~x + 1) for negatives. For minSigned
    // this gives the correct magnitude as an *unsigned* value.
    ApInt magLhs = *this;
    ApInt magRhs = rhs;

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
    *this = magLhs;

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

void ApInt::bitwiseOr(uint64_t rhs)
{
    SWC_ASSERT(numWords_ && bitWidth_);
    if (rhs == 0)
        return;

    if (bitWidth_ < WORD_BITS)
    {
        const uint64_t mask = (ONE << bitWidth_) - 1;
        rhs &= mask;
    }

    words_[0] |= rhs;
    normalize();
}

bool ApInt::testBit(uint64_t bitIndex) const
{
    SWC_ASSERT(bitIndex < bitWidth_);
    const uint64_t wordIndex = bitIndex / WORD_BITS;
    const uint64_t bitInWord = bitIndex % WORD_BITS;
    SWC_ASSERT(wordIndex < numWords_);
    return (words_[wordIndex] >> bitInWord) & 1;
}

void ApInt::setBit(uint64_t bitIndex)
{
    SWC_ASSERT(bitIndex < bitWidth_);
    const uint64_t wordIndex = bitIndex / WORD_BITS;
    const uint64_t bitInWord = bitIndex % WORD_BITS;
    SWC_ASSERT(wordIndex < numWords_);
    words_[wordIndex] |= (ONE << bitInWord);
}

void ApInt::setAllBits()
{
    std::fill_n(words_, numWords_, ~ZERO);
    normalize();
}

void ApInt::invertAllBits()
{
    for (uint32_t i = 0; i < numWords_; ++i)
        words_[i] = ~words_[i];
    normalize();
}

void ApInt::clearBit(uint64_t bitIndex)
{
    SWC_ASSERT(bitIndex < bitWidth_);
    const uint64_t wordIndex = bitIndex / WORD_BITS;
    const uint64_t bitInWord = bitIndex % WORD_BITS;
    SWC_ASSERT(wordIndex < numWords_);
    words_[wordIndex] &= ~(ONE << bitInWord);
}

bool ApInt::isSignBitSet() const
{
    SWC_ASSERT(bitWidth_ > 0);
    const uint64_t msb = bitWidth_ - 1;
    return testBit(msb);
}

bool ApInt::isSignBitClear() const
{
    return !isSignBitSet();
}

bool ApInt::isNegative() const
{
    return isSignBitSet();
}

bool ApInt::isNonNegative() const
{
    return !isSignBitSet();
}

bool ApInt::isStrictlyPositive() const
{
    return isNonNegative() && !isZero();
}

bool ApInt::isNonPositive() const
{
    return isNegative() || isZero();
}

uint64_t ApInt::getSignBit() const
{
    return isSignBitSet() ? ONE : ZERO;
}

void ApInt::setSignBit(bool isNegative)
{
    const uint64_t signIndex = bitWidth_ - 1;
    if (isNegative)
        setBit(signIndex);
    else
        clearBit(signIndex);
}

namespace
{
    ApInt makeMinValue(uint32_t bitWidth)
    {
        ApInt result(bitWidth);
        result.setZero();
        return result;
    }

    ApInt makeMinSignedValue(uint32_t bitWidth)
    {
        ApInt result(bitWidth);
        result.setZero();
        result.setBit(bitWidth - 1);
        return result;
    }

    ApInt makeMaxValue(uint32_t bitWidth)
    {
        ApInt result(bitWidth);
        result.setAllBits();
        return result;
    }

    ApInt makeMaxSignedValue(uint32_t bitWidth)
    {
        ApInt result(bitWidth);
        result.setAllBits();
        result.clearBit(bitWidth - 1);
        return result;
    }
}

ApInt ApInt::minValue(uint32_t bitWidth)
{
    static const ApInt U8   = makeMinValue(8);
    static const ApInt U16  = makeMinValue(16);
    static const ApInt U32  = makeMinValue(32);
    static const ApInt U64  = makeMinValue(64);
    static const ApInt U128 = makeMinValue(128);

    switch (bitWidth)
    {
        case 8: return U8;
        case 16: return U16;
        case 32: return U32;
        case 64: return U64;
        case 128: return U128;
        default: return makeMinValue(bitWidth);
    }
}

ApInt ApInt::minSignedValue(uint32_t bitWidth)
{
    static const ApInt S8   = makeMinSignedValue(8);
    static const ApInt S16  = makeMinSignedValue(16);
    static const ApInt S32  = makeMinSignedValue(32);
    static const ApInt S64  = makeMinSignedValue(64);
    static const ApInt S128 = makeMinSignedValue(128);

    switch (bitWidth)
    {
        case 8: return S8;
        case 16: return S16;
        case 32: return S32;
        case 64: return S64;
        case 128: return S128;
        default: return makeMinSignedValue(bitWidth);
    }
}

ApInt ApInt::maxValue(uint32_t bitWidth)
{
    static const ApInt U8   = makeMaxValue(8);
    static const ApInt U16  = makeMaxValue(16);
    static const ApInt U32  = makeMaxValue(32);
    static const ApInt U64  = makeMaxValue(64);
    static const ApInt U128 = makeMaxValue(128);

    switch (bitWidth)
    {
        case 8: return U8;
        case 16: return U16;
        case 32: return U32;
        case 64: return U64;
        case 128: return U128;
        default: return makeMaxValue(bitWidth);
    }
}

ApInt ApInt::maxSignedValue(uint32_t bitWidth)
{
    static const ApInt S8   = makeMaxSignedValue(8);
    static const ApInt S16  = makeMaxSignedValue(16);
    static const ApInt S32  = makeMaxSignedValue(32);
    static const ApInt S64  = makeMaxSignedValue(64);
    static const ApInt S128 = makeMaxSignedValue(128);

    switch (bitWidth)
    {
        case 8: return S8;
        case 16: return S16;
        case 32: return S32;
        case 64: return S64;
        case 128: return S128;
        default: return makeMaxSignedValue(bitWidth);
    }
}

bool ApInt::eq(const ApInt& rhs) const
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    return same(rhs);
}

bool ApInt::ne(const ApInt& rhs) const
{
    return !eq(rhs);
}

bool ApInt::ult(const ApInt& rhs) const
{
    return compare(rhs) < 0;
}

bool ApInt::ule(const ApInt& rhs) const
{
    return !rhs.ult(*this);
}

bool ApInt::ugt(const ApInt& rhs) const
{
    return rhs.ult(*this);
}

bool ApInt::uge(const ApInt& rhs) const
{
    return !ult(rhs);
}

bool ApInt::slt(const ApInt& rhs) const
{
    SWC_ASSERT(bitWidth_ == rhs.bitWidth_);
    const bool lhsNeg = isNegative();
    const bool rhsNeg = rhs.isNegative();
    if (lhsNeg != rhsNeg)
        return lhsNeg;
    return compare(rhs) < 0;
}

bool ApInt::sle(const ApInt& rhs) const
{
    return !rhs.slt(*this);
}

bool ApInt::sgt(const ApInt& rhs) const
{
    return rhs.slt(*this);
}

bool ApInt::sge(const ApInt& rhs) const
{
    return !slt(rhs);
}

void ApInt::shrink(uint32_t newBitWidth)
{
    SWC_ASSERT(newBitWidth > 0);
    SWC_ASSERT(newBitWidth <= bitWidth_);

    if (newBitWidth == bitWidth_)
        return;

    const uint32_t newNumWords = computeNumWords(newBitWidth);

    // Update bitWidth and word count
    bitWidth_ = newBitWidth;
    numWords_ = newNumWords;

    // Mask off unused high bits of the last word
    normalize();
}

// In-place zero-extend or truncate.
void ApInt::resizeUnsigned(uint32_t newBitWidth)
{
    SWC_ASSERT(newBitWidth > 0);

    if (newBitWidth == bitWidth_)
        return;

    const uint32_t oldBitWidth = bitWidth_;
    const uint32_t oldNumWords = numWords_;
    const uint32_t newNumWords = computeNumWords(newBitWidth);

    if (newBitWidth < oldBitWidth)
    {
        // Truncation: just shrink metadata and mask the new top word.
        bitWidth_ = newBitWidth;
        numWords_ = newNumWords;
        normalize();
        return;
    }

    // Zero-extension.
    // Make sure any newly used words are cleared.
    if (newNumWords > oldNumWords)
        std::fill(words_ + oldNumWords, words_ + newNumWords, ZERO);

    bitWidth_ = newBitWidth;
    numWords_ = newNumWords;

    // Ensure bits above newBitWidth are cleared in the last word.
    normalize();
}

// In-place sign-extend or truncate.
void ApInt::resizeSigned(uint32_t newBitWidth)
{
    SWC_ASSERT(newBitWidth > 0);

    if (newBitWidth == bitWidth_)
        return;

    const uint32_t oldBitWidth = bitWidth_;
    const uint32_t oldNumWords = numWords_;
    const uint32_t newNumWords = computeNumWords(newBitWidth);

    if (newBitWidth < oldBitWidth)
    {
        // Truncation: same as unsigned; sign is not preserved when shrinking.
        bitWidth_ = newBitWidth;
        numWords_ = newNumWords;
        normalize();
        return;
    }

    // Extension.
    const bool sign = isSignBitSet();

    if (!sign)
    {
        // Positive value: sign extension == zero extension.
        if (newNumWords > oldNumWords)
            std::fill(words_ + oldNumWords, words_ + newNumWords, ZERO);
    }
    else
    {
        // Negative value: replicate sign bit into the new high bits.

        const uint32_t usedBitsInLastWord = oldBitWidth % WORD_BITS;
        const uint32_t lastWordIndex      = oldNumWords - 1;

        // If the old type didn't use the entire last word, fill the remaining bits
        // in that word with 1s (they become part of the extended sign region).
        if (usedBitsInLastWord != 0)
        {
            const uint64_t mask = ~((ONE << usedBitsInLastWord) - 1); // bits [usedBitsInLastWord .. 63] = 1
            words_[lastWordIndex] |= mask;
        }

        // Any additional whole words that become newly visible should be all 1s.
        for (uint32_t i = oldNumWords; i < newNumWords; ++i)
            words_[i] = ~0ull;
    }

    bitWidth_ = newBitWidth;
    numWords_ = newNumWords;

    // Clear bits above the new bit width in the top word.
    normalize();
}

void ApInt::abs(bool& overflow)
{
    overflow = false;
    if (!isNegative())
        return;
    invertAllBits();
    add(1, overflow);
}

void ApInt::negate(bool& overflow)
{
    overflow = false;

    if (isZero())
        return;

    // If the value is the minimum signed value (1000...0),
    // then -x is not representable in the same bit width.
    bool isMinSigned = isSignBitSet();
    for (uint32_t i = 0; i < numWords_ - 1 && isMinSigned; ++i)
    {
        if (words_[i] != ZERO)
            isMinSigned = false;
    }

    if (isMinSigned)
    {
        overflow = true;
        return;
    }

    // Normal negation: x = ~x + 1
    invertAllBits();
    add(1, overflow);
}

Utf8 ApInt::toString() const
{
    // Treat the bits as an unsigned integer.
    if (isZero())
        return "0";

    ApInt       tmp(*this); // Work on a copy, since div() is in-place
    std::string result;

    while (!tmp.isZero())
    {
        const uint64_t rem = tmp.div(10); // tmp = tmp / 10, rem = tmp % 10
        SWC_ASSERT(rem < 10);
        result.push_back(static_cast<char>('0' + rem));
    }

    std::ranges::reverse(result);
    return result;
}

Utf8 ApInt::toSignedString() const
{
    // Interpret the value as a signed two's-complement integer.
    if (isZero())
        return "0";

    // Non-negative is just the unsigned representation.
    if (isNonNegative())
        return toString();

    // Negative number: need magnitude = |value|
    ApInt mag(bitWidth_);
    mag.setZero();

    // Detect minimum signed value: 1000...000 (sign bit = 1, others 0)
    bool isMinSigned = isSignBitSet();
    if (isMinSigned)
    {
        // Check all words except the last
        for (uint32_t i = 0; i < numWords_ - 1; ++i)
        {
            if (words_[i] != ZERO)
            {
                isMinSigned = false;
                break;
            }
        }

        // Check that the highest word has only the sign bit set
        if (isMinSigned)
        {
            const uint32_t bitsInLastWord = bitWidth_ % WORD_BITS;
            const uint32_t effectiveBits  = (bitsInLastWord == 0) ? WORD_BITS : bitsInLastWord;
            const uint64_t signBitMask    = UINT64_C(1) << (effectiveBits - 1);

            if (words_[numWords_ - 1] != signBitMask)
                isMinSigned = false;
        }
    }

    if (isMinSigned)
    {
        // |min| = 2^(bitWidth_-1)
        mag.setBit(bitWidth_ - 1);
    }
    else
    {
        // Normal case: mag = abs(this)
        mag           = *this;
        bool overflow = false;
        mag.abs(overflow);
        SWC_ASSERT(!overflow);
    }

    // Convert magnitude to decimal
    std::string digits;
    while (!mag.isZero())
    {
        const uint64_t rem = mag.div(10);
        SWC_ASSERT(rem < 10);
        digits.push_back(static_cast<char>('0' + rem));
    }

    std::ranges::reverse(digits);
    return "-" + digits;
}

SWC_END_NAMESPACE()
