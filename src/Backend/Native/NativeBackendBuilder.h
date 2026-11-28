#pragma once
#include "Backend/Linker/LinkJob.h"
#include "Backend/Micro/MachineCode.h"
#include "Backend/Native/NativeGlobalLayout.h"
#include "Backend/Native/NativeSection.h"
#include "Compiler/Sema/Constant/ConstantStorageLayout.h"
#include "Main/TaskContext.h"
#include "Support/Core/ByteArray.h"
#include "Support/Core/DataSegment.h"
#include "Support/Core/PointerSet.h"
#include "Support/Core/Result.h"
#include "Support/Core/Utf8.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

struct MicroRelocation;
class CompilerInstance;
class Archive;
class NativeElfFunctionCache;
class Linker;
class ScopedTimedLog;
class SymbolFunction;
class SymbolVariable;

struct NativeFunctionInfo
{
    SymbolFunction*    symbol      = nullptr;
    const MachineCode* machineCode = nullptr;

    Utf8 sortKey;
    Utf8 symbolName;
    Utf8 debugName;

    uint32_t jobIndex   = 0;
    uint32_t textOffset = 0;

    bool compilerFn = false;
    bool cacheHit   = false;
};

// One line of a previous build's function cache index.
struct NativeFunctionCacheEntry
{
    Utf8     fingerprint;
    Utf8     symbolName;
    uint64_t callClobbers = MicroInstr::K_CALL_CLOBBERS_ALL;
};

struct NativeFunctionCacheRecord
{
    Utf8 key;
    Utf8 fingerprint;
    Utf8 symbolName;

    ByteArray objectBytes;
    bool      hit = false;
};

struct NativeStartupInfo
{
    MachineCode code;
    Utf8        symbolName = "mainCRTStartup";
    Utf8        debugName  = "mainCRTStartup";
    uint32_t    textOffset = 0;
};

struct NativeRDataAllocationMapEntry
{
    uint32_t sourceOffset  = 0;
    uint32_t size          = 0;
    uint32_t emittedOffset = 0;
};

struct NativeObjDescription
{
    uint32_t  index = 0;
    fs::path  objPath;
    ByteArray objBytes;

    std::vector<NativeFunctionInfo*> functions;
    NativeStartupInfo*               startup = nullptr;

    bool includeData          = false;
    bool includeMergedRData   = false;

    bool allowUnresolvedSymbols = false;
};

class NativeBackendBuilder
{
public:
    // Version 1 omitted per-function Optimize overrides from the code identity. Version 2 kept no
    // call clobbers, which an optimized caller of a reused leaf reads.
    static constexpr uint32_t K_FUNCTION_CACHE_VERSION = 3;

    struct ArtifactRunReport
    {
        bool        completed = false;
        uint32_t    exitCode  = UINT32_MAX;
        std::string output;
    };

    NativeBackendBuilder(CompilerInstance& compiler, bool runArtifact);
    ~NativeBackendBuilder();

    TaskContext&            ctx();
    const TaskContext&      ctx() const;
    CompilerInstance&       compiler();
    const CompilerInstance& compiler() const;

    bool   tryResolveConstantSourceRef(DataSegmentRef& outSourceRef, const MicroRelocation& relocation) const noexcept;
    Result resolveConstantSourceRef(DataSegmentRef& outSourceRef, const Utf8& ownerName, const MicroRelocation& relocation);

    const NativeFunctionInfo* tryFindFunctionInfo(const SymbolFunction& targetFunction) const noexcept;
    Result                    resolveFunctionSymbolName(Utf8& outName, const SymbolFunction* targetFunction, bool allowUnresolvedSymbols = false);

    const NativeRDataAllocationMapEntry* tryFindRDataSourceAllocation(uint32_t shardIndex, uint32_t sourceOffset) const noexcept;
    bool tryMapRDataSourceOffset(uint32_t& outOffset, uint32_t shardIndex, uint32_t sourceOffset) const noexcept;

    Result appendCodeRelocation(const NativeCodeRelocationTarget& target, const Utf8& ownerName, const MicroRelocation& relocation);

    bool                             tryReuseFunction(SymbolFunction& function);
    Result                           finalizeFunctionCacheHit(bool& outHit, SymbolFunction& function, const Utf8& symbolName);
    const NativeFunctionCacheRecord* functionCacheRecord(const SymbolFunction& function) const;
    bool                             functionCacheEnabled() const { return functionCacheEnabled_; }
    const fs::path&                  functionCacheArchivePath() const { return functionCacheArchivePath_; }
    const fs::path&                  functionCacheIndexPath() const { return functionCacheIndexPath_; }

