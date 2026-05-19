#include "pch.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/Native/NativeRDataCollector.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Helpers/SemaRuntime.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Support/Memory/Heap.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Thread/JobManager.h"
#if SWC_HAS_VALIDATE_NATIVE
#include "Backend/Native/NativeValidate.h"
#endif

SWC_BEGIN_NAMESPACE();

class NativeStartupBuildJob final : public Job
{
public:
    NativeStartupBuildJob(const TaskContext& ctx, const NativeArtifactBuilder& artifactBuilder) :
        Job(ctx, JobKind::NativeArtifact),
        artifactBuilder_(&artifactBuilder)
    {
    }

    JobResult exec() override
    {
        SWC_MEM_SCOPE("Backend/Native/Startup");
        ctx().state().setNone();
        SWC_ASSERT(artifactBuilder_ != nullptr);
        result_.store(artifactBuilder_->buildStartup(ctx()), std::memory_order_release);
        return JobResult::Done;
    }

    Result result() const noexcept
    {
        return result_.load(std::memory_order_acquire);
    }

private:
    const NativeArtifactBuilder* artifactBuilder_ = nullptr;
    std::atomic<Result>          result_          = Result::Continue;
};

namespace
{
    struct TestSourceLocation
    {
        Utf8     fileName = "<unknown>";
        uint32_t line     = 0;
    };

    Utf8 testSourceFileName(const SourceFile* sourceFile)
    {
        if (!sourceFile)
            return {};
        return sourceFile->path().filename().string();
    }

    bool assignTestSourceFileName(Utf8& outFileName, const SourceFile* sourceFile)
    {
        const Utf8 fileName = testSourceFileName(sourceFile);
        if (fileName.empty())
            return false;

        outFileName = fileName;
        return true;
    }

    bool hasUsableTestSourceFileName(const TestSourceLocation& location)
    {
        return !location.fileName.empty() && location.fileName != "<unknown>";
    }

    const SymbolFunction* primaryTestLocationSymbol(const SymbolFunction& symbol)
    {
        const SymbolFunction* location = SemaRuntime::transparentLocationFunction(&symbol);
        if (!location)
            return symbol.genericRootOrSelf();
        return location->genericRootOrSelf();
    }

    MicroReg nextVirtualIntReg(uint32_t& nextIndex)
    {
        return MicroReg::virtualIntReg(nextIndex++);
    }

    ConstantRef materializeRuntimeStringConstant(TaskContext& ctx, std::string_view value)
    {
        ConstantManager&  cstMgr          = ctx.cstMgr();
        const TypeRef     runtimeTypeRef  = ctx.typeMgr().typeString();
        const uint32_t    cacheShardIndex = ConstantManager::runtimeStringConstantCacheShard(runtimeTypeRef, value);
        const ConstantRef cached          = cstMgr.findRuntimeStringConstant(cacheShardIndex, runtimeTypeRef, value);
        if (cached.isValid())
            return cached;

        const std::string_view storedValue = cstMgr.addString(ctx, value);
        DataSegmentRef         targetRef;
        if (storedValue.data())
            cstMgr.resolveDataSegmentRef(targetRef, storedValue.data());

        SWC_ASSERT(storedValue.empty() || storedValue.data()[storedValue.size()] == '\0');
        SWC_ASSERT(storedValue.empty() || targetRef.isValid());
        if (!storedValue.empty() && targetRef.isInvalid())
            return ConstantRef::invalid();

        const uint32_t shardIndex    = targetRef.isInvalid() ? 0 : targetRef.shardIndex;
        DataSegment&   segment       = cstMgr.shardDataSegment(shardIndex);
        const auto [offset, storage] = segment.reserveBytes(sizeof(Runtime::String), alignof(Runtime::String), true);
        auto* runtimeString          = reinterpret_cast<Runtime::String*>(storage);
        runtimeString->ptr           = storedValue.data();
        runtimeString->length        = storedValue.size();

        if (targetRef.isValid())
            segment.addRelocation(offset + offsetof(Runtime::String, ptr), targetRef.offset);

        ConstantValue runtimeStringCst = ConstantValue::makeStructBorrowed(ctx, runtimeTypeRef, ByteSpan{storage, sizeof(Runtime::String)});
        runtimeStringCst.setDataSegmentRef({.shardIndex = shardIndex, .offset = offset});
        const ConstantRef cstRef = cstMgr.addUniqueMaterializedPayloadConstant(runtimeStringCst);
        return cstMgr.publishRuntimeStringConstant(cacheShardIndex, runtimeTypeRef, value, cstRef);
    }

