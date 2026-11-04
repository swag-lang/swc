#pragma once

SWC_BEGIN_NAMESPACE();

namespace CodeViewLeaf
{
    // Answers how many bytes the numeric leaf at offset takes, or 0 when the span cuts it short or
    // its kind is not one CodeView defines for integers. A value below 0x8000 is stored inline.
    inline size_t numericSize(const std::span<const std::byte> bytes, const size_t offset)
    {
        if (offset + sizeof(uint16_t) > bytes.size())
            return 0;

        uint16_t leaf = 0;
        std::memcpy(&leaf, bytes.data() + offset, sizeof(leaf));
        size_t size = 0;
        switch (leaf)
        {
            case 0x8000: // LF_CHAR
                size = 3;
                break;
            case 0x8001: // LF_SHORT
            case 0x8002: // LF_USHORT
                size = 4;
                break;
            case 0x8003: // LF_LONG
            case 0x8004: // LF_ULONG
                size = 6;
                break;
            case 0x8009: // LF_QUADWORD
            case 0x800A: // LF_UQUADWORD
                size = 10;
                break;
            default:
                size = leaf < 0x8000 ? sizeof(uint16_t) : 0;
                break;
        }

        return offset + size <= bytes.size() ? size : 0;
    }
}

SWC_END_NAMESPACE();
