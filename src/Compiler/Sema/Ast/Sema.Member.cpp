#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"

SWC_BEGIN_NAMESPACE();

Result AstMemberAccessExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef)
{
    SWC_UNUSED(childRef);
    if (childRef != nodeRightRef)
        return Result::Continue;

    bool allowOverloadSet = hasFlag(AstMemberAccessExprFlagsE::CallCallee);
    if (const auto* ident = sema.node(nodeRightRef).safeCast<AstIdentifier>())
        allowOverloadSet = allowOverloadSet || ident->hasFlag(AstIdentifierFlagsE::InCompilerDefined);
    return SemaHelpers::resolveMemberAccess(sema, sema.curNodeRef(), *this, allowOverloadSet);
}

SWC_END_NAMESPACE();
