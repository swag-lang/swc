#pragma once
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

struct MicroPassContext;

namespace MicroVerify
{
#if SWC_HAS_VALIDATE_MICRO
    bool     isEnabled(const MicroPassContext& context);
    Result   reportError(const MicroPassContext& context, std::string_view phase, std::string_view message);
    Result   verify(const MicroPassContext& context, std::string_view phase, uint64_t* outStructuralHash = nullptr);
    Result   verifyAllRegistersVirtual(const MicroPassContext& context, std::string_view phase);
    uint64_t computeStructuralHash(const MicroPassContext& context);
#else
    inline bool isEnabled(const MicroPassContext& context)
    {
        (void) context;
        return false;
    }

    inline Result reportError(const MicroPassContext& context, std::string_view phase, std::string_view message)
    {
        (void) context;
        (void) phase;
        (void) message;
        return Result::Error;
    }

    inline Result verify(const MicroPassContext& context, std::string_view phase, uint64_t* outStructuralHash = nullptr)
    {
        (void) context;
        (void) phase;
        if (outStructuralHash)
            *outStructuralHash = 0;
        return Result::Continue;
    }

    inline Result verifyAllRegistersVirtual(const MicroPassContext& context, std::string_view phase)
    {
        (void) context;
        (void) phase;
        return Result::Continue;
    }

    inline uint64_t computeStructuralHash(const MicroPassContext& context)
    {
        (void) context;
        return 0;
    }
#endif
}

SWC_END_NAMESPACE();
