#include "pch.h"
#include "Helpers/SemaError.h"
#include "Helpers/SemaNodeView.h"
#include "Parser/AstNodes.h"
#include "Sema/Helpers/SemaMatch.h"
#include "Sema/Sema.h"
#include "Symbol/IdentifierManager.h"
#include "Symbol/MatchResult.h"
#include "Symbol/Symbol.h"
#include "Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstParenExpr::semaPostNode(Sema& sema)
{
    sema.semaInherit(*this, nodeExprRef);
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstIdentifier::semaPostNode(Sema& sema) const
{
    const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokRef());

    MatchResult result;
    SemaMatch::lookup(sema, result, idRef);
    if (result.empty())
        return sema.pause(TaskStateKind::SemaWaitingIdentifier);
    if (!result.isComplete())
        return sema.pause(TaskStateKind::SemaWaitingFullComplete);
    sema.setSymbol(sema.curNodeRef(), result.first());
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstMemberAccessExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeRightRef)
        return AstVisitStepResult::Continue;

    const SemaNodeView nodeLeftView(sema, nodeLeftRef);
    const SemaNodeView nodeRightView(sema, nodeRightRef);
    TokenRef           tokNameRef;

    if (nodeRightView.node->is(AstNodeId::Identifier))
        tokNameRef = nodeRightView.node->tokRef();
    else
        SWC_UNREACHABLE();

    const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokNameRef);

    // Namespace
    if (nodeLeftView.sym && nodeLeftView.sym->isNamespace())
    {
        const auto& namespaceSym = nodeLeftView.sym->cast<SymbolNamespace>();

        MatchResult result;
        SemaMatch::lookupAppend(sema, namespaceSym, result, idRef);
        if (result.empty())
            return sema.pause(TaskStateKind::SemaWaitingIdentifier);
        if (!result.isComplete())
            return sema.pause(TaskStateKind::SemaWaitingFullComplete);

        sema.semaInfo().setSymbol(sema.curNodeRef(), result.first());
        return AstVisitStepResult::SkipChildren;
    }

    // Enum
    if (nodeLeftView.type && nodeLeftView.type->isEnum())
    {
        const auto& enumSym = nodeLeftView.type->enumSym();
        if (!enumSym.isComplete())
            return sema.pause(TaskStateKind::SemaWaitingFullComplete);

        MatchResult result;
        SemaMatch::lookupAppend(sema, enumSym, result, idRef);
        if (result.empty())
            return sema.pause(TaskStateKind::SemaWaitingIdentifier);
        if (!result.isComplete())
            return sema.pause(TaskStateKind::SemaWaitingFullComplete);

        sema.semaInfo().setSymbol(sema.curNodeRef(), result.first());
        return AstVisitStepResult::SkipChildren;
    }

    SemaError::raiseInternal(sema, *this);
    return AstVisitStepResult::Stop;
}

SWC_END_NAMESPACE()
