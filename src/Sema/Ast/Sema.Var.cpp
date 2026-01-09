#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Symbol/SemaMatch.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/CastContext.h"
#include "Sema/Type/SemaCast.h"

SWC_BEGIN_NAMESPACE();

Result AstVarDecl::semaPreDecl(Sema& sema) const
{
    if (hasParserFlag(Const))
        SemaHelpers::registerSymbol<SymbolConstant>(sema, *this, tokNameRef);
    else
    {
        SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokNameRef);
        if (hasParserFlag(Let))
        {
            SymbolVariable& symVar = sema.symbolOf(sema.curNodeRef()).cast<SymbolVariable>();
            symVar.addVarFlag(SymbolVariableFlagsE::Let);
        }
    }

    return Result::SkipChildren;
}

Result AstVarDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);
    const Symbol& sym = sema.symbolOf(sema.curNodeRef());
    return SemaMatch::ghosting(sema, sym);
}

Result AstVarDecl::semaPostNode(Sema& sema) const
{
    auto&              ctx = sema.ctx();
    SemaNodeView       nodeInitView(sema, nodeInitRef);
    const SemaNodeView nodeTypeView(sema, nodeTypeRef);
    bool               isConst = hasParserFlag(Const);
    bool               isLet   = hasParserFlag(Let);

    // Initialized to 'undefined'
    if (nodeInitRef.isValid() && nodeInitView.cstRef == sema.cstMgr().cstUndefined())
    {
        if (hasParserFlag(Const))
            return SemaError::raise(sema, DiagnosticId::sema_err_const_missing_init, srcViewRef(), tokNameRef);
        if (hasParserFlag(Let))
            return SemaError::raise(sema, DiagnosticId::sema_err_let_missing_init, srcViewRef(), tokNameRef);
        if (nodeTypeRef.isInvalid())
            return SemaError::raise(sema, DiagnosticId::sema_err_not_type, srcViewRef(), tokNameRef);

        Symbol& sym = sema.symbolOf(sema.curNodeRef());
        sym.addFlag(SymbolFlagsE::ExplicitUndefined);
    }

    // Implicit cast from initializer to the specified type
    if (nodeInitView.typeRef.isValid() && nodeTypeView.typeRef.isValid())
    {
        CastContext castCtx(CastKind::Initialization);
        castCtx.errorNodeRef = nodeInitRef;

        const auto res = SemaCast::castAllowed(sema, castCtx, nodeInitView.typeRef, nodeTypeView.typeRef);
        if (res != Result::Continue)
        {
            if (res == Result::Stop)
            {
                // Primary, context-specific diagnostic
                auto diag = SemaError::report(sema, castCtx.failure.diagId, castCtx.errorNodeRef);
                diag.addArgument(Diagnostic::ARG_TYPE, castCtx.failure.srcTypeRef);
                diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, castCtx.failure.dstTypeRef);

                // Explicit cast works hint
                CastContext explicitCtx{CastKind::Explicit};
                explicitCtx.errorNodeRef = nodeInitRef;
                if (SemaCast::castAllowed(sema, explicitCtx, nodeInitView.typeRef, nodeTypeView.typeRef) == Result::Continue)
                    diag.addElement(DiagnosticId::sema_note_cast_explicit);

                diag.report(ctx);
            }

            return res;
        }

        // Convert init constant to the right type
        if (nodeInitView.cstRef.isValid())
        {
            ConstantRef newCstRef;
            RESULT_VERIFY(SemaCast::castConstant(sema, newCstRef, castCtx, nodeInitView.cstRef, nodeTypeView.typeRef));
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
        ConstantRef newCstRef;
        RESULT_VERIFY(ctx.cstMgr().concretizeConstant(sema, newCstRef, nodeInitView.nodeRef, nodeInitView.cstRef, TypeInfo::Sign::Unknown));

        // Be sure it's at least 32 bits for an integer
        const ConstantValue& cst = sema.cstMgr().get(newCstRef);
        if (cst.type(ctx).isInt())
        {
            const TypeRef newTypeRef = sema.typeMgr().promote(cst.typeRef(), cst.typeRef(), true);
            if (newTypeRef != cst.typeRef())
            {
                CastContext castCtx(CastKind::Implicit);
                castCtx.errorNodeRef = nodeInitRef;
                RESULT_VERIFY(SemaCast::castConstant(sema, newCstRef, castCtx, newCstRef, newTypeRef));
            }
        }

        nodeInitView.setCstRef(sema, newCstRef);
    }

    // Be sure the initialization expression has a value
    if (nodeInitRef.isValid())
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeInitRef));

    // Global variable must be initialized to a constexpr
    if (!sema.curScope().isLocal() && !isConst && nodeInitRef.isValid())
    {
        RESULT_VERIFY(SemaCheck::isConstant(sema, nodeInitRef));
    }

    // Constant
    if (isConst)
    {
        if (nodeInitRef.isInvalid())
            return SemaError::raise(sema, DiagnosticId::sema_err_const_missing_init, srcViewRef(), tokNameRef);
        if (nodeInitView.cstRef.isInvalid())
            return SemaError::raiseExprNotConst(sema, nodeInitRef);

        if (nodeTypeRef.isValid() && nodeTypeView.typeRef.isValid())
        {
            CastContext castCtx(CastKind::Initialization);
            castCtx.errorNodeRef = nodeInitRef;
            ConstantRef newCstRef;
            RESULT_VERIFY(SemaCast::castConstant(sema, newCstRef, castCtx, nodeInitView.cstRef, nodeTypeView.typeRef));
            nodeInitView.setCstRef(sema, newCstRef);
        }

        SymbolConstant& symCst = sema.symbolOf(sema.curNodeRef()).cast<SymbolConstant>();
        symCst.setCstRef(nodeInitView.cstRef);
        symCst.setTypeRef(nodeInitView.typeRef);
        symCst.setTyped(sema.ctx());
        symCst.setCompleted(ctx);
        return Result::Continue;
    }

    // Variable
    if (isLet && nodeInitRef.isInvalid())
        return SemaError::raise(sema, DiagnosticId::sema_err_let_missing_init, srcViewRef(), tokNameRef);

    SymbolVariable& symVar = sema.symbolOf(sema.curNodeRef()).cast<SymbolVariable>();
    symVar.setTypeRef(nodeTypeView.typeRef.isValid() ? nodeTypeView.typeRef : nodeInitView.typeRef);
    symVar.setTyped(sema.ctx());
    symVar.setCompleted(ctx);
    return Result::Continue;
}

