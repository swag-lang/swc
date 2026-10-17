#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Support/Core/ByteArray.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(ByteArray_AlignmentMatchesIterativePadding)
{
    for (const size_t alignment : {size_t{1}, size_t{2}, size_t{3}, size_t{5}, size_t{8}, size_t{17}})
    {
        for (size_t prefix = 0; prefix <= 32; ++prefix)
        {
            for (const std::byte pad : {std::byte{0}, std::byte{0xCC}})
            {
                ByteArray expected(prefix, std::byte{0x11});
                while (expected.size() % alignment)
                    expected.pushBack(pad);
                for (const bool reserved : {false, true})
                {
                    ByteArray bytes(prefix, std::byte{0x11});
                    if (reserved)
                        bytes.reserve(prefix + alignment);
                    bytes.align(alignment, pad);
                    if (bytes != expected)
                        return Result::Error;
                }
            }
        }
    }
}
SWC_TEST_END()

SWC_END_NAMESPACE();

#endif
