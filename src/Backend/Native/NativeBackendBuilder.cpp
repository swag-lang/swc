#include "pch.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Linker/Linker.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/Native/NativeObjFileWriter.h"
#include "Backend/Native/NativeObjJob.h"
#include "Backend/Native/SymbolSort.h"
#include "Backend/RuntimeName.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Math/Hash.h"
#include "Support/Memory/Heap.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Report/Logger.h"
#include "Support/Report/ScopedTimedAction.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Utf8 lowerPathExtension(const fs::path& path)
    {
        Utf8 result = path.extension().string();
        result.make_lower();
        return result;
    }

    bool isPublishDependencyExtension(const Utf8& extension)
    {
        return extension == ".dll" || extension == ".pdb";
    }

    bool publishDependencyFilesHaveSameContent(const fs::path& lhsPath, const fs::path& rhsPath)
    {
        FileSystem::IoErrorInfo ioError;
        std::vector<std::byte>  lhsData;
        if (FileSystem::readBinaryFile(lhsPath, lhsData, ioError) != Result::Continue)
            return false;

        std::vector<std::byte> rhsData;
        if (FileSystem::readBinaryFile(rhsPath, rhsData, ioError) != Result::Continue)
            return false;

        return lhsData == rhsData;
    }

    bool isCompilerFunction(const SymbolFunction& symbol)
    {
        return symbol.decl() && symbol.decl()->id() == AstNodeId::CompilerFunc;
    }

    void writeU64(std::vector<std::byte>& bytes, const uint32_t offset, const uint64_t value)
    {
        std::memcpy(bytes.data() + offset, &value, sizeof(value));
    }

    bool shouldCopyPublishDependencyFile(const fs::path& srcPath, const fs::path& dstPath)
    {
        std::error_code ec;
        const bool      dstExists = fs::exists(dstPath, ec);
        if (ec || !dstExists)
            return true;

        ec.clear();
        if (!fs::is_regular_file(dstPath, ec) || ec)
            return true;

        ec.clear();
        const uintmax_t srcSize = fs::file_size(srcPath, ec);
        if (ec)
            return true;

        ec.clear();
        const uintmax_t dstSize = fs::file_size(dstPath, ec);
        if (ec || srcSize != dstSize)
            return true;

        ec.clear();
        const auto srcTime = fs::last_write_time(srcPath, ec);
        if (ec)
            return true;

        ec.clear();
        const auto dstTime = fs::last_write_time(dstPath, ec);
        if (ec)
            return true;

        if (srcTime != dstTime)
            return true;

        return !publishDependencyFilesHaveSameContent(srcPath, dstPath);
    }

    Utf8 buildLocalFunctionSymbolName(const NativeBackendBuilder& builder, const NativeFunctionInfo& info, const uint32_t ordinal)
    {
        const uint32_t scopeHash = Math::hash(nativeArtifactScopeName(builder.compiler()).view());
        return std::format("__swc_fn_{:08x}_{:06}_{:08x}", scopeHash, ordinal, Math::hash(info.sortKey));
    }

    bool supportsExportedPublicFunctionSymbols(const NativeBackendBuilder& builder)
    {
        switch (builder.compiler().buildCfg().backendKind)
        {
            case Runtime::BuildCfgBackendKind::StaticLibrary:
            case Runtime::BuildCfgBackendKind::SharedLibrary:
                return true;

            default:
                return false;
        }
    }

    SymbolFunction* createRuntimeDependencyHookSymbol(NativeBackendBuilder& builder, const NativeRuntimeDependency& dependency)
    {
        constexpr SymbolFlags syntheticFlags = SymbolFlagsE::Declared | SymbolFlagsE::Typed | SymbolFlagsE::SemaCompleted;

        const IdentifierRef idRef = builder.ctx().idMgr().addIdentifier(dependency.hookSymbolName.view());
        auto*               hook  = Symbol::make<SymbolFunction>(builder.ctx(), nullptr, TokenRef::invalid(), idRef, syntheticFlags);
        hook->setReturnTypeRef(builder.ctx().typeMgr().typeVoid());
        hook->setCallConvKind(CallConvKind::Swag);
        hook->ensureAttributes(builder.ctx()).setForeign(dependency.linkModuleName.view(), dependency.hookSymbolName.view(), dependency.linkModuleName.view(), CallConvKind::Swag);
        return hook;
    }

    void buildRuntimeDependencyOrders(NativeBackendBuilder& builder)
    {
        builder.runtimeDependencyInitOrder.clear();
        builder.runtimeDependencyDropOrder.clear();
        if (builder.runtimeDependencies.empty())
            return;

        std::unordered_map<Utf8, uint32_t> dependencyIndices;
        dependencyIndices.reserve(builder.runtimeDependencies.size());
        for (uint32_t i = 0; i < builder.runtimeDependencies.size(); ++i)
            dependencyIndices.emplace(builder.runtimeDependencies[i].moduleName, i);

        std::vector<std::vector<uint32_t>> outgoing(builder.runtimeDependencies.size());
        std::vector<uint32_t>              indegree(builder.runtimeDependencies.size(), 0);
        for (uint32_t i = 0; i < builder.runtimeDependencies.size(); ++i)
        {
            std::unordered_set<uint32_t> directDependencies;
            for (const Utf8& importedModule : builder.runtimeDependencies[i].transitiveImports)
            {
                const auto it = dependencyIndices.find(importedModule);
                if (it == dependencyIndices.end() || it->second == i || !directDependencies.insert(it->second).second)
                    continue;

                outgoing[it->second].push_back(i);
                indegree[i] += 1;
            }
        }

        builder.runtimeDependencyInitOrder.reserve(builder.runtimeDependencies.size());
        std::vector scheduled(builder.runtimeDependencies.size(), false);
        while (builder.runtimeDependencyInitOrder.size() < builder.runtimeDependencies.size())
        {
            bool progressed = false;
            for (uint32_t i = 0; i < builder.runtimeDependencies.size(); ++i)
            {
                if (scheduled[i] || indegree[i] != 0)
                    continue;

                scheduled[i] = true;
                builder.runtimeDependencyInitOrder.push_back(i);
                for (const uint32_t dependentIndex : outgoing[i])
                {
                    SWC_ASSERT(indegree[dependentIndex] != 0);
                    indegree[dependentIndex] -= 1;
                }

                progressed = true;
                break;
            }

            if (progressed)
                continue;

            for (uint32_t i = 0; i < builder.runtimeDependencies.size(); ++i)
            {
                if (scheduled[i])
                    continue;

                scheduled[i] = true;
                builder.runtimeDependencyInitOrder.push_back(i);
            }
        }

        builder.runtimeDependencyDropOrder = builder.runtimeDependencyInitOrder;
        std::ranges::reverse(builder.runtimeDependencyDropOrder);
    }

    template<typename T>
    const SourceFile* sourceFileForSymbol(const NativeBackendBuilder& builder, const T& symbol)
    {
        return builder.compiler().srcView(symbol.srcViewRef()).file();
    }

    bool isNativeArtifactCompilerFunction(const TokenId tokenId)
    {
        switch (tokenId)
        {
            case TokenId::CompilerFuncTest:
            case TokenId::CompilerFuncInit:
            case TokenId::CompilerFuncDrop:
            case TokenId::CompilerFuncMain:
            case TokenId::CompilerFuncPreMain:
                return true;

            default:
                return false;
        }
    }

    bool isRuntimeArtifactFunction(const NativeBackendBuilder& builder, const SymbolFunction& symbol)
    {
        if (symbol.attributes().hasRtFlag(RtAttributeFlagsE::Macro) || symbol.attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
            return false;
        if (symbol.attributes().hasRtFlag(RtAttributeFlagsE::Compiler))
            return false;
        if (symbol.hasUnmaterializedGenericBody())
            return false;

        const AstNode* decl = symbol.decl();
        if (!decl)
            return true;

        if (decl->id() == AstNodeId::CompilerRunBlock || decl->id() == AstNodeId::CompilerRunExpr)
            return false;
        if (decl->id() != AstNodeId::CompilerFunc)
            return true;

        const TokenId tokenId = builder.compiler().srcView(symbol.srcViewRef()).token(symbol.tokRef()).id;
        return isNativeArtifactCompilerFunction(tokenId);
    }

    bool shouldPrepareFile(const SourceFile* file)
    {
        if (!file)
            return true;

        return file->ast().srcView().runsNativeArtifact();
    }

    template<typename T>
    bool shouldPrepareSymbol(const NativeBackendBuilder& builder, const T& symbol)
    {
        return shouldPrepareFile(sourceFileForSymbol(builder, symbol));
    }

    template<>
    bool shouldPrepareSymbol<SymbolFunction>(const NativeBackendBuilder& builder, const SymbolFunction& symbol)
    {
        return !symbol.isIgnored() &&
               !symbol.isForeign() &&
               !symbol.isEmpty() &&
               !symbol.isAttribute() &&
               shouldPrepareFile(sourceFileForSymbol(builder, symbol)) &&
               isRuntimeArtifactFunction(builder, symbol);
    }

    template<typename T>
    void filterPreparedSymbols(std::vector<T*>& values, const NativeBackendBuilder& builder)
    {
        size_t writeIndex = 0;
        for (size_t readIndex = 0; readIndex < values.size(); ++readIndex)
        {
            T* symbol = values[readIndex];
            if (symbol == nullptr || !shouldPrepareSymbol(builder, *symbol))
                continue;

            values[writeIndex++] = symbol;
        }

        values.resize(writeIndex);
    }

    bool isIncludableDependency(const NativeBackendBuilder& builder, const SymbolFunction& fn)
    {
        if (fn.isIgnored())
            return false;
        if (fn.isForeign() || fn.isEmpty() || fn.isAttribute())
            return false;
        if (fn.attributes().hasRtFlag(RtAttributeFlagsE::Macro) || fn.attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
            return false;
        return shouldPrepareSymbol(builder, fn) && (fn.isSemaCompleted() || fn.hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBody));
    }

    bool appendCodeGenDependencies(const NativeBackendBuilder& builder, std::vector<SymbolFunction*>& functions)
    {
        bool               changed = false;
        std::unordered_set seenFunctions(functions.begin(), functions.end());
        for (size_t idx = 0; idx < functions.size(); ++idx)
        {
            const SymbolFunction* function = functions[idx];
            SWC_ASSERT(function != nullptr);

            SmallVector<SymbolFunction*> deps;
            function->appendCallDependencies(deps);
            for (SymbolFunction* dep : deps)
            {
                if (!dep || !isIncludableDependency(builder, *dep))
                    continue;
                if (!seenFunctions.insert(dep).second)
                    continue;

                functions.push_back(dep);
                changed = true;
            }
        }

        return changed;
    }

    bool appendConstantFunctionDependenciesRec(const NativeBackendBuilder& builder, std::vector<SymbolFunction*>& functions, std::unordered_set<SymbolFunction*>& seenFunctions, std::unordered_set<uint64_t>& visitedAllocations, const uint32_t shardIndex, const uint32_t sourceOffset)
    {
        const DataSegment&    segment = builder.compiler().cstMgr().shardDataSegment(shardIndex);
        DataSegmentAllocation allocation;
        if (!segment.findAllocation(allocation, sourceOffset))
            return false;

        const uint64_t allocationKey = (static_cast<uint64_t>(shardIndex) << 32) | allocation.offset;
        if (!visitedAllocations.insert(allocationKey).second)
            return false;

        bool                               changed = false;
        std::vector<DataSegmentRelocation> relocations;
        segment.copyRelocations(relocations, allocation.offset, allocation.size);
        for (const DataSegmentRelocation& relocation : relocations)
        {
            if (relocation.kind == DataSegmentRelocationKind::FunctionSymbol)
            {
                auto target = const_cast<SymbolFunction*>(relocation.targetSymbol);
                if (!target || !isIncludableDependency(builder, *target))
                    continue;
                if (!seenFunctions.insert(target).second)
                    continue;

                functions.push_back(target);
                changed = true;
                continue;
            }

            const uint32_t targetShardIndex = relocation.targetShardIndex == INVALID_REF ? shardIndex : relocation.targetShardIndex;
            changed                         = appendConstantFunctionDependenciesRec(builder, functions, seenFunctions, visitedAllocations, targetShardIndex, relocation.targetOffset) || changed;
        }

        return changed;
    }

    bool appendConstantFunctionDependencies(const NativeBackendBuilder& builder, std::vector<SymbolFunction*>& functions)
    {
        std::unordered_set           seenFunctions(functions.begin(), functions.end());
        std::unordered_set<uint64_t> visitedAllocations;
        bool                         changed = false;

        // Newly discovered constant dependencies are appended to 'functions', so iterate by
        // index to keep traversal stable while still visiting the new entries in the same pass.
        for (size_t idx = 0; idx < functions.size(); ++idx)
        {
            const SymbolFunction* function = functions[idx];
            if (!function)
                continue;

            const MachineCode& code = function->loweredCode();
            for (const MicroRelocation& relocation : code.codeRelocations)
            {
                if (relocation.kind != MicroRelocation::Kind::ConstantAddress)
                    continue;

                DataSegmentRef sourceRef;
                if (!builder.tryResolveConstantSourceRef(sourceRef, relocation))
                    continue;

                changed = appendConstantFunctionDependenciesRec(builder, functions, seenFunctions, visitedAllocations, sourceRef.shardIndex, sourceRef.offset) || changed;
            }
        }

        return changed;
    }

    bool appendGlobalFunctionInitDependencies(const NativeBackendBuilder& builder, std::vector<SymbolFunction*>& functions, const std::span<SymbolVariable* const> globals)
    {
        bool               changed = false;
        std::unordered_set seenFunctions(functions.begin(), functions.end());
        for (const SymbolVariable* global : globals)
        {
            if (!global)
                continue;

            SymbolFunction* target = global->globalFunctionInit();
            if (!target || !isIncludableDependency(builder, *target))
                continue;
            if (!seenFunctions.insert(target).second)
                continue;

            functions.push_back(target);
            changed = true;
        }

        return changed;
    }

    void rebuildFunctionInfos(NativeBackendBuilder& builder, const std::vector<SymbolFunction*>& functions)
    {
        builder.functionInfos.clear();
        builder.functionBySymbol.clear();

        for (SymbolFunction* symbol : functions)
        {
            SWC_ASSERT(symbol != nullptr);

            NativeFunctionInfo info;
            info.symbol                   = symbol;
            info.machineCode              = &symbol->loweredCode();
            info.sortKey                  = SymbolSort::locationKey(builder.compiler(), *symbol);
            const bool exportPublicSymbol = supportsExportedPublicFunctionSymbols(builder) && symbol->isPublic() && !isCompilerFunction(*symbol) && symbol->supportsPublicApiForeignExport();
            if (exportPublicSymbol)
                info.symbolName = symbol->computePublicApiSymbolName(builder.ctx());
            else
                info.symbolName = buildLocalFunctionSymbolName(builder, info, static_cast<uint32_t>(builder.functionInfos.size()));
            info.debugName  = symbol->getFullScopedName(builder.ctx());
            info.exported   = exportPublicSymbol;
            info.compilerFn = isCompilerFunction(*symbol);
            builder.functionInfos.push_back(std::move(info));
        }

        for (const auto& info : builder.functionInfos)
            builder.functionBySymbol.emplace(info.symbol, &info);
    }

    Result scheduleCodeGen(NativeBackendBuilder& builder)
    {
        if (builder.functionInfos.empty())
            return Result::Continue;

        SourceFile* firstFile = nullptr;
        for (SourceFile* file : builder.compiler().files())
        {
            if (file && file->moduleNamespace())
            {
                firstFile = file;
                break;
            }
        }

        if (!firstFile)
            return builder.reportError(DiagnosticId::cmd_err_native_codegen_source_missing);

        Sema        baseSema(builder.ctx(), firstFile->nodePayloadContext(), false);
        JobManager& jobMgr = builder.ctx().global().jobMgr();
        for (const auto& info : builder.functionInfos)
        {
            SWC_ASSERT(info.symbol != nullptr);
            if (info.symbol->isCodeGenCompleted() || !info.symbol->loweredCode().bytes.empty())
                continue;
            if (!info.symbol->tryMarkCodeGenJobScheduled())
                continue;

            const AstNodeRef root = info.symbol->declNodeRef();
            if (root.isInvalid())
                return builder.reportError(DiagnosticId::cmd_err_native_codegen_decl_missing, Diagnostic::ARG_SYM, info.symbolName);

            auto* job = heapNew<CodeGenJob>(builder.ctx(), baseSema, *info.symbol, root);
            jobMgr.enqueue(*job, JobPriority::Normal, builder.compiler().jobClientId());
        }

        Sema::waitDone(builder.ctx(), builder.compiler().jobClientId());
        if (Stats::hasError())
            return Result::Error;

        for (const auto& info : builder.functionInfos)
        {
            if (!info.machineCode || info.machineCode->bytes.empty())
            {
                const Utf8& reportedName = info.debugName.empty() ? info.symbolName : info.debugName;
                return builder.reportError(DiagnosticId::cmd_err_native_codegen_machine_code_missing, Diagnostic::ARG_SYM, reportedName);
            }
        }

        return Result::Continue;
    }
}

