#include "pch.h"
#include "Backend/JIT/JITPatchJob.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Main/CompilerInstance.h"
#include "Main/Global.h"
#include "Support/Memory/Heap.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

JITPatchJob::JITPatchJob(const TaskContext& ctx, SymbolFunction& symbolFunc, const SymbolFunction* weakRelocationBlocker) :
    Job(ctx, JobKind::JitPatch),
    symbolFunc_(&symbolFunc),
    weakRelocationBlocker_(weakRelocationBlocker)
{
}

bool JITPatchJob::schedule(TaskContext& ctx, SymbolFunction& symbolFunc, const SymbolFunction* weakRelocationBlocker)
{
    if (symbolFunc.jitEntryAddress())
        return false;
    if (!symbolFunc.tryMarkJitPatchJobScheduled())
        return false;

    if (!weakRelocationBlocker)
        weakRelocationBlocker = ctx.state().weakJitRelocationBlocker;

    auto* job = heapNew<JITPatchJob>(ctx, symbolFunc, weakRelocationBlocker);
    ctx.compiler().global().jobMgr().enqueue(*job, JobPriority::Normal, ctx.compiler().jobClientId());
    return true;
}

JobResult JITPatchJob::exec()
{
    SWC_ASSERT(symbolFunc_ != nullptr);
    ctx().state().setNone();
    ctx().state().weakJitRelocationBlocker = weakRelocationBlocker_;

    const Result result = symbolFunc_->jitMaterialize(ctx());
    if (result == Result::Error)
        symbolFunc_->setIgnored(ctx());

    return toJobResult(ctx(), result);
}

SWC_END_NAMESPACE();
