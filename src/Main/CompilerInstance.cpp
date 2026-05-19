#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Backend/JIT/JIT.h"
#include "Backend/JIT/JITExecManager.h"
#include "Backend/JIT/JITMemoryManager.h"
#include "Backend/RuntimeName.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaJob.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/ExternalModuleManager.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Core/AppendOnlyLookupTable.h"
#include "Support/Core/Timer.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Memory/Heap.h"
#include "Support/Memory/mimalloc/include/mimalloc.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/Logger.h"
#include "Support/Report/ScopedTimedAction.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

bool CompilerInstance::dbgDevStop = false;

namespace
{
    uint64_t       g_RuntimeContextTlsId;
    std::once_flag g_RuntimeContextTlsIdOnce;

    template<typename T>
    bool appendUnique(std::vector<T*>& values, T* value)
    {
        if (std::ranges::find(values, value) != values.end())
            return false;

        values.push_back(value);
        return true;
    }

    bool isEligibleNativeFunction(const SymbolFunction& symbol)
    {
        return !symbol.isIgnored() &&
               !symbol.isForeign() &&
               !symbol.isEmpty() &&
               !symbol.hasUnmaterializedGenericBody() &&
               !symbol.isAttribute() &&
               !symbol.attributes().hasRtFlag(RtAttributeFlagsE::Macro) &&
               !symbol.attributes().hasRtFlag(RtAttributeFlagsE::Mixin) &&
               !symbol.attributes().hasRtFlag(RtAttributeFlagsE::Compiler);
    }

    bool isNativeRootFunction(const SymbolFunction& symbol)
    {
        const SymbolMap* owner = symbol.ownerSymMap();
        if (!owner)
            return false;

        while (owner->ownerSymMap())
            owner = owner->ownerSymMap();

        if (owner->isModule() || owner->isStruct() || owner->isInterface() || owner->isImpl())
            return true;

        return owner->isNamespace() && owner->idRef().isValid();
    }

    template<typename T>
    bool isImportedApiSource(const CompilerInstance& compiler, const T& symbol)
    {
        const SourceFile* sourceFile = compiler.sourceViewFile(symbol);
        return sourceFile && sourceFile->isImportedApi();
    }

    bool canRegisterNativeFunction(const CompilerInstance& compiler, const SymbolFunction& symbol, const bool requireRoot)
    {
        if (!isEligibleNativeFunction(symbol))
            return false;
        if (isImportedApiSource(compiler, symbol))
            return false;
        return !requireRoot || isNativeRootFunction(symbol);
    }

    bool canRegisterNativeGlobalVariable(const CompilerInstance& compiler, const SymbolVariable& symbol)
    {
        if (isImportedApiSource(compiler, symbol))
            return false;
        if (!symbol.hasGlobalStorage())
            return false;
        return symbol.globalStorageKind() != DataSegmentKind::Compiler;
    }

    template<typename T>
    bool appendUniqueBuckets(std::initializer_list<std::vector<T*>*> buckets, T* value)
    {
        bool inserted = false;
        for (std::vector<T*>* bucket : buckets)
        {
            SWC_ASSERT(bucket != nullptr);
            inserted |= appendUnique(*bucket, value);
        }

        return inserted;
    }

    template<typename T>
    bool appendUniqueStateBuckets(std::shared_mutex& mutex, std::initializer_list<std::vector<T*>*> buckets, T* value)
    {
        const std::unique_lock lock(mutex);
        return appendUniqueBuckets(buckets, value);
    }

    Utf8 buildCfgString(const Runtime::String& value)
    {
        if (!value.ptr || !value.length)
            return {};

        return Utf8{value};
    }

    bool endsWithLineBreak(const std::string_view text)
    {
        if (text.empty())
            return false;

        const char last = text.back();
        return last == '\n' || last == '\r';
    }

    uint32_t countLineBreaks(const std::string_view text)
    {
        uint32_t count = 0;
        for (size_t i = 0; i < text.size(); ++i)
        {
            if (text[i] == '\n')
            {
                count++;
                continue;
            }

            if (text[i] != '\r')
                continue;

            count++;
            if (i + 1 < text.size() && text[i + 1] == '\n')
                i++;
        }

        return count;
    }

    uint32_t effectiveSourceViewLineCount(const SourceView& srcView)
    {
        const auto& lines = srcView.lines();
        if (lines.empty())
            return 0;

        uint32_t count = static_cast<uint32_t>(lines.size());
        if (!srcView.stringView().empty() && lines.back() == srcView.stringView().size())
            count--;

        return std::max(count, 1u);
    }

    bool sourceViewContainsRuntimeLine(const SourceView& srcView, const uint32_t runtimeLine)
    {
        if (!runtimeLine)
            return false;

        const uint32_t lineCount = effectiveSourceViewLineCount(srcView);
        if (!lineCount)
            return false;

        const uint32_t firstLine = srcView.lineOffset() + 1;
        const uint32_t lastLine  = srcView.lineOffset() + lineCount;
        return runtimeLine >= firstLine && runtimeLine <= lastLine;
    }

    Utf8 generatedSourceDumpBaseName(const CompilerInstance& compiler)
    {
        Utf8 baseName = buildCfgString(compiler.buildCfg().name);
        if (baseName.empty())
            baseName = defaultArtifactName(compiler.cmdLine());

        baseName = FileSystem::sanitizeFileName(baseName);
        if (baseName.empty())
            baseName = "module";
        return baseName;
    }

