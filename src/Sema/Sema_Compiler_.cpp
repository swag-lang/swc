#include "pch.h"
#include "Parser/AstNodes.h"
#include "Sema/ConstantManager.h"
#include "Sema/SemaJob.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstCompilerIf::semaPreChild(SemaJob& job, AstNodeRef& childRef)
{
    if (childRef == nodeCondition)
        return AstVisitStepResult::Continue;

    const auto nodeCond = job.node(nodeCondition);
    if (!nodeCond->isConstant())
        return AstVisitStepResult::Stop;

    const auto& constant = nodeCond->getConstant(job.ctx());
    if (!constant.isBool())
        return AstVisitStepResult::Stop;

    if (childRef == nodeIfBlock && !constant.getBool())
        return AstVisitStepResult::SkipChildren;
    if (childRef == nodeElseBlock && constant.getBool())
        return AstVisitStepResult::SkipChildren;

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