NativeBackendBuilder::NativeBackendBuilder(CompilerInstance& compiler, const bool runArtifact) :
    ctx_(compiler),
    compiler_(&compiler),
    runArtifact_(runArtifact)
{
}

// Defined here (not defaulted in the header) so the unique_ptr<Linker> member can be destroyed
// with the complete Linker type, which is only visible in this translation unit.
NativeBackendBuilder::~NativeBackendBuilder() = default;

TaskContext& NativeBackendBuilder::ctx()
{
    return ctx_;
}

const TaskContext& NativeBackendBuilder::ctx() const
{
    return ctx_;
}

CompilerInstance& NativeBackendBuilder::compiler()
{
    SWC_ASSERT(compiler_ != nullptr);
    return *compiler_;
}

const CompilerInstance& NativeBackendBuilder::compiler() const
{
    SWC_ASSERT(compiler_ != nullptr);
    return *compiler_;
}

bool NativeBackendBuilder::tryResolveConstantSourceRef(DataSegmentRef& outSourceRef, const MicroRelocation& relocation) const noexcept
{
    outSourceRef = {};
    SWC_ASSERT(relocation.kind == MicroRelocation::Kind::ConstantAddress);
    if (relocation.hasConstantSource())
    {
        if (relocation.constantShard >= ConstantManager::SHARD_COUNT)
            return false;

        outSourceRef = {
            .shardIndex = relocation.constantShard,
            .offset     = relocation.constantOffset,
        };
        return true;
    }

    return compiler().cstMgr().resolveConstantDataSegmentRef(outSourceRef, relocation.constantRef, reinterpret_cast<const void*>(relocation.targetAddress));
}

