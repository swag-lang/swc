#include "pch.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isInlineRecursion(Sema& sema, const SymbolFunction& fn)
    {
        if (sema.currentFunction() == &fn)
            return true;

        const SemaInlinePayload* inlinePayload = sema.frame().currentInlinePayload();
        while (inlinePayload)
        {
            if (inlinePayload->sourceFunction == &fn)
                return true;
            inlinePayload = inlinePayload->parentInlinePayload;
        }

        return false;
    }

    bool isInlineReexpandableExpr(const AstNode& node)
    {
        return node.is(AstNodeId::CallExpr) ||
               node.is(AstNodeId::AliasCallExpr) ||
               node.is(AstNodeId::IntrinsicCallExpr) ||
               node.is(AstNodeId::UnaryExpr) ||
               node.is(AstNodeId::BinaryExpr) ||
               node.is(AstNodeId::RelationalExpr) ||
               node.is(AstNodeId::IndexExpr) ||
               node.is(AstNodeId::CastExpr);
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

    struct InlineArgumentMapContext
    {
        AstNodeRef                            callRef      = AstNodeRef::invalid();
        const SymbolFunction*                 fn           = nullptr;
        const Ast*                            sourceAst    = nullptr;
        std::span<AstNodeRef>                 args         = {};
        std::span<AstNodeRef>                 sourceArgs   = {};
        AstNodeRef                            ufcsArg      = AstNodeRef::invalid();
        std::span<const ResolvedCallArgument> resolvedArgs = {};
    };

    AstNodeRef cloneSourceArgumentToCallerAst(Sema& sema, AstNodeRef argRef, const Ast* sourceAst)
    {
        if (argRef.isInvalid() || !sourceAst || sourceAst == &sema.ast())
            return argRef;

        const SemaClone::CloneContext cloneContext{std::span<const SemaClone::ParamBinding>{}, std::span<const SemaClone::NodeReplacement>{}, false, sourceAst};
        return SemaClone::cloneAst(sema, argRef, cloneContext);
    }

    SymbolVariable* receiverBinding(Sema& sema, const SymbolFunction& fn)
    {
        const IdentifierRef meId = sema.idMgr().predefined(IdentifierManager::PredefinedName::Me);
        for (SymbolVariable* param : fn.parameters())
        {
            if (param && param->idRef() == meId)
                return param;
        }

        return nullptr;
    }

    void appendGenericBindingsFromKeys(Sema& sema, std::span<const SemaGeneric::GenericParamDesc> params, std::span<const GenericInstanceKey> args, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        if (params.size() != args.size())
            return;

        for (size_t i = 0; i < args.size(); ++i)
        {
            SemaGeneric::GenericResolvedArg resolvedArg;
            resolvedArg.present = args[i].typeRef.isValid() || args[i].cstRef.isValid();
            resolvedArg.typeRef = args[i].typeRef;
            resolvedArg.cstRef  = args[i].cstRef;
            if (resolvedArg.cstRef.isValid() && !resolvedArg.typeRef.isValid())
                resolvedArg.typeRef = sema.cstMgr().get(resolvedArg.cstRef).typeRef();
            SemaGeneric::appendResolvedGenericBinding(params[i], resolvedArg, outBindings);
        }
    }

    void appendFunctionGenericBindings(Sema& sema, const SymbolFunction& fn, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        if (!fn.isGenericInstance())
            return;

        const SymbolFunction* root = fn.genericRootSym();
        if (!root || !root->decl())
            return;

        const auto* decl = root->decl()->safeCast<AstFunctionDecl>();
        if (!decl || decl->spanGenericParamsRef.isInvalid())
            return;

        SmallVector<SemaGeneric::GenericParamDesc> params;
        SemaGeneric::collectGenericParams(sema, *decl, decl->spanGenericParamsRef, params);
        if (params.empty())
            return;

        SmallVector<GenericInstanceKey> args;
        if (!root->genericInstanceStorage(sema.ctx()).tryGetArgs(fn, args))
            return;
        if (args.size() > params.size())
            args.resize(params.size());

        appendGenericBindingsFromKeys(sema, params.span(), args.span(), outBindings);
    }

    void appendOwnerStructGenericBindings(Sema& sema, const SymbolFunction& fn, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        const SymbolStruct* ownerInstance = fn.ownerStruct();
        if (!ownerInstance || !ownerInstance->isGenericInstance())
            return;

        const SymbolStruct* root = ownerInstance->genericRootSym();
        if (!root || !root->decl())
            return;

        const auto* decl = root->decl()->safeCast<AstStructDecl>();
        if (!decl || decl->spanGenericParamsRef.isInvalid())
            return;

        SmallVector<SemaGeneric::GenericParamDesc> params;
        SemaGeneric::collectGenericParams(sema, *decl, decl->spanGenericParamsRef, params);
        if (params.empty())
            return;

        SmallVector<GenericInstanceKey> args;
        if (!root->tryGetGenericInstanceArgs(*ownerInstance, args))
            return;
        if (args.size() > params.size())
            args.resize(params.size());

        appendGenericBindingsFromKeys(sema, params.span(), args.span(), outBindings);
    }

    void appendGenericInstanceBindings(Sema& sema, const SymbolFunction& fn, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        appendFunctionGenericBindings(sema, fn, outBindings);
        appendOwnerStructGenericBindings(sema, fn, outBindings);
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

    AstNodeRef bindingValueArgumentRef(Sema& sema, AstNodeRef argRef)
    {
        if (argRef.isInvalid())
            return AstNodeRef::invalid();

        if (sema.node(argRef).is(AstNodeId::EmbeddedBlock))
        {
            const auto* inlinePayload = sema.inlinePayload(argRef);
            if (inlinePayload && inlinePayload->callRef.isValid())
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
            isInlineReexpandableExpr(sema.node(argRef)))
            return argRef;

        return resolvedRef;
    }

    bool isImplicitTrailingCodeBlockArg(Sema& sema, AstNodeRef argRef)
    {
        const AstNode& argNode = sema.node(argRef);
        if (!argNode.is(AstNodeId::CompilerCodeBlock))
            return false;

        const AstNodeRef bodyRef = argNode.cast<AstCompilerCodeBlock>().nodeBodyRef;
        if (bodyRef.isInvalid())
            return false;
        if (!sema.node(bodyRef).is(AstNodeId::EmbeddedBlock))
            return false;

        return sema.node(bodyRef).cast<AstEmbeddedBlock>().hasFlag(AstEmbeddedBlockFlagsE::ImplicitCodeBlockArg);
    }

    AstNodeRef sourceArgRefAt(const InlineArgumentMapContext& context, size_t index, AstNodeRef fallbackArgRef)
    {
        if (context.sourceArgs.size() == context.args.size() && index < context.sourceArgs.size())
            return context.sourceArgs[index];
        return fallbackArgRef;
    }

    AstNodeRef bindingArgumentRef(Sema& sema, const SymbolVariable& param, AstNodeRef argRef, AstNodeRef sourceArgRef = AstNodeRef::invalid())
    {
        if (argRef.isInvalid())
            return AstNodeRef::invalid();

        const TypeInfo& paramType = param.type(sema.ctx());
        if (paramType.isCodeBlock())
        {
            const AstNodeRef resolvedRef = sema.viewZero(argRef).nodeRef();
            if (resolvedRef.isValid() && resolvedRef != argRef)
            {
                const AstNode& resolvedNode = sema.node(resolvedRef);
                if (resolvedNode.is(AstNodeId::CompilerCodeExpr) || resolvedNode.is(AstNodeId::CompilerCodeBlock))
                    return wrapCodeArgument(sema, param, resolvedRef);
            }

            if (sema.node(argRef).is(AstNodeId::CompilerCodeExpr) || sema.node(argRef).is(AstNodeId::CompilerCodeBlock))
                return wrapCodeArgument(sema, param, resolvedRef.isValid() ? resolvedRef : argRef);
            if (sourceArgRef.isValid())
                return wrapCodeArgument(sema, param, sourceArgRef);
            return wrapCodeArgument(sema, param, argRef);
        }

        return bindingValueArgumentRef(sema, argRef);
    }

    AstNodeRef bindingResolvedArgumentRef(Sema& sema, const SymbolVariable& param, std::span<const ResolvedCallArgument> resolvedArgs, size_t paramIndex, AstNodeRef fallbackArgRef)
    {
        if (paramIndex < resolvedArgs.size() && resolvedArgs[paramIndex].argRef.isValid())
            return bindingArgumentRef(sema, param, resolvedArgs[paramIndex].argRef);
        return bindingArgumentRef(sema, param, fallbackArgRef);
    }

    AstNodeRef stripUserDefinedLiteralInlineValue(Sema& sema, AstNodeRef argRef)
    {
        UserDefinedLiteralSuffixInfo suffixInfo;
        if (!Cast::resolveUserDefinedLiteralSuffix(sema, argRef, suffixInfo) || !suffixInfo.literalRef.isValid())
            return argRef;

        const SemaClone::CloneContext noBindings{std::span<const SemaClone::ParamBinding>{}};
        const AstNodeRef              literalRef = SemaClone::cloneAst(sema, suffixInfo.literalRef, noBindings);
        if (literalRef.isInvalid())
            return argRef;

        if (suffixInfo.unaryOp != TokenId::SymPlus && suffixInfo.unaryOp != TokenId::SymMinus)
            return literalRef;

        auto [unaryRef, unaryPtr] = sema.ast().makeNode<AstNodeId::UnaryExpr>(sema.node(suffixInfo.exprRef).tokRef());
        unaryPtr->setCodeRef(sema.node(suffixInfo.exprRef).codeRef());
        unaryPtr->nodeExprRef = literalRef;
        return unaryRef;
    }

    bool shouldStripLiteralSuffixInlineValue(const SymbolFunction& fn, size_t paramIndex, size_t numFixed)
    {
        return fn.specOpKind() == SpecOpKind::OpSetLiteral && paramIndex + 1 == numFixed;
    }

    AstNodeRef bindingInlineArgumentRef(Sema& sema, const InlineArgumentMapContext& context, const SymbolVariable& param, size_t paramIndex, size_t numFixed, AstNodeRef argRef, AstNodeRef sourceArgRef = AstNodeRef::invalid())
    {
        AstNodeRef argValueRef = bindingArgumentRef(sema, param, argRef, sourceArgRef);
        if (!shouldStripLiteralSuffixInlineValue(*context.fn, paramIndex, numFixed))
            return argValueRef;

        argValueRef = bindingResolvedArgumentRef(sema, param, context.resolvedArgs, paramIndex, argRef);
        return stripUserDefinedLiteralInlineValue(sema, argValueRef);
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

    void normalizeInlineConstantType(Sema& sema, ConstantRef& ioConstant, TypeRef targetTypeRef)
    {
        if (!ioConstant.isValid() || !targetTypeRef.isValid())
            return;

        ConstantValue constantValue = sema.cstMgr().get(ioConstant);
        if (constantValue.typeRef() == targetTypeRef)
            return;

        constantValue.setTypeRef(targetTypeRef);
        ioConstant = sema.cstMgr().addConstant(sema.ctx(), constantValue);
    }

    bool resolveFunctionDecl(const Sema& sema, const SymbolFunction& fn, const AstFunctionDecl*& outDecl, const Ast*& outDeclAst)
    {
        outDecl    = nullptr;
        outDeclAst = nullptr;

        const AstNode* declNode = fn.decl();
        if (!declNode || !declNode->is(AstNodeId::FunctionDecl))
            return false;

        const Ast* declAst = declNode->sourceAst(sema.ctx());
        if (!declAst)
            return false;

        outDecl    = &declNode->cast<AstFunctionDecl>();
        outDeclAst = declAst;
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

    void collectAliasUsage(Sema& sema, const Ast& sourceAst, AstNodeRef nodeRef, AliasRefArray& outAliasRefs)
    {
        if (nodeRef.isInvalid())
            return;

        const AstNode& node = sourceAst.node(nodeRef);
        if (node.tokRef().isInvalid())
            return;

        const SourceView& sourceView = sema.srcView(node.srcViewRef());
        const TokenRef    endTokRef  = node.tokRefEnd(sourceAst);
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

        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, sourceAst);
        for (const AstNodeRef childRef : children)
            collectAliasUsage(sema, sourceAst, childRef, outAliasRefs);
    }

    Result collectAliasUsageInfo(Sema& sema, const Ast& sourceAst, const AstFunctionDecl& decl, AliasUsageInfo& outInfo)
    {
        outInfo = {};
        if (decl.nodeBodyRef.isInvalid())
            return Result::Continue;

        AliasRefArray aliasRefs = {};
        collectAliasUsage(sema, sourceAst, decl.nodeBodyRef, aliasRefs);

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

    Result collectAliasIdentifiers(Sema& sema, AstNodeRef callRef, const Ast& sourceAst, const AstFunctionDecl& decl, AliasIdentifierArray& outAliasIdentifiers)
    {
        outAliasIdentifiers.fill(IdentifierRef::invalid());

        SmallVector<AstNodeRef> aliases;
        SmallVector<TokenRef>   foreachNames;
        bool                    isForeachCall = false;
        if (callRef.isValid())
        {
            const AstNode& callNode = sema.node(callRef);

            const auto* aliasCall = callNode.safeCast<AstAliasCallExpr>();
            if (aliasCall)
                aliasCall->collectAliases(aliases, sema.ast());

            const auto* foreachStmt = callNode.safeCast<AstForeachStmt>();
            if (foreachStmt)
            {
                isForeachCall = true;
                sema.ast().appendTokens(foreachNames, foreachStmt->spanNamesRef);
            }
        }

        AliasUsageInfo aliasUsage;
        const Result   usageResult = collectAliasUsageInfo(sema, sourceAst, decl, aliasUsage);
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

        const size_t providedAliasCount = !aliases.empty() ? aliases.size() : foreachNames.size();
        if (providedAliasCount > aliasUsage.aliasCount)
        {
            const SourceCodeRef errorRef = !aliases.empty() ? sema.node(aliases[aliasUsage.aliasCount]).codeRef() : SourceCodeRef{sema.node(callRef).srcViewRef(), foreachNames[aliasUsage.aliasCount]};
            auto                diag     = SemaError::report(sema, DiagnosticId::sema_err_too_many_aliases, errorRef);
            diag.addArgument(Diagnostic::ARG_COUNT, aliasUsage.aliasCount);
            diag.addArgument(Diagnostic::ARG_VALUE, static_cast<uint32_t>(providedAliasCount));
            diag.report(sema.ctx());
            return Result::Error;
        }

        for (size_t slot = 0; slot < aliases.size(); ++slot)
        {
            const AstNode& aliasNode = sema.node(aliases[slot]);
            if (aliasNode.is(AstNodeId::Identifier))
                outAliasIdentifiers[slot] = SemaHelpers::resolveIdentifier(sema, aliasNode.codeRef());
        }

        for (size_t slot = 0; slot < foreachNames.size(); ++slot)
            outAliasIdentifiers[slot] = sema.idMgr().addIdentifier(sema.ctx(), SourceCodeRef{sema.node(callRef).srcViewRef(), foreachNames[slot]});

        if (isForeachCall)
        {
            for (uint32_t slot = static_cast<uint32_t>(foreachNames.size()); slot < aliasUsage.aliasCount; ++slot)
                outAliasIdentifiers[slot] = SemaHelpers::getUniqueIdentifier(sema, "__foreach_alias");
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

    SymbolVariable* makeMaterializedInlineBindingSymbol(Sema& sema, const AstSingleVarDecl& sourceDecl, AstSingleVarDecl& materializedDecl)
    {
        const IdentifierRef idRef  = SemaHelpers::getUniqueIdentifier(sema, "__inline_arg");
        const SymbolFlags   flags  = sema.frame().flagsForCurrentAccess();
        auto*               symVar = Symbol::make<SymbolVariable>(sema.ctx(), &materializedDecl, sourceDecl.tokNameRef, idRef, flags);
        symVar->addExtraFlag(SymbolVariableFlagsE::Let);
        return symVar;
    }

    AstNodeRef makeMaterializedInlineBindingUse(Sema& sema, const AstSingleVarDecl& sourceDecl, SymbolVariable& materializedSym)
    {
        auto [identRef, identPtr] = sema.ast().makeNode<AstNodeId::Identifier>(sourceDecl.tokRef());
        identPtr->addFlag(AstIdentifierFlagsE::PreResolvedSymbol);
        sema.setSymbol(identRef, &materializedSym);
        return identRef;
    }

    void appendInlineLocalIdentifier(Sema& sema, const AstNode& node, TokenRef tokNameRef, SmallVector<IdentifierRef>& outIdentifiers)
    {
        if (tokNameRef.isValid())
            outIdentifiers.push_back(SemaHelpers::resolveIdentifier(sema, {node.srcViewRef(), tokNameRef}));
    }

    void appendInlineLocalIdentifiers(Sema& sema, const Ast& sourceAst, const AstNode& node, SpanRef spanNamesRef, SmallVector<IdentifierRef>& outIdentifiers)
    {
        SmallVector<TokenRef> tokNames;
        sourceAst.appendTokens(tokNames, spanNamesRef);
        for (const TokenRef tokNameRef : tokNames)
            appendInlineLocalIdentifier(sema, node, tokNameRef, outIdentifiers);
    }

    void collectInlineLocalIdentifiers(Sema& sema, const Ast& sourceAst, AstNodeRef nodeRef, SmallVector<IdentifierRef>& outIdentifiers)
    {
        if (nodeRef.isInvalid())
            return;

        const AstNode& node = sourceAst.node(nodeRef);
        if (const auto* singleVar = node.safeCast<AstSingleVarDecl>())
            appendInlineLocalIdentifier(sema, node, singleVar->tokNameRef, outIdentifiers);
        else if (const auto* multiVar = node.safeCast<AstMultiVarDecl>())
            appendInlineLocalIdentifiers(sema, sourceAst, node, multiVar->spanNamesRef, outIdentifiers);
        else if (const auto* destructuring = node.safeCast<AstVarDeclDestructuring>())
            appendInlineLocalIdentifiers(sema, sourceAst, node, destructuring->spanNamesRef, outIdentifiers);
        else if (const auto* forStmt = node.safeCast<AstForStmt>())
            appendInlineLocalIdentifier(sema, node, forStmt->tokNameRef, outIdentifiers);
        else if (const auto* foreachStmt = node.safeCast<AstForeachStmt>())
            appendInlineLocalIdentifiers(sema, sourceAst, node, foreachStmt->spanNamesRef, outIdentifiers);

        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, sourceAst);
        for (const AstNodeRef childRef : children)
            collectInlineLocalIdentifiers(sema, sourceAst, childRef, outIdentifiers);
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

    Result materializeInlineBindings(Sema& sema, const SymbolFunction& fn, const Ast& sourceAst, const AstFunctionDecl& decl, SmallVector<SemaClone::ParamBinding>& ioBindings, SmallVector<AstNodeRef>& outStatements)
    {
        outStatements.clear();
        if (ioBindings.empty())
            return Result::Continue;

        const SemaClone::CloneContext noBindings{std::span<const SemaClone::ParamBinding>{}};
        SmallVector<IdentifierRef>    localIdentifiers;
        collectInlineLocalIdentifiers(sema, sourceAst, decl.nodeBodyRef, localIdentifiers);

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
            SymbolVariable* materializedSym = makeMaterializedInlineBindingSymbol(sema, *paramDecl, *declPtr);
            sema.setSymbol(declRef, materializedSym);
            outStatements.push_back(declRef);

            binding.exprRef = makeMaterializedInlineBindingUse(sema, *paramDecl, *materializedSym);
            remainingBindings.push_back(binding);
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
                normalizeInlineConstantType(sema, cstRef, payload.returnTypeRef);
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

    Result mapArguments(Sema& sema, bool& outMapped, const InlineArgumentMapContext& context, SmallVector<SemaClone::ParamBinding>& outBindings, InlineVariadicBinding& outVariadic)
    {
        outMapped   = false;
        outVariadic = {};

        SWC_ASSERT(context.fn != nullptr);
        const SymbolFunction& fn     = *context.fn;
        const auto&           params = fn.parameters();
        const auto            args   = context.args;
        if (params.empty())
        {
            outMapped = !context.ufcsArg.isValid() && args.empty();
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

        if (context.ufcsArg.isValid())
        {
            const AstNodeRef ufcsRef = bindingArgumentRef(sema, *params[0], context.ufcsArg);
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
                return Result::Continue;
            }
        }

        for (size_t argIndex = 0; argIndex < args.size(); ++argIndex)
        {
            const AstNodeRef argRef  = args[argIndex];
            const AstNode&   argNode = sema.node(argRef);
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

            AstNodeRef       sourceValueRef = AstNodeRef::invalid();
            const AstNodeRef sourceArgRef   = sourceArgRefAt(context, argIndex, argRef);
            if (sourceArgRef.isValid())
            {
                const AstNode& sourceArgNode = sema.node(sourceArgRef);
                if (sourceArgNode.is(AstNodeId::NamedArgument))
                    sourceValueRef = sourceArgNode.cast<AstNamedArgument>().nodeArgRef;
            }

            AstNodeRef argValueRef = bindingInlineArgumentRef(sema, context, *params[paramIndex], paramIndex, numFixed, namedArg.nodeArgRef, sourceValueRef);
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

        for (size_t argIndex = 0; argIndex < args.size(); ++argIndex)
        {
            const AstNodeRef argRef       = args[argIndex];
            const AstNodeRef sourceArgRef = sourceArgRefAt(context, argIndex, argRef);
            const AstNode&   argNode      = sema.node(argRef);
            if (argNode.is(AstNodeId::NamedArgument))
                continue;

            if (numFixed &&
                isImplicitTrailingCodeBlockArg(sema, argRef) &&
                params[numFixed - 1]->type(sema.ctx()).isCodeBlock() &&
                !isBindingAssigned(bound[numFixed - 1]))
            {
                const size_t trailingParamIndex   = numFixed - 1;
                bound[trailingParamIndex].idRef   = params[trailingParamIndex]->idRef();
                bound[trailingParamIndex].exprRef = bindingInlineArgumentRef(sema, context, *params[trailingParamIndex], trailingParamIndex, numFixed, argRef, sourceArgRef);
                continue;
            }

            while (nextParam < numFixed && isBindingAssigned(bound[nextParam]))
                nextParam++;

            AstNodeRef argValueRef = nextParam < numFixed ? bindingInlineArgumentRef(sema, context, *params[nextParam], nextParam, numFixed, argRef, sourceArgRef) : bindingValueArgumentRef(sema, argRef);
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
                    const SourceCodeRange codeRange = sema.node(context.callRef).codeRangeWithChildren(sema.ctx(), sema.ast());
                    bound[i].typeRef                = param->typeRef();
                    SWC_RESULT(ConstantHelpers::makeSourceCodeLocation(sema, bound[i].cstRef, codeRange, SemaHelpers::currentLocationFunction(sema)));
                }
                else
                {
                    const AstNodeRef defaultArgRef = cloneSourceArgumentToCallerAst(sema, SemaHelpers::defaultArgumentExprRef(*param), context.sourceAst);
                    const AstNodeRef defaultRef    = bindingArgumentRef(sema, *param, defaultArgRef);
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

Result SemaInline::tryInlineCall(Sema& sema, AstNodeRef callRef, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, std::span<AstNodeRef> sourceArgs)
{
    if (sema.hasSubstitute(callRef))
    {
        return Result::Continue;
    }

    if (isInlineRecursion(sema, fn))
    {
        return Result::Continue;
    }

    if (!canInlineCall(sema, fn))
    {
        return Result::Continue;
    }

    const AstFunctionDecl* decl    = nullptr;
    const Ast*             declAst = nullptr;
    if (!resolveFunctionDecl(sema, fn, decl, declAst))
    {
        return Result::Continue;
    }
    SWC_ASSERT(declAst != nullptr);

    const bool isMacro          = fn.attributes().hasRtFlag(RtAttributeFlagsE::Macro);
    const bool isMixin          = fn.attributes().hasRtFlag(RtAttributeFlagsE::Mixin);
    const bool isCrossAstInline = declAst != &sema.ast();
    if (isCrossAstInline && !isMacro && !isMixin)
        return Result::Continue;

    SmallVector<ResolvedCallArgument> resolvedArgs;
    sema.appendResolvedCallArguments(callRef, resolvedArgs);

    const InlineArgumentMapContext context{
        .callRef      = callRef,
        .fn           = &fn,
        .sourceAst    = declAst,
        .args         = args,
        .sourceArgs   = sourceArgs,
        .ufcsArg      = ufcsArg,
        .resolvedArgs = resolvedArgs.span(),
    };

    SmallVector<SemaClone::ParamBinding> bindings;
    InlineVariadicBinding                variadicBinding;
    bool                                 mapped = false;
    SWC_RESULT(mapArguments(sema, mapped, context, bindings, variadicBinding));
    if (!mapped)
    {
        return Result::Continue;
    }
    if (isCrossAstInline)
        appendGenericInstanceBindings(sema, fn, bindings);

    AliasIdentifierArray aliasIdentifiers = {};
    SWC_RESULT(collectAliasIdentifiers(sema, callRef, *declAst, *decl, aliasIdentifiers));

    AstNodeRef variadicExprRef     = AstNodeRef::invalid();
    TypeRef    variadicExprTypeRef = TypeRef::invalid();
    SWC_RESULT(createVariadicInlineExpression(sema, callRef, variadicBinding, variadicExprRef, variadicExprTypeRef));
    if (variadicBinding.param)
    {
        if (variadicExprRef.isInvalid() || variadicExprTypeRef.isInvalid())
        {
            return Result::Continue;
        }
        if (variadicBinding.param->idRef().isValid())
            bindings.push_back({variadicBinding.param->idRef(), variadicExprRef, variadicExprTypeRef});
    }

    TypeRef returnTypeRef = fn.returnTypeRef();
    if (!returnTypeRef.isValid())
        returnTypeRef = sema.typeMgr().typeVoid();

    SWC_RESULT(waitInlineResultTypeIfNeeded(sema, callRef, returnTypeRef));

    SmallVector<AstNodeRef> materializedBindings;
    if (!fn.attributes().hasRtFlag(RtAttributeFlagsE::Macro) && !fn.attributes().hasRtFlag(RtAttributeFlagsE::Mixin))
        SWC_RESULT(materializeInlineBindings(sema, fn, *declAst, *decl, bindings, materializedBindings));

    const SemaClone::CloneContext cloneContext{bindings.span(), std::span<const SemaClone::NodeReplacement>{}, false, declAst};
    const AstNodeRef              inlineRootRef = isMixin ? mixinBodyRef(sema, *decl, cloneContext, materializedBindings.span()) : inlineBodyRef(sema, *decl, cloneContext, materializedBindings.span());
    if (inlineRootRef.isInvalid())
    {
        return Result::Continue;
    }
    sema.node(inlineRootRef).setCodeRef(sema.node(callRef).codeRef());

    SymbolVariable* resultVar = nullptr;
    SWC_RESULT(createInlineResultVariable(sema, callRef, returnTypeRef, resultVar));

    // Create payload
    auto*      inlinePayload = sema.compiler().allocate<SemaInlinePayload>();
    auto       frame         = sema.frame();
    SemaScope* callerScope   = sema.curScopePtr();

    inlinePayload->callRef             = callRef;
    inlinePayload->inlineRootRef       = inlineRootRef;
    inlinePayload->sourceFunction      = &fn;
    inlinePayload->parentInlinePayload = sema.frame().currentInlinePayload();
    inlinePayload->callerScope         = callerScope;
    inlinePayload->crossAstInline      = isCrossAstInline;
    inlinePayload->resultVar           = resultVar;
    inlinePayload->returnTypeRef       = returnTypeRef;
    inlinePayload->aliasIdentifiers    = aliasIdentifiers;
    for (const SemaClone::ParamBinding& binding : bindings)
        inlinePayload->argMappings.push_back(binding);
    for (SymbolVariable* bindingVar : frame.bindingVars())
        inlinePayload->callerBindingVars.push_back(bindingVar);
    for (TypeRef bindingType : frame.bindingTypes())
        inlinePayload->callerBindingTypes.push_back(bindingType);

    if (returnTypeRef != sema.typeMgr().typeVoid())
        frame.pushBindingType(returnTypeRef);
    frame.setCurrentInlinePayload(inlinePayload);
    if ((isMacro || isMixin) && isCrossAstInline)
    {
        if (SymbolVariable* receiver = receiverBinding(sema, fn))
            frame.pushBindingVar(receiver);
    }
    if (isMacro)
        frame.setUpLookupScope(callerScope);
    sema.pushFramePopOnPostNode(frame, inlineRootRef);
    if (!isMixin)
    {
        if ((isMacro || isMixin) && isCrossAstInline)
        {
            SemaScope* ownerScope = sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local, inlineRootRef);
            if (fn.ownerSymMap())
                ownerScope->setSymMap(const_cast<SymbolMap*>(fn.ownerSymMap()));
            ownerScope->setLookupParent(callerScope);

            SemaScope* inlineScope = sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local, inlineRootRef);
            inlineScope->setSymMap(const_cast<SymbolFunction*>(&fn));
            inlineScope->setLookupParent(ownerScope);
        }
        else
        {
            sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local, inlineRootRef);
        }
    }

    sema.deferPostNodeAction(inlineRootRef, [inlinePayload](Sema& inSema, AstNodeRef nodeRef) {
        SWC_ASSERT(inlinePayload != nullptr);
        SWC_RESULT(finalizeInlineBlock(inSema, nodeRef, *inlinePayload));
        if (const auto* existingPayload = inSema.inlinePayload(nodeRef))
            SWC_ASSERT(existingPayload == inlinePayload);
        else
            inSema.setInlinePayload(nodeRef, inlinePayload);
        return Result::Continue;
    });

    sema.setSubstitute(callRef, inlineRootRef);
    sema.visit().restartCurrentNode(inlineRootRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