    fs::path generatedSourceOutputDirectory(const CompilerInstance& compiler)
    {
        const Utf8 outDir = buildCfgString(compiler.buildCfg().outDir);
        if (!outDir.empty())
            return FileSystem::absolutePathNoThrow(fs::path(outDir.c_str()));
        if (!compiler.cmdLine().outDir.empty())
            return FileSystem::absolutePathNoThrow(compiler.cmdLine().outDir);
        if (!compiler.cmdLine().exportApiDir.empty())
            return FileSystem::absolutePathNoThrow(compiler.cmdLine().exportApiDir);

        const Utf8 workDir = buildCfgString(compiler.buildCfg().workDir);
        if (!workDir.empty())
            return FileSystem::absolutePathNoThrow(fs::path(workDir.c_str()));

        if (!compiler.cmdLine().workDir.empty())
            return FileSystem::absolutePathNoThrow(compiler.cmdLine().workDir);

        return FileSystem::absolutePathNoThrow(Os::getTemporaryPath());
    }

    fs::path generatedSourceDumpPath(const CompilerInstance& compiler, const uint32_t threadIndex)
    {
        const fs::path directory = generatedSourceOutputDirectory(compiler);
        const Utf8     baseName  = generatedSourceDumpBaseName(compiler);
        return (directory / std::format("{}-generated-source-{}.swgsrc", baseName.c_str(), threadIndex)).lexically_normal();
    }

    void initRuntimeContextTlsId()
    {
        g_RuntimeContextTlsId = Os::tlsAlloc();
    }

    uint64_t runtimeContextTlsId()
    {
        std::call_once(g_RuntimeContextTlsIdOnce, initRuntimeContextTlsId);
        return g_RuntimeContextTlsId;
    }

    void runtimeAllocatorReq(const CompilerInstance*, Runtime::AllocatorRequest* request)
    {
        if (!request)
            return;

        switch (request->mode)
        {
            case Runtime::AllocatorMode::Free:
                mi_free(request->address);
                request->address = nullptr;
                return;

            case Runtime::AllocatorMode::Alloc:
                request->address = nullptr;
                [[fallthrough]];

            case Runtime::AllocatorMode::Realloc:
            {
                if (request->size == 0)
                {
                    if (request->mode == Runtime::AllocatorMode::Realloc)
                        mi_free(request->address);
                    request->address = nullptr;
                    return;
                }

                const size_t alignment = request->alignment ? request->alignment : sizeof(void*);
                if (request->mode == Runtime::AllocatorMode::Alloc)
                {
                    request->address = alignment > sizeof(void*) ? mi_malloc_aligned(request->size, alignment) : mi_malloc(request->size);
                }
                else
                {
                    request->address = alignment > sizeof(void*) ? mi_realloc_aligned(request->address, request->size, alignment) : mi_realloc(request->address, request->size);
                }

                return;
            }

            case Runtime::AllocatorMode::FreeAll:
            case Runtime::AllocatorMode::AssertIsAllocated:
                return;

            default:
                return;
        }
    }

}

CompilerInstance::SourceViewBuffer::SourceViewBuffer(const std::string_view source)
{
    content.reserve(source.size() + TRAILING_0);
    content.resize(source.size());
    if (!source.empty())
        std::memcpy(content.data(), source.data(), source.size());

    for (uint32_t i = 0; i < TRAILING_0; ++i)
        content.push_back(0);
}

std::string_view CompilerInstance::SourceViewBuffer::view() const
{
    if (content.size() < TRAILING_0)
        return {};

    return {reinterpret_cast<const char*>(content.data()), content.size() - TRAILING_0};
}

CompilerInstance::CompilerInstance(const Global& global, const CommandLine& cmdLine) :
    cmdLine_(&cmdLine),
    global_(&global),
    buildCfg_(cmdLine.defaultBuildCfg)
{
    (void) runtimeContextTlsId();

    jobClientId_ = global.jobMgr().newClientId();
    exeFullName_ = Os::getExeFullName();

    const uint32_t numWorkers     = global.jobMgr().numWorkers();
    const uint32_t perThreadSlots = global.jobMgr().isSingleThreaded() ? 1 : numWorkers + 1;
    perThreadData_.resize(perThreadSlots);
    fileLookup_        = std::make_unique<AppendOnlyLookupTable<SourceFile>>();
    srcViewLookup_     = std::make_unique<AppendOnlyLookupTable<SourceView>>();
    jitMemMgr_         = std::make_unique<JITMemoryManager>();
    jitExecMgr_        = std::make_unique<JITExecManager>();
    externalModuleMgr_ = std::make_unique<ExternalModuleManager>();
    setupRuntimeCompiler();
}

CompilerInstance::~CompilerInstance()
{
    // SymbolFunction instances are arena-allocated, so their JITMemory destructors do not reliably
    // run during compiler teardown. Unregister prepared function tables before executable pages are
    // released or stale Windows unwind entries can survive into the next compiler instance.
    resetPreparedJitFunctions();
}

std::byte* CompilerInstance::dataSegmentAddress(const DataSegmentKind kind, const uint32_t offset)
{
    switch (kind)
    {
        case DataSegmentKind::GlobalZero:
            return globalZeroSegment_.ptr<std::byte>(offset);
        case DataSegmentKind::GlobalInit:
            return globalInitSegment_.ptr<std::byte>(offset);
        case DataSegmentKind::Compiler:
            return compilerSegment_.ptr<std::byte>(offset);
        case DataSegmentKind::Zero:
            return constantSegment_.ptr<std::byte>(offset);
    }

    SWC_UNREACHABLE();
}

