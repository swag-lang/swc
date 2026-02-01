#pragma once
#include "Support/Core/Store.h"

SWC_BEGIN_NAMESPACE();

struct DataSegmentRelocation
{
    uint32_t offset;
    uint32_t targetOffset;
};

class DataSegment
{
public:
    std::pair<ByteSpan, Ref>         addSpan(ByteSpan value);
    std::pair<std::string_view, Ref> addString(const Utf8& value);
    uint32_t                         addString(uint32_t baseOffset, uint32_t fieldOffset, const Utf8& value);
    void                             addRelocation(uint32_t offset, uint32_t targetOffset);
    Ref                              findRef(const void* ptr) const noexcept { return store_.findRef(ptr); }

    template<typename T>
    std::pair<uint32_t, T*> reserve()
    {
        std::unique_lock lock(mutex_);
        auto             res = store_.emplace_uninit<T>();
        std::memset(res.second, 0, sizeof(T));
        return res;
    }

    template<typename T>
    std::pair<uint32_t, T*> reserveSpan(uint32_t count)
    {
        if (!count)
            return {0, nullptr};
        std::unique_lock lock(mutex_);
        const uint32_t   bytes = static_cast<uint32_t>(sizeof(T)) * count;
        const auto       res   = store_.push_copy_span(ByteSpan{static_cast<const std::byte*>(nullptr), bytes}, static_cast<uint32_t>(alignof(T)));
        auto*            ptr   = store_.ptr<T>(res.second);
        std::memset(ptr, 0, bytes);
        return {res.second, ptr};
    }

    template<typename T>
    uint32_t add(const T& value)
    {
        std::unique_lock lock(mutex_);
        return store_.push_back(value);
    }

    template<class T>
    T* ptr(Ref ref) noexcept
    {
        std::shared_lock lock(mutex_);
        return store_.ptr<T>(ref);
    }

    template<class T>
    const T* ptr(Ref ref) const noexcept
    {
        std::shared_lock lock(mutex_);
        return store_.ptr<T>(ref);
    }

private:
    Store                                                                  store_;
    std::unordered_map<std::string, std::pair<std::string_view, uint32_t>> mapString_;
    std::vector<DataSegmentRelocation>                                     relocations_;
    mutable std::shared_mutex                                              mutex_;
};

SWC_END_NAMESPACE();
