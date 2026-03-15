#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Backend/JIT/JITExecManager.h"
#include "Backend/JIT/JITMemoryManager.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Main/ExternalModuleManager.h"
#include "Main/FileSystem.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Core/Timer.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Os/Os.h"
#include "Support/Report/Diagnostic.h"
#include "Support/Report/LogColor.h"
#include "Support/Report/Logger.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

bool CompilerInstance::dbgDevMode = false;

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

    bool shouldRegisterNativeFunction(const SymbolFunction& symbol)
    {
        return !symbol.isForeign() &&
               !symbol.isEmpty() &&
               !symbol.isAttribute() &&
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

    void initRuntimeContextTlsId()
    {
        g_RuntimeContextTlsId = Os::tlsAlloc();
    }

    uint64_t runtimeContextTlsId()
    {
        std::call_once(g_RuntimeContextTlsIdOnce, initRuntimeContextTlsId);
        return g_RuntimeContextTlsId;
    }

    Utf8 normalizePathForCompare(const fs::path& path)
    {
        Utf8 result{path.generic_string()};
#ifdef _WIN32
        result.make_lower();
#endif
        return result;
    }

    void collectSwagFilesRec(const CommandLine& cmdLine, const fs::path& folder, std::vector<fs::path>& files, bool canFilter = true)
    {
        std::error_code ec;
        for (fs::recursive_directory_iterator it(folder, fs::directory_options::skip_permission_denied, ec), end; it != end; it.increment(ec))
        {
            if (ec)
            {
                ec.clear();
                continue;
            }

            const fs::directory_entry& entry = *it;
            if (!entry.is_regular_file(ec))
            {
                ec.clear();
                continue;
            }

            const fs::path&   path = entry.path();
            const std::string ext  = path.extension().string();
            if (ext != ".swg" && ext != ".swgs")
                continue;

            if (canFilter && !cmdLine.fileFilter.empty())
            {
                const std::string pathString = path.string();
                bool              ignore     = false;
                for (const Utf8& filter : cmdLine.fileFilter)
                {
                    if (!pathString.contains(filter))
                    {
                        ignore = true;
                        break;
                    }
                }

                if (ignore)
                    continue;
            }

            files.push_back(path);
        }
    }

    const Runtime::CompilerMessage* runtimeCompilerGetMessage(const CompilerInstance* owner)
    {
        SWC_ASSERT(owner != nullptr);
        return &owner->runtimeCompilerMessage();
    }

    Runtime::BuildCfg* runtimeCompilerGetBuildCfg(CompilerInstance* owner)
    {
        SWC_ASSERT(owner != nullptr);
        return &owner->buildCfg();
    }

    void runtimeCompilerCompileString(const CompilerInstance* owner, Runtime::String str)
    {
        SWC_ASSERT(owner != nullptr);
        std::print("{}", std::string_view(str.ptr, str.length));
    }
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
    jitMemMgr_         = std::make_unique<JITMemoryManager>();
    jitExecMgr_        = std::make_unique<JITExecManager>();
    externalModuleMgr_ = std::make_unique<ExternalModuleManager>();
    setupRuntimeCompiler();
}

CompilerInstance::~CompilerInstance() = default;

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

void CompilerInstance::setupSema(TaskContext& ctx)
{
    typeMgr_ = std::make_unique<TypeManager>();
    typeGen_ = std::make_unique<TypeGen>();
    cstMgr_  = std::make_unique<ConstantManager>();
    idMgr_   = std::make_unique<IdentifierManager>();

    idMgr_->setup(ctx);
    typeMgr_->setup(ctx);
    cstMgr_->setup(ctx);
}

uint32_t CompilerInstance::pendingImplRegistrations() const
{
    return pendingImplRegistrations_.load(std::memory_order_relaxed);
}

void CompilerInstance::incPendingImplRegistrations()
{
    pendingImplRegistrations_.fetch_add(1, std::memory_order_relaxed);
    notifyAlive();
}

void CompilerInstance::decPendingImplRegistrations()
{
    const uint32_t prev = pendingImplRegistrations_.fetch_sub(1, std::memory_order_relaxed);
    SWC_ASSERT(prev > 0);
    notifyAlive();
}

