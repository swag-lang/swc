#include "pch.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/Native/NativeRDataCollector.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#if SWC_HAS_NATIVE_VALIDATION
#include "Backend/Native/NativeValidate.h"
#endif

SWC_BEGIN_NAMESPACE();

namespace
{
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
        const fs::path  absolutePath = fs::absolute(path, ec);
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
    builder_(&builder)
{
}

Result NativeArtifactBuilder::build() const
{
#if SWC_HAS_NATIVE_VALIDATION
    const NativeValidate nativeValidate(*builder_);
    nativeValidate.validate();
#endif
    SWC_RESULT(buildStartup());
    SWC_RESULT(prepareDataSections());
    return partitionObjects();
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
        fs::path sourceRoot = inputRootPath(builder_->ctx().cmdLine());
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

Result NativeArtifactBuilder::clearOutputFolders(const NativeArtifactPaths& paths) const
{
    SWC_RESULT(FileSystem::clearDirectoryContents(builder_->ctx(), paths.workDir, DiagnosticId::cmd_err_native_output_dir_clear_failed));
    if (!FileSystem::pathEquals(paths.outDir, paths.workDir))
        SWC_RESULT(FileSystem::clearDirectoryContents(builder_->ctx(), paths.outDir, DiagnosticId::cmd_err_native_output_dir_clear_failed));
    return Result::Continue;
}

Utf8 NativeArtifactBuilder::artifactName() const
{
    const auto buildCfgName = Utf8(builder_->compiler().buildCfg().name);
    if (!buildCfgName.empty())
        return FileSystem::sanitizeFileName(buildCfgName);

    const auto& cmdLine     = builder_->ctx().cmdLine();
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
    switch (builder_->ctx().cmdLine().targetOs)
    {
        case Runtime::TargetOs::Windows:
            switch (builder_->compiler().buildCfg().backendKind)
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
    switch (builder_->ctx().cmdLine().targetOs)
    {
        case Runtime::TargetOs::Windows:
            return ".obj";
    }

    SWC_UNREACHABLE();
}

fs::path NativeArtifactBuilder::configuredOutDir(const fs::path& defaultOutDir) const
{
    const auto buildCfgOutDir = Utf8(builder_->compiler().buildCfg().outDir);
    if (!buildCfgOutDir.empty())
        return {buildCfgOutDir.c_str()};
    return defaultOutDir;
}

Result NativeArtifactBuilder::createOutDir(const fs::path& outDir) const
{
    std::error_code ec;
    fs::create_directories(outDir, ec);
    if (ec)
        return builder_->reportError(DiagnosticId::cmd_err_native_work_dir_create_failed, Diagnostic::ARG_PATH, Utf8(outDir), Diagnostic::ARG_BECAUSE, ec.message());
    return Result::Continue;
}

fs::path NativeArtifactBuilder::configuredWorkDir() const
{
    const auto buildCfgWorkDir = Utf8(builder_->compiler().buildCfg().workDir);
    if (!buildCfgWorkDir.empty())
        return {buildCfgWorkDir.c_str()};
    return {};
}

Utf8 NativeArtifactBuilder::automaticWorkDirName(const Utf8& name) const
{
    const CommandLine& cmdLine     = builder_->ctx().cmdLine();
    const auto&        directories = inputDirectories(cmdLine);
    const auto&        files       = inputFiles(cmdLine);
    const auto&        modulePath  = inputModulePath(cmdLine);
    Utf8               key;

    key += std::format("cmd={};os={};arch={};backend={};sub={};name={};", static_cast<int>(cmdLine.command), static_cast<int>(cmdLine.targetOs), static_cast<int>(cmdLine.targetArch), static_cast<int>(builder_->compiler().buildCfg().backendKind), static_cast<int>(builder_->compiler().buildCfg().backendSubKind), name);

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
    // and incremental native builds operate in the same location.
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
        return builder_->reportError(DiagnosticId::cmd_err_native_work_dir_create_failed, Diagnostic::ARG_PATH, Utf8(buildDir), Diagnostic::ARG_BECAUSE, ec.message());
    return Result::Continue;
}

Result NativeArtifactBuilder::prepareDataSections() const
{
    builder_->mergedRData.name            = ".rdata";
    builder_->mergedRData.characteristics = IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_ALIGN_16BYTES;
    builder_->mergedData.name             = ".data";
    builder_->mergedData.characteristics  = IMAGE_SCN_CNT_INITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_MEM_WRITE | IMAGE_SCN_ALIGN_16BYTES;
    builder_->mergedBss.name              = ".bss";
    builder_->mergedBss.characteristics   = IMAGE_SCN_CNT_UNINITIALIZED_DATA | IMAGE_SCN_MEM_READ | IMAGE_SCN_MEM_WRITE | IMAGE_SCN_ALIGN_16BYTES;

    CompilerInstance& compiler = builder_->compiler();

    builder_->mergedRData.bytes.clear();
    builder_->mergedRData.relocations.clear();
    builder_->mergedData.bytes.clear();
    builder_->mergedData.relocations.clear();
    builder_->mergedBss.bssSize = compiler.globalZeroSegment().extentSize();
    builder_->mergedBss.bss     = builder_->mergedBss.bssSize != 0;
    for (auto& mappings : builder_->rdataAllocationMap)
        mappings.clear();

    // Emitted machine code is the source of truth for native constant roots.
    // Global initializers are already materialized into .data/.bss and do not need shard-wide .rdata copies.
    NativeRDataCollector collector(*builder_);
    SWC_RESULT(collector.collectAndEmit());

    const uint32_t dataSize = compiler.globalInitSegment().extentSize();
    if (dataSize)
    {
        builder_->mergedData.bytes.resize(dataSize);
        compiler.globalInitSegment().copyToPreserveOffsets(ByteSpanRW{builder_->mergedData.bytes.data(), dataSize});

        for (const auto& relocation : compiler.globalInitSegment().relocations())
        {
            NativeSectionRelocation record;
            record.offset     = relocation.offset;
            record.symbolName = K_DATA_BASE_SYMBOL;
            record.addend     = relocation.targetOffset;
            builder_->mergedData.relocations.push_back(record);
        }

        for (const SymbolVariable* symbol : builder_->regularGlobals)
        {
            if (!symbol)
                continue;
            if (!symbol->hasGlobalStorage())
                continue;
            if (symbol->globalStorageKind() != DataSegmentKind::GlobalInit)
                continue;

            const SymbolFunction* const targetFunction = symbol->globalFunctionInit();
            if (!targetFunction)
                continue;

            const uint64_t storageSize = builder_->ctx().typeMgr().get(symbol->typeRef()).sizeOf(builder_->ctx());
            SWC_ASSERT(storageSize == sizeof(uint64_t));

            NativeSectionRelocation record;
            record.offset = symbol->offset();
            if (targetFunction->isForeign())
            {
                record.symbolName = targetFunction->resolveForeignFunctionName(builder_->ctx());
            }
            else if (const auto it = builder_->functionBySymbol.find(const_cast<SymbolFunction*>(targetFunction)); it != builder_->functionBySymbol.end())
            {
                record.symbolName = it->second->symbolName;
            }
            else
            {
                return builder_->reportError(DiagnosticId::cmd_err_native_invalid_local_function_relocation);
            }

            record.addend = 0;
            builder_->mergedData.relocations.push_back(record);
        }
    }

    return Result::Continue;
}

Result NativeArtifactBuilder::partitionObjects() const
{
    builder_->objectDescriptions.clear();

    const size_t functionCount = builder_->functionInfos.size();
    uint32_t     maxJobs       = builder_->ctx().cmdLine().numCores;
    if (!maxJobs)
        maxJobs = std::max<uint32_t>(1, builder_->ctx().global().jobMgr().numWorkers());
    if (!maxJobs)
        maxJobs = 1;

    const uint32_t numJobs = std::max<uint32_t>(1, static_cast<uint32_t>(functionCount ? std::min<size_t>(functionCount, maxJobs) : 1));
    builder_->objectDescriptions.resize(numJobs);

    NativeArtifactPaths paths;
    queryPaths(paths, numJobs);
    if (builder_->ctx().cmdLine().clear && builder_->compiler().markNativeOutputsCleared())
        SWC_RESULT(clearOutputFolders(paths));
    SWC_RESULT(createBuildDir(paths.buildDir));
    SWC_RESULT(createOutDir(paths.outDir));
    builder_->buildDir     = paths.buildDir;
    builder_->artifactPath = paths.artifactPath;
    builder_->pdbPath      = paths.pdbPath;

    // Object 0 owns shared sections/startup, so the remaining objects only need code.
    for (uint32_t i = 0; i < numJobs; ++i)
    {
        builder_->objectDescriptions[i].index       = i;
        builder_->objectDescriptions[i].includeData = i == 0;
        builder_->objectDescriptions[i].objPath     = paths.objectPaths[i];
    }

    if (builder_->startup)
        builder_->objectDescriptions[0].startup = builder_->startup.get();

    for (size_t i = 0; i < builder_->functionInfos.size(); ++i)
    {
        NativeFunctionInfo& info     = builder_->functionInfos[i];
        const uint32_t      objIndex = static_cast<uint32_t>(i % numJobs);
        info.jobIndex                = objIndex;
        builder_->objectDescriptions[objIndex].functions.push_back(&info);
    }
    return Result::Continue;
}

Result NativeArtifactBuilder::buildStartup() const
{
    builder_->startup.reset();

    if (builder_->compiler().buildCfg().backendKind != Runtime::BuildCfgBackendKind::Executable)
        return Result::Continue;
    // Source-driven native tests can legitimately build an executable with
    // #test entries and no user-defined #main.
    if (builder_->mainFunctions.empty() && builder_->testFunctions.empty())
        return builder_->reportError(DiagnosticId::cmd_err_native_main_missing);

    auto         startup = std::make_unique<NativeStartupInfo>();
    MicroBuilder builder(builder_->ctx());
    builder.setBackendBuildCfg(builder_->compiler().buildCfg().backend);

    // The startup thunk runs compiler-generated lifecycle hooks and then hands off
    // process termination to the runtime wrapper for the active target.
    for (SymbolFunction* symbol : builder_->initFunctions)
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
    for (SymbolFunction* symbol : builder_->preMainFunctions)
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
    for (SymbolFunction* symbol : builder_->testFunctions)
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
    for (SymbolFunction* symbol : builder_->mainFunctions)
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
    for (SymbolFunction* symbol : builder_->dropFunctions)
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});

    const IdentifierRef exitIdRef = builder_->ctx().idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::Exit);
    SymbolFunction*     exitFn    = builder_->compiler().runtimeFunctionSymbol(exitIdRef);
    SWC_ASSERT(exitFn != nullptr);

    // Startup calls the runtime wrapper instead of a raw OS entry point, so the
    // emitted startup sequence stays stable across target-specific runtimes.
    const ABICall::PreparedCall preparedExit = ABICall::prepareArgs(builder, exitFn->callConvKind(), {});
    ABICall::callLocal(builder, exitFn->callConvKind(), exitFn, preparedExit);
    builder.emitRet();

    if (startup->code.emit(builder_->ctx(), builder) != Result::Continue)
        return builder_->reportError(DiagnosticId::cmd_err_native_test_entry_lower_failed);

    builder_->startup = std::move(startup);
    return Result::Continue;
}

SWC_END_NAMESPACE();
