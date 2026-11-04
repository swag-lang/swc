#pragma once
#include "Backend/ABI/SystemVAbi.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
class TypeInfo;
struct CallConv;

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
        // The marker and two three-bit classes fit the existing shape's padding.
        // Size/alignment below describe storage for both indirect and System V values.
        uint8_t  systemVClasses    = 0;
        uint32_t indirectSize      = 0;
        uint32_t indirectAlign     = 0;

        bool isSystemVStorage() const { return systemVClasses != 0; }
        SystemVAbi::Classification systemVStorageType() const
        {
            return {{static_cast<SystemVAbi::Class>(systemVClasses & 7), static_cast<SystemVAbi::Class>((systemVClasses >> 3) & 7)}, indirectSize, indirectAlign};
        }
    };
    static_assert(sizeof(NormalizedType) == 16);

    NormalizedType normalize(TaskContext& ctx, const CallConv& conv, const TypeInfo& type, Usage usage);
}

SWC_END_NAMESPACE();