const std::byte* CompilerInstance::dataSegmentAddress(const DataSegmentKind kind, const uint32_t offset) const
{
    switch (kind)
    {
        case DataSegmentKind::GlobalZero:
            return globalZeroSegment_.ptr<std::byte>(offset);
        case DataSegmentKind::GlobalInit:
            return globalInitSegment_.ptr<std::byte>(offset);
        case DataSegmentKind::Compiler:
            return compilerSegment_.ptr<std::byte>(offset);
        case DataSegmentKind::Zero:
            return constantSegment_.ptr<std::byte>(offset);
    }

    SWC_UNREACHABLE();
}

Result CompilerInstance::setupSema(TaskContext& ctx)
{
    typeMgr_ = std::make_unique<TypeManager>();
    typeGen_ = std::make_unique<TypeGen>();
    cstMgr_  = std::make_unique<ConstantManager>();
    idMgr_   = std::make_unique<IdentifierManager>();

    idMgr_->setup(ctx);
    typeMgr_->setup(ctx);
    cstMgr_->setup(ctx);
    SWC_RESULT(compilerTags_.setup(ctx));
    return Result::Continue;
}

bool CompilerInstance::tryEnqueueCodeGenJob(Sema& sema, SymbolFunction& symbolFunc, const AstNodeRef root) const
{
    if (!symbolFunc.tryMarkCodeGenJobScheduled())
        return false;

    SWC_ASSERT(root.isValid());
    auto* job = heapNew<CodeGenJob>(sema.ctx(), sema, symbolFunc, root);
    global().jobMgr().enqueue(*job, JobPriority::Normal, jobClientId());
    return true;
}

Sema* CompilerInstance::tryGetJobSema(Job* job)
{
    if (!job)
        return nullptr;
    if (auto* semaJob = job->safeCast<SemaJob>())
        return &semaJob->sema();
    if (auto* codeGenJob = job->safeCast<CodeGenJob>())
        return &codeGenJob->sema();
    return nullptr;
}

const Sema* CompilerInstance::tryGetJobSema(const Job* job)
{
    if (!job)
        return nullptr;
    if (const auto* semaJob = job->safeCast<SemaJob>())
        return &semaJob->sema();
    if (const auto* codeGenJob = job->safeCast<CodeGenJob>())
        return &codeGenJob->sema();
    return nullptr;
}

uint32_t CompilerInstance::pendingImplRegistrations(const IdentifierRef idRef) const
{
    if (!idRef.isValid())
        return 0;

    const std::scoped_lock lock(pendingImplRegistrationsMutex_);
    const auto             it = pendingImplRegistrations_.find(idRef);
    if (it == pendingImplRegistrations_.end())
        return 0;

    return it->second;
}

void CompilerInstance::incPendingImplRegistrations(const IdentifierRef idRef)
{
    SWC_ASSERT(idRef.isValid());
    const std::scoped_lock lock(pendingImplRegistrationsMutex_);
    pendingImplRegistrations_[idRef]++;
}

void CompilerInstance::decPendingImplRegistrations(const IdentifierRef idRef)
{
    SWC_ASSERT(idRef.isValid());

    bool notify = false;
    {
        const std::scoped_lock lock(pendingImplRegistrationsMutex_);
        const auto             it = pendingImplRegistrations_.find(idRef);
        SWC_ASSERT(it != pendingImplRegistrations_.end());
        SWC_ASSERT(it->second > 0);
        it->second--;
        if (!it->second)
        {
            pendingImplRegistrations_.erase(it);
            notify = true;
        }
    }

    if (notify)
        notifyAlive();
}

void CompilerInstance::logBefore()
{
    const TaskContext ctx(*this);
    ctx.global().logger().resetStageClaims();
    TimedActionLog::printSessionFlags(ctx);
}

void CompilerInstance::logAfter()
{
    const TaskContext ctx(*this);
    TimedActionLog::printSummary(ctx);
}

void CompilerInstance::logStats()
{
    if (!cmdLine().stats && !cmdLine().statsMem)
        return;

    const TaskContext ctx(*this);
    Stats::get().print(ctx);
}

void CompilerInstance::processCommand()
{
    const Timer time(&Stats::get().timeTotal);
    clearLastArtifactLabel();

    if (cmdLine().dryRun || cmdLine().showConfig)
    {
        if (cmdLine().dryRun)
            Command::dryRun(*this);
        if (cmdLine().showConfig)
            Command::showConfig(*this);
        return;
    }

    switch (cmdLine().command)
    {
        case CommandKind::Format:
            Command::format(*this);
            break;
        case CommandKind::Syntax:
            Command::syntax(*this);
            break;
        case CommandKind::Sema:
            Command::sema(*this);
            break;
        case CommandKind::Unittest:
            return;
        case CommandKind::Test:
            Command::test(*this);
            break;
        case CommandKind::Build:
            Command::build(*this);
            break;
        case CommandKind::Run:
            Command::run(*this);
            break;
        default:
            SWC_UNREACHABLE();
    }
}

