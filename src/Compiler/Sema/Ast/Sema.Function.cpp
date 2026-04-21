#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantIntrinsic.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
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
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    const SymbolImpl* functionDeclImplContext(Sema& sema, const SymbolFunction* symFunc = nullptr)
    {
        if (symFunc)
        {
            if (const auto* symImpl = symFunc->declImplContext())
                return symImpl;
        }

        if (const auto* symImpl = sema.frame().currentImpl())
            return symImpl;

        for (SymbolMap* symMap = sema.curSymMap(); symMap; symMap = symMap->ownerSymMap())
        {
            if (symMap->isImpl())
                return &symMap->cast<SymbolImpl>();
        }

        return nullptr;
    }

    const SymbolInterface* functionDeclInterfaceContext(Sema& sema, const SymbolFunction* symFunc = nullptr)
    {
        if (symFunc)
        {
            if (const auto* symItf = symFunc->declInterfaceContext())
                return symItf;
        }

        if (const auto* symItf = sema.frame().currentInterface())
            return symItf;

        if (const auto* symImpl = sema.frame().currentImpl())
        {
            if (const auto* symItf = symImpl->symInterface())
                return symItf;
        }

        for (SymbolMap* symMap = sema.curSymMap(); symMap; symMap = symMap->ownerSymMap())
        {
            if (symMap->isInterface())
                return &symMap->cast<SymbolInterface>();

            if (symMap->isImpl())
            {
                if (const auto* symItf = symMap->cast<SymbolImpl>().symInterface())
                    return symItf;
            }
        }

        return nullptr;
    }

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
                        return innerMember.nodeLeftRef;
                }
            }

            return outerMember.nodeLeftRef;
        }

        if (outerMember.nodeLeftRef.isInvalid() ||
            sema.node(outerMember.nodeLeftRef).isNot(AstNodeId::MemberAccessExpr))
            return AstNodeRef::invalid();

        const auto& innerMember = sema.node(outerMember.nodeLeftRef).cast<AstMemberAccessExpr>();
        if (isNestedUfcsReceiverValue(sema, innerMember.nodeLeftRef))
            return innerMember.nodeLeftRef;

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
}

Result AstFunctionDecl::semaPreDecl(Sema& sema) const
{
    auto& sym = SemaHelpers::registerSymbol<SymbolFunction>(sema, *this, tokNameRef);

    sym.setExtraFlags(flags());
    sym.setDeclNodeRef(sema.curNodeRef());
    sym.setSpecOpKind(SemaSpecOp::computeSymbolKind(sema, sym));

    if (sym.ownerSymMap() &&
        sym.ownerSymMap()->isImpl() &&
        sym.specOpKind() != SpecOpKind::None &&
        sym.specOpKind() != SpecOpKind::Invalid)
    {
        sym.ownerSymMap()->cast<SymbolImpl>().addFunction(sema.ctx(), &sym);
    }

    sym.setGenericRoot(spanGenericParamsRef.isValid());
    if (nodeBodyRef.isInvalid())
        sym.addExtraFlag(SymbolFunctionFlagsE::Empty);

    return Result::SkipChildren;
}

Result AstFunctionDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);

    auto&       sym      = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    const auto* declImpl = functionDeclImplContext(sema, &sym);
    const auto* declItf  = functionDeclInterfaceContext(sema, &sym);
    if (sym.isMethod() && !declImpl && !declItf)
    {
        const SourceView& srcView   = sema.srcView(srcViewRef());
        const TokenRef    mtdTokRef = srcView.findLeftFrom(tokNameRef, {TokenId::KwdMtd});
        return SemaError::raise(sema, DiagnosticId::sema_err_method_outside_impl, SourceCodeRef{srcViewRef(), mtdTokRef});
    }

    if (sym.isGenericRoot() && !sym.isGenericInstance())
    {
        SWC_RESULT(SemaSpecOp::validateSymbol(sema, sym));
        sym.setSemaCompleted(sema.ctx());
        return Result::SkipChildren;
    }

    SemaFrame frame           = sema.frame();
    frame.currentAttributes() = sym.attributes();
    frame.setCurrentImpl(declImpl);
    frame.setCurrentInterface(declItf);
    frame.setCurrentFunction(&sym);
    frame.setCurrentErrorContext(AstNodeRef::invalid(), SemaFrame::ErrorContextMode::None);
    sema.pushFramePopOnPostNode(frame);
    return Result::Continue;
}

Result AstFunctionExpr::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
    {
        TaskContext& ctx = sema.ctx();
        auto*        sym = Symbol::make<SymbolFunction>(ctx, this, tokRef(), SemaHelpers::getUniqueIdentifier(sema, "__lambda"), sema.frame().flagsForCurrentAccess());
        SymbolMap*   map = SemaFrame::currentSymMap(sema);
        SWC_ASSERT(map != nullptr);
        map->addSymbol(ctx, sym, true);

        sym->setExtraFlags(flags());
        sym->setDeclNodeRef(sema.curNodeRef());
        sym->setSpecOpKind(SemaSpecOp::computeSymbolKind(sema, *sym));
        sym->setDeclared(ctx);
        sema.setSymbol(sema.curNodeRef(), sym);

        SemaHelpers::addCurrentFunctionCallDependency(sema, sym);
    }

    auto&     sym   = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    SemaFrame frame = sema.frame();
    frame.setCurrentFunction(&sym);
    frame.setCurrentErrorContext(AstNodeRef::invalid(), SemaFrame::ErrorContextMode::None);
    sema.pushFramePopOnPostNode(frame);
    return Result::Continue;
}

Result AstClosureExpr::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
    {
        TaskContext& ctx = sema.ctx();
        auto*        sym = Symbol::make<SymbolFunction>(ctx, this, tokRef(), SemaHelpers::getUniqueIdentifier(sema, "__closure"), sema.frame().flagsForCurrentAccess());
        SymbolMap*   map = SemaFrame::currentSymMap(sema);
        SWC_ASSERT(map != nullptr);
        map->addSymbol(ctx, sym, true);

        sym->setExtraFlags(flags());
        sym->setDeclNodeRef(sema.curNodeRef());
        sym->setSpecOpKind(SemaSpecOp::computeSymbolKind(sema, *sym));
        sym->setDeclared(ctx);
        sema.setSymbol(sema.curNodeRef(), sym);

        SemaHelpers::addCurrentFunctionCallDependency(sema, sym);
    }

    auto&     sym   = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    SemaFrame frame = sema.frame();
    frame.setCurrentFunction(&sym);
    frame.setCurrentErrorContext(AstNodeRef::invalid(), SemaFrame::ErrorContextMode::None);
    sema.pushFramePopOnPostNode(frame);
    return Result::Continue;
}

namespace
{

