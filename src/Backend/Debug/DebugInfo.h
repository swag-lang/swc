#pragma once
#include "Support/Core/RefTypes.h"
#include "Support/Core/Utf8.h"
#include "Support/Core/Result.h"
#include "Backend/Micro/MicroReg.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Support/Core/ByteArray.h"

SWC_BEGIN_NAMESPACE();

class SymbolFunction;
class SourceFile;
class TaskContext;

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
    const SourceFile*                        sourceFile    = nullptr;
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

// A lowered local variable or parameter, ready for an S_REGREL32 record in a PDB module stream.
struct DebugInfoPdbLocal
{
    Utf8     name;
    uint32_t typeIndex   = 0;
    int32_t  frameOffset = 0;
    uint16_t cvRegister  = 0; // CodeView register that addresses the frame
    bool     isParam     = false;
};

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
    ByteArray                         tpiRecords;
    ByteArray                         ipiRecords;
    uint32_t                          tpiIndexEnd    = 0x1000;
    uint32_t                          ipiIndexEnd    = 0x1000;
    uint32_t                          buildInfoIndex = 0;
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

    // SHA-256 of a source file's content for the PDB/CodeView checksum. Returns the bytes Visual Studio
    // re-hashes from disk: for generated sources (CustomSrc) that is the whole per-thread .swgsrc dump (the
    // in-memory content, taken at link time to avoid racing the on-disk flush), not a single section view.
    static std::array<uint8_t, 32> sourceFileChecksum(const TaskContext& ctx, const SourceFile& file);

    virtual Result buildObject(DebugInfoObjectResult& outResult, const DebugInfoObjectRequest& request) = 0;
    virtual void   buildPdbInfo(DebugInfoPdbResult& outResult, const DebugInfoObjectRequest& request)   = 0;
};

SWC_END_NAMESPACE();