void CompilerInstance::setupRuntimeCompiler()
{
    runtimeAllocator_.obj      = this;
    runtimeAllocator_.itable   = runtimeAllocatorITable_;
    runtimeAllocatorITable_[0] = nullptr;
    runtimeAllocatorITable_[1] = reinterpret_cast<void*>(&runtimeAllocatorReq);

    runtimeCompiler_.obj      = this;
    runtimeCompiler_.itable   = runtimeCompilerITable_;
    runtimeCompilerITable_[0] = nullptr;
    runtimeCompilerITable_[1] = reinterpret_cast<void*>(&CompilerInstance::runtimeCompilerGetMessage);
    runtimeCompilerITable_[2] = reinterpret_cast<void*>(&CompilerInstance::runtimeCompilerGetBuildCfg);
    runtimeCompilerITable_[3] = reinterpret_cast<void*>(&CompilerInstance::runtimeCompilerCompileString);
}

uint64_t* CompilerInstance::runtimeContextTlsIdStorage()
{
    (void) runtimeContextTlsId();
    return &g_RuntimeContextTlsId;
}

Runtime::Context* CompilerInstance::runtimeContextFromTls()
{
    return static_cast<Runtime::Context*>(Os::tlsGetValue(runtimeContextTlsId()));
}

void CompilerInstance::setRuntimeContextForCurrentThread(Runtime::Context* context)
{
    Os::tlsSetValue(runtimeContextTlsId(), context);
}

uint32_t CompilerInstance::nativeRuntimeContextTlsIdOffset()
{
    std::call_once(nativeRuntimeContextTlsIdOffsetOnce_, [this] {
        const auto [offset, storage]     = globalZeroSegment_.reserve<uint64_t>();
        nativeRuntimeContextTlsIdOffset_ = offset;
        *storage                         = runtimeContextTlsId() + 1;
    });

    SWC_ASSERT(nativeRuntimeContextTlsIdOffset_ != UINT32_MAX);
    return nativeRuntimeContextTlsIdOffset_;
}

uint32_t CompilerInstance::nativeProcessInfosOffset()
{
    std::call_once(nativeProcessInfosOffsetOnce_, [this] {
        const auto [offset, storage] = globalZeroSegment_.reserve<Runtime::ProcessInfos>();
        nativeProcessInfosOffset_    = offset;
        *storage                     = {};
    });

    SWC_ASSERT(nativeProcessInfosOffset_ != UINT32_MAX);
    return nativeProcessInfosOffset_;
}

void CompilerInstance::initPerThreadRuntimeContextForJit()
{
    PerThreadData& td              = perThreadData_[JobManager::threadIndex()];
    td.runtimeContext.runtimeFlags = Runtime::RuntimeFlags::FromCompiler;
    if (!td.runtimeContext.allocator.obj || !td.runtimeContext.allocator.itable)
        td.runtimeContext.allocator = runtimeAllocator();
    setRuntimeContextForCurrentThread(&td.runtimeContext);

    if (nativeRuntimeContextTlsIdOffset_ != UINT32_MAX)
    {
        uint64_t* tlsStorage = globalZeroSegment_.ptr<uint64_t>(nativeRuntimeContextTlsIdOffset_);
        SWC_ASSERT(tlsStorage != nullptr);
        *tlsStorage = runtimeContextTlsId() + 1;
    }
}

void CompilerInstance::registerNativeCodeFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!canRegisterNativeFunction(*this, *symbol, true))
        return;

    if (appendUniqueStateBuckets(stateMutex_, {&nativeCodeSegment_}, symbol))
        notifyAlive();
}

void CompilerInstance::registerNativeTestFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!canRegisterNativeFunction(*this, *symbol, false))
        return;

    if (appendUniqueStateBuckets(stateMutex_, {&nativeCodeSegment_, &nativeTestFunctions_}, symbol))
        notifyAlive();
}

void CompilerInstance::registerNativeInitFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!canRegisterNativeFunction(*this, *symbol, false))
        return;

    if (appendUniqueStateBuckets(stateMutex_, {&nativeCodeSegment_, &nativeInitFunctions_}, symbol))
        notifyAlive();
}

void CompilerInstance::registerNativePreMainFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!canRegisterNativeFunction(*this, *symbol, false))
        return;

    if (appendUniqueStateBuckets(stateMutex_, {&nativeCodeSegment_, &nativePreMainFunctions_}, symbol))
        notifyAlive();
}

void CompilerInstance::registerNativeDropFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!canRegisterNativeFunction(*this, *symbol, false))
        return;

    if (appendUniqueStateBuckets(stateMutex_, {&nativeCodeSegment_, &nativeDropFunctions_}, symbol))
        notifyAlive();
}

void CompilerInstance::registerNativeMainFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!canRegisterNativeFunction(*this, *symbol, false))
        return;

    if (appendUniqueStateBuckets(stateMutex_, {&nativeCodeSegment_, &nativeMainFunctions_}, symbol))
        notifyAlive();
}

void CompilerInstance::registerNativeGlobalVariable(SymbolVariable* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!canRegisterNativeGlobalVariable(*this, *symbol))
        return;

    if (appendUniqueStateBuckets(stateMutex_, {&nativeGlobalVariables_}, symbol))
    {
        if (symbol->globalStorageKind() == DataSegmentKind::GlobalInit &&
            symbol->globalFunctionInit() != nullptr)
            invalidateGlobalFunctionBindings();
        notifyAlive();
    }
}

void CompilerInstance::registerNativeGlobalFunctionInitTarget(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    if (isImportedApiSource(*this, *symbol))
        return;

    if (appendUniqueStateBuckets(stateMutex_, {&nativeGlobalFunctionInitTargets_}, symbol))
    {
        nativeGlobalFunctionInitTargetsVersion_.fetch_add(1, std::memory_order_release);
        invalidateGlobalFunctionBindings();
        notifyAlive();
    }
}

