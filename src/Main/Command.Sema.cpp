#include "pch.h"
#include "Main/Command.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Math/Hash.h"
#include "Memory/Heap.h"
#include "Parser/Parser/ParserJob.h"
#include "Sema/Core/SemaJob.h"
#include "Sema/Symbol/IdentifierManager.h"
#include "Sema/Symbol/Symbols.h"
#include "Thread/Job.h"
#include "Thread/JobManager.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE();

namespace Command
{
    void sema(CompilerInstance& compiler)
    {
        TaskContext ctx(compiler);

        const auto&       global   = ctx.global();
        auto&             jobMgr   = global.jobMgr();
        const JobClientId clientId = compiler.jobClientId();

        // Collect files
        if (compiler.collectFiles(ctx) == Result::Error)
            return;

        // Parser
        for (SourceFile* f : compiler.files())
        {
            const auto job = heapNew<ParserJob>(ctx, f);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);

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

        SymbolModule*       symModule       = Symbol::make<SymbolModule>(ctx, nullptr, TokenRef::invalid(), IdentifierRef::invalid(), SymbolFlagsE::Zero);
        const IdentifierRef idRef           = ctx.idMgr().addIdentifier("test", Math::hash("test"));
        SymbolNamespace*    moduleNamespace = Symbol::make<SymbolNamespace>(ctx, nullptr, TokenRef::invalid(), idRef, SymbolFlagsE::Zero);
        symModule->addSingleSymbol(ctx, moduleNamespace);

        for (SourceFile* f : files)
        {
            f->semaInfo().setModuleNamespace(*moduleNamespace);
            const auto job = heapNew<SemaJob>(ctx, f->semaInfo(), true);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);

        for (SourceFile* f : files)
        {
            const auto job = heapNew<SemaJob>(ctx, f->semaInfo(), false);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        Sema::waitDone(ctx, clientId);
    }
}

SWC_END_NAMESPACE();
