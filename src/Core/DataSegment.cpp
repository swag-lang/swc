#include "pch.h"
#include "Core/DataSegment.h"

SWC_BEGIN_NAMESPACE();

std::string_view DataSegment::addView(std::string_view value)
{
    std::unique_lock lock(mutex_);
    return store_.push_copy_view(value);
}

std::string_view DataSegment::addString(const Utf8& value)
{
    std::unique_lock lock(mutex_);
    if (const auto it = mapString_.find(value); it != mapString_.end())
        return it->second;
    const auto view   = store_.push_copy_view(std::string_view(value));
    mapString_[value] = view;
    return view;
}

SWC_END_NAMESPACE();
