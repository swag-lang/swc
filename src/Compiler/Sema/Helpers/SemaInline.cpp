#include "pch.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct InlineVariadicBinding
    {
        const SymbolVariable*   param           = nullptr;
        bool                    untypedVariadic = false;
        SmallVector<AstNodeRef> argRefs;
    };

    AstNodeRef defaultArgumentExprRef(const SymbolVariable& param)
    {
        const AstNode* declNode = param.decl();
        if (!declNode)
            return AstNodeRef::invalid();

        if (const auto* singleVar = declNode->safeCast<AstSingleVarDecl>())
            return singleVar->nodeInitRef;

        if (const auto* multiVar = declNode->safeCast<AstMultiVarDecl>())
            return multiVar->nodeInitRef;

        return AstNodeRef::invalid();
    }

    AstNodeRef wrapCodeArgument(Sema& sema, const SymbolVariable& param, AstNodeRef argRef)
    {
        if (argRef.isInvalid())
            return AstNodeRef::invalid();

        const TypeRef  payloadTypeRef = param.type(sema.ctx()).payloadTypeRef();
        const AstNode& argNode        = sema.node(argRef);
        if (argNode.is(AstNodeId::CompilerCodeBlock))
        {
            auto [wrappedRef, wrappedPtr] = sema.ast().makeNode<AstNodeId::CompilerCodeBlock>(argNode.tokRef());
            wrappedPtr->setCodeRef(argNode.codeRef());
            wrappedPtr->nodeBodyRef    = argNode.cast<AstCompilerCodeBlock>().nodeBodyRef;
            wrappedPtr->payloadTypeRef = payloadTypeRef;
            return wrappedRef;
        }

        if (argNode.is(AstNodeId::CompilerCodeExpr))
        {
            auto [wrappedRef, wrappedPtr] = sema.ast().makeNode<AstNodeId::CompilerCodeExpr>(argNode.tokRef());
            wrappedPtr->setCodeRef(argNode.codeRef());
            wrappedPtr->nodeExprRef    = argNode.cast<AstCompilerCodeExpr>().nodeExprRef;
            wrappedPtr->payloadTypeRef = payloadTypeRef;
            return wrappedRef;
        }

        if (argNode.is(AstNodeId::EmbeddedBlock))
        {
            auto [wrappedRef, wrappedPtr] = sema.ast().makeNode<AstNodeId::CompilerCodeBlock>(argNode.tokRef());
            wrappedPtr->setCodeRef(argNode.codeRef());
            wrappedPtr->nodeBodyRef    = argRef;
            wrappedPtr->payloadTypeRef = payloadTypeRef;
            return wrappedRef;
        }

        auto [wrappedRef, wrappedPtr] = sema.ast().makeNode<AstNodeId::CompilerCodeExpr>(argNode.tokRef());
        wrappedPtr->setCodeRef(argNode.codeRef());
        wrappedPtr->nodeExprRef    = argRef;
        wrappedPtr->payloadTypeRef = payloadTypeRef;
        return wrappedRef;
    }

    AstNodeRef bindingArgumentRef(Sema& sema, const SymbolVariable& param, AstNodeRef argRef)
    {
        if (argRef.isInvalid())
            return AstNodeRef::invalid();

        const TypeInfo& paramType = param.type(sema.ctx());
        if (paramType.isCodeBlock())
        {
            const AstNodeRef resolvedRef = sema.viewZero(argRef).nodeRef();
            if (resolvedRef.isValid())
                return wrapCodeArgument(sema, param, resolvedRef);
            return wrapCodeArgument(sema, param, argRef);
        }

        return sema.viewZero(argRef).nodeRef();
    }

    bool tryGetSimpleInlineConstant(Sema& sema, AstNodeRef inlineRootRef, ConstantRef& outConstant)
    {
        outConstant = ConstantRef::invalid();
        if (inlineRootRef.isInvalid())
            return false;

        const AstNode&          rootNode = sema.node(inlineRootRef);
        SmallVector<AstNodeRef> statements;
        if (rootNode.is(AstNodeId::EmbeddedBlock))
        {
            sema.ast().appendNodes(statements, rootNode.cast<AstEmbeddedBlock>().spanChildrenRef);
        }
        else if (rootNode.is(AstNodeId::FunctionBody))
        {
            sema.ast().appendNodes(statements, rootNode.cast<AstFunctionBody>().spanChildrenRef);
        }
        else
        {
            return false;
        }

        if (statements.size() != 1)
            return false;

        const AstNode& stmtNode = sema.node(statements.front());
        if (!stmtNode.is(AstNodeId::ReturnStmt))
            return false;

        const AstNodeRef exprRef = stmtNode.cast<AstReturnStmt>().nodeExprRef;
        if (exprRef.isInvalid())
            return false;

        const SemaNodeView exprView = sema.viewConstant(exprRef);
        if (!exprView.hasConstant())
            return false;

        outConstant = exprView.cstRef();
        return outConstant.isValid();
    }

    bool isNamedArgument(const AstNode& node)
    {
        return node.is(AstNodeId::NamedArgument);
    }

    bool resolveFunctionDeclInCurrentAst(const Sema& sema, const SymbolFunction& fn, const AstFunctionDecl*& outDecl)
    {
        outDecl = nullptr;

        const AstNode* declNode = fn.decl();
        if (!declNode || !declNode->is(AstNodeId::FunctionDecl))
            return false;

        const Ast* const declAst = declNode->sourceAst(sema.ctx());
        if (!declAst || declAst != &sema.ast())
            return false;

        outDecl = &declNode->cast<AstFunctionDecl>();
        return true;
    }

    AstNodeRef makeInlineBodyFromShort(Sema& sema, const AstFunctionDecl& decl, const SemaClone::CloneContext& cloneContext)
    {
        if (decl.nodeBodyRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNodeRef clonedExprRef = SemaClone::cloneAst(sema, decl.nodeBodyRef, cloneContext);
        if (clonedExprRef.isInvalid())
            return AstNodeRef::invalid();

        auto [returnRef, returnPtr] = sema.ast().makeNode<AstNodeId::ReturnStmt>(decl.tokRef());
        returnPtr->nodeExprRef      = clonedExprRef;

        auto [blockRef, blockPtr] = sema.ast().makeNode<AstNodeId::EmbeddedBlock>(decl.tokRef());
        SmallVector<AstNodeRef> statements;
        statements.push_back(returnRef);
        blockPtr->spanChildrenRef = sema.ast().pushSpan(statements.span());
        return blockRef;
    }

    AstNodeRef makeMixinBodyFromShort(Sema& sema, const AstFunctionDecl& decl, const SemaClone::CloneContext& cloneContext)
    {
        if (decl.nodeBodyRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNodeRef clonedExprRef = SemaClone::cloneAst(sema, decl.nodeBodyRef, cloneContext);
        if (clonedExprRef.isInvalid())
            return AstNodeRef::invalid();

        auto [returnRef, returnPtr] = sema.ast().makeNode<AstNodeId::ReturnStmt>(decl.tokRef());
        returnPtr->nodeExprRef      = clonedExprRef;

        auto [bodyRef, bodyPtr] = sema.ast().makeNode<AstNodeId::FunctionBody>(decl.tokRef());
        SmallVector<AstNodeRef> statements;
        statements.push_back(returnRef);
        bodyPtr->spanChildrenRef = sema.ast().pushSpan(statements.span());
        return bodyRef;
    }

    AstNodeRef inlineBodyRef(Sema& sema, const AstFunctionDecl& decl, const SemaClone::CloneContext& cloneContext)
    {
        if (decl.hasFlag(AstFunctionFlagsE::Short))
            return makeInlineBodyFromShort(sema, decl, cloneContext);

        if (decl.nodeBodyRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNodeRef clonedBodyRef = SemaClone::cloneAst(sema, decl.nodeBodyRef, cloneContext);
        if (clonedBodyRef.isInvalid())
            return AstNodeRef::invalid();

        if (sema.node(clonedBodyRef).is(AstNodeId::EmbeddedBlock))
            return clonedBodyRef;

        auto [blockRef, blockPtr] = sema.ast().makeNode<AstNodeId::EmbeddedBlock>(decl.tokRef());
        SmallVector<AstNodeRef> statements;
        statements.push_back(clonedBodyRef);
        blockPtr->spanChildrenRef = sema.ast().pushSpan(statements.span());
        return blockRef;
    }

    AstNodeRef mixinBodyRef(Sema& sema, const AstFunctionDecl& decl, const SemaClone::CloneContext& cloneContext)
    {
        if (decl.hasFlag(AstFunctionFlagsE::Short))
            return makeMixinBodyFromShort(sema, decl, cloneContext);

        if (decl.nodeBodyRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNodeRef clonedBodyRef = SemaClone::cloneAst(sema, decl.nodeBodyRef, cloneContext);
        if (clonedBodyRef.isInvalid())
            return AstNodeRef::invalid();

        if (sema.node(clonedBodyRef).is(AstNodeId::FunctionBody))
            return clonedBodyRef;

        if (sema.node(clonedBodyRef).is(AstNodeId::EmbeddedBlock))
        {
            const auto& embeddedBlock = sema.node(clonedBodyRef).cast<AstEmbeddedBlock>();
            auto [bodyRef, bodyPtr]   = sema.ast().makeNode<AstNodeId::FunctionBody>(decl.tokRef());
            bodyPtr->spanChildrenRef  = embeddedBlock.spanChildrenRef;
            return bodyRef;
        }

        auto [bodyRef, bodyPtr] = sema.ast().makeNode<AstNodeId::FunctionBody>(decl.tokRef());
        SmallVector<AstNodeRef> statements;
        statements.push_back(clonedBodyRef);
        bodyPtr->spanChildrenRef = sema.ast().pushSpan(statements.span());
        return bodyRef;
    }

    Result createInlineResultVariable(Sema& sema, AstNodeRef callRef, TypeRef typeRef, SymbolVariable*& outResultVar)
    {
        outResultVar = nullptr;
        if (typeRef.isInvalid() || typeRef == sema.typeMgr().typeVoid())
            return Result::Continue;

        const AstNode&      callNode = sema.node(callRef);
        TaskContext&        ctx      = sema.ctx();
        const SymbolFlags   flags    = sema.frame().flagsForCurrentAccess();
        const IdentifierRef idRef    = SemaHelpers::getUniqueIdentifier(sema, "__inline_result");
        auto*               symVar   = Symbol::make<SymbolVariable>(ctx, &callNode, callNode.tokRef(), idRef, flags);
        symVar->addExtraFlag(SymbolVariableFlagsE::Initialized);
        symVar->setTypeRef(typeRef);
        symVar->setDeclared(ctx);
        symVar->setTyped(ctx);
        symVar->setSemaCompleted(ctx);

        if (SymbolFunction* const currentFn = sema.frame().currentFunction())
        {
            const TypeInfo& resultType = sema.typeMgr().get(typeRef);
            SWC_ASSERT(resultType.isCompleted(ctx));
            currentFn->addLocalVariable(ctx, symVar);
        }

        outResultVar = symVar;
        return Result::Continue;
    }

    Result waitInlineResultTypeIfNeeded(Sema& sema, AstNodeRef callRef, TypeRef returnTypeRef)
    {
        if (returnTypeRef.isInvalid() || returnTypeRef == sema.typeMgr().typeVoid())
            return Result::Continue;

        if (!sema.frame().currentFunction())
            return Result::Continue;

        const TypeInfo& resultType = sema.typeMgr().get(returnTypeRef);
        return sema.waitSemaCompleted(&resultType, callRef);
    }

    Result finalizeInlineBlock(Sema& sema, AstNodeRef inlineRootRef, const SemaInlinePayload& payload)
    {
        SWC_ASSERT(inlineRootRef.isValid());
        SWC_ASSERT(payload.returnTypeRef.isValid());

        sema.setType(inlineRootRef, payload.returnTypeRef);
        const TypeInfo& returnType = sema.typeMgr().get(payload.returnTypeRef);
        if (!returnType.isVoid())
        {
            sema.setIsValue(inlineRootRef);
            if (returnType.isReference())
                sema.setIsLValue(inlineRootRef);
        }

        if (!returnType.isVoid())
        {
            ConstantRef cstRef = ConstantRef::invalid();
            if (tryGetSimpleInlineConstant(sema, inlineRootRef, cstRef))
            {
                sema.setFoldedTypedConst(inlineRootRef);
                sema.setConstant(inlineRootRef, cstRef);
                sema.setFoldedTypedConst(payload.callRef);
                sema.setConstant(payload.callRef, cstRef);
            }
        }

        return Result::Continue;
    }

    Result createVariadicInlineExpression(Sema& sema, AstNodeRef callRef, const InlineVariadicBinding& variadicBinding, AstNodeRef& outExprRef, TypeRef& outExprTypeRef)
    {
        outExprRef     = AstNodeRef::invalid();
        outExprTypeRef = TypeRef::invalid();
        if (!variadicBinding.param)
            return Result::Continue;
        if (variadicBinding.argRefs.empty())
            return Result::Continue;

        TypeRef targetElemTypeRef = TypeRef::invalid();
        if (variadicBinding.untypedVariadic)
            targetElemTypeRef = sema.typeMgr().typeAny();
        else
            targetElemTypeRef = variadicBinding.param->type(sema.ctx()).payloadTypeRef();

        if (targetElemTypeRef.isInvalid())
            return Result::Continue;

        const SemaClone::CloneContext noBindings{std::span<const SemaClone::ParamBinding>{}};
        SmallVector<AstNodeRef>       clonedValues;
        clonedValues.reserve(variadicBinding.argRefs.size());

        for (const AstNodeRef rawArgRef : variadicBinding.argRefs)
        {
            AstNodeRef argRef = sema.viewZero(rawArgRef).nodeRef();
            if (argRef.isInvalid())
                return Result::Continue;

            const AstNodeRef clonedArgRef = SemaClone::cloneAst(sema, argRef, noBindings);
            if (clonedArgRef.isInvalid())
                return Result::Continue;

            clonedValues.push_back(clonedArgRef);
        }

        const TokenRef callTokRef = sema.node(callRef).tokRef();

        auto [arrayRef, arrayPtr] = sema.ast().makeNode<AstNodeId::ArrayLiteral>(callTokRef);
        arrayPtr->spanChildrenRef = sema.ast().pushSpan(clonedValues.span());

        SmallVector4<uint64_t> dims;
        dims.push_back(clonedValues.size());
        outExprTypeRef = sema.typeMgr().addType(TypeInfo::makeArray(dims.span(), targetElemTypeRef));
        outExprRef     = arrayRef;
        return Result::Continue;
    }

    bool mapArguments(Sema& sema, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, SmallVector<SemaClone::ParamBinding>& outBindings, InlineVariadicBinding& outVariadic)
    {
        outVariadic = {};

        const auto& params = fn.parameters();
        if (params.empty())
            return !ufcsArg.isValid() && args.empty();

        const TypeInfo& lastParamType  = params.back()->type(sema.ctx());
        const bool      hasAnyVariadic = lastParamType.isAnyVariadic();
        const size_t    numFixed       = hasAnyVariadic ? params.size() - 1 : params.size();

        if (hasAnyVariadic)
        {
            outVariadic.param           = params.back();
            outVariadic.untypedVariadic = lastParamType.isVariadic();
        }

        std::vector bound(numFixed, AstNodeRef::invalid());
        size_t      nextParam = 0;

        if (ufcsArg.isValid())
        {
            const AstNodeRef ufcsRef = bindingArgumentRef(sema, *params[0], ufcsArg);
            if (numFixed > 0)
            {
                bound[0]  = ufcsRef;
                nextParam = 1;
            }
            else if (hasAnyVariadic)
            {
                outVariadic.argRefs.push_back(ufcsRef);
            }
            else
            {
                return false;
            }
        }

        for (const auto argRef : args)
        {
            const AstNode& argNode = sema.node(argRef);
            if (!isNamedArgument(argNode))
                continue;

            const auto&         namedArg = argNode.cast<AstNamedArgument>();
            const IdentifierRef idRef    = sema.idMgr().addIdentifier(sema.ctx(), namedArg.codeRef());

            size_t paramIndex = params.size();
            for (size_t i = 0; i < params.size(); i++)
            {
                if (params[i]->idRef() == idRef)
                {
                    paramIndex = i;
                    break;
                }
            }

            if (paramIndex >= params.size())
                return false;

            const AstNodeRef argValueRef = bindingArgumentRef(sema, *params[paramIndex], namedArg.nodeArgRef);
            if (hasAnyVariadic && paramIndex == numFixed)
            {
                outVariadic.argRefs.push_back(argValueRef);
                continue;
            }

            if (paramIndex >= numFixed)
                return false;
            if (bound[paramIndex].isValid())
                return false;

            bound[paramIndex] = argValueRef;
        }

        for (const auto argRef : args)
        {
            const AstNode& argNode = sema.node(argRef);
            if (isNamedArgument(argNode))
                continue;

            while (nextParam < numFixed && bound[nextParam].isValid())
                nextParam++;

            const AstNodeRef argValueRef = nextParam < numFixed ? bindingArgumentRef(sema, *params[nextParam], argRef) : sema.viewZero(argRef).nodeRef();
            if (nextParam < numFixed)
            {
                bound[nextParam++] = argValueRef;
                continue;
            }

            if (hasAnyVariadic)
            {
                outVariadic.argRefs.push_back(argValueRef);
                continue;
            }

            if (nextParam >= numFixed)
                return false;
        }

        if (bound.size() != numFixed)
            return false;

        for (size_t i = 0; i < numFixed; i++)
        {
            if (!bound[i].isValid())
            {
                const SymbolVariable* param = params[i];
                SWC_ASSERT(param != nullptr);
                if (!param->hasExtraFlag(SymbolVariableFlagsE::Initialized))
                    return false;

                const AstNodeRef defaultRef = bindingArgumentRef(sema, *param, defaultArgumentExprRef(*param));
                if (defaultRef.isInvalid())
                    return false;
                bound[i] = defaultRef;
            }

            if (params[i]->idRef().isValid())
                outBindings.push_back({params[i]->idRef(), bound[i], TypeRef::invalid()});
        }

        return true;
    }

}

bool SemaInline::canInlineCall(Sema& sema, const SymbolFunction& fn)
{
    if (fn.isClosure() || fn.isEmpty() || fn.isForeign())
        return false;
    if (fn.hasVariadicParam())
    {
        const auto& params = fn.parameters();
        if (!params.empty() && params.back()->type(sema.ctx()).isVariadic())
            return false;
    }
    if (fn.attributes().hasRtFlag(RtAttributeFlagsE::NoInline))
        return false;

    const AttributeList& attributes = fn.attributes();
    if (attributes.hasRtFlag(RtAttributeFlagsE::Macro) || attributes.hasRtFlag(RtAttributeFlagsE::Mixin))
        return true;

    return SemaHelpers::isOptimizeEnabled(sema) && attributes.hasRtFlag(RtAttributeFlagsE::Inline);
}

Result SemaInline::tryInlineCall(Sema& sema, AstNodeRef callRef, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
{
    if (sema.hasSubstitute(callRef))
        return Result::Continue;

    if (!canInlineCall(sema, fn))
        return Result::Continue;

    const AstFunctionDecl* decl = nullptr;
    if (!resolveFunctionDeclInCurrentAst(sema, fn, decl))
        return Result::Continue;

    SmallVector<SemaClone::ParamBinding> bindings;
    InlineVariadicBinding                variadicBinding;
    if (!mapArguments(sema, fn, args, ufcsArg, bindings, variadicBinding))
        return Result::Continue;

    AstNodeRef variadicExprRef     = AstNodeRef::invalid();
    TypeRef    variadicExprTypeRef = TypeRef::invalid();
    SWC_RESULT(createVariadicInlineExpression(sema, callRef, variadicBinding, variadicExprRef, variadicExprTypeRef));
    if (variadicBinding.param)
    {
        if (variadicExprRef.isInvalid() || variadicExprTypeRef.isInvalid())
            return Result::Continue;
        if (variadicBinding.param->idRef().isValid())
            bindings.push_back({variadicBinding.param->idRef(), variadicExprRef, variadicExprTypeRef});
    }

    TypeRef returnTypeRef = fn.returnTypeRef();
    if (!returnTypeRef.isValid())
        returnTypeRef = sema.typeMgr().typeVoid();

    SWC_RESULT(waitInlineResultTypeIfNeeded(sema, callRef, returnTypeRef));

    const SemaClone::CloneContext cloneContext{bindings.span()};
    const bool                    isMixin       = fn.attributes().hasRtFlag(RtAttributeFlagsE::Mixin);
    const AstNodeRef              inlineRootRef = isMixin ? mixinBodyRef(sema, *decl, cloneContext) : inlineBodyRef(sema, *decl, cloneContext);
    if (inlineRootRef.isInvalid())
        return Result::Continue;

    sema.node(inlineRootRef).setCodeRef(sema.node(callRef).codeRef());

    SymbolVariable* resultVar = nullptr;
    SWC_RESULT(createInlineResultVariable(sema, callRef, returnTypeRef, resultVar));

    // Create payload
    auto* inlinePayload           = sema.compiler().allocate<SemaInlinePayload>();
    inlinePayload->callRef        = callRef;
    inlinePayload->inlineRootRef  = inlineRootRef;
    inlinePayload->sourceFunction = &fn;
    inlinePayload->resultVar      = resultVar;
    inlinePayload->returnTypeRef  = returnTypeRef;
    for (const SemaClone::ParamBinding& binding : bindings)
        inlinePayload->argMappings.push_back({binding.idRef, binding.exprRef});

    auto frame = sema.frame();
    if (returnTypeRef != sema.typeMgr().typeVoid())
        frame.pushBindingType(returnTypeRef);
    frame.setCurrentInlinePayload(inlinePayload);
    sema.pushFramePopOnPostNode(frame, inlineRootRef);
    if (!isMixin)
        sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local, inlineRootRef);

    sema.deferPostNodeAction(inlineRootRef, [inlinePayload](Sema& inSema, AstNodeRef nodeRef) {
        SWC_ASSERT(inlinePayload != nullptr);
        SWC_RESULT(finalizeInlineBlock(inSema, nodeRef, *inlinePayload));
        inSema.setSemaPayload(nodeRef, inlinePayload);
        return Result::Continue;
    });

    sema.setSubstitute(callRef, inlineRootRef);
    sema.visit().restartCurrentNode(inlineRootRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
