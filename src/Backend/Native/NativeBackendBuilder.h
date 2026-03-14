#pragma once
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

inline constexpr auto K_R_DATA_BASE_SYMBOL = "__swc_rdata_base";
inline constexpr auto K_DATA_BASE_SYMBOL   = "__swc_data_base";
inline constexpr auto K_BSS_BASE_SYMBOL    = "__swc_bss_base";

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
    std::vector<NativeFunctionInfo*> functions;
    NativeStartupInfo*               startup                = nullptr;
    bool                             includeData            = false;
    bool                             allowUnresolvedSymbols = false;
};

class NativeBackendBuilder
{
public:
    NativeBackendBuilder(CompilerInstance& compiler, bool runArtifact);

    TaskContext&            ctx();
    const TaskContext&      ctx() const;
    CompilerInstance&       compiler();
    const CompilerInstance& compiler() const;
    bool                    tryMapRDataSourceOffset(uint32_t& outOffset, uint32_t shardIndex, uint32_t sourceOffset) const noexcept;

    Result run();
    Result prepare();
    Result writeObject(uint32_t objIndex);

    Result reportError(DiagnosticId id) const;

    template<typename T1>
    Result reportError(DiagnosticId id, std::string_view name1, T1&& value1) const
    {
        Diagnostic diag = Diagnostic::get(id);
        diag.addArgument(name1, std::forward<T1>(value1));
        return reportError(std::move(diag));
    }

    template<typename T1, typename T2>
    Result reportError(DiagnosticId id, std::string_view name1, T1&& value1, std::string_view name2, T2&& value2) const
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
    std::vector<NativeFunctionInfo>                                                      functionInfos;
    std::unordered_map<SymbolFunction*, const NativeFunctionInfo*>                       functionBySymbol;
    std::unique_ptr<NativeStartupInfo>                                                   startup;
    NativeSectionData                                                                    mergedRData;
    NativeSectionData                                                                    mergedData;
    NativeSectionData                                                                    mergedBss;
    std::array<std::vector<NativeRDataAllocationMapEntry>, ConstantManager::SHARD_COUNT> rdataAllocationMap;
    std::vector<NativeObjDescription>                                                    objectDescriptions;
    fs::path                                                                             buildDir;
    fs::path                                                                             artifactPath;
    fs::path                                                                             pdbPath;
    std::atomic<bool>                                                                    objWriteFailed = false;

private:
    Result reportError(const Diagnostic& diag) const;
    Result validateTarget() const;
    Result writeObjects();
    Result runGeneratedArtifact() const;

    TaskContext       ctx_;
    CompilerInstance& compiler_;
    bool              runArtifact_ = false;
};

SWC_END_NAMESPACE();
