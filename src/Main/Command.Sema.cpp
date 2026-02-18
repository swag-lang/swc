#include "pch.h"
#include "Main/Command.h"
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

        // Collect files
        if (compiler.collectFiles(ctx) == Result::Error)
            return;

        // Parser
        for (SourceFile* f : compiler.files())
        {
            ParserJob* job = heapNew<ParserJob>(ctx, f);
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
            f->setModuleNamespace(*moduleNamespace);
            SemaJob* job = heapNew<SemaJob>(ctx, f->nodePayloadContext(), true);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        jobMgr.waitAll(clientId);

        for (SourceFile* f : files)
        {
            SemaJob* job = heapNew<SemaJob>(ctx, f->nodePayloadContext(), false);
            jobMgr.enqueue(*job, JobPriority::Normal, clientId);
        }

        Sema::waitDone(ctx, clientId);
    }
}

SWC_END_NAMESPACE();