    SymbolFunction& functionExprSymbol(Sema& sema, AstNodeRef nodeRef)
    {
        if (Symbol* sym = sema.viewSymbol(nodeRef).sym())
            return sym->cast<SymbolFunction>();

        const TypeRef typeRef = sema.viewType(nodeRef).typeRef();
        SWC_ASSERT(typeRef.isValid());
        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        SWC_ASSERT(typeInfo.isFunction());
        return typeInfo.payloadSymFunction();
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

    using SemaHelpers::resolveLambdaBindingFunction;
    using SemaHelpers::unwrapLambdaBindingType;

    Result findCompatibleReturnBindingType(Sema& sema, AstNodeRef exprRef, TypeRef& outTypeRef)
    {
        outTypeRef = TypeRef::invalid();
        if (exprRef.isInvalid())
            return Result::Continue;

        const SemaNodeView exprView = sema.viewNodeTypeConstant(exprRef);
        const auto         frames   = sema.frames();
        for (size_t frameIndex = frames.size(); frameIndex > 0; --frameIndex)
        {
            const std::span<const TypeRef> bindingTypes = frames[frameIndex - 1].bindingTypes();
            for (size_t bindingIndex = bindingTypes.size(); bindingIndex > 0; --bindingIndex)
            {
                const TypeRef bindingTypeRef = bindingTypes[bindingIndex - 1];
                if (!bindingTypeRef.isValid())
                    continue;

                CastRequest castRequest(CastKind::Implicit);
                castRequest.errorNodeRef = exprRef;
                const Result castResult  = Cast::castAllowed(sema, castRequest, exprView.typeRef(), bindingTypeRef);
                if (castResult == Result::Pause)
                    return Result::Pause;
                if (castResult != Result::Continue)
                    continue;

                outTypeRef = bindingTypeRef;
                return Result::Continue;
            }
        }

        return Result::Continue;
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

        const auto attachWrapper = [&](AstNodeRef targetRef) {
            if (!targetRef.isValid())
                return;

            CodeGenNodePayload& payload      = SemaHelpers::ensureCodeGenNodePayload(sema, targetRef);
            payload.throwableWrapperOwnerRef = ownerRef;
            payload.throwableWrapperTokenId  = tokenId;
            payload.throwableFailLabel       = MicroLabelRef::invalid();
            payload.throwableDoneLabel       = MicroLabelRef::invalid();
        };

        attachWrapper(ownerRef);

        const auto attachInlineRootIfCallLike = [&](AstNodeRef targetRef) {
            if (!targetRef.isValid())
                return;

            const AstNodeId nodeId = sema.node(targetRef).id();
            if (nodeId == AstNodeId::CallExpr || nodeId == AstNodeId::AliasCallExpr)
                attachWrapper(targetRef);
        };

        attachInlineRootIfCallLike(managedChildRef);
        attachInlineRootIfCallLike(sema.viewZero(managedChildRef).nodeRef());
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
        return isThrowableFunctionContext(sema) || sema.frame().currentErrorContextMode() != SemaFrame::ErrorContextMode::None;
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

        if (const auto* fn = calledFunctionFromNode(sema, childRef); fn && !fn->isThrowable())
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
            return reportErrorManagementOperandNotThrowable(sema, sema.curNodeRef(), managedChildRef);

        payload.isThrowableResult = tokenId == TokenId::KwdTry;
        if (payload.isThrowableResult)
            markCurrentErrorScopeThrowable(sema);

        switch (tokenId)
        {
            case TokenId::KwdCatch:
                SWC_RESULT(SemaHelpers::requireRuntimeFunctionDependency(sema, IdentifierManager::RuntimeFunctionKind::PushErr, sema.curNode().codeRef()));
                SWC_RESULT(SemaHelpers::requireRuntimeFunctionDependency(sema, IdentifierManager::RuntimeFunctionKind::CatchErr, sema.curNode().codeRef()));
                break;

            case TokenId::KwdTryCatch:
                SWC_RESULT(SemaHelpers::requireRuntimeFunctionDependency(sema, IdentifierManager::RuntimeFunctionKind::PushErr, sema.curNode().codeRef()));
                SWC_RESULT(SemaHelpers::requireRuntimeFunctionDependency(sema, IdentifierManager::RuntimeFunctionKind::PopErr, sema.curNode().codeRef()));
                break;

            case TokenId::KwdAssume:
                SWC_RESULT(SemaHelpers::requireRuntimeFunctionDependency(sema, IdentifierManager::RuntimeFunctionKind::PushErr, sema.curNode().codeRef()));
                SWC_RESULT(SemaHelpers::requireRuntimeFunctionDependency(sema, IdentifierManager::RuntimeFunctionKind::PopErr, sema.curNode().codeRef()));
                if (sema.frame().currentAttributes().hasRuntimeSafety(sema.buildCfg().safetyGuards, Runtime::SafetyWhat::Assume))
                {
                    auto& codeGenPayload = SemaHelpers::ensureCodeGenNodePayload(sema, sema.curNodeRef());
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

    TypeRef deduceHomogeneousAggregateArrayType(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        if (type.isArray())
            return typeRef;
        if (!type.isAggregateArray())
            return TypeRef::invalid();

        const auto& elemTypes = type.payloadAggregate().types;
        if (elemTypes.empty())
            return TypeRef::invalid();

        TypeRef concreteElemTypeRef = TypeRef::invalid();
        for (TypeRef elemTypeRef : elemTypes)
        {
            const TypeInfo& elemType = sema.typeMgr().get(elemTypeRef);
            if (elemType.isAggregateArray())
                elemTypeRef = deduceHomogeneousAggregateArrayType(sema, elemTypeRef);

            if (!elemTypeRef.isValid())
                return TypeRef::invalid();

            if (!concreteElemTypeRef.isValid())
                concreteElemTypeRef = elemTypeRef;
            else if (concreteElemTypeRef != elemTypeRef)
                return TypeRef::invalid();
        }

        SmallVector4<uint64_t> dims;
        dims.push_back(elemTypes.size());
        return sema.typeMgr().addType(TypeInfo::makeArray(dims.span(), concreteElemTypeRef));
    }

    Result concretizeImplicitReturnTypeIfNeeded(Sema& sema, AstNodeRef exprRef, TypeRef& ioTypeRef)
    {
        if (exprRef.isInvalid() || !ioTypeRef.isValid())
            return Result::Continue;

        const TypeInfo& typeInfo = sema.typeMgr().get(ioTypeRef);
        if (typeInfo.isScalarUnsized() && sema.viewConstant(exprRef).hasConstant())
        {
            const ConstantRef exprCstRef = sema.viewConstant(exprRef).cstRef();
            SWC_ASSERT(exprCstRef.isValid());

            ConstantRef concretizedCstRef = ConstantRef::invalid();
            SWC_RESULT(Cast::concretizeConstant(sema, concretizedCstRef, exprRef, exprCstRef, TypeInfo::Sign::Unknown));
            if (concretizedCstRef.isValid())
            {
                sema.setConstant(exprRef, concretizedCstRef);
                ioTypeRef = sema.cstMgr().get(concretizedCstRef).typeRef();
            }
        }

        const TypeInfo& concretizedTypeInfo = sema.typeMgr().get(ioTypeRef);
        if (concretizedTypeInfo.isIntUnsized())
        {
            TypeInfo::Sign sign = concretizedTypeInfo.payloadIntSign();
            if (sign == TypeInfo::Sign::Unknown)
                sign = TypeInfo::Sign::Signed;

            const TypeRef concreteTypeRef = sema.typeMgr().typeInt(32, sign);
            SemaNodeView  castView        = sema.viewNodeTypeConstant(exprRef);
            SWC_RESULT(Cast::cast(sema, castView, concreteTypeRef, CastKind::Implicit));
            ioTypeRef = concreteTypeRef;
        }
        else if (concretizedTypeInfo.isFloatUnsized())
        {
            const TypeRef concreteTypeRef = sema.typeMgr().typeF64();
            SemaNodeView  castView        = sema.viewNodeTypeConstant(exprRef);
            SWC_RESULT(Cast::cast(sema, castView, concreteTypeRef, CastKind::Implicit));
            ioTypeRef = concreteTypeRef;
        }

        const TypeRef concreteArrayTypeRef = deduceHomogeneousAggregateArrayType(sema, ioTypeRef);
        if (!concreteArrayTypeRef.isValid())
            return Result::Continue;

        SemaNodeView castView = sema.viewNodeTypeConstant(exprRef);
        SWC_RESULT(Cast::cast(sema, castView, concreteArrayTypeRef, CastKind::Implicit));
        ioTypeRef = concreteArrayTypeRef;
        return Result::Continue;
    }

    Result inferCompilerRunBlockReturnType(Sema& sema, SymbolFunction& sym, AstNodeRef exprRef, TypeRef& outTypeRef)
    {
        outTypeRef = TypeRef::invalid();
        if (exprRef.isInvalid())
        {
            outTypeRef = sema.typeMgr().typeVoid();
            sym.setReturnTypeRef(outTypeRef);
            return Result::Continue;
        }

        SWC_RESULT(findCompatibleReturnBindingType(sema, exprRef, outTypeRef));
        if (!outTypeRef.isValid())
        {
            const SemaNodeView exprView = sema.viewNodeTypeConstant(exprRef);
            if (exprView.cstRef().isValid())
            {
                ConstantRef newCstRef = ConstantRef::invalid();
                SWC_RESULT(Cast::concretizeConstant(sema, newCstRef, exprRef, exprView.cstRef(), TypeInfo::Sign::Unknown));
                if (newCstRef.isValid() && newCstRef != exprView.cstRef())
                    sema.setConstant(exprRef, newCstRef);
            }

            outTypeRef = sema.viewNodeTypeConstant(exprRef).typeRef();
            SWC_RESULT(concretizeImplicitReturnTypeIfNeeded(sema, exprRef, outTypeRef));
        }

        sym.setReturnTypeRef(outTypeRef);
        return Result::Continue;
    }

    bool canInferImplicitCompilerReturnType(const Sema& sema, const SymbolFunction& sym)
    {
        const AstNode* declNode = sym.decl();
        if (!declNode)
            return false;
        if (declNode->is(AstNodeId::CompilerRunBlock))
            return true;
        if (declNode->is(AstNodeId::CompilerFunc))
            return sema.token(declNode->codeRef()).id == TokenId::CompilerAst;
        return false;
    }

    Result resolveReturnTypeRef(Sema& sema, AstNodeRef exprRef, TypeRef& outTypeRef)
    {
        outTypeRef                             = TypeRef::invalid();
        const SemaInlinePayload* inlinePayload = sema.frame().currentInlinePayload();
        if (inlinePayload && !inlinePayload->returnsToCallerSite())
        {
            outTypeRef = inlinePayload->returnTypeRef;
            return Result::Continue;
        }

        auto* sym = sema.currentFunction();
        SWC_ASSERT(sym);
        if (!sym)
            return Result::Error;

        outTypeRef = sym->returnTypeRef();
        if (!outTypeRef.isValid() && canInferImplicitCompilerReturnType(sema, *sym))
            return inferCompilerRunBlockReturnType(sema, *sym, exprRef, outTypeRef);

        return Result::Continue;
    }

    Result validateReturnStatementValue(Sema& sema, AstNodeRef returnRef, AstNodeRef exprRef, TypeRef returnTypeRef)
    {
        SWC_ASSERT(returnTypeRef.isValid());
        if (!returnTypeRef.isValid())
            return Result::Error;

        const TypeInfo& returnType = sema.typeMgr().get(returnTypeRef);
        if (exprRef.isValid())
        {
            const SemaNodeView exprTypeView = sema.viewType(exprRef);
            if (returnType.isVoid())
            {
                if (exprTypeView.type() && exprTypeView.type()->isVoid())
                    return Result::Continue;

                auto diag = SemaError::report(sema, DiagnosticId::sema_err_return_value_in_void, exprRef);
                if (const auto* currentFn = sema.currentFunction())
                {
                    diag.addArgument(Diagnostic::ARG_SYM, currentFn->name(sema.ctx()));
                    diag.addNote(DiagnosticId::sema_note_function_declared_here);
                    diag.last().addArgument(Diagnostic::ARG_SYM, currentFn->name(sema.ctx()));
                    diag.last().addSpan(currentFn->codeRange(sema.ctx()));
                }
                diag.report(sema.ctx());
                return Result::Error;
            }

            SemaNodeView view = sema.viewNodeTypeConstant(exprRef);
            if (returnType.isAnyTypeInfo(sema.ctx()))
                SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, view));
            SWC_RESULT(Cast::cast(sema, view, returnTypeRef, CastKind::Implicit));
            return Result::Continue;
        }

        if (!returnType.isVoid())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_return_missing_value, returnRef);
            diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, returnType.toName(sema.ctx()));
            if (const auto* currentFn = sema.currentFunction())
            {
                const auto* decl = currentFn->decl() ? currentFn->decl()->safeCast<AstFunctionDecl>() : nullptr;
                if (decl && decl->nodeReturnTypeRef.isValid())
                {
                    diag.addNote(DiagnosticId::sema_note_function_return_type_declared_here);
                    diag.last().addArgument(Diagnostic::ARG_REQUESTED_TYPE, returnType.toName(sema.ctx()));
                    SemaError::addSpan(sema, diag.last(), decl->nodeReturnTypeRef);
                }
                else
                {
                    diag.addNote(DiagnosticId::sema_note_function_declared_here);
                    diag.last().addArgument(Diagnostic::ARG_SYM, currentFn->name(sema.ctx()));
                    diag.last().addSpan(currentFn->codeRange(sema.ctx()));
                }
            }
            diag.report(sema.ctx());
            return Result::Error;
        }

