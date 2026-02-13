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

    struct FFIArgumentDesc
    {
        FFITypeDesc typeDesc = {};
        const void* valuePtr = nullptr;
    };

    struct FFIReturn
    {
        TypeRef typeRef  = TypeRef::invalid();
        void*   valuePtr = nullptr;
    };

    struct FFIReturnDesc
    {
        FFITypeDesc typeDesc = {};
        void*       valuePtr = nullptr;
    };

    class FFI final
    {
    public:
        static Result compileCall(TaskContext& ctx, void* targetFn, JITExecMemory& outExecutableMemory);
        static Result callFFI(TaskContext& ctx, void* targetFn, std::span<const FFIArgument> args, const FFIReturn& ret);
        static Result callFFI(TaskContext& ctx, void* targetFn, std::span<const FFIArgumentDesc> args, const FFIReturnDesc& ret);
        static Result describeType(TaskContext& ctx, TypeRef typeRef, FFITypeDesc& outDesc);

        template<typename F>
        static Result compileCall(TaskContext& ctx, F targetFn, JITExecMemory& outExecutableMemory)
        {
            static_assert(std::is_pointer_v<F>);
            static_assert(std::is_function_v<std::remove_pointer_t<F>>);
            return compileCall(ctx, reinterpret_cast<void*>(targetFn), outExecutableMemory);
        }
    };
}

SWC_END_NAMESPACE();
