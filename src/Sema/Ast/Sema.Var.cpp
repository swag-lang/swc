#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Report/DiagnosticDef.h"
#include "Sema/Cast/Cast.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Match/Match.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void markExplicitUndefined(const std::span<Symbol*>& symbols)
    {
        for (auto* s : symbols)
        {
            if (const auto symVar = s->safeCast<SymbolVariable>())
                symVar->addExtraFlag(SymbolVariableFlagsE::ExplicitUndefined);
        }
    }

    void completeConst(Sema& sema, const std::span<Symbol*>& symbols, ConstantRef cstRef, TypeRef typeRef)
    {
        for (auto* s : symbols)
        {
            auto& symCst = s->cast<SymbolConstant>();
            symCst.setCstRef(cstRef);
            symCst.setTypeRef(typeRef);
            symCst.setTyped(sema.ctx());
            symCst.setCompleted(sema.ctx());
        }
    }

    void completeVar(Sema& sema, const std::span<Symbol*>& symbols, TypeRef typeRef)
    {
        for (auto* s : symbols)
        {
            auto& symVar = s->cast<SymbolVariable>();
            symVar.setTypeRef(typeRef);
            symVar.setTyped(sema.ctx());
            symVar.setCompleted(sema.ctx());
        }
    }

    Result semaPostVarDeclCommon(Sema&                       sema,
                                 const AstNode&              owner,
                                 TokenRef                    tokDiag,
                                 AstNodeRef                  nodeInitRef,
                                 AstNodeRef                  nodeTypeRef,
                                 EnumFlags<AstVarDeclFlagsE> flags,
                                 const std::span<Symbol*>&   symbols)
    {
        auto&              ctx = sema.ctx();
        SemaNodeView       nodeInitView(sema, nodeInitRef);
        const SemaNodeView nodeTypeView(sema, nodeTypeRef);

        const bool isConst     = flags.has(AstVarDeclFlagsE::Const);
        const bool isLet       = flags.has(AstVarDeclFlagsE::Let);
        const bool isParameter = flags.has(AstVarDeclFlagsE::Parameter);
        const bool isUsing     = flags.has(AstVarDeclFlagsE::Using);

        // Initialized to 'undefined'
        if (nodeInitRef.isValid() && nodeInitView.cstRef == sema.cstMgr().cstUndefined())
        {
            if (isConst)
                return SemaError::raise(sema, DiagnosticId::sema_err_const_missing_init, owner.srcViewRef(), tokDiag);
            if (isLet)
                return SemaError::raise(sema, DiagnosticId::sema_err_let_missing_init, owner.srcViewRef(), tokDiag);
            if (nodeTypeRef.isInvalid())
                return SemaError::raise(sema, DiagnosticId::sema_err_not_type, owner.srcViewRef(), tokDiag);

            if (!isParameter && nodeTypeView.typeRef.isValid() && nodeTypeView.type->isReference())
                return SemaError::raise(sema, DiagnosticId::sema_err_ref_missing_init, owner.srcViewRef(), tokDiag);

            markExplicitUndefined(symbols);
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
            RESULT_VERIFY(SemaCheck::isValue(sema, nodeInitView.nodeRef));

        if (!sema.curScope().isLocal() && !sema.curScope().isParameters() && !isConst && nodeInitRef.isValid())
            RESULT_VERIFY(SemaCheck::isConstant(sema, nodeInitView.nodeRef));

        const TypeRef finalTypeRef = nodeTypeView.typeRef.isValid() ? nodeTypeView.typeRef : nodeInitView.typeRef;
        const bool    isRefType    = finalTypeRef.isValid() && sema.typeMgr().get(finalTypeRef).isReference();
        if (isConst && isRefType)
            return SemaError::raise(sema, DiagnosticId::sema_err_const_ref_type, owner.srcViewRef(), tokDiag);

        if (isUsing && finalTypeRef.isValid())
        {
            const TypeInfo& ultimateType = sema.typeMgr().get(finalTypeRef);
            if (!ultimateType.isStruct())
            {
                if (!ultimateType.isAnyPointer() || !sema.typeMgr().get(ultimateType.typeRef()).isStruct())
                {
                    auto diag = SemaError::report(sema, DiagnosticId::sema_err_using_member_type, owner.srcViewRef(), tokDiag);
                    diag.addArgument(Diagnostic::ARG_TYPE, finalTypeRef);
                    diag.report(ctx);
                    return Result::Error;
                }
            }
        }

        // Constant
        if (isConst)
        {
            if (nodeInitRef.isInvalid())
                return SemaError::raise(sema, DiagnosticId::sema_err_const_missing_init, owner.srcViewRef(), tokDiag);
            if (nodeInitView.cstRef.isInvalid())
                return SemaError::raiseExprNotConst(sema, nodeInitView.nodeRef);

            completeConst(sema, symbols, nodeInitView.cstRef, nodeInitView.typeRef);
            return Result::Continue;
        }

        // Variable
        if (isLet && nodeInitRef.isInvalid())
            return SemaError::raise(sema, DiagnosticId::sema_err_let_missing_init, owner.srcViewRef(), tokDiag);

        if (!isLet && !isParameter && isRefType && nodeInitRef.isInvalid())
            return SemaError::raise(sema, DiagnosticId::sema_err_ref_missing_init, owner.srcViewRef(), tokDiag);

        completeVar(sema, symbols, nodeTypeView.typeRef.isValid() ? nodeTypeView.typeRef : nodeInitView.typeRef);

        if (nodeInitRef.isValid())
        {
            for (auto* s : symbols)
            {
                if (const auto symVar = s->safeCast<SymbolVariable>())
                    symVar->addExtraFlag(SymbolVariableFlagsE::Initialized);
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
            symVar.addExtraFlag(SymbolVariableFlagsE::Let);
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

Result AstVarDecl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeTypeRef && nodeInitRef.isValid())
    {
        const SemaNodeView nodeTypeView(sema, nodeTypeRef);
        auto               frame = sema.frame();
        frame.pushBindingType(nodeTypeView.typeRef);
        sema.pushFrameAutoPopOnPostChild(frame, nodeInitRef);
    }

    return Result::Continue;
}

Result AstVarDecl::semaPostNode(Sema& sema) const
{
    Symbol& sym   = sema.symbolOf(sema.curNodeRef());
    Symbol* one[] = {&sym};
    return semaPostVarDeclCommon(sema, *this, tokNameRef, nodeInitRef, nodeTypeRef, flags(), std::span<Symbol*>{one});
}

Result AstVarDeclNameList::semaPreDecl(Sema& sema) const
{
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
                symVar.addExtraFlag(SymbolVariableFlagsE::Let);
            }
        }
    }

    sema.setSymbolList(sema.curNodeRef(), symbols.span());
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
    {
        RESULT_VERIFY(Match::ghosting(sema, *sym));
    }

    return Result::Continue;
}

