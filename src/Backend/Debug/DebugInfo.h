#pragma once
#include "Backend/Micro/MicroReg.h"
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

struct DebugInfoTypedRecord
{
    Utf8    name;
    Utf8    linkageName;
    TypeRef typeRef = TypeRef::invalid();
    bool    isConst = false;
};

struct DebugInfoLocalRecord : DebugInfoTypedRecord
{
    uint32_t offset  = 0;
    MicroReg baseReg = MicroReg::invalid();
};

struct DebugInfoDataRecord : DebugInfoTypedRecord
{
    Utf8     symbolName;
    Utf8     sectionName;
    uint32_t symbolOffset = 0;
    bool     isGlobal     = true;
};

struct DebugInfoConstantRecord : DebugInfoTypedRecord
{
    ConstantRef valueRef = ConstantRef::invalid();
};

struct DebugInfoFunctionRecord
{
    Utf8                                     symbolName;
    Utf8                                     debugName;
    TypeRef                                  returnTypeRef = TypeRef::invalid();
    const MachineCode*                       machineCode   = nullptr;
    uint32_t                                 frameSize     = 0;
    MicroReg                                 frameBaseReg  = MicroReg::invalid();
    std::span<const DebugInfoLocalRecord>    parameters;
    std::span<const DebugInfoLocalRecord>    locals;
    std::span<const DebugInfoConstantRecord> constants;
};

struct DebugInfoObjectRequest
{
    TaskContext*                             ctx      = nullptr;
    Runtime::TargetOs                        targetOs = Runtime::TargetOs::Windows;
    fs::path                                 objectPath;
    std::span<const DebugInfoFunctionRecord> functions;
    std::span<const DebugInfoDataRecord>     globals;
    std::span<const DebugInfoConstantRecord> constants;
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
