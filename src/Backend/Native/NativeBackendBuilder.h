#pragma once
#include "Backend/Linker/LinkJob.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Native/NativeSection.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Main/TaskContext.h"
#include "Support/Core/ByteArray.h"
#include "Support/Core/Result.h"
#include "Support/Core/Utf8.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

struct MicroRelocation;
class CompilerInstance;
class Linker;
class ScopedTimedLog;
class SymbolFunction;
class SymbolVariable;

struct NativeFunctionInfo
{
    SymbolFunction*    symbol      = nullptr;
    const MachineCode* machineCode = nullptr;
    Utf8               sortKey;
    Utf8               symbolName;
    Utf8               exportName;
    Utf8               debugName;
    uint32_t           jobIndex   = 0;
    uint32_t           textOffset = 0;
    bool               exported   = false;
    bool               compilerFn = false;
};

struct NativeStartupInfo
{
    MachineCode code;
    Utf8        symbolName = "mainCRTStartup";
    Utf8        debugName  = "mainCRTStartup";
    uint32_t    textOffset = 0;
};

struct NativeRuntimeDependency
{
    Utf8              moduleName;
    Utf8              linkModuleName;
    Utf8              hookSymbolName;
    std::vector<Utf8> transitiveImports;
    SymbolFunction*   hookSymbol = nullptr;
};

struct NativeRDataAllocationMapEntry
{
    uint32_t sourceOffset  = 0;
    uint32_t size          = 0;
    uint32_t emittedOffset = 0;
};

struct NativeObjDescription
{
    uint32_t                         index = 0;
    fs::path                         objPath;
    ByteArray                        objBytes;
    std::vector<NativeFunctionInfo*> functions;
    NativeStartupInfo*               startup                = nullptr;
    bool                             includeData            = false;
    bool                             allowUnresolvedSymbols = false;
};

class NativeBackendBuilder
{
public:
    struct NativeTestProgressEvent
    {
        Utf8     name;
        uint32_t executed = 0;
        uint32_t failed   = 0;
    };

    NativeBackendBuilder(CompilerInstance& compiler, bool runArtifact);
    ~NativeBackendBuilder();

    TaskContext&              ctx();
    const TaskContext&        ctx() const;
    CompilerInstance&         compiler();
    const CompilerInstance&   compiler() const;
    bool                      tryResolveConstantSourceRef(DataSegmentRef& outSourceRef, const MicroRelocation& relocation) const noexcept;
    Result                    resolveConstantSourceRef(DataSegmentRef& outSourceRef, const Utf8& ownerName, const MicroRelocation& relocation);
    const NativeFunctionInfo* tryFindFunctionInfo(const SymbolFunction& targetFunction) const noexcept;
    Result                    resolveFunctionSymbolName(Utf8& outName, const SymbolFunction* targetFunction, bool allowUnresolvedSymbols = false);
    bool                      tryMapRDataSourceOffset(uint32_t& outOffset, uint32_t shardIndex, uint32_t sourceOffset) const noexcept;
    Result                    appendCodeRelocation(const NativeCodeRelocationTarget& target, const Utf8& ownerName, const MicroRelocation& relocation);
    DiagnosticId              lastErrorId() const { return lastErrorId_; }
    bool                      artifactLinked() const { return artifactLinked_; }

    Result run();
    Result runExistingArtifact();
    Result prepare();
    Result buildObject(uint32_t objIndex);

    // Serialises the current object partition into COFF bytes. buildObjects() calls it for a static
    // library; the shared-library path calls it again, on a finer partition, for the archive it
    // publishes beside its DLL.
    Result buildObjectBytes();
    Result publishExistingArtifact();
    Result publishExecutableDependencies();

    // Deferred (workspace async-link) path. prepareForLink runs the full build up to but not
    // including the link, leaving a prepared LinkJob in deferredToolRun(). The caller then runs
    // Linker::executeLink(deferredToolRun()) on a background thread, and finally calls
    // finishDeferredLink() back on the foreground thread to report results and, for an executable run,
    // launch the artifact.
    Result   prepareForLink();
    Result   finishDeferredLink();
    LinkJob& deferredToolRun() { return deferredToolRun_; }

    Result reportError(DiagnosticId id);
    Result reportError(const Diagnostic& diag);

    template<typename T1>
    Result reportError(DiagnosticId id, std::string_view name1, T1&& value1)
    {
        Diagnostic diag = Diagnostic::get(id);
        diag.addArgument(name1, std::forward<T1>(value1));
        return reportError(std::move(diag));
    }

    template<typename T1, typename T2>
    Result reportError(DiagnosticId id, std::string_view name1, T1&& value1, std::string_view name2, T2&& value2)
    {
        Diagnostic diag = Diagnostic::get(id);
        diag.addArgument(name1, std::forward<T1>(value1));
        diag.addArgument(name2, std::forward<T2>(value2));
        return reportError(std::move(diag));
    }

    std::vector<SymbolFunction*>                                                         testFunctions;
    std::vector<SymbolFunction*>                                                         initFunctions;
    std::vector<SymbolFunction*>                                                         preMainFunctions;
    std::vector<SymbolFunction*>                                                         dropFunctions;
    std::vector<SymbolFunction*>                                                         mainFunctions;
    std::vector<SymbolVariable*>                                                         regularGlobals;
    std::vector<NativeRuntimeDependency>                                                 runtimeDependencies;
    std::vector<uint32_t>                                                                runtimeDependencyInitOrder;
    std::vector<uint32_t>                                                                runtimeDependencyDropOrder;
    std::vector<NativeFunctionInfo>                                                      functionInfos;
    std::unordered_map<const SymbolFunction*, const NativeFunctionInfo*>                 functionBySymbol;
    std::vector<std::unique_ptr<MachineCode>>                                            generatedMachineCodes;
    std::unique_ptr<NativeStartupInfo>                                                   startup;
    NativeSectionData                                                                    mergedRData;
    NativeSectionData                                                                    mergedData;
    NativeSectionData                                                                    mergedBss;
    std::array<std::vector<NativeRDataAllocationMapEntry>, ConstantManager::SHARD_COUNT> rdataAllocationMap;
    std::vector<NativeObjDescription>                                                    objectDescriptions;
    fs::path                                                                             buildDir;
    fs::path                                                                             artifactPath;
    fs::path                                                                             pdbPath;
    std::atomic<bool>                                                                    objBuildFailed = false;

    // Test tally parsed from the generated executable's "[swag.test]" marker line
    // (see the runtime's __testsDone). Valid when hasNativeTestSummary is true.
    bool     hasNativeTestSummary = false;
    uint32_t nativeTestsExecuted  = 0;
    uint32_t nativeTestsFailed    = 0;

    static bool parseNativeTestProgressEvent(NativeTestProgressEvent& outEvent, std::string_view line);

private:
    struct NativeTestProgressContext;

    static void forwardNativeTestProgress(void* userData, std::string_view line);
    void        updateNativeTestProgress(ScopedTimedLog& stage, std::string_view line);
    void        parseNativeTestSummary(const std::string& output);
    Result      validateTarget();
    Result      buildObjects();
    Result      runGeneratedArtifact();
    Result      runAfterLink();

    TaskContext             ctx_;
    CompilerInstance*       compiler_       = nullptr;
    bool                    runArtifact_    = false;
    bool                    artifactLinked_ = false;
    DiagnosticId            lastErrorId_    = DiagnosticId::None;
    std::unique_ptr<Linker> deferredLinker_;
    LinkJob                 deferredToolRun_;
};

SWC_END_NAMESPACE();
