#pragma once
#include "Support/Core/Result.h"
#include <cstdint>
#include <string_view>

SWC_BEGIN_NAMESPACE();

struct MicroPassContext;

namespace MicroVerify
{
    Result   verify(const MicroPassContext& context, std::string_view phase);
    uint64_t computeStructuralHash(const MicroPassContext& context);
}

SWC_END_NAMESPACE();
