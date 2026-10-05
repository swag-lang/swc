#pragma once
#include "Backend/ABI/CallConv.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class TypeInfo;

namespace ABITypeNormalize
{
    enum class Usage : uint8_t
    {
        Argument,
        Return,
    };

    struct NormalizedType
    {
        // Normalized ABI shape consumed by call/return lowering.
        bool     isVoid            = true;
        bool     isFloat           = false;
        bool     isSigned          = false;
        bool     isIndirect        = false;
        bool     needsIndirectCopy = false;
        uint8_t  numBits           = 0;
        uint32_t indirectSize      = 0;
        uint32_t indirectAlign     = 0;
    };

    NormalizedType normalize(TaskContext& ctx, const CallConv& conv, const TypeInfo& type, Usage usage);
}

SWC_END_NAMESPACE();
