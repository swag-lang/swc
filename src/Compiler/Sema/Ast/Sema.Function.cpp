#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantIntrinsic.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Compiler/Sema/Helpers/SemaPurity.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

Result AstFunctionDecl::semaPreDecl(Sema& sema) const
{
    auto& sym = SemaHelpers::registerSymbol<SymbolFunction>(sema, *this, tokNameRef);

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

    auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    if (sym.isMethod() && !sema.frame().currentImpl() && !sema.frame().currentInterface())
    {
        const SourceView& srcView   = sema.srcView(srcViewRef());
        const TokenRef    mtdTokRef = srcView.findLeftFrom(tokNameRef, {TokenId::KwdMtd});
        return SemaError::raise(sema, DiagnosticId::sema_err_method_outside_impl, SourceCodeRef{srcViewRef(), mtdTokRef});
    }

    SemaFrame frame           = sema.frame();
    frame.currentAttributes() = sym.attributes();
    frame.setCurrentFunction(&sym);
    sema.pushFramePopOnPostNode(frame);
    return Result::Continue;
}

namespace
{
    bool isInsideInlineRoot(const Sema& sema, AstNodeRef inlineRootRef)
    {
        if (inlineRootRef.isInvalid())
            return false;
        if (sema.curNodeRef() == inlineRootRef)
            return true;

        for (size_t parentIndex = 0;; parentIndex++)
        {
            const AstNodeRef parentRef = sema.visit().parentNodeRef(parentIndex);
            if (parentRef.isInvalid())
                return false;
            if (parentRef == inlineRootRef)
                return true;
        }
    }

    bool isCallResultIgnored(const Sema& sema)
    {
        const AstNode* parent = sema.visit().parentNode();
        if (!parent)
            return false;

        if (parent->is(AstNodeId::DiscardExpr))
            return false;

        switch (parent->id())
        {
            case AstNodeId::EmbeddedBlock:
            case AstNodeId::FunctionBody:
            case AstNodeId::SwitchCaseBody:
            case AstNodeId::TopLevelBlock:
                return true;
            default:
                return false;
        }
    }

