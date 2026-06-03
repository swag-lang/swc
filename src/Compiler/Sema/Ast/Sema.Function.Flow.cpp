#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Backend/Runtime.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantIntrinsic.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isNestedUfcsReceiverValue(Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return false;

        const SemaNodeView view = sema.viewNodeTypeSymbol(nodeRef);
        if (view.sym())
        {
            if (view.sym()->isNamespace() || view.sym()->isModule())
                return false;
            if (view.sym()->isVariable())
                return true;
        }

        if (sema.isValue(nodeRef))
            return true;

        // The resolved expression type is the most reliable signal here. Some receiver
        // expressions (for example enum-value member accesses or inlined clones) can still
        // carry a type symbol on the node while already having a concrete non-type result.
        if (view.type() && !view.type()->isType())
            return true;

        return false;
    }

    AstNodeRef resolvedUfcsReceiverArg(Sema& sema, AstNodeRef nodeRef)
    {
        const AstNodeRef resolvedRef = sema.viewZero(nodeRef).nodeRef();
        return resolvedRef.isValid() ? resolvedRef : nodeRef;
    }

    AstNodeRef resolveUfcsReceiverArg(Sema& sema, AstNodeRef calleeExprRef)
    {
        AstNodeRef resolvedCalleeRef = calleeExprRef;
        if (resolvedCalleeRef.isValid() && sema.node(resolvedCalleeRef).isNot(AstNodeId::MemberAccessExpr))
            resolvedCalleeRef = SemaHelpers::unwrapCallCalleeRef(sema, calleeExprRef);
        if (resolvedCalleeRef.isInvalid() || sema.node(resolvedCalleeRef).isNot(AstNodeId::MemberAccessExpr))
            return AstNodeRef::invalid();

        const auto& outerMember = sema.node(resolvedCalleeRef).cast<AstMemberAccessExpr>();
        if (isNestedUfcsReceiverValue(sema, outerMember.nodeLeftRef))
        {
            const SemaNodeView outerLeftView = sema.viewNodeTypeSymbol(outerMember.nodeLeftRef);
            if (outerLeftView.type() && outerLeftView.type()->isInterface())
                return AstNodeRef::invalid();

            if (outerMember.nodeLeftRef.isValid() && sema.node(outerMember.nodeLeftRef).is(AstNodeId::MemberAccessExpr))
            {
                const auto& innerMember = sema.node(outerMember.nodeLeftRef).cast<AstMemberAccessExpr>();
                if ((outerLeftView.sym() && outerLeftView.sym()->isImpl()) ||
                    (outerLeftView.type() && outerLeftView.type()->isInterface()))
                {
                    if (isNestedUfcsReceiverValue(sema, innerMember.nodeLeftRef))
                        return resolvedUfcsReceiverArg(sema, innerMember.nodeLeftRef);
                }
            }

            return resolvedUfcsReceiverArg(sema, outerMember.nodeLeftRef);
        }

        if (outerMember.nodeLeftRef.isInvalid() ||
            sema.node(outerMember.nodeLeftRef).isNot(AstNodeId::MemberAccessExpr))
            return AstNodeRef::invalid();

        const auto& innerMember = sema.node(outerMember.nodeLeftRef).cast<AstMemberAccessExpr>();
        if (isNestedUfcsReceiverValue(sema, innerMember.nodeLeftRef))
            return resolvedUfcsReceiverArg(sema, innerMember.nodeLeftRef);

        return AstNodeRef::invalid();
    }

    bool isAttributeContextCall(const AstCallExpr& node)
    {
        return node.hasFlag(AstCallExprFlagsE::AttributeContext);
    }

    bool isAttributeContextCall(const AstIntrinsicCallExpr& node)
    {
        return node.hasFlag(AstCallExprFlagsE::AttributeContext);
    }

    bool isAttributeContextCall(const AstAliasCallExpr&)
    {
        return false;
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
            case AstNodeId::TryCatchStmt:
                return true;
            default:
                return false;
        }
    }

    struct ErrorManagementPayload
    {
        bool containsThrowable = false;
        bool isThrowableResult = false;
    };

    ErrorManagementPayload& ensureErrorManagementPayload(Sema& sema, AstNodeRef nodeRef)
    {
        auto* payload = sema.semaPayload<ErrorManagementPayload>(nodeRef);
        if (!payload)
        {
            payload = sema.compiler().allocate<ErrorManagementPayload>();
            sema.setSemaPayload(nodeRef, payload);
        }

        return *payload;
    }

    void attachThrowableWrapper(Sema& sema, AstNodeRef ownerRef, AstNodeRef targetRef, TokenId tokenId)
    {
        if (!targetRef.isValid())
            return;

        CodeGenLoweringPayload& payload  = SemaHelpers::ensureCodeGenLoweringPayload(sema, targetRef);
        payload.throwableWrapperOwnerRef = ownerRef;
        payload.throwableWrapperTokenId  = tokenId;
    }

    void attachInlineRootThrowableWrapperIfCallLike(Sema& sema, AstNodeRef ownerRef, AstNodeRef targetRef, TokenId tokenId)
    {
        if (!targetRef.isValid())
            return;

        const AstNodeId nodeId = sema.node(targetRef).id();
        if (nodeId == AstNodeId::CallExpr || nodeId == AstNodeId::AliasCallExpr)
            attachThrowableWrapper(sema, ownerRef, targetRef, tokenId);
    }

    void attachThrowableWrapperToManagedChild(Sema& sema, AstNodeRef ownerRef, AstNodeRef managedChildRef, TokenId tokenId)
    {
        switch (tokenId)
        {
            case TokenId::KwdCatch:
            case TokenId::KwdTryCatch:
            case TokenId::KwdAssume:
                break;
            default:
                return;
        }

        attachThrowableWrapper(sema, ownerRef, ownerRef, tokenId);
        attachInlineRootThrowableWrapperIfCallLike(sema, ownerRef, managedChildRef, tokenId);
        attachInlineRootThrowableWrapperIfCallLike(sema, ownerRef, sema.viewZero(managedChildRef).nodeRef(), tokenId);
    }

    SemaFrame::ErrorContextMode errorContextMode(TokenId tokenId)
    {
        switch (tokenId)
        {
            case TokenId::KwdTry:
                return SemaFrame::ErrorContextMode::Try;
            case TokenId::KwdCatch:
                return SemaFrame::ErrorContextMode::Catch;
            case TokenId::KwdTryCatch:
                return SemaFrame::ErrorContextMode::TryCatch;
            case TokenId::KwdAssume:
                return SemaFrame::ErrorContextMode::Assume;
            default:
                return SemaFrame::ErrorContextMode::None;
        }
    }

    bool isThrowableFunctionContext(const Sema& sema)
    {
        const auto* currentFn = sema.currentFunction();
        return currentFn && currentFn->isThrowable();
    }

    bool isNativeArtifactCompilerEntryContext(const Sema& sema)
    {
        const auto* currentFn = sema.currentFunction();
        if (!currentFn)
            return false;

        const AstNode* decl = currentFn->decl();
        if (!decl || decl->id() != AstNodeId::CompilerFunc)
            return false;

        switch (sema.token(decl->codeRef()).id)
        {
            case TokenId::CompilerFuncInit:
            case TokenId::CompilerFuncDrop:
            case TokenId::CompilerFuncMain:
            case TokenId::CompilerFuncPreMain:
                return true;

            default:
                return false;
        }
    }

    bool isCompilerTestFunctionContext(const Sema& sema)
    {
        const auto* currentFn = sema.currentFunction();
        if (!currentFn)
            return false;

        const AstNode* decl = currentFn->decl();
        if (!decl || decl->id() != AstNodeId::CompilerFunc)
            return false;

        return sema.token(decl->codeRef()).id == TokenId::CompilerFuncTest;
    }

    TokenId effectiveErrorManagementTokenId(const Sema& sema, TokenId tokenId)
    {
        if (tokenId == TokenId::KwdTry && isCompilerTestFunctionContext(sema))
            return TokenId::KwdAssume;

        return tokenId;
    }

    bool canPropagateThrowableResult(const Sema& sema)
    {
        return isThrowableFunctionContext(sema) ||
               isNativeArtifactCompilerEntryContext(sema) ||
               sema.frame().currentErrorContextMode() != SemaFrame::ErrorContextMode::None;
    }

    void addFunctionDeclaredHereNote(Sema& sema, Diagnostic& diag, const SymbolFunction& fn)
    {
        const SourceCodeRange codeRange = fn.codeRange(sema.ctx());
        if (codeRange.srcView == nullptr)
            return;

        diag.addNote(DiagnosticId::sema_note_function_declared_here);
        diag.last().addArgument(Diagnostic::ARG_SYM, fn.name(sema.ctx()));
        diag.last().addSpan(codeRange);
    }

    Result reportTryOutsideThrowableContext(Sema& sema, AstNodeRef errorRef)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_try_outside_throwable_context, errorRef);
        if (const auto* currentFn = sema.currentFunction())
            addFunctionDeclaredHereNote(sema, diag, *currentFn);
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result reportThrowOutsideThrowableContext(Sema& sema, AstNodeRef errorRef)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_throw_outside_throwable_context, errorRef);
        if (const auto* currentFn = sema.currentFunction())
            addFunctionDeclaredHereNote(sema, diag, *currentFn);
        diag.report(sema.ctx());
        return Result::Error;
    }

    Result reportThrowableCallRequiresContext(Sema& sema, const SymbolFunction& fn, AstNodeRef errorRef)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_throwable_call_requires_handler, errorRef);
        diag.addArgument(Diagnostic::ARG_SYM, fn.name(sema.ctx()));
        addFunctionDeclaredHereNote(sema, diag, fn);
        diag.report(sema.ctx());
        return Result::Error;
    }

    const SymbolFunction* calledFunctionFromNode(Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return nullptr;

        const AstNodeRef resolvedRef = sema.viewZero(nodeRef).nodeRef();
        if (resolvedRef.isInvalid())
            return nullptr;

        const AstNode& resolvedNode = sema.node(resolvedRef);
        if (resolvedNode.isNot(AstNodeId::CallExpr) &&
            resolvedNode.isNot(AstNodeId::AliasCallExpr) &&
            resolvedNode.isNot(AstNodeId::IntrinsicCallExpr))
            return nullptr;

        const Symbol* sym = sema.viewSymbol(resolvedRef).sym();
        if (!sym || !sym->isFunction())
            return nullptr;

        return &sym->cast<SymbolFunction>();
    }

    Result reportErrorManagementOperandNotThrowable(Sema& sema, AstNodeRef errorRef, AstNodeRef childRef)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_error_mgmt_operand_not_throwable, errorRef);
        diag.addArgument(Diagnostic::ARG_TOK, Diagnostic::tokenErrorString(sema.ctx(), sema.curNode().codeRef()));

        const auto* fn = calledFunctionFromNode(sema, childRef);
        if (fn && !fn->isThrowable())
            addFunctionDeclaredHereNote(sema, diag, *fn);

        diag.report(sema.ctx());
        return Result::Error;
    }

    void markCurrentErrorScopeThrowable(Sema& sema)
    {
        const AstNodeRef errorScopeRef = sema.frame().currentErrorScope();
        if (errorScopeRef.isInvalid())
            return;

        ensureErrorManagementPayload(sema, errorScopeRef).containsThrowable = true;
    }

    TypeRef preferredThrowResultType(Sema& sema)
    {
        const auto frames = sema.frames();
        for (size_t frameIndex = frames.size(); frameIndex > 0; --frameIndex)
        {
            const std::span<const TypeRef> bindingTypes = frames[frameIndex - 1].bindingTypes();
            for (size_t bindingIndex = bindingTypes.size(); bindingIndex > 0; --bindingIndex)
            {
                const TypeRef bindingTypeRef = bindingTypes[bindingIndex - 1];
                if (bindingTypeRef.isValid())
                    return bindingTypeRef;
            }
        }

        return sema.typeMgr().typeVoid();
    }

    TypeRef assumeNullableResultTypeRef(Sema& sema, AstNodeRef managedChildRef)
    {
        if (managedChildRef.isInvalid())
            return TypeRef::invalid();

        const AstNodeRef resolvedChildRef = sema.viewZero(managedChildRef).nodeRef();
        if (resolvedChildRef.isInvalid())
            return TypeRef::invalid();

        const SemaNodeView childView = sema.viewType(resolvedChildRef);
        if (!childView.typeRef().isValid())
            return TypeRef::invalid();

        TypeRef nullableTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), childView.typeRef());
        if (nullableTypeRef.isInvalid())
            nullableTypeRef = childView.typeRef();

        const TypeInfo& nullableType = sema.typeMgr().get(nullableTypeRef);
        if (!nullableType.isNullable())
            return TypeRef::invalid();

        TypeInfo resultType = nullableType;
        resultType.removeFlag(TypeInfoFlagsE::Nullable);
        return sema.typeMgr().addType(resultType);
    }

    Result setupNullableAssume(Sema& sema, AstNodeRef managedChildRef)
    {
        const AstNodeRef resolvedChildRef = sema.viewZero(managedChildRef).nodeRef();
        SWC_RESULT(SemaCheck::isValue(sema, resolvedChildRef));

        auto& codeGenPayload          = SemaHelpers::ensureCodeGenLoweringPayload(sema, sema.curNodeRef());
        codeGenPayload.assumeNullable = true;
        return SemaHelpers::setupRuntimeSafetyPanic(sema, sema.curNodeRef(), Runtime::SafetyWhat::Assume, sema.curNode().codeRef());
    }

    Result semaTryCatchPreNodeCommon(Sema& sema)
    {
        ensureErrorManagementPayload(sema, sema.curNodeRef());
        return Result::Continue;
    }

    Result semaTryCatchPreNodeChildCommon(Sema& sema, AstNodeRef managedChildRef, const AstNodeRef& childRef)
    {
        if (childRef != managedChildRef || childRef.isInvalid())
            return Result::Continue;

        auto          frame   = sema.frame();
        const TokenId tokenId = effectiveErrorManagementTokenId(sema, sema.token(sema.curNode().codeRef()).id);
        frame.setCurrentErrorContext(sema.curNodeRef(), errorContextMode(tokenId));
        sema.pushFramePopOnPostChild(frame, childRef);
        return Result::Continue;
    }

    Result semaTryCatchPostNodeCommon(Sema& sema, AstNodeRef managedChildRef)
    {
        auto&         payload = ensureErrorManagementPayload(sema, sema.curNodeRef());
        const Token&  tok     = sema.token(sema.curNode().codeRef());
        const TokenId tokenId = effectiveErrorManagementTokenId(sema, tok.id);

        if (tokenId == TokenId::KwdTry && !canPropagateThrowableResult(sema))
            return reportTryOutsideThrowableContext(sema, sema.curNodeRef());

        if (!payload.containsThrowable)
        {
            if (tokenId == TokenId::KwdAssume && assumeNullableResultTypeRef(sema, managedChildRef).isValid())
                return setupNullableAssume(sema, managedChildRef);

            return reportErrorManagementOperandNotThrowable(sema, sema.curNodeRef(), managedChildRef);
        }

        payload.isThrowableResult = tokenId == TokenId::KwdTry;
        if (payload.isThrowableResult)
            markCurrentErrorScopeThrowable(sema);

        switch (tokenId)
        {
            case TokenId::KwdCatch:
                SWC_RESULT(SemaHelpers::requireRuntimeCatchScopeDependencies(sema, sema.curNode().codeRef()));
                break;

            case TokenId::KwdTryCatch:
                SWC_RESULT(SemaHelpers::requireRuntimePopScopeDependencies(sema, sema.curNode().codeRef()));
                break;

            case TokenId::KwdAssume:
                SWC_RESULT(SemaHelpers::requireRuntimePopScopeDependencies(sema, sema.curNode().codeRef()));
                if (sema.frame().currentAttributes().hasRuntimeSafety(sema.buildCfg().safetyGuards, Runtime::SafetyWhat::Assume))
                {
                    auto& codeGenPayload = SemaHelpers::ensureCodeGenLoweringPayload(sema, sema.curNodeRef());
                    codeGenPayload.addRuntimeSafety(Runtime::SafetyWhat::Assume);
                    SWC_RESULT(SemaHelpers::requireRuntimeFunctionDependency(sema, IdentifierManager::RuntimeFunctionKind::FailedAssume, sema.curNode().codeRef()));
                }
                break;

            default:
                break;
        }

        attachThrowableWrapperToManagedChild(sema, sema.curNodeRef(), managedChildRef, tokenId);
        return Result::Continue;
    }

}