Result AstVarDeclNameList::semaPreDecl(Sema& sema) const
{
    auto& ctx = sema.ctx();

    SmallVector<TokenRef> tokNames;
    sema.ast().tokens(tokNames, spanNamesRef);

    SmallVector<const Symbol*> symbols;
    const SymbolFlags          flags     = sema.frame().flagsForCurrentAccess();
    SymbolMap*                 symbolMap = SemaFrame::currentSymMap(sema);

    for (const auto& tokNameRef : tokNames)
    {
        const IdentifierRef idRef = sema.idMgr().addIdentifier(ctx, srcViewRef(), tokNameRef);
        Symbol*             sym;

        if (hasParserFlag(AstVarDecl::Const))
            sym = Symbol::make<SymbolConstant>(ctx, this, tokNameRef, idRef, flags);
        else
        {
            sym = Symbol::make<SymbolVariable>(ctx, this, tokNameRef, idRef, flags);
            if (hasParserFlag(AstVarDecl::Let))
                sym->cast<SymbolVariable>().addVarFlag(SymbolVariableFlagsE::Let);
        }

        symbolMap->addSymbol(ctx, sym, true);
        sym->registerCompilerIf(sema);
        symbols.push_back(sym);

        if (const auto symStruct = symbolMap->safeCast<SymbolStruct>())
        {
            if (sym->isVariable())
                symStruct->addField(reinterpret_cast<SymbolVariable*>(sym));
        }

        if (const auto symAttr = symbolMap->safeCast<SymbolAttribute>())
        {
            if (sym->isVariable())
                symAttr->addParameter(reinterpret_cast<SymbolVariable*>(sym));
        }
    }

    sema.semaInfo().setSymbols(sema.curNodeRef(), symbols.span());
    return Result::SkipChildren;
}

Result AstVarDeclNameList::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
    {
        if (!sema.hasSymbols(sema.curNodeRef()))
            semaPreDecl(sema);
        const auto symbols = sema.getSymbols(sema.curNodeRef());
        for (const auto sym : symbols)
        {
            const_cast<Symbol*>(sym)->registerAttributes(sema);
            const_cast<Symbol*>(sym)->setDeclared(sema.ctx());
        }
    }

    const auto symbols = sema.getSymbols(sema.curNodeRef());
    for (const auto sym : symbols)
    {
        RESULT_VERIFY(SemaMatch::ghosting(sema, *sym));
    }

    return Result::Continue;
}

