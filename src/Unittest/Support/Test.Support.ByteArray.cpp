#include "pch.h"

#if SWC_HAS_UNITTEST

#include "Support/Core/ByteArray.h"
#include "Unittest/Unittest.h"

SWC_BEGIN_NAMESPACE();

SWC_TEST_BEGIN(ByteArray_WordAccessPreservesByteOrderAndNeighbours)
{
    ByteArray bytes{std::byte{0xAA}};
    bytes.appendLe16(0xFEDC);
    bytes.appendLe32(0x89ABCDEF);
    bytes.appendLe64(0x0123456789ABCDEF);
    bytes.appendBe32(0x10203040);
    const ByteArray appended{
        std::byte{0xAA}, std::byte{0xDC}, std::byte{0xFE},
        std::byte{0xEF}, std::byte{0xCD}, std::byte{0xAB}, std::byte{0x89},
        std::byte{0xEF}, std::byte{0xCD}, std::byte{0xAB}, std::byte{0x89},
        std::byte{0x67}, std::byte{0x45}, std::byte{0x23}, std::byte{0x01},
        std::byte{0x10}, std::byte{0x20}, std::byte{0x30}, std::byte{0x40}};
    if (bytes != appended || bytes.readLe16(1) != 0xFEDC || bytes.readLe32(3) != 0x89ABCDEF ||
        bytes.readLe64(7) != 0x0123456789ABCDEF || bytes.readBe32(15) != 0x10203040)
        return Result::Error;

    bytes.writeLe16(1, 0x1357);
    bytes.writeLe32(3, 0x2468ACE0);
    bytes.writeLe64(7, 0xF0E1D2C3B4A59687);
    const ByteArray overwritten{
        std::byte{0xAA}, std::byte{0x57}, std::byte{0x13},
        std::byte{0xE0}, std::byte{0xAC}, std::byte{0x68}, std::byte{0x24},
        std::byte{0x87}, std::byte{0x96}, std::byte{0xA5}, std::byte{0xB4},
        std::byte{0xC3}, std::byte{0xD2}, std::byte{0xE1}, std::byte{0xF0},
        std::byte{0x10}, std::byte{0x20}, std::byte{0x30}, std::byte{0x40}};
    if (bytes != overwritten || bytes.readLe16(1) != 0x1357 || bytes.readLe32(3) != 0x2468ACE0 ||
        bytes.readLe64(7) != 0xF0E1D2C3B4A59687)
        return Result::Error;
}
SWC_TEST_END()

SWC_TEST_BEGIN(ByteArray_AppendAlignedPreservesPaddingAndOffset)
{
    const ByteArray payload{std::byte{0x11}, std::byte{0x22}, std::byte{0x33}};
    for (size_t prefix = 0; prefix <= 16; ++prefix)
    {
        ByteArray expected(prefix, std::byte{0xCC});
        while (expected.size() % 8)
            expected.pushBack(std::byte{0});
        const uint32_t expectedOffset = static_cast<uint32_t>(expected.size());
        expected.append(payload);

        for (const bool reserved : {false, true})
        {
            ByteArray bytes(prefix, std::byte{0xCC});
            if (reserved)
                bytes.reserve(prefix + payload.size() + 8);

            uint32_t offset = std::numeric_limits<uint32_t>::max();
            bytes.appendAligned(offset, payload, 8);
            if (offset != expectedOffset || bytes != expected)
                return Result::Error;
        }
    }
}
SWC_TEST_END()

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
