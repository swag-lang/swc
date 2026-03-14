#include "pch.h"
#include "Main/Command/Command.h"
#include "Compiler/Core/SourceFile.h"
#include "Compiler/Parser/Parser/ParserJob.h"
#include "Compiler/Sema/Core/SemaJob.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Support/Math/Hash.h"
#include "Support/Memory/Heap.h"
#include "Support/Thread/Job.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace Command
{
    void sema(CompilerInstance& compiler)
    {
        TaskContext ctx(compiler);

        const Global&     global   = ctx.global();
        JobManager&       jobMgr   = global.jobMgr();
        const JobClientId clientId = compiler.jobClientId();

        // Collect files
        if (compiler.collectFiles(ctx) == Result::Error)
            return;

        // Parser
        for (SourceFile* const f : compiler.files())
        {
            auto* job = heapNew<ParserJob>(ctx, f);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);

        // Filter files
        std::vector<SourceFile*> files;
        files.reserve(compiler.files().size());
        for (SourceFile* const f : compiler.files())
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
        compiler.setSymModule(symModule);

        for (SourceFile* const f : files)
        {
            f->setModuleNamespace(*moduleNamespace);
            auto* job = heapNew<SemaJob>(ctx, f->nodePayloadContext(), true);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);

        for (SourceFile* const f : files)
        {
            auto* job = heapNew<SemaJob>(ctx, f->nodePayloadContext(), false);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        Sema::waitDone(ctx, clientId);
    }
}

SWC_END_NAMESPACE();
