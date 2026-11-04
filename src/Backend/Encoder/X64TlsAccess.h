#pragma once

SWC_BEGIN_NAMESPACE();

// An encoded dynamic TLS read. Native Windows images keep the TEB instruction;
// the JIT replaces it with the host TLS operation when running on another OS.
struct X64TlsAccess
{
    static constexpr uint32_t K_INSTRUCTION_SIZE = 9;
    uint32_t codeOffset = 0;
    uint32_t destination = 0;
    uint32_t slot = 0;

    bool valid(std::span<const std::byte> code) const
    {
        if (destination >= 16 || slot >= 16 || destination == 4 || slot == 4 || codeOffset > code.size() || code.size() - codeOffset < K_INSTRUCTION_SIZE)
            return false;
        const std::array<uint8_t, K_INSTRUCTION_SIZE> expected = {
            0x65, static_cast<uint8_t>(0x48 | ((destination >> 3) << 2) | ((slot >> 3) << 1)),
            0x8b, static_cast<uint8_t>(((destination & 7) << 3) | 4),
            static_cast<uint8_t>(0xc5 | ((slot & 7) << 3)), 0x78, 0x14, 0, 0};
        return std::memcmp(code.data() + codeOffset, expected.data(), expected.size()) == 0;
    }
};

SWC_END_NAMESPACE();
