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
    static void emit(TaskContext& ctx, std::span<const std::byte> linearCode, std::span<const MicroInstrCodeRelocation> relocations, JITExecMemory& outExecutableMemory);
    static void call(TaskContext& ctx, void* targetFn, std::span<const JITArgument> args, const JITReturn& ret);
};

SWC_END_NAMESPACE();
