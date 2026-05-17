#include "pch.h"
#include "Main/CompilerMessageTypeInfoJob.h"
#include "Compiler/Sema/Core/Sema.h"

SWC_BEGIN_NAMESPACE();

CompilerMessageTypeInfoJob::CompilerMessageTypeInfoJob(const TaskContext& ctx) :
    Job(ctx, JobKind::CompilerMessage)
{
}

JobResult CompilerMessageTypeInfoJob::exec()
{
    if (!hasCurrentRequest_)
    {
        if (!ctx().compiler().tryPopCompilerMessageTypeInfoPreparation(currentRequest_))
            return JobResult::Done;
        hasCurrentRequest_ = true;
    }

    ctx().state().setNone();
    if (!currentRequest_.listenerFile || currentRequest_.ownerNodeRef.isInvalid() || currentRequest_.typeRef.isInvalid())
    {
        hasCurrentRequest_ = false;
        return JobResult::Done;
    }

    Sema         sema(ctx(), currentRequest_.listenerFile->nodePayloadContext(), false);
    const Result result = ctx().compiler().prepareCompilerMessageTypeInfo(sema, currentRequest_.typeRef, currentRequest_.ownerNodeRef);
    if (result == Result::Pause)
        return JobResult::Sleep;

    hasCurrentRequest_ = false;
    if (result == Result::Error)
    {
        ctx().compiler().markCompilerMessageTypeInfoPreparationFailed();
        return JobResult::Done;
    }

    return JobResult::Done;
}

SWC_END_NAMESPACE();