Result NativeBackendBuilder::resolveConstantSourceRef(DataSegmentRef& outSourceRef, const Utf8& ownerName, const MicroRelocation& relocation)
{
    if (tryResolveConstantSourceRef(outSourceRef, relocation))
        return Result::Continue;

    return reportError(DiagnosticId::cmd_err_native_constant_storage_unsupported, Diagnostic::ARG_SYM, ownerName);
}

const NativeFunctionInfo* NativeBackendBuilder::tryFindFunctionInfo(const SymbolFunction& targetFunction) const noexcept
{
    const auto it = functionBySymbol.find(&targetFunction);
    if (it != functionBySymbol.end())
        return it->second;

    if (!targetFunction.srcViewRef().isValid())
        return nullptr;

    const Utf8 sortKey = SymbolSort::locationKey(compiler(), targetFunction);
    for (const NativeFunctionInfo& info : functionInfos)
    {
        if (info.sortKey == sortKey)
            return &info;
    }

    return nullptr;
}

Result NativeBackendBuilder::resolveFunctionSymbolName(Utf8& outName, const SymbolFunction* targetFunction, const bool allowUnresolvedSymbols)
{
    outName.clear();
    if (!targetFunction)
        return reportError(DiagnosticId::cmd_err_native_invalid_local_function_relocation, Diagnostic::ARG_SYM, Utf8("<null>"));

    if (targetFunction->isForeign())
    {
        outName = targetFunction->resolveForeignFunctionName(ctx());
        return Result::Continue;
    }

    if (const NativeFunctionInfo* info = tryFindFunctionInfo(*targetFunction))
    {
        outName = info->symbolName;
        return Result::Continue;
    }

    if (allowUnresolvedSymbols)
    {
        outName = unresolvedFunctionSymbolName(ctx(), *targetFunction);
        return Result::Continue;
    }

    return reportError(DiagnosticId::cmd_err_native_invalid_local_function_relocation, Diagnostic::ARG_SYM, targetFunction->getFullScopedName(ctx()));
}

