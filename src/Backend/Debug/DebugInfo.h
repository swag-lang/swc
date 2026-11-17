#pragma once
#include "Backend/Debug/DebugPdbLocal.h"
#include "Backend/Debug/DebugInfoRecords.h"
#include "Backend/Native/NativeSection.h"
#include "Backend/RuntimeBase.h"
#include "Support/Core/ByteArray.h"
#include "Support/Core/Result.h"
#include "Support/Core/Utf8.h"

SWC_BEGIN_NAMESPACE();

class TaskContext;

struct DebugInfoDefinedSymbol
{
    Utf8     name;
    Utf8     sectionName;
    uint32_t value        = 0;
    uint16_t type         = 0;
    uint8_t  storageClass = K_COFF_SYM_CLASS_STATIC;
};

struct DebugInfoObjectRequest
{
    TaskContext*      ctx      = nullptr;
    Runtime::TargetOs targetOs = Runtime::TargetOs::Windows;
    fs::path          objectPath;

    // Use the module emission index as exact object identity. Function-per-member archives
    // can contain thousands of objects; hashing their paths risks collisions that define
    // an unwind symbol twice.
    uint32_t objectIndex = 0;
    // The artifact's symbol scope keeps objects of different modules apart without depending
    // on where their files are written.
    uint32_t symbolScopeHash = 0;

    std::span<const DebugInfoFunctionRecord> functions;
    std::span<const DebugInfoDataRecord>     globals;
    std::span<const DebugInfoConstantRecord> constants;

    bool emitCodeView = false;
    bool emitDwarf    = false;
};

struct DebugInfoObjectResult
{
    std::vector<NativeSectionData>      sections;
    std::vector<DebugInfoDefinedSymbol> symbols;
};

using DebugInfoPdbLocal = DebugPdbLocal;

// Per-function lowered type/frame data, parallel to DebugInfoObjectRequest::functions.
struct DebugInfoPdbFunction
{
    uint32_t                       procTypeIndex = 0; // TPI LF_PROCEDURE index (0 = T_NOTYPE)
    uint16_t                       frameReg      = 0;
    uint32_t                       frameFlags    = 0;
    std::vector<DebugInfoPdbLocal> locals;
};

struct DebugInfoPdbUdt
{
    Utf8     name;
    uint32_t typeIndex = 0;
};

// CodeView types and per-symbol type indices lowered for a PDB. tpiRecords holds the TPI stream body (no
// stream signature); indices run from 0x1000 to tpiIndexEnd. The function/global vectors run parallel to
// the request's functions/globals.
struct DebugInfoPdbResult
{
    ByteArray tpiRecords;
    ByteArray ipiRecords;

    uint32_t tpiIndexEnd    = 0x1000;
    uint32_t ipiIndexEnd    = 0x1000;
    uint32_t buildInfoIndex = 0;

    std::vector<DebugInfoPdbFunction> functions;
    std::vector<uint32_t>             globalTypes;
    std::vector<DebugInfoPdbUdt>      udts;
};

class DebugInfo
{
public:
    virtual ~DebugInfo() = default;

    static std::unique_ptr<DebugInfo> create(Runtime::TargetOs targetOs);

    static Result buildObject(const DebugInfoObjectRequest& request, DebugInfoObjectResult& outResult);
    static void   buildPdbInfo(const DebugInfoObjectRequest& request, DebugInfoPdbResult& outResult);

    virtual Result buildObject(DebugInfoObjectResult& outResult, const DebugInfoObjectRequest& request) = 0;
    virtual void   buildPdbInfo(DebugInfoPdbResult& outResult, const DebugInfoObjectRequest& request)   = 0;
};

SWC_END_NAMESPACE();
