#include "pch.h"
#include "Compiler/CodeGen/Core/CodeGenJob.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/Global.h"
#include "Support/Memory/Heap.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool areDepsReadyForCompletion(const SmallVector<SymbolFunction*>& deps)
    {
        for (const auto* dep : deps)
        {
            if (!dep)
                continue;

            if (!(dep->isCodeGenCompleted() || dep->isCodeGenPreSolved()))
                return false;
        }

        return true;
    }
}

CodeGenJob::CodeGenJob(const TaskContext& ctx, Sema& sema, SymbolFunction& symbolFunc, AstNodeRef root) :
    Job(ctx, JobKind::CodeGen),
    sema_(&sema),
    symbolFunc_(&symbolFunc),
    root_(root)
{
    func = [this] {
        return exec();
    };
}

JobResult CodeGenJob::exec()
{
    SWC_ASSERT(sema_);
    SWC_ASSERT(symbolFunc_);

    SmallVector<SymbolFunction*> deps;
    symbolFunc_->appendCallDependencies(deps);

    ///////////////////////////////////////////
    const Result selfWaitResult = sema_->waitSemaCompleted(symbolFunc_, symbolFunc_->codeRef());
    if (selfWaitResult != Result::Continue)
        return toJobResult(selfWaitResult);
    for (const auto* dep : deps)
    {
        SWC_ASSERT(dep);
        const Result depWaitResult = sema_->waitSemaCompleted(dep, dep->codeRef());
        if (depWaitResult != Result::Continue)
            return toJobResult(depWaitResult);
    }

    ///////////////////////////////////////////
    for (auto* dep : deps)
    {
        SWC_ASSERT(dep);

        if (!dep->tryMarkCodeGenJobScheduled())
            continue;
        const AstNodeRef depRoot = dep->declNodeRef();
        if (!depRoot.isValid())
            continue;
        const auto depJob = heapNew<CodeGenJob>(ctx(), *sema_, *dep, depRoot);
        sema_->compiler().global().jobMgr().enqueue(*depJob, JobPriority::Normal, sema_->compiler().jobClientId());
    }

    ///////////////////////////////////////////
    SWC_ASSERT(root_.isValid());
    CodeGen      codeGen(*sema_);
    const Result codeGenResult = codeGen.exec(*symbolFunc_, root_);
    if (codeGenResult != Result::Continue)
        return toJobResult(codeGenResult);
    symbolFunc_->setCodeGenPreSolved(ctx());

    const Result jitResult = symbolFunc_->ensureJitEntry(ctx());
    if (jitResult != Result::Continue)
        return toJobResult(jitResult);

    ///////////////////////////////////////////
    if (!areDepsReadyForCompletion(deps))
        return JobResult::Sleep;

    symbolFunc_->setCodeGenCompleted(ctx());
    return JobResult::Done;
}

SWC_END_NAMESPACE();
