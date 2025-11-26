#include "pch.h"
#include "Sema/SemaJob.h"
#include "Main/Global.h"
#include "Parser/Ast.h"
#include "Parser/AstVisit.h"
#include "Thread/JobManager.h"

SWC_BEGIN_NAMESPACE()

SemaJob::SemaJob(const TaskContext& ctx, Ast* ast, AstNodeRef root) :
    Job(ctx),
    ast_(ast)
{
    func = [this]() {
        return exec();
    };

    visit_.start(*ast, root);
    visit_.setPreNodeVisitor([this](AstNode& node) { return preNode(node); });
    visit_.setPostNodeVisitor([this](AstNode& node) { return postNode(node); });
    visit_.setPreChildVisitor([this](AstNode& node, AstNodeRef& childRef) { return preChild(node, childRef); });
}

AstVisitStepResult SemaJob::preNode(AstNode& node)
{
    const auto& info = Ast::nodeIdInfos(node.id());
    if (!info.semaPreNode)
        return AstVisitStepResult::Continue;
    return info.semaPreNode(*this, node);
}

AstVisitStepResult SemaJob::postNode(AstNode& node)
{
    const auto& info = Ast::nodeIdInfos(node.id());
    if (!info.semaPostNode)
        return AstVisitStepResult::Continue;
    return info.semaPostNode(*this, node);
}

AstVisitStepResult SemaJob::preChild(AstNode& node, AstNodeRef& childRef)
{
    const auto& info = Ast::nodeIdInfos(node.id());

    const auto childPtr = ast().node(childRef);
    switch (childPtr->id())
    {
        case AstNodeId::CompilerFlow:
        {
            if (visit().root() == ast().root())
            {
                const auto job = std::make_shared<SemaJob>(ctx(), &ast(), childRef);
                compiler().global().jobMgr().enqueue(job, JobPriority::Normal, compiler().jobClientId());
                return AstVisitStepResult::SkipChildren;
            }

            break;
        }

        default:
            break;
    }

    if (!info.semaPreChild)
        return AstVisitStepResult::Continue;
    return info.semaPreChild(*this, node, childRef);
}

JobResult SemaJob::exec()
{
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
