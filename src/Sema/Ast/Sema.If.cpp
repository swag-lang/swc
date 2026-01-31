#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/Ast/AstNodes.h"
#include "Sema/Cast/Cast.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

Result AstIfStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeIfBlockRef || childRef == nodeElseBlockRef)
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Local, childRef);

    return Result::Continue;
}

Result AstIfStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeConditionRef)
    {
        SemaNodeView nodeView(sema, nodeConditionRef);
        RESULT_VERIFY(Cast::cast(sema, nodeView, sema.ctx().typeMgr().typeBool(), CastKind::Condition));
    }

    return Result::Continue;
}

Result AstElseStmt::semaPreNode(Sema& sema)
{
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    return Result::Continue;
}

Result AstElseIfStmt::semaPreNode(Sema& sema)
{
    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    return Result::Continue;
}

SWC_END_NAMESPACE();