    void loadConstantStoragePointerReg(MicroBuilder& builder, TaskContext& ctx, MicroReg reg, ConstantRef cstRef)
    {
        const ConstantValue& cst = ctx.cstMgr().get(cstRef);
        SWC_ASSERT(cst.isString() || cst.isStruct());

        if (cst.isString())
        {
            const std::string_view view = cst.getString();
            builder.emitLoadRegPtrReloc(reg, reinterpret_cast<uint64_t>(view.data()), cstRef);
            return;
        }

        const ByteSpan bytes = cst.getStruct();
        builder.emitLoadRegPtrReloc(reg, reinterpret_cast<uint64_t>(bytes.data()), cstRef);
    }

    TestSourceLocation resolveTestSourceLocation(TaskContext& ctx, const CompilerInstance& compiler, const SymbolFunction& symbol)
    {
        TestSourceLocation result;

        const AstNode*      decl    = symbol.decl();
        const SourceViewRef viewRef = decl ? decl->srcViewRef() : symbol.srcViewRef();
        if (!viewRef.isValid())
            return result;

        const SourceView& declView   = compiler.srcView(viewRef);
        const SourceFile* sourceFile = compiler.owningSourceFile(declView);
        const Ast*        sourceAst  = sourceFile && sourceFile->ast().hasSourceView() ? &sourceFile->ast() : nullptr;
        SourceCodeRange   codeRange;

        if (decl && sourceAst && sourceAst->hasSourceView() && sourceAst->tryFindNodeRef(decl).isValid())
        {
            codeRange = decl->codeRangeWithChildren(ctx, *sourceAst, declView);
        }
        else if (decl)
        {
            codeRange = decl->codeRange(ctx);
        }
        else
        {
            codeRange = symbol.codeRange(ctx);
        }

        const SourceFile* codeRangeFile = compiler.owningSourceFile(codeRange.srcView);
        if (!assignTestSourceFileName(result.fileName, codeRangeFile))
            assignTestSourceFileName(result.fileName, sourceFile);

        if (result.fileName == "<unknown>" && symbol.srcViewRef().isValid())
        {
            const SourceView& symbolView = compiler.srcView(symbol.srcViewRef());
            assignTestSourceFileName(result.fileName, compiler.owningSourceFile(symbolView));
        }

        result.line = codeRange.line;
        return result;
    }
}

NativeArtifactBuilder::NativeArtifactBuilder(NativeBackendBuilder& builder) :
    builder_(&builder)
{
}

Result NativeArtifactBuilder::build() const
{
#if SWC_HAS_VALIDATE_NATIVE
    if (builder_->ctx().cmdLine().validateNative)
    {
        const NativeValidate nativeValidate(*builder_);
        nativeValidate.validate();
    }
#endif
    SWC_RESULT(prepareTestProgressEntries(builder_->ctx()));
    if (builder_->ctx().global().jobMgr().numWorkers() == 0)
    {
        SWC_RESULT(buildStartup(builder_->ctx()));
        SWC_RESULT(prepareDataSections());
    }
    else
    {
        SWC_RESULT(buildStartupAndDataSectionsParallel());
    }

    return partitionObjects();
}