Result NativeBackendBuilder::appendCodeRelocation(const NativeCodeRelocationTarget& target, const Utf8& ownerName, const MicroRelocation& relocation)
{
    SWC_ASSERT(target.bytes != nullptr);
    SWC_ASSERT(target.relocations != nullptr);
    if (!target.bytes || !target.relocations)
        return reportError(DiagnosticId::cmd_err_native_invalid_local_function_relocation, Diagnostic::ARG_SYM, ownerName);

    const uint32_t patchOffset = target.functionOffset + relocation.codeOffset;
    SWC_ASSERT(patchOffset + sizeof(uint64_t) <= target.bytes->size());

    NativeSectionRelocation record;
    record.offset = patchOffset;

    switch (relocation.kind)
    {
        case MicroRelocation::Kind::LocalFunctionAddress:
        case MicroRelocation::Kind::ForeignFunctionAddress:
        {
            const auto* targetFunction = relocation.targetSymbol ? relocation.targetSymbol->safeCast<SymbolFunction>() : nullptr;
            SWC_ASSERT(targetFunction != nullptr);
            SWC_RESULT(resolveFunctionSymbolName(record.symbolName, targetFunction, target.allowUnresolvedSymbols));
            record.addend = 0;
            writeU64(*target.bytes, patchOffset, 0);
            break;
        }

        case MicroRelocation::Kind::ConstantAddress:
        {
            DataSegmentRef sourceRef;
            SWC_RESULT(resolveConstantSourceRef(sourceRef, ownerName, relocation));
            uint32_t mappedOffset = 0;
            if (!tryMapRDataSourceOffset(mappedOffset, sourceRef.shardIndex, sourceRef.offset))
                return reportError(DiagnosticId::cmd_err_native_constant_payload_unsupported, Diagnostic::ARG_SYM, ownerName);

            record.symbolName = nativeScopedSectionBaseSymbol(compiler(), K_R_DATA_BASE_SYMBOL);
            record.addend     = mappedOffset;
            writeU64(*target.bytes, patchOffset, record.addend);
            break;
        }

        case MicroRelocation::Kind::GlobalInitAddress:
            record.symbolName = nativeScopedSectionBaseSymbol(compiler(), K_DATA_BASE_SYMBOL);
            record.addend     = relocation.targetAddress;
            writeU64(*target.bytes, patchOffset, record.addend);
            break;

        case MicroRelocation::Kind::GlobalZeroAddress:
            record.symbolName = nativeScopedSectionBaseSymbol(compiler(), K_BSS_BASE_SYMBOL);
            record.addend     = relocation.targetAddress;
            writeU64(*target.bytes, patchOffset, record.addend);
            break;

        case MicroRelocation::Kind::CompilerAddress:
            SWC_UNREACHABLE();
    }

    target.relocations->push_back(record);
    return Result::Continue;
}

