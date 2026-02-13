#pragma once
#include "Backend/JIT/JITExecMemory.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"
#include <span>
#include <type_traits>

SWC_BEGIN_NAMESPACE();

class TaskContext;

namespace Backend
{
    enum class FFIValueClass : uint8_t
    {
        Void,
        Int,
        Float,
    };

    struct FFITypeDesc
    {
        FFIValueClass valueClass = FFIValueClass::Void;
        uint8_t       numBits    = 0;
    };

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