void CompilerInstance::registerPreparedJitFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);

    if (appendUniqueStateBuckets(stateMutex_, {&jitPreparedFunctions_}, symbol))
        invalidateGlobalFunctionBindings();
}

void CompilerInstance::invalidateGlobalFunctionBindings()
{
    globalFunctionBindingsVersion_.fetch_add(1, std::memory_order_release);
}

Result CompilerInstance::ensurePatchedGlobalFunctionBindings(TaskContext& ctx)
{
    const uint64_t wantedVersion = globalFunctionBindingsVersion_.load(std::memory_order_acquire);
    if (patchedGlobalFunctionBindingsVersion_.load(std::memory_order_acquire) == wantedVersion)
        return Result::Continue;

    const std::scoped_lock patchLock(globalFunctionBindingsMutex_);
    const uint64_t         lockedVersion = globalFunctionBindingsVersion_.load(std::memory_order_acquire);
    if (patchedGlobalFunctionBindingsVersion_.load(std::memory_order_relaxed) == lockedVersion)
        return Result::Continue;

    SWC_RESULT(JIT::patchGlobalFunctionVariables(ctx));
    if (globalFunctionBindingsVersion_.load(std::memory_order_acquire) == lockedVersion)
        patchedGlobalFunctionBindingsVersion_.store(lockedVersion, std::memory_order_release);

    return Result::Continue;
}

void CompilerInstance::resetPreparedJitFunctions()
{
    std::vector<SymbolFunction*> preparedFunctions;
    {
        const std::unique_lock lock(stateMutex_);
        preparedFunctions.swap(jitPreparedFunctions_);
    }

    for (SymbolFunction* function : preparedFunctions)
    {
        if (function)
            function->resetJitState();
    }
}

std::vector<SymbolFunction*> CompilerInstance::nativeGlobalFunctionInitTargetsSnapshot() const
{
    const std::shared_lock lock(stateMutex_);
    return nativeGlobalFunctionInitTargets_;
}

std::vector<SymbolVariable*> CompilerInstance::nativeGlobalVariablesSnapshot() const
{
    const std::shared_lock lock(stateMutex_);
    return nativeGlobalVariables_;
}

std::vector<SymbolFunction*> CompilerInstance::jitPreparedFunctionsSnapshot() const
{
    const std::shared_lock lock(stateMutex_);
    return jitPreparedFunctions_;
}

ExitCode CompilerInstance::run()
{
    Stats::resetCommandMetrics();
    logBefore();
    const auto runStart = std::chrono::steady_clock::now();
    ExitCode   exitCode;
    if (!cmdLine().workspacePath.empty())
        exitCode = runWorkspace();
    else
    {
        processCommand();
        if (!cmdLine().dryRun && !cmdLine().showConfig)
        {
            TaskContext ctx(*this);
            (void) flushGeneratedSourceDumps(ctx);
        }

        exitCode = Stats::getNumErrors() > 0 ? ExitCode::CompileError : ExitCode::Success;
    }
    commandWallTimeNs_ = std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now() - runStart).count();
    logAfter();
    logStats();
    return exitCode;
}

SourceView& CompilerInstance::addSourceView()
{
    const std::unique_lock lock(sourceStorageMutex_);
    SWC_ASSERT(srcViews_.size() == srcViewLookup_->size());
    auto srcViewRef = SourceViewRef(srcViewLookup_->size());
    srcViews_.emplace_back(std::make_unique<SourceView>(srcViewRef, nullptr));
    srcViewLookup_->pushBack(srcViews_.back().get());
#if SWC_HAS_REF_DEBUG_INFO
    srcViewRef.dbgPtr = srcViews_.back().get();
#endif
    return *srcViews_.back();
}

SourceView& CompilerInstance::addSourceView(FileRef fileRef)
{
    SWC_ASSERT(fileRef.isValid());

    const std::unique_lock lock(sourceStorageMutex_);
    SWC_ASSERT(srcViews_.size() == srcViewLookup_->size());
    auto        srcViewRef = SourceViewRef(srcViewLookup_->size());
    SourceFile* ownerFile  = fileLookup_->at(fileRef.get());
    srcViews_.emplace_back(std::make_unique<SourceView>(srcViewRef, ownerFile));
    srcViewLookup_->pushBack(srcViews_.back().get());
#if SWC_HAS_REF_DEBUG_INFO
    srcViewRef.dbgPtr = srcViews_.back().get();
#endif
    return *srcViews_.back();
}

SourceView& CompilerInstance::addBufferedSourceView(const FileRef fileRef, const std::string_view content)
{
    SWC_ASSERT(fileRef.isValid());

    const std::unique_lock lock(sourceStorageMutex_);
    SWC_ASSERT(srcViews_.size() == srcViewLookup_->size());

    auto        srcViewRef = SourceViewRef(srcViewLookup_->size());
    SourceFile* ownerFile  = fileLookup_->at(fileRef.get());
    auto        buffer     = std::make_unique<SourceViewBuffer>(content);
    auto        sourceView = std::make_unique<SourceView>(srcViewRef, ownerFile, buffer->view());

    srcViewBuffers_.push_back(std::move(buffer));
    srcViews_.push_back(std::move(sourceView));
    srcViewLookup_->pushBack(srcViews_.back().get());
#if SWC_HAS_REF_DEBUG_INFO
    srcViewRef.dbgPtr = srcViews_.back().get();
#endif
    return *srcViews_.back();
}

