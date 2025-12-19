#include "pch.h"
#include "Helpers/SemaError.h"
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

    const SymbolConstant* symCst = sym->safeCast<SymbolConstant>();
    if (symCst)
        sema.setConstant(sema.curNodeRef(), symCst->cstRef());
    else
        sema.setSymbol(sema.curNodeRef(), sym);

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