    DiagnosticId lastErrorId() const { return lastErrorId_; }
    bool         artifactLinked() const { return artifactLinked_; }

    Result run();
    Result runExistingArtifact(ArtifactRunReport* report = nullptr);
    Result prepare();

    // The JIT consumes machine code and relocations from the prepared functions.
    Result prepareForJit(std::vector<SymbolFunction*>& outFunctions);

    std::vector<SymbolFunction*> collectPreparedFunctions() const
    {
        std::vector<SymbolFunction*> result;
        result.reserve(functionInfos.size());
        for (const NativeFunctionInfo& info : functionInfos)
        {
            if (info.symbol)
                result.push_back(info.symbol);
        }

        return result;
    }

    Result buildObject(uint32_t objIndex);

    Result buildObjectBytes();

    // Deferred linking: prepareForLink() captures a LinkJob in deferredToolRun().
    // Run Linker::executeLink() on a background thread, then finishDeferredLink()
    // on the foreground thread to report results and launch executable runs.
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

    std::vector<SymbolFunction*> testFunctions;
    std::vector<SymbolFunction*> initFunctions;
    std::vector<SymbolFunction*> preMainFunctions;
    std::vector<SymbolFunction*> dropFunctions;
    std::vector<SymbolFunction*> mainFunctions;
    std::vector<SymbolVariable*> regularGlobals;


    std::vector<NativeFunctionInfo>                      functionInfos;
    PointerMap<SymbolFunction, const NativeFunctionInfo> functionBySymbol;
    std::vector<std::unique_ptr<MachineCode>>            generatedMachineCodes;
    std::unique_ptr<NativeStartupInfo>                   startup;

    NativeSectionData  mergedRData;
    NativeSectionData  mergedData;
    NativeSectionData  mergedBss;
    NativeGlobalLayout globalLayout;

    std::array<std::vector<NativeRDataAllocationMapEntry>, ConstantStorageLayout::SHARD_COUNT> rdataAllocationMap;

    std::vector<NativeObjDescription> objectDescriptions;

    fs::path buildDir;
    fs::path artifactPath;
    fs::path pdbPath;

    std::atomic<bool> objBuildFailed = false;

    // Test tally parsed from the generated executable's "[swag.test]" marker line
    // (see the runtime's __testsDone). Valid when hasNativeTestSummary is true.
    bool     hasNativeTestSummary = false;
    uint32_t nativeTestsExecuted  = 0;
    uint32_t nativeTestsFailed    = 0;

    // Section bases and allocation-name scope depend only on the artifact.
    // Cache them once to avoid formatting them for every data relocation.
    struct ScopedSymbolNames
    {
        Utf8     rdataBase;
        Utf8     dataBase;
        Utf8     bssBase;
        uint32_t scopeHash = 0;
    };

    const ScopedSymbolNames& scopedSymbolNames() const;

private:
    struct NativeTestProgressContext;

    static void forwardNativeTestProgress(void* userData, std::string_view line);
    void        updateNativeTestProgress(ScopedTimedLog& stage, std::string_view line);
    size_t      selectedNativeTestCount() const;
    void        parseNativeTestSummary(const std::string& output);
    Result      validateTarget();
    Result      prepareBackend(std::vector<SymbolFunction*>* outJitFunctions);
    void        prepareFunctionCache(bool preparesArtifact);
    Result      buildObjects();
    Result      buildArtifactObjects(std::optional<ScopedTimedLog>& outStage);
    void        adoptArtifactPaths();
    Result      runGeneratedArtifact(ArtifactRunReport* report = nullptr);
    Result      runAfterLink();

    mutable std::once_flag    scopedSymbolNamesOnce_;
    mutable ScopedSymbolNames scopedSymbolNames_;

    TaskContext       ctx_;
    CompilerInstance* compiler_       = nullptr;
    bool              runArtifact_    = false;
    bool              artifactLinked_ = false;
    DiagnosticId      lastErrorId_    = DiagnosticId::None;

    std::unique_ptr<Linker> deferredLinker_;
    LinkJob                 deferredToolRun_;

    std::unique_ptr<Archive>                                             existingFunctionCacheArchive_;
    std::unique_ptr<NativeElfFunctionCache>                              existingElfFunctionCache_;
    std::unordered_map<Utf8, NativeFunctionCacheEntry>                   existingFunctionCacheEntries_;
    std::unordered_map<const SymbolFunction*, NativeFunctionCacheRecord> functionCacheRecords_;
    mutable std::mutex                                                   functionCacheMutex_;

    fs::path functionCacheArchivePath_;
    fs::path functionCacheIndexPath_;
    bool     functionCacheEnabled_ = false;
};

SWC_END_NAMESPACE();
