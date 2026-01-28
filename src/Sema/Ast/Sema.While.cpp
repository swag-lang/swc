#include "pch.h"
#include "Parser/AstNodes.h"
#include "Sema/Cast/Cast.h"
#include "Sema/Core/Sema.h"
#include "Sema/Core/SemaNodeView.h"

SWC_BEGIN_NAMESPACE();

Result AstWhileStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    // Body has its own local scope.
    if (childRef == nodeBodyRef)
        sema.pushScopeAutoPopOnPostChild(SemaScopeFlagsE::Local, childRef);

    return Result::Continue;
}

Result AstWhileStmt::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    // Ensure while condition is `bool` (or castable to it).
    if (childRef == nodeExprRef)
    {
        SemaNodeView nodeView(sema, nodeExprRef);
        RESULT_VERIFY(Cast::cast(sema, nodeView, sema.ctx().typeMgr().typeBool(), CastKind::Condition));
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
