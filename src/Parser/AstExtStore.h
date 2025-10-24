#pragma once
SWC_BEGIN_NAMESPACE();

class AstExtStore
{
    std::vector<uint8_t>  bytes_;   // one big pool
    std::vector<uint32_t> offsets_; // index -> offset into bytes

public:
    using Index = uint32_t;

    static uint32_t pad4(uint32_t x) { return (x + 3u) & ~3u; }

    // Create a new record and return its index. You provide a byte size and (optionally) a writer.
    Index allocRecord(uint32_t payloadSize, const void* payload = nullptr);

    // Views (unchecked; call them according to the kind’s contract)
    const uint8_t* data(Index index) const { return bytes_.data() + offsets_[index]; }
};

SWC_END_NAMESPACE();