SourceView& CompilerInstance::srcView(SourceViewRef ref)
{
    SWC_ASSERT(ref.isValid());
    return *srcViewLookup_->at(ref.get());
}

const SourceView& CompilerInstance::srcView(SourceViewRef ref) const
{
    SWC_ASSERT(ref.isValid());
    return *srcViewLookup_->at(ref.get());
}

const SourceFile* CompilerInstance::ownerSourceFile(SourceViewRef ref) const
{
    if (!ref.isValid())
        return nullptr;

    return ownerSourceFile(srcView(ref));
}

const SourceFile* CompilerInstance::ownerSourceFile(const SourceView& srcView) const
{
    if (!srcView.ownerFileRef().isValid())
        return nullptr;

    return &file(srcView.ownerFileRef());
}

const SourceFile* CompilerInstance::sourceViewFile(SourceViewRef ref) const
{
    if (!ref.isValid())
        return nullptr;

    return srcView(ref).file();
}

const SourceFile* CompilerInstance::sourceViewFile(const Symbol& symbol) const
{
    return sourceViewFile(symbol.srcViewRef());
}

const SourceFile* CompilerInstance::owningSourceFile(const SourceView& srcView) const
{
    if (srcView.ownerFileRef().isValid())
        return &file(srcView.ownerFileRef());
    if (srcView.fileRef().isValid())
        return &file(srcView.fileRef());
    return srcView.file();
}

const SourceFile* CompilerInstance::owningSourceFile(const SourceView* srcView) const
{
    if (!srcView)
        return nullptr;

    return owningSourceFile(*srcView);
}

bool CompilerInstance::tryTokenCodeRange(const TaskContext& ctx, SourceCodeRange& outCodeRange, const SourceCodeRef& codeRef) const
{
    outCodeRange = {};
    if (!codeRef.isValid() || !codeRef.srcViewRef.isValid())
        return false;
    if (codeRef.srcViewRef.get() >= srcViewLookup_->size())
        return false;

    const SourceView& sourceView = srcView(codeRef.srcViewRef);
    if (!codeRef.tokRef.isValid() || codeRef.tokRef.get() >= sourceView.numTokens())
        return false;

    outCodeRange = sourceView.tokenCodeRange(ctx, codeRef.tokRef);
    return outCodeRange.srcView != nullptr && outCodeRange.len != 0;
}

bool CompilerInstance::tryResolveSourceLocation(const TaskContext& ctx, ResolvedSourceLocation& outResolvedLocation, const SourceCodeRef& codeRef) const
{
    outResolvedLocation = {};
    if (!tryTokenCodeRange(ctx, outResolvedLocation.codeRange, codeRef))
        return false;

    outResolvedLocation.sourceFile = sourceViewFile(outResolvedLocation.codeRange.srcView->ref());
    return true;
}

bool CompilerInstance::tryResolveSourceLocation(const TaskContext& ctx, ResolvedSourceLocation& outResolvedLocation, const Runtime::SourceCodeLocation& location) const
{
    outResolvedLocation = {};
    const SourceView* srcView = findSourceViewByLocation(location);
    if (!srcView)
        return false;

    srcView->codeRangeFromRuntimeLocation(ctx, location, outResolvedLocation.codeRange);
    if (!outResolvedLocation.codeRange.srcView || !outResolvedLocation.codeRange.len)
        return false;

    outResolvedLocation.sourceFile = sourceViewFile(srcView->ref());
    return true;
}

const SourceView* CompilerInstance::findSourceViewByLocation(const Runtime::SourceCodeLocation& location) const
{
    const auto locationFileName = std::string_view{location.fileName.ptr, static_cast<size_t>(location.fileName.length)};
    if (locationFileName.empty())
        return nullptr;

    const fs::path wantedPath{std::string(locationFileName)};
    const Utf8     wantedPathNormalized = Utf8Helper::normalizePathForCompare(wantedPath);

    const SourceView* firstPathMatch      = nullptr;
    const SourceView* lineStartMatch      = nullptr;
    const SourceView* lineEndMatch        = nullptr;
    const uint32_t    requestedStartLine  = location.lineStart ? location.lineStart : 1;
    const uint32_t    requestedEndLine    = location.lineEnd ? location.lineEnd : requestedStartLine;
    const uint32_t    numSourceViews      = srcViewLookup_->size();

    for (uint32_t i = 0; i < numSourceViews; ++i)
    {
        const SourceView* srcView    = srcViewLookup_->at(i);
        const SourceFile* sourceFile = srcView->file();
        if (!sourceFile)
            continue;

        if (Utf8Helper::normalizePathForCompare(sourceFile->path()) != wantedPathNormalized)
            continue;

        if (!firstPathMatch)
            firstPathMatch = srcView;

        if (sourceViewContainsRuntimeLine(*srcView, requestedStartLine))
        {
            if (!lineStartMatch || srcView->lineOffset() > lineStartMatch->lineOffset())
                lineStartMatch = srcView;
            continue;
        }

        if (sourceViewContainsRuntimeLine(*srcView, requestedEndLine))
        {
            if (!lineEndMatch || srcView->lineOffset() > lineEndMatch->lineOffset())
                lineEndMatch = srcView;
        }
    }

    if (lineStartMatch)
        return lineStartMatch;
    if (lineEndMatch)
        return lineEndMatch;
    return firstPathMatch;
}