void CompilerInstance::logBefore()
{
    const TaskContext ctx(*this);

    const Logger::ScopedLock loggerLock(ctx.global().logger());

#if SWC_DEBUG
    Logger::printHeaderCentered(ctx, LogColor::Magenta, "[Debug]", LogColor::Magenta, "ON");
#elif SWC_DEV_MODE
    Logger::printHeaderCentered(ctx, LogColor::Blue, "[DevMode]", LogColor::Blue, "ON");
#elif SWC_STATS
    Logger::printHeaderCentered(ctx, LogColor::Yellow, "[Stats]", LogColor::Yellow, "ON");
#endif

#if SWC_DEBUG || SWC_DEV_MODE
    if (ctx.cmdLine().randomize)
        Logger::printHeaderCentered(ctx, LogColor::Blue, "[Randomize]", LogColor::Blue, std::format("seed is {}", ctx.global().jobMgr().randSeed()));
#endif
}

void CompilerInstance::logAfter()
{
    const TaskContext ctx(*this);

    const Utf8               timeSrc = Utf8Helper::toNiceTime(Timer::toSeconds(Stats::get().timeTotal));
    const Logger::ScopedLock loggerLock(ctx.global().logger());
    if (Stats::get().numErrors.load() == 1)
        Logger::printAction(ctx, "Done", "1 error");
    else if (Stats::get().numErrors.load() > 1)
        Logger::printAction(ctx, "Done", std::format("{} errors", Stats::get().numErrors.load()));
    else if (Stats::get().numWarnings.load() == 1)
        Logger::printAction(ctx, "Done", std::format("{} (1 warning)", timeSrc));
    else if (Stats::get().numWarnings.load() > 1)
        Logger::printAction(ctx, "Done", std::format("{} ({} warnings)", timeSrc, Stats::get().numWarnings.load()));
    else
        Logger::printAction(ctx, "Done", timeSrc);
}

void CompilerInstance::logStats()
{
    if (!cmdLine().stats)
        return;

#if SWC_HAS_STATS
    size_t memFrontendSource          = 0;
    size_t memFrontendTokens          = 0;
    size_t memFrontendLines           = 0;
    size_t memFrontendTrivia          = 0;
    size_t memFrontendIdentifiers     = 0;
    size_t memFrontendAstReserved     = 0;
    size_t memSemaNodePayloadReserved = 0;

    {
        const std::shared_lock lock(mutex_);

        for (const std::unique_ptr<SourceFile>& file : files_)
        {
            const SourceFile* const srcFile = file.get();
            SWC_ASSERT(srcFile != nullptr);
            memFrontendSource += srcFile->content().capacity() * sizeof(char8_t);
            memFrontendAstReserved += srcFile->ast().memStorageReserved();
            memSemaNodePayloadReserved += srcFile->nodePayloadContext().memStorageReserved();
        }

        for (const std::unique_ptr<SourceView>& srcViewPtr : srcViews_)
        {
            const SourceView* const srcView = srcViewPtr.get();
            SWC_ASSERT(srcView != nullptr);
            memFrontendTokens += srcView->tokens().capacity() * sizeof(Token);
            memFrontendLines += srcView->lines().capacity() * sizeof(uint32_t);
            memFrontendTrivia += srcView->trivia().capacity() * sizeof(SourceTrivia);
            memFrontendTrivia += srcView->triviaStart().capacity() * sizeof(uint32_t);
            memFrontendIdentifiers += srcView->identifiers().capacity() * sizeof(SourceIdentifier);
        }
    }

    size_t memCompilerArenaReserved = 0;
    for (const PerThreadData& td : perThreadData_)
    {
        memCompilerArenaReserved += td.arena.reservedBytes();
    }

    const size_t memSemaConstantsReserved = cstMgr_ ? cstMgr_->memStorageReserved() : 0;
    const size_t memSemaTypesReserved     = typeMgr_ ? typeMgr_->memStorageReserved() : 0;
    const size_t memDataSegmentConstant   = constantSegment_.memStorageReserved();
    const size_t memDataSegmentGlobalZero = globalZeroSegment_.memStorageReserved();
    const size_t memDataSegmentGlobalInit = globalInitSegment_.memStorageReserved();
    const size_t memDataSegmentCompiler   = compilerSegment_.memStorageReserved();

    Stats& stats = Stats::get();
    stats.memFrontendSource.store(memFrontendSource, std::memory_order_relaxed);
    stats.memFrontendTokens.store(memFrontendTokens, std::memory_order_relaxed);
    stats.memFrontendLines.store(memFrontendLines, std::memory_order_relaxed);
    stats.memFrontendTrivia.store(memFrontendTrivia, std::memory_order_relaxed);
    stats.memFrontendIdentifiers.store(memFrontendIdentifiers, std::memory_order_relaxed);
    stats.memFrontendAstReserved.store(memFrontendAstReserved, std::memory_order_relaxed);
    stats.memSemaNodePayloadReserved.store(memSemaNodePayloadReserved, std::memory_order_relaxed);
    stats.memSemaIdentifiersReserved.store(idMgr_ ? idMgr_->memStorageReserved() : 0, std::memory_order_relaxed);
    stats.memCompilerArenaReserved.store(memCompilerArenaReserved, std::memory_order_relaxed);
    stats.memConstantsReserved.store(memSemaConstantsReserved, std::memory_order_relaxed);
    stats.memTypesReserved.store(memSemaTypesReserved, std::memory_order_relaxed);
    stats.memDataSegmentConstant.store(memDataSegmentConstant, std::memory_order_relaxed);
    stats.memDataSegmentGlobalZero.store(memDataSegmentGlobalZero, std::memory_order_relaxed);
    stats.memDataSegmentGlobalInit.store(memDataSegmentGlobalInit, std::memory_order_relaxed);
    stats.memDataSegmentCompiler.store(memDataSegmentCompiler, std::memory_order_relaxed);
#endif

    const TaskContext ctx(*this);
    Stats::get().print(ctx);
}

