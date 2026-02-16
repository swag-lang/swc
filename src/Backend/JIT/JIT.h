#pragma once
#include "Backend/CodeGen/Micro/MicroInstrBuilder.h"
#include "Support/Core/RefTypes.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
class JITExecMemory;

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
    using JITInvokerFn      = void (*)();
    using JITInvokerVoidU64 = void (*)(uint64_t);

    static void emit(TaskContext& ctx, std::span<const std::byte> linearCode, std::span<const MicroInstrCodeRelocation> relocations, JITExecMemory& outExecutableMemory);
    static void call(TaskContext& ctx, void* targetFn, std::span<const JITArgument> args, const JITReturn& ret);
    static void callVoid(TaskContext& ctx, JITInvokerFn invoker);
    static void callVoidU64(TaskContext& ctx, JITInvokerVoidU64 invoker, uint64_t arg0);
};

SWC_END_NAMESPACE();
