#pragma once

#include <vector>

SWC_BEGIN_NAMESPACE();

struct BackendSegment
{
    uint32_t reserve(uint32_t size, uint8_t** outPtr)
    {
        const uint32_t offset = static_cast<uint32_t>(data.size());
        data.resize(offset + size);
        *outPtr = data.data() + offset;
        return offset;
    }

    uint8_t* address(uint32_t offset)
    {
        return data.data() + offset;
    }

    const uint8_t* address(uint32_t offset) const
    {
        return data.data() + offset;
    }

    std::vector<uint8_t> data;
};

struct Module
{
    BackendSegment constantSegment;
    BackendSegment compilerSegment;
};

SWC_END_NAMESPACE();