bool NativeBackendBuilder::tryMapRDataSourceOffset(uint32_t& outOffset, const uint32_t shardIndex, const uint32_t sourceOffset) const noexcept
{
    outOffset = 0;
    if (shardIndex >= ConstantManager::SHARD_COUNT)
        return false;

    const auto& entries = rdataAllocationMap[shardIndex];
    if (entries.empty())
        return false;

    const auto it = std::ranges::upper_bound(entries, sourceOffset, {}, &NativeRDataAllocationMapEntry::sourceOffset);
    if (it == entries.begin())
        return false;

    const auto& entry = *std::prev(it);
    if (sourceOffset < entry.sourceOffset || sourceOffset - entry.sourceOffset >= entry.size)
        return false;

    outOffset = entry.emittedOffset + (sourceOffset - entry.sourceOffset);
    return true;
}

Result NativeBackendBuilder::run()
{
    SWC_MEM_SCOPE("Backend/Native");
    SWC_ASSERT(compiler_ != nullptr);
    SWC_RESULT(compiler_->ensureCompilerMessagePass(Runtime::CompilerMsgKind::PassBeforeOutput));
    SWC_RESULT(validateTarget());

    const NativeArtifactBuilder artifactBuilder(*this);
    NativeArtifactPaths         paths;
    artifactBuilder.queryPaths(paths);
    compiler_->setLastArtifactLabel(paths.artifactPath.filename().empty() ? Utf8(paths.artifactPath) : Utf8(paths.artifactPath.filename()));
    {
        ScopedTimedLog stage(ctx_, ScopedTimedLog::Stage::Build);

        SWC_RESULT(prepare());
        Utf8 buildStat = ScopedTimedLog::formatStatCount(ctx_, compiler_->nativeCodeSegment().size(), "function");
        if (!compiler_->lastArtifactLabel().empty())
            buildStat = ScopedTimedLog::joinStatItems(ctx_, {buildStat, ScopedTimedLog::formatStatName(ctx_, compiler_->lastArtifactLabel())});
        stage.setStat(std::move(buildStat));
        SWC_RESULT(artifactBuilder.build());
        SWC_RESULT(buildObjects());

        const auto linker = Linker::create(*this);
        SWC_ASSERT(linker != nullptr);
        SWC_RESULT(linker->link());
    }

    return runAfterLink();
}