        return Result::Continue;
    }

    const SymbolFunction* resolveCalledFunction(Sema& sema, Symbol* sym)
    {
        if (!sym)
            return nullptr;
        if (sym->isFunction())
            return &sym->cast<SymbolFunction>();
        if (sym->isVariable())
            return SemaHelpers::callableTypeFunction(sema.ctx(), sym->typeRef());
        return nullptr;
    }

    void collectCalleeSymbolsWithFallback(Sema& sema, const SemaNodeView& nodeCallee, SmallVector<Symbol*>& outSymbols)
    {
        nodeCallee.getSymbols(outSymbols);
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

    bool canConsumeTrailingCodeBlock(Sema& sema, const SymbolFunction& fn, std::span<const AstNodeRef> args, AstNodeRef ufcsArg)
    {
        if (!SemaInline::canInlineCall(sema, fn))
            return false;

        const auto& params = fn.parameters();
        if (params.empty())
            return false;
        if (!isVoidCodeBlockParameter(sema, *params.back()))
            return false;
        if (hasExplicitLastArgumentBinding(sema, fn, args, ufcsArg))
            return false;

        return true;
    }

    AstNodeRef findTrailingCodeBlockSibling(Sema& sema, AstNodeRef callRef)
    {
        const AstNode* parentNode = sema.visit().parentNode();
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

        for (size_t childIndex = 0; childIndex < children.size(); ++childIndex)
        {
            if (children[childIndex] != callRef)
                continue;

            for (size_t nextIndex = childIndex + 1; nextIndex < children.size(); ++nextIndex)
            {
                const AstNodeRef siblingRef = children[nextIndex];
                if (siblingRef.isInvalid())
                    continue;
                if (siblingRef == callRef)
                    continue;

                return sema.node(siblingRef).is(AstNodeId::EmbeddedBlock) ? siblingRef : AstNodeRef::invalid();
            }

            break;
        }

        return AstNodeRef::invalid();
    }

    AstNodeRef makeTrailingCodeBlockArgument(Sema& sema, AstNodeRef siblingRef, const SymbolVariable& param)
    {
        auto [wrappedRef, wrappedPtr] = sema.ast().makeNode<AstNodeId::CompilerCodeBlock>(sema.node(siblingRef).tokRef());
        wrappedPtr->setCodeRef(sema.node(siblingRef).codeRef());
        wrappedPtr->nodeBodyRef    = siblingRef;
        wrappedPtr->payloadTypeRef = param.type(sema.ctx()).payloadTypeRef();
        return wrappedRef;
    }

    AstNodeRef resolveTrailingCodeBlockArgument(Sema& sema, const SemaNodeView& nodeCallee, std::span<Symbol*> symbols, std::span<const AstNodeRef> args, AstNodeRef ufcsArg, AstNodeRef& outSiblingRef)
    {
        outSiblingRef = findTrailingCodeBlockSibling(sema, sema.curNodeRef());
        if (outSiblingRef.isInvalid())
            return AstNodeRef::invalid();

        for (Symbol* const sym : symbols)
        {
            const SymbolFunction* fn = resolveCalledFunction(sema, sym);
            if (fn && canConsumeTrailingCodeBlock(sema, *fn, args, ufcsArg))
                return makeTrailingCodeBlockArgument(sema, outSiblingRef, *fn->parameters().back());
        }

        if (symbols.empty() && sema.isValue(nodeCallee.nodeRef()))
        {
            const auto* fn = SemaHelpers::callableTypeFunction(sema.ctx(), nodeCallee.typeRef());
            if (fn && canConsumeTrailingCodeBlock(sema, *fn, args, ufcsArg))
                return makeTrailingCodeBlockArgument(sema, outSiblingRef, *fn->parameters().back());
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

    template<typename T>
    const SymbolVariable* mappedCallParameter(Sema& sema, const T& call, const SymbolFunction& fn, AstNodeRef childRef, AstNodeRef ufcsArg)
    {
        SmallVector<AstNodeRef> args;
        call.collectArguments(args, sema.ast());

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
        const AstNodeRef      ufcsArg = resolveUfcsReceiverArg(sema, call.nodeExprRef);
        const SymbolVariable* param   = mappedCallParameter(sema, call, fn, childRef, ufcsArg);
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
    TypeRef resolveCallArgumentContextBindingType(Sema& sema, const T& call, AstNodeRef childRef)
    {
        if (!childCanConsumeContextualBinding(sema, childRef))
            return TypeRef::invalid();

        const SemaNodeView   nodeCallee = sema.view(call.nodeExprRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol);
        SmallVector<Symbol*> symbols;
        collectCalleeSymbolsWithFallback(sema, nodeCallee, symbols);

        const AstNodeRef ufcsArg        = resolveUfcsReceiverArg(sema, call.nodeExprRef);
        TypeRef          bindingTypeRef = TypeRef::invalid();
        for (Symbol* const sym : symbols)
        {
            const SymbolFunction* fn = resolveCalledFunction(sema, sym);
            if (!fn)
                continue;

            const SymbolVariable* param = mappedCallParameter(sema, call, *fn, childRef, ufcsArg);
            if (!param)
                continue;

            const TypeRef paramTypeRef = param->typeRef();
            if (bindingTypeRef.isInvalid())
            {
                bindingTypeRef = paramTypeRef;
                continue;
            }

            if (bindingTypeRef != paramTypeRef)
                return TypeRef::invalid();
        }

        return bindingTypeRef;
    }

    template<typename T>
    TypeRef resolveCallArgumentLambdaBindingType(Sema& sema, const T& call, AstNodeRef childRef)
    {
        const AstNode& childNode = sema.node(childRef);
        if (!childCanConsumeLambdaBinding(childNode))
            return TypeRef::invalid();

        const SemaNodeView   nodeCallee = sema.view(call.nodeExprRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol);
        SmallVector<Symbol*> symbols;
        collectCalleeSymbolsWithFallback(sema, nodeCallee, symbols);

        const AstNodeRef ufcsArg        = resolveUfcsReceiverArg(sema, call.nodeExprRef);
        TypeRef          bindingTypeRef = TypeRef::invalid();
        TypeRef          compareTypeRef = TypeRef::invalid();

        for (Symbol* const sym : symbols)
        {
            const SymbolFunction* fn = resolveCalledFunction(sema, sym);
            if (!fn)
                continue;

            const SymbolVariable* param = mappedCallParameter(sema, call, *fn, childRef, ufcsArg);
            if (!param)
                continue;

            const TypeRef paramTypeRef    = param->typeRef();
            const TypeRef resolvedTypeRef = unwrapLambdaBindingType(sema.ctx(), paramTypeRef);
            if (!resolvedTypeRef.isValid() || !sema.typeMgr().get(resolvedTypeRef).isFunction())
                continue;

            if (compareTypeRef.isInvalid())
            {
                bindingTypeRef = paramTypeRef;
                compareTypeRef = resolvedTypeRef;
                continue;
            }

            if (compareTypeRef != resolvedTypeRef)
                return TypeRef::invalid();
        }

        return bindingTypeRef;
    }

    Result deduceLambdaParameterTypeFromDefault(Sema& sema, AstNodeRef defaultValueRef, TypeRef& outTypeRef)
    {
        outTypeRef = TypeRef::invalid();
        if (defaultValueRef.isInvalid())
            return Result::Continue;

        SemaNodeView defaultView = sema.viewNodeTypeConstant(defaultValueRef);
        SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, defaultView));

        if (defaultView.typeRef().isInvalid() && defaultView.cstRef().isValid())
        {
            ConstantRef newCstRef;
            SWC_RESULT(Cast::concretizeConstant(sema, newCstRef, defaultView.nodeRef(), defaultView.cstRef(), TypeInfo::Sign::Unknown));
            sema.setConstant(defaultView.nodeRef(), newCstRef);
            defaultView.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        }

        if (defaultView.type() && defaultView.type()->isInt())
        {
            const TypeRef promotedTypeRef = sema.typeMgr().promote(defaultView.typeRef(), defaultView.typeRef(), false);
            SWC_RESULT(Cast::cast(sema, defaultView, promotedTypeRef, CastKind::Implicit));
        }

        outTypeRef = defaultView.typeRef();
        return Result::Continue;
    }

    Result finalizeLambdaParameterDefault(Sema& sema, const AstLambdaParam& param, SymbolVariable& symVar)
    {
        if (param.nodeDefaultValueRef.isInvalid())
            return Result::Continue;

        SemaNodeView defaultView = sema.viewNodeTypeConstant(param.nodeDefaultValueRef);
        SWC_RESULT(SemaCheck::isValueOrTypeInfo(sema, defaultView));

        const TypeInfo& paramType = sema.typeMgr().get(symVar.typeRef());
        if (!paramType.isCodeBlock())
        {
            if (defaultView.typeRef().isValid())
            {
                SWC_RESULT(Cast::cast(sema, defaultView, symVar.typeRef(), CastKind::Initialization));
            }
            else if (defaultView.cstRef().isValid())
            {
                ConstantRef newCstRef;
                SWC_RESULT(Cast::concretizeConstant(sema, newCstRef, defaultView.nodeRef(), defaultView.cstRef(), TypeInfo::Sign::Unknown));
                sema.setConstant(defaultView.nodeRef(), newCstRef);
                defaultView.recompute(sema, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);

                if (defaultView.type() && defaultView.type()->isInt())
                {
                    const TypeRef promotedTypeRef = sema.typeMgr().promote(defaultView.typeRef(), defaultView.typeRef(), false);
                    SWC_RESULT(Cast::cast(sema, defaultView, promotedTypeRef, CastKind::Implicit));
                }
            }
        }

        bool           isCallerLocation = false;
        const AstNode& initNode         = sema.node(param.nodeDefaultValueRef);
        if (initNode.is(AstNodeId::CompilerLiteral))
        {
            const Token& tok = sema.token(initNode.codeRef());
            isCallerLocation = tok.id == TokenId::CompilerCallerLocation;
        }

        if (defaultView.cstRef().isValid())
            symVar.setDefaultValueRef(defaultView.cstRef());
        if (isCallerLocation)
            symVar.addExtraFlag(SymbolVariableFlagsE::CallerLocationDefault);
        symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
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

        TypeRef bindingTypeRef = resolveCallArgumentContextBindingType(sema, node, childRef);
        if (!bindingTypeRef.isValid())
            bindingTypeRef = resolveCallArgumentLambdaBindingType(sema, node, childRef);
        if (bindingTypeRef.isValid())
        {
            auto frame = sema.frame();
            frame.pushBindingType(bindingTypeRef);
            sema.pushFramePopOnPostChild(frame, childRef);
        }

        return Result::Continue;
    }

    bool lambdaHasExpressionBody(Sema& sema, AstNodeRef bodyRef)
    {
        return bodyRef.isValid() && sema.node(bodyRef).isNot(AstNodeId::EmbeddedBlock);
    }

    template<typename T>
    Result buildFunctionExprParameters(Sema& sema, const T& node, SymbolFunction& sym)
    {
        if (!sym.parameters().empty())
            return Result::Continue;

        TaskContext&            ctx             = sema.ctx();
        const SymbolFunction*   bindingFunction = resolveLambdaBindingFunction(sema);
        SmallVector<AstNodeRef> params;
        sema.ast().appendNodes(params, node.spanArgsRef);

        for (size_t paramIndex = 0; paramIndex < params.size(); paramIndex++)
        {
            const AstNodeRef      paramRef  = params[paramIndex];
            const AstLambdaParam& param     = sema.node(paramRef).cast<AstLambdaParam>();
            TypeRef               paramType = TypeRef::invalid();
            if (param.nodeTypeRef.isValid())
                paramType = sema.viewType(param.nodeTypeRef).typeRef();
            else if (bindingFunction && paramIndex < bindingFunction->parameters().size())
                paramType = bindingFunction->parameters()[paramIndex]->typeRef();
            else if (param.nodeDefaultValueRef.isValid())
                SWC_RESULT(deduceLambdaParameterTypeFromDefault(sema, param.nodeDefaultValueRef, paramType));

            SWC_ASSERT(paramType.isValid());

            IdentifierRef idRef = IdentifierRef::invalid();
            if (param.hasFlag(AstLambdaParamFlagsE::Named))
            {
                const Token& tok = sema.token(param.codeRef());
                if (tok.id == TokenId::Identifier)
                    idRef = sema.idMgr().addIdentifier(ctx, param.codeRef());
            }

            auto* symVar = Symbol::make<SymbolVariable>(ctx, &param, param.tokRef(), idRef, SymbolFlagsE::Zero);
            symVar->setTypeRef(paramType);
            symVar->addExtraFlag(SymbolVariableFlagsE::Parameter);
            SWC_RESULT(finalizeLambdaParameterDefault(sema, param, *symVar));

            sym.addParameter(symVar);
            if (idRef.isValid())
                sym.addSymbol(ctx, symVar, false);

            symVar->setDeclared(ctx);
            symVar->setTyped(ctx);
            symVar->setSemaCompleted(ctx);
        }

        return Result::Continue;
    }

    template<typename T>
    Result prepareFunctionExprSignature(Sema& sema, const T& node, SymbolFunction& sym)
    {
        SWC_RESULT(buildFunctionExprParameters(sema, node, sym));

        if (sym.returnTypeRef().isValid())
            return Result::Continue;

        if (node.nodeReturnTypeRef.isValid())
        {
            sym.setReturnTypeRef(sema.viewType(node.nodeReturnTypeRef).typeRef());
            return Result::Continue;
        }

        if (const SymbolFunction* bindingFunction = resolveLambdaBindingFunction(sema))
        {
            sym.setReturnTypeRef(bindingFunction->returnTypeRef());
            return Result::Continue;
        }

        if (!lambdaHasExpressionBody(sema, node.nodeBodyRef))
            sym.setReturnTypeRef(sema.typeMgr().typeVoid());

        return Result::Continue;
    }

    template<typename T>
    Result finalizeFunctionExprSignature(Sema& sema, const T& node, SymbolFunction& sym)
    {
        SWC_RESULT(prepareFunctionExprSignature(sema, node, sym));

        if (!sym.returnTypeRef().isValid())
        {
            if (node.nodeBodyRef.isValid())
            {
                TypeRef returnTypeRef = sema.viewType(node.nodeBodyRef).typeRef();
                SWC_RESULT(concretizeImplicitReturnTypeIfNeeded(sema, node.nodeBodyRef, returnTypeRef));
                sym.setReturnTypeRef(returnTypeRef);
            }
            else
                sym.setReturnTypeRef(sema.typeMgr().typeVoid());
        }

        sym.setVariadicParamFlag(sema.ctx());

        const TypeInfo ti      = TypeInfo::makeFunction(&sym, TypeInfoFlagsE::Zero);
        const TypeRef  typeRef = sema.typeMgr().addType(ti);
        sym.setTypeRef(typeRef);
        SemaPurity::computePurityFlag(sema, sym);
        sym.setTyped(sema.ctx());

        SWC_RESULT(SemaCheck::isValidSignature(sema, sym.parameters(), false));
        SWC_RESULT(SemaSpecOp::validateSymbol(sema, sym));
        registerRuntimeFunctionSymbol(sema, sym);

        sema.setIsValue(sema.curNodeRef());
        sema.unsetIsLValue(sema.curNodeRef());
        return Result::Continue;
    }

    SymbolFunction* resolveEnclosingFunctionForClosureRuntimeStorage(Sema& sema)
    {
        for (size_t parentIndex = 0;; ++parentIndex)
        {
            const AstNodeRef parentRef = sema.visit().parentNodeRef(parentIndex);
            if (parentRef.isInvalid())
                break;

            Symbol* const symbol = sema.viewSymbol(parentRef).sym();
            if (symbol && symbol->isFunction())
                return &symbol->cast<SymbolFunction>();
        }

        return nullptr;
    }

    Result attachClosureExprRuntimeStorageIfNeeded(Sema& sema, const AstClosureExpr& node, const SymbolFunction& sym)
    {
        if (sema.isGlobalScope())
            return Result::Continue;
        if (!sym.typeRef().isValid())
            return Result::Continue;

        auto& payload = SemaHelpers::ensureCodeGenNodePayload(sema, sema.curNodeRef());
        if (payload.runtimeStorageSym == nullptr)
        {
            if (SymbolVariable* const boundStorage = SemaHelpers::currentRuntimeStorage(sema))
            {
                payload.runtimeStorageSym = boundStorage;
                return Result::Continue;
            }

            payload.runtimeStorageSym = &SemaHelpers::registerUniqueRuntimeStorageSymbol(sema, node, "__closure_runtime_storage");
        }

        auto& storageSym = *payload.runtimeStorageSym;
        if (&storageSym == SemaHelpers::currentRuntimeStorage(sema))
            return Result::Continue;

        storageSym.addExtraFlag(SymbolVariableFlagsE::Initialized);
        if (!storageSym.typeRef().isValid())
            storageSym.setTypeRef(sym.typeRef());

        if (!storageSym.isDeclared())
        {
            storageSym.registerAttributes(sema);
            storageSym.setDeclared(sema.ctx());
            SWC_RESULT(Match::ghosting(sema, storageSym));
        }

        // Closure storage must live in the enclosing function (resolved by walking parents),
        // not the symbol that the closure body is currently being analysed under.
        SymbolFunction* ownerFunction = resolveEnclosingFunctionForClosureRuntimeStorage(sema);
        if (!ownerFunction)
            ownerFunction = sema.currentFunction();
        if (!storageSym.isSemaCompleted() && ownerFunction)
        {
            const TypeInfo& symType = sema.typeMgr().get(sym.typeRef());
            SWC_RESULT(sema.waitSemaCompleted(&symType, sema.curNodeRef()));
            ownerFunction->addLocalVariable(sema.ctx(), &storageSym);

            storageSym.setTyped(sema.ctx());
            storageSym.setSemaCompleted(sema.ctx());
        }

        return Result::Continue;
    }

    SymbolVariable* findClosureCaptureSymbol(const SymbolFunction& sym, const SymbolVariable& sourceVar)
    {
        std::vector<const Symbol*> symbols;
        sym.getAllSymbols(symbols, true);
        for (const Symbol* symbol : symbols)
        {
            const auto* captureSym = symbol ? symbol->safeCast<SymbolVariable>() : nullptr;
            if (!captureSym || !captureSym->isClosureCapture())
                continue;
            if (captureSym->closureCapturedSource() == &sourceVar)
                return const_cast<SymbolVariable*>(captureSym);
        }

        return nullptr;
    }

    Result buildClosureCaptureSymbols(Sema& sema, const AstClosureExpr& node, SymbolFunction& sym)
    {
        TaskContext&            ctx = sema.ctx();
        SmallVector<AstNodeRef> captures;
        sema.ast().appendNodes(captures, node.nodeCaptureArgsRef);

        uint64_t captureOffset = 0;
        for (const AstNodeRef captureRef : captures)
        {
            const AstClosureArgument& captureArg = sema.node(captureRef).cast<AstClosureArgument>();
            const SemaNodeView        sourceView = sema.viewSymbol(captureArg.nodeIdentifierRef);
            Symbol* const             sourceSym  = sourceView.sym();
            if (!sourceSym)
                return SemaError::raise(sema, DiagnosticId::sema_err_closure_capture_invalid, captureArg.nodeIdentifierRef);

            if (!sourceSym->isVariable())
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_closure_capture_invalid, captureArg.nodeIdentifierRef);
                diag.report(sema.ctx());
                return Result::Error;
            }

            auto&           sourceVar = sourceSym->cast<SymbolVariable>();
            const TypeRef   typeRef   = sourceVar.typeRef();
            const TypeInfo& typeInfo  = sema.typeMgr().get(typeRef);
            SWC_RESULT(sema.waitSemaCompleted(&typeInfo, captureArg.nodeIdentifierRef));

            const bool captureByRef = captureArg.hasFlag(AstClosureArgumentFlagsE::Address);
            if (captureByRef && sourceVar.hasExtraFlag(SymbolVariableFlagsE::Let))
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_closure_capture_let_by_ref, captureArg.nodeIdentifierRef);
                diag.addArgument(Diagnostic::ARG_SYM, sourceVar.name(sema.ctx()));
                diag.report(sema.ctx());
                return Result::Error;
            }

            uint32_t storageSize  = static_cast<uint32_t>(typeInfo.sizeOf(ctx));
            uint32_t storageAlign = typeInfo.alignOf(ctx);
            if (captureByRef)
            {
                storageSize  = sizeof(void*);
                storageAlign = alignof(void*);
            }

            if (!storageAlign)
                storageAlign = 1;

            captureOffset = Math::alignUpU64(captureOffset, storageAlign);
            if (SymbolVariable* const existingCapture = findClosureCaptureSymbol(sym, sourceVar))
            {
                if (existingCapture->decl() == &captureArg)
                {
                    captureOffset += storageSize;
                    continue;
                }
            }

            if (captureOffset + storageSize > Runtime::CLOSURE_CAPTURE_BUFFER_SIZE)
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_closure_capture_too_large, captureArg.nodeIdentifierRef);
                diag.addArgument(Diagnostic::ARG_TYPE, typeRef);
                diag.addArgument(Diagnostic::ARG_VALUE, Runtime::CLOSURE_CAPTURE_BUFFER_SIZE);
                diag.report(sema.ctx());
                return Result::Error;
            }

            auto* captureSym = Symbol::make<SymbolVariable>(ctx, &captureArg, captureArg.tokRef(), sourceVar.idRef(), SymbolFlagsE::Zero);
            captureSym->setTypeRef(typeRef);
            captureSym->setClosureCapturedSource(&sourceVar);
            captureSym->setClosureCaptureOffset(static_cast<uint32_t>(captureOffset));
            captureSym->setClosureCaptureByRef(captureByRef);

            if (captureByRef && sourceVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
                sourceVar.addExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage);

            if (sourceVar.idRef().isValid())
            {
                Symbol* inserted = sym.addSingleSymbol(ctx, captureSym);
                if (inserted != captureSym)
                {
                    auto diag = SemaError::report(sema, DiagnosticId::sema_err_closure_capture_duplicate, captureArg.nodeIdentifierRef);
                    diag.addArgument(Diagnostic::ARG_SYM, sourceVar.name(ctx));
                    diag.addNote(DiagnosticId::sema_note_previous_capture);
                    diag.last().addSpan(inserted->codeRange(ctx));
                    diag.report(ctx);
                    return Result::Error;
                }
            }

            captureSym->setDeclared(ctx);
            captureSym->setTyped(ctx);
            captureSym->setSemaCompleted(ctx);
            captureOffset += storageSize;
        }

        return Result::Continue;
    }

    TypeRef implOwnerTypeRef(const SymbolImpl& symImpl)
    {
        if (symImpl.isForStruct())
            return symImpl.symStruct()->typeRef();
        if (symImpl.isForEnum())
            return symImpl.symEnum()->typeRef();

        return TypeRef::invalid();
    }

    TypeRef implReceiverTypeRef(Sema& sema, const SymbolImpl& symImpl, bool isConstReceiver)
    {
        const TypeRef ownerType = implOwnerTypeRef(symImpl);
        if (!ownerType.isValid())
            return TypeRef::invalid();

        if (symImpl.isForEnum())
        {
            if (!isConstReceiver)
                return ownerType;

            TypeInfo typeInfo = sema.typeMgr().get(ownerType);
            typeInfo.addFlag(TypeInfoFlagsE::Const);
            return sema.typeMgr().addType(typeInfo);
        }

        TypeInfoFlags typeFlags = TypeInfoFlagsE::Zero;
        if (isConstReceiver)
            typeFlags.add(TypeInfoFlagsE::Const);
        return sema.typeMgr().addType(TypeInfo::makeReference(ownerType, typeFlags));
    }

    void addMeParameter(Sema& sema, SymbolFunction& sym)
    {
        const SymbolImpl* symImpl = sema.frame().currentImpl();
        if (!symImpl)
            return;

        const IdentifierRef meId = sema.idMgr().predefined(IdentifierManager::PredefinedName::Me);
        if (!sym.parameters().empty())
        {
            const SymbolVariable* firstParam = sym.parameters().front();
            if (firstParam && firstParam->idRef() == meId)
            {
                return;
            }
        }

        const TypeRef receiverTypeRef = implReceiverTypeRef(sema, *symImpl, sym.hasExtraFlag(SymbolFunctionFlagsE::Const));
        if (!receiverTypeRef.isValid())
            return;

        TaskContext& ctx   = sema.ctx();
        auto*        symMe = Symbol::make<SymbolVariable>(ctx, nullptr, TokenRef::invalid(), meId, SymbolFlagsE::Zero);
        symMe->setTypeRef(receiverTypeRef);
        symMe->addExtraFlag(SymbolVariableFlagsE::Parameter);

        sym.addParameter(symMe);
        sym.addSymbol(ctx, symMe, true);
        symMe->setDeclared(ctx);
        symMe->setTyped(ctx);
    }

    SymbolVariable* resolveBodyBindingReceiver(const Sema& sema, const SymbolFunction& sym)
    {
        const auto& params = sym.parameters();
        if (params.empty())
            return nullptr;

        SymbolVariable* receiver = params[0];
        if (!receiver)
            return nullptr;

        if (receiver->idRef() != sema.idMgr().predefined(IdentifierManager::PredefinedName::Me))
            return nullptr;

        return receiver;
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

    template<typename T>
    Result semaCallExprCommon(Sema& sema, const T& node, bool tryIntrinsicFold)
    {
        const SemaNodeView nodeCallee = sema.view(node.nodeExprRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol);

        SmallVector<AstNodeRef> args;
        node.collectArguments(args, sema.ast());
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
        }

        SmallVector<ResolvedCallArgument> resolvedArgs;
        const auto                        resolveMode = isAttributeContextCall(node) ? Match::ResolveCallMode::AttributeOnly : Match::ResolveCallMode::Normal;
        SWC_RESULT(Match::resolveFunctionCandidates(sema, nodeCallee, symbols, args, ufcsArg, &resolvedArgs, resolveMode));
        sema.setResolvedCallArguments(sema.curNodeRef(), resolvedArgs);
        const SemaNodeView nodeSymView = sema.curViewSymbol();
        SWC_ASSERT(nodeSymView.hasSymbol());

        auto&      calledFn    = nodeSymView.sym()->cast<SymbolFunction>();
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
            SWC_RESULT(ConstantIntrinsic::tryConstantFoldCall(sema, calledFn, args));
        }
        else
        {
            SWC_RESULT(SemaJIT::tryRunConstCall(sema, calledFn, sema.curNodeRef(), resolvedArgs.span()));
            if (sema.viewConstant(sema.curNodeRef()).hasConstant())
                return Result::Continue;
            SWC_RESULT(SemaInline::tryInlineCall(sema, sema.curNodeRef(), calledFn, args, ufcsArg));
        }

        if (sema.viewConstant(sema.curNodeRef()).hasConstant())
            return Result::Continue;

        SWC_RESULT(SemaHelpers::attachIndirectReturnRuntimeStorageIfNeeded(sema, node, calledFn, "__call_runtime_storage"));

        return Result::Continue;
    }
}

