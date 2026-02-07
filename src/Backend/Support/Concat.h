#pragma once

#include "Support/Core/ByteSpan.h"
#include "Support/Core/Store.h"

SWC_BEGIN_NAMESPACE();

class Concat
{
public:
    void clear()
    {
        store_.clear();
        currentSP = nullptr;
    }

    uint32_t totalCount() const noexcept
    {
        return store_.size();
    }

    uint8_t* getSeekPtr() const noexcept
    {
        return currentSP;
    }

    void addU8(uint8_t v) { appendPod(v); }
    void addU16(uint16_t v) { appendPod(v); }
    void addU32(uint32_t v) { appendPod(v); }
    void addU64(uint64_t v) { appendPod(v); }
    void addS32(int32_t v) { appendPod(v); }

    uint8_t* currentSP = nullptr;

private:
    template<typename T>
    void appendPod(const T& v)
    {
        const ByteSpan payload{reinterpret_cast<const std::byte*>(&v), sizeof(T)};
        const auto     res = store_.push_copy_span(payload, 1);
        currentSP = const_cast<uint8_t*>(reinterpret_cast<const uint8_t*>(res.first.data())) + res.first.size();
    }

    Store store_;
};

SWC_END_NAMESPACE();