Result AstVarDeclNameList::semaPostNode(Sema& sema) const
{
    auto&              ctx = sema.ctx();
    SemaNodeView       nodeInitView(sema, nodeInitRef);
    const SemaNodeView nodeTypeView(sema, nodeTypeRef);
    bool               isConst = hasParserFlag(AstVarDecl::Const);
    bool               isLet   = hasParserFlag(AstVarDecl::Let);

    // Initialized to 'undefined'
    if (nodeInitRef.isValid() && nodeInitView.cstRef == sema.cstMgr().cstUndefined())
    {
        if (hasParserFlag(AstVarDecl::Const))
            return SemaError::raise(sema, DiagnosticId::sema_err_const_missing_init, srcViewRef(), tokRef());
        if (hasParserFlag(AstVarDecl::Let))
            return SemaError::raise(sema, DiagnosticId::sema_err_let_missing_init, srcViewRef(), tokRef());
        if (nodeTypeRef.isInvalid())
            return SemaError::raise(sema, DiagnosticId::sema_err_not_type, srcViewRef(), tokRef());

        const auto symbols = sema.getSymbols(sema.curNodeRef());
        for (const auto sym : symbols)
            const_cast<Symbol*>(sym)->addFlag(SymbolFlagsE::ExplicitUndefined);
    }

    // Implicit cast from initializer to the specified type
    if (nodeInitView.typeRef.isValid() && nodeTypeView.typeRef.isValid())
    {
        CastContext castCtx(CastKind::Initialization);
        castCtx.errorNodeRef = nodeInitRef;

        const auto res = SemaCast::castAllowed(sema, castCtx, nodeInitView.typeRef, nodeTypeView.typeRef);
        if (res != Result::Continue)
        {
            if (res == Result::Stop)
            {
                auto diag = SemaError::report(sema, castCtx.failure.diagId, castCtx.errorNodeRef);
                diag.addArgument(Diagnostic::ARG_TYPE, castCtx.failure.srcTypeRef);
                diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, castCtx.failure.dstTypeRef);

                CastContext explicitCtx{CastKind::Explicit};
                explicitCtx.errorNodeRef = nodeInitRef;
                if (SemaCast::castAllowed(sema, explicitCtx, nodeInitView.typeRef, nodeTypeView.typeRef) == Result::Continue)
                    diag.addElement(DiagnosticId::sema_note_cast_explicit);

                diag.report(ctx);
            }

            return res;
        }

        if (nodeInitView.cstRef.isValid())
        {
            ConstantRef newCstRef;
            RESULT_VERIFY(SemaCast::castConstant(sema, newCstRef, castCtx, nodeInitView.cstRef, nodeTypeView.typeRef));
            sema.setConstant(nodeInitRef, newCstRef);
        }
        else
        {
            SemaCast::createImplicitCast(sema, nodeTypeView.typeRef, nodeInitRef);
        }
    }
    else if (nodeInitView.cstRef.isValid())
    {
        ConstantRef newCstRef;
        RESULT_VERIFY(ctx.cstMgr().concretizeConstant(sema, newCstRef, nodeInitView.nodeRef, nodeInitView.cstRef, TypeInfo::Sign::Unknown));

        const ConstantValue& cst = sema.cstMgr().get(newCstRef);
        if (cst.type(ctx).isInt())
        {
            const TypeRef newTypeRef = sema.typeMgr().promote(cst.typeRef(), cst.typeRef(), true);
            if (newTypeRef != cst.typeRef())
            {
                CastContext castCtx(CastKind::Implicit);
                castCtx.errorNodeRef = nodeInitRef;
                RESULT_VERIFY(SemaCast::castConstant(sema, newCstRef, castCtx, newCstRef, newTypeRef));
            }
        }

        nodeInitView.setCstRef(sema, newCstRef);
    }

    if (nodeInitRef.isValid())
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeInitRef));

    if (!sema.curScope().isLocal() && !isConst && nodeInitRef.isValid())
    {
        RESULT_VERIFY(SemaCheck::isConstant(sema, nodeInitRef));
    }

    const auto symbols = sema.getSymbols(sema.curNodeRef());

    // Constant
    if (isConst)
    {
        if (nodeInitRef.isInvalid())
            return SemaError::raise(sema, DiagnosticId::sema_err_const_missing_init, srcViewRef(), tokRef());
        if (nodeInitView.cstRef.isInvalid())
            return SemaError::raiseExprNotConst(sema, nodeInitRef);

        if (nodeTypeRef.isValid() && nodeTypeView.typeRef.isValid())
        {
            CastContext castCtx(CastKind::Initialization);
            castCtx.errorNodeRef = nodeInitRef;
            ConstantRef newCstRef;
            RESULT_VERIFY(SemaCast::castConstant(sema, newCstRef, castCtx, nodeInitView.cstRef, nodeTypeView.typeRef));
            nodeInitView.setCstRef(sema, newCstRef);
        }

        for (const auto sym : symbols)
        {
            SymbolConstant& symCst = const_cast<Symbol*>(sym)->cast<SymbolConstant>();
            symCst.setCstRef(nodeInitView.cstRef);
            symCst.setTypeRef(nodeInitView.typeRef);
            symCst.setTyped(sema.ctx());
            symCst.setCompleted(ctx);
        }
        return Result::Continue;
    }

    // Variable
    if (isLet && nodeInitRef.isInvalid())
        return SemaError::raise(sema, DiagnosticId::sema_err_let_missing_init, srcViewRef(), tokRef());

    for (const auto sym : symbols)
    {
        SymbolVariable& symVar = const_cast<Symbol*>(sym)->cast<SymbolVariable>();
        symVar.setTypeRef(nodeTypeView.typeRef.isValid() ? nodeTypeView.typeRef : nodeInitView.typeRef);
        symVar.setTyped(sema.ctx());
        symVar.setCompleted(ctx);
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
