#pragma once
#include "Core/Store.h"
#include <unordered_map>

SWC_BEGIN_NAMESPACE();

class DataSegment
{
public:
    template<typename T>
    uint32_t add(const T& value)
    {
        std::unique_lock lock(mutex_);
        return store_.push_back(value);
    }

    std::string_view addView(std::string_view value)
    {
        std::unique_lock lock(mutex_);
        return store_.push_back(value);
    }

    std::string_view addString(std::string_view value)
    {
        std::unique_lock lock(mutex_);
        if (const auto it = mapString_.find(value); it != mapString_.end())
            return it->second;
        const auto view  = store_.push_back(value);
        mapString_[view] = view;
        return view;
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
    Store                                              store_;
    std::unordered_map<std::string_view, std::string_view> mapString_;
    mutable std::shared_mutex                          mutex_;
};

SWC_END_NAMESPACE();
