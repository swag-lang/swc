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
    Result waitSymbolSemaCompletion(Sema& sema, const Symbol& symbol)
    {
        return sema.waitSemaCompleted(&symbol, symbol.codeRef());
    }

    bool areDepsReadyForCompletion(const SmallVector<SymbolFunction*>& deps)
    {
        for (const auto* dep : deps)
        {
            SWC_ASSERT(dep);
            if (!(dep->isCodeGenCompleted() || dep->isCodeGenPreSolved()))
                return false;
        }

        return true;
    }

    Result generateFunctionCodeGen(Sema& sema, SymbolFunction& symbolFunc, AstNodeRef root)
    {
        if (!root.isValid())
            return Result::Error;
        CodeGen codeGen(sema);
        return codeGen.exec(symbolFunc, root);
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

    const Result selfWaitResult = waitSymbolSemaCompletion(*sema_, *symbolFunc_);
    if (selfWaitResult != Result::Continue)
        return toJobResult(selfWaitResult);

    SmallVector<SymbolFunction*> deps;
    symbolFunc_->appendCallDependencies(deps);

    for (auto* dep : deps)
    {
        if (!dep)
            continue;

        const Result depWaitResult = waitSymbolSemaCompletion(*sema_, *dep);
        if (depWaitResult != Result::Continue)
            return toJobResult(depWaitResult);

        if (dep->tryMarkCodeGenJobScheduled())
        {
            const AstNodeRef depRoot = dep->declNodeRef();
            if (!depRoot.isValid())
                continue;
            const auto depJob = heapNew<CodeGenJob>(ctx(), *sema_, *dep, depRoot);
            sema_->compiler().global().jobMgr().enqueue(*depJob, JobPriority::Normal, sema_->compiler().jobClientId());
        }
    }

    const Result result = generateFunctionCodeGen(*sema_, *symbolFunc_, root_);
    if (result != Result::Continue)
        return toJobResult(result);

    symbolFunc_->setCodeGenPreSolved(ctx());

    const Result jitResult = symbolFunc_->ensureJitEntry(ctx());
    if (jitResult != Result::Continue)
        return toJobResult(jitResult);

    if (!areDepsReadyForCompletion(deps))
        return JobResult::Sleep;

    symbolFunc_->setCodeGenCompleted(ctx());
    return JobResult::Done;
}

SWC_END_NAMESPACE();