namespace
{
    using SemaHelpers::unwrapLambdaBindingType;

    const SymbolFunction* resolveCalledFunction(Sema& sema, Symbol* sym)
    {
        if (!sym)
            return nullptr;
        if (sym->isFunction())
            return &sym->cast<SymbolFunction>();
        if (sym->isAlias())
            return resolveCalledFunction(sema, const_cast<Symbol*>(sym->cast<SymbolAlias>().aliasedSymbol()));
        if (sym->isVariable())
            return SemaHelpers::callableTypeFunction(sema.ctx(), sym->typeRef());
        return nullptr;
    }

    bool hasCallableCalleeSymbols(Sema& sema, std::span<Symbol* const> symbols)
    {
        for (Symbol* sym : symbols)
        {
            if (resolveCalledFunction(sema, sym))
                return true;
        }

        return false;
    }

    bool canConsumeTrailingCodeBlockSyntax(Sema& sema, const SymbolFunction& fn)
    {
        if (fn.isClosure() || fn.isForeign())
            return false;

        const AttributeList& attributes = fn.attributes();
        if (attributes.hasRtFlag(RtAttributeFlagsE::Macro) || attributes.hasRtFlag(RtAttributeFlagsE::Mixin))
            return true;

        return SemaInline::canInlineCall(sema, fn);
    }

