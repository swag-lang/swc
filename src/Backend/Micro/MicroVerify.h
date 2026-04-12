#pragma once
#include "Support/Core/Result.h"
#include <cstdint>
#include <string_view>

SWC_BEGIN_NAMESPACE();

struct MicroPassContext;

namespace MicroVerify
{
    bool     isEnabled(const MicroPassContext& context);
    Result   reportError(const MicroPassContext& context, std::string_view phase, std::string_view message);
    Result   verify(const MicroPassContext& context, std::string_view phase, uint64_t* outStructuralHash = nullptr);
    uint64_t computeStructuralHash(const MicroPassContext& context);
}

SWC_END_NAMESPACE();