Result NativeArtifactBuilder::prepareTestProgressEntries(TaskContext& ctx) const
{
    builder_->testProgressEntries.clear();

    const uint32_t expectedTestCount = builder_->expectedTestFunctionCount();
    if (!expectedTestCount || ctx.cmdLine().command != CommandKind::Test || !ctx.cmdLine().nativeTestProgress)
        return Result::Continue;

    builder_->testProgressEntries.reserve(builder_->testFunctions.size());
    for (SymbolFunction* symbol : builder_->testFunctions)
    {
        TestSourceLocation sourceLocation;
        bool               hasSourceLocation = false;

        const SymbolFunction* candidates[] = {
            primaryTestLocationSymbol(*symbol),
            symbol->genericRootSym(),
            symbol,
        };

        for (size_t candidateIndex = 0; candidateIndex < std::size(candidates); ++candidateIndex)
        {
            const SymbolFunction* candidate = candidates[candidateIndex];
            if (!candidate)
                continue;

            bool alreadyTried = false;
            for (size_t priorIndex = 0; priorIndex < candidateIndex; ++priorIndex)
            {
                if (candidates[priorIndex] == candidate)
                {
                    alreadyTried = true;
                    break;
                }
            }

            if (alreadyTried)
                continue;

            const TestSourceLocation candidateLocation = resolveTestSourceLocation(ctx, builder_->compiler(), *candidate);
            if (!hasSourceLocation)
            {
                sourceLocation    = candidateLocation;
                hasSourceLocation = true;
            }

            if (hasUsableTestSourceFileName(candidateLocation))
            {
                sourceLocation = candidateLocation;
                break;
            }
        }

        Utf8 progressMessage = sourceLocation.fileName;
        progressMessage += ":";
        progressMessage += std::to_string(sourceLocation.line);
        progressMessage += "\n";

        const ConstantRef messageRuntimeStringCstRef = materializeRuntimeStringConstant(ctx, progressMessage);
        SWC_ASSERT(messageRuntimeStringCstRef.isValid());
        if (messageRuntimeStringCstRef.isInvalid())
            return builder_->reportError(DiagnosticId::cmd_err_native_test_entry_lower_failed);

        builder_->testProgressEntries.push_back({
            .messageRuntimeStringCstRef = messageRuntimeStringCstRef,
        });
    }

    return Result::Continue;
}

Result NativeArtifactBuilder::prepareOutputFolders() const
{
    NativeArtifactPaths paths;
    queryPaths(paths, static_cast<uint32_t>(builder_->objectDescriptions.size()));
    if (builder_->ctx().cmdLine().clear && builder_->compiler().markNativeOutputsCleared())
        SWC_RESULT(clearOutputFolders(paths));
    SWC_RESULT(createBuildDir(paths.buildDir));
    SWC_RESULT(createOutDir(paths.outDir));
    return Result::Continue;
}

void NativeArtifactBuilder::queryPaths(NativeArtifactPaths& outPaths, const uint32_t numObjects) const
{
    outPaths.workDir.clear();
    outPaths.buildDir.clear();
    outPaths.objectPaths.clear();
    const auto buildCfgName = Utf8(builder_->compiler().buildCfg().name);
    if (!buildCfgName.empty())
        outPaths.name = FileSystem::sanitizeFileName(buildCfgName);
    else
        outPaths.name = defaultArtifactName(builder_->ctx().cmdLine());

    const auto buildCfgWorkDir = Utf8(builder_->compiler().buildCfg().workDir);
    if (!buildCfgWorkDir.empty())
        outPaths.workDir = fs::path(buildCfgWorkDir.c_str());
    if (outPaths.workDir.empty())
    {
        const CommandLine&    cmdLine = builder_->ctx().cmdLine();
        std::vector<fs::path> roots;
        if (!cmdLine.modulePath.empty())
            roots.push_back(FileSystem::absolutePathNoThrow(cmdLine.modulePath.parent_path()));

        for (const fs::path& input : cmdLine.files)
        {
            fs::path root = input.parent_path();
            if (root.empty())
                root = input;

            root = FileSystem::absolutePathNoThrow(root);
            if (!root.empty())
                roots.push_back(root);
        }

        for (const fs::path& input : cmdLine.directories)
        {
            fs::path root = FileSystem::absolutePathNoThrow(input);
            if (!root.empty())
                roots.push_back(root);
        }

        fs::path sourceRoot;
        if (!roots.empty())
        {
            sourceRoot = roots.front();
            for (size_t i = 1; i < roots.size(); ++i)
            {
                fs::path commonRoot;
                auto     lhsIt = sourceRoot.begin();
                auto     rhsIt = roots[i].begin();
                while (lhsIt != sourceRoot.end() && rhsIt != roots[i].end() && *lhsIt == *rhsIt)
                {
                    commonRoot /= *lhsIt;
                    ++lhsIt;
                    ++rhsIt;
                }

                sourceRoot = std::move(commonRoot);
                if (sourceRoot.empty())
                {
                    sourceRoot = roots.front();
                    break;
                }
            }

            if (sourceRoot == sourceRoot.root_path())
                sourceRoot = roots.front();
        }

        if (sourceRoot.empty())
            sourceRoot = FileSystem::currentPathNoThrow();
        outPaths.workDir = sourceRoot / ".output" / automaticWorkDirName(outPaths.name).c_str();
    }

    outPaths.buildDir          = outPaths.workDir;
    outPaths.artifactExtension = artifactExtension();
    const auto buildCfgOutDir  = Utf8(builder_->compiler().buildCfg().outDir);
    if (!buildCfgOutDir.empty())
        outPaths.outDir = fs::path(buildCfgOutDir.c_str());
    else
        outPaths.outDir = outPaths.workDir;
    outPaths.artifactPath = outPaths.outDir / std::format("{}{}", outPaths.name, outPaths.artifactExtension);
    outPaths.pdbPath      = outPaths.outDir / std::format("{}.pdb", outPaths.name);

    if (!numObjects)
        return;

    outPaths.objectPaths.clear();
    outPaths.objectPaths.reserve(numObjects);
    const Utf8 objectExt = objectExtension();
    for (uint32_t i = 0; i < numObjects; ++i)
        outPaths.objectPaths.push_back(outPaths.buildDir / std::format("{}_{:02}{}", outPaths.name, i, objectExt).c_str());
}

