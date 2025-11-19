#include "pch.h"

#include "Parser/Ast.h"
#include "Parser/AstVisit.h"
#include "Sema/SemaJob.h"

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
    visit_.setPreChildVisitor([this](AstNode& node, AstNodeRef childRef) { return preChild(node, childRef); });
}

AstVisitStepResult SemaJob::preNode(AstNode& node)
{
    return AstVisitStepResult::Continue;
}

AstVisitStepResult SemaJob::postNode(AstNode& node)
{
    return AstVisitStepResult::Continue;
}

AstNodeRef SemaJob::preChild(AstNode& node, AstNodeRef childRef)
{
    const auto& info = Ast::nodeIdInfos(node.id);
    return info.semaPreChild(&node, childRef);
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
