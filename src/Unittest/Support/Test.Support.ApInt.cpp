#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Support/Math/ApInt.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    uint32_t standardWidthForPrecision(uint32_t bits)
    {
        for (const uint32_t width : {8u, 16u, 32u, 64u, 128u})
        {
            if (bits <= width)
                return width;
        }
        return 0;
    }

    bool normalizedQueriesMatchBits(const ApInt& value)
    {
        uint64_t   lowWord      = 0;
        uint32_t   setBits      = 0;
        uint32_t   unsignedBits = 1;
        uint32_t   signedBits   = 1;
        bool       hasUpperBits = false;
        const bool sign         = value.testBit(value.bitWidth() - 1);
        for (uint32_t bit = 0; bit < value.bitWidth(); ++bit)
        {
            const bool set = value.testBit(bit);
            if (set != sign)
                signedBits = bit + 2;
            if (!set)
                continue;
            unsignedBits = bit + 1;
            ++setBits;
            if (bit < 64)
                lowWord |= uint64_t{1} << bit;
            else
                hasUpperBits = true;
        }
        ApInt widened = value;
        widened.resize(ApInt::maxBitWidth());
        for (uint32_t bit = value.bitWidth(); bit < widened.bitWidth(); ++bit)
        {
            if (widened.testBit(bit))
                return false;
        }
        return value.as64() == lowWord && value.fit64() == !hasUpperBits && value.isPowerOf2() == (setBits == 1) &&
               value.minBits() == standardWidthForPrecision(unsignedBits) && value.minBitsSigned() == standardWidthForPrecision(signedBits) &&
               value.fit64Signed() == (signedBits <= 64);
    }
}

