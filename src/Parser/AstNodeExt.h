#pragma once
SWC_BEGIN_NAMESPACE();

class AstNodeExt
{
    std::vector<uint8_t>  bytes_;   // one big pool
    std::vector<uint32_t> offsets_; // index -> offset into bytes

public:
    using ExtIndex = uint32_t;

    static uint32_t pad4(uint32_t x) { return (x + 3u) & ~3u; }

    // Create a new record and return its index. You provide a byte size and (optionally) a writer.
    ExtIndex allocRecord(uint32_t payloadSize, const void* payload = nullptr);

    // Views (unchecked; call them according to the kind’s contract)
    const uint8_t* data(ExtIndex index) const { return bytes_.data() + offsets_[index]; }
};

SWC_END_NAMESPACE();
