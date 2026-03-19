#include "pch.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isBindingAssigned(const SemaClone::ParamBinding& binding)
    {
        return binding.exprRef.isValid() || binding.cstRef.isValid();
    }

    struct InlineVariadicBinding
    {
        const SymbolVariable*   param           = nullptr;
        bool                    untypedVariadic = false;
        SmallVector<AstNodeRef> argRefs;
    };

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

    constexpr std::array<std::string_view, 10> INTERNAL_ALIAS_NAMES = {
        "#alias0",
        "#alias1",
        "#alias2",
        "#alias3",
        "#alias4",
        "#alias5",
        "#alias6",
        "#alias7",
        "#alias8",
        "#alias9",
    };

    struct AliasUsageInfo
    {
        uint32_t      aliasCount  = 0;
        SourceCodeRef invalidRef  = SourceCodeRef::invalid();
        uint32_t      missingSlot = 0;
        uint32_t      usedSlot    = 0;
    };

    void collectAliasUsage(Sema& sema, AstNodeRef nodeRef, std::array<SourceCodeRef, INTERNAL_ALIAS_NAMES.size()>& outAliasRefs)
    {
        if (nodeRef.isInvalid())
            return;

        const AstNode& node = sema.node(nodeRef);
        if (node.tokRef().isInvalid())
            return;

        const SourceView& sourceView = sema.srcView(node.srcViewRef());
        const TokenRef    endTokRef  = node.tokRefEnd(sema.ast());
        if (endTokRef.isInvalid())
            return;

        for (uint32_t tokIndex = node.tokRef().get(); tokIndex <= endTokRef.get() && tokIndex < sourceView.tokens().size(); ++tokIndex)
        {
            const TokenRef         tokRef{tokIndex};
            const std::string_view tokenText = sourceView.token(tokRef).string(sourceView);
            for (size_t slot = 0; slot < INTERNAL_ALIAS_NAMES.size(); ++slot)
            {
                if (tokenText != INTERNAL_ALIAS_NAMES[slot])
                    continue;
                if (!outAliasRefs[slot].isValid())
                    outAliasRefs[slot] = SourceCodeRef{node.srcViewRef(), tokRef};
                break;
            }
        }
    }

    Result collectAliasUsageInfo(Sema& sema, const AstFunctionDecl& decl, AliasUsageInfo& outInfo)
    {
        outInfo = {};
        if (decl.nodeBodyRef.isInvalid())
            return Result::Continue;

        std::array<SourceCodeRef, INTERNAL_ALIAS_NAMES.size()> aliasRefs = {};
        collectAliasUsage(sema, decl.nodeBodyRef, aliasRefs);

        int32_t highestSlot = -1;
        for (int32_t slot = static_cast<int32_t>(aliasRefs.size()) - 1; slot >= 0; --slot)
        {
            if (aliasRefs[slot].isValid())
            {
                highestSlot = slot;
                break;
            }
        }

        if (highestSlot < 0)
            return Result::Continue;

        outInfo.aliasCount = static_cast<uint32_t>(highestSlot + 1);
        for (int32_t slot = 0; slot <= highestSlot; ++slot)
        {
            if (aliasRefs[slot].isValid())
                continue;

            for (int32_t usedSlot = slot + 1; usedSlot <= highestSlot; ++usedSlot)
            {
                if (!aliasRefs[usedSlot].isValid())
                    continue;

                outInfo.invalidRef  = aliasRefs[usedSlot];
                outInfo.missingSlot = static_cast<uint32_t>(slot);
                outInfo.usedSlot    = static_cast<uint32_t>(usedSlot);
                return Result::Error;
            }
        }

        return Result::Continue;
    }

    void collectCallAliases(Sema& sema, AstNodeRef callRef, SmallVector<AstNodeRef>& outAliases)
    {
        outAliases.clear();
        if (callRef.isInvalid())
            return;

        const AstNode& callNode = sema.node(callRef);
        if (callNode.is(AstNodeId::AliasCallExpr))
            callNode.cast<AstAliasCallExpr>().collectAliases(outAliases, sema.ast());
    }

    Result collectAliasIdentifiers(Sema& sema, AstNodeRef callRef, const AstFunctionDecl& decl, std::array<IdentifierRef, INTERNAL_ALIAS_NAMES.size()>& outAliasIdentifiers)
    {
        outAliasIdentifiers.fill(IdentifierRef::invalid());

        SmallVector<AstNodeRef> aliases;
        collectCallAliases(sema, callRef, aliases);

        AliasUsageInfo aliasUsage;
        const Result   usageResult = collectAliasUsageInfo(sema, decl, aliasUsage);
        if (usageResult != Result::Continue)
        {
            if (aliasUsage.invalidRef.isValid())
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_alias_hole, aliasUsage.invalidRef);
                diag.addArgument(Diagnostic::ARG_COUNT, aliasUsage.missingSlot);
                diag.addArgument(Diagnostic::ARG_VALUE, aliasUsage.usedSlot);
                diag.report(sema.ctx());
            }

            return usageResult;
        }

        if (aliases.size() > aliasUsage.aliasCount)
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_too_many_aliases, aliases[aliasUsage.aliasCount]);
            diag.addArgument(Diagnostic::ARG_COUNT, aliasUsage.aliasCount);
            diag.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(aliases.size()));
            diag.report(sema.ctx());
            return Result::Error;
        }

        for (size_t slot = 0; slot < aliases.size(); ++slot)
        {
            const AstNode& aliasNode = sema.node(aliases[slot]);
            if (aliasNode.is(AstNodeId::Identifier))
                outAliasIdentifiers[slot] = sema.idMgr().addIdentifier(sema.ctx(), aliasNode.codeRef());
        }

        return Result::Continue;
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

        SWC_RESULT(SemaHelpers::addCurrentFunctionLocalVariable(sema, *symVar, typeRef));

        outResultVar = symVar;
        return Result::Continue;
    }

    Result waitInlineResultTypeIfNeeded(Sema& sema, AstNodeRef callRef, TypeRef returnTypeRef)
    {
        if (returnTypeRef.isInvalid() || returnTypeRef == sema.typeMgr().typeVoid())
            return Result::Continue;

        if (!SemaHelpers::isCurrentFunction(sema))
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

    bool mapArguments(Sema& sema, AstNodeRef callRef, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, SmallVector<SemaClone::ParamBinding>& outBindings, InlineVariadicBinding& outVariadic)
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

        std::vector<SemaClone::ParamBinding> bound(numFixed);
        size_t                               nextParam = 0;

        if (ufcsArg.isValid())
        {
            const AstNodeRef ufcsRef = bindingArgumentRef(sema, *params[0], ufcsArg);
            if (numFixed > 0)
            {
                bound[0].idRef   = params[0]->idRef();
                bound[0].exprRef = ufcsRef;
                nextParam        = 1;
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
            if (!argNode.is(AstNodeId::NamedArgument))
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
            if (isBindingAssigned(bound[paramIndex]))
                return false;

            bound[paramIndex].idRef   = params[paramIndex]->idRef();
            bound[paramIndex].exprRef = argValueRef;
        }

        for (const auto argRef : args)
        {
            const AstNode& argNode = sema.node(argRef);
            if (argNode.is(AstNodeId::NamedArgument))
                continue;

            while (nextParam < numFixed && isBindingAssigned(bound[nextParam]))
                nextParam++;

            const AstNodeRef argValueRef = nextParam < numFixed ? bindingArgumentRef(sema, *params[nextParam], argRef) : sema.viewZero(argRef).nodeRef();
            if (nextParam < numFixed)
            {
                bound[nextParam].idRef   = params[nextParam]->idRef();
                bound[nextParam].exprRef = argValueRef;
                nextParam++;
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
            if (!isBindingAssigned(bound[i]))
            {
                const SymbolVariable* param = params[i];
                SWC_ASSERT(param != nullptr);
                if (!param->hasExtraFlag(SymbolVariableFlagsE::Initialized))
                    return false;

                bound[i].idRef = param->idRef();
                if (SemaHelpers::isDirectCallerLocationDefault(sema, *param))
                {
                    const SourceCodeRange codeRange = sema.node(callRef).codeRangeWithChildren(sema.ctx(), sema.ast());
                    bound[i].typeRef                = param->typeRef();
                    bound[i].cstRef                 = ConstantHelpers::makeSourceCodeLocation(sema, codeRange, SemaHelpers::currentLocationFunction(sema));
                }
                else
                {
                    const AstNodeRef defaultRef = bindingArgumentRef(sema, *param, SemaHelpers::defaultArgumentExprRef(*param));
                    if (defaultRef.isInvalid())
                        return false;
                    bound[i].exprRef = defaultRef;
                }
            }

            if (bound[i].idRef.isValid())
                outBindings.push_back(bound[i]);
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
    if (!mapArguments(sema, callRef, fn, args, ufcsArg, bindings, variadicBinding))
        return Result::Continue;

    std::array<IdentifierRef, INTERNAL_ALIAS_NAMES.size()> aliasIdentifiers = {};
    SWC_RESULT(collectAliasIdentifiers(sema, callRef, *decl, aliasIdentifiers));

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
    auto* inlinePayload             = sema.compiler().allocate<SemaInlinePayload>();
    inlinePayload->callRef          = callRef;
    inlinePayload->inlineRootRef    = inlineRootRef;
    inlinePayload->sourceFunction   = &fn;
    inlinePayload->resultVar        = resultVar;
    inlinePayload->returnTypeRef    = returnTypeRef;
    inlinePayload->aliasIdentifiers = aliasIdentifiers;
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
