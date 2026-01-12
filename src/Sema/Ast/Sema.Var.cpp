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
            RESULT_VERIFY(Cast::cast(sema, nodeInitView, nodeTypeView.typeRef, CastKind::Initialization));
        }
        else if (nodeInitView.cstRef.isValid())
        {
            ConstantRef newCstRef;
            RESULT_VERIFY(ctx.cstMgr().concretizeConstant(sema, newCstRef, nodeInitView.nodeRef, nodeInitView.cstRef, TypeInfo::Sign::Unknown));
            nodeInitView.setCstRef(sema, newCstRef);

            if (nodeInitView.type->isInt())
            {
                const TypeRef newTypeRef = sema.typeMgr().promote(nodeInitView.typeRef, nodeInitView.typeRef, true);
                RESULT_VERIFY(Cast::cast(sema, nodeInitView, newTypeRef, CastKind::Implicit));
            }
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

            completeConst(sema, syms, nodeInitView.cstRef, nodeInitView.typeRef);
            return Result::Continue;
        }

        // Variable
        if (isLet && nodeInitRef.isInvalid())
            return SemaError::raise(sema, DiagnosticId::sema_err_let_missing_init, owner.srcViewRef(), tokDiag);

        completeVar(sema, syms, nodeTypeView.typeRef.isValid() ? nodeTypeView.typeRef : nodeInitView.typeRef);

        if (nodeInitRef.isValid())
        {
            for (auto* s : syms)
            {
                if (auto symVar = s->safeCast<SymbolVariable>())
                    symVar->addVarFlag(SymbolVariableFlagsE::Initialized);
            }
        }

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
    for (const auto& tokNameRef : tokNames)
    {
        if (hasFlag(AstVarDeclFlagsE::Const))
        {
            Symbol& sym = SemaHelpers::registerSymbol<SymbolConstant>(sema, *this, tokNameRef);
            symbols.push_back(&sym);
        }
        else
        {
            Symbol& sym = SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokNameRef);
            symbols.push_back(&sym);
            if (hasFlag(AstVarDeclFlagsE::Let))
            {
                SymbolVariable& symVar = sema.symbolOf(sema.curNodeRef()).cast<SymbolVariable>();
                symVar.addVarFlag(SymbolVariableFlagsE::Let);
            }
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
