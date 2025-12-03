#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/Symbols.h"
#include "Symbol/IdentifierManager.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstVarDecl::semaPostNode(Sema& sema) const
{
    if (hasParserFlag(Const))
    {
        if (nodeInitRef.isInvalid())
        {
            sema.raiseError(DiagnosticId::sema_err_const_missing_init, srcViewRef(), tokNameRef);
            return AstVisitStepResult::Stop;
        }

        if (!sema.hasConstant(nodeInitRef))
        {
            sema.raiseExprNotConst(nodeInitRef);
            return AstVisitStepResult::Stop;
        }
    }
    else
    {
        sema.raiseInternalError(*this);
        return AstVisitStepResult::Stop;
    }

    // SemaNodeView type(sema, nodeTypeRef);
    // SemaNodeView init(sema, nodeInitRef);

    const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokNameRef);
    const auto          cst   = new SymbolConstant(sema.ctx(), idRef, sema.constantRefOf(nodeInitRef));
    sema.setSymbol(sema.curNodeRef(), cst);

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
