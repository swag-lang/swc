#pragma once

#include "Backend/Native/NativeBackend_Priv.h"

SWC_BEGIN_NAMESPACE();

namespace NativeBackendDetail
{
    class NativeObjJob;
    class NativeObjectFileWriterWindowsCoff;

    class NativeBackendBuilder
    {
        friend class NativeObjJob;
        friend class NativeObjectFileWriterWindowsCoff;

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