const SourceView* CompilerInstance::findSourceViewByFileName(const std::string_view fileName) const
{
    if (fileName.empty())
        return nullptr;

    const fs::path wantedPath{std::string(fileName)};
    const Utf8     wantedPathNormalized = Utf8Helper::normalizePathForCompare(wantedPath);

    const uint32_t numSourceViews = srcViewLookup_->size();
    for (uint32_t i = 0; i < numSourceViews; ++i)
    {
        const SourceView* srcView    = srcViewLookup_->at(i);
        const SourceFile* sourceFile = srcView->file();
        if (!sourceFile)
            continue;

        if (Utf8Helper::normalizePathForCompare(sourceFile->path()) == wantedPathNormalized)
            return srcView;
    }

    return nullptr;
}

bool CompilerInstance::setMainFunc(AstCompilerFunc* node)
{
    const std::unique_lock lock(stateMutex_);
    if (mainFunc_)
        return false;
    mainFunc_ = node;
    return true;
}

bool CompilerInstance::markNativeOutputsCleared()
{
    return !nativeOutputsCleared_.exchange(true, std::memory_order_acq_rel);
}

bool CompilerInstance::registerForeignLib(std::string_view name)
{
    const std::unique_lock lock(stateMutex_);
    for (const Utf8& lib : foreignLibs_)
    {
        if (lib == name)
            return false;
    }

    foreignLibs_.emplace_back(name);
    return true;
}

const CompilerTag* CompilerInstance::findCompilerTag(const std::string_view name) const
{
    return compilerTags_.find(name);
}

void CompilerInstance::registerRuntimeFunctionSymbol(const IdentifierRef idRef, SymbolFunction* symbol)
{
    SWC_ASSERT(idRef.isValid());
    SWC_ASSERT(symbol != nullptr);

    bool                   inserted = false;
    const std::unique_lock lock(stateMutex_);
    const auto             it = runtimeFunctionSymbols_.find(idRef);
    if (it == runtimeFunctionSymbols_.end())
    {
        runtimeFunctionSymbols_.emplace(idRef, symbol);
        inserted = true;
    }
    else if (it->second == nullptr)
    {
        it->second = symbol;
        inserted   = true;
    }

    if (inserted)
        notifyAlive();
}

SymbolFunction* CompilerInstance::runtimeFunctionSymbol(const IdentifierRef idRef) const
{
    const std::shared_lock lock(stateMutex_);
    const auto             it = runtimeFunctionSymbols_.find(idRef);
    if (it == runtimeFunctionSymbols_.end())
        return nullptr;
    return it->second;
}

bool CompilerInstance::tryRegisterReportedDiagnostic(const std::string_view message)
{
    const std::scoped_lock lock(reportedDiagnosticsMutex_);
    Utf8                   messageUtf8(message);
    return reportedDiagnostics_.insert(std::move(messageUtf8)).second;
}

Result CompilerInstance::appendGeneratedSource(GeneratedSourceAppendResult& outResult, Utf8& outBecause, const std::string_view sectionText, const uint32_t codeOffsetInSection)
{
    outResult = {};
    outBecause.clear();

    SWC_ASSERT(codeOffsetInSection <= sectionText.size());

    const auto threadIndex = static_cast<uint32_t>(JobManager::threadIndex());
    auto&      generated   = perThreadData_[threadIndex].generatedSource;
    if (generated.path.empty())
        generated.path = generatedSourceDumpPath(*this, threadIndex);

    outResult.path            = generated.path;
    outResult.codeStartOffset = codeOffsetInSection;
    outResult.lineOffset      = generated.nextLineOffset;
    outResult.snapshot        = sectionText;
    if (!outResult.snapshot.empty() && !endsWithLineBreak(outResult.snapshot.view()))
        outResult.snapshot += "\n";

    if (!outResult.snapshot.empty())
    {
        generated.content += outResult.snapshot;
        generated.nextLineOffset += countLineBreaks(outResult.snapshot.view());
        generated.dirty = true;
    }

    return Result::Continue;
}

Result CompilerInstance::flushGeneratedSourceDumps(TaskContext& ctx)
{
    for (PerThreadData& td : perThreadData_)
    {
        auto& generated = td.generatedSource;
        if (!generated.dirty || generated.path.empty())
            continue;

        std::error_code ec;
        fs::create_directories(generated.path.parent_path(), ec);
        if (ec)
        {
            Diagnostic diag = Diagnostic::get(DiagnosticId::sema_err_ast_file_write_failed);
            diag.addArgument(Diagnostic::ARG_PATH, Utf8(generated.path));
            diag.addArgument(Diagnostic::ARG_BECAUSE, FileSystem::normalizeSystemMessage(ec));
            diag.report(ctx);
            return Result::Error;
        }

        std::ofstream generatedStream(generated.path, std::ios::binary | std::ios::trunc);
        if (!generatedStream.is_open())
        {
            Utf8 because = Os::systemError();
            if (because.empty())
                because = FileSystem::describeIoProblem(FileSystem::IoProblem::OpenWrite);
            else
                because = FileSystem::normalizeSystemMessage(because);

            Diagnostic diag = Diagnostic::get(DiagnosticId::sema_err_ast_file_write_failed);
            diag.addArgument(Diagnostic::ARG_PATH, Utf8(generated.path));
            diag.addArgument(Diagnostic::ARG_BECAUSE, because);
            diag.report(ctx);
            return Result::Error;
        }

        if (!generated.content.empty())
            generatedStream.write(generated.content.data(), static_cast<std::streamsize>(generated.content.size()));

        if (!generatedStream)
        {
            Utf8 because = Os::systemError();
            if (because.empty())
                because = FileSystem::describeIoProblem(FileSystem::IoProblem::Write);
            else
                because = FileSystem::normalizeSystemMessage(because);

            Diagnostic diag = Diagnostic::get(DiagnosticId::sema_err_ast_file_write_failed);
            diag.addArgument(Diagnostic::ARG_PATH, Utf8(generated.path));
            diag.addArgument(Diagnostic::ARG_BECAUSE, because);
            diag.report(ctx);
            return Result::Error;
        }

        generatedStream.close();
        if (!generatedStream)
        {
            Utf8 because = Os::systemError();
            if (because.empty())
                because = FileSystem::describeIoProblem(FileSystem::IoProblem::CloseWrite);
            else
                because = FileSystem::normalizeSystemMessage(because);

            Diagnostic diag = Diagnostic::get(DiagnosticId::sema_err_ast_file_write_failed);
            diag.addArgument(Diagnostic::ARG_PATH, Utf8(generated.path));
            diag.addArgument(Diagnostic::ARG_BECAUSE, because);
            diag.report(ctx);
            return Result::Error;
        }

        generated.dirty = false;
    }

    return Result::Continue;
}