Result AstFunctionDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (spanConstraintsRef.isValid())
    {
        SmallVector<AstNodeRef> constraintRefs;
        sema.ast().appendNodes(constraintRefs, spanConstraintsRef);
        for (const AstNodeRef constraintRef : constraintRefs)
        {
            if (childRef == constraintRef)
                return Result::SkipChildren;
        }
    }

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
        auto&      sym                 = sema.curViewSymbol().sym()->cast<SymbolFunction>();
        const bool deferInlineBodySema = sym.attributes().hasRtFlag(RtAttributeFlagsE::Mixin) || sym.attributes().hasRtFlag(RtAttributeFlagsE::Macro);
        if (deferInlineBodySema)
        {
            const bool shortWithoutExplicitReturnType = hasFlag(AstFunctionFlagsE::Short) && nodeReturnTypeRef.isInvalid();
            if (!shortWithoutExplicitReturnType)
                return Result::SkipChildren;
        }

        bool        whereSatisfied = true;
        CastFailure whereFailure;
        SWC_RESULT(SemaGeneric::evaluateFunctionWhereConstraints(sema, whereSatisfied, sym, &whereFailure));
        if (!whereSatisfied)
        {
            if (whereFailure.diagId == DiagnosticId::sema_err_function_where_failed)
                return Result::SkipChildren;

            bool directSatisfied = true;
            return SemaGeneric::evaluateFunctionWhereConstraints(sema, directSatisfied, sym, nullptr);
        }

        auto frame = sema.frame();
        if (SymbolVariable* receiver = resolveBodyBindingReceiver(sema, sym))
            frame.pushBindingVar(receiver);

        // Lookup-scope overrides are expression-local. A fresh function body must
        // start from its lexical scope or local declarations can miss themselves.
        frame.setLookupScope(nullptr);
        frame.setUpLookupScope(nullptr);
        frame.setIgnoreRuntimeAccess(false);
        frame.setCurrentErrorContext(AstNodeRef::invalid(), SemaFrame::ErrorContextMode::None);
        frame.pushBindingType(sym.returnTypeRef());
        sema.pushFramePopOnPostNode(frame);

        sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
        sema.curScope().setSymMap(&sym);
    }

    return Result::Continue;
}

