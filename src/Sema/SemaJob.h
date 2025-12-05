#pragma once
#include "Sema/Sema.h"
#include "Thread/Job.h"

SWC_BEGIN_NAMESPACE()

class SemaJob : public Job
{
    Sema sema_;

public:
    static constexpr auto K = JobKind::Sema;

    SemaJob(const TaskContext& ctx, SemaInfo& semaCtx);
    SemaJob(const TaskContext& ctx, const Sema& parentSema, AstNodeRef root);
    JobResult exec();

    Sema&       sema() { return sema_; }
    const Sema& sema() const { return sema_; }
};

SWC_END_NAMESPACE()