    void collectQuotedCalleeBaseSymbols(Sema& sema, const AstNode& calleeNode, SmallVector<Symbol*>& outSymbols)
    {
        AstNodeRef baseRef = AstNodeRef::invalid();
        if (const auto* quotedExpr = calleeNode.safeCast<AstQuotedExpr>())
            baseRef = quotedExpr->nodeExprRef;
        else if (const auto* quotedList = calleeNode.safeCast<AstQuotedListExpr>())
            baseRef = quotedList->nodeExprRef;
        else
            return;

        if (baseRef.isInvalid())
            return;

        SemaNodeView baseView(sema, baseRef, SemaNodeViewPartE::Symbol);
        baseView.getSymbols(outSymbols);
        if (!outSymbols.empty())
            return;

        baseView.compute(sema, baseRef, SemaNodeViewPartE::Symbol, SemaNodeViewResolveE::Stored);
        baseView.getSymbols(outSymbols);
    }

    void collectMemberCalleeSymbols(Sema& sema, const AstNode& calleeNode, SmallVector<Symbol*>& outSymbols)
    {
        AstNodeRef memberNameRef = AstNodeRef::invalid();
        if (const auto* memberAccess = calleeNode.safeCast<AstMemberAccessExpr>())
            memberNameRef = SemaHelpers::unwrapCallCalleeRef(sema, memberAccess->nodeRightRef);
        else if (const auto* autoMemberAccess = calleeNode.safeCast<AstAutoMemberAccessExpr>())
            memberNameRef = SemaHelpers::unwrapCallCalleeRef(sema, autoMemberAccess->nodeIdentRef);
        else
            return;

        if (memberNameRef.isInvalid())
            return;

        SemaNodeView memberView(sema, memberNameRef, SemaNodeViewPartE::Symbol);
        memberView.getSymbols(outSymbols);
        if (!outSymbols.empty())
            return;

        memberView.compute(sema, memberNameRef, SemaNodeViewPartE::Symbol, SemaNodeViewResolveE::Stored);
        memberView.getSymbols(outSymbols);
    }

    void collectCalleeSymbolsWithFallback(Sema& sema, const SemaNodeView& nodeCallee, SmallVector<Symbol*>& outSymbols)
    {
        nodeCallee.getSymbols(outSymbols);
        if (!hasCallableCalleeSymbols(sema, outSymbols))
        {
            SmallVector<Symbol*> quotedSymbols;
            collectQuotedCalleeBaseSymbols(sema, *nodeCallee.node(), quotedSymbols);
            if (hasCallableCalleeSymbols(sema, quotedSymbols.span()))
                outSymbols = std::move(quotedSymbols);
        }

        if (!hasCallableCalleeSymbols(sema, outSymbols))
        {
            SmallVector<Symbol*> memberSymbols;
            collectMemberCalleeSymbols(sema, *nodeCallee.node(), memberSymbols);
            if (hasCallableCalleeSymbols(sema, memberSymbols.span()))
                outSymbols = std::move(memberSymbols);
        }

        if (outSymbols.empty() && sema.isValue(nodeCallee.nodeRef()))
        {
            if (auto* symFunc = SemaHelpers::callableTypeFunction(sema.ctx(), nodeCallee.typeRef()))
                outSymbols.push_back(symFunc);
        }
    }

