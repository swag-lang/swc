#include "pch.h"
#include "Main/Command.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Memory/Heap.h"
#include "Parser/ParserJob.h"
#include "Sema/Helpers/SemaJob.h"
#include "Sema/Symbol/IdentifierManager.h"
#include "Sema/Symbol/Symbols.h"
#include "Thread/Job.h"
#include "Thread/JobManager.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE()

namespace Command
{
    void sema(CompilerInstance& compiler)
    {
        TaskContext ctx(compiler);

        const auto&       global   = ctx.global();
        auto&             jobMgr   = global.jobMgr();
        const JobClientId clientId = compiler.jobClientId();

        if (compiler.collectFiles(ctx) == Result::Error)
            return;

        for (const auto& f : compiler.files())
        {
            const auto job = heapNew<ParserJob>(ctx, f);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);

        compiler.setupSema(ctx);

        const auto symModule       = ctx.compiler().allocate<SymbolModule>(ctx);
        const auto idRef           = ctx.compiler().idMgr().addIdentifier("test", Math::hash("test"));
        const auto moduleNamespace = symModule->addNamespace(ctx, idRef, SymbolFlagsE::Zero);

        for (const auto& f : compiler.files())
        {
            const auto& srcView = f->ast().srcView();
            if (srcView.mustSkip())
                continue;

            if (f->hasError())
                continue;

            f->semaInfo().setModuleNamespace(*moduleNamespace);
            f->semaInfo().setFileNamespace(*moduleNamespace->addNamespace(ctx, IdentifierRef::invalid(), SymbolFlagsE::Zero));

            const auto job = heapNew<SemaJob>(ctx, f->semaInfo());
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        Sema::waitAll(ctx, clientId);
    }
}

SWC_END_NAMESPACE()
