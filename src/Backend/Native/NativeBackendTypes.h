#pragma once
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Support/Os/Os.h"

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
    uint32_t           jobIndex   = 0;
    uint32_t           textOffset = 0;
    bool               exported   = false;
    bool               compilerFn = false;
};

struct NativeStartupInfo
{
    MachineCode code;
    Utf8        symbolName = "mainCRTStartup";
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

struct NativeObjDescription
{
    uint32_t                         index = 0;
    fs::path                         objPath;
    std::vector<NativeFunctionInfo*> functions;
    NativeStartupInfo*               startup     = nullptr;
    bool                             includeData = false;
};

struct NativeBackendState
{
    std::vector<SymbolFunction*>                                   rawFunctions;
    std::vector<SymbolFunction*>                                   rawTestFunctions;
    std::vector<SymbolFunction*>                                   rawInitFunctions;
    std::vector<SymbolFunction*>                                   rawPreMainFunctions;
    std::vector<SymbolFunction*>                                   rawDropFunctions;
    std::vector<SymbolFunction*>                                   rawMainFunctions;
    std::vector<SymbolVariable*>                                   regularGlobals;
    std::vector<NativeFunctionInfo>                                functionInfos;
    std::unordered_map<SymbolFunction*, const NativeFunctionInfo*> functionBySymbol;
    std::unique_ptr<NativeStartupInfo>                             startup;
    NativeSectionData                                              mergedRData;
    NativeSectionData                                              mergedData;
    NativeSectionData                                              mergedBss;
    std::array<uint32_t, ConstantManager::SHARD_COUNT>             rdataShardBaseOffsets{};
    std::vector<NativeObjDescription>                              objectDescriptions;
    fs::path                                                       workDir;
    fs::path                                                       artifactPath;
    std::atomic<bool>                                              objWriteFailed = false;
};

class NativeBackendBuilder;
class NativeArtifactBuilder;
class NativeLinker;
class NativeLinkerCoff;
class NativeObjJob;
class NativeObjFileWriter;
class NativeObjFileWriterCoff;
class NativeSymbolCollector;

SWC_END_NAMESPACE();