    bool isVoidCodeBlockParameter(Sema& sema, const SymbolVariable& param)
    {
        const TypeInfo& paramType = param.type(sema.ctx());
        return paramType.isCodeBlock() && paramType.payloadTypeRef() == sema.typeMgr().typeVoid();
    }

    bool isVoidCodeBlockParameter(Sema& sema, const SemaGeneric::GenericFunctionParamDesc& param)
    {
        if (!param.resolvedTypeRef.isValid())
            return false;

        const TypeRef   resolvedTypeRef  = sema.typeMgr().unwrapAliasEnum(sema.ctx(), param.resolvedTypeRef);
        const TypeRef   effectiveTypeRef = resolvedTypeRef.isValid() ? resolvedTypeRef : param.resolvedTypeRef;
        const TypeInfo& paramType        = sema.typeMgr().get(effectiveTypeRef);
        return paramType.isCodeBlock() && paramType.payloadTypeRef() == sema.typeMgr().typeVoid();
    }

    bool hasExplicitLastArgumentBinding(Sema& sema, const SymbolFunction& fn, std::span<const AstNodeRef> args, AstNodeRef ufcsArg)
    {
        const auto& params = fn.parameters();
        if (params.empty())
            return false;

        std::vector<uint8_t> assigned(params.size(), 0);
        if (ufcsArg.isValid())
            assigned[0] = 1;

        for (const AstNodeRef argRef : args)
        {
            const AstNode& argNode = sema.node(argRef);
            if (!argNode.is(AstNodeId::NamedArgument))
                continue;

            const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), argNode.codeRef());
            for (size_t paramIndex = 0; paramIndex < params.size(); ++paramIndex)
            {
                if (params[paramIndex]->idRef() == idRef)
                {
                    assigned[paramIndex] = 1;
                    break;
                }
            }
        }

        size_t nextParam = ufcsArg.isValid() ? 1 : 0;
        for (const AstNodeRef argRef : args)
        {
            const AstNode& argNode = sema.node(argRef);
            if (argNode.is(AstNodeId::NamedArgument))
                continue;

            while (nextParam < params.size() && assigned[nextParam])
                ++nextParam;
            if (nextParam >= params.size())
                break;

            assigned[nextParam] = 1;
            ++nextParam;
        }

        return assigned.back() != 0;
    }

    bool hasExplicitLastArgumentBinding(Sema& sema, std::span<const SemaGeneric::GenericFunctionParamDesc> params, std::span<const AstNodeRef> args, AstNodeRef ufcsArg)
    {
        if (params.empty())
            return false;

        std::vector<uint8_t> assigned(params.size(), 0);
        if (ufcsArg.isValid())
            assigned[0] = 1;

        for (const AstNodeRef argRef : args)
        {
            if (!sema.node(argRef).is(AstNodeId::NamedArgument))
                continue;

            const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), sema.node(argRef).codeRef());
            for (size_t paramIndex = 0; paramIndex < params.size(); ++paramIndex)
            {
                if (params[paramIndex].idRef == idRef)
                {
                    assigned[paramIndex] = 1;
                    break;
                }
            }
        }

        size_t nextParam = ufcsArg.isValid() ? 1 : 0;
        for (const AstNodeRef argRef : args)
        {
            if (sema.node(argRef).is(AstNodeId::NamedArgument))
                continue;

            while (nextParam < params.size() && assigned[nextParam])
                ++nextParam;
            if (nextParam >= params.size())
                break;

            assigned[nextParam] = 1;
            ++nextParam;
        }

        return assigned.back() != 0;
    }

    TypeRef consumableTrailingCodeBlockPayloadType(Sema& sema, const SymbolFunction& fn, std::span<const AstNodeRef> args, AstNodeRef ufcsArg)
    {
        if (!canConsumeTrailingCodeBlockSyntax(sema, fn))
            return TypeRef::invalid();

        SmallVector<SemaGeneric::GenericFunctionParamDesc> paramDescs;
        SemaGeneric::collectFunctionParamDescs(sema, fn, paramDescs);
        if (!paramDescs.empty())
        {
            if (isVoidCodeBlockParameter(sema, paramDescs.back()))
            {
                if (hasExplicitLastArgumentBinding(sema, paramDescs.span(), args, ufcsArg))
                    return TypeRef::invalid();
                return sema.typeMgr().typeVoid();
            }
        }

        const auto& params = fn.parameters();
        if (!params.empty())
        {
            if (!isVoidCodeBlockParameter(sema, *params.back()))
                return TypeRef::invalid();
            if (hasExplicitLastArgumentBinding(sema, fn, args, ufcsArg))
                return TypeRef::invalid();
            return params.back()->type(sema.ctx()).payloadTypeRef();
        }

        return TypeRef::invalid();
    }

    AstNodeRef findTrailingCodeBlockSibling(Sema& sema, AstNodeRef callRef)
    {
        AstNodeRef searchRef = callRef;
        for (size_t up = 0;; ++up)
        {
            const AstNode* parentNode = sema.visit().parentNode(up);
            if (!parentNode)
                return AstNodeRef::invalid();

            switch (parentNode->id())
            {
                case AstNodeId::EmbeddedBlock:
                case AstNodeId::FunctionBody:
                case AstNodeId::SwitchCaseBody:
                case AstNodeId::TopLevelBlock:
                    break;
                default:
                    return AstNodeRef::invalid();
            }

            SmallVector<AstNodeRef> children;
            parentNode->collectChildrenFromAst(children, sema.ast());

            bool wrappedInSingleStmtBlock = false;
            for (size_t childIndex = 0; childIndex < children.size(); ++childIndex)
            {
                if (children[childIndex] != searchRef)
                    continue;

                for (size_t nextIndex = childIndex + 1; nextIndex < children.size(); ++nextIndex)
                {
                    const AstNodeRef siblingRef = children[nextIndex];
                    if (siblingRef.isInvalid() || siblingRef == searchRef)
                        continue;

                    return sema.node(siblingRef).is(AstNodeId::EmbeddedBlock) ? siblingRef : AstNodeRef::invalid();
                }

                wrappedInSingleStmtBlock = parentNode->is(AstNodeId::EmbeddedBlock) && children.size() == 1;
                break;
            }

            if (!wrappedInSingleStmtBlock)
                return AstNodeRef::invalid();

            searchRef = sema.visit().parentNodeRef(up);
            if (searchRef.isInvalid())
                return AstNodeRef::invalid();
        }
    }

    AstNodeRef makeTrailingCodeBlockArgument(Sema& sema, AstNodeRef siblingRef, TypeRef payloadTypeRef)
    {
        auto [wrappedRef, wrappedPtr] = sema.ast().makeNode<AstNodeId::CompilerCodeBlock>(sema.node(siblingRef).tokRef());
        wrappedPtr->setCodeRef(sema.node(siblingRef).codeRef());
        wrappedPtr->nodeBodyRef    = siblingRef;
        wrappedPtr->payloadTypeRef = payloadTypeRef;
        return wrappedRef;
    }

    AstNodeRef resolveTrailingCodeBlockArgument(Sema& sema, const SemaNodeView& nodeCallee, std::span<Symbol*> symbols, std::span<const AstNodeRef> args, AstNodeRef ufcsArg, AstNodeRef& outSiblingRef)
    {
        outSiblingRef = findTrailingCodeBlockSibling(sema, sema.curNodeRef());
        if (outSiblingRef.isInvalid())
            return AstNodeRef::invalid();

        for (Symbol* sym : symbols)
        {
            const SymbolFunction* fn = resolveCalledFunction(sema, sym);
            if (!fn)
                continue;

            const TypeRef payloadTypeRef = consumableTrailingCodeBlockPayloadType(sema, *fn, args, ufcsArg);
            if (payloadTypeRef.isValid())
                return makeTrailingCodeBlockArgument(sema, outSiblingRef, payloadTypeRef);
        }

        if (symbols.empty() && sema.isValue(nodeCallee.nodeRef()))
        {
            const auto* fn = SemaHelpers::callableTypeFunction(sema.ctx(), nodeCallee.typeRef());
            if (fn)
            {
                const TypeRef payloadTypeRef = consumableTrailingCodeBlockPayloadType(sema, *fn, args, ufcsArg);
                if (payloadTypeRef.isValid())
                    return makeTrailingCodeBlockArgument(sema, outSiblingRef, payloadTypeRef);
            }
        }

        outSiblingRef.setInvalid();
        return AstNodeRef::invalid();
    }

    const SymbolFunction* uniqueInlineFunctionForCodeArgs(Sema& sema, AstNodeRef calleeRef)
    {
        const AstNode& calleeNode = sema.node(calleeRef);
        if (calleeNode.is(AstNodeId::MemberAccessExpr) || calleeNode.is(AstNodeId::AutoMemberAccessExpr))
            return nullptr;

        const SemaNodeView   nodeCallee = sema.view(calleeRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol);
        SmallVector<Symbol*> symbols;
        collectCalleeSymbolsWithFallback(sema, nodeCallee, symbols);

        if (symbols.size() != 1)
            return nullptr;

        const SymbolFunction* fn = resolveCalledFunction(sema, symbols.front());
        if (!fn || !SemaInline::canInlineCall(sema, *fn))
            return nullptr;

        return fn;
    }

    const SymbolVariable* mappedCallParameter(Sema& sema, std::span<const AstNodeRef> args, const SymbolFunction& fn, AstNodeRef childRef, AstNodeRef ufcsArg)
    {
        const auto& params = fn.parameters();
        if (params.empty())
            return nullptr;

        uint32_t paramStart = 0;
        if (ufcsArg.isValid())
        {
            if (childRef == ufcsArg)
                return params[0];
            paramStart = 1;
        }

        const AstNode& childNode = sema.node(childRef);
        if (childNode.is(AstNodeId::NamedArgument))
        {
            const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), childNode.codeRef());
            for (uint32_t i = paramStart; i < params.size(); ++i)
            {
                const SymbolVariable* param = params[i];
                if (param && param->idRef() == idRef)
                    return param;
            }

            return nullptr;
        }

        uint32_t positionalIndex = paramStart;
        bool     seenNamed       = false;
        for (const AstNodeRef argRef : args)
        {
            const AstNode& argNode = sema.node(argRef);
            if (argNode.is(AstNodeId::NamedArgument))
            {
                seenNamed = true;
                continue;
            }

            if (seenNamed)
                return nullptr;

            if (argRef != childRef)
            {
                ++positionalIndex;
                continue;
            }

            if (positionalIndex >= params.size())
                return nullptr;

            return params[positionalIndex];
        }

        return nullptr;
    }

    template<typename T>
    const SymbolVariable* mappedCodeParameter(Sema& sema, const T& call, const SymbolFunction& fn, AstNodeRef childRef)
    {
        SmallVector<AstNodeRef> args;
        call.collectArguments(args, sema.ast());
        const AstNodeRef      ufcsArg = resolveUfcsReceiverArg(sema, call.nodeExprRef);
        const SymbolVariable* param   = mappedCallParameter(sema, args.span(), fn, childRef, ufcsArg);
        return param && param->type(sema.ctx()).isCodeBlock() ? param : nullptr;
    }

    bool childCanConsumeLambdaBinding(const AstNode& node)
    {
        if (node.is(AstNodeId::FunctionExpr) || node.is(AstNodeId::ClosureExpr))
            return true;

        if (node.is(AstNodeId::ParenExpr))
            return true;

        if (node.is(AstNodeId::NamedArgument))
            return true;

        return false;
    }

    bool childCanConsumeContextualBinding(Sema& sema, AstNodeRef childRef)
    {
        if (childRef.isInvalid())
            return false;

        const AstNode& childNode = sema.node(childRef);
        if (childNode.is(AstNodeId::NamedArgument))
            return childCanConsumeContextualBinding(sema, childNode.cast<AstNamedArgument>().nodeArgRef);

        return SemaHelpers::canUseContextualBinding(sema, childRef);
    }

    template<typename T>
    Result resolveCallArgumentContextBindingType(Sema& sema, const T& call, AstNodeRef childRef, TypeRef& outBindingTypeRef)
    {
        outBindingTypeRef = TypeRef::invalid();
        if (!childCanConsumeContextualBinding(sema, childRef))
            return Result::Continue;

        const SemaNodeView   nodeCallee = sema.view(call.nodeExprRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol);
        SmallVector<Symbol*> symbols;
        collectCalleeSymbolsWithFallback(sema, nodeCallee, symbols);
        SmallVector<AstNodeRef> args;
        call.collectArguments(args, sema.ast());

        const AstNodeRef ufcsArg = resolveUfcsReceiverArg(sema, call.nodeExprRef);
        for (Symbol* sym : symbols)
        {
            const SymbolFunction* fn = resolveCalledFunction(sema, sym);
            if (!fn)
                continue;

            TypeRef               paramTypeRef = TypeRef::invalid();
            const SymbolVariable* param        = mappedCallParameter(sema, args.span(), *fn, childRef, ufcsArg);
            if (param)
                paramTypeRef = param->typeRef();
            else if (fn->parameters().empty() && !fn->isGenericRoot())
                SWC_RESULT(SemaGeneric::resolveFunctionCallParamType(sema, *fn, call.nodeExprRef, args.span(), ufcsArg, childRef, paramTypeRef));

            if (!paramTypeRef.isValid())
                continue;

            if (outBindingTypeRef.isInvalid())
            {
                outBindingTypeRef = paramTypeRef;
                continue;
            }

            if (outBindingTypeRef != paramTypeRef)
            {
                outBindingTypeRef = TypeRef::invalid();
                return Result::Continue;
            }
        }

        return Result::Continue;
    }

    template<typename T>
    Result resolveCallArgumentLambdaBindingType(Sema& sema, const T& call, AstNodeRef childRef, TypeRef& outBindingTypeRef)
    {
        outBindingTypeRef        = TypeRef::invalid();
        const AstNode& childNode = sema.node(childRef);
        if (!childCanConsumeLambdaBinding(childNode))
            return Result::Continue;

        const SemaNodeView   nodeCallee = sema.view(call.nodeExprRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol);
        SmallVector<Symbol*> symbols;
        collectCalleeSymbolsWithFallback(sema, nodeCallee, symbols);
        SmallVector<AstNodeRef> args;
        call.collectArguments(args, sema.ast());

        const AstNodeRef ufcsArg        = resolveUfcsReceiverArg(sema, call.nodeExprRef);
        TypeRef          compareTypeRef = TypeRef::invalid();

        for (Symbol* sym : symbols)
        {
            const SymbolFunction* fn = resolveCalledFunction(sema, sym);
            if (!fn)
                continue;

            TypeRef               paramTypeRef = TypeRef::invalid();
            const SymbolVariable* param        = mappedCallParameter(sema, args.span(), *fn, childRef, ufcsArg);
            if (param)
                paramTypeRef = param->typeRef();
            else if (fn->parameters().empty())
                SWC_RESULT(SemaGeneric::resolveFunctionCallParamType(sema, *fn, call.nodeExprRef, args.span(), ufcsArg, childRef, paramTypeRef));

            if (!paramTypeRef.isValid())
                continue;

            const TypeRef resolvedTypeRef = unwrapLambdaBindingType(sema.ctx(), paramTypeRef);
            if (!resolvedTypeRef.isValid() || !sema.typeMgr().get(resolvedTypeRef).isFunction())
                continue;

            if (compareTypeRef.isInvalid())
            {
                outBindingTypeRef = paramTypeRef;
                compareTypeRef    = resolvedTypeRef;
                continue;
            }

            if (compareTypeRef != resolvedTypeRef)
            {
                outBindingTypeRef = TypeRef::invalid();
                return Result::Continue;
            }
        }

        return Result::Continue;
    }

    bool isCallAliasChild(const AstCallExpr&, const Ast&, AstNodeRef)
    {
        return false;
    }

    bool isCallAliasChild(const AstIntrinsicCallExpr&, const Ast&, AstNodeRef)
    {
        return false;
    }

    bool isCallAliasChild(const AstAliasCallExpr& call, const Ast& ast, AstNodeRef childRef)
    {
        for (size_t i = 0; i < ast.spanSize(call.spanAliasesRef); ++i)
        {
            if (ast.nthNode(call.spanAliasesRef, i) == childRef)
                return true;
        }

        return false;
    }

    template<typename T>
    Result semaCallExprPreNodeChildCommon(Sema& sema, const T& node, AstNodeRef childRef)
    {
        if (childRef == node.nodeExprRef)
            return Result::Continue;

        if (isCallAliasChild(node, sema.ast(), childRef))
            return Result::SkipChildren;

        if (const SymbolFunction* fn = uniqueInlineFunctionForCodeArgs(sema, node.nodeExprRef))
        {
            if (mappedCodeParameter(sema, node, *fn, childRef))
                return Result::SkipChildren;
        }

        if (isAttributeContextCall(node))
            SemaHelpers::pushConstExprRequirement(sema, childRef);

        TypeRef bindingTypeRef = TypeRef::invalid();
        SWC_RESULT(resolveCallArgumentContextBindingType(sema, node, childRef, bindingTypeRef));
        if (!bindingTypeRef.isValid())
            SWC_RESULT(resolveCallArgumentLambdaBindingType(sema, node, childRef, bindingTypeRef));
        if (bindingTypeRef.isValid())
        {
            auto frame = sema.frame();
            frame.pushBindingType(bindingTypeRef);
            sema.pushFramePopOnPostChild(frame, childRef);
        }

        return Result::Continue;
    }

    Result setupIntrinsicGetContextRuntimeCall(Sema& sema, const AstIntrinsicCallExpr& node)
    {
        if (sema.isNativeBuild())
        {
            SWC_RESULT(SemaHelpers::requireRuntimeFunctionDependency(sema, IdentifierManager::RuntimeFunctionKind::TlsAlloc, node.codeRef()));
            return SemaHelpers::requireRuntimeFunctionDependency(sema, IdentifierManager::RuntimeFunctionKind::TlsGetPtr, node.codeRef());
        }

        return SemaHelpers::attachRuntimeFunctionToNode(sema, sema.curNodeRef(), IdentifierManager::RuntimeFunctionKind::TlsGetValue, node.codeRef());
    }

    Result setupIntrinsicSetContextRuntimeCall(Sema& sema, const AstIntrinsicCallExpr& node)
    {
        if (sema.isNativeBuild())
            SWC_RESULT(SemaHelpers::requireRuntimeFunctionDependency(sema, IdentifierManager::RuntimeFunctionKind::TlsAlloc, node.codeRef()));

        return SemaHelpers::attachRuntimeFunctionToNode(sema, sema.curNodeRef(), IdentifierManager::RuntimeFunctionKind::TlsSetValue, node.codeRef());
    }

    Result setupIntrinsicAssertRuntimeCall(Sema& sema, const AstIntrinsicCallExpr& node)
    {
        return SemaHelpers::attachRuntimeFunctionToNode(sema, sema.curNodeRef(), IdentifierManager::RuntimeFunctionKind::RaiseException, node.codeRef());
    }

    bool intrinsicNeedsMathRuntimeSafety(const TokenId tokenId)
    {
        switch (tokenId)
        {
            case TokenId::IntrinsicSqrt:
            case TokenId::IntrinsicASin:
            case TokenId::IntrinsicACos:
            case TokenId::IntrinsicLog:
            case TokenId::IntrinsicLog2:
            case TokenId::IntrinsicLog10:
            case TokenId::IntrinsicPow:
                return true;

            default:
                return false;
        }
    }

    Result setupIntrinsicMathRuntimeSafety(Sema& sema, const AstIntrinsicCallExpr& node)
    {
        if (sema.viewConstant(sema.curNodeRef()).hasConstant())
            return Result::Continue;
        if (!intrinsicNeedsMathRuntimeSafety(sema.token(node.codeRef()).id))
            return Result::Continue;
        return SemaHelpers::setupRuntimeSafetyPanic(sema, sema.curNodeRef(), Runtime::SafetyWhat::Math, node.codeRef());
    }

    bool isAliasPreservingNumericIntrinsic(TokenId tokenId)
    {
        switch (tokenId)
        {
            case TokenId::IntrinsicAbs:
            case TokenId::IntrinsicMin:
            case TokenId::IntrinsicMax:
            case TokenId::IntrinsicRol:
            case TokenId::IntrinsicRor:
            case TokenId::IntrinsicByteSwap:
            case TokenId::IntrinsicBitCountNz:
            case TokenId::IntrinsicBitCountTz:
            case TokenId::IntrinsicBitCountLz:
            case TokenId::IntrinsicAtomicAdd:
            case TokenId::IntrinsicAtomicAnd:
            case TokenId::IntrinsicAtomicOr:
            case TokenId::IntrinsicAtomicXor:
            case TokenId::IntrinsicAtomicXchg:
            case TokenId::IntrinsicAtomicCmpXchg:
                return true;

            default:
                return false;
        }
    }

    TypeRef aliasStorageTypeRef(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        if (!typeInfo.isAlias())
            return TypeRef::invalid();

        return typeInfo.unwrap(sema.ctx(), typeRef, TypeExpandE::Alias);
    }

    TypeRef intrinsicAliasOperandResultTypeRef(Sema& sema, AstNodeRef operandRef, TypeRef selectedReturnTypeRef)
    {
        const TypeRef operandTypeRef = sema.viewType(operandRef).typeRef();
        const TypeRef storageTypeRef = aliasStorageTypeRef(sema, operandTypeRef);
        if (!storageTypeRef.isValid() || storageTypeRef != selectedReturnTypeRef)
            return TypeRef::invalid();

        const TypeInfo& storageType = sema.typeMgr().get(storageTypeRef);
        if (!storageType.isScalarNumeric())
            return TypeRef::invalid();
        return operandTypeRef;
    }

    Result applyAliasPreservingIntrinsicResultType(Sema& sema, const AstIntrinsicCallExpr& node, std::span<AstNodeRef> args)
    {
        const TokenId tokenId = sema.token(node.codeRef()).id;
        if (!isAliasPreservingNumericIntrinsic(tokenId) || args.empty())
            return Result::Continue;

        const TypeRef selectedReturnTypeRef = sema.viewType(sema.curNodeRef()).typeRef();
        if (!selectedReturnTypeRef.isValid())
            return Result::Continue;

        TypeRef resultTypeRef = TypeRef::invalid();
        switch (tokenId)
        {
            case TokenId::IntrinsicMin:
            case TokenId::IntrinsicMax:
            {
                if (args.size() != 2)
                    return Result::Continue;

                resultTypeRef = intrinsicAliasOperandResultTypeRef(sema, args[0], selectedReturnTypeRef);
                if (!resultTypeRef.isValid())
                    return Result::Continue;

                const TypeRef rightStorageTypeRef = aliasStorageTypeRef(sema, sema.viewType(args[1]).typeRef());
                if (rightStorageTypeRef.isValid() && rightStorageTypeRef != selectedReturnTypeRef)
                    return Result::Continue;
                break;
            }

            case TokenId::IntrinsicAtomicAdd:
            case TokenId::IntrinsicAtomicAnd:
            case TokenId::IntrinsicAtomicOr:
            case TokenId::IntrinsicAtomicXor:
            case TokenId::IntrinsicAtomicXchg:
            case TokenId::IntrinsicAtomicCmpXchg:
            {
                if (args.size() < 2)
                    return Result::Continue;

                resultTypeRef = intrinsicAliasOperandResultTypeRef(sema, args[1], selectedReturnTypeRef);
                break;
            }

            default:
                resultTypeRef = intrinsicAliasOperandResultTypeRef(sema, args[0], selectedReturnTypeRef);
                break;
        }

        if (resultTypeRef.isValid())
            sema.setType(sema.curNodeRef(), resultTypeRef);
        return Result::Continue;
    }

    template<typename T>
    Result semaCallExprCommon(Sema& sema, const T& node, bool tryIntrinsicFold)
    {
        const SemaNodeView nodeCallee = sema.view(node.nodeExprRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol);

        SmallVector<AstNodeRef> args;
        node.collectArguments(args, sema.ast());
        SmallVector<AstNodeRef> sourceArgs = args;
        for (auto& arg : args)
            arg = Match::resolveCallArgumentRef(sema, arg);

        SmallVector<Symbol*> symbols;
        collectCalleeSymbolsWithFallback(sema, nodeCallee, symbols);

        AstNodeRef ufcsArg = resolveUfcsReceiverArg(sema, node.nodeExprRef);

        AstNodeRef       trailingBlockSiblingRef = AstNodeRef::invalid();
        const AstNodeRef trailingBlockArgRef     = resolveTrailingCodeBlockArgument(sema, nodeCallee, symbols, args.span(), ufcsArg, trailingBlockSiblingRef);
        if (trailingBlockArgRef.isValid())
        {
            if (trailingBlockSiblingRef.isValid())
                sema.markImplicitCodeBlockArg(sema.visit().parentNodeRef(), trailingBlockSiblingRef);
            args.push_back(trailingBlockArgRef);
            sourceArgs.push_back(trailingBlockArgRef);
        }

        SmallVector<ResolvedCallArgument> resolvedArgs;
        auto                              resolveMode = isAttributeContextCall(node) ? Match::ResolveCallMode::AttributeOnly : Match::ResolveCallMode::Normal;
        if constexpr (std::is_same_v<T, AstIntrinsicCallExpr>)
            resolveMode = Match::ResolveCallMode::Intrinsic;
        const Result resolveResult = Match::resolveFunctionCandidates(sema, nodeCallee, symbols, args, ufcsArg, &resolvedArgs, resolveMode);
        SWC_RESULT(resolveResult);
        sema.setResolvedCallArguments(sema.curNodeRef(), resolvedArgs);
        const SemaNodeView nodeSymView = sema.curViewSymbol();
        SWC_ASSERT(nodeSymView.hasSymbol());

        auto&        calledFn   = nodeSymView.sym()->cast<SymbolFunction>();
        const Result lazyResult = sema.completeLazyGenericFunction(calledFn);
        SWC_RESULT(lazyResult);

        const bool isMixinCall = calledFn.attributes().hasRtFlag(RtAttributeFlagsE::Mixin);
        const bool isMacroCall = calledFn.attributes().hasRtFlag(RtAttributeFlagsE::Macro);
        auto*      currentFn   = sema.currentFunction();
        if (currentFn &&
            currentFn->decl() &&
            calledFn.decl() &&
            calledFn.declNodeRef().isValid() &&
            !calledFn.isForeign() &&
            !calledFn.isEmpty() &&
            !isMixinCall &&
            !isMacroCall)
            currentFn->addCallDependency(&calledFn);

        if (calledFn.isThrowable())
        {
            markCurrentErrorScopeThrowable(sema);
            if (!canPropagateThrowableResult(sema))
                return reportThrowableCallRequiresContext(sema, calledFn, sema.curNodeRef());

            SWC_RESULT(SemaHelpers::requireRuntimeFunctionDependency(sema, IdentifierManager::RuntimeFunctionKind::HasErr, sema.curNode().codeRef()));
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
            if constexpr (std::is_same_v<T, AstIntrinsicCallExpr>)
                SWC_RESULT(applyAliasPreservingIntrinsicResultType(sema, node, args));
            SWC_RESULT(ConstantIntrinsic::tryConstantFoldCall(sema, calledFn, args));
        }
        else
        {
            SWC_RESULT(SemaJIT::tryRunConstCall(sema, calledFn, sema.curNodeRef(), resolvedArgs.span()));
            if (sema.viewConstant(sema.curNodeRef()).hasConstant())
                return Result::Continue;
            SWC_RESULT(SemaInline::tryInlineCall(sema, sema.curNodeRef(), calledFn, args, ufcsArg, sourceArgs.span()));
        }

        if (sema.viewConstant(sema.curNodeRef()).hasConstant())
            return Result::Continue;
        if (sema.hasSubstitute(sema.curNodeRef()))
            return Result::Continue;

        SWC_RESULT(SemaHelpers::attachIndirectReturnRuntimeStorageIfNeeded(sema, node, calledFn, "__call_runtime_storage"));

        if (!returnType.isVoid())
        {
            sema.setIsValue(sema.curNodeRef());
            if (returnType.isReference())
                sema.setIsLValue(sema.curNodeRef());
            else
                sema.unsetIsLValue(sema.curNodeRef());
        }

        return Result::Continue;
    }
}

