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
}

NativeArtifactBuilder::NativeArtifactBuilder(NativeBackendBuilder& builder) :
    builder_(builder)
{
}

void NativeArtifactBuilder::queryPaths(NativeArtifactPaths& outPaths, const std::optional<uint32_t> workDirIndex, const uint32_t numObjects) const
{
    outPaths.workDir.clear();
    outPaths.buildDir.clear();
    outPaths.objectPaths.clear();
    outPaths.name = artifactName();

    // Reuse a stable work directory when possible, so repeated native builds converge
    // to the same artifact/output layout unless the caller asks for a unique build slot.
    outPaths.workDir = configuredWorkDir();
    if (outPaths.workDir.empty())
        outPaths.workDir = Os::getTemporaryPath() / "swc_native" / automaticWorkDirName(outPaths.name).c_str();

    outPaths.artifactExtension = artifactExtension();
    outPaths.outDir            = configuredOutDir(outPaths.workDir);
    outPaths.artifactPath      = outPaths.outDir / std::format("{}{}", outPaths.name, outPaths.artifactExtension);
    outPaths.pdbPath           = outPaths.outDir / std::format("{}{}.pdb", outPaths.name, outPaths.artifactExtension);

    if (!workDirIndex.has_value())
        return;

    outPaths.buildDir = buildDir(outPaths.workDir, workDirIndex.value());
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
    SWC_RESULT(prepareDataSections());
    SWC_RESULT(buildStartup());
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
    builder_.rdataShardBaseOffsets.fill(0);

    // Constant shards are concatenated into one synthetic .rdata section while preserving
    // per-shard offsets so relocations can still target the original logical base.
    for (uint32_t shardIndex = 0; shardIndex < ConstantManager::SHARD_COUNT; ++shardIndex)
    {
        const DataSegment& segment     = compiler.cstMgr().shardDataSegment(shardIndex);
        const uint32_t     segmentSize = segment.extentSize();
        if (!segmentSize)
            continue;

        const uint32_t baseOffset = Math::alignUpU32(static_cast<uint32_t>(builder_.mergedRData.bytes.size()), 16);
        if (builder_.mergedRData.bytes.size() < baseOffset)
            builder_.mergedRData.bytes.resize(baseOffset, std::byte{0});
        builder_.rdataShardBaseOffsets[shardIndex] = baseOffset;

        const uint32_t insertOffset = static_cast<uint32_t>(builder_.mergedRData.bytes.size());
        builder_.mergedRData.bytes.resize(insertOffset + segmentSize);
        segment.copyToPreserveOffsets(ByteSpanRW{builder_.mergedRData.bytes.data() + insertOffset, segmentSize});

        for (const auto& relocation : segment.relocations())
        {
            NativeSectionRelocation record;
            record.offset     = baseOffset + relocation.offset;
            record.symbolName = K_R_DATA_BASE_SYMBOL;
            record.addend     = baseOffset + relocation.targetOffset;
            builder_.mergedRData.relocations.push_back(record);
        }
    }

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
    if (builder_.compiler().nativeMainFunctions().empty())
        return builder_.reportError(DiagnosticId::cmd_err_native_main_missing);

    auto         startup = std::make_unique<NativeStartupInfo>();
    MicroBuilder builder(builder_.ctx());
    builder.setBackendBuildCfg(builder_.compiler().buildCfg().backend);

    // The startup thunk runs compiler-generated lifecycle hooks and then exits with the
    // program return value already carried in the host integer return register.
    for (SymbolFunction* symbol : builder_.compiler().nativeInitFunctions())
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
    for (SymbolFunction* symbol : builder_.compiler().nativePreMainFunctions())
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
    for (SymbolFunction* symbol : builder_.compiler().nativeTestFunctions())
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
    for (SymbolFunction* symbol : builder_.compiler().nativeMainFunctions())
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
    for (SymbolFunction* symbol : builder_.compiler().nativeDropFunctions())
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

    const uint32_t      workDirIndex = builder_.compiler().atomicId().fetch_add(1, std::memory_order_relaxed);
    NativeArtifactPaths paths;
    queryPaths(paths, workDirIndex, numJobs);
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

fs::path NativeArtifactBuilder::buildDir(const fs::path& workDir, const uint32_t buildIndex)
{
    return workDir / std::format("{:08x}", buildIndex);
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