void CompilerInstance::registerInMemoryFile(fs::path path, const std::string_view content)
{
    if (!path.is_absolute())
        path = fs::absolute(path);

    path = path.lexically_normal();

    const std::unique_lock lock(sourceStorageMutex_);
    inMemoryFiles_[Utf8Helper::normalizePathForCompare(path)] = Utf8(content);
}

SourceFile& CompilerInstance::addFile(fs::path path, FileFlags flags)
{
    if (!path.is_absolute())
        path = fs::absolute(path);

    return addResolvedFile(path.lexically_normal(), flags);
}

SourceFile& CompilerInstance::addLoadedFile(fs::path path, FileFlags flags, const std::string_view content)
{
    if (!path.is_absolute())
        path = fs::absolute(path);

    return addResolvedLoadedFile(path.lexically_normal(), flags, content);
}

SourceFile& CompilerInstance::file(const FileRef ref) const
{
    SWC_ASSERT(ref.isValid());
    SourceFile* file = fileLookup_->at(ref.get());
    SWC_ASSERT(file != nullptr);
    return *file;
}

std::vector<SourceFile*> CompilerInstance::filesSnapshot() const
{
    return files();
}

SourceFile& CompilerInstance::addResolvedFile(fs::path path, FileFlags flags)
{
    const std::unique_lock lock(sourceStorageMutex_);
    SWC_RACE_CONDITION_WRITE(rcFiles_);
    SWC_ASSERT(path.is_absolute());
    path = path.lexically_normal();

    SWC_ASSERT(files_.size() == fileLookup_->size());
    auto fileRef = FileRef(fileLookup_->size());
    files_.emplace_back(std::make_unique<SourceFile>(fileRef, std::move(path), flags));
    fileLookup_->pushBack(files_.back().get());
#if SWC_HAS_REF_DEBUG_INFO
    fileRef.dbgPtr = files_.back().get();
#endif

    const Utf8 key = Utf8Helper::normalizePathForCompare(files_.back()->path());
    const auto it  = inMemoryFiles_.find(key);
    if (it != inMemoryFiles_.end())
        files_.back()->setContent(it->second.view());

    return *files_.back();
}

SourceFile& CompilerInstance::addResolvedLoadedFile(fs::path path, FileFlags flags, const std::string_view content)
{
    const std::unique_lock lock(sourceStorageMutex_);
    SWC_RACE_CONDITION_WRITE(rcFiles_);
    SWC_ASSERT(path.is_absolute());
    path = path.lexically_normal();

    SWC_ASSERT(files_.size() == fileLookup_->size());
    auto sourceFileRef = FileRef(fileLookup_->size());
    auto sourceFile    = std::make_unique<SourceFile>(sourceFileRef, std::move(path), flags);
    sourceFile->setContent(content);

    SWC_ASSERT(srcViews_.size() == srcViewLookup_->size());
    auto sourceViewRef = SourceViewRef(srcViewLookup_->size());
    auto sourceView    = std::make_unique<SourceView>(sourceViewRef, sourceFile.get());
    sourceFile->ast().setSourceView(*sourceView);

    files_.push_back(std::move(sourceFile));
    fileLookup_->pushBack(files_.back().get());
    srcViews_.push_back(std::move(sourceView));
    srcViewLookup_->pushBack(srcViews_.back().get());
#if SWC_HAS_REF_DEBUG_INFO
    sourceFileRef.dbgPtr = files_.back().get();
    sourceViewRef.dbgPtr = srcViews_.back().get();
#endif
    return *files_.back();
}

std::vector<SourceFile*> CompilerInstance::files() const
{
    std::vector<SourceFile*> result;
    const uint32_t           numFiles = fileLookup_->size();
    result.reserve(numFiles);
    for (uint32_t i = 0; i < numFiles; ++i)
        result.push_back(fileLookup_->at(i));
    return result;
}

bool CompilerInstance::hasResolvedFilePath(const fs::path& path) const
{
    const Utf8 wantedPathNormalized = Utf8Helper::normalizePathForCompare(path);

    const uint32_t numFiles = fileLookup_->size();
    for (uint32_t i = 0; i < numFiles; ++i)
    {
        const SourceFile* file = fileLookup_->at(i);
        if (Utf8Helper::normalizePathForCompare(file->path()) == wantedPathNormalized)
            return true;
    }

    return false;
}

SWC_END_NAMESPACE();