Result AstCallExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    return semaCallExprPreNodeChildCommon(sema, *this, childRef);
}

Result AstCallExpr::semaPostNode(Sema& sema) const
{
    return semaCallExprCommon(sema, *this, false);
}

Result AstAliasCallExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    return semaCallExprPreNodeChildCommon(sema, *this, childRef);
}

Result AstAliasCallExpr::semaPostNode(Sema& sema) const
{
    return semaCallExprCommon(sema, *this, false);
}

Result AstIntrinsicCallExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    return semaCallExprPreNodeChildCommon(sema, *this, childRef);
}

Result AstIntrinsicCallExpr::semaPostNode(Sema& sema) const
{
    SWC_RESULT(semaCallExprCommon(sema, *this, true));

    const Token& tok = sema.token(codeRef());
    if (tok.id == TokenId::IntrinsicGetContext)
        SWC_RESULT(setupIntrinsicGetContextRuntimeCall(sema, *this));
    else if (tok.id == TokenId::IntrinsicSetContext)
        SWC_RESULT(setupIntrinsicSetContextRuntimeCall(sema, *this));
    else if (tok.id == TokenId::IntrinsicAssert)
        SWC_RESULT(setupIntrinsicAssertRuntimeCall(sema, *this));
    else if (tok.id == TokenId::IntrinsicGvtd)
    {
        if (SymbolFunction* fn = sema.currentFunction())
            fn->setUsesGvtd();
    }

    SWC_RESULT(setupIntrinsicMathRuntimeSafety(sema, *this));
    return Result::Continue;
}