// Builds everything up to but not including the link, leaving a prepared LinkJob in deferredToolRun_.
// Mirrors run() but stops short of executing the linker so the workspace pipeline can overlap the
// link with the next module's compilation. The link is excluded from the Build stage on purpose: in
// the deferred path it runs later, off this thread.
Result NativeBackendBuilder::prepareForLink()
{
    SWC_MEM_SCOPE("Backend/Native");
    SWC_ASSERT(compiler_ != nullptr);
    SWC_RESULT(compiler_->ensureCompilerMessagePass(Runtime::CompilerMsgKind::PassBeforeOutput));
    SWC_RESULT(validateTarget());

    const NativeArtifactBuilder artifactBuilder(*this);
    NativeArtifactPaths         paths;
    artifactBuilder.queryPaths(paths);
    compiler_->setLastArtifactLabel(paths.artifactPath.filename().empty() ? Utf8(paths.artifactPath) : Utf8(paths.artifactPath.filename()));
    {
        ScopedTimedLog stage(ctx_, ScopedTimedLog::Stage::Build);
        SWC_RESULT(prepare());
        Utf8 buildStat = ScopedTimedLog::formatStatCount(ctx_, compiler_->nativeCodeSegment().size(), "function");
        if (!compiler_->lastArtifactLabel().empty())
        {
            buildStat = ScopedTimedLog::joinStatItems(ctx_, {buildStat, ScopedTimedLog::formatStatName(ctx_, compiler_->lastArtifactLabel())});
        }
        stage.setStat(std::move(buildStat));
        SWC_RESULT(artifactBuilder.build());
        SWC_RESULT(buildObjects());
    }

    deferredLinker_ = Linker::create(*this);
    SWC_ASSERT(deferredLinker_ != nullptr);
    deferredToolRun_ = {};
    return deferredLinker_->prepareLink(deferredToolRun_);
}

// Foreground continuation of the deferred link: interpret the result of the background process,
// report diagnostics/output in order, then run the artifact if this is an executable run.
Result NativeBackendBuilder::finishDeferredLink()
{
    SWC_MEM_SCOPE("Backend/Native");
    SWC_ASSERT(deferredLinker_ != nullptr);
    SWC_RESULT(deferredLinker_->finishLink(deferredToolRun_));
    return runAfterLink();
}

Result NativeBackendBuilder::runAfterLink()
{
    if (runArtifact_ && compiler_->buildCfg().backendKind == Runtime::BuildCfgBackendKind::Executable)
        SWC_RESULT(runGeneratedArtifact());

    return Result::Continue;
}

Result NativeBackendBuilder::runExistingArtifact()
{
    SWC_MEM_SCOPE("Backend/Native");
    SWC_ASSERT(compiler_ != nullptr);
    if (compiler_->buildCfg().backendKind != Runtime::BuildCfgBackendKind::Executable)
        return Result::Continue;

    SWC_RESULT(validateTarget());

    const NativeArtifactBuilder artifactBuilder(*this);
    NativeArtifactPaths         paths;
    artifactBuilder.queryPaths(paths);
    buildDir     = paths.buildDir;
    artifactPath = paths.artifactPath;
    pdbPath      = paths.pdbPath;
    compiler_->setLastArtifactLabel(paths.artifactPath.filename().empty() ? Utf8(paths.artifactPath) : Utf8(paths.artifactPath.filename()));
    return runGeneratedArtifact();
}

Result NativeBackendBuilder::prepare()
{
    runtimeDependencies.clear();
    runtimeDependencyInitOrder.clear();
    runtimeDependencyDropOrder.clear();
    functionInfos.clear();
    functionBySymbol.clear();
    generatedMachineCodes.clear();
    SWC_ASSERT(compiler_ != nullptr);
    testFunctions    = compiler_->nativeTestFunctions();
    initFunctions    = compiler_->nativeInitFunctions();
    preMainFunctions = compiler_->nativePreMainFunctions();
    dropFunctions    = compiler_->nativeDropFunctions();
    mainFunctions    = compiler_->nativeMainFunctions();
    regularGlobals   = compiler_->nativeGlobalVariables();
    filterPreparedSymbols(testFunctions, *this);
    filterPreparedSymbols(initFunctions, *this);
    filterPreparedSymbols(preMainFunctions, *this);
    filterPreparedSymbols(dropFunctions, *this);
    filterPreparedSymbols(mainFunctions, *this);
    filterPreparedSymbols(regularGlobals, *this);

    auto functions = compiler_->nativeCodeSegment();
    filterPreparedSymbols(functions, *this);
    SymbolSort::sortAndUniqueByLocation(testFunctions, *compiler_);
    SymbolSort::sortAndUniqueByLocation(initFunctions, *compiler_);
    SymbolSort::sortAndUniqueByLocation(preMainFunctions, *compiler_);
    SymbolSort::sortAndUniqueByLocation(dropFunctions, *compiler_);
    SymbolSort::sortAndUniqueByLocation(mainFunctions, *compiler_);
    SymbolSort::sortAndUniqueByLocation(regularGlobals, *compiler_);
    appendGlobalFunctionInitDependencies(*this, functions, regularGlobals);

    const auto& importedRuntimeDeps = compiler_->nativeRuntimeImports();
    runtimeDependencies.reserve(importedRuntimeDeps.size());
    for (const auto& importedRuntimeDep : importedRuntimeDeps)
    {
        NativeRuntimeDependency dependency;
        dependency.moduleName        = importedRuntimeDep.moduleName;
        dependency.linkModuleName    = importedRuntimeDep.linkModuleName;
        dependency.hookSymbolName    = runtimeHookSymbolName(dependency.linkModuleName.view());
        dependency.transitiveImports = importedRuntimeDep.transitiveImports;
        runtimeDependencies.push_back(std::move(dependency));
    }

    for (auto& runtimeDependency : runtimeDependencies)
        runtimeDependency.hookSymbol = createRuntimeDependencyHookSymbol(*this, runtimeDependency);
    buildRuntimeDependencyOrders(*this);

    std::optional<ScopedTimedLog> microStage;
    if (ctx_.global().logger().claimStageOnce("micro"))
    {
        microStage.emplace(ctx_, ScopedTimedLog::Stage::Micro);
    }

    while (true)
    {
        appendCodeGenDependencies(*this, functions);
        SymbolSort::sortAndUniqueByLocation(functions, *compiler_);
        rebuildFunctionInfos(*this, functions);
        SWC_RESULT(scheduleCodeGen(*this));

        const bool addedCallDeps     = appendCodeGenDependencies(*this, functions);
        const bool addedConstantDeps = appendConstantFunctionDependencies(*this, functions);
        if (!addedCallDeps && !addedConstantDeps)
        {
            if (microStage)
                microStage->setStat(ScopedTimedLog::formatStatCount(ctx_, functions.size(), "function"));
            return Result::Continue;
        }
    }
}

