#include "pch.h"
#include "Main/Command/Command.h"
#include "Main/Command/CommandLine.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/Sema/Core/SemaJob.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
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

namespace Command
{
    void sema(CompilerInstance& compiler)
    {
        SWC_MEM_SCOPE("Sema");
        TaskContext                 ctx(compiler);
        TimedActionLog::ScopedStage stage(ctx, TimedActionLog::Stage::Sema);

        const Global&     global   = ctx.global();
        JobManager&       jobMgr   = global.jobMgr();
        const JobClientId clientId = compiler.jobClientId();

        // Collect files
        if (compiler.collectFiles(ctx) == Result::Error)
            return;

        // Parser
        const uint64_t errorsBefore = Stats::getNumErrors();
        for (SourceFile* f : compiler.files())
        {
            auto* job = heapNew<ParserJob>(ctx, f);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);
        if (Stats::getNumErrors() != errorsBefore)
            return;

        // Filter files
        std::vector<SourceFile*> files;
        files.reserve(compiler.files().size());
        for (SourceFile* f : compiler.files())
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

        auto* symModule = Symbol::make<SymbolModule>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        Utf8  moduleNamespaceName(compiler.buildCfg().moduleNamespace);
        if (moduleNamespaceName.empty())
            moduleNamespaceName = commandLineDefaultModuleNamespace(commandLineDefaultArtifactName(compiler.cmdLine()));

        constexpr SymbolFlags namespaceFlags = SymbolFlagsE::Declared | SymbolFlagsE::Typed | SymbolFlagsE::SemaCompleted;
        const IdentifierRef   idRef          = ctx.idMgr().addIdentifierOwned(moduleNamespaceName, Math::hash(moduleNamespaceName));
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

        stage.setStat(Utf8Helper::countWithLabel(Stats::get().numTokens.load(std::memory_order_relaxed), "token"));
    }
}

SWC_END_NAMESPACE();