    void addMeParameter(Sema& sema, SymbolFunction& sym)
    {
        if (sema.frame().currentImpl() && sema.frame().currentImpl()->isForStruct())
        {
            const SymbolImpl& symImpl   = sema.frame().currentImpl()->asSymMap()->cast<SymbolImpl>();
            const TypeRef     ownerType = symImpl.symStruct()->typeRef();
            TaskContext&      ctx       = sema.ctx();
            auto*             symMe     = Symbol::make<SymbolVariable>(ctx, nullptr, TokenRef::invalid(), sema.idMgr().predefined(IdentifierManager::PredefinedName::Me), SymbolFlagsE::Zero);
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

    void registerRuntimeFunctionSymbol(Sema& sema, SymbolFunction& sym)
    {
        const SourceFile* file = sema.file();
        if (!file || !file->isRuntime())
            return;

        if (sym.isForeign() || sym.isEmpty())
            return;

        const auto kind = sema.idMgr().runtimeFunctionKind(sym.idRef());
        if (kind == IdentifierManager::RuntimeFunctionKind::Count)
            return;

        sema.compiler().registerRuntimeFunctionSymbol(sym.idRef(), &sym);
    }

    Result setupIntrinsicGetContextRuntimeCall(Sema& sema, const AstIntrinsicCallExpr& node)
    {
        if (sema.compiler().buildCfg().backendKind != Runtime::BuildCfgBackendKind::None)
        {
            SymbolFunction* tlsAllocFn  = nullptr;
            SymbolFunction* tlsGetPtrFn = nullptr;
            SWC_RESULT(sema.waitRuntimeFunction(IdentifierManager::RuntimeFunctionKind::TlsAlloc, tlsAllocFn, node.codeRef()));
            SWC_RESULT(sema.waitRuntimeFunction(IdentifierManager::RuntimeFunctionKind::TlsGetPtr, tlsGetPtrFn, node.codeRef()));
            SWC_ASSERT(tlsAllocFn != nullptr);
            SWC_ASSERT(tlsGetPtrFn != nullptr);

            if (SymbolFunction* currentFn = sema.frame().currentFunction())
            {
                currentFn->addCallDependency(tlsAllocFn);
                currentFn->addCallDependency(tlsGetPtrFn);
            }

            return Result::Continue;
        }

        SymbolFunction* tlsGetValueFn = nullptr;
        SWC_RESULT(sema.waitRuntimeFunction(IdentifierManager::RuntimeFunctionKind::TlsGetValue, tlsGetValueFn, node.codeRef()));
        SWC_ASSERT(tlsGetValueFn != nullptr);

        if (SymbolFunction* currentFn = sema.frame().currentFunction())
            currentFn->addCallDependency(tlsGetValueFn);

        auto* payload = sema.codeGenPayload<CodeGenNodePayload>(sema.curNodeRef());
        if (!payload)
        {
            payload = sema.compiler().allocate<CodeGenNodePayload>();
            sema.setCodeGenPayload(sema.curNodeRef(), payload);
        }

        payload->runtimeFunctionSymbol = tlsGetValueFn;
        return Result::Continue;
    }

    Result setupIntrinsicAssertRuntimeCall(Sema& sema, const AstIntrinsicCallExpr& node)
    {
        SymbolFunction* raiseExceptionFn = nullptr;
        SWC_RESULT(sema.waitRuntimeFunction(IdentifierManager::RuntimeFunctionKind::RaiseException, raiseExceptionFn, node.codeRef()));
        SWC_ASSERT(raiseExceptionFn != nullptr);

        if (SymbolFunction* currentFn = sema.frame().currentFunction())
            currentFn->addCallDependency(raiseExceptionFn);

        auto* payload = sema.codeGenPayload<CodeGenNodePayload>(sema.curNodeRef());
        if (!payload)
        {
            payload = sema.compiler().allocate<CodeGenNodePayload>();
            sema.setCodeGenPayload(sema.curNodeRef(), payload);
        }

        payload->runtimeFunctionSymbol = raiseExceptionFn;
        return Result::Continue;
    }

    TypeRef callExprRuntimeStorageTypeRef(Sema& sema, const SymbolFunction& calledFn)
    {
        if (sema.frame().currentFunction() == nullptr)
            return TypeRef::invalid();

        const TypeRef returnTypeRef = calledFn.returnTypeRef();
        if (!returnTypeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& returnType = sema.typeMgr().get(returnTypeRef);
        if (returnType.isVoid())
            return TypeRef::invalid();

        const CallConv&                        callConv      = CallConv::get(calledFn.callConvKind());
        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(sema.ctx(), callConv, returnTypeRef, ABITypeNormalize::Usage::Return);
        if (!normalizedRet.isIndirect)
            return TypeRef::invalid();

        const TypeRef storageTypeRef = returnType.unwrap(sema.ctx(), returnTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        if (storageTypeRef.isValid())
            return storageTypeRef;

        return returnTypeRef;
    }

    Result completeCallExprRuntimeStorageSymbol(Sema& sema, SymbolVariable& symVar, TypeRef typeRef)
    {
        symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
        symVar.setTypeRef(typeRef);

        if (SymbolFunction* currentFunc = sema.frame().currentFunction())
        {
            const TypeInfo& symType = sema.typeMgr().get(typeRef);
            SWC_RESULT(sema.waitSemaCompleted(&symType, sema.curNodeRef()));
            currentFunc->addLocalVariable(sema.ctx(), &symVar);
        }

        symVar.setTyped(sema.ctx());
        symVar.setSemaCompleted(sema.ctx());
        return Result::Continue;
    }

    SymbolVariable& registerUniqueCallExprRuntimeStorageSymbol(Sema& sema, const AstNode& node)
    {
        TaskContext&        ctx         = sema.ctx();
        const auto          privateName = Utf8("__call_runtime_storage");
        const IdentifierRef idRef       = SemaHelpers::getUniqueIdentifier(sema, privateName);
        const SymbolFlags   flags       = sema.frame().flagsForCurrentAccess();

        auto* sym = Symbol::make<SymbolVariable>(ctx, &node, node.tokRef(), idRef, flags);
        if (sema.curScope().isLocal() && !sema.curScope().symMap())
        {
            sema.curScope().addSymbol(sym);
        }
        else
        {
            SymbolMap* symMap = SemaFrame::currentSymMap(sema);
            SWC_ASSERT(symMap != nullptr);
            symMap->addSymbol(ctx, sym, true);
        }

        return *(sym);
    }

    Result attachCallExprRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, const SymbolFunction& calledFn)
    {
        auto* payload = sema.codeGenPayload<CodeGenNodePayload>(sema.curNodeRef());
        if (payload && payload->runtimeStorageSym != nullptr)
            return Result::Continue;

        const TypeRef storageTypeRef = callExprRuntimeStorageTypeRef(sema, calledFn);
        if (storageTypeRef.isInvalid())
            return Result::Continue;

        auto& storageSym = registerUniqueCallExprRuntimeStorageSymbol(sema, node);
        storageSym.registerAttributes(sema);
        storageSym.setDeclared(sema.ctx());
        SWC_RESULT(Match::ghosting(sema, storageSym));
        SWC_RESULT(completeCallExprRuntimeStorageSymbol(sema, storageSym, storageTypeRef));

        if (!payload)
        {
            payload = sema.compiler().allocate<CodeGenNodePayload>();
            sema.setCodeGenPayload(sema.curNodeRef(), payload);
        }

        payload->runtimeStorageSym = &storageSym;
        return Result::Continue;
    }

    template<typename T>
    Result semaCallExprCommon(Sema& sema, const T& node, bool tryIntrinsicFold)
    {
        const SemaNodeView nodeCallee = sema.viewNodeSymbolList(node.nodeExprRef);

        SmallVector<AstNodeRef> args;
        node.collectArguments(args, sema.ast());
        for (auto& arg : args)
            arg = Match::resolveCallArgumentRef(sema, arg);

        SmallVector<Symbol*> symbols;
        nodeCallee.getSymbols(symbols);

        AstNodeRef ufcsArg = AstNodeRef::invalid();
        SWC_ASSERT(nodeCallee.node() != nullptr);
        if (nodeCallee.node()->is(AstNodeId::MemberAccessExpr))
        {
            const auto&        memberAccess = nodeCallee.node()->cast<AstMemberAccessExpr>();
            const SemaNodeView nodeLeftView = sema.viewZero(memberAccess.nodeLeftRef);
            if (sema.isValue(nodeLeftView.nodeRef()))
                ufcsArg = nodeLeftView.nodeRef();
        }

        SmallVector<ResolvedCallArgument> resolvedArgs;
        const auto                        resolveMode = node.hasFlag(AstCallExprFlagsE::AttributeContext) ? Match::ResolveCallMode::AttributeOnly : Match::ResolveCallMode::Normal;
        SWC_RESULT(Match::resolveFunctionCandidates(sema, nodeCallee, symbols, args, ufcsArg, &resolvedArgs, resolveMode));
        sema.setResolvedCallArguments(sema.curNodeRef(), resolvedArgs);
        const SemaNodeView nodeSymView = sema.curViewSymbol();
        SWC_ASSERT(nodeSymView.hasSymbol());

        auto& calledFn = nodeSymView.sym()->cast<SymbolFunction>();
        if (SymbolFunction* currentFn = sema.frame().currentFunction())
        {
            const bool isMixinCall = calledFn.attributes().hasRtFlag(RtAttributeFlagsE::Mixin);
            if (currentFn->decl() &&
                calledFn.decl() &&
                calledFn.declNodeRef().isValid() &&
                !calledFn.isForeign() &&
                !calledFn.isEmpty() &&
                !isMixinCall)
            {
                currentFn->addCallDependency(&calledFn);
            }
        }

        const TypeInfo& returnType = sema.typeMgr().get(calledFn.returnTypeRef());
        if (!returnType.isVoid() &&
            !calledFn.attributes().hasRtFlag(RtAttributeFlagsE::Discardable) &&
            isCallResultIgnored(sema))
        {
            return SemaError::raise(sema, DiagnosticId::sema_err_return_value_must_be_used, sema.curNodeRef());
        }

        if (tryIntrinsicFold)
        {
            SWC_RESULT(ConstantIntrinsic::tryConstantFoldCall(sema, calledFn, args));
        }
        else
        {
            SWC_RESULT(SemaJIT::tryRunConstCall(sema, calledFn, sema.curNodeRef(), resolvedArgs.span()));
            if (sema.viewConstant(sema.curNodeRef()).hasConstant())
                return Result::Continue;
            SWC_RESULT(SemaInline::tryInlineCall(sema, sema.curNodeRef(), calledFn, args, ufcsArg));
            SWC_RESULT(attachCallExprRuntimeStorageIfNeeded(sema, node, calledFn));
        }

        return Result::Continue;
    }
}

Result AstFunctionDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeParamsRef)
    {
        auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Parameters, childRef);
        sema.curScope().setSymMap(&sym);
        if (sym.isMethod())
            addMeParameter(sema, sym);
    }
    else if (childRef == nodeBodyRef)
    {
        auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();
        if (sym.attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
        {
            const bool shortWithoutExplicitReturnType = hasFlag(AstFunctionFlagsE::Short) && nodeReturnTypeRef.isInvalid();
            if (!shortWithoutExplicitReturnType)
                return Result::SkipChildren;
        }

        auto frame = sema.frame();
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
    auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();

    bool setIsTyped = false;
    if (hasFlag(AstFunctionFlagsE::Short))
    {
        if (nodeReturnTypeRef.isValid())
        {
            if (childRef == nodeReturnTypeRef)
            {
                sym.setReturnTypeRef(sema.viewType(nodeReturnTypeRef).typeRef());
                setIsTyped = true;
            }
        }
        else if (childRef == nodeBodyRef)
        {
            sym.setReturnTypeRef(sema.viewType(nodeBodyRef).typeRef());
            setIsTyped = true;
        }
    }
    else if (childRef == nodeReturnTypeRef || (childRef == nodeParamsRef && nodeReturnTypeRef.isInvalid()))
    {
        TypeRef returnType = sema.typeMgr().typeVoid();
        if (nodeReturnTypeRef.isValid())
            returnType = sema.viewType(nodeReturnTypeRef).typeRef();
        sym.setReturnTypeRef(returnType);
        setIsTyped = true;
    }

    if (setIsTyped)
    {
        sym.setVariadicParamFlag(sema.ctx());

        const TypeInfo ti      = TypeInfo::makeFunction(&sym, TypeInfoFlagsE::Zero);
        const TypeRef  typeRef = sema.typeMgr().addType(ti);
        sym.setTypeRef(typeRef);
        SemaPurity::computePurityFlag(sema, sym);
        sym.setTyped(sema.ctx());

        SWC_RESULT(SemaCheck::isValidSignature(sema, sym.parameters(), false));
        SWC_RESULT(SemaSpecOp::validateSymbol(sema, sym));
        if (!sym.isEmpty())
            SWC_RESULT(Match::ghosting(sema, sym));

        registerRuntimeFunctionSymbol(sema, sym);
    }

    return Result::Continue;
}

Result AstFunctionDecl::semaPostNode(Sema& sema)
{
    auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    if (sym.isForeign() && !sym.isEmpty())
        return SemaError::raise(sema, DiagnosticId::sema_err_foreign_cannot_have_body, sema.curNodeRef());

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
    SWC_RESULT(semaCallExprCommon(sema, *this, true));

    const Token& tok = sema.token(codeRef());
    if (tok.id == TokenId::IntrinsicGetContext)
    {
        SWC_RESULT(setupIntrinsicGetContextRuntimeCall(sema, *this));
    }
    else if (tok.id == TokenId::IntrinsicAssert)
    {
        SWC_RESULT(setupIntrinsicAssertRuntimeCall(sema, *this));
    }

    return Result::Continue;
}

Result AstReturnStmt::semaPostNode(Sema& sema) const
{
    TypeRef                  returnTypeRef = TypeRef::invalid();
    const SemaInlinePayload* inlinePayload = sema.frame().currentInlinePayload();
    if (inlinePayload && isInsideInlineRoot(sema, inlinePayload->inlineRootRef))
    {
        returnTypeRef = inlinePayload->returnTypeRef;
    }
    else
    {
        const SymbolFunction* sym = sema.frame().currentFunction();
        SWC_ASSERT(sym);
        returnTypeRef = sym->returnTypeRef();
    }

    SWC_ASSERT(returnTypeRef.isValid());
    const TypeInfo& returnType = sema.typeMgr().get(returnTypeRef);
    if (nodeExprRef.isValid())
    {
        if (returnType.isVoid())
            return SemaError::raise(sema, DiagnosticId::sema_err_return_value_in_void, nodeExprRef);

        SemaNodeView view = sema.viewNodeTypeConstant(nodeExprRef);
        SWC_RESULT(Cast::cast(sema, view, returnTypeRef, CastKind::Implicit));
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

Result AstDiscardExpr::semaPostNode(Sema& sema)
{
    sema.setType(sema.curNodeRef(), sema.typeMgr().typeVoid());
    return Result::Continue;
}

SWC_END_NAMESPACE();
