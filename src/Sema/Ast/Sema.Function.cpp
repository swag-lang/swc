#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Match/Match.h"
#include "Sema/Match/MatchContext.h"
#include "Sema/Symbol/Symbol.Impl.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/Cast.h"

SWC_BEGIN_NAMESPACE();

Result AstFunctionDecl::semaPreDecl(Sema& sema) const
{
    SymbolFunction& sym = SemaHelpers::registerSymbol<SymbolFunction>(sema, *this, tokNameRef);

    sym.setExtraFlags(flags());
    if (nodeBodyRef.isInvalid())
        sym.addExtraFlag(SymbolFunctionFlagsE::Empty);

    return Result::SkipChildren;
}

Result AstFunctionDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);

    SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
    if (sym.isMethod() && !sema.frame().impl() && !sema.frame().interface())
    {
        const SourceView& srcView   = sema.srcView(srcViewRef());
        const TokenRef    mtdTokRef = srcView.findLeftFrom(tokNameRef, {TokenId::KwdMtd});
        return SemaError::raise(sema, DiagnosticId::sema_err_method_outside_impl, srcViewRef(), mtdTokRef);
    }

    SemaFrame frame = sema.frame();
    frame.setFunction(&sym);
    sema.pushFrame(frame);
    return Result::Continue;
}

namespace
{
    void addMeParameter(Sema& sema, SymbolFunction& sym)
    {
        if (sema.frame().impl() && sema.frame().impl()->isForStruct())
        {
            const SymbolImpl* symImpl   = sema.frame().impl()->asSymMap()->safeCast<SymbolImpl>();
            const TypeRef     ownerType = symImpl->symStruct()->typeRef();
            auto&             ctx       = sema.ctx();
            SymbolVariable*   symMe     = Symbol::make<SymbolVariable>(ctx, nullptr, TokenRef::invalid(), sema.idMgr().nameMe(), SymbolFlagsE::Zero);
            TypeInfoFlags     typeFlags = TypeInfoFlagsE::Zero;
            if (sym.hasExtraFlag(SymbolFunctionFlagsE::Const))
                typeFlags.add(TypeInfoFlagsE::Const);
            const TypeRef typeRef = sema.typeMgr().addType(TypeInfo::makeValuePointer(ownerType, typeFlags));
            symMe->setTypeRef(typeRef);

            sym.addParameter(symMe);
            sym.addSymbol(ctx, symMe, true);
            symMe->setDeclared(ctx);
            symMe->setTyped(ctx);
        }
    }
}

Result AstFunctionDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeParamsRef)
    {
        SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
        sema.pushScope(SemaScopeFlagsE::Parameters);
        sema.curScope().setSymMap(&sym);
        if (sym.isMethod())
            addMeParameter(sema, sym);
    }
    else if (childRef == nodeBodyRef)
    {
        return Result::SkipChildren; // TODO
        SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
        sema.pushScope(SemaScopeFlagsE::Local);
        sema.curScope().setSymMap(&sym);
    }

    return Result::Continue;
}

Result AstFunctionDecl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeParamsRef && sema.enteringState())
        sema.popScope();

    if (childRef == nodeReturnTypeRef || (childRef == nodeParamsRef && nodeReturnTypeRef.isInvalid()))
    {
        SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();

        TypeRef returnType = sema.typeMgr().typeVoid();
        if (nodeReturnTypeRef.isValid())
            returnType = sema.typeRefOf(nodeReturnTypeRef);
        sym.setReturnType(returnType);

        const TypeInfo ti      = TypeInfo::makeFunction(&sym, TypeInfoFlagsE::Zero);
        const TypeRef  typeRef = sema.typeMgr().addType(ti);
        sym.setTypeRef(typeRef);
        sym.setTyped(sema.ctx());

        RESULT_VERIFY(SemaCheck::checkSignature(sema, sym.parameters(), false));
        if (!sym.isEmpty())
            RESULT_VERIFY(Match::ghosting(sema, sym));
    }
    else if (childRef == nodeBodyRef)
    {
        sema.popScope();
    }

    return Result::Continue;
}

Result AstFunctionDecl::semaPostNode(Sema& sema)
{
    SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
    sym.setCompleted(sema.ctx());
    sema.popFrame();
    return Result::Continue;
}

Result AstFunctionParamMe::semaPreNode(Sema& sema) const
{
    if (!sema.frame().impl())
        return SemaError::raise(sema, DiagnosticId::sema_err_tok_outside_impl, sema.curNodeRef());

    const SymbolImpl* symImpl   = sema.frame().impl()->symMap()->safeCast<SymbolImpl>();
    const TypeRef     ownerType = symImpl->ownerKind() == SymbolImplOwnerKind::Struct ? symImpl->symStruct()->typeRef() : symImpl->symEnum()->typeRef();

    auto& sym = SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokRef());

    TypeInfoFlags typeFlags = TypeInfoFlagsE::Zero;
    if (hasFlag(AstFunctionParamMeFlagsE::Const))
        typeFlags.add(TypeInfoFlagsE::Const);
    const TypeRef typeRef = sema.typeMgr().addType(TypeInfo::makeValuePointer(ownerType, typeFlags));
    sym.setTypeRef(typeRef);

    return Result::Continue;
}

Result AstCallExpr::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeCallee(sema, nodeExprRef);

    // Collect arguments: take care of sustitutions
    SmallVector<AstNodeRef> args;
    collectArguments(args, sema.ast());
    for (auto& arg : args)
        arg = sema.semaInfo().getSubstituteRef(arg);

    // Collect overload set
    SmallVector<Symbol*> symbols;
    nodeCallee.getSymbols(symbols);

    // Possible UFCS if we are inside a member access expression with a value on the left
    AstNodeRef ufcsArg = AstNodeRef::invalid();
    if (const auto memberAccess = nodeCallee.node->safeCast<AstMemberAccessExpr>())
    {
        const SemaNodeView nodeLeftView(sema, memberAccess->nodeLeftRef);
        if (SemaInfo::isValue(*nodeLeftView.node))
            ufcsArg = nodeLeftView.nodeRef;
    }

    return Match::resolveFunctionCandidates(sema, nodeCallee, symbols, args, ufcsArg);
}

SWC_END_NAMESPACE();