Result AstVarDeclNameList::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeTypeRef && nodeInitRef.isValid())
    {
        const SemaNodeView nodeTypeView(sema, nodeTypeRef);
        auto               frame = sema.frame();
        frame.pushBindingType(nodeTypeView.typeRef);
        sema.pushFrameAutoPopOnPostChild(frame, nodeInitRef);
    }

    return Result::Continue;
}

Result AstVarDeclNameList::semaPostNode(Sema& sema) const
{
    const auto symbols = sema.getSymbolList(sema.curNodeRef());
    return semaPostVarDeclCommon(sema, *this, tokRef(), nodeInitRef, nodeTypeRef, flags(), symbols);
}

Result AstVarDeclDecomposition::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeInitView(sema, nodeInitRef);
    if (!nodeInitView.type->isStruct())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_not_struct, nodeInitView.nodeRef);
        diag.addArgument(Diagnostic::ARG_TYPE, nodeInitView.typeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    const SymbolStruct& symStruct = nodeInitView.type->symStruct();
    const auto&         fields    = symStruct.fields();

    SmallVector<TokenRef> tokNames;
    sema.ast().tokens(tokNames, spanNamesRef);

    if (tokNames.size() > fields.size())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_too_many_names, nodeRef(sema.ast()));
        diag.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(fields.size()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    if (tokNames.size() < fields.size())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_decomposition_not_enough_names, nodeRef(sema.ast()));
        diag.addArgument(Diagnostic::ARG_COUNT, static_cast<uint32_t>(fields.size()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    SmallVector<Symbol*> symbols;
    for (size_t i = 0; i < tokNames.size(); i++)
    {
        const auto& tokNameRef = tokNames[i];
        if (tokNameRef.isInvalid())
            continue;

        SymbolVariable& sym = SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokNameRef);
        if (hasFlag(AstVarDeclFlagsE::Let))
            sym.addExtraFlag(SymbolVariableFlagsE::Let);
        sym.setDeclared(sema.ctx());

        symbols.push_back(&sym);

        const SymbolVariable* field = fields[i];
        sym.setTypeRef(field->typeRef());
        sym.setTyped(sema.ctx());
        sym.setCompleted(sema.ctx());

        RESULT_VERIFY(Match::ghosting(sema, sym));
    }

    sema.setSymbolList(sema.curNodeRef(), symbols.span());
    return semaPostVarDeclCommon(sema, *this, tokRef(), nodeInitRef, AstNodeRef::invalid(), flags(), symbols.span());
}

SWC_END_NAMESPACE();