Result NativeBackendBuilder::buildObject(const uint32_t objIndex)
{
    SWC_ASSERT(objIndex < objectDescriptions.size());
    const auto objectWriter = NativeObjFileWriter::create(*this);
    SWC_ASSERT(objectWriter != nullptr);
    NativeObjDescription& description = objectDescriptions[objIndex];
    return objectWriter->buildObjectFile(description.objBytes, description);
}

Result NativeBackendBuilder::publishExistingArtifact()
{
    SWC_ASSERT(compiler_ != nullptr);
    if (!ctx_.cmdLine().publish || compiler_->buildCfg().backendKind != Runtime::BuildCfgBackendKind::Executable)
        return Result::Continue;

    SWC_RESULT(validateTarget());

    const NativeArtifactBuilder artifactBuilder(*this);
    NativeArtifactPaths         paths;
    artifactBuilder.queryPaths(paths);
    buildDir     = paths.buildDir;
    artifactPath = paths.artifactPath;
    pdbPath      = paths.pdbPath;
    compiler_->setLastArtifactLabel(paths.artifactPath.filename().empty() ? Utf8(paths.artifactPath) : Utf8(paths.artifactPath.filename()));

    if (!fs::exists(artifactPath))
        return reportError(DiagnosticId::cmd_err_native_artifact_missing, Diagnostic::ARG_PATH, Utf8(artifactPath));

    return publishExecutableDependencies();
}

