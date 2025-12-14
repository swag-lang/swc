#include "pch.h"
#include "Helpers/SemaError.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Helpers/SemaCast.h"
#include "Sema/Helpers/SemaNodeView.h"
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
            SemaError::raise(sema, DiagnosticId::sema_err_const_missing_init, srcViewRef(), tokNameRef);
            return AstVisitStepResult::Stop;
        }

        SemaNodeView nodeInitView(sema, nodeInitRef);
        if (nodeInitView.cstRef.isInvalid())
        {
            SemaError::raiseExprNotConst(sema, nodeInitRef);
            return AstVisitStepResult::Stop;
        }

        if (nodeTypeRef.isValid())
        {
            const SemaNodeView nodeTypeView(sema, nodeTypeRef);

            CastContext castCtx(CastKind::Implicit);
            castCtx.errorNodeRef = nodeTypeRef;
            nodeInitView.cstRef  = SemaCast::castConstant(sema, castCtx, nodeInitView.cstRef, nodeTypeView.typeRef);
            if (nodeInitView.cstRef.isInvalid())
                return AstVisitStepResult::Stop;
        }

        symbolMap->addConstant(sema.ctx(), idRef, nodeInitView.cstRef);
    }
    else
    {
        SemaError::raiseInternal(sema, *this);
    }

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
