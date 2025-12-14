#include "pch.h"
#include "Helpers/SemaError.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisit.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Helpers/SemaNodeView.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/SemaCast.h"
#include "Symbol/IdentifierManager.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstVarDecl::semaPostNode(Sema& sema) const
{
    SemaNodeView       nodeInitView(sema, nodeInitRef);
    const SemaNodeView nodeTypeView(sema, nodeTypeRef);

    if (nodeInitView.typeRef.isValid() && nodeTypeView.typeRef.isValid())
    {
        CastContext castCtx(CastKind::Implicit);
        castCtx.errorNodeRef = nodeInitRef;

        if (!SemaCast::analyseCast(sema,
                                  castCtx,
                                  nodeInitView.typeRef,
                                  nodeTypeView.typeRef,
                                  CastMode::Check,
                                  ConstantRef::invalid(),
                                  nullptr))
        {
            const CastFailure& failure = castCtx.failure;

            // Primary, context-specific diagnostic
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_var_init_type_mismatch, castCtx.errorNodeRef);
            diag.addArgument(Diagnostic::ARG_TYPE, failure.srcTypeRef);
            diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, failure.dstTypeRef);

            // Add the underlying reason as a note (format like your previous code)
            if (failure.diagId != DiagnosticId::None)
                diag.addNote(failure.diagId);

            // Explicit cast works hint
            CastContext explicitCtx = castCtx;
            explicitCtx.kind        = CastKind::Explicit;

            if (SemaCast::analyseCast(sema,
                                     explicitCtx,
                                     nodeInitView.typeRef,
                                     nodeTypeView.typeRef,
                                     CastMode::Check,
                                     ConstantRef::invalid(),
                                     nullptr))
            {
                diag.addElement(DiagnosticId::sema_note_cast_explicit);
            }

            diag.report(sema.ctx());
            return AstVisitStepResult::Stop;
        }
    }

    // Get the destination symbolMap
    const IdentifierRef idRef     = sema.idMgr().addIdentifier(sema.ctx(), srcViewRef(), tokNameRef);
    SymbolMap*          symbolMap = nullptr;
    const SymbolAccess  access    = sema.frame().currentAccess.value_or(sema.frame().defaultAccess);
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

        if (nodeInitView.cstRef.isInvalid())
        {
            SemaError::raiseExprNotConst(sema, nodeInitRef);
            return AstVisitStepResult::Stop;
        }

        if (nodeTypeRef.isValid())
        {
            CastContext castCtx(CastKind::Implicit);
            castCtx.errorNodeRef = nodeInitRef;

            // castConstant now takes CastContext& (mutable) and uses castCtx.failure internally.
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
