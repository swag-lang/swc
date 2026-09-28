#pragma once
#include "Support/Core/ByteArray.h"

SWC_BEGIN_NAMESPACE();

namespace NativeTest
{
    inline void emit(ByteArray& out, std::initializer_list<int> bytes)
    {
        for (const int b : bytes)
            out.pushBack(static_cast<std::byte>(b));
    }
}

SWC_END_NAMESPACE();
