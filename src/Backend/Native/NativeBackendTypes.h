#pragma once

#include "Backend/ABI/ABICall.h"
#include "Backend/Native/NativeBackend.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Math/Hash.h"
#include "Support/Math/Helpers.h"
#include "Support/Memory/Heap.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Thread/JobManager.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE();

inline constexpr auto K_RDataBaseSymbol = "__swc_rdata_base";
inline constexpr auto K_DataBaseSymbol  = "__swc_data_base";
inline constexpr auto K_BssBaseSymbol   = "__swc_bss_base";

enum class NativeObjectFormat : uint8_t
{
    WindowsCoff,
};

inline std::optional<NativeObjectFormat> getNativeObjectFormat(const Runtime::TargetOs targetOs)
{
    switch (targetOs)
    {
        case Runtime::TargetOs::Windows:
            return NativeObjectFormat::WindowsCoff;

        case Runtime::TargetOs::Linux:
            return std::nullopt;

        default:
            return std::nullopt;
    }
}

inline Utf8 makeUtf8(const fs::path& path)
{
    return {path.generic_string()};
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
class NativeObjectFileWriter;
class NativeObjectFileWriterWindowsCoff;
class NativeSymbolCollector;

SWC_END_NAMESPACE();
