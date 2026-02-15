#pragma once
#include "Backend/MachineCode/ABI/CallConv.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

namespace ABITypeNormalize
{
    enum class Usage : uint8_t
    {
        Argument,
        Return,
    };

    struct NormalizedType
    {
        bool     isVoid            = true;
        bool     isFloat           = false;
        bool     isIndirect        = false;
        bool     needsIndirectCopy = false;
        uint8_t  numBits           = 0;
        uint32_t indirectSize      = 0;
        uint32_t indirectAlign     = 0;
    };

    NormalizedType normalize(TaskContext& ctx, const CallConv& conv, TypeRef typeRef, Usage usage);
}

SWC_END_NAMESPACE();