Result NativeBackendBuilder::publishExecutableDependencies()
{
    if (compiler_->buildCfg().backendKind != Runtime::BuildCfgBackendKind::Executable)
        return Result::Continue;

    const bool     publishDependencies = ctx_.cmdLine().publish;
    const fs::path artifactDir         = artifactPath.parent_path();
    if (artifactDir.empty())
        return Result::Continue;

    std::error_code ec;
    for (const fs::path& sourceDir : compiler_->importedDependencyLinkDirs())
    {
        if (sourceDir.empty())
            continue;

        const fs::path normalizedSourceDir = FileSystem::normalizePath(sourceDir);
        if (FileSystem::pathEquals(normalizedSourceDir, FileSystem::normalizePath(artifactDir)))
            continue;

        for (fs::directory_iterator it(normalizedSourceDir, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
                return reportError(DiagnosticId::cmd_err_native_publish_dependency_failed, Diagnostic::ARG_PATH, Utf8(normalizedSourceDir), Diagnostic::ARG_BECAUSE, FileSystem::normalizeSystemMessage(ec));

            ec.clear();
            if (!it->is_regular_file(ec) || ec)
                continue;
            if (!isPublishDependencyExtension(lowerPathExtension(it->path())))
                continue;

            const fs::path dstPath = (artifactDir / it->path().filename()).lexically_normal();
            if (FileSystem::pathEquals(FileSystem::normalizePath(it->path()), FileSystem::normalizePath(dstPath)))
                continue;

            if (!publishDependencies)
            {
                // Windows loads DLLs from the executable folder before PATH. If dependencies
                // were published by a previous build, remove them when publish is now disabled.
                ec.clear();
                if (!fs::exists(dstPath, ec))
                    continue;
                if (ec)
                    return reportError(DiagnosticId::cmd_err_native_publish_dependency_failed, Diagnostic::ARG_PATH, Utf8(dstPath), Diagnostic::ARG_BECAUSE, FileSystem::normalizeSystemMessage(ec));

                ec.clear();
                fs::remove(dstPath, ec);
                if (ec)
                    return reportError(DiagnosticId::cmd_err_native_publish_dependency_failed, Diagnostic::ARG_PATH, Utf8(dstPath), Diagnostic::ARG_BECAUSE, FileSystem::normalizeSystemMessage(ec));

                continue;
            }

            if (!shouldCopyPublishDependencyFile(it->path(), dstPath))
                continue;

            fs::copy_file(it->path(), dstPath, fs::copy_options::overwrite_existing, ec);
            if (ec)
                return reportError(DiagnosticId::cmd_err_native_publish_dependency_failed, Diagnostic::ARG_PATH, Utf8(dstPath), Diagnostic::ARG_BECAUSE, FileSystem::normalizeSystemMessage(ec));

            ec.clear();
            const auto srcTime = fs::last_write_time(it->path(), ec);
            if (!ec)
            {
                ec.clear();
                fs::last_write_time(dstPath, srcTime, ec);
                if (ec)
                    return reportError(DiagnosticId::cmd_err_native_publish_dependency_failed, Diagnostic::ARG_PATH, Utf8(dstPath), Diagnostic::ARG_BECAUSE, FileSystem::normalizeSystemMessage(ec));
            }
        }
    }

    return Result::Continue;
}

Result NativeBackendBuilder::reportError(DiagnosticId id)
{
    return reportError(Diagnostic::get(id));
}

Result NativeBackendBuilder::reportError(const Diagnostic& diag)
{
    lastErrorId_ = diag.elements().empty() ? DiagnosticId::None : diag.elements().front()->id();
    diag.report(ctx_);
    return Result::Error;
}

Result NativeBackendBuilder::validateTarget()
{
    const CommandLine& commandLine = ctx_.cmdLine();
    if (commandLine.targetOs != Runtime::TargetOs::Windows)
    {
        return reportError(DiagnosticId::cmd_err_native_target_os_not_supported);
    }

    if (commandLine.targetArch != Runtime::TargetArch::X86_64)
    {
        return reportError(DiagnosticId::cmd_err_native_target_arch_not_supported);
    }

    SWC_ASSERT(compiler_ != nullptr);
    const Runtime::BuildCfg& buildCfg = compiler_->buildCfg();
    if (!Runtime::backendKindProducesNativeArtifact(buildCfg.backendKind))
    {
        return reportError(DiagnosticId::cmd_err_native_backend_kind_required);
    }

    if (buildCfg.backendKind == Runtime::BuildCfgBackendKind::Executable &&
        buildCfg.backendSubKind != Runtime::BuildCfgBackendSubKind::Default &&
        buildCfg.backendSubKind != Runtime::BuildCfgBackendSubKind::Console)
    {
        return reportError(DiagnosticId::cmd_err_native_executable_subsystem_not_supported);
    }

    return Result::Continue;
}

Result NativeBackendBuilder::buildObjects()
{
    objBuildFailed.store(false, std::memory_order_release);

    const NativeArtifactBuilder artifactBuilder(*this);
    SWC_RESULT(artifactBuilder.prepareOutputFolders());

    // The integrated PE linker builds executable/DLL images directly from functionInfos, so it only
    // needs COFF object bytes when producing a static library archive.
    if (compiler_->buildCfg().backendKind != Runtime::BuildCfgBackendKind::StaticLibrary)
        return Result::Continue;

    JobManager& jobMgr = ctx_.global().jobMgr();
    for (uint32_t i = 0; i < objectDescriptions.size(); ++i)
    {
        auto* job = heapNew<NativeObjJob>(ctx_, *this, i);
        jobMgr.enqueue(*job, JobPriority::Normal, compiler_->jobClientId());
    }

    jobMgr.waitAll(compiler_->jobClientId());
    return objBuildFailed.load(std::memory_order_acquire) ? Result::Error : Result::Continue;
}

Result NativeBackendBuilder::runGeneratedArtifact()
{
    ScopedTimedLog stage(ctx_, ScopedTimedLog::Stage::Run);

    uint32_t              exitCode = 0;
    std::string           artifactOutput;
    std::vector<fs::path> runtimePathDirs;
    const fs::path        artifactDir = artifactPath.parent_path();
    for (const fs::path& importedLinkDir : compiler_->importedDependencyLinkDirs())
    {
        if (!importedLinkDir.empty())
            runtimePathDirs.push_back(importedLinkDir);
    }

    const Os::ProcessRunOptions options{
        .capturedOutput            = &artifactOutput,
        .logCtx                    = &ctx_,
        .additionalPathDirectories = runtimePathDirs,
    };

    const std::vector<Utf8> runArgs = effectiveGeneratedArtifactRunArgs(compiler_->cmdLine());
    const auto              result  = Os::runProcess(exitCode, artifactPath, runArgs, artifactDir.empty() ? buildDir : artifactDir, &options);
    switch (result)
    {
        case Os::ProcessRunResult::Ok:
            break;
        case Os::ProcessRunResult::StartFailed:
            return reportError(DiagnosticId::cmd_err_native_artifact_start_failed, Diagnostic::ARG_PATH, Utf8(artifactPath), Diagnostic::ARG_BECAUSE, Os::systemError());
        case Os::ProcessRunResult::WaitFailed:
            return reportError(DiagnosticId::cmd_err_native_artifact_wait_failed, Diagnostic::ARG_PATH, Utf8(artifactPath));
        case Os::ProcessRunResult::ExitCodeFailed:
            return reportError(DiagnosticId::cmd_err_native_artifact_exit_code_failed, Diagnostic::ARG_PATH, Utf8(artifactPath), Diagnostic::ARG_BECAUSE, Os::systemError());
    }

    if (exitCode != 0)
        return reportError(DiagnosticId::cmd_err_native_artifact_failed, Diagnostic::ARG_VALUE, Os::formatProcessExitCode(exitCode));

    return Result::Continue;
}

SWC_END_NAMESPACE();
