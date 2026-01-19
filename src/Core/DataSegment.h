#pragma once
#include "Core/Store.h"
#include <unordered_map>

SWC_BEGIN_NAMESPACE();

class DataSegment
{
public:
    std::string_view addView(std::string_view value);
    std::string_view addString(const Utf8& value);
    uint32_t         addString(uint32_t baseOffset, uint32_t fieldOffset, const Utf8& value);
    uint32_t         offset(const void* ptr) const;
    void             addRelocation(uint32_t offset, uint32_t targetOffset);

    template<typename T>
    uint32_t reserve(T** ptrValue)
    {
        std::unique_lock lock(mutex_);
        auto             res = store_.emplace_uninit<T>();
        *ptrValue            = res.second;
        memset(*ptrValue, 0, sizeof(T));
        return res.first;
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
    Store                                             store_;
    std::unordered_map<std::string, std::string_view> mapString_;
    std::vector<std::pair<uint32_t, uint32_t>>        relocations_;
    mutable std::shared_mutex                         mutex_;
};

SWC_END_NAMESPACE();
