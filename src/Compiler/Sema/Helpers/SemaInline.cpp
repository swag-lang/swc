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
    bool isInlineReexpandableCall(const AstNode& node)
    {
        return node.is(AstNodeId::CallExpr) ||
               node.is(AstNodeId::AliasCallExpr) ||
               node.is(AstNodeId::IntrinsicCallExpr);
    }

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

    AstNodeRef bindingValueArgumentRef(Sema& sema, AstNodeRef argRef)
    {
        if (argRef.isInvalid())
            return AstNodeRef::invalid();

        if (sema.node(argRef).is(AstNodeId::EmbeddedBlock))
        {
            if (const auto* inlinePayload = sema.semaPayload<SemaInlinePayload>(argRef);
                inlinePayload && inlinePayload->callRef.isValid())
                return inlinePayload->callRef;
        }

        const AstNodeRef resolvedRef = sema.viewZero(argRef).nodeRef();
        if (resolvedRef.isInvalid())
            return argRef;

        // Preserve call syntax for already-inlined value arguments. Cloning the substituted
        // inline block into a new inline context would orphan its `return` statements from the
        // payload that gives that block expression semantics, so let the cloned call re-inline.
        if (resolvedRef != argRef &&
            sema.node(resolvedRef).is(AstNodeId::EmbeddedBlock) &&
            isInlineReexpandableCall(sema.node(argRef)))
            return argRef;

        return resolvedRef;
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

        return bindingValueArgumentRef(sema, argRef);
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

    using AliasIdentifierArray = std::array<IdentifierRef, 10>;
    using AliasRefArray        = std::array<SourceCodeRef, 10>;

    struct AliasUsageInfo
    {
        uint32_t      aliasCount  = 0;
        SourceCodeRef invalidRef  = SourceCodeRef::invalid();
        uint32_t      missingSlot = 0;
        uint32_t      usedSlot    = 0;
    };

    void collectAliasUsage(Sema& sema, AstNodeRef nodeRef, AliasRefArray& outAliasRefs)
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
            const TokenRef tokRef{tokIndex};
            const Token&   tok = sourceView.token(tokRef);
            if (!Token::isCompilerAlias(tok.id))
                continue;

            const uint32_t slot = SemaHelpers::aliasSlotIndex(tok.id);
            if (slot < outAliasRefs.size() && !outAliasRefs[slot].isValid())
                outAliasRefs[slot] = SourceCodeRef{node.srcViewRef(), tokRef};
        }
    }

    Result collectAliasUsageInfo(Sema& sema, const AstFunctionDecl& decl, AliasUsageInfo& outInfo)
    {
        outInfo = {};
        if (decl.nodeBodyRef.isInvalid())
            return Result::Continue;

        AliasRefArray aliasRefs = {};
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

    Result collectAliasIdentifiers(Sema& sema, AstNodeRef callRef, const AstFunctionDecl& decl, AliasIdentifierArray& outAliasIdentifiers)
    {
        outAliasIdentifiers.fill(IdentifierRef::invalid());

        SmallVector<AstNodeRef> aliases;
        if (callRef.isValid())
        {
            const auto* aliasCall = sema.node(callRef).safeCast<AstAliasCallExpr>();
            if (aliasCall)
                aliasCall->collectAliases(aliases, sema.ast());
        }

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

    const AstSingleVarDecl* inlineBindingParamDecl(const SymbolVariable& param)
    {
        const AstNode* declNode = param.decl();
        if (!declNode)
            return nullptr;

        return declNode->safeCast<AstSingleVarDecl>();
    }

    void collectInlineLoopIdentifiers(Sema& sema, AstNodeRef nodeRef, SmallVector<IdentifierRef>& outIdentifiers)
    {
        if (nodeRef.isInvalid())
            return;

        const AstNode& node = sema.node(nodeRef);
        if (const auto* forStmt = node.safeCast<AstForStmt>())
        {
            if (forStmt->tokNameRef.isValid())
                outIdentifiers.push_back(SemaHelpers::resolveIdentifier(sema, {forStmt->srcViewRef(), forStmt->tokNameRef}));
        }

        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, sema.ast());
        for (const AstNodeRef childRef : children)
            collectInlineLoopIdentifiers(sema, childRef, outIdentifiers);
    }

    void collectIdentifierUses(Sema& sema, AstNodeRef nodeRef, SmallVector<IdentifierRef>& outIdentifiers)
    {
        if (nodeRef.isInvalid())
            return;

        const AstNode& node = sema.node(nodeRef);
        if (node.is(AstNodeId::Identifier))
            outIdentifiers.push_back(sema.idMgr().addIdentifier(sema.ctx(), node.codeRef()));

        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, sema.ast());
        for (const AstNodeRef childRef : children)
            collectIdentifierUses(sema, childRef, outIdentifiers);
    }

    bool inlineBindingNeedsMaterialization(Sema& sema, AstNodeRef exprRef, const SmallVector<IdentifierRef>& localIdentifiers)
    {
        if (exprRef.isInvalid() || localIdentifiers.empty())
            return false;

        SmallVector<IdentifierRef> exprIdentifiers;
        collectIdentifierUses(sema, exprRef, exprIdentifiers);
        for (const IdentifierRef exprIdRef : exprIdentifiers)
        {
            if (std::ranges::find(localIdentifiers, exprIdRef) != localIdentifiers.end())
                return true;
        }

        return false;
    }

    void appendBodyStatements(Sema& sema, AstNodeRef bodyRef, SmallVector<AstNodeRef>& outStatements, const AstNodeId transparentBodyId)
    {
        if (bodyRef.isInvalid())
            return;

        const AstNode& bodyNode = sema.node(bodyRef);
        if (bodyNode.is(transparentBodyId))
        {
            if (transparentBodyId == AstNodeId::EmbeddedBlock)
                sema.ast().appendNodes(outStatements, bodyNode.cast<AstEmbeddedBlock>().spanChildrenRef);
            else
                sema.ast().appendNodes(outStatements, bodyNode.cast<AstFunctionBody>().spanChildrenRef);
            return;
        }

        if (transparentBodyId == AstNodeId::FunctionBody && bodyNode.is(AstNodeId::EmbeddedBlock))
        {
            sema.ast().appendNodes(outStatements, bodyNode.cast<AstEmbeddedBlock>().spanChildrenRef);
            return;
        }

        outStatements.push_back(bodyRef);
    }

    AstNodeRef buildInlineRoot(Sema& sema, const AstFunctionDecl& decl, const AstNodeId rootId, std::span<const AstNodeRef> prefixStatements, AstNodeRef bodyRef)
    {
        SmallVector<AstNodeRef> statements;
        statements.reserve(prefixStatements.size() + 1);
        for (const AstNodeRef stmtRef : prefixStatements)
            statements.push_back(stmtRef);
        appendBodyStatements(sema, bodyRef, statements, rootId);

        if (rootId == AstNodeId::EmbeddedBlock)
        {
            auto [blockRef, blockPtr] = sema.ast().makeNode<AstNodeId::EmbeddedBlock>(decl.tokRef());
            blockPtr->spanChildrenRef = sema.ast().pushSpan(statements.span());
            return blockRef;
        }

        auto [bodyRootRef, bodyRootPtr] = sema.ast().makeNode<AstNodeId::FunctionBody>(decl.tokRef());
        bodyRootPtr->spanChildrenRef    = sema.ast().pushSpan(statements.span());
        return bodyRootRef;
    }

    Result materializeInlineBindings(Sema& sema, const SymbolFunction& fn, const AstFunctionDecl& decl, SmallVector<SemaClone::ParamBinding>& ioBindings, SmallVector<AstNodeRef>& outStatements)
    {
        outStatements.clear();
        if (ioBindings.empty())
            return Result::Continue;

        const SemaClone::CloneContext noBindings{std::span<const SemaClone::ParamBinding>{}};
        SmallVector<IdentifierRef>    localIdentifiers;
        collectInlineLoopIdentifiers(sema, decl.nodeBodyRef, localIdentifiers);

        SmallVector<SemaClone::ParamBinding> remainingBindings;
        remainingBindings.reserve(ioBindings.size());
        for (SemaClone::ParamBinding& binding : ioBindings)
        {
            if (!binding.exprRef.isValid())
            {
                remainingBindings.push_back(binding);
                continue;
            }

            const SymbolVariable* param = nullptr;
            for (const SymbolVariable* candidate : fn.parameters())
            {
                if (candidate && candidate->idRef() == binding.idRef)
                {
                    param = candidate;
                    break;
                }
            }

            if (!param)
                continue;

            const TypeInfo& paramType = param->type(sema.ctx());
            if (paramType.isCodeBlock() || paramType.isAnyVariadic())
            {
                remainingBindings.push_back(binding);
                continue;
            }

            if (!inlineBindingNeedsMaterialization(sema, binding.exprRef, localIdentifiers))
            {
                remainingBindings.push_back(binding);
                continue;
            }

            const AstSingleVarDecl* paramDecl = inlineBindingParamDecl(*param);
            if (!paramDecl)
            {
                remainingBindings.push_back(binding);
                continue;
            }

            const AstNodeRef clonedInitRef = SemaClone::cloneAst(sema, binding.exprRef, noBindings);
            if (clonedInitRef.isInvalid())
                return Result::Error;

            auto [declRef, declPtr] = sema.ast().makeNode<AstNodeId::SingleVarDecl>(paramDecl->tokRef());
            declPtr->flags()        = AstVarDeclFlagsE::Let;
            declPtr->tokNameRef     = paramDecl->tokNameRef;
            declPtr->nodeInitRef    = clonedInitRef;
            outStatements.push_back(declRef);
        }

        ioBindings = std::move(remainingBindings);
        return Result::Continue;
    }

    AstNodeRef inlineBodyRef(Sema& sema, const AstFunctionDecl& decl, const SemaClone::CloneContext& cloneContext, std::span<const AstNodeRef> prefixStatements)
    {
        if (decl.hasFlag(AstFunctionFlagsE::Short))
        {
            const AstNodeRef shortBodyRef = makeInlineBodyFromShort(sema, decl, cloneContext);
            if (shortBodyRef.isInvalid())
                return AstNodeRef::invalid();
            return buildInlineRoot(sema, decl, AstNodeId::EmbeddedBlock, prefixStatements, shortBodyRef);
        }

        if (decl.nodeBodyRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNodeRef clonedBodyRef = SemaClone::cloneAst(sema, decl.nodeBodyRef, cloneContext);
        if (clonedBodyRef.isInvalid())
            return AstNodeRef::invalid();

        return buildInlineRoot(sema, decl, AstNodeId::EmbeddedBlock, prefixStatements, clonedBodyRef);
    }

    AstNodeRef mixinBodyRef(Sema& sema, const AstFunctionDecl& decl, const SemaClone::CloneContext& cloneContext, std::span<const AstNodeRef> prefixStatements)
    {
        if (decl.hasFlag(AstFunctionFlagsE::Short))
        {
            const AstNodeRef shortBodyRef = makeMixinBodyFromShort(sema, decl, cloneContext);
            if (shortBodyRef.isInvalid())
                return AstNodeRef::invalid();
            return buildInlineRoot(sema, decl, AstNodeId::FunctionBody, prefixStatements, shortBodyRef);
        }

        if (decl.nodeBodyRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNodeRef clonedBodyRef = SemaClone::cloneAst(sema, decl.nodeBodyRef, cloneContext);
        if (clonedBodyRef.isInvalid())
            return AstNodeRef::invalid();

        return buildInlineRoot(sema, decl, AstNodeId::FunctionBody, prefixStatements, clonedBodyRef);
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

        if (!sema.isCurrentFunction())
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
            AstNodeRef argRef = bindingValueArgumentRef(sema, rawArgRef);
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

    Result mapArguments(Sema& sema, bool& outMapped, AstNodeRef callRef, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, SmallVector<SemaClone::ParamBinding>& outBindings, InlineVariadicBinding& outVariadic)
    {
        outMapped   = false;
        outVariadic = {};

        const auto& params = fn.parameters();
        if (params.empty())
        {
            outMapped = !ufcsArg.isValid() && args.empty();
            return Result::Continue;
        }

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
                bound[0].exprRef = ufcsArg;
                nextParam        = 1;
            }
            else if (hasAnyVariadic)
            {
                outVariadic.argRefs.push_back(ufcsRef);
            }
            else
            {
                return Result::Continue;
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
                return Result::Continue;

            const AstNodeRef argValueRef = bindingArgumentRef(sema, *params[paramIndex], namedArg.nodeArgRef);
            if (hasAnyVariadic && paramIndex == numFixed)
            {
                outVariadic.argRefs.push_back(argValueRef);
                continue;
            }

            if (paramIndex >= numFixed)
                return Result::Continue;
            if (isBindingAssigned(bound[paramIndex]))
                return Result::Continue;

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

            const AstNodeRef argValueRef = nextParam < numFixed ? bindingArgumentRef(sema, *params[nextParam], argRef) : bindingValueArgumentRef(sema, argRef);
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
                return Result::Continue;
        }

        if (bound.size() != numFixed)
            return Result::Continue;

        for (size_t i = 0; i < numFixed; i++)
        {
            if (!isBindingAssigned(bound[i]))
            {
                const SymbolVariable* param = params[i];
                SWC_ASSERT(param != nullptr);
                if (!param->hasExtraFlag(SymbolVariableFlagsE::Initialized))
                    return Result::Continue;

                bound[i].idRef = param->idRef();
                if (SemaHelpers::isDirectCallerLocationDefault(sema, *param))
                {
                    const SourceCodeRange codeRange = sema.node(callRef).codeRangeWithChildren(sema.ctx(), sema.ast());
                    bound[i].typeRef                = param->typeRef();
                    SWC_RESULT(ConstantHelpers::makeSourceCodeLocation(sema, bound[i].cstRef, codeRange, SemaHelpers::currentLocationFunction(sema)));
                }
                else
                {
                    const AstNodeRef defaultRef = bindingArgumentRef(sema, *param, SemaHelpers::defaultArgumentExprRef(*param));
                    if (defaultRef.isInvalid())
                        return Result::Continue;
                    bound[i].exprRef = defaultRef;
                }
            }

            if (bound[i].idRef.isValid())
                outBindings.push_back(bound[i]);
        }

        outMapped = true;
        return Result::Continue;
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

    return sema.isOptimizeEnabled() && attributes.hasRtFlag(RtAttributeFlagsE::Inline);
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
    bool                                 mapped = false;
    SWC_RESULT(mapArguments(sema, mapped, callRef, fn, args, ufcsArg, bindings, variadicBinding));
    if (!mapped)
        return Result::Continue;

    AliasIdentifierArray aliasIdentifiers = {};
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

    SmallVector<AstNodeRef> materializedBindings;
    if (!fn.attributes().hasRtFlag(RtAttributeFlagsE::Macro) && !fn.attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
        SWC_RESULT(materializeInlineBindings(sema, fn, *decl, bindings, materializedBindings));

    const SemaClone::CloneContext cloneContext{bindings.span()};
    const bool                    isMixin       = fn.attributes().hasRtFlag(RtAttributeFlagsE::Mixin);
    const AstNodeRef              inlineRootRef = isMixin ? mixinBodyRef(sema, *decl, cloneContext, materializedBindings.span()) : inlineBodyRef(sema, *decl, cloneContext, materializedBindings.span());
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
        inlinePayload->argMappings.push_back(binding);

    auto       frame       = sema.frame();
    SemaScope* callerScope = sema.curScopePtr();
    if (returnTypeRef != sema.typeMgr().typeVoid())
        frame.pushBindingType(returnTypeRef);
    frame.setCurrentInlinePayload(inlinePayload);
    if (fn.attributes().hasRtFlag(RtAttributeFlagsE::Macro))
        frame.setUpLookupScope(callerScope);
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