void CompilerInstance::processCommand()
{
    const Timer time(&Stats::get().timeTotal);
    if (cmdLine().verboseInfo)
        Command::verboseInfo(*this);

    switch (cmdLine().command)
    {
        case CommandKind::Syntax:
            Command::syntax(*this);
            break;
        case CommandKind::Sema:
            Command::sema(*this);
            break;
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
    runtimeCompiler_.obj      = this;
    runtimeCompiler_.itable   = runtimeCompilerITable_;
    runtimeCompilerITable_[0] = reinterpret_cast<void*>(&runtimeCompilerGetMessage);
    runtimeCompilerITable_[1] = reinterpret_cast<void*>(&runtimeCompilerGetBuildCfg);
    runtimeCompilerITable_[2] = reinterpret_cast<void*>(&runtimeCompilerCompileString);
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

void CompilerInstance::initPerThreadRuntimeContextForJit()
{
    PerThreadData& td              = perThreadData_[JobManager::threadIndex()];
    td.runtimeContext.runtimeFlags = Runtime::RuntimeFlags::FromCompiler;
    setRuntimeContextForCurrentThread(&td.runtimeContext);

    if (nativeRuntimeContextTlsIdOffset_ != UINT32_MAX)
    {
        uint64_t* const tlsStorage = globalZeroSegment_.ptr<uint64_t>(nativeRuntimeContextTlsIdOffset_);
        SWC_ASSERT(tlsStorage != nullptr);
        *tlsStorage = runtimeContextTlsId() + 1;
    }
}

void CompilerInstance::registerNativeCodeFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!shouldRegisterNativeFunction(*symbol))
        return;
    if (!isNativeRootFunction(*symbol))
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted = appendUnique(nativeCodeSegment_, symbol);
    }

    if (inserted)
        notifyAlive();
}

void CompilerInstance::registerNativeTestFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!shouldRegisterNativeFunction(*symbol))
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted |= appendUnique(nativeCodeSegment_, symbol);
        inserted |= appendUnique(nativeTestFunctions_, symbol);
    }

    if (inserted)
        notifyAlive();
}

void CompilerInstance::registerNativeInitFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!shouldRegisterNativeFunction(*symbol))
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted |= appendUnique(nativeCodeSegment_, symbol);
        inserted |= appendUnique(nativeInitFunctions_, symbol);
    }

    if (inserted)
        notifyAlive();
}

