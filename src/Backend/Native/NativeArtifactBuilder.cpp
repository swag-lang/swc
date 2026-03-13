#include "pch.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/Native/NativeValidate.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct PendingRDataAllocation
    {
        uint32_t shardIndex   = 0;
        uint32_t sourceOffset = 0;
        Utf8     ownerName;
    };

    class NativeRDataCollector
    {
    public:
        explicit NativeRDataCollector(NativeBackendBuilder& builder) :
            builder_(builder)
        {
        }

        Result collectAndEmit()
        {
            SWC_RESULT(collectRoots());
            return emitReachableAllocations();
        }

    private:
        Result collectRoots()
        {
            if (builder_.startup)
                SWC_RESULT(collectCodeRoots(builder_.startup->debugName, builder_.startup->code.codeRelocations));

            for (const NativeFunctionInfo& info : builder_.functionInfos)
            {
                if (!info.machineCode)
                    continue;

                const Utf8 ownerName = info.symbol ? info.symbol->getFullScopedName(builder_.ctx()) : info.debugName;
                SWC_RESULT(collectCodeRoots(ownerName, info.machineCode->codeRelocations));
            }

            while (!pending_.empty())
            {
                PendingRDataAllocation pending = std::move(pending_.back());
                pending_.pop_back();

                const DataSegment& segment = builder_.compiler().cstMgr().shardDataSegment(pending.shardIndex);
                DataSegmentAllocation allocation;
                if (!segment.findAllocation(allocation, pending.sourceOffset) || allocation.offset != pending.sourceOffset)
                    return builder_.reportError(DiagnosticId::cmd_err_native_constant_payload_unsupported, Diagnostic::ARG_SYM, pending.ownerName);

                for (const DataSegmentRelocation& relocation : segment.relocations())
                {
                    if (relocation.offset < allocation.offset)
                        continue;
                    if (relocation.offset - allocation.offset >= allocation.size)
                        continue;

                    SWC_RESULT(enqueueSourceOffset(pending.ownerName, pending.shardIndex, relocation.targetOffset));
                }
            }

            return Result::Continue;
        }

        Result collectCodeRoots(const Utf8& ownerName, const std::span<const MicroRelocation> relocations)
        {
            for (const MicroRelocation& relocation : relocations)
            {
                if (relocation.kind != MicroRelocation::Kind::ConstantAddress)
                    continue;

                SWC_RESULT(enqueuePointer(ownerName, reinterpret_cast<const void*>(relocation.targetAddress)));
            }

            return Result::Continue;
        }

        Result enqueuePointer(const Utf8& ownerName, const void* ptr)
        {
            if (!ptr)
                return Result::Continue;

            uint32_t  shardIndex = 0;
            const Ref sourceRef  = builder_.compiler().cstMgr().findDataSegmentRef(shardIndex, ptr);
            if (sourceRef == INVALID_REF)
                return builder_.reportError(DiagnosticId::cmd_err_native_constant_storage_unsupported, Diagnostic::ARG_SYM, ownerName);

            return enqueueSourceOffset(ownerName, shardIndex, sourceRef);
        }

        Result enqueueSourceOffset(const Utf8& ownerName, const uint32_t shardIndex, const uint32_t sourceOffset)
        {
            const DataSegment& segment = builder_.compiler().cstMgr().shardDataSegment(shardIndex);
            DataSegmentAllocation allocation;
            if (!segment.findAllocation(allocation, sourceOffset))
                return builder_.reportError(DiagnosticId::cmd_err_native_constant_payload_unsupported, Diagnostic::ARG_SYM, ownerName);

            if (!seen_[shardIndex].insert(allocation.offset).second)
                return Result::Continue;

            reachableOffsets_[shardIndex].push_back(allocation.offset);
            owners_[shardIndex].emplace(allocation.offset, ownerName);
            pending_.push_back({
                .shardIndex   = shardIndex,
                .sourceOffset = allocation.offset,
                .ownerName    = ownerName,
            });
            return Result::Continue;
        }

        Result emitReachableAllocations()
        {
            std::array<std::vector<DataSegmentAllocation>, ConstantManager::SHARD_COUNT> emittedAllocations;

            for (uint32_t shardIndex = 0; shardIndex < ConstantManager::SHARD_COUNT; ++shardIndex)
            {
                auto& reachable = reachableOffsets_[shardIndex];
                std::ranges::sort(reachable);

                const DataSegment& segment = builder_.compiler().cstMgr().shardDataSegment(shardIndex);
                auto&              mappings = builder_.rdataAllocationMap[shardIndex];
                mappings.clear();
                emittedAllocations[shardIndex].reserve(reachable.size());
                mappings.reserve(reachable.size());

                for (const uint32_t sourceOffset : reachable)
                {
                    DataSegmentAllocation allocation;
                    if (!segment.findAllocation(allocation, sourceOffset) || allocation.offset != sourceOffset)
                    {
                        const auto ownerIt = owners_[shardIndex].find(sourceOffset);
                        const Utf8 ownerName = ownerIt != owners_[shardIndex].end() ? ownerIt->second : Utf8("<rdata>");
                        return builder_.reportError(DiagnosticId::cmd_err_native_constant_payload_unsupported, Diagnostic::ARG_SYM, ownerName);
                    }

                    const uint32_t emittedOffset = Math::alignUpU32(static_cast<uint32_t>(builder_.mergedRData.bytes.size()), std::max(allocation.align, 1u));
                    if (builder_.mergedRData.bytes.size() < emittedOffset)
                        builder_.mergedRData.bytes.resize(emittedOffset, std::byte{0});

                    const uint32_t insertOffset = static_cast<uint32_t>(builder_.mergedRData.bytes.size());
                    SWC_ASSERT(insertOffset == emittedOffset);
                    builder_.mergedRData.bytes.resize(insertOffset + allocation.size);

                    const auto* sourceBytes = segment.ptr<std::byte>(allocation.offset);
                    SWC_ASSERT(sourceBytes != nullptr);
                    std::memcpy(builder_.mergedRData.bytes.data() + insertOffset, sourceBytes, allocation.size);

                    emittedAllocations[shardIndex].push_back(allocation);
                    mappings.push_back({
                        .sourceOffset  = allocation.offset,
                        .size          = allocation.size,
                        .emittedOffset = emittedOffset,
                    });
                }
            }

            for (uint32_t shardIndex = 0; shardIndex < ConstantManager::SHARD_COUNT; ++shardIndex)
            {
                const DataSegment&   segment          = builder_.compiler().cstMgr().shardDataSegment(shardIndex);
                const auto&          allocations      = emittedAllocations[shardIndex];
                const auto&          relocations      = segment.relocations();
                const auto&          allocationOwners = owners_[shardIndex];

                for (size_t i = 0; i < allocations.size(); ++i)
                {
                    const DataSegmentAllocation&        allocation = allocations[i];
                    const NativeRDataAllocationMapEntry mapping    = builder_.rdataAllocationMap[shardIndex][i];

                    for (const DataSegmentRelocation& relocation : relocations)
                    {
                        if (relocation.offset < allocation.offset)
                            continue;
                        if (relocation.offset - allocation.offset >= allocation.size)
                            continue;

                        uint32_t targetOffset = 0;
                        if (!builder_.tryMapRDataSourceOffset(targetOffset, shardIndex, relocation.targetOffset))
                        {
                            const auto ownerIt = allocationOwners.find(allocation.offset);
                            const Utf8 ownerName = ownerIt != allocationOwners.end() ? ownerIt->second : Utf8("<rdata>");
                            return builder_.reportError(DiagnosticId::cmd_err_native_constant_payload_unsupported, Diagnostic::ARG_SYM, ownerName);
                        }

                        NativeSectionRelocation record;
                        record.offset     = mapping.emittedOffset + (relocation.offset - allocation.offset);
                        record.symbolName = K_R_DATA_BASE_SYMBOL;
                        record.addend     = targetOffset;
                        builder_.mergedRData.relocations.push_back(record);
                    }
                }
            }

            return Result::Continue;
        }

        NativeBackendBuilder&                                                            builder_;
        std::array<std::vector<uint32_t>, ConstantManager::SHARD_COUNT>                  reachableOffsets_;
        std::array<std::unordered_set<uint32_t>, ConstantManager::SHARD_COUNT>           seen_;
        std::array<std::unordered_map<uint32_t, Utf8>, ConstantManager::SHARD_COUNT>     owners_;
        std::vector<PendingRDataAllocation>                                              pending_;
    };

    Utf8 objectFileName(const Utf8& name, const Utf8& extension, const uint32_t objectIndex)
    {
        return std::format("{}_{:02}{}", name, objectIndex, extension);
    }

    const std::set<fs::path>& inputDirectories(const CommandLine& cmdLine)
    {
        if (!cmdLine.originalDirectories.empty())
            return cmdLine.originalDirectories;
        return cmdLine.directories;
    }

    const std::set<fs::path>& inputFiles(const CommandLine& cmdLine)
    {
        if (!cmdLine.originalFiles.empty())
            return cmdLine.originalFiles;
        return cmdLine.files;
    }

    const fs::path& inputModulePath(const CommandLine& cmdLine)
    {
        if (!cmdLine.originalModulePath.empty())
            return cmdLine.originalModulePath;
        return cmdLine.modulePath;
    }

    fs::path absolutePathNoThrow(const fs::path& path)
    {
        if (path.empty())
            return {};

        std::error_code ec;
        fs::path        absolutePath = fs::absolute(path, ec);
        if (ec)
            return path.lexically_normal();
        return absolutePath.lexically_normal();
    }

    void appendInputRoots(std::vector<fs::path>& outRoots, const std::set<fs::path>& inputs, const bool useParentDirectory)
    {
        for (const fs::path& input : inputs)
        {
            fs::path root = useParentDirectory ? input.parent_path() : input;
            if (root.empty())
                root = input;

            root = absolutePathNoThrow(root);
            if (!root.empty())
                outRoots.push_back(root);
        }
    }

    fs::path commonPathPrefix(const fs::path& lhs, const fs::path& rhs)
    {
        fs::path result;
        auto     lhsIt = lhs.begin();
        auto     rhsIt = rhs.begin();
        while (lhsIt != lhs.end() && rhsIt != rhs.end() && *lhsIt == *rhsIt)
        {
            result /= *lhsIt;
            ++lhsIt;
            ++rhsIt;
        }

        return result;
    }

    fs::path inputRootPath(const CommandLine& cmdLine)
    {
        std::vector<fs::path> roots;
        const auto&           modulePath = inputModulePath(cmdLine);
        if (!modulePath.empty())
            roots.push_back(absolutePathNoThrow(modulePath.parent_path()));

        appendInputRoots(roots, inputFiles(cmdLine), true);
        appendInputRoots(roots, inputDirectories(cmdLine), false);

        if (roots.empty())
            return {};

        fs::path root = roots.front();
        for (size_t i = 1; i < roots.size(); ++i)
        {
            root = commonPathPrefix(root, roots[i]);
            if (root.empty())
                return roots.front();
        }

        if (!root.empty() && root != root.root_path())
            return root;
        return roots.front();
    }

    fs::path currentPathNoThrow()
    {
        std::error_code ec;
        const fs::path  currentDir = fs::current_path(ec);
        if (ec)
            return {};
        return currentDir.lexically_normal();
    }
}