SWC_TEST_BEGIN(ApInt_ArithmeticShiftMatchesBitOracle)
{
    for (uint32_t width = 1; width <= ApInt::maxBitWidth(); ++width)
    {
        for (uint32_t pattern = 0; pattern < 5; ++pattern)
        {
            ApInt input(width);
            for (uint32_t bit = 0; bit < width; ++bit)
            {
                const bool set = pattern == 2 ||
                                 (pattern == 1 && bit == width - 1) ||
                                 (pattern == 3 && bit % 3 == 0) ||
                                 (pattern == 4 && bit == 0);
                if (set)
                    input.setBit(bit);
            }
            for (uint32_t shift = 0; shift <= width + 1; ++shift)
            {
                ApInt shifted = input;
                shifted.arithmeticShiftRight(shift);
                for (uint32_t bit = 0; bit < width; ++bit)
                {
                    const bool expected = bit + shift < width ? input.testBit(bit + shift) : input.isNegative();
                    if (shifted.testBit(bit) != expected)
                        return Result::Error;
                }
            }
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ApInt_SubtractionMatchesBitBorrowOracle)
{
    constexpr uint64_t max = std::numeric_limits<uint64_t>::max();

    constexpr std::array<std::array<uint64_t, 2>, 7> patterns = {{
        {0, 0},
        {1, 0},
        {max, 0},
        {0, 1},
        {1, max},
        {max, max},
        {max - 1, max},
    }};
    for (uint32_t width = 1; width <= ApInt::maxBitWidth(); ++width)
    {
        for (const auto& left : patterns)
        {
            for (const auto& right : patterns)
            {
                const ApInt lhs(left.data(), width);
                const ApInt rhs(right.data(), width);
                ApInt       expected(width);
                bool        borrow = false;
                for (uint32_t bit = 0; bit < width; ++bit)
                {
                    const bool a = lhs.testBit(bit);
                    const bool b = rhs.testBit(bit);
                    if (a ^ b ^ borrow)
                        expected.setBit(bit);
                    borrow = (!a && (b || borrow)) || (b && borrow);
                }
                ApInt actual   = lhs;
                bool  overflow = false;
                actual.sub(rhs, overflow);
                if (!actual.same(expected) || overflow != borrow)
                    return Result::Error;
            }
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ApInt_NormalizedQueriesMatchBitOracle)
{
    constexpr std::array<std::array<uint64_t, 2>, 4> patterns = {{
        {0, 0},
        {1, 0},
        {0xAAAAAAAAAAAAAAAA, 0x5555555555555555},
        {UINT64_MAX, UINT64_MAX},
    }};
    for (uint32_t width = 1; width <= ApInt::maxBitWidth(); ++width)
    {
        if (!normalizedQueriesMatchBits(ApInt::minValue(width)) ||
            !normalizedQueriesMatchBits(ApInt::minValueSigned(width)) ||
            !normalizedQueriesMatchBits(ApInt::maxValue(width)) ||
            !normalizedQueriesMatchBits(ApInt::maxValueSigned(width)))
            return Result::Error;

        for (const auto& pattern : patterns)
        {
            const ApInt original(pattern.data(), width);
            if (!normalizedQueriesMatchBits(original))
                return Result::Error;

            for (const uint32_t shift : {1u, 63u, 64u, 65u})
            {
                ApInt left     = original;
                bool  overflow = false;
                left.logicalShiftLeft(shift, overflow);
                ApInt right = original;
                right.arithmeticShiftRight(shift);
                ApInt logicalRight = original;
                logicalRight.logicalShiftRight(shift);
                if (!normalizedQueriesMatchBits(left) || !normalizedQueriesMatchBits(right) || !normalizedQueriesMatchBits(logicalRight))
                    return Result::Error;
            }

            ApInt resized = original;
            resized.resizeSigned(ApInt::maxBitWidth());
            if (!normalizedQueriesMatchBits(resized))
                return Result::Error;
            resized.shrink(width);
            if (!normalizedQueriesMatchBits(resized))
                return Result::Error;

            ApInt arithmetic = original;
            bool  overflow   = false;
            arithmetic.add(UINT64_MAX, overflow);
            if (!normalizedQueriesMatchBits(arithmetic))
                return Result::Error;
            arithmetic.mul(UINT64_MAX, overflow);
            if (!normalizedQueriesMatchBits(arithmetic))
                return Result::Error;
            arithmetic.invertAllBits();
            if (!normalizedQueriesMatchBits(arithmetic))
                return Result::Error;

            const ApInt mask = ApInt::maxValue(width);
            ApInt       ored = original;
            ored.bitwiseOr(mask);
            ApInt anded = original;
            anded.bitwiseAnd(mask);
            ApInt xored = original;
            xored.bitwiseXor(mask);
            ApInt lowOr = original;
            lowOr.bitwiseOr(UINT64_MAX);
            if (!normalizedQueriesMatchBits(ored) || !normalizedQueriesMatchBits(anded) ||
                !normalizedQueriesMatchBits(xored) || !normalizedQueriesMatchBits(lowOr))
                return Result::Error;
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ApInt_MinimumWidthsMatchSingleBitsAndComplements)
{
    for (uint32_t width = 1; width <= ApInt::maxBitWidth(); ++width)
    {
        ApInt value(width);
        for (uint32_t bit = 0; bit < width; ++bit)
        {
            value.setBit(bit);
            ApInt complement = value;
            complement.invertAllBits();
            if (!normalizedQueriesMatchBits(value) || !normalizedQueriesMatchBits(complement))
                return Result::Error;
            value.clearBit(bit);
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ApInt_DivisionClearsPreviousOverflow)
{
    for (uint32_t width = 1; width <= ApInt::maxBitWidth(); ++width)
    {
        for (const bool zero : {false, true})
        {
            const ApInt input     = zero ? ApInt(width) : ApInt::maxValue(width);
            ApInt       quotient  = input;
            bool        overflow  = true;
            const ApInt remainder = quotient.div(ApInt(1, width), overflow);
            if (overflow || !quotient.same(input) || !remainder.isZero())
                return Result::Error;
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ApInt_DivisionReturnsNormalizedRemainders)
{
    for (uint32_t width = 2; width <= ApInt::maxBitWidth(); ++width)
    {
        ApInt quotient = ApInt::maxValue(width);
        ApInt expected(width);
        for (uint32_t bit = width % 2; bit + 1 < width; bit += 2)
            expected.setBit(bit);

        bool        overflow  = false;
        const ApInt remainder = quotient.div(ApInt(3, width), overflow);
        if (overflow || !quotient.same(expected) || remainder.as64() != width % 2 || !remainder.fit64())
            return Result::Error;
    }

    constexpr std::array<uint64_t, 2> numerator{11, 2};
    constexpr std::array<uint64_t, 2> denominator{3, 1};
    for (uint32_t width = 66; width <= ApInt::maxBitWidth(); ++width)
    {
        ApInt       quotient(numerator.data(), width);
        bool        overflow  = false;
        const ApInt remainder = quotient.div(ApInt(denominator.data(), width), overflow);
        if (overflow || quotient.as64() != 2 || !quotient.fit64() || remainder.as64() != 5 || !remainder.fit64())
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ApInt_SignedDivisionPreservesNormalizedResults)
{
    for (uint32_t width = 3; width <= ApInt::maxBitWidth(); ++width)
    {
        const ApInt minusOne = ApInt::maxValue(width);
        ApInt       quotient = minusOne;
        quotient.clearBit(0);
        quotient.clearBit(1);
        bool        overflow  = false;
        const ApInt remainder = quotient.divSigned(ApInt(3, width), overflow);
        if (overflow || !quotient.same(minusOne) || !remainder.same(minusOne) ||
            !normalizedQueriesMatchBits(quotient) || !normalizedQueriesMatchBits(remainder))
            return Result::Error;
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ApInt_BoundariesMatchEveryActiveBit)
{
    for (uint32_t requestedWidth = 0; requestedWidth <= ApInt::maxBitWidth(); ++requestedWidth)
    {
        const uint32_t   width = requestedWidth ? requestedWidth : ApInt::maxBitWidth();
        const std::array bounds{
            ApInt::minValue(requestedWidth),
            ApInt::minValueSigned(requestedWidth),
            ApInt::maxValue(requestedWidth),
            ApInt::maxValueSigned(requestedWidth),
        };
        for (uint32_t kind = 0; kind < bounds.size(); ++kind)
        {
            if (bounds[kind].bitWidth() != width)
                return Result::Error;
            for (uint32_t bit = 0; bit < width; ++bit)
            {
                const bool expected = kind == 2 ||
                                      (kind == 1 && bit + 1 == width) ||
                                      (kind == 3 && bit + 1 < width);
                if (bounds[kind].testBit(bit) != expected)
                    return Result::Error;
            }
        }
    }
    return Result::Continue;
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
