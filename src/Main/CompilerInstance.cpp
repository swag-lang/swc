#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Backend/JIT/JITExecManager.h"
#include "Backend/JIT/JITMemoryManager.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/Command.h"
#include "Main/CommandLine.h"
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
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE();

bool CompilerInstance::dbgDevMode = false;

namespace
{
    uint64_t       g_RuntimeContextTlsId;
    std::once_flag g_RuntimeContextTlsIdOnce;

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

    void applyPredefinedBuildCfg(Runtime::BuildCfg& buildCfg, const CommandLine& cmdLine)
    {
        const std::string_view cfgName = cmdLine.buildCfg;

        if (cfgName == "fast-compile")
        {
            buildCfg.safetyGuards      = Runtime::SafetyWhat::None;
            buildCfg.sanity            = false;
            buildCfg.errorStackTrace   = false;
            buildCfg.debugAllocator    = true;
            buildCfg.backend.optimize  = false;
            buildCfg.backend.debugInfo = false;
        }
        else if (cfgName == "debug")
        {
            buildCfg.safetyGuards      = Runtime::SafetyWhat::All;
            buildCfg.sanity            = true;
            buildCfg.errorStackTrace   = true;
            buildCfg.debugAllocator    = true;
            buildCfg.backend.optimize  = false;
            buildCfg.backend.debugInfo = true;
        }
        else if (cfgName == "fast-debug")
        {
            buildCfg.safetyGuards      = Runtime::SafetyWhat::All;
            buildCfg.sanity            = true;
            buildCfg.errorStackTrace   = true;
            buildCfg.debugAllocator    = true;
            buildCfg.backend.optimize  = true;
            buildCfg.backend.debugInfo = true;
        }
        else if (cfgName == "release")
        {
            buildCfg.safetyGuards               = Runtime::SafetyWhat::None;
            buildCfg.sanity                     = false;
            buildCfg.errorStackTrace            = false;
            buildCfg.debugAllocator             = false;
            buildCfg.backend.optimize           = true;
            buildCfg.backend.debugInfo          = true;
            buildCfg.backend.fpMathFma          = true;
            buildCfg.backend.fpMathNoNaN        = true;
            buildCfg.backend.fpMathNoInf        = true;
            buildCfg.backend.fpMathNoSignedZero = true;
        }
        else
        {
            buildCfg.safetyGuards      = Runtime::SafetyWhat::All;
            buildCfg.sanity            = true;
            buildCfg.errorStackTrace   = true;
            buildCfg.debugAllocator    = true;
            buildCfg.backend.optimize  = true;
            buildCfg.backend.debugInfo = true;
        }

        if (cmdLine.backendOptimize.has_value())
            buildCfg.backend.optimize = cmdLine.backendOptimize.value();

        if (cmdLine.backendKindName == "exe")
            buildCfg.backendKind = Runtime::BuildCfgBackendKind::Executable;
        else if (cmdLine.backendKindName == "dll")
            buildCfg.backendKind = Runtime::BuildCfgBackendKind::Library;
        else if (cmdLine.backendKindName == "lib")
            buildCfg.backendKind = Runtime::BuildCfgBackendKind::Export;

        if (cmdLine.verify)
        {
            buildCfg.backend.debugInfo        = true;
            buildCfg.backend.enableExceptions = true;
        }
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
    global_(&global)
{
    (void) runtimeContextTlsId();
    applyPredefinedBuildCfg(buildCfg_, cmdLine);

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
    switch (cmdLine().command)
    {
        case CommandKind::Info:
            Command::info(*this);
            break;
        case CommandKind::Syntax:
            Command::syntax(*this);
            break;
        case CommandKind::Sema:
            Command::sema(*this);
            break;
        case CommandKind::Test:
            Command::test(*this);
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

void CompilerInstance::initPerThreadRuntimeContextForJit()
{
    PerThreadData& td              = perThreadData_[JobManager::threadIndex()];
    td.runtimeContext.runtimeFlags = Runtime::RuntimeFlags::FromCompiler;
    setRuntimeContextForCurrentThread(&td.runtimeContext);
}

void CompilerInstance::resetNativeCodeSegment()
{
    nativeCodeSegment_.clear();
    nativeTestFunctions_.clear();
    nativeInitFunctions_.clear();
    nativePreMainFunctions_.clear();
    nativeDropFunctions_.clear();
    nativeMainFunctions_.clear();
}

void CompilerInstance::addNativeCodeFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    nativeCodeSegment_.push_back(symbol);
}

void CompilerInstance::addNativeTestFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    nativeTestFunctions_.push_back(symbol);
}

void CompilerInstance::addNativeInitFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    nativeInitFunctions_.push_back(symbol);
}

void CompilerInstance::addNativePreMainFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    nativePreMainFunctions_.push_back(symbol);
}

