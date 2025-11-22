#include "pch.h"
#include "Parser/Ast.h"
#include "Parser/AstNodes.h"
#include "Sema/ConstantManager.h"
#include "Sema/SemaJob.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstBoolLiteral::semaPreNode(SemaJob& job)
{
    const auto& tok = job.token(srcViewRef(), tokRef());
    if (tok.is(TokenId::KwdTrue))
        setConstant(job.constMgr().boolTrue());
    else if (tok.is(TokenId::KwdFalse))
        setConstant(job.constMgr().boolFalse());
    else
        SWC_UNREACHABLE();

    return AstVisitStepResult::SkipChildren;
}

AstVisitStepResult AstStringLiteral::semaPreNode(SemaJob& job)
{
    const auto& tok     = job.token(srcViewRef(), tokRef());
    const auto& srcView = job.compiler().srcView(srcViewRef());
    const auto  str     = tok.string(srcView);

    if (tok.hasNotFlag(TokenFlagsE::Escaped))
    {
        const auto val = ConstantValue::makeString(job.ctx(), str);
        setConstant(job.constMgr().addConstant(val));
        return AstVisitStepResult::SkipChildren;
    }

    const std::string result{str};
    const auto        val = ConstantValue::makeString(job.ctx(), result);
    setConstant(job.constMgr().addConstant(val));
    return AstVisitStepResult::SkipChildren;
}

SWC_END_NAMESPACE()
