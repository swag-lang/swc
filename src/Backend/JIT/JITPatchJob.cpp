#include "pch.h"
#include "Backend/JIT/JITPatchJob.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Support/Memory/Heap.h"

SWC_BEGIN_NAMESPACE();

JITPatchJob::JITPatchJob(const TaskContext& ctx, SymbolFunction& symbolFunc) :
    Job(ctx, JobKind::JitPatch),
    symbolFunc_(&symbolFunc)
{
}

bool JITPatchJob::schedule(TaskContext& ctx, SymbolFunction& symbolFunc)
{
    if (symbolFunc.jitEntryAddress())
        return false;
    if (!symbolFunc.tryMarkJitPatchJobScheduled())
        return false;

    auto* job = heapNew<JITPatchJob>(ctx, symbolFunc);
    ctx.compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, ctx.compiler().jobClientId());
    return true;
}

JobResult JITPatchJob::exec()
{
    SWC_ASSERT(symbolFunc_ != nullptr);
    ctx().state().reset();

    Result result = symbolFunc_->jitMaterialize(ctx());
    if (result == Result::Error)
        symbolFunc_->setIgnored(ctx());

    return Job::toJobResult(ctx(), result);
}

SWC_END_NAMESPACE();