Result AstTryCatchExpr::semaPreNode(Sema& sema)
{
    return semaTryCatchPreNodeCommon(sema);
}

Result AstTryCatchExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    return semaTryCatchPreNodeChildCommon(sema, nodeExprRef, childRef);
}

Result AstTryCatchExpr::semaPostNode(Sema& sema) const
{
    SWC_RESULT(semaTryCatchPostNodeCommon(sema, nodeExprRef));

    const AstNodeRef   resolvedExprRef = sema.viewZero(nodeExprRef).nodeRef();
    const SemaNodeView exprView        = sema.viewNodeTypeConstant(resolvedExprRef);
    sema.inheritPayloadFlags(sema.curNode(), resolvedExprRef);
    TypeRef resultTypeRef = exprView.typeRef();
    const auto* codeGenPayload = sema.loweringPayload<CodeGenLoweringPayload>(sema.curNodeRef());
    if (codeGenPayload && codeGenPayload->assumeNullable)
        resultTypeRef = assumeNullableResultTypeRef(sema, nodeExprRef);
    sema.setType(sema.curNodeRef(), resultTypeRef);
    const bool requiresNullableAssumeRuntimeCheck = codeGenPayload && codeGenPayload->assumeNullable && codeGenPayload->hasRuntimeSafety(Runtime::SafetyWhat::Assume);
    if (exprView.cstRef().isValid() && !requiresNullableAssumeRuntimeCheck)
        sema.setConstant(sema.curNodeRef(), exprView.cstRef());
    sema.copyResolvedCallArguments(sema.curNodeRef(), resolvedExprRef);

    const TokenId tokenId = effectiveErrorManagementTokenId(sema, sema.token(codeRef()).id);
    if (tokenId != TokenId::KwdTry && resultTypeRef.isValid() && resultTypeRef != sema.typeMgr().typeVoid())
        SWC_RESULT(SemaHelpers::attachRuntimeStorageIfNeeded(sema, resolvedExprRef, *this, resultTypeRef, "__trycatch_runtime_storage"));

    return Result::Continue;
}

