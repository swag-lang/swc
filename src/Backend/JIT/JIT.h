#pragma once
#include "Backend/Micro/MicroBuilder.h"
#include "Support/Core/ByteSpan.h"
#include "Support/Core/RefTypes.h"
#include "Support/Core/Result.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
class JITMemory;
class SymbolFunction;

struct JITArgument
{
    TypeRef     typeRef  = TypeRef::invalid();
    const void* valuePtr = nullptr;
};

struct JITReturn
{
    TypeRef typeRef  = TypeRef::invalid();
    void*   valuePtr = nullptr;
};

class JIT final
{
public:
    static void   emit(TaskContext& ctx, JITMemory& outExecutableMemory, ByteSpan linearCode, std::span<const MicroRelocation> relocations);
    static void   emitAndCall(TaskContext& ctx, void* targetFn, std::span<const JITArgument> args, const JITReturn& ret);
    static Result call(TaskContext& ctx, void* invoker, const uint64_t* arg0 = nullptr);
};

SWC_END_NAMESPACE();
