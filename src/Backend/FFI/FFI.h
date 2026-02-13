#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

namespace Backend
{
    struct FFIArgument
    {
        TypeRef     typeRef  = TypeRef::invalid();
        const void* valuePtr = nullptr;
    };

    struct FFIReturn
    {
        TypeRef typeRef  = TypeRef::invalid();
        void*   valuePtr = nullptr;
    };

    class FFI final
    {
    public:
        static Result callFFI(TaskContext& ctx, void* targetFn, std::span<const FFIArgument> args, const FFIReturn& ret);
    };
}

SWC_END_NAMESPACE();
