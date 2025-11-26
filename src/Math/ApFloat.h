#pragma once

SWC_BEGIN_NAMESPACE()

class ApFloat
{
    uint32_t bitWidth_;

public:
    ApFloat() = delete;
    explicit ApFloat(uint32_t bitWidth) :
        bitWidth_(bitWidth)
    {
    }

    bool     same(const ApFloat& other) const;
    size_t   hash() const;
    uint32_t bitWidth() const { return bitWidth_; }
};

SWC_END_NAMESPACE()
