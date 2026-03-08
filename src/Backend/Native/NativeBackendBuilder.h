#pragma once

#include "Backend/Native/NativeBackendTypes.h"
#include "Support/Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE();

class NativeBackendBuilder
{
public:
    NativeBackendBuilder(CompilerInstance& compiler, bool runArtifact);

    TaskContext&            ctx();
    const TaskContext&      ctx() const;
    CompilerInstance&       compiler();
    const CompilerInstance& compiler() const;

    Result run();
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
