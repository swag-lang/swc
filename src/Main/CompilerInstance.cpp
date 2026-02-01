#include "pch.h"
#include "Main/CompilerInstance.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/Command.h"
#include "Main/CommandLine.h"
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

CompilerInstance::CompilerInstance(const Global& global, const CommandLine& cmdLine) :
    cmdLine_(&cmdLine),
    global_(&global)
{
    jobClientId_ = global.jobMgr().newClientId();
    exeFullName_ = Os::getExeFullName();

    const auto numWorkers = global.jobMgr().isSingleThreaded() ? 1 : global.jobMgr().numWorkers();
    perThreadData_.resize(numWorkers);
}

CompilerInstance::~CompilerInstance() = default;

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
    const auto prev = pendingImplRegistrations_.fetch_sub(1, std::memory_order_relaxed);
    SWC_ASSERT(prev > 0);
    notifyAlive();
}

void CompilerInstance::logBefore()
{
    const TaskContext ctx(*this);

    ctx.global().logger().lock();

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

    ctx.global().logger().unlock();
}

void CompilerInstance::logAfter()
{
    const TaskContext ctx(*this);

    const auto timeSrc = Utf8Helper::toNiceTime(Timer::toSeconds(Stats::get().timeTotal));
    ctx.global().logger().lock();
    if (Stats::get().numErrors.load() == 1)
        Logger::printHeaderCentered(ctx, LogColor::Green, "Done", LogColor::BrightRed, "1 error");
    else if (Stats::get().numErrors.load() > 1)
        Logger::printHeaderCentered(ctx, LogColor::Green, "Done", LogColor::BrightRed, std::format("{} errors", Stats::get().numErrors.load()));
    else if (Stats::get().numWarnings.load() == 1)
        Logger::printHeaderCentered(ctx, LogColor::Green, "Done", LogColor::Magenta, std::format("{} (1 warning)", timeSrc));
    else if (Stats::get().numWarnings.load() > 1)
        Logger::printHeaderCentered(ctx, LogColor::Green, "Done", LogColor::Magenta, std::format("{} ({} warnings)", timeSrc, Stats::get().numWarnings.load()));
    else
        Logger::printHeaderCentered(ctx, LogColor::Green, "Done", LogColor::White, timeSrc);
    ctx.global().logger().unlock();
}

void CompilerInstance::logStats()
{
    if (cmdLine().stats)
    {
        const TaskContext ctx(*this);
        Stats::get().print(ctx);
    }
}

void CompilerInstance::processCommand()
{
    Timer time(&Stats::get().timeTotal);
    switch (cmdLine().command)
    {
        case CommandKind::Syntax:
            Command::syntax(*this);
            break;
        case CommandKind::Sema:
            Command::sema(*this);
            break;
        default:
            SWC_UNREACHABLE();
    }
}

ExitCode CompilerInstance::run()
{
    logBefore();
    processCommand();
    logAfter();
    logStats();
    return ExitCode::Success;
}

SourceView& CompilerInstance::addSourceView()
{
    std::unique_lock lock(mutex_);
    auto             srcViewRef = static_cast<SourceViewRef>(static_cast<uint32_t>(srcViews_.size()));
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

    std::unique_lock lock(mutex_);
    auto             srcViewRef = static_cast<SourceViewRef>(static_cast<uint32_t>(srcViews_.size()));
    srcViews_.emplace_back(std::make_unique<SourceView>(srcViewRef, &file(fileRef)));
#if SWC_HAS_REF_DEBUG_INFO
    srcViewRef.dbgPtr = srcViews_.back().get();
#endif
    return *srcViews_.back();
}

bool CompilerInstance::setMainFunc(AstCompilerFunc* node)
{
    std::unique_lock lock(mutex_);
    if (mainFunc_)
        return false;
    mainFunc_ = node;
    return true;
}

SourceFile& CompilerInstance::addFile(fs::path path, FileFlags flags)
{
    SWC_RACE_CONDITION_WRITE(rcFiles_);
    path         = fs::absolute(path);
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
    for (const auto& f : files_)
        result.push_back(f.get());
    return result;
}

Result CompilerInstance::collectFiles(TaskContext& ctx)
{
    const auto&           cmdLine = ctx.cmdLine();
    std::vector<fs::path> paths;

    // Collect direct folders from the command line
    paths.clear();
    for (const auto& folder : cmdLine.directories)
    {
        FileSystem::collectSwagFilesRec(ctx, folder, paths);
        if (cmdLine.numCores == 1)
            std::ranges::sort(paths);
        for (const auto& f : paths)
            addFile(f, FileFlagsE::CustomSrc);
    }

    // Collect direct files from the command line
    paths.clear();
    for (const auto& file : cmdLine.files)
        paths.push_back(file);
    if (cmdLine.numCores == 1)
        std::ranges::sort(paths);
    for (const auto& f : paths)
        addFile(f, FileFlagsE::CustomSrc);

    // Collect files for the module
    if (!cmdLine.modulePath.empty())
    {
        modulePathFile_ = cmdLine.modulePath / "module.swg";
        RESULT_VERIFY(FileSystem::resolveFile(ctx, modulePathFile_));
        addFile(modulePathFile_, FileFlagsE::Module);

        modulePathSrc_ = cmdLine.modulePath / "src";
        RESULT_VERIFY(FileSystem::resolveFolder(ctx, modulePathSrc_));
        FileSystem::collectSwagFilesRec(ctx, modulePathSrc_, paths);
        if (cmdLine.numCores == 1)
            std::ranges::sort(paths);
        for (const auto& f : paths)
            addFile(f, FileFlagsE::ModuleSrc);
    }

    // Collect runtime files
    if (cmdLine.runtime)
    {
        fs::path runtimePath = exeFullName_.parent_path() / "Runtime";
        RESULT_VERIFY(FileSystem::resolveFolder(ctx, runtimePath));
        FileSystem::collectSwagFilesRec(ctx, runtimePath, paths, false);
        if (cmdLine.numCores == 1)
            std::ranges::sort(paths);
        for (const auto& f : paths)
            addFile(f, FileFlagsE::Runtime);
    }

    if (files_.empty())
    {
        const auto diag = Diagnostic::get(DiagnosticId::cmd_err_no_input);
        diag.report(ctx);
        return Result::Error;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
