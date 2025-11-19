#include "pch.h"
#include "Sema/SemaJob.h"
#include "Parser/AstVisit.h"

SWC_BEGIN_NAMESPACE()

SemaJob::SemaJob(const TaskContext& ctx, Ast* ast, AstNodeRef root) :
    Job(ctx),
    ast_(ast)
{
    func = [this](JobContext& jobCtx) {
        return exec(jobCtx);
    };

    visit_.start(*ast, root);
    visit_.setPreNodeVisitor([this](AstNode& node) { return preNode(node); });
    visit_.setPostNodeVisitor([this](AstNode& node) { return postNode(node); });
}

AstVisitStepResult SemaJob::preNode(AstNode& node)
{
    return AstVisitStepResult::Continue;
}

AstVisitStepResult SemaJob::postNode(AstNode& node)
{
    return AstVisitStepResult::Continue;
}

JobResult SemaJob::exec(JobContext& ctx)
{
    ctx_ = &ctx;
    while (true)
    {
        const auto result = visit_.step();
        if (result == AstVisitResult::Pause)
            return JobResult::Sleep;
        if (result == AstVisitResult::Stop)
            return JobResult::Done;
    }
}

SWC_END_NAMESPACE()
