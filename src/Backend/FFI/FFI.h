#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

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
    static void callFFI(TaskContext& ctx, void* targetFn, std::span<const FFIArgument> args, const FFIReturn& ret);
};

SWC_END_NAMESPACE();
