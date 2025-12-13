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
    const IdentifierRef idRef     = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokNameRef);
    SymbolMap*          symbolMap = nullptr;

    const SymbolAccess access = sema.frame().currentAccess.value_or(sema.frame().defaultAccess);
    if (access == SymbolAccess::Internal)
        symbolMap = &sema.semaInfo().fileNamespace();
    else
        symbolMap = sema.curSymMap();

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

        symbolMap->addConstant(sema.ctx(), idRef, sema.constantRefOf(nodeInitRef));
    }
    else
    {
        sema.raiseInternalError(*this);
    }

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