Result NativeArtifactBuilder::clearOutputFolders(const NativeArtifactPaths& paths) const
{
    SWC_RESULT(FileSystem::clearDirectoryContents(builder_->ctx(), paths.workDir, DiagnosticId::cmd_err_native_output_dir_clear_failed));
    if (!FileSystem::pathEquals(paths.outDir, paths.workDir))
        SWC_RESULT(FileSystem::clearDirectoryContents(builder_->ctx(), paths.outDir, DiagnosticId::cmd_err_native_output_dir_clear_failed));
    return Result::Continue;
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
                case Runtime::BuildCfgBackendKind::SharedLibrary:
                    return ".dll";
                case Runtime::BuildCfgBackendKind::StaticLibrary:
                    return ".lib";
                case Runtime::BuildCfgBackendKind::Export:
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

Result NativeArtifactBuilder::createOutDir(const fs::path& outDir) const
{
    std::error_code ec;
    fs::create_directories(outDir, ec);
    if (ec)
        return builder_->reportError(DiagnosticId::cmd_err_native_work_dir_create_failed, Diagnostic::ARG_PATH, Utf8(outDir), Diagnostic::ARG_BECAUSE, ec.message());
    return Result::Continue;
}

Utf8 NativeArtifactBuilder::automaticWorkDirName(const Utf8& name) const
{
    const CommandLine& cmdLine = builder_->ctx().cmdLine();
    Utf8               key;

    key += std::format("cmd={};os={};arch={};backend={};sub={};name={};", static_cast<int>(cmdLine.command), static_cast<int>(cmdLine.targetOs), static_cast<int>(cmdLine.targetArch), static_cast<int>(builder_->compiler().buildCfg().backendKind), static_cast<int>(builder_->compiler().buildCfg().backendSubKind), name);

    if (!cmdLine.modulePath.empty())
    {
        key += "module=";
        key += Utf8(cmdLine.modulePath);
        key += ";";
    }

    for (const fs::path& file : cmdLine.files)
    {
        key += "file=";
        key += Utf8(file);
        key += ";";
    }

    for (const fs::path& directory : cmdLine.directories)
    {
        key += "directory=";
        key += Utf8(directory);
        key += ";";
    }

    for (const fs::path& file : cmdLine.importApiFiles)
    {
        key += "import-api-file=";
        key += Utf8(file);
        key += ";";
    }

    for (const fs::path& directory : cmdLine.importApiDirs)
    {
        key += "import-api-dir=";
        key += Utf8(directory);
        key += ";";
    }

    // Keep the auto-generated work dir deterministic for a given command line so cleanup
    // and incremental native builds operate in the same location.
    const uint32_t hash = static_cast<uint32_t>(std::hash<std::string_view>{}(key.view()));
    return std::format("{}_{:08x}", FileSystem::sanitizeFileName(name), hash);
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
    resetDataSections();

    NativeRDataCollector collector(*builder_);
    SWC_RESULT(collector.collectStartupRoots());
    SWC_RESULT(prepareDataSectionsWithoutStartup(collector));
    return finishDataSections(collector);
}

Result NativeArtifactBuilder::buildStartupAndDataSectionsParallel() const
{
    resetDataSections();

    JobManager&          jobMgr     = builder_->ctx().global().jobMgr();
    auto*                startupJob = heapNew<NativeStartupBuildJob>(builder_->ctx(), *this);
    NativeRDataCollector collector(*builder_);
    const JobClientId    clientId = builder_->compiler().jobClientId();
    jobMgr.enqueue(*startupJob, JobPriority::Normal, clientId);

    const Result dataResult = prepareDataSectionsWithoutStartup(collector);
    jobMgr.waitAll(clientId);
#if SWC_DEV_MODE
    jobMgr.assertNoWaitingJobs(clientId, "NativeArtifactBuilder::buildStartupAndDataSectionsParallel");
#endif

    SWC_RESULT(startupJob->result());
    SWC_RESULT(dataResult);
    SWC_RESULT(collector.collectStartupRoots());
    return finishDataSections(collector);
}

void NativeArtifactBuilder::resetDataSections() const
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
}