void CompilerInstance::registerNativePreMainFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!shouldRegisterNativeFunction(*symbol))
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted |= appendUnique(nativeCodeSegment_, symbol);
        inserted |= appendUnique(nativePreMainFunctions_, symbol);
    }

    if (inserted)
        notifyAlive();
}

void CompilerInstance::registerNativeDropFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!shouldRegisterNativeFunction(*symbol))
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted |= appendUnique(nativeCodeSegment_, symbol);
        inserted |= appendUnique(nativeDropFunctions_, symbol);
    }

    if (inserted)
        notifyAlive();
}

void CompilerInstance::registerNativeMainFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!shouldRegisterNativeFunction(*symbol))
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted |= appendUnique(nativeCodeSegment_, symbol);
        inserted |= appendUnique(nativeMainFunctions_, symbol);
    }

    if (inserted)
        notifyAlive();
}

void CompilerInstance::registerNativeGlobalVariable(SymbolVariable* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    SWC_ASSERT(symbol->isSemaCompleted());
    if (!symbol->hasGlobalStorage())
        return;
    if (symbol->globalStorageKind() == DataSegmentKind::Compiler)
        return;

    bool inserted = false;
    {
        const std::unique_lock lock(mutex_);
        inserted = appendUnique(nativeGlobalVariables_, symbol);
    }

    if (inserted)
        notifyAlive();
}

std::vector<SymbolVariable*> CompilerInstance::nativeGlobalVariablesSnapshot() const
{
    const std::shared_lock lock(mutex_);
    return nativeGlobalVariables_;
}

ExitCode CompilerInstance::run()
{
    logBefore();
    processCommand();
    logAfter();
    logStats();
    return Stats::get().numErrors.load() > 0 ? ExitCode::CompileError : ExitCode::Success;
}

SourceView& CompilerInstance::addSourceView()
{
    const std::unique_lock lock(mutex_);
    auto                   srcViewRef = static_cast<SourceViewRef>(static_cast<uint32_t>(srcViews_.size()));
    srcViews_.emplace_back(std::make_unique<SourceView>(srcViewRef, nullptr));
#if SWC_HAS_REF_DEBUG_INFO
    srcViewRef.dbgPtr = srcViews_.back().get();
#endif
    return *srcViews_.back();
}

SourceView& CompilerInstance::addSourceView(FileRef fileRef)
{
    SWC_ASSERT(fileRef.isValid());
    SWC_RACE_CONDITION_READ(rcFiles_);

    const std::unique_lock lock(mutex_);
    auto                   srcViewRef = static_cast<SourceViewRef>(static_cast<uint32_t>(srcViews_.size()));
    srcViews_.emplace_back(std::make_unique<SourceView>(srcViewRef, &file(fileRef)));
#if SWC_HAS_REF_DEBUG_INFO
    srcViewRef.dbgPtr = srcViews_.back().get();
#endif
    return *srcViews_.back();
}

SourceView& CompilerInstance::srcView(SourceViewRef ref)
{
    const std::shared_lock lock(mutex_);
    SWC_ASSERT(ref.get() < srcViews_.size());

    SourceView* const view = srcViews_[ref.get()].get();
    return *(view);
}

const SourceView& CompilerInstance::srcView(SourceViewRef ref) const
{
    const std::shared_lock lock(mutex_);
    SWC_ASSERT(ref.get() < srcViews_.size());

    const SourceView* const view = srcViews_[ref.get()].get();
    return *(view);
}

const SourceView* CompilerInstance::findSourceViewByFileName(const std::string_view fileName) const
{
    if (fileName.empty())
        return nullptr;

    const fs::path wantedPath{std::string(fileName)};
    const Utf8     wantedPathNormalized = normalizePathForCompare(wantedPath);

    const std::shared_lock lock(mutex_);
    for (const std::unique_ptr<SourceView>& srcViewPtr : srcViews_)
    {
        const SourceView* const srcView = srcViewPtr.get();
        if (!srcView)
            continue;

        const SourceFile* const sourceFile = srcView->file();
        if (!sourceFile)
            continue;

        if (normalizePathForCompare(sourceFile->path()) == wantedPathNormalized)
            return srcView;
    }

    return nullptr;
}

