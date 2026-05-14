#include "pch.h"
#include "Main/Command/Command.h"
#include "Backend/JIT/JITExecManager.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/Sema/Core/SemaJob.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Main/Command/CommandLineParser.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Core/Utf8Helper.h"
#include "Support/Math/Hash.h"
#include "Support/Memory/Heap.h"
#include "Support/Memory/MemoryProfile.h"
#include "Support/Report/ScopedTimedAction.h"
#include "Support/Thread/Job.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Utf8 buildModuleNamespaceName(const CompilerInstance& compiler)
    {
        Utf8 moduleNamespaceName;
        if (compiler.buildCfg().moduleNamespace.ptr && compiler.buildCfg().moduleNamespace.length)
            moduleNamespaceName = compiler.buildCfg().moduleNamespace;
        if (!moduleNamespaceName.empty())
            return moduleNamespaceName;

        Utf8 artifactName;
        if (compiler.buildCfg().name.ptr && compiler.buildCfg().name.length)
            artifactName = compiler.buildCfg().name;
        if (artifactName.empty())
            artifactName = defaultArtifactName(compiler.cmdLine());
        return defaultModuleNamespace(artifactName);
    }

    bool shouldLogBuildConfiguration(const CompilerInstance& compiler)
    {
        switch (compiler.cmdLine().command)
        {
            case CommandKind::Build:
            case CommandKind::Run:
            case CommandKind::Test:
                return true;
            default:
                return false;
        }
    }
}

namespace Command
{
    void sema(CompilerInstance& compiler)
    {
        SWC_MEM_SCOPE("Sema");
        TaskContext ctx(compiler);

        const Global&     global   = ctx.global();
        JobManager&       jobMgr   = global.jobMgr();
        const JobClientId clientId = compiler.jobClientId();

        // Collect files
        if (compiler.collectFiles(ctx) == Result::Error)
            return;
        if (compiler.runModuleSetup(ctx) == Result::Error)
            return;
        if (shouldLogBuildConfiguration(compiler))
            TimedActionLog::printBuildConfiguration(ctx);

        TimedActionLog::ScopedStage stage(ctx, TimedActionLog::Stage::Sema);

        std::vector<SourceFile*> inputFiles;
        inputFiles.reserve(compiler.files().size());
        for (SourceFile* f : compiler.files())
        {
            if (!f)
                continue;
            if (!compiler.cmdLine().moduleFilePath.empty() && f->hasFlag(FileFlagsE::Module))
                continue;
            inputFiles.push_back(f);
        }

        // Parser
        const uint64_t errorsBefore = Stats::getNumErrors();
        for (SourceFile* f : inputFiles)
        {
            auto* job = heapNew<ParserJob>(ctx, f);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);
#if SWC_DEV_MODE
        jobMgr.assertNoWaitingJobs(clientId, "Command::sema parser waitAll");
#endif
        if (Stats::getNumErrors() != errorsBefore)
            return;

        // Filter files
        std::vector<SourceFile*> files;
        files.reserve(inputFiles.size());
        for (SourceFile* f : inputFiles)
        {
            const SourceView& srcView = f->ast().srcView();
            if (srcView.mustSkip())
                continue;
            if (!srcView.runsSema())
                continue;
            if (f->hasError())
                continue;
            files.push_back(f);
        }

        if (compiler.setupSema(ctx) == Result::Error)
            return;

        auto* symModule           = Symbol::make<SymbolModule>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        Utf8  moduleNamespaceName = buildModuleNamespaceName(compiler);

        constexpr SymbolFlags namespaceFlags  = SymbolFlagsE::Declared | SymbolFlagsE::Typed | SymbolFlagsE::SemaCompleted;
        const IdentifierRef   idRef           = ctx.idMgr().addIdentifierOwned(moduleNamespaceName, Math::hash(moduleNamespaceName));
        auto*                 moduleNamespace = Symbol::make<SymbolNamespace>(ctx, nullptr, TokenRef::invalid(), idRef, namespaceFlags);
        symModule->addSingleSymbol(ctx, moduleNamespace);
        compiler.setSymModule(symModule);

        for (SourceFile* f : files)
        {
            f->setModuleNamespace(*moduleNamespace);
            auto* job = heapNew<SemaJob>(ctx, f->nodePayloadContext(), true);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);

        for (SourceFile* f : files)
        {
            auto* job = heapNew<SemaJob>(ctx, f->nodePayloadContext(), false);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        Sema::waitDone(ctx, clientId);
#if SWC_DEV_MODE
        if (jobMgr.debugHasWaitingJobs(clientId))
            std::fprintf(stderr, "%s", compiler.jitExecMgr().debugDescribeState().c_str());
        jobMgr.assertNoWaitingJobs(clientId, "Command::sema sema waitDone");
#endif
        if (!Stats::hasError() && compiler.exportModuleApi(ctx) == Result::Error)
            return;

        const TimedActionLog::StatsSnapshot deltaSnapshot = stage.delta();
        std::vector<Utf8>                   statParts;
        if (deltaSnapshot.numFiles)
            statParts.push_back(TimedActionLog::formatStatCount(ctx, deltaSnapshot.numFiles, "file"));
        if (deltaSnapshot.numTokens)
            statParts.push_back(TimedActionLog::formatStatCount(ctx, deltaSnapshot.numTokens, "token"));

        stage.setStat(TimedActionLog::joinStatItems(ctx, statParts));
    }
}

SWC_END_NAMESPACE();
