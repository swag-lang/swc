#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Symbol/Match.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/Cast.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void markExplicitUndefined(const std::span<Symbol*>& syms)
    {
        for (auto* s : syms)
            s->addFlag(SymbolFlagsE::ExplicitUndefined);
    }

    void completeConst(Sema& sema, const std::span<Symbol*>& syms, ConstantRef cstRef, TypeRef typeRef)
    {
        auto& ctx = sema.ctx();

        for (auto* s : syms)
        {
            auto& symCst = s->cast<SymbolConstant>();
            symCst.setCstRef(cstRef);
            symCst.setTypeRef(typeRef);
            symCst.setTyped(sema.ctx());
            symCst.setCompleted(ctx);
        }
    }

    void completeVar(Sema& sema, const std::span<Symbol*>& syms, TypeRef typeRef)
    {
        auto& ctx = sema.ctx();

        for (auto* s : syms)
        {
            auto& symVar = s->cast<SymbolVariable>();
            symVar.setTypeRef(typeRef);
            symVar.setTyped(sema.ctx());
            symVar.setCompleted(ctx);
        }
    }

    Result semaPostVarDeclCommon(Sema& sema, const AstNode& owner, TokenRef tokDiag, AstNodeRef nodeInitRef, AstNodeRef nodeTypeRef, bool isConst, bool isLet, const std::span<Symbol*>& syms)
    {
        auto&              ctx = sema.ctx();
        SemaNodeView       nodeInitView(sema, nodeInitRef);
        const SemaNodeView nodeTypeView(sema, nodeTypeRef);

        // Initialized to 'undefined'
        if (nodeInitRef.isValid() && nodeInitView.cstRef == sema.cstMgr().cstUndefined())
        {
            if (isConst)
                return SemaError::raise(sema, DiagnosticId::sema_err_const_missing_init, owner.srcViewRef(), tokDiag);
            if (isLet)
                return SemaError::raise(sema, DiagnosticId::sema_err_let_missing_init, owner.srcViewRef(), tokDiag);
            if (nodeTypeRef.isInvalid())
                return SemaError::raise(sema, DiagnosticId::sema_err_not_type, owner.srcViewRef(), tokDiag);

            markExplicitUndefined(syms);
        }

        // Implicit cast from initializer to the specified type
        if (nodeInitView.typeRef.isValid() && nodeTypeView.typeRef.isValid())
        {
            CastContext castCtx(CastKind::Initialization);
            castCtx.errorNodeRef = nodeInitRef;

            const auto res = Cast::castAllowed(sema, castCtx, nodeInitView.typeRef, nodeTypeView.typeRef);
            if (res != Result::Continue)
            {
                if (res == Result::Stop)
                {
                    auto diag = SemaError::report(sema, castCtx.failure.diagId, castCtx.errorNodeRef);
                    diag.addArgument(Diagnostic::ARG_TYPE, castCtx.failure.srcTypeRef);
                    diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, castCtx.failure.dstTypeRef);

                    CastContext explicitCtx{CastKind::Explicit};
                    explicitCtx.errorNodeRef = nodeInitRef;
                    if (Cast::castAllowed(sema, explicitCtx, nodeInitView.typeRef, nodeTypeView.typeRef) == Result::Continue)
                        diag.addElement(DiagnosticId::sema_note_cast_explicit);

                    diag.report(ctx);
                }

                return res;
            }

            if (nodeInitView.cstRef.isValid())
            {
                ConstantRef newCstRef;
                RESULT_VERIFY(Cast::castConstant(sema, newCstRef, castCtx, nodeInitView.cstRef, nodeTypeView.typeRef));
                sema.setConstant(nodeInitRef, newCstRef);
            }
            else
            {
                Cast::createImplicitCast(sema, nodeTypeView.typeRef, nodeInitRef);
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
                    RESULT_VERIFY(Cast::castConstant(sema, newCstRef, castCtx, newCstRef, newTypeRef));
                }
            }

            nodeInitView.setCstRef(sema, newCstRef);
        }

        if (nodeInitRef.isValid())
            RESULT_VERIFY(SemaCheck::isValue(sema, nodeInitRef));

        if (!sema.curScope().isLocal() && !isConst && nodeInitRef.isValid())
            RESULT_VERIFY(SemaCheck::isConstant(sema, nodeInitRef));

        // Constant
        if (isConst)
        {
            if (nodeInitRef.isInvalid())
                return SemaError::raise(sema, DiagnosticId::sema_err_const_missing_init, owner.srcViewRef(), tokDiag);
            if (nodeInitView.cstRef.isInvalid())
                return SemaError::raiseExprNotConst(sema, nodeInitRef);

            if (nodeTypeRef.isValid() && nodeTypeView.typeRef.isValid())
            {
                CastContext castCtx(CastKind::Initialization);
                castCtx.errorNodeRef = nodeInitRef;
                ConstantRef newCstRef;
                RESULT_VERIFY(Cast::castConstant(sema, newCstRef, castCtx, nodeInitView.cstRef, nodeTypeView.typeRef));
                nodeInitView.setCstRef(sema, newCstRef);
            }

            completeConst(sema, syms, nodeInitView.cstRef, nodeInitView.typeRef);
            return Result::Continue;
        }

        // Variable
        if (isLet && nodeInitRef.isInvalid())
            return SemaError::raise(sema, DiagnosticId::sema_err_let_missing_init, owner.srcViewRef(), tokDiag);

        completeVar(sema, syms, nodeTypeView.typeRef.isValid() ? nodeTypeView.typeRef : nodeInitView.typeRef);
        return Result::Continue;
    }
}

