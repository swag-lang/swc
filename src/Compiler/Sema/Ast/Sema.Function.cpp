#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantIntrinsic.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

Result AstFunctionDecl::semaPreDecl(Sema& sema) const
{
    SymbolFunction& sym = SemaHelpers::registerSymbol<SymbolFunction>(sema, *this, tokNameRef);

    sym.setExtraFlags(flags());
    sym.setDeclNodeRef(sema.curNodeRef());
    sym.setSpecOpKind(SemaSpecOp::computeSymbolKind(sema, sym));
    if (nodeBodyRef.isInvalid())
        sym.addExtraFlag(SymbolFunctionFlagsE::Empty);

    return Result::SkipChildren;
}

Result AstFunctionDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);

    SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
    if (sym.isMethod() && !sema.frame().currentImpl() && !sema.frame().currentInterface())
    {
        const SourceView& srcView   = sema.srcView(srcViewRef());
        const TokenRef    mtdTokRef = srcView.findLeftFrom(tokNameRef, {TokenId::KwdMtd});
        return SemaError::raise(sema, DiagnosticId::sema_err_method_outside_impl, SourceCodeRef{srcViewRef(), mtdTokRef});
    }

    SemaFrame frame = sema.frame();
    frame.currentAttributes() = sym.attributes();
    frame.setCurrentFunction(&sym);
    sema.pushFramePopOnPostNode(frame);
    return Result::Continue;
}

namespace
{
    void addMeParameter(Sema& sema, SymbolFunction& sym)
    {
        if (sema.frame().currentImpl() && sema.frame().currentImpl()->isForStruct())
        {
            const SymbolImpl* symImpl   = sema.frame().currentImpl()->asSymMap()->safeCast<SymbolImpl>();
            const TypeRef     ownerType = symImpl->symStruct()->typeRef();
            auto&             ctx       = sema.ctx();
            SymbolVariable*   symMe     = Symbol::make<SymbolVariable>(ctx, nullptr, TokenRef::invalid(), sema.idMgr().predefined(IdentifierManager::PredefinedName::Me), SymbolFlagsE::Zero);
            TypeInfoFlags     typeFlags = TypeInfoFlagsE::Zero;
            if (sym.hasExtraFlag(SymbolFunctionFlagsE::Const))
                typeFlags.add(TypeInfoFlagsE::Const);
            symMe->setTypeRef(sema.typeMgr().addType(TypeInfo::makeReference(ownerType, typeFlags)));
            symMe->addExtraFlag(SymbolVariableFlagsE::Parameter);

            sym.addParameter(symMe);
            sym.addSymbol(ctx, symMe, true);
            symMe->setDeclared(ctx);
            symMe->setTyped(ctx);
        }
    }

    template<typename T>
    Result semaCallExprCommon(Sema& sema, const T& node, bool tryIntrinsicFold)
    {
        const SemaNodeView nodeCallee = sema.nodeView(node.nodeExprRef);

        SmallVector<AstNodeRef> args;
        node.collectArguments(args, sema.ast());
        for (auto& arg : args)
            arg = Match::resolveCallArgumentRef(sema, arg);

        SmallVector<Symbol*> symbols;
        nodeCallee.getSymbols(symbols);

        if (node.hasFlag(AstCallExprFlagsE::AttributeContext))
        {
            bool hasAttributeCandidate = false;
            for (const Symbol* sym : symbols)
            {
                if (sym && sym->isAttribute())
                {
                    hasAttributeCandidate = true;
                    break;
                }
            }

            if (!hasAttributeCandidate)
                return SemaError::raise(sema, DiagnosticId::sema_err_not_attribute, node.nodeExprRef);
        }

        AstNodeRef ufcsArg = AstNodeRef::invalid();
        if (const auto memberAccess = nodeCallee.node->safeCast<AstMemberAccessExpr>())
        {
            const SemaNodeView nodeLeftView = sema.nodeView(memberAccess->nodeLeftRef);
            if (sema.isValue(*nodeLeftView.node))
                ufcsArg = nodeLeftView.nodeRef;
        }

        SmallVector<ResolvedCallArgument> resolvedArgs;
        RESULT_VERIFY(Match::resolveFunctionCandidates(sema, nodeCallee, symbols, args, ufcsArg, &resolvedArgs));
        sema.setResolvedCallArguments(sema.curNodeRef(), resolvedArgs);
        SWC_ASSERT(sema.hasSymbol(sema.curNodeRef()));
        const Symbol& sym = sema.symbolOf(sema.curNodeRef());
        SWC_ASSERT(sym.isFunction());
        if (auto* currentFn = sema.frame().currentFunction())
        {
            auto* calledFn = const_cast<SymbolFunction*>(&sym.cast<SymbolFunction>());
            if (currentFn->decl() && calledFn->decl() && currentFn->srcViewRef() == calledFn->srcViewRef())
                currentFn->addCallDependency(calledFn);
        }

        if (tryIntrinsicFold)
        {
            RESULT_VERIFY(ConstantIntrinsic::tryConstantFoldCall(sema, sym.cast<SymbolFunction>(), args));
        }
        else
        {
            RESULT_VERIFY(SemaInline::tryInlineCall(sema, sema.curNodeRef(), sym.cast<SymbolFunction>(), args, ufcsArg));
        }

        return Result::Continue;
    }
}

