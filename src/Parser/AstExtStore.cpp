#include "pch.h"
#include "Parser/AstExtStore.h"

SWC_BEGIN_NAMESPACE();

AstExtStore::Index AstExtStore::allocRecord(uint32_t payloadSize, const void* payload)
{
    const uint32_t off = static_cast<uint32_t>(bytes_.size());
    bytes_.resize(off + payloadSize);
    if (payload && payloadSize)
        std::memcpy(bytes_.data() + off, payload, payloadSize);
    const Index idx = static_cast<uint32_t>(offsets_.size());
    offsets_.push_back(off);
    return idx;
}

SWC_END_NAMESPACE();
