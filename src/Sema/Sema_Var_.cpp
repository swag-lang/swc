#include "pch.h"
#include "Helpers/SemaError.h"
#include "Helpers/SemaMatch.h"
#include "Parser/AstNodes.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Helpers/SemaFrame.h"
#include "Sema/Helpers/SemaNodeView.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/IdentifierManager.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/CastContext.h"
#include "Sema/Type/SemaCast.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstVarDecl::semaPreDecl(Sema& sema) const
{
    auto&               ctx   = sema.ctx();
    const IdentifierRef idRef = sema.idMgr().addIdentifier(ctx, srcViewRef(), tokNameRef);

    SymbolFlags        flags  = SymbolFlagsE::Zero;
    const SymbolAccess access = SemaFrame::currentAccess(sema);
    if (access == SymbolAccess::Public)
        flags.add(SymbolFlagsE::Public);
    SymbolMap* symbolMap = SemaFrame::currentSymMap(sema);

    if (hasParserFlag(Const))
    {
        SymbolConstant* symCst = Symbol::make<SymbolConstant>(ctx, srcViewRef(), tokNameRef, idRef, flags);
        if (!symbolMap->addSymbol(ctx, symCst, true))
            return AstVisitStepResult::Stop;
        symCst->setContext(sema);
        sema.setSymbol(sema.curNodeRef(), symCst);
    }
    else
    {
        SymbolVariable* symVar = Symbol::make<SymbolVariable>(ctx, srcViewRef(), tokNameRef, idRef, flags);
        if (!symbolMap->addSymbol(ctx, symVar, true))
            return AstVisitStepResult::Stop;
        symVar->setContext(sema);
        sema.setSymbol(sema.curNodeRef(), symVar);
    }

    return AstVisitStepResult::SkipChildren;
}

void AstVarDecl::semaEnterNode(Sema& sema)
{
    Symbol& sym = sema.symbolOf(sema.curNodeRef());
    sym.setDeclared(sema.ctx());
}

AstVisitStepResult AstVarDecl::semaPreNode(Sema& sema)
{
    const Symbol& sym = sema.symbolOf(sema.curNodeRef());
    return SemaMatch::ghosting(sema, sym);
}

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
            ConstantRef newCstRef = SemaCast::castConstant(sema, castCtx, nodeInitView.cstRef, nodeTypeView.typeRef);
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
        const ConstantRef newCstRef = ctx.cstMgr().concretizeConstant(sema, nodeInitView.nodeRef, nodeInitView.cstRef, TypeInfo::Sign::Unknown);
        if (newCstRef.isInvalid())
            return AstVisitStepResult::Stop;
        nodeInitView.setCstRef(sema, newCstRef);
    }

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
            castCtx.errorNodeRef        = nodeInitRef;
            const ConstantRef newCstRef = SemaCast::castConstant(sema, castCtx, nodeInitView.cstRef, nodeTypeView.typeRef);
            if (newCstRef.isInvalid())
                return AstVisitStepResult::Stop;
            nodeInitView.setCstRef(sema, newCstRef);
        }

        SymbolConstant& symCst = sema.symbolOf(sema.curNodeRef()).cast<SymbolConstant>();
        symCst.setCstRef(nodeInitView.cstRef);
        symCst.setTypeRef(nodeInitView.typeRef);
        symCst.setComplete(ctx);
    }

    // Variable
    else
    {
        SymbolVariable& symVar = sema.symbolOf(sema.curNodeRef()).cast<SymbolVariable>();
        symVar.setTypeRef(nodeTypeView.typeRef.isValid() ? nodeTypeView.typeRef : nodeInitView.typeRef);
        symVar.setComplete(ctx);
    }

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
