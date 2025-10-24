#include "pch.h"
#include "Parser/AstNodeExt.h"

SWC_BEGIN_NAMESPACE();

AstNodeExt::ExtIndex AstNodeExt::allocRecord(uint32_t payloadSize, const void* payload)
{
    const uint32_t off = static_cast<uint32_t>(bytes_.size());
    bytes_.resize(off + payloadSize);
    if (payload && payloadSize)
        std::memcpy(bytes_.data() + off, payload, payloadSize);
    const ExtIndex idx = static_cast<uint32_t>(offsets_.size());
    offsets_.push_back(off);
    return idx;
}

SWC_END_NAMESPACE();
