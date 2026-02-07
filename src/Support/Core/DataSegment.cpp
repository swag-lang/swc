#include "pch.h"
#include "Support/Core/DataSegment.h"

SWC_BEGIN_NAMESPACE();

std::pair<ByteSpan, Ref> DataSegment::addSpan(ByteSpan value)
{
    std::unique_lock lock(mutex);
    return store.pushCopySpan(value);
}

std::pair<std::string_view, Ref> DataSegment::addString(const Utf8& value)
{
    std::unique_lock lock(mutex);
    if (const auto it = stringMap.find(value); it != stringMap.end())
        return it->second;
    const auto [span, ref]      = store.pushCopySpan(asByteSpan(std::string_view(value)));
    const std::string_view view = asStringView(span);
    stringMap[value]            = {view, ref};
    return {view, ref};
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
    std::unique_lock lock(mutex);
    relocations.push_back({.offset = offset, .targetOffset = targetOffset});
}

SWC_END_NAMESPACE();
