#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Support/Math/ApInt.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(ApInt_ArithmeticShiftMatchesBitOracle)
{
    for (uint32_t width = 1; width <= ApInt::maxBitWidth(); ++width)
    {
        for (uint32_t pattern = 0; pattern < 5; ++pattern)
        {
            ApInt input(width);
            for (uint32_t bit = 0; bit < width; ++bit)
            {
                const bool set = pattern == 1 ? bit == width - 1 : pattern == 2 ? true
                                                               : pattern == 3   ? bit % 3 == 0
                                                               : pattern == 4   ? bit == 0
                                                                                : false;
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
    constexpr uint64_t                               max      = std::numeric_limits<uint64_t>::max();
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

SWC_END_NAMESPACE();

#endif
