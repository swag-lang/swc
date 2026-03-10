#pragma once
#include "Backend/Native/NativeBackendBuilder.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;

struct DebugInfoDefinedSymbol
{
    Utf8     name;
    Utf8     sectionName;
    uint32_t value        = 0;
    uint16_t type         = 0;
    uint8_t  storageClass = IMAGE_SYM_CLASS_STATIC;
};

struct DebugInfoFunctionRecord
{
    Utf8               symbolName;
    Utf8               debugName;
    uint32_t           textOffset  = 0;
    const MachineCode* machineCode = nullptr;
};

struct DebugInfoObjectRequest
{
    TaskContext*                             ctx      = nullptr;
    Runtime::TargetOs                        targetOs = Runtime::TargetOs::Windows;
    fs::path                                 objectPath;
    uint16_t                                 textSectionNumber = 0;
    std::span<const DebugInfoFunctionRecord> functions;
    bool                                     emitCodeView = false;
};

struct DebugInfoObjectResult
{
    std::vector<NativeSectionData>      sections;
    std::vector<DebugInfoDefinedSymbol> symbols;
};

struct JitDebugArtifact
{
    fs::path imagePath;
    fs::path pdbPath;
    uint64_t imageBase = 0;
    uint32_t imageSize = 0;
    Utf8     moduleName;
};

struct JitDebugRequest
{
    TaskContext*          ctx      = nullptr;
    Runtime::TargetOs     targetOs = Runtime::TargetOs::Windows;
    const SymbolFunction* function = nullptr;
    Utf8                  symbolName;
    Utf8                  debugName;
    const MachineCode*    machineCode = nullptr;
    void*                 codeAddress = nullptr;
    fs::path              workDir;
};

namespace DebugInfo
{
    Result buildObject(const DebugInfoObjectRequest& request, DebugInfoObjectResult& outResult);
    bool   emitJitArtifact(const JitDebugRequest& request, JitDebugArtifact& outArtifact);
}

SWC_END_NAMESPACE();
