#pragma once
#include "Backend/Encoder/EncoderDebugInfo.h"
#include "Backend/Micro/MicroRelocation.h"
#include "Support/Core/ByteArray.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;
class SymbolFunction;
class MicroBuilder;
struct MachineCode;

// The input is consumer-owned lowered IR. Archives contain no process pointers:
// emitted relocations and source ranges refer back to that input by index.
class MachineCodeCache
{
public:
    MachineCodeCache(TaskContext& ctx, const SymbolFunction& function, const MicroBuilder& builder);
    bool        read(MachineCode& out) const;
    void        write(const MachineCode& code) const;
    static void flush();
    // Describes current IR and source bindings without cache I/O.
    static Utf8 inputKey(TaskContext& ctx, std::vector<DebugSourceInfo>& outSources, const SymbolFunction& function, const MicroBuilder& builder, std::string_view compilerIdentity);

private:
    TaskContext*                 ctx_ = nullptr;
    Utf8                         key_;
    std::vector<MicroRelocation> targets_;
    std::vector<DebugSourceInfo> sources_;
};

SWC_END_NAMESPACE();