Result AstVarDecl::semaPreDecl(Sema& sema) const
{
    if (hasFlag(AstVarDeclFlagsE::Const))
        SemaHelpers::registerSymbol<SymbolConstant>(sema, *this, tokNameRef);
    else
    {
        SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokNameRef);
        if (hasFlag(AstVarDeclFlagsE::Let))
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
    return Match::ghosting(sema, sym);
}

Result AstVarDecl::semaPostNode(Sema& sema) const
{
    Symbol& sym   = sema.symbolOf(sema.curNodeRef());
    Symbol* one[] = {&sym};
    return semaPostVarDeclCommon(sema, *this, tokNameRef, nodeInitRef, nodeTypeRef, hasFlag(AstVarDeclFlagsE::Const), hasFlag(AstVarDeclFlagsE::Let), std::span<Symbol*>{one});
}

Result AstVarDeclNameList::semaPreDecl(Sema& sema) const
{
    auto& ctx = sema.ctx();

    SmallVector<TokenRef> tokNames;
    sema.ast().tokens(tokNames, spanNamesRef);

    SmallVector<const Symbol*> symbols;
    const SymbolFlags          symFlags  = sema.frame().flagsForCurrentAccess();
    SymbolMap*                 symbolMap = SemaFrame::currentSymMap(sema);

    for (const auto& tokNameRef : tokNames)
    {
        const IdentifierRef idRef = sema.idMgr().addIdentifier(ctx, srcViewRef(), tokNameRef);
        Symbol*             sym;

        if (hasFlag(AstVarDeclFlagsE::Const))
            sym = Symbol::make<SymbolConstant>(ctx, this, tokNameRef, idRef, symFlags);
        else
        {
            sym = Symbol::make<SymbolVariable>(ctx, this, tokNameRef, idRef, symFlags);
            if (hasFlag(AstVarDeclFlagsE::Let))
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
        if (!sema.hasSymbolList(sema.curNodeRef()))
            semaPreDecl(sema);
        const auto symbols = sema.getSymbolList(sema.curNodeRef());
        for (const auto sym : symbols)
        {
            sym->registerAttributes(sema);
            sym->setDeclared(sema.ctx());
        }
    }

    const auto symbols = sema.getSymbolList(sema.curNodeRef());
    for (const auto sym : symbols)
        RESULT_VERIFY(Match::ghosting(sema, *sym));

    return Result::Continue;
}

Result AstVarDeclNameList::semaPostNode(Sema& sema) const
{
    const auto symbols = sema.getSymbolList(sema.curNodeRef());
    return semaPostVarDeclCommon(sema, *this, tokRef(), nodeInitRef, nodeTypeRef, hasFlag(AstVarDeclFlagsE::Const), hasFlag(AstVarDeclFlagsE::Let), symbols);
}

SWC_END_NAMESPACE();
