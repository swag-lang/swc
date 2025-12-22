#include "pch.h"
#include "Helpers/SemaError.h"
#include "Helpers/SemaNodeView.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
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
        return sema.pause(TaskStateKind::SemaWaitingIdentifier, sema.curNodeRef());

    const Symbol* sym = result.first();
    if (const SymbolConstant* symCst = sym->safeCast<SymbolConstant>())
        sema.setConstant(sema.curNodeRef(), symCst->cstRef());
    else if (const SymbolEnumValue* symEnumVal = sym->safeCast<SymbolEnumValue>())
        sema.setConstant(sema.curNodeRef(), symEnumVal->cstRef());
    else
        sema.setSymbol(sema.curNodeRef(), sym);

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstMemberAccessExpr::semaPostNode(Sema& sema) const
{
    const SemaNodeView  nodeView(sema, nodeLeftRef);
    const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokMemberRef);

    if (nodeView.type->isEnum())
    {
        const auto& enumSym = nodeView.type->enumSym();
        if (!enumSym.isFullComplete())
            return sema.pause(TaskStateKind::SemaWaitingFullComplete, nodeLeftRef);

        SmallVector<Symbol*> matches;
        enumSym.lookup(idRef, matches);
        SWC_ASSERT(matches.size() == 1);

        const auto& symValue = matches[0]->cast<SymbolEnumValue>();
        sema.semaInfo().setConstant(sema.curNodeRef(), symValue.cstRef());
    }
    else
    {
        SemaError::raiseInternal(sema, *this);
    }

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