NativeArtifactBuilder::NativeArtifactBuilder(NativeBackendBuilder& builder) :
    builder_(builder)
{
}

void NativeArtifactBuilder::queryPaths(NativeArtifactPaths& outPaths, const uint32_t numObjects) const
{
    outPaths.workDir.clear();
    outPaths.buildDir.clear();
    outPaths.objectPaths.clear();
    outPaths.name = artifactName();

    outPaths.workDir = configuredWorkDir();
    if (outPaths.workDir.empty())
    {
        fs::path sourceRoot = inputRootPath(builder_.ctx().cmdLine());
        if (sourceRoot.empty())
            sourceRoot = currentPathNoThrow();
        outPaths.workDir = sourceRoot / ".output" / automaticWorkDirName(outPaths.name).c_str();
    }

    outPaths.buildDir          = buildDir(outPaths.workDir);
    outPaths.artifactExtension = artifactExtension();
    outPaths.outDir            = configuredOutDir(outPaths.workDir);
    outPaths.artifactPath      = outPaths.outDir / std::format("{}{}", outPaths.name, outPaths.artifactExtension);
    outPaths.pdbPath           = outPaths.outDir / std::format("{}.pdb", outPaths.name);

    if (!numObjects)
        return;

    outPaths.objectPaths.clear();
    outPaths.objectPaths.reserve(numObjects);
    const Utf8 objectExt = objectExtension();
    for (uint32_t i = 0; i < numObjects; ++i)
        outPaths.objectPaths.push_back(outPaths.buildDir / objectFileName(outPaths.name, objectExt, i).c_str());
}

