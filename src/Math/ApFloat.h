#pragma once

SWC_BEGIN_NAMESPACE()

class ApFloat
{
public:
    bool   equals(const ApFloat& other) const;
    size_t hash() const;
};

SWC_END_NAMESPACE()
