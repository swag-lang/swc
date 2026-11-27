#include "pch.h"
#include "Backend/Native/NativeArtifactBuilder.h"
#include "Backend/ABI/ABICall.h"
#include "Backend/Linker/Format.COFF.h"
#include "Backend/Micro/MicroBuilder.h"
#include "Backend/Native/NativeBackendBuilder.h"
#include "Backend/Native/NativeNames.h"
#include "Backend/Native/NativeRDataCollector.h"
#include "Backend/RuntimeBackendConfig.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantStorageLayout.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLine.h"
#include "Main/CompilerInstance.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"
#include "Support/Report/ScopedTimedLog.h"
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
    MicroReg nextVirtualIntReg(uint32_t& nextIndex)
    {
        return MicroReg::virtualIntReg(nextIndex++);
    }

    void emitLifecycleCalls(MicroBuilder& builder, const std::span<SymbolFunction* const> functions)
    {
        for (const SymbolFunction* symbol : functions)
            ABICall::callLocal(builder, symbol->callConvKind(), symbol, {});
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

Result NativeArtifactBuilder::prepareOutputFolders() const
{
    NativeArtifactPaths paths;
    queryPaths(paths);
    SWC_RESULT(createDirectories(paths.buildDir));
    SWC_RESULT(createDirectories(paths.outDir));

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

    // The mode travels in the name, so the artifact, its PDB, and its object files
    // are all distinct from the ones another mode produces from the same sources.
    outPaths.name += artifactModeSuffix(builder_->ctx().cmdLine());

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

    const auto buildCfgOutDir = Utf8(builder_->compiler().buildCfg().outDir);
    if (!buildCfgOutDir.empty())
        outPaths.outDir = fs::path(buildCfgOutDir.c_str());
    else
        outPaths.outDir = outPaths.workDir;

    outPaths.artifactPath = outPaths.outDir / std::format("{}{}", outPaths.name, outPaths.artifactExtension);
    outPaths.pdbPath      = builder_->ctx().cmdLine().targetOs == Runtime::TargetOs::Windows ? outPaths.outDir / std::format("{}.pdb", outPaths.name) : fs::path{};

    if (!numObjects)
        return;

    outPaths.objectPaths.reserve(numObjects);
    const Utf8 objectExt = objectExtension();
    for (uint32_t i = 0; i < numObjects; ++i)
        outPaths.objectPaths.push_back(outPaths.buildDir / std::format("{}_{:02}{}", outPaths.name, i, objectExt).c_str());
}

Utf8 NativeArtifactBuilder::artifactExtension() const
{
    return builder_->ctx().cmdLine().targetOs == Runtime::TargetOs::Windows ? ".exe" : "";
}

Utf8 NativeArtifactBuilder::objectExtension() const
{
    switch (builder_->ctx().cmdLine().targetOs)
    {
        case Runtime::TargetOs::Linux:
            return ".o";
        case Runtime::TargetOs::Windows:
            return ".obj";
    }

    SWC_UNREACHABLE();
}

Result NativeArtifactBuilder::createDirectories(const fs::path& path) const
{
    std::error_code ec;
    fs::create_directories(path, ec);
    if (ec)
        return builder_->reportError(DiagnosticId::cmd_err_native_work_dir_create_failed, Diagnostic::ARG_PATH, Utf8(path), Diagnostic::ARG_BECAUSE, ec.message());

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

    // Keep the auto-generated work dir deterministic for a given command line so cleanup
    // and incremental native builds operate in the same location.
    const uint32_t hash = static_cast<uint32_t>(std::hash<std::string_view>{}(key.view()));
    return std::format("{}_{:08x}", FileSystem::sanitizeFileName(name), hash);
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
    auto*                startupJob = builder_->compiler().makeJob<NativeStartupBuildJob>(builder_->ctx(), *this);
    NativeRDataCollector collector(*builder_);
    const JobClientId    clientId = builder_->compiler().jobClientId();
    jobMgr.enqueue(*startupJob, JobPriority::Normal, clientId);

    const Result dataResult = prepareDataSectionsWithoutStartup(collector);
    jobMgr.waitAll(clientId);

    SWC_RESULT(startupJob->result());
    SWC_RESULT(dataResult);
    SWC_RESULT(collector.collectStartupRoots());
    return finishDataSections(collector);
}

void NativeArtifactBuilder::resetDataSections() const
{
    builder_->mergedRData.name            = ".rdata";
    builder_->mergedRData.characteristics = PE::SCN_CNT_INITIALIZED_DATA | PE::SCN_MEM_READ | PE::SCN_ALIGN_16BYTES;

    builder_->mergedData.name            = ".data";
    builder_->mergedData.characteristics = PE::SCN_CNT_INITIALIZED_DATA | PE::SCN_MEM_READ | PE::SCN_MEM_WRITE | PE::SCN_ALIGN_16BYTES;

    builder_->mergedBss.name            = ".bss";
    builder_->mergedBss.characteristics = PE::SCN_CNT_UNINITIALIZED_DATA | PE::SCN_MEM_READ | PE::SCN_MEM_WRITE | PE::SCN_ALIGN_16BYTES;

    builder_->mergedRData.bytes.clear();
    builder_->mergedRData.relocations.clear();
    builder_->mergedData.bytes.clear();
    builder_->mergedData.relocations.clear();
    builder_->mergedBss.bssSize = 0;
    builder_->mergedBss.bss     = false;

    for (auto& mappings : builder_->rdataAllocationMap)
        mappings.clear();
}

Result NativeArtifactBuilder::prepareDataSectionsWithoutStartup(NativeRDataCollector& rdataCollector) const
{
    // Startup roots, and the global storage that startup code reaches, arrive after startup
    // lowering has completed.
    return rdataCollector.collectFunctionRoots();
}

Result NativeArtifactBuilder::finishDataSections(NativeRDataCollector& rdataCollector) const
{
    // Startup code is lowered by now, so every root of the global storage is known. Global
    // initializers also retain constants, such as dynamic type descriptors, without requiring a
    // code reference; constant offsets are only known once every root has been emitted.
    NativeGlobalLayout& layout = builder_->globalLayout;
    layout.build(*builder_);
    builder_->mergedData.requireAlignment(layout.initAlignment());
    builder_->mergedBss.requireAlignment(layout.zeroAlignment());
    SWC_RESULT(rdataCollector.collectGlobalRoots());
    SWC_RESULT(rdataCollector.emitCollectedRoots());

    builder_->mergedBss.bssSize = layout.zeroSize();
    builder_->mergedBss.bss     = builder_->mergedBss.bssSize != 0;
    if (!layout.initSize())
        return Result::Continue;

    const DataSegment& initSegment = builder_->compiler().globalInitSegment();
    builder_->mergedData.bytes.resize(layout.initSize());

    const NativeBackendBuilder::ScopedSymbolNames* names = nullptr;
    std::vector<DataSegmentRelocation>             relocations;
    for (const NativeGlobalLayout::Allocation& allocation : layout.initAllocations())
    {
        const auto* sourceBytes = initSegment.ptr<std::byte>(allocation.sourceOffset);
        SWC_ASSERT(sourceBytes != nullptr);
        std::memcpy(builder_->mergedData.bytes.data() + allocation.emittedOffset, sourceBytes, allocation.size);

        initSegment.copyRelocations(relocations, allocation.sourceOffset, allocation.size);
        for (const auto& relocation : relocations)
        {
            NativeSectionRelocation record;
            record.offset = allocation.emittedOffset + (relocation.offset - allocation.sourceOffset);
            if (relocation.kind == DataSegmentRelocationKind::DataSegmentOffset)
            {
                if (!names)
                    names = &builder_->scopedSymbolNames();

                if (relocation.targetShardIndex == INVALID_REF)
                {
                    record.symbolName = names->dataBase;
                    record.addend     = layout.map(DataSegmentKind::GlobalInit, relocation.targetOffset);
                }
                else
                {
                    uint32_t targetOffset = 0;
                    if (!builder_->tryMapRDataSourceOffset(targetOffset, relocation.targetShardIndex, relocation.targetOffset))
                        return builder_->reportError(DiagnosticId::cmd_err_native_constant_payload_unsupported, Diagnostic::ARG_SYM, names->dataBase);

                    record.symbolName = names->rdataBase;
                    record.addend     = targetOffset;
                }
            }
            else
            {
                SWC_ASSERT(relocation.kind == DataSegmentRelocationKind::FunctionSymbol);
                SWC_RESULT(builder_->resolveFunctionSymbolName(record.symbolName, relocation.targetSymbol));
                record.addend = 0;
            }

            builder_->mergedData.relocations.push_back(std::move(record));
        }
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
        record.offset = layout.map(DataSegmentKind::GlobalInit, symbol->offset());
        SWC_RESULT(builder_->resolveFunctionSymbolName(record.symbolName, targetFunction));
        record.addend = 0;
        builder_->mergedData.relocations.push_back(std::move(record));
    }

    return Result::Continue;
}

Result NativeArtifactBuilder::partitionObjects() const
{
    builder_->objectDescriptions.clear();

    const size_t functionCount = std::ranges::count_if(builder_->functionInfos, [](const NativeFunctionInfo& info) { return !info.cacheHit; });

    uint32_t maxJobs = builder_->ctx().cmdLine().numCores;
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
    const size_t functionsPerObject = functionCount / numJobs;
    const size_t extraFunctions     = functionCount % numJobs;
    for (uint32_t i = 0; i < numJobs; ++i)
    {
        builder_->objectDescriptions[i].index                 = i;
        builder_->objectDescriptions[i].includeData           = i == 0;
        builder_->objectDescriptions[i].includeMergedRData   = i == 0;
        builder_->objectDescriptions[i].objPath               = std::move(paths.objectPaths[i]);
        builder_->objectDescriptions[i].functions.reserve(functionsPerObject + (i < extraFunctions ? 1 : 0));
    }

    if (builder_->startup)
        builder_->objectDescriptions[0].startup = builder_->startup.get();

    size_t functionIndex = 0;
    for (size_t i = 0; i < builder_->functionInfos.size(); ++i)
    {
        NativeFunctionInfo& info = builder_->functionInfos[i];
        if (info.cacheHit)
            continue;

        const uint32_t objIndex = static_cast<uint32_t>(functionIndex++ % numJobs);
        info.jobIndex           = objIndex;
        builder_->objectDescriptions[objIndex].functions.push_back(&info);
    }

    return Result::Continue;
}

Result NativeArtifactBuilder::partitionIncrementalFunctionObjects() const
{
    builder_->objectDescriptions.clear();
    for (NativeFunctionInfo& info : builder_->functionInfos)
    {
        const NativeFunctionCacheRecord* record = info.symbol ? builder_->functionCacheRecord(*info.symbol) : nullptr;
        if (!record || info.cacheHit)
            continue;

        NativeObjDescription description;
        description.index = static_cast<uint32_t>(builder_->objectDescriptions.size());
        description.functions.push_back(&info);
        builder_->objectDescriptions.push_back(std::move(description));
    }

    NativeArtifactPaths paths;
    queryPaths(paths, static_cast<uint32_t>(builder_->objectDescriptions.size()));
    for (uint32_t i = 0; i < builder_->objectDescriptions.size(); ++i)
    {
        builder_->objectDescriptions[i].index                       = i;
        builder_->objectDescriptions[i].objPath                     = std::move(paths.objectPaths[i]);
        builder_->objectDescriptions[i].functions.front()->jobIndex = i;
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

    auto         startup = std::make_unique<NativeStartupInfo>();
    MicroBuilder builder(builder_->ctx());
    builder.setBackendBuildCfg(builder_->compiler().buildCfg().backend);
    uint32_t nextVirtualIntRegIndex = builder.nextVirtualIntRegIndexHint();

    if (ctx.cmdLine().targetOs == Runtime::TargetOs::Linux)
    {
        startup->symbolName           = "main";
        startup->debugName            = "main";
        const auto* argumentsFunction = builder_->compiler().runtimeFunctionSymbol(IdentifierManager::RuntimeFunctionKind::SetupUnixArguments);
        SWC_ASSERT(argumentsFunction);
        if (!argumentsFunction)
            return builder_->reportError(DiagnosticId::cmd_err_native_test_entry_lower_failed);
        const CallConv& incoming = CallConv::get(CallConvKind::SystemVAMD64);
        const MicroReg  argcReg  = nextVirtualIntReg(nextVirtualIntRegIndex);
        const MicroReg  argvReg  = nextVirtualIntReg(nextVirtualIntRegIndex);
        builder.emitLoadRegReg(argcReg, incoming.intArgRegs[0], MicroOpBits::B32);
        builder.emitLoadRegReg(argvReg, incoming.intArgRegs[1], MicroOpBits::B64);
        const std::array<ABICall::PreparedArg, 2> arguments = {{{.srcReg = argcReg, .numBits = 32}, {.srcReg = argvReg, .numBits = 64}}};
        const auto                                prepared  = ABICall::prepareArgs(builder, argumentsFunction->callConvKind(), arguments);
        ABICall::callLocal(builder, argumentsFunction->callConvKind(), argumentsFunction, prepared);
    }

    const IdentifierRef   setupRuntimeIdRef = ctx.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::SetupRuntime);
    const IdentifierRef   closeRuntimeIdRef = ctx.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::CloseRuntime);
    const SymbolFunction* setupRuntimeFn    = builder_->compiler().runtimeFunctionSymbol(setupRuntimeIdRef);
    const SymbolFunction* closeRuntimeFn    = builder_->compiler().runtimeFunctionSymbol(closeRuntimeIdRef);
    SWC_ASSERT(setupRuntimeFn != nullptr);
    SWC_ASSERT(closeRuntimeFn != nullptr);
    if (!setupRuntimeFn || !closeRuntimeFn)
        return builder_->reportError(DiagnosticId::cmd_err_native_test_entry_lower_failed);

    const MicroReg runtimeFlagsReg = nextVirtualIntReg(nextVirtualIntRegIndex);
    builder.emitLoadRegImm(runtimeFlagsReg, ApInt(static_cast<uint64_t>(Runtime::RuntimeFlags::Zero), 64), MicroOpBits::B64);

    ABICall::PreparedArg runtimeFlagsArg;
    runtimeFlagsArg.srcReg  = runtimeFlagsReg;
    runtimeFlagsArg.kind    = ABICall::PreparedArgKind::Direct;
    runtimeFlagsArg.numBits = 64;

    SmallVector<ABICall::PreparedArg> setupRuntimeArgs;
    setupRuntimeArgs.push_back(runtimeFlagsArg);

    const ABICall::PreparedCall preparedSetupRuntime = ABICall::prepareArgs(builder, setupRuntimeFn->callConvKind(), setupRuntimeArgs);
    ABICall::callLocal(builder, setupRuntimeFn->callConvKind(), setupRuntimeFn, preparedSetupRuntime);

    // The startup thunk runs compiler-generated lifecycle hooks and then hands off
    // process termination to the runtime wrapper for the active target.
    emitLifecycleCalls(builder, builder_->initFunctions);
    emitLifecycleCalls(builder, builder_->preMainFunctions);

    // #test functions run through the runtime test runner: __runTest reports and
    // counts a failing test (assert/panic) without stopping the remaining ones, and
    // __testsDone prints the executed/failed tally the compiler parses back.
    if (!builder_->testFunctions.empty())
    {
        const IdentifierRef   runTestIdRef   = ctx.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::RunTest);
        const IdentifierRef   testsDoneIdRef = ctx.idMgr().runtimeFunction(IdentifierManager::RuntimeFunctionKind::TestsDone);
        const SymbolFunction* runTestFn      = builder_->compiler().runtimeFunctionSymbol(runTestIdRef);
        const SymbolFunction* testsDoneFn    = builder_->compiler().runtimeFunctionSymbol(testsDoneIdRef);
        SWC_ASSERT(runTestFn != nullptr && testsDoneFn != nullptr);
        if (!runTestFn || !testsDoneFn)
            return builder_->reportError(DiagnosticId::cmd_err_native_test_entry_lower_failed);

        for (const SymbolFunction* symbol : builder_->testFunctions)
        {
            const MicroReg testFnReg = nextVirtualIntReg(nextVirtualIntRegIndex);
            builder.emitLoadRegPtrReloc(testFnReg, 0, ConstantRef::invalid(), symbol);

            const Utf8           testName    = ScopedTimedLog::formatTestLocation(ctx, *symbol);
            const ConstantRef    testNameRef = ctx.cstMgr().addConstant(ctx, ConstantValue::makeString(ctx, testName));
            const ConstantValue& testNameCst = ctx.cstMgr().get(testNameRef);
            const MicroReg       testNameReg = nextVirtualIntReg(nextVirtualIntRegIndex);
            builder.emitLoadRegPtrReloc(testNameReg, reinterpret_cast<uint64_t>(testNameCst.getString().data()), testNameRef);

            const SourceFile* sourceFile = builder_->compiler().ownerSourceFile(symbol->srcViewRef());
            if (!sourceFile)
                sourceFile = builder_->compiler().sourceViewFile(*symbol);

            const Utf8           testPath    = sourceFile ? Utf8Helper::normalizePathForCompare(sourceFile->path()) : Utf8{};
            const ConstantRef    testPathRef = ctx.cstMgr().addConstant(ctx, ConstantValue::makeString(ctx, testPath));
            const ConstantValue& testPathCst = ctx.cstMgr().get(testPathRef);
            const MicroReg       testPathReg = nextVirtualIntReg(nextVirtualIntRegIndex);
            builder.emitLoadRegPtrReloc(testPathReg, reinterpret_cast<uint64_t>(testPathCst.getString().data()), testPathRef);

            const std::string_view testTag    = builder_->compiler().testTag(*symbol);
            const ConstantRef      testTagRef = ctx.cstMgr().addConstant(ctx, ConstantValue::makeString(ctx, testTag));
            const ConstantValue&   testTagCst = ctx.cstMgr().get(testTagRef);
            const MicroReg         testTagReg = nextVirtualIntReg(nextVirtualIntRegIndex);
            builder.emitLoadRegPtrReloc(testTagReg, reinterpret_cast<uint64_t>(testTagCst.getString().data()), testTagRef);

            ABICall::PreparedArg testFnArg;
            testFnArg.srcReg  = testFnReg;
            testFnArg.kind    = ABICall::PreparedArgKind::Direct;
            testFnArg.numBits = 64;

            ABICall::PreparedArg testNameArg;
            testNameArg.srcReg  = testNameReg;
            testNameArg.kind    = ABICall::PreparedArgKind::Direct;
            testNameArg.numBits = 64;

            ABICall::PreparedArg testPathArg;
            testPathArg.srcReg  = testPathReg;
            testPathArg.kind    = ABICall::PreparedArgKind::Direct;
            testPathArg.numBits = 64;

            ABICall::PreparedArg testTagArg;
            testTagArg.srcReg  = testTagReg;
            testTagArg.kind    = ABICall::PreparedArgKind::Direct;
            testTagArg.numBits = 64;

            SmallVector<ABICall::PreparedArg> runTestArgs;
            runTestArgs.push_back(testFnArg);
            runTestArgs.push_back(testNameArg);
            runTestArgs.push_back(testPathArg);
            runTestArgs.push_back(testTagArg);

            const ABICall::PreparedCall preparedRunTest = ABICall::prepareArgs(builder, runTestFn->callConvKind(), runTestArgs);
            ABICall::callLocal(builder, runTestFn->callConvKind(), runTestFn, preparedRunTest);
        }

        const ABICall::PreparedCall preparedTestsDone = ABICall::prepareArgs(builder, testsDoneFn->callConvKind(), {});
        ABICall::callLocal(builder, testsDoneFn->callConvKind(), testsDoneFn, preparedTestsDone);
    }

    // The test command must stop after #test functions: running #main would also
    // launch the application and its side effects. Startup coverage belongs in #test.
    if (ctx.cmdLine().command != CommandKind::Test)
        emitLifecycleCalls(builder, builder_->mainFunctions);

    emitLifecycleCalls(builder, builder_->dropFunctions);

    // Startup closes the runtime through the shared runtime wrapper so setup and
    // teardown stay aligned across native entry points.
    const ABICall::PreparedCall preparedCloseRuntime = ABICall::prepareArgs(builder, closeRuntimeFn->callConvKind(), {});
    ABICall::callLocal(builder, closeRuntimeFn->callConvKind(), closeRuntimeFn, preparedCloseRuntime);
    builder.emitRet();

    if (startup->code.emit(ctx, builder) != Result::Continue)
        return builder_->reportError(DiagnosticId::cmd_err_native_test_entry_lower_failed);

    builder_->startup = std::move(startup);
    return Result::Continue;
}

SWC_END_NAMESPACE();