Result AstFunctionExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    auto& sym = functionExprSymbol(sema, sema.curNodeRef());
    SWC_RESULT(prepareFunctionExprSignature(sema, *this, sym));

    auto frame = sema.frame();
    frame.setLookupScope(nullptr);
    frame.setUpLookupScope(nullptr);
    frame.setIgnoreRuntimeAccess(false);
    frame.setCurrentErrorContext(AstNodeRef::invalid(), SemaFrame::ErrorContextMode::None);
    if (sym.returnTypeRef().isValid())
        frame.pushBindingType(sym.returnTypeRef());
    sema.pushFramePopOnPostNode(frame);

    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    sema.curScope().setSymMap(&sym);
    return Result::Continue;
}

Result AstClosureExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    auto& sym = functionExprSymbol(sema, sema.curNodeRef());
    SWC_RESULT(prepareFunctionExprSignature(sema, *this, sym));
    SWC_RESULT(buildClosureCaptureSymbols(sema, *this, sym));

    auto frame = sema.frame();
    frame.setLookupScope(nullptr);
    frame.setUpLookupScope(nullptr);
    frame.setIgnoreRuntimeAccess(false);
    frame.setCurrentErrorContext(AstNodeRef::invalid(), SemaFrame::ErrorContextMode::None);
    if (sym.returnTypeRef().isValid())
        frame.pushBindingType(sym.returnTypeRef());
    sema.pushFramePopOnPostNode(frame);

    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    sema.curScope().setSymMap(&sym);
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
            else if (childRef == nodeBodyRef)
            {
                SWC_RESULT(validateReturnStatementValue(sema, nodeBodyRef, nodeBodyRef, sym.returnTypeRef()));
            }
        }
        else if (childRef == nodeBodyRef)
        {
            TypeRef returnTypeRef = sema.viewType(nodeBodyRef).typeRef();
            SWC_RESULT(concretizeImplicitReturnTypeIfNeeded(sema, nodeBodyRef, returnTypeRef));
            sym.setReturnTypeRef(returnTypeRef);
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
        if (sym.returnTypeRef().isValid() && sema.typeMgr().get(sym.returnTypeRef()).isCodeBlock())
            return SemaError::raiseCodeTypeRestricted(sema, nodeReturnTypeRef.isValid() ? nodeReturnTypeRef : childRef, sym.returnTypeRef());

        sym.setVariadicParamFlag(sema.ctx());

        const TypeInfo ti      = TypeInfo::makeFunction(&sym, TypeInfoFlagsE::Zero);
        const TypeRef  typeRef = sema.typeMgr().addType(ti);
        sym.setTypeRef(typeRef);
        SemaPurity::computePurityFlag(sema, sym);
        sym.setTyped(sema.ctx());

        SWC_RESULT(SemaCheck::isValidSignature(sema, sym.parameters(), false));
        SWC_RESULT(SemaSpecOp::validateSymbol(sema, sym));
        if (!sym.isEmpty() && !sym.isGenericInstance())
            SWC_RESULT(Match::ghosting(sema, sym));

        registerRuntimeFunctionSymbol(sema, sym);
    }

    return Result::Continue;
}

