#pragma once
#include "Parser/AstVisit.h"
#include "Thread/Job.h"

SWC_BEGIN_NAMESPACE()

class SemaJob : public Job
{
    JobContext* ctx_ = nullptr;
    Ast*        ast_ = nullptr;
    AstVisit    visit_;

    AstVisitStepResult preNode(AstNode& node);
    AstVisitStepResult postNode(AstNode& node);
    JobResult          exec(JobContext& ctx);

public:
    SemaJob(const TaskContext& ctx, Ast* ast);
};

SWC_END_NAMESPACE()
