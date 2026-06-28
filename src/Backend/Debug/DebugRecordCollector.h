#pragma once
#include "Support/Core/RefTypes.h"
#include "Backend/Debug/DebugInfo.h"

SWC_BEGIN_NAMESPACE();

class NativeBackendBuilder;
struct NativeFunctionInfo;
struct NativeStartupInfo;

// Backing storage for a function's parameter/local/constant debug records. DebugInfoFunctionRecord holds
// spans into these vectors, so the storage must outlive the records and never reallocate (the collector
// reserves it up front).
struct FunctionDebugStorage
{
    std::vector<DebugInfoLocalRecord>    parameters;
    std::vector<DebugInfoLocalRecord>    locals;
    std::vector<DebugInfoConstantRecord> constants;
};

// The debug records gathered from the backend for one module/object: functions (with their parameter and
// local variable storage), data globals and global constants. Self-contained except for the TypeRef /
// ConstantRef handles, which are resolved later against the same compiler.
struct CollectedDebugRecords
{
    std::vector<FunctionDebugStorage>    functionStorage;
    std::vector<DebugInfoFunctionRecord> functions;
    std::vector<DebugInfoDataRecord>     globals;
    std::vector<DebugInfoConstantRecord> constants;
};

// Gathers the debug records for the given functions (optionally a startup stub and module data/constants).
// Shared by the COFF object writer (per-object) and the integrated linker (whole module, for the PDB), so
// both describe the program identically. Must run on the foreground thread: it reads compiler state.
void collectDebugRecords(NativeBackendBuilder&                      builder,
                         std::span<const NativeFunctionInfo* const> functions,
                         const NativeStartupInfo*                   startup,
                         bool                                       includeData,
                         CollectedDebugRecords&                     out);

SWC_END_NAMESPACE();
