#include "pch.h"
#include "Main/Command.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/Sema/Core/SemaJob.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Main/Stats.h"
#include "Support/Math/Hash.h"
#include "Support/Memory/Heap.h"
#include "Support/Thread/Job.h"
#include "Support/Thread/JobManager.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE();

namespace Command
{
    void sema(CompilerInstance& compiler)
    {
        TaskContext ctx(compiler);

        const Global&     global   = ctx.global();
        JobManager&       jobMgr   = global.jobMgr();
        const JobClientId clientId = compiler.jobClientId();
#if SWC_HAS_STATS
        Stats& stats = Stats::get();
#endif

        // Collect files
        if (compiler.collectFiles(ctx) == Result::Error)
            return;

        // Parser
        for (SourceFile* f : compiler.files())
        {
            auto* job = heapNew<ParserJob>(ctx, f);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);
#if SWC_HAS_STATS
        stats.memAllocatedAfterParser.store(stats.memAllocated.load(std::memory_order_relaxed), std::memory_order_relaxed);
        stats.memMaxAfterParser.store(stats.memMaxAllocated.load(std::memory_order_relaxed), std::memory_order_relaxed);
#endif

        // Filter files
        std::vector<SourceFile*> files;
        for (SourceFile* f : compiler.files())
        {
            const SourceView& srcView = f->ast().srcView();
            if (srcView.mustSkip())
                continue;
            if (f->hasError())
                continue;
            files.push_back(f);
        }

        compiler.setupSema(ctx);

        auto*               symModule       = Symbol::make<SymbolModule>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        const IdentifierRef idRef           = ctx.idMgr().addIdentifier("test", Math::hash("test"));
        auto*               moduleNamespace = Symbol::make<SymbolNamespace>(ctx, nullptr, TokenRef::invalid(), idRef, SymbolFlagsE::Zero);
        symModule->addSingleSymbol(ctx, moduleNamespace);

        for (SourceFile* f : files)
        {
            f->setModuleNamespace(*moduleNamespace);
            auto* job = heapNew<SemaJob>(ctx, f->nodePayloadContext(), true);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);
#if SWC_HAS_STATS
        stats.memAllocatedAfterSemaDecl.store(stats.memAllocated.load(std::memory_order_relaxed), std::memory_order_relaxed);
        stats.memMaxAfterSemaDecl.store(stats.memMaxAllocated.load(std::memory_order_relaxed), std::memory_order_relaxed);
#endif

        for (SourceFile* f : files)
        {
            auto* job = heapNew<SemaJob>(ctx, f->nodePayloadContext(), false);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        Sema::waitDone(ctx, clientId);
#if SWC_HAS_STATS
        stats.memAllocatedAfterSema.store(stats.memAllocated.load(std::memory_order_relaxed), std::memory_order_relaxed);
        stats.memMaxAfterSema.store(stats.memMaxAllocated.load(std::memory_order_relaxed), std::memory_order_relaxed);
#endif
    }
}

SWC_END_NAMESPACE();