bool CompilerInstance::setMainFunc(AstCompilerFunc* node)
{
    const std::unique_lock lock(mutex_);
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
    const std::unique_lock lock(mutex_);
    for (const Utf8& lib : foreignLibs_)
    {
        if (lib == name)
            return false;
    }

    foreignLibs_.emplace_back(name);
    return true;
}

void CompilerInstance::registerRuntimeFunctionSymbol(const IdentifierRef idRef, SymbolFunction* symbol)
{
    SWC_ASSERT(idRef.isValid());
    SWC_ASSERT(symbol != nullptr);

    bool                   inserted = false;
    const std::unique_lock lock(mutex_);
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
    const std::shared_lock lock(mutex_);
    const auto             it = runtimeFunctionSymbols_.find(idRef);
    if (it == runtimeFunctionSymbols_.end())
        return nullptr;
    return it->second;
}

SourceFile& CompilerInstance::addFile(fs::path path, FileFlags flags)
{
    if (!path.is_absolute())
        path = fs::absolute(path);

    return addResolvedFile(std::move(path), flags);
}

SourceFile& CompilerInstance::addResolvedFile(fs::path path, FileFlags flags)
{
    SWC_RACE_CONDITION_WRITE(rcFiles_);
    SWC_ASSERT(path.is_absolute());

    auto fileRef = static_cast<FileRef>(static_cast<uint32_t>(files_.size()));
    files_.emplace_back(std::make_unique<SourceFile>(fileRef, std::move(path), flags));
    filePtrs_.push_back(files_.back().get());
#if SWC_HAS_REF_DEBUG_INFO
    fileRef.dbgPtr = files_.back().get();
#endif
    return *files_.back();
}

std::span<SourceFile* const> CompilerInstance::files() const
{
    SWC_RACE_CONDITION_READ(rcFiles_);
    return filePtrs_;
}

void CompilerInstance::appendResolvedFiles(std::vector<fs::path>& paths, FileFlags flags)
{
    if (paths.empty())
        return;

    files_.reserve(files_.size() + paths.size());
    filePtrs_.reserve(filePtrs_.size() + paths.size());
    for (fs::path& path : paths)
        addResolvedFile(std::move(path), flags);
}

void CompilerInstance::collectFolderFiles(const fs::path& folder, FileFlags flags, const bool canFilter)
{
    std::vector<fs::path> paths;
    collectSwagFilesRec(cmdLine(), folder, paths, canFilter);
    std::ranges::sort(paths);
    appendResolvedFiles(paths, flags);
}

Result CompilerInstance::collectFiles(TaskContext& ctx)
{
    const CommandLine& cmdLine = ctx.cmdLine();

    // Collect direct folders from the command line
    for (const fs::path& folder : cmdLine.directories)
        collectFolderFiles(folder, FileFlagsE::CustomSrc, true);

    // Collect direct files from the command line
    if (!cmdLine.files.empty())
    {
        files_.reserve(files_.size() + cmdLine.files.size());
        filePtrs_.reserve(filePtrs_.size() + cmdLine.files.size());
        for (const fs::path& file : cmdLine.files)
            addResolvedFile(file, FileFlagsE::CustomSrc);
    }

    // Collect files for the module
    if (!cmdLine.modulePath.empty())
    {
        modulePathFile_ = cmdLine.modulePath / "module.swg";
        SWC_RESULT(FileSystem::resolveFile(ctx, modulePathFile_));
        addResolvedFile(modulePathFile_, FileFlagsE::Module);

        modulePathSrc_ = cmdLine.modulePath / "src";
        SWC_RESULT(FileSystem::resolveFolder(ctx, modulePathSrc_));
        collectFolderFiles(modulePathSrc_, FileFlagsE::ModuleSrc, true);
    }

    // Collect runtime files
    if (cmdLine.runtime)
    {
        fs::path runtimePath = exeFullName_.parent_path() / "Runtime";
        SWC_RESULT(FileSystem::resolveFolder(ctx, runtimePath));
        collectFolderFiles(runtimePath, FileFlagsE::Runtime, false);
    }

    srcViews_.reserve(files_.size());

    if (files_.empty())
    {
        const Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_no_input);
        diag.report(ctx);
        return Result::Error;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
