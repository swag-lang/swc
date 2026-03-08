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

namespace NativeBackendDetail
{
    inline constexpr auto K_RDataBaseSymbol = "__swc_rdata_base";
    inline constexpr auto K_DataBaseSymbol  = "__swc_data_base";
    inline constexpr auto K_BssBaseSymbol   = "__swc_bss_base";

    Utf8                makeUtf8(const fs::path& path);
    std::wstring        toWide(std::string_view value);
    void                appendQuotedCommandArg(std::wstring& out, std::wstring_view arg);
    std::optional<Utf8> readEnvUtf8(const char* name);

    struct NativeToolchain
    {
        fs::path linkExe;
        fs::path libExe;
        fs::path vcLibPath;
        fs::path sdkUmLibPath;
        fs::path sdkUcrtLibPath;
    };

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

    struct CoffSymbolRecord
    {
        Utf8     name;
        int16_t  sectionNumber = 0;
        uint32_t value         = 0;
        uint16_t type          = 0;
        uint8_t  storageClass  = 0;
        uint8_t  numAuxSymbols = 0;
    };

    struct CoffSectionBuild
    {
        NativeSectionData                    data;
        std::vector<NativeSectionRelocation> relocations;
        uint16_t                             sectionNumber        = 0;
        uint32_t                             pointerToRawData     = 0;
        uint32_t                             pointerToRelocations = 0;
        uint16_t                             numberOfRelocations  = 0;
        uint32_t                             sizeOfRawData        = 0;
    };

    class NativeBackendBuilder;

    class NativeObjJob final : public Job
    {
    public:
        static constexpr auto K = JobKind::NativeObj;

        NativeObjJob(const TaskContext& ctx, NativeBackendBuilder& builder, uint32_t objIndex);

    private:
        JobResult exec();

        NativeBackendBuilder* builder_  = nullptr;
        uint32_t              objIndex_ = 0;
    };

    class NativeBackendBuilder
    {
        friend class NativeObjJob;

    public:
        NativeBackendBuilder(CompilerInstance& compiler, bool runArtifact);
        Result run();
        bool   writeObject(uint32_t objIndex);

    private:
        enum class CompilerFunctionKind : uint8_t
        {
            None,
            Test,
            Init,
            PreMain,
            Drop,
            Main,
            Excluded,
        };

        template<typename T>
        void sortAndUnique(std::vector<T*>& values) const;

        bool                 validateHost() const;
        bool                 collectSymbols();
        void                 collectSymbolsRec(const SymbolMap& symbolMap);
        void                 collectFunction(SymbolFunction& symbol);
        CompilerFunctionKind classifyCompilerFunction(const SymbolFunction& symbol) const;
        static bool          isCompilerFunction(const SymbolFunction& symbol);
        Utf8                 makeSymbolSortKey(const SymbolFunction& symbol) const;
        Utf8                 makeSortKey(const SymbolFunction& symbol) const;
        Utf8                 makeSortKey(const SymbolVariable& symbol) const;
        bool                 scheduleCodeGen();
        bool                 validateNativeData() const;
        bool                 isNativeStaticType(TypeRef typeRef) const;
        bool                 validateRelocations(const SymbolFunction& owner, const MachineCode& code) const;
        bool                 validateConstantRelocation(const MicroRelocation& relocation) const;
        bool                 prepareDataSections();
        bool                 buildStartup();
        bool                 partitionObjects();
        Utf8                 artifactBaseName() const;
        Utf8                 artifactExtension() const;
        bool                 createWorkDirectory(const Utf8& baseName);
        bool                 writeObjects();
        bool                 discoverToolchain();
        bool                 discoverMsvcToolchain();
        bool                 discoverWindowsSdk();
        bool                 linkArtifact() const;
        std::vector<Utf8>    buildLinkArguments(bool dll) const;
        std::vector<Utf8>    buildLibArguments() const;
        void                 appendLinkSearchPaths(std::vector<Utf8>& args) const;
        void                 collectLinkLibraries(std::set<Utf8>& out) const;
        static Utf8          normalizeLibraryName(std::string_view value);
        void                 appendUserLinkerArgs(std::vector<Utf8>& args) const;
        bool                 runGeneratedArtifact() const;
        bool                 runProcess(const fs::path& exePath, const std::vector<Utf8>& args, const fs::path& workingDirectory, uint32_t& outExitCode) const;
        bool                 writeObjectFile(const NativeObjDescription& description);
        bool                 buildTextSection(const NativeObjDescription& description, CoffSectionBuild& textSection);
        bool                 appendCodeRelocations(const NativeStartupInfo& startup, const MachineCode& code, CoffSectionBuild& textSection);
        bool                 appendCodeRelocations(const NativeFunctionInfo& owner, const MachineCode& code, CoffSectionBuild& textSection);
        bool                 appendSingleCodeRelocation(uint32_t functionOffset, const MicroRelocation& relocation, CoffSectionBuild& textSection);
        bool                 buildDataRelocations(CoffSectionBuild& section) const;
        static void          writeU64(std::vector<std::byte>& bytes, uint32_t offset, uint64_t value);
        static void          addDefinedSymbols(const NativeObjDescription& description, const std::vector<CoffSectionBuild>& sections, std::vector<CoffSymbolRecord>& symbols, std::unordered_map<Utf8, uint32_t>& symbolIndices);
        static void          addUndefinedSymbols(const std::vector<CoffSectionBuild>& sections, std::vector<CoffSymbolRecord>& symbols, std::unordered_map<Utf8, uint32_t>& symbolIndices);
        bool                 flushCoffFile(const fs::path& objPath, std::vector<CoffSectionBuild>& sections, const std::vector<CoffSymbolRecord>& symbols, const std::unordered_map<Utf8, uint32_t>& symbolIndices) const;
        bool                 reportError(std::string_view because) const;
        static Utf8          sanitizeName(Utf8 value);

        TaskContext                                                    ctx_;
        CompilerInstance&                                              compiler_;
        bool                                                           runArtifact_ = false;
        std::vector<SymbolFunction*>                                   rawFunctions_;
        std::vector<SymbolFunction*>                                   rawTestFunctions_;
        std::vector<SymbolFunction*>                                   rawInitFunctions_;
        std::vector<SymbolFunction*>                                   rawPreMainFunctions_;
        std::vector<SymbolFunction*>                                   rawDropFunctions_;
        std::vector<SymbolFunction*>                                   rawMainFunctions_;
        std::vector<SymbolVariable*>                                   regularGlobals_;
        std::vector<NativeFunctionInfo>                                functionInfos_;
        std::unordered_map<SymbolFunction*, const NativeFunctionInfo*> functionBySymbol_;
        std::unique_ptr<NativeStartupInfo>                             startup_;
        NativeSectionData                                              mergedRData_;
        NativeSectionData                                              mergedData_;
        NativeSectionData                                              mergedBss_;
        std::array<uint32_t, ConstantManager::SHARD_COUNT>             rdataShardBaseOffsets_{};
        std::vector<NativeObjDescription>                              objectDescriptions_;
        NativeToolchain                                                toolchain_;
        fs::path                                                       workDir_;
        fs::path                                                       artifactPath_;
        std::atomic<bool>                                              objWriteFailed_ = false;
    };
}

SWC_END_NAMESPACE();