Result NativeArtifactBuilder::build() const
{
#if SWC_HAS_NATIVE_VALIDATION
    const NativeValidate nativeValidate(builder_);
    nativeValidate.validate();
#endif
    SWC_RESULT(buildStartup());
    SWC_RESULT(prepareDataSections());
    return partitionObjects();
}

Result NativeArtifactBuilder::prepareDataSections() const
{
    builder_.mergedRData.name            = ".rdata";
    builder_.mergedRData.characteristics = IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_ALIGN_16BYTES;
    builder_.mergedData.name             = ".data";
    builder_.mergedData.characteristics  = IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_MEM_WRITE | IMAGE_SCN_ALIGN_16BYTES;
    builder_.mergedBss.name              = ".bss";
    builder_.mergedBss.characteristics   = IMAGE_SCN_CNT_UNINITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_MEM_WRITE | IMAGE_SCN_ALIGN_16BYTES;

    CompilerInstance& compiler = builder_.compiler();

    builder_.mergedRData.bytes.clear();
    builder_.mergedRData.relocations.clear();
    builder_.mergedData.bytes.clear();
    builder_.mergedData.relocations.clear();
    builder_.mergedBss.bssSize = compiler.globalZeroSegment().extentSize();
    builder_.mergedBss.bss     = builder_.mergedBss.bssSize != 0;
    for (auto& mappings : builder_.rdataAllocationMap)
        mappings.clear();

    // Emitted machine code is the source of truth for native constant roots.
    // Global initializers are already materialized into .data/.bss and do not need shard-wide .rdata copies.
    NativeRDataCollector collector(builder_);
    SWC_RESULT(collector.collectAndEmit());

    const uint32_t dataSize = compiler.globalInitSegment().extentSize();
    if (dataSize)
    {
        builder_.mergedData.bytes.resize(dataSize);
        compiler.globalInitSegment().copyToPreserveOffsets(ByteSpanRW{builder_.mergedData.bytes.data(), dataSize});

        for (const auto& relocation : compiler.globalInitSegment().relocations())
        {
            NativeSectionRelocation record;
            record.offset     = relocation.offset;
            record.symbolName = K_DATA_BASE_SYMBOL;
            record.addend     = relocation.targetOffset;
            builder_.mergedData.relocations.push_back(record);
        }
    }

    return Result::Continue;
}