Result AstFunctionExpr::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    auto& sym = functionExprSymbol(sema, sema.curNodeRef());
    return finalizeFunctionExprSignature(sema, *this, sym);
}

Result AstClosureExpr::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    auto& sym = functionExprSymbol(sema, sema.curNodeRef());
    SWC_RESULT(finalizeFunctionExprSignature(sema, *this, sym));
    return attachClosureExprRuntimeStorageIfNeeded(sema, *this, sym);
}

Result AstFunctionDecl::semaPostNode(Sema& sema)
{
    auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    if (sym.isGenericRoot() && !sym.isGenericInstance())
        return Result::Continue;

    if (sym.isForeign() && !sym.isEmpty())
        return SemaError::raise(sema, DiagnosticId::sema_err_foreign_cannot_have_body, sema.curNodeRef());

    sym.setSemaCompleted(sema.ctx());
    if (!sym.attributes().hasRtFlag(RtAttributeFlagsE::Macro) && !sym.attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
        sema.compiler().registerNativeCodeFunction(&sym);
    return Result::Continue;
}

Result AstFunctionExpr::semaPostNode(Sema& sema) const
{
    auto& sym = functionExprSymbol(sema, sema.curNodeRef());
    if (!sym.isTyped())
        SWC_RESULT(finalizeFunctionExprSignature(sema, *this, sym));

    sym.setSemaCompleted(sema.ctx());
    if (!sym.attributes().hasRtFlag(RtAttributeFlagsE::Macro) && !sym.attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
        sema.compiler().registerNativeCodeFunction(&sym);
    return Result::Continue;
}

Result AstClosureExpr::semaPostNode(Sema& sema) const
{
    auto& sym = functionExprSymbol(sema, sema.curNodeRef());
    if (!sym.isTyped())
        SWC_RESULT(finalizeFunctionExprSignature(sema, *this, sym));

    SWC_RESULT(attachClosureExprRuntimeStorageIfNeeded(sema, *this, sym));
    sym.setSemaCompleted(sema.ctx());
    if (!sym.attributes().hasRtFlag(RtAttributeFlagsE::Macro) && !sym.attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
        sema.compiler().registerNativeCodeFunction(&sym);
    return Result::Continue;
}

Result AstFunctionParamMe::semaPreNode(Sema& sema) const
{
    if (!sema.enteringState())
        return Result::Continue;

    // Generic specialization can pause and restart while walking the signature.
    // Reuse the receiver symbol already attached to this node instead of
    // registering a second `me` parameter on resume.
    if (sema.curViewSymbol().sym())
        return Result::Continue;

    const SymbolImpl* symImpl = sema.frame().currentImpl();
    if (!symImpl)
        return SemaError::raise(sema, DiagnosticId::sema_err_tok_outside_impl, sema.curNodeRef());

    TaskContext&        ctx       = sema.ctx();
    const TypeRef       ownerType = implOwnerTypeRef(*symImpl);
    const IdentifierRef idRef     = sema.idMgr().predefined(IdentifierManager::PredefinedName::Me);
    const SymbolFlags   flags     = sema.frame().flagsForCurrentAccess();
    auto*               sym       = Symbol::make<SymbolVariable>(ctx, this, tokRef(), idRef, flags);
    SymbolMap*          symbolMap = SemaFrame::currentSymMap(sema);
    SWC_ASSERT(ownerType.isValid());

    if (sema.curScope().isLocal())
        sema.curScope().addSymbol(sym);
    else
        symbolMap->addSymbol(ctx, sym, true);

    SemaHelpers::handleSymbolRegistration(sema, symbolMap, sym);
    sym->registerCompilerIf(sema);
    sema.setSymbol(sema.curNodeRef(), sym);

    sym->setTypeRef(implReceiverTypeRef(sema, *symImpl, hasFlag(AstFunctionParamMeFlagsE::Const)));
    sym->setDeclared(ctx);
    sym->setTyped(ctx);
    sym->setSemaCompleted(ctx);

    return Result::Continue;
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

Result AstReturnStmt::semaPostNode(Sema& sema) const
{
    TypeRef returnTypeRef = TypeRef::invalid();
    SWC_RESULT(resolveReturnTypeRef(sema, nodeExprRef, returnTypeRef));
    return validateReturnStatementValue(sema, sema.curNodeRef(), nodeExprRef, returnTypeRef);
}

Result AstReturnStmt::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeExprRef || childRef.isInvalid())
        return Result::Continue;

    TypeRef returnTypeRef = TypeRef::invalid();
    if (const SemaInlinePayload* inlinePayload = sema.frame().currentInlinePayload();
        inlinePayload && !inlinePayload->returnsToCallerSite())
    {
        returnTypeRef = inlinePayload->returnTypeRef;
    }
    else if (const SymbolFunction* currentFn = sema.currentFunction())
    {
        returnTypeRef = currentFn->returnTypeRef();
    }

    if (!returnTypeRef.isValid())
        return Result::Continue;

    auto frame = sema.frame();
    frame.pushBindingType(returnTypeRef);
    sema.pushFramePopOnPostChild(frame, childRef);
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
    sema.setType(sema.curNodeRef(), exprView.typeRef());
    if (exprView.cstRef().isValid())
        sema.setConstant(sema.curNodeRef(), exprView.cstRef());
    sema.copyResolvedCallArguments(sema.curNodeRef(), resolvedExprRef);

    const TokenId tokenId = effectiveErrorManagementTokenId(sema, sema.token(codeRef()).id);
    if (tokenId != TokenId::KwdTry && exprView.typeRef().isValid() && exprView.typeRef() != sema.typeMgr().typeVoid())
        SWC_RESULT(SemaHelpers::attachRuntimeStorageIfNeeded(sema, resolvedExprRef, *this, exprView.typeRef(), "__trycatch_runtime_storage"));

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
