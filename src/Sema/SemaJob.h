#pragma once
#include "Sema/Sema.h"
#include "Thread/Job.h"

SWC_BEGIN_NAMESPACE()

class SemaJob : public Job
{
    Sema sema_;

public:
    SemaJob(TaskContext& ctx, Ast* ast, AstNodeRef root);
    SemaJob(TaskContext& ctx, Ast* ast, AstNodeRef root, const Sema& parentSema);
    JobResult exec();
};

SWC_END_NAMESPACE()