Result NativeArtifactBuilder::buildStartup() const
{
    builder_.startup.reset();

    if (builder_.compiler().buildCfg().backendKind != Runtime::BuildCfgBackendKind::Executable)
        return Result::Continue;
    if (builder_.mainFunctions.empty())
        return builder_.reportError(DiagnosticId::cmd_err_native_main_missing);

    auto         startup = std::make_unique<NativeStartupInfo>();
    MicroBuilder builder(builder_.ctx());
    builder.setBackendBuildCfg(builder_.compiler().buildCfg().backend);

    // The startup thunk runs compiler-generated lifecycle hooks and then exits with the
    // program return value already carried in the host integer return register.
    for (SymbolFunction* symbol : builder_.initFunctions)
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
    for (SymbolFunction* symbol : builder_.preMainFunctions)
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
    for (SymbolFunction* symbol : builder_.testFunctions)
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
    for (SymbolFunction* symbol : builder_.mainFunctions)
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
    for (SymbolFunction* symbol : builder_.dropFunctions)
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});

    auto* exitProcess = Symbol::make<SymbolFunction>(builder_.ctx(), nullptr, TokenRef::invalid(), builder_.compiler().idMgr().addIdentifier("ExitProcess"), SymbolFlagsE::Zero);
    exitProcess->attributes().setForeign("kernel32", "ExitProcess");
    exitProcess->setCallConvKind(CallConvKind::Host);
    exitProcess->setReturnTypeRef(builder_.compiler().typeMgr().typeVoid());

    SmallVector<ABICall::PreparedArg> exitArgs;
    exitArgs.push_back({
        .srcReg      = CallConv::host().intReturn,
        .kind        = ABICall::PreparedArgKind::Direct,
        .isFloat     = false,
        .isAddressed = false,
        .numBits     = 32,
    });

    builder.emitClearReg(CallConv::host().intReturn, MicroOpBits::B32);
    const ABICall::PreparedCall preparedExit = ABICall::prepareArgs(builder, CallConvKind::Host, exitArgs.span());
    ABICall::callExtern(builder, CallConvKind::Host, exitProcess, preparedExit);
    builder.emitRet();

    if (startup->code.emit(builder_.ctx(), builder) != Result::Continue)
        return builder_.reportError(DiagnosticId::cmd_err_native_test_entry_lower_failed);

    builder_.startup = std::move(startup);
    return Result::Continue;
}

