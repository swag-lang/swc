#pragma once
#include "Backend/Linker/LinkJob.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Support/Math/Hash.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

struct MicroRelocation;
class Linker;

inline constexpr auto K_R_DATA_BASE_SYMBOL = "__swc_rdata_base";
inline constexpr auto K_DATA_BASE_SYMBOL   = "__swc_data_base";
inline constexpr auto K_BSS_BASE_SYMBOL    = "__swc_bss_base";

inline Utf8 nativeArtifactScopeName(const CompilerInstance& compiler)
{
    const Runtime::String& artifactName = compiler.buildCfg().name;
    if (artifactName.ptr && artifactName.length)
        return Utf8{artifactName};
    if (!compiler.cmdLine().name.empty())
        return compiler.cmdLine().name;
    if (!compiler.cmdLine().modulePath.empty())
        return Utf8(compiler.cmdLine().modulePath.filename().string());
    if (!compiler.cmdLine().moduleFilePath.empty())
        return Utf8(compiler.cmdLine().moduleFilePath.parent_path().filename().string());
    return "module";
}

inline Utf8 nativeScopedSectionBaseSymbol(const CompilerInstance& compiler, std::string_view baseName)
{
    return std::format("{}_{:08x}", baseName, Math::hash(nativeArtifactScopeName(compiler).view()));
}

inline Utf8 unresolvedFunctionSymbolName(const TaskContext& ctx, const SymbolFunction& function)
{
    Utf8 key = function.getFullScopedName(ctx);
    key += "|";
    key += std::to_string(function.tokRef().get());
    return std::format("__swc_ext_fn_{:08x}", Math::hash(key.view()));
}

enum class NativeObjectFormat : uint8_t
{
    WindowsCoff,
};

inline std::optional<NativeObjectFormat> getNativeObjFormat(const Runtime::TargetOs targetOs)
{
    switch (targetOs)
    {
        case Runtime::TargetOs::Windows:
            return NativeObjectFormat::WindowsCoff;
        default:
            return std::nullopt;
    }
}

struct NativeFunctionInfo
{
    SymbolFunction*    symbol      = nullptr;
    const MachineCode* machineCode = nullptr;
    Utf8               sortKey;
    Utf8               symbolName;
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

struct NativeSectionRelocation
{
    uint32_t offset = 0;
    Utf8     symbolName;
    uint64_t addend = 0;
    uint16_t type   = IMAGE_REL_AMD64_ADDR64;
};

struct NativeSectionData
{
    Utf8                                 name;
    std::vector<std::byte>               bytes;
    std::vector<NativeSectionRelocation> relocations;
    uint32_t                             characteristics = 0;
    bool                                 bss             = false;
    uint32_t                             bssSize         = 0;
};

struct NativeCodeRelocationTarget
{
    std::vector<std::byte>*               bytes                  = nullptr;
    std::vector<NativeSectionRelocation>* relocations            = nullptr;
    uint32_t                              functionOffset         = 0;
    bool                                  allowUnresolvedSymbols = false;
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
    std::vector<std::byte>           objBytes;
    std::vector<NativeFunctionInfo*> functions;
    NativeStartupInfo*               startup                = nullptr;
    bool                             includeData            = false;
    bool                             allowUnresolvedSymbols = false;
};

class NativeBackendBuilder
{
public:
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

    Result run();
    Result runExistingArtifact();
    Result prepare();
    Result buildObject(uint32_t objIndex);

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

private:
    Result validateTarget();
    Result buildObjects();
    Result runGeneratedArtifact();
    Result runAfterLink();

    TaskContext             ctx_;
    CompilerInstance*       compiler_    = nullptr;
    bool                    runArtifact_ = false;
    DiagnosticId            lastErrorId_ = DiagnosticId::None;
    std::unique_ptr<Linker> deferredLinker_;
    LinkJob                 deferredToolRun_;
};

SWC_END_NAMESPACE();