Result AstTryCatchStmt::semaPreNode(Sema& sema)
{
    return semaTryCatchPreNodeCommon(sema);
}

Result AstTryCatchStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    return semaTryCatchPreNodeChildCommon(sema, nodeBodyRef, childRef);
}

Result AstTryCatchStmt::semaPostNode(Sema& sema) const
{
    return semaTryCatchPostNodeCommon(sema, nodeBodyRef);
}

Result AstThrowExpr::semaPostNode(Sema& sema) const
{
    const SemaNodeView exprView = sema.viewNodeTypeConstant(nodeExprRef);
    SWC_RESULT(SemaCheck::isValue(sema, exprView.nodeRef()));

    if (!canPropagateThrowableResult(sema))
        return reportThrowOutsideThrowableContext(sema, sema.curNodeRef());

    auto& payload             = ensureErrorManagementPayload(sema, sema.curNodeRef());
    payload.containsThrowable = true;
    payload.isThrowableResult = true;
    markCurrentErrorScopeThrowable(sema);
    SWC_RESULT(SemaHelpers::requireRuntimeFunctionDependency(sema, IdentifierManager::RuntimeFunctionKind::SetErrRaw, codeRef()));
    SWC_RESULT(SemaHelpers::attachRuntimeStorageIfNeeded(sema, sema.curNodeRef(), *this, exprView.typeRef(), "__throw_runtime_storage"));

    sema.setType(sema.curNodeRef(), preferredThrowResultType(sema));
    sema.setIsValue(sema.curNodeRef());
    sema.unsetIsLValue(sema.curNodeRef());
    return Result::Continue;
}

Result AstDiscardExpr::semaPostNode(Sema& sema)
{
    sema.setType(sema.curNodeRef(), sema.typeMgr().typeVoid());
    return Result::Continue;
}

SWC_END_NAMESPACE();