Result NativeArtifactBuilder::prepareDataSectionsWithoutStartup(NativeRDataCollector& rdataCollector) const
{
    // Emitted function code is the source of truth for native constant roots.
    // Startup roots are collected after startup lowering has completed.
    SWC_RESULT(rdataCollector.collectFunctionRoots());

    CompilerInstance& compiler = builder_->compiler();
    const uint32_t    dataSize = compiler.globalInitSegment().extentSize();
    if (dataSize)
    {
        builder_->mergedData.bytes.resize(dataSize);
        compiler.globalInitSegment().copyToPreserveOffsets(ByteSpanRW{builder_->mergedData.bytes.data(), dataSize});

        for (const auto& relocation : compiler.globalInitSegment().relocations())
        {
            NativeSectionRelocation record;
            record.offset = relocation.offset;
            if (relocation.kind == DataSegmentRelocationKind::DataSegmentOffset)
            {
                record.symbolName = nativeScopedSectionBaseSymbol(builder_->compiler(), K_DATA_BASE_SYMBOL);
                record.addend     = relocation.targetOffset;
            }
            else
            {
                SWC_ASSERT(relocation.kind == DataSegmentRelocationKind::FunctionSymbol);
                SWC_RESULT(builder_->resolveFunctionSymbolName(record.symbolName, relocation.targetSymbol));
                record.addend = 0;
            }

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

            const SymbolFunction* targetFunction = symbol->globalFunctionInit();
            if (!targetFunction)
                continue;

            const uint64_t storageSize = builder_->ctx().typeMgr().get(symbol->typeRef()).sizeOf(builder_->ctx());
            SWC_ASSERT(storageSize == sizeof(uint64_t));

            NativeSectionRelocation record;
            record.offset = symbol->offset();
            SWC_RESULT(builder_->resolveFunctionSymbolName(record.symbolName, targetFunction));
            record.addend = 0;
            builder_->mergedData.relocations.push_back(record);
        }
    }

    return Result::Continue;
}