Result AstFunctionDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeParamsRef)
    {
        SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Parameters, childRef);
        sema.curScope().setSymMap(&sym);
        if (sym.isMethod())
            addMeParameter(sema, sym);
    }
    else if (childRef == nodeBodyRef)
    {
        SymbolFunction& sym   = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
        auto            frame = sema.frame();
        if (sym.isMethod())
        {
            const auto& params = sym.parameters();
            if (!params.empty() && params[0]->idRef() == sema.idMgr().predefined(IdentifierManager::PredefinedName::Me))
                frame.pushBindingVar(params[0]);
        }

        frame.pushBindingType(sym.returnTypeRef());
        sema.pushFramePopOnPostNode(frame);

        sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
        sema.curScope().setSymMap(&sym);
    }

    return Result::Continue;
}

Result AstFunctionDecl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();

    bool setIsTyped = false;
    if (hasFlag(AstFunctionFlagsE::Short))
    {
        if (nodeReturnTypeRef.isValid())
        {
            if (childRef == nodeReturnTypeRef)
            {
                sym.setReturnTypeRef(sema.typeRefOf(nodeReturnTypeRef));
                setIsTyped = true;
            }
        }
        else if (childRef == nodeBodyRef)
        {
            sym.setReturnTypeRef(sema.typeRefOf(nodeBodyRef));
            setIsTyped = true;
        }
    }
    else if (childRef == nodeReturnTypeRef || (childRef == nodeParamsRef && nodeReturnTypeRef.isInvalid()))
    {
        TypeRef returnType = sema.typeMgr().typeVoid();
        if (nodeReturnTypeRef.isValid())
            returnType = sema.typeRefOf(nodeReturnTypeRef);
        sym.setReturnTypeRef(returnType);
        setIsTyped = true;
    }

    if (setIsTyped)
    {
        const TypeInfo ti      = TypeInfo::makeFunction(&sym, TypeInfoFlagsE::Zero);
        const TypeRef  typeRef = sema.typeMgr().addType(ti);
        sym.setTypeRef(typeRef);
        sym.setTyped(sema.ctx());

        RESULT_VERIFY(SemaCheck::isValidSignature(sema, sym.parameters(), false));
        RESULT_VERIFY(SemaSpecOp::validateSymbol(sema, sym));
        if (!sym.isEmpty())
            RESULT_VERIFY(Match::ghosting(sema, sym));
    }

    return Result::Continue;
}

Result AstFunctionDecl::semaPostNode(Sema& sema)
{
    SymbolFunction& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolFunction>();
    sym.setSemaCompleted(sema.ctx());
    return Result::Continue;
}

Result AstFunctionParamMe::semaPreNode(Sema& sema) const
{
    const SymbolImpl* symImpl = sema.frame().currentImpl();
    if (!symImpl)
        return SemaError::raise(sema, DiagnosticId::sema_err_tok_outside_impl, sema.curNodeRef());

    const TypeRef ownerType = symImpl->isForStruct() ? symImpl->symStruct()->typeRef() : symImpl->symEnum()->typeRef();
    auto&         sym       = SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokRef());

    TypeInfoFlags typeFlags = TypeInfoFlagsE::Zero;
    if (hasFlag(AstFunctionParamMeFlagsE::Const))
        typeFlags.add(TypeInfoFlagsE::Const);
    sym.setTypeRef(sema.typeMgr().addType(TypeInfo::makeReference(ownerType, typeFlags)));

    return Result::Continue;
}

Result AstCallExpr::semaPostNode(Sema& sema) const
{
    return semaCallExprCommon(sema, *this, false);
}

Result AstIntrinsicCallExpr::semaPostNode(Sema& sema) const
{
    return semaCallExprCommon(sema, *this, true);
}

Result AstReturnStmt::semaPostNode(Sema& sema) const
{
    const SymbolFunction* sym = sema.frame().currentFunction();
    SWC_ASSERT(sym);

    const TypeRef returnTypeRef = sym->returnTypeRef();
    const auto&   returnType    = sema.typeMgr().get(returnTypeRef);
    if (nodeExprRef.isValid())
    {
        if (returnType.isVoid())
            return SemaError::raise(sema, DiagnosticId::sema_err_return_value_in_void, nodeExprRef);

        SemaNodeView nodeView = sema.nodeView(nodeExprRef);
        RESULT_VERIFY(Cast::cast(sema, nodeView, returnTypeRef, CastKind::Implicit));
    }
    else if (!returnType.isVoid())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_return_missing_value, sema.curNodeRef());
        diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, returnType.toName(sema.ctx()));
        diag.report(sema.ctx());
        return Result::Error;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