Result NativeArtifactBuilder::partitionObjects() const
{
    builder_.objectDescriptions.clear();

    const size_t functionCount = builder_.functionInfos.size();
    uint32_t     maxJobs       = builder_.ctx().cmdLine().numCores;
    if (!maxJobs)
        maxJobs = std::max<uint32_t>(1, builder_.ctx().global().jobMgr().numWorkers());
    if (!maxJobs)
        maxJobs = 1;

    const uint32_t numJobs = std::max<uint32_t>(1, static_cast<uint32_t>(functionCount ? std::min<size_t>(functionCount, maxJobs) : 1));
    builder_.objectDescriptions.resize(numJobs);

    NativeArtifactPaths paths;
    queryPaths(paths, numJobs);
    if (builder_.ctx().cmdLine().clear && builder_.compiler().markNativeOutputsCleared())
        SWC_RESULT(clearOutputFolders(paths));
    SWC_RESULT(createBuildDir(paths.buildDir));
    SWC_RESULT(createOutDir(paths.outDir));
    builder_.buildDir     = paths.buildDir;
    builder_.artifactPath = paths.artifactPath;
    builder_.pdbPath      = paths.pdbPath;

    // Object 0 owns shared sections/startup, so the remaining objects only need code.
    for (uint32_t i = 0; i < numJobs; ++i)
    {
        builder_.objectDescriptions[i].index       = i;
        builder_.objectDescriptions[i].includeData = i == 0;
        builder_.objectDescriptions[i].objPath     = paths.objectPaths[i];
    }

    if (builder_.startup)
        builder_.objectDescriptions[0].startup = builder_.startup.get();

    for (size_t i = 0; i < builder_.functionInfos.size(); ++i)
    {
        NativeFunctionInfo& info     = builder_.functionInfos[i];
        const uint32_t      objIndex = static_cast<uint32_t>(i % numJobs);
        info.jobIndex                = objIndex;
        builder_.objectDescriptions[objIndex].functions.push_back(&info);
    }
    return Result::Continue;
}

Result NativeArtifactBuilder::clearOutputFolders(const NativeArtifactPaths& paths) const
{
    SWC_RESULT(FileSystem::clearDirectoryContents(builder_.ctx(), paths.workDir, DiagnosticId::cmd_err_native_output_dir_clear_failed));
    if (!FileSystem::pathEquals(paths.outDir, paths.workDir))
        SWC_RESULT(FileSystem::clearDirectoryContents(builder_.ctx(), paths.outDir, DiagnosticId::cmd_err_native_output_dir_clear_failed));
    return Result::Continue;
}

Utf8 NativeArtifactBuilder::artifactName() const
{
    const auto buildCfgName = Utf8(builder_.compiler().buildCfg().name);
    if (!buildCfgName.empty())
        return FileSystem::sanitizeFileName(buildCfgName);

    const auto& cmdLine     = builder_.ctx().cmdLine();
    const auto& directories = inputDirectories(cmdLine);
    const auto& files       = inputFiles(cmdLine);
    const auto& modulePath  = inputModulePath(cmdLine);

    if (!modulePath.empty())
        return FileSystem::sanitizeFileName(Utf8(modulePath.filename().string()));
    if (files.size() == 1)
        return FileSystem::sanitizeFileName(Utf8(files.begin()->stem().string()));
    if (directories.size() == 1)
        return FileSystem::sanitizeFileName(Utf8(directories.begin()->filename().string()));

    return "native";
}

