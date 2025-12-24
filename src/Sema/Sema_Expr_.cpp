#include "pch.h"
#include "Helpers/SemaError.h"
#include "Helpers/SemaNodeView.h"
#include "Parser/AstNodes.h"
#include "Sema/Helpers/SemaMatch.h"
#include "Sema/Sema.h"
#include "Symbol/IdentifierManager.h"
#include "Symbol/LookupResult.h"
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

    LookupResult result;
    SemaMatch::lookup(sema, result, idRef);
    if (result.empty())
        return sema.pause(TaskStateKind::SemaWaitingIdentifier);
    if (!result.isFullComplete())
        return sema.pause(TaskStateKind::SemaWaitingFullComplete);
    sema.setSymbol(sema.curNodeRef(), result.first());
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstMemberAccessExpr::semaPostNode(Sema& sema) const
{
    const SemaNodeView  nodeView(sema, nodeLeftRef);
    const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokMemberRef);

    // Namespace
    if (nodeView.sym && nodeView.sym->isNamespace())
    {
        const auto& namespaceSym = nodeView.sym->cast<SymbolNamespace>();

        LookupResult result;
        SemaMatch::lookup(sema, namespaceSym, result, idRef);
        if (result.empty())
            return sema.pause(TaskStateKind::SemaWaitingIdentifier);
        if (!result.isFullComplete())
            return sema.pause(TaskStateKind::SemaWaitingFullComplete);
        sema.semaInfo().setSymbol(sema.curNodeRef(), result.first());
        return AstVisitStepResult::Continue;
    }

    // Enum
    if (nodeView.type && nodeView.type->isEnum())
    {
        const auto& enumSym = nodeView.type->enumSym();
        if (!enumSym.isFullComplete())
            return sema.pause(TaskStateKind::SemaWaitingFullComplete);

        LookupResult result;
        SemaMatch::lookup(sema, enumSym, result, idRef);
        if (result.empty())
            return sema.pause(TaskStateKind::SemaWaitingIdentifier);
        if (!result.isFullComplete())
            return sema.pause(TaskStateKind::SemaWaitingFullComplete);
        sema.semaInfo().setSymbol(sema.curNodeRef(), result.first());
        return AstVisitStepResult::Continue;
    }

    SemaError::raiseInternal(sema, *this);
    return AstVisitStepResult::Stop;
}

SWC_END_NAMESPACE()
