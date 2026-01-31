#include "pch.h"
#include "Core/DataSegment.h"

SWC_BEGIN_NAMESPACE();

std::pair<std::string_view, Ref> DataSegment::addView(std::string_view value)
{
    std::unique_lock lock(mutex_);
    return store_.push_copy_view(value);
}

std::pair<ByteSpan, Ref> DataSegment::addView(ByteSpan value)
{
    std::unique_lock lock(mutex_);
    auto [ref, dst] = store_.push_back_raw(static_cast<uint32_t>(value.size()), alignof(std::byte));
    std::memcpy(dst, value.data(), value.size());
    return {{static_cast<const std::byte*>(dst), value.size()}, ref};
}

std::pair<std::string_view, Ref> DataSegment::addString(const Utf8& value)
{
    std::unique_lock lock(mutex_);
    if (const auto it = mapString_.find(value); it != mapString_.end())
        return it->second;
    const auto res    = store_.push_copy_view(std::string_view(value));
    mapString_[value] = res;
    return res;
}

uint32_t DataSegment::addString(uint32_t baseOffset, uint32_t fieldOffset, const Utf8& value)
{
    const auto res = addString(value);
    addRelocation(baseOffset + fieldOffset, res.second);

    const auto ptrField = ptr<char*>(baseOffset + fieldOffset);
    *ptrField           = const_cast<char*>(res.first.data());

    return static_cast<uint32_t>(res.first.size());
}

void DataSegment::addRelocation(uint32_t offset, uint32_t targetOffset)
{
    std::unique_lock lock(mutex_);
    relocations_.push_back({.offset = offset, .targetOffset = targetOffset});
}

SWC_END_NAMESPACE();