Utf8 NativeArtifactBuilder::artifactExtension() const
{
    switch (builder_.ctx().cmdLine().targetOs)
    {
        case Runtime::TargetOs::Windows:
            switch (builder_.compiler().buildCfg().backendKind)
            {
                case Runtime::BuildCfgBackendKind::Executable:
                    return ".exe";
                case Runtime::BuildCfgBackendKind::Library:
                    return ".dll";
                case Runtime::BuildCfgBackendKind::Export:
                    return ".lib";
                case Runtime::BuildCfgBackendKind::None:
                    break;
            }

            break;
    }

    SWC_UNREACHABLE();
}

Utf8 NativeArtifactBuilder::objectExtension() const
{
    switch (builder_.ctx().cmdLine().targetOs)
    {
        case Runtime::TargetOs::Windows:
            return ".obj";
    }

    SWC_UNREACHABLE();
}

fs::path NativeArtifactBuilder::configuredOutDir(const fs::path& defaultOutDir) const
{
    const auto buildCfgOutDir = Utf8(builder_.compiler().buildCfg().outDir);
    if (!buildCfgOutDir.empty())
        return {buildCfgOutDir.c_str()};
    return defaultOutDir;
}

Result NativeArtifactBuilder::createOutDir(const fs::path& outDir) const
{
    std::error_code ec;
    fs::create_directories(outDir, ec);
    if (ec)
        return builder_.reportError(DiagnosticId::cmd_err_native_work_dir_create_failed, Diagnostic::ARG_PATH, Utf8(outDir), Diagnostic::ARG_BECAUSE, ec.message());
    return Result::Continue;
}

fs::path NativeArtifactBuilder::configuredWorkDir() const
{
    const auto buildCfgWorkDir = Utf8(builder_.compiler().buildCfg().workDir);
    if (!buildCfgWorkDir.empty())
        return {buildCfgWorkDir.c_str()};
    return {};
}

Utf8 NativeArtifactBuilder::automaticWorkDirName(const Utf8& name) const
{
    const CommandLine& cmdLine     = builder_.ctx().cmdLine();
    const auto&        directories = inputDirectories(cmdLine);
    const auto&        files       = inputFiles(cmdLine);
    const auto&        modulePath  = inputModulePath(cmdLine);
    Utf8               key;

    key += std::format("cmd={};os={};arch={};backend={};sub={};name={};", static_cast<int>(cmdLine.command), static_cast<int>(cmdLine.targetOs), static_cast<int>(cmdLine.targetArch), static_cast<int>(builder_.compiler().buildCfg().backendKind), static_cast<int>(builder_.compiler().buildCfg().backendSubKind), name);

    if (!modulePath.empty())
    {
        key += "module=";
        key += Utf8(modulePath);
        key += ";";
    }

    for (const fs::path& file : files)
    {
        key += "file=";
        key += Utf8(file);
        key += ";";
    }

    for (const fs::path& directory : directories)
    {
        key += "directory=";
        key += Utf8(directory);
        key += ";";
    }

    // Keep the auto-generated work dir deterministic for a given command line so cleanup
    // and incremental native builds operate on the same location.
    const uint32_t hash = static_cast<uint32_t>(std::hash<std::string_view>{}(key.view()));
    return std::format("{}_{:08x}", FileSystem::sanitizeFileName(name), hash);
}

fs::path NativeArtifactBuilder::buildDir(const fs::path& workDir)
{
    return workDir;
}

Result NativeArtifactBuilder::createBuildDir(const fs::path& buildDir) const
{
    std::error_code ec;
    fs::create_directories(buildDir, ec);
    if (ec)
        return builder_.reportError(DiagnosticId::cmd_err_native_work_dir_create_failed, Diagnostic::ARG_PATH, Utf8(buildDir), Diagnostic::ARG_BECAUSE, ec.message());
    return Result::Continue;
}

SWC_END_NAMESPACE();
