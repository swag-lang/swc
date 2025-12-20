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
#include "Type/CastContext.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstVarDecl::semaPostNode(Sema& sema) const
{
    auto&              ctx = sema.ctx();
    SemaNodeView       nodeInitView(sema, nodeInitRef);
    const SemaNodeView nodeTypeView(sema, nodeTypeRef);

    // Implicit cast from initializer to the specified type
    if (nodeInitView.typeRef.isValid() && nodeTypeView.typeRef.isValid())
    {
        CastContext castCtx(CastKind::Implicit);
        castCtx.errorNodeRef = nodeInitRef;

        if (!SemaCast::castAllowed(sema, castCtx, nodeInitView.typeRef, nodeTypeView.typeRef))
        {
            // Primary, context-specific diagnostic
            auto diag = SemaError::report(sema, castCtx.failure.diagId, castCtx.errorNodeRef);
            diag.addArgument(Diagnostic::ARG_TYPE, castCtx.failure.srcTypeRef);
            diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, castCtx.failure.dstTypeRef);

            // Explicit cast works hint
            CastContext explicitCtx{CastKind::Explicit};
            castCtx.errorNodeRef = nodeInitRef;
            if (SemaCast::castAllowed(sema, explicitCtx, nodeInitView.typeRef, nodeTypeView.typeRef))
                diag.addElement(DiagnosticId::sema_note_cast_explicit);

            diag.report(ctx);
            return AstVisitStepResult::Stop;
        }

        // Convert init constant to the right type
        if (nodeInitView.cstRef.isValid())
        {
            auto newCstRef = SemaCast::castConstant(sema, castCtx, nodeInitView.cstRef, nodeTypeView.typeRef);
            if (newCstRef.isInvalid())
                return AstVisitStepResult::Stop;
            sema.setConstant(nodeInitRef, newCstRef);
        }

        // Otherwise creates an implicit cast
        else
        {
            SemaCast::createImplicitCast(sema, nodeTypeView.typeRef, nodeInitRef);
        }
    }
    else if (nodeInitView.cstRef.isValid())
    {
        nodeInitView.cstRef = ctx.cstMgr().concretizeConstant(sema, nodeInitView.nodeRef, nodeInitView.cstRef, TypeInfo::Sign::Unknown);
        if (nodeInitView.cstRef.isInvalid())
            return AstVisitStepResult::Stop;
        nodeInitView.typeRef = ctx.cstMgr().get(nodeInitView.cstRef).typeRef();
    }

    // Register name
    const IdentifierRef idRef = sema.idMgr().addIdentifier(ctx, srcViewRef(), tokNameRef);

    // Get the destination symbolMap
    SymbolFlags        flags     = SymbolFlagsE::Zero;
    SymbolMap*         symbolMap = sema.curSymMap();
    const SymbolAccess access    = sema.frame().currentAccess.value_or(sema.frame().defaultAccess);
    if (access == SymbolAccess::Internal)
        symbolMap = &sema.semaInfo().fileNamespace();
    else if (access == SymbolAccess::Public)
        flags.add(SymbolFlagsE::Public);

    // Constant
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

        if (nodeTypeRef.isValid() && nodeTypeView.typeRef.isValid())
        {
            CastContext castCtx(CastKind::Implicit);
            castCtx.errorNodeRef = nodeInitRef;
            nodeInitView.cstRef  = SemaCast::castConstant(sema, castCtx, nodeInitView.cstRef, nodeTypeView.typeRef);
            if (nodeInitView.cstRef.isInvalid())
                return AstVisitStepResult::Stop;
        }

        auto* sym = sema.compiler().allocate<SymbolConstant>(ctx, this, idRef, nodeInitView.cstRef, flags);
        symbolMap->addSymbol(ctx, sym);
        return AstVisitStepResult::Continue;
    }

    TypeRef typeRef = nodeTypeView.typeRef;
    if (typeRef.isInvalid())
        typeRef = nodeInitView.typeRef;

    auto* sym = sema.compiler().allocate<SymbolVariable>(ctx, this, idRef, typeRef, flags);
    symbolMap->addSymbol(ctx, sym);
    sema.setSymbol(sema.curNodeRef(), sym);

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
