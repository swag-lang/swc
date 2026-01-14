#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstNodes.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Symbol/Match.h"
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
    SemaNodeView nodeCallee(sema, nodeExprRef);

    if (!nodeCallee.type || !nodeCallee.type->isFunction())
    {
        auto        diag    = SemaError::report(sema, DiagnosticId::sema_err_not_callable, nodeExprRef);
        const auto& srcView = sema.srcView(nodeCallee.node->srcViewRef());
        diag.addArgument(Diagnostic::ARG_SYM, srcView.token(nodeCallee.node->tokRef()).string(srcView));
        diag.addArgument(Diagnostic::ARG_TYPE, nodeCallee.type ? nodeCallee.type->toName(sema.ctx()) : "invalid type");
        diag.report(sema.ctx());
        return Result::Error;
    }

    const auto& symFunc    = nodeCallee.type->symFunction();
    const auto& parameters = symFunc.parameters();

    SmallVector<AstNodeRef> children;
    collectArguments(children, sema.ast());
    const uint32_t numArgs   = static_cast<uint32_t>(children.size());
    const uint32_t numParams = static_cast<uint32_t>(parameters.size());

    if (numArgs > numParams)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_too_many_arguments, children[numParams]);
        diag.addArgument(Diagnostic::ARG_COUNT, std::to_string(numParams));
        diag.addArgument(Diagnostic::ARG_VALUE, std::to_string(numArgs));
        diag.report(sema.ctx());
        return Result::Error;
    }

    for (uint32_t i = 0; i < numParams; ++i)
    {
        if (i < numArgs)
        {
            const AstNodeRef argRef = children[i];
            SemaNodeView     argView(sema, argRef);
            RESULT_VERIFY(Cast::cast(sema, argView, parameters[i]->typeRef(), CastKind::Implicit));
        }
        else
        {
            if (!parameters[i]->hasExtraFlag(SymbolVariableFlagsE::Initialized))
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_too_few_arguments, sema.curNodeRef());
                diag.addArgument(Diagnostic::ARG_COUNT, std::to_string(numParams));
                diag.addArgument(Diagnostic::ARG_VALUE, std::to_string(numArgs));
                diag.report(sema.ctx());
                return Result::Error;
            }
        }
    }

    sema.setType(sema.curNodeRef(), symFunc.returnType());
    SemaInfo::setIsValue(sema.node(sema.curNodeRef()));

    return Result::Continue;
}

SWC_END_NAMESPACE();