void CompilerInstance::addNativeDropFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    nativeDropFunctions_.push_back(symbol);
}

void CompilerInstance::addNativeMainFunction(SymbolFunction* symbol)
{
    SWC_ASSERT(symbol != nullptr);
    nativeMainFunctions_.push_back(symbol);
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
    SWC_RACE_CONDITION_WRITE(rcFiles_);
    if (!path.is_absolute())
        path = fs::absolute(path);

    auto fileRef = static_cast<FileRef>(static_cast<uint32_t>(files_.size()));
    files_.emplace_back(std::make_unique<SourceFile>(fileRef, std::move(path), flags));
#if SWC_HAS_REF_DEBUG_INFO
    fileRef.dbgPtr = files_.back().get();
#endif
    return *files_.back();
}

std::vector<SourceFile*> CompilerInstance::files() const
{
    SWC_RACE_CONDITION_READ(rcFiles_);
    std::vector<SourceFile*> result;
    result.reserve(files_.size());
    for (const std::unique_ptr<SourceFile>& f : files_)
        result.push_back(f.get());
    return result;
}

Result CompilerInstance::collectFiles(TaskContext& ctx)
{
    const CommandLine&    cmdLine = ctx.cmdLine();
    std::vector<fs::path> paths;

    // Collect direct folders from the command line
    for (const fs::path& folder : cmdLine.directories)
    {
        paths.clear();
        collectSwagFilesRec(cmdLine, folder, paths);
        if (cmdLine.numCores == 1)
            std::ranges::sort(paths);
        for (const fs::path& f : paths)
            addFile(f, FileFlagsE::CustomSrc);
    }

    // Collect direct files from the command line
    paths.clear();
    for (const fs::path& file : cmdLine.files)
        paths.push_back(file);
    if (cmdLine.numCores == 1)
        std::ranges::sort(paths);
    for (const fs::path& f : paths)
        addFile(f, FileFlagsE::CustomSrc);

    // Collect files for the module
    if (!cmdLine.modulePath.empty())
    {
        modulePathFile_ = cmdLine.modulePath / "module.swg";
        SWC_RESULT_VERIFY(FileSystem::resolveFile(ctx, modulePathFile_));
        addFile(modulePathFile_, FileFlagsE::Module);

        modulePathSrc_ = cmdLine.modulePath / "src";
        SWC_RESULT_VERIFY(FileSystem::resolveFolder(ctx, modulePathSrc_));
        paths.clear();
        collectSwagFilesRec(cmdLine, modulePathSrc_, paths);
        if (cmdLine.numCores == 1)
            std::ranges::sort(paths);
        for (const fs::path& f : paths)
            addFile(f, FileFlagsE::ModuleSrc);
    }

    // Collect runtime files
    if (cmdLine.runtime)
    {
        fs::path runtimePath = exeFullName_.parent_path() / "Runtime";
        SWC_RESULT_VERIFY(FileSystem::resolveFolder(ctx, runtimePath));
        paths.clear();
        collectSwagFilesRec(cmdLine, runtimePath, paths, false);
        if (cmdLine.numCores == 1)
            std::ranges::sort(paths);
        for (const fs::path& f : paths)
            addFile(f, FileFlagsE::Runtime);
    }

    if (files_.empty())
    {
        const Diagnostic diag = Diagnostic::get(DiagnosticId::cmd_err_no_input);
        diag.report(ctx);
        return Result::Error;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
