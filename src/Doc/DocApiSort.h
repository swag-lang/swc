#pragma once
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

namespace DocApiSort
{
    inline bool alphabeticLess(const std::string_view lhs, const std::string_view rhs)
    {
        const size_t size = std::min(lhs.size(), rhs.size());
        for (size_t i = 0; i < size; ++i)
        {
            const int left  = std::tolower(static_cast<unsigned char>(lhs[i]));
            const int right = std::tolower(static_cast<unsigned char>(rhs[i]));
            if (left != right)
                return left < right;
        }
        if (lhs.size() != rhs.size())
            return lhs.size() < rhs.size();
        return lhs < rhs;
    }
}

SWC_END_NAMESPACE();
