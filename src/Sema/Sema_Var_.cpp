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
    SemaNodeView        nodeInitView(sema, nodeInitRef);
    const SemaNodeView  nodeTypeView(sema, nodeTypeRef);
    SymbolMap*          symbolMap = nullptr;
    const IdentifierRef idRef     = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokNameRef);

    // Get the destination symbolMap
    const SymbolAccess access = sema.frame().currentAccess.value_or(sema.frame().defaultAccess);
    if (access == SymbolAccess::Internal)
        symbolMap = &sema.semaInfo().fileNamespace();
    else
        symbolMap = sema.curSymMap();

    CastContext castCtx(CastKind::Implicit);
    castCtx.errorNodeRef = nodeInitRef;

    if (nodeInitView.typeRef.isValid() && nodeTypeView.typeRef.isValid())
    {
        if (auto failure = SemaCast::check(sema, castCtx, nodeInitView.typeRef, nodeTypeView.typeRef))
        {
            // Primary, context-specific diagnostic
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_var_init_type_mismatch, castCtx.errorNodeRef);
            diag.addArgument(Diagnostic::ARG_TYPE, nodeInitView.typeRef);
            diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, nodeTypeView.typeRef);

            // Add the underlying reason as a note
            {
                auto reason = SemaError::report(sema, failure->diagId, failure->nodeRef);
                reason.addArgument(Diagnostic::ARG_TYPE, nodeInitView.typeRef);
                reason.addArgument(Diagnostic::ARG_REQUESTED_TYPE, nodeTypeView.typeRef);

                switch (failure->diagId)
                {
                    case DiagnosticId::sema_err_bit_cast_invalid_type:
                        reason.addArgument(Diagnostic::ARG_TYPE, failure->typeArg);
                        break;
                    case DiagnosticId::sema_err_bit_cast_size:
                        reason.addArgument(Diagnostic::ARG_LEFT, failure->leftType);
                        reason.addArgument(Diagnostic::ARG_RIGHT, failure->rightType);
                        break;
                    default:
                        reason.addArgument(Diagnostic::ARG_LEFT, failure->leftType);
                        reason.addArgument(Diagnostic::ARG_RIGHT, failure->rightType);
                        break;
                }

                diag.addElement(reason.last());
            }

            // Explicit cast works hint
            castCtx.kind = CastKind::Explicit;
            if (!SemaCast::check(sema, castCtx, nodeInitView.typeRef, nodeTypeView.typeRef))
                diag.addElement(DiagnosticId::sema_note_cast_explicit);

            diag.report(sema.ctx());
            return AstVisitStepResult::Stop;
        }
    }

    if (hasParserFlag(Const))
    {
        if (nodeInitRef.isInvalid())
        {
            SemaError::raise(sema, DiagnosticId::sema_err_const_missing_init, srcViewRef(), tokNameRef);
            return AstVisitStepResult::Stop;
        }

        if (nodeInitView.cstRef.isInvalid())
        {
            SemaError::raiseExprNotConst(sema, nodeInitRef);
            return AstVisitStepResult::Stop;
        }

        if (nodeTypeRef.isValid())
        {
            nodeInitView.cstRef = SemaCast::castConstant(sema, castCtx, nodeInitView.cstRef, nodeTypeView.typeRef);
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