Result NativeArtifactBuilder::finishDataSections(NativeRDataCollector& rdataCollector)
{
    return rdataCollector.emitCollectedRoots();
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

Result NativeArtifactBuilder::buildStartup(TaskContext& ctx) const
{
    builder_->startup.reset();

    if (builder_->compiler().buildCfg().backendKind != Runtime::BuildCfgBackendKind::Executable)
        return Result::Continue;
    // Source-driven native tests can legitimately build an executable with no user-defined
    // #main: #test and lifecycle hooks still need a startup thunk to run.
    if (builder_->mainFunctions.empty() && builder_->testFunctions.empty() && builder_->initFunctions.empty() && builder_->preMainFunctions.empty() && builder_->dropFunctions.empty())
        return builder_->reportError(DiagnosticId::cmd_err_native_main_missing);

    const uint32_t expectedTestCount = builder_->expectedTestFunctionCount();
    if (builder_->testFunctions.size() != expectedTestCount)
    {
        return builder_->reportError(DiagnosticId::cmd_err_native_test_count_mismatch, Diagnostic::ARG_COUNT, expectedTestCount, Diagnostic::ARG_VALUE, static_cast<uint32_t>(builder_->testFunctions.size()));
    }
    const bool emitTestProgress = expectedTestCount && ctx.cmdLine().command == CommandKind::Test && ctx.cmdLine().nativeTestProgress;

    auto         startup = std::make_unique<NativeStartupInfo>();
    MicroBuilder builder(builder_->ctx());
    builder.setBackendBuildCfg(builder_->compiler().buildCfg().backend);
    uint32_t       nextVirtualIntRegIndex = builder.nextVirtualIntRegIndexHint();
    const MicroReg testProgressMessageReg = emitTestProgress ? nextVirtualIntReg(nextVirtualIntRegIndex) : MicroReg::invalid();

    const IdentifierRef ensureRuntimeAllocatorIdRef = ctx.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::EnsureRuntimeAllocator);
    SymbolFunction*     ensureRuntimeAllocatorFn    = builder_->compiler().runtimeFunctionSymbol(ensureRuntimeAllocatorIdRef);
    SymbolFunction*     testCountInitFn             = nullptr;
    SymbolFunction*     testCountTickFn             = nullptr;
    SymbolFunction*     testPrintStartFn            = nullptr;
    SymbolFunction*     testPrintProgressFn         = nullptr;
    SymbolFunction*     testPrintDoneFn             = nullptr;
    SWC_ASSERT(ensureRuntimeAllocatorFn != nullptr);
    if (!ensureRuntimeAllocatorFn)
        return builder_->reportError(DiagnosticId::cmd_err_native_test_entry_lower_failed);
    if (expectedTestCount)
    {
        const IdentifierRef testCountInitIdRef = ctx.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::TestCountInit);
        const IdentifierRef testCountTickIdRef = ctx.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::TestCountTick);
        testCountInitFn                        = builder_->compiler().runtimeFunctionSymbol(testCountInitIdRef);
        testCountTickFn                        = builder_->compiler().runtimeFunctionSymbol(testCountTickIdRef);
        SWC_ASSERT(testCountInitFn != nullptr);
        SWC_ASSERT(testCountTickFn != nullptr);
        if (!testCountInitFn || !testCountTickFn)
            return builder_->reportError(DiagnosticId::cmd_err_native_test_entry_lower_failed);
    }
    if (emitTestProgress)
    {
        SWC_ASSERT(builder_->testProgressEntries.size() == builder_->testFunctions.size());
        if (builder_->testProgressEntries.size() != builder_->testFunctions.size())
            return builder_->reportError(DiagnosticId::cmd_err_native_test_entry_lower_failed);

        const IdentifierRef testPrintStartIdRef    = ctx.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::TestPrintStart);
        const IdentifierRef testPrintProgressIdRef = ctx.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::TestPrintProgress);
        const IdentifierRef testPrintDoneIdRef     = ctx.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::TestPrintDone);
        testPrintStartFn                           = builder_->compiler().runtimeFunctionSymbol(testPrintStartIdRef);
        testPrintProgressFn                        = builder_->compiler().runtimeFunctionSymbol(testPrintProgressIdRef);
        testPrintDoneFn                            = builder_->compiler().runtimeFunctionSymbol(testPrintDoneIdRef);
        SWC_ASSERT(testPrintStartFn != nullptr);
        SWC_ASSERT(testPrintProgressFn != nullptr);
        SWC_ASSERT(testPrintDoneFn != nullptr);
        if (!testPrintStartFn || !testPrintProgressFn || !testPrintDoneFn)
            return builder_->reportError(DiagnosticId::cmd_err_native_test_entry_lower_failed);
    }

    ABICall::callLocal(builder, ensureRuntimeAllocatorFn->callConvKind(), ensureRuntimeAllocatorFn, {});

    // The startup thunk runs compiler-generated lifecycle hooks and then hands off
    // process termination to the runtime wrapper for the active target.
    for (SymbolFunction* symbol : builder_->initFunctions)
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
    for (SymbolFunction* symbol : builder_->preMainFunctions)
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});

    if (testCountInitFn)
    {
        const MicroReg expectedCountReg = nextVirtualIntReg(nextVirtualIntRegIndex);
        builder.emitLoadRegImm(expectedCountReg, ApInt(expectedTestCount, 64), MicroOpBits::B64);

        ABICall::PreparedArg countArg;
        countArg.srcReg  = expectedCountReg;
        countArg.kind    = ABICall::PreparedArgKind::Direct;
        countArg.numBits = 64;

        SmallVector<ABICall::PreparedArg> preparedArgs;
        preparedArgs.push_back(countArg);

        const ABICall::PreparedCall preparedInit = ABICall::prepareArgs(builder, testCountInitFn->callConvKind(), preparedArgs);
        ABICall::callLocal(builder, testCountInitFn->callConvKind(), testCountInitFn, preparedInit);
        if (testPrintStartFn)
        {
            const ABICall::PreparedCall preparedStart = ABICall::prepareArgs(builder, testPrintStartFn->callConvKind(), {});
            ABICall::callLocal(builder, testPrintStartFn->callConvKind(), testPrintStartFn, preparedStart);
        }
    }

    for (size_t testIndex = 0; testIndex < builder_->testFunctions.size(); ++testIndex)
    {
        SymbolFunction* symbol = builder_->testFunctions[testIndex];
        if (testPrintProgressFn)
        {
            const NativeTestProgressEntry& progressEntry              = builder_->testProgressEntries[testIndex];
            const ConstantRef              messageRuntimeStringCstRef = progressEntry.messageRuntimeStringCstRef;
            SWC_ASSERT(messageRuntimeStringCstRef.isValid());
            if (messageRuntimeStringCstRef.isInvalid())
                return builder_->reportError(DiagnosticId::cmd_err_native_test_entry_lower_failed);

            loadConstantStoragePointerReg(builder, ctx, testProgressMessageReg, messageRuntimeStringCstRef);

            ABICall::PreparedArg messageArg;
            messageArg.srcReg             = testProgressMessageReg;
            messageArg.kind               = ABICall::PreparedArgKind::Direct;
            messageArg.isFloat            = false;
            messageArg.isSigned           = false;
            messageArg.isAddressed        = false;
            messageArg.constrainToArgLane = true;
            messageArg.numBits            = 64;

            SmallVector<ABICall::PreparedArg> preparedArgs;
            preparedArgs.push_back(messageArg);

            const ABICall::PreparedCall preparedProgress = ABICall::prepareArgs(builder, testPrintProgressFn->callConvKind(), preparedArgs);
            ABICall::callLocal(builder, testPrintProgressFn->callConvKind(), testPrintProgressFn, preparedProgress);
        }
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
        if (testCountTickFn)
        {
            const ABICall::PreparedCall preparedTick = ABICall::prepareArgs(builder, testCountTickFn->callConvKind(), {});
            ABICall::callLocal(builder, testCountTickFn->callConvKind(), testCountTickFn, preparedTick);
        }
    }
    for (SymbolFunction* symbol : builder_->mainFunctions)
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
    for (SymbolFunction* symbol : builder_->dropFunctions)
        ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
    if (testPrintDoneFn)
    {
        const ABICall::PreparedCall preparedDone = ABICall::prepareArgs(builder, testPrintDoneFn->callConvKind(), {});
        ABICall::callLocal(builder, testPrintDoneFn->callConvKind(), testPrintDoneFn, preparedDone);
    }

    const IdentifierRef exitIdRef = ctx.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::Exit);
    SymbolFunction*     exitFn    = builder_->compiler().runtimeFunctionSymbol(exitIdRef);
    SWC_ASSERT(exitFn != nullptr);

    // Startup calls the runtime wrapper instead of a raw OS entry point, so the
    // emitted startup sequence stays stable across target-specific runtimes.
    const ABICall::PreparedCall preparedExit = ABICall::prepareArgs(builder, exitFn->callConvKind(), {});
    ABICall::callLocal(builder, exitFn->callConvKind(), exitFn, preparedExit);
    builder.emitRet();

    if (startup->code.emit(ctx, builder) != Result::Continue)
        return builder_->reportError(DiagnosticId::cmd_err_native_test_entry_lower_failed);

    builder_->startup = std::move(startup);
    return Result::Continue;
}

SWC_END_NAMESPACE();
