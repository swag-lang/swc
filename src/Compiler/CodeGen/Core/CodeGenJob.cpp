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

    Result waitSelfAndDepsSema(Sema& sema, const SymbolFunction& symbolFunc, const SmallVector<SymbolFunction*>& deps)
    {
        const Result selfWaitResult = waitSymbolSemaCompletion(sema, symbolFunc);
        if (selfWaitResult != Result::Continue)
            return selfWaitResult;

        for (const auto* dep : deps)
        {
            SWC_ASSERT(dep);
            const Result depWaitResult = waitSymbolSemaCompletion(sema, *dep);
            if (depWaitResult != Result::Continue)
                return depWaitResult;
        }

        return Result::Continue;
    }

    void scheduleDepCodeGenJobs(TaskContext& ctx, Sema& sema, const SmallVector<SymbolFunction*>& deps)
    {
        for (auto* dep : deps)
        {
            SWC_ASSERT(dep);

            if (!dep->tryMarkCodeGenJobScheduled())
                continue;

            const AstNodeRef depRoot = dep->declNodeRef();
            if (!depRoot.isValid())
                continue;

            const auto depJob = heapNew<CodeGenJob>(ctx, sema, *dep, depRoot);
            sema.compiler().global().jobMgr().enqueue(*depJob, JobPriority::Normal, sema.compiler().jobClientId());
        }
    }

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

    Result generateFunctionCodeGen(Sema& sema, SymbolFunction& symbolFunc, AstNodeRef root)
    {
        SWC_ASSERT(root.isValid());
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

    SmallVector<SymbolFunction*> deps;
    symbolFunc_->appendCallDependencies(deps);

    ///////////////////////////////////////////
    const Result waitSemaResult = waitSelfAndDepsSema(*sema_, *symbolFunc_, deps);
    if (waitSemaResult != Result::Continue)
        return toJobResult(waitSemaResult);

    ///////////////////////////////////////////
    scheduleDepCodeGenJobs(ctx(), *sema_, deps);

    ///////////////////////////////////////////
    const Result codeGenResult = generateFunctionCodeGen(*sema_, *symbolFunc_, root_);
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
