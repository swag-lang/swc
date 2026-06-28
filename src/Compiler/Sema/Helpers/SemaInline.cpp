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
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isInlineRecursion(Sema& sema, const SymbolFunction& fn)
    {
        const SemaInlinePayload* frameInlinePayload     = sema.frame().currentInlinePayload();
        const SemaInlinePayload* effectiveInlinePayload = SemaHelpers::effectiveInlinePayload(sema);

        if (effectiveInlinePayload == frameInlinePayload && sema.currentFunction() == &fn)
            return true;

        const SemaInlinePayload* inlinePayload = effectiveInlinePayload;
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

    // A `character`/`bool` literal argument is a coercible constant just like an integer literal: a
    // real call coerces it to the parameter type (e.g. `'A'` -> `u8`). The shared
    // canUseContextualBinding does not list them (to stay conservative at its other, non-inline call
    // sites), so an inline binding recognizes them here. Without this, the materialized body sees the
    // raw `character`/`bool` type and, e.g., rejects `arr[vkey]` as a non-integer index.
    bool isInlineCoercibleLiteralArg(const AstNode& node)
    {
        return node.is(AstNodeId::CharacterLiteral) || node.is(AstNodeId::BoolLiteral);
    }

    TypeRef inlineContextualBindingTypeRef(Sema& sema, const SymbolVariable& param, AstNodeRef exprRef)
    {
        const TypeRef paramTypeRef = param.typeRef();
        if (paramTypeRef.isInvalid() || exprRef.isInvalid())
            return TypeRef::invalid();

        const TypeInfo& paramType = param.type(sema.ctx());
        if (paramType.isCodeBlock() || paramType.isAnyVariadic() || paramType.isReference())
            return TypeRef::invalid();
        const AstNode& exprNode   = sema.node(exprRef);
        const bool     isCastExpr = exprNode.is(AstNodeId::CastExpr) || exprNode.is(AstNodeId::AutoCastExpr);
        if (!isCastExpr && !isInlineCoercibleLiteralArg(exprNode) && !SemaHelpers::canUseContextualBinding(sema, exprRef))
            return TypeRef::invalid();

        return paramTypeRef;
    }

    void assignInlineBindingExpr(Sema& sema, SemaClone::ParamBinding& binding, const SymbolVariable& param, AstNodeRef exprRef)
    {
        binding.idRef       = param.idRef();
        binding.sourceParam = &param;

        const TypeRef paramTypeRef = param.typeRef();
        if (paramTypeRef.isValid() && exprRef.isValid())
        {
            const TypeInfo& paramType = param.type(sema.ctx());
            if (paramType.isAnyTypeInfo(sema.ctx()))
            {
                const SemaNodeView exprView(sema, exprRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
                if (exprView.cstRef().isValid() && exprView.type() && exprView.type()->isAnyTypeInfo(sema.ctx()))
                {
                    binding.typeRef = paramTypeRef;
                    binding.cstRef  = exprView.cstRef();
                    return;
                }
            }
        }

        binding.exprRef = exprRef;
        binding.typeRef = inlineContextualBindingTypeRef(sema, param, exprRef);
    }

    bool functionOwnsVariable(const SymbolFunction& function, const SymbolVariable& symVar)
    {
        if (symVar.ownerSymMap() == &function)
            return true;
        if (function.containsLocalVariable(symVar))
            return true;

        const auto& params = function.parameters();
        return std::ranges::find(params, &symVar) != params.end();
    }

    const SymbolFunction* parentLexicalFunction(const SymbolFunction& function)
    {
        const SymbolMap* map = function.ownerSymMap();
        while (map)
        {
            if (map->isFunction())
                return &map->cast<SymbolFunction>();
            map = map->ownerSymMap();
        }

        return nullptr;
    }

    const SymbolFunction* localFunctionBoundaryForOuterVariable(const SymbolFunction& currentFn, const SymbolVariable& symVar)
    {
        if (symVar.hasGlobalStorage())
            return nullptr;

        if (!(symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter) ||
              symVar.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal) ||
              symVar.isClosureCapture()))
            return nullptr;

        const SymbolFunction* fn = &currentFn;
        while (fn)
        {
            if (functionOwnsVariable(*fn, symVar))
                return nullptr;

            const AstNode* decl = fn->decl();
            if (decl && decl->is(AstNodeId::FunctionDecl))
                return fn;

            fn = parentLexicalFunction(*fn);
        }

        return nullptr;
    }

    const SymbolFunction* inlineBindingValidationFunction(Sema& sema, AstNodeRef nodeRef, const SymbolFunction& currentFn)
    {
        const AstNode& node = sema.node(nodeRef);
        if (node.isNot(AstNodeId::FunctionExpr) && node.isNot(AstNodeId::ClosureExpr))
            return &currentFn;

        const Symbol* sym = sema.viewStored(nodeRef, SemaNodeViewPartE::Symbol).sym();
        if (!sym || !sym->isFunction())
            return &currentFn;

        return &sym->cast<SymbolFunction>();
    }

    Result validateInlineBindingOuterScopeVariables(Sema& sema, const SymbolFunction& currentFn, AstNodeRef exprRef, SmallVector<AstNodeRef>& visited)
    {
        if (exprRef.isInvalid())
            return Result::Continue;

        SmallVector<AstNodeRef> pending;
        pending.push_back(exprRef);
        while (!pending.empty())
        {
            const AstNodeRef nodeRef = pending.back();
            pending.pop_back();
            if (nodeRef.isInvalid())
                continue;
            if (std::ranges::find(visited, nodeRef) != visited.end())
                continue;
            visited.push_back(nodeRef);

            const AstNode& node = sema.node(nodeRef);
            if (node.is(AstNodeId::Identifier))
            {
                const auto*   identifier = node.safeCast<AstIdentifier>();
                const Symbol* sym        = identifier && identifier->hasFlag(AstIdentifierFlagsE::InClosureCapture) ? nullptr : sema.viewStored(nodeRef, SemaNodeViewPartE::Symbol).sym();
                if (sym && sym->isVariable())
                {
                    const auto&           symVar        = sym->cast<SymbolVariable>();
                    const SymbolFunction* localBoundary = localFunctionBoundaryForOuterVariable(currentFn, symVar);
                    if (localBoundary)
                    {
                        const std::string_view symName = node.codeRef().isValid() ? sema.tokenString(node.codeRef()) : symVar.name(sema.ctx());
                        auto                   diag    = SemaError::report(sema, DiagnosticId::sema_err_local_function_outer_scope_variable, nodeRef);
                        diag.addArgument(Diagnostic::ARG_SYM, symName);

                        if (localBoundary->decl())
                        {
                            diag.addNote(DiagnosticId::sema_note_function_declared_here);
                            diag.last().addArgument(Diagnostic::ARG_SYM, localBoundary->name(sema.ctx()));
                            diag.last().addSpan(localBoundary->codeRange(sema.ctx()));
                        }

                        if (symVar.decl())
                        {
                            diag.addNote(DiagnosticId::sema_note_capture_source_declared_here);
                            diag.last().addArgument(Diagnostic::ARG_SYM, symName);
                            diag.last().addSpan(symVar.codeRange(sema.ctx()));
                        }

                        diag.report(sema.ctx());
                        return Result::Error;
                    }
                }
            }

            const AstNodeRef resolvedRef = sema.viewZero(nodeRef).nodeRef();
            if (resolvedRef.isValid() && resolvedRef != nodeRef)
                pending.push_back(resolvedRef);

            const SymbolFunction* childCurrentFn = inlineBindingValidationFunction(sema, nodeRef, currentFn);
            if (childCurrentFn != &currentFn)
            {
                SmallVector<AstNodeRef> children;
                node.collectChildrenFromAst(children, sema.ast());
                for (const AstNodeRef childRef : children)
                    SWC_RESULT(validateInlineBindingOuterScopeVariables(sema, *childCurrentFn, childRef, visited));
                continue;
            }

            SmallVector<AstNodeRef> children;
            node.collectChildrenFromAst(children, sema.ast());
            for (const AstNodeRef childRef : children)
                pending.push_back(childRef);
        }

        return Result::Continue;
    }

    Result validateInlineBindingOuterScopeVariables(Sema& sema, AstNodeRef exprRef)
    {
        const SymbolFunction* currentFn = sema.currentFunction();
        if (!currentFn)
            return Result::Continue;

        SmallVector<AstNodeRef> visited;
        return validateInlineBindingOuterScopeVariables(sema, *currentFn, exprRef, visited);
    }

    bool shouldValidateInlineBindingOuterScope(Sema& sema, const SemaClone::ParamBinding& binding, bool callerScopeInline)
    {
        if (!callerScopeInline)
            return true;

        if (binding.sourceParam && binding.sourceParam->type(sema.ctx()).isCodeBlock())
            return false;

        if (binding.exprRef.isInvalid())
            return true;

        const AstNode& exprNode = sema.node(binding.exprRef);
        return !exprNode.is(AstNodeId::CompilerCodeExpr) &&
               !exprNode.is(AstNodeId::CompilerCodeBlock);
    }

    struct InlineVariadicBinding
    {
        const SymbolVariable*   param           = nullptr;
        bool                    untypedVariadic = false;
        bool                    allArgsConstant = false;
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

    SymbolVariable* materializedReceiverBinding(Sema& sema, const SymbolVariable& receiver, std::span<const SemaClone::ParamBinding> bindings)
    {
        for (const SemaClone::ParamBinding& binding : bindings)
        {
            if (binding.idRef != receiver.idRef() || !binding.exprRef.isValid())
                continue;

            Symbol* sym = sema.viewSymbol(binding.exprRef).sym();
            if (sym && sym->isVariable())
                return &sym->cast<SymbolVariable>();
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
        SmallVector<SemaGeneric::GenericParamDesc> params;
        SmallVector<GenericInstanceKey>            args;
        if (!SemaGeneric::Internal::loadFunctionInstanceGenericArgs(sema, fn, params, args))
            return;

        appendGenericBindingsFromKeys(sema, params.span(), args.span(), outBindings);
    }

    void appendOwnerStructGenericBindings(Sema& sema, const SymbolFunction& fn, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        SmallVector<SemaGeneric::GenericParamDesc> params;
        SmallVector<GenericInstanceKey>            args;
        if (!SemaGeneric::Internal::loadOwnerStructGenericArgs(sema, fn, params, args))
            return;

        appendGenericBindingsFromKeys(sema, params.span(), args.span(), outBindings);
    }

    void appendGenericInstanceBindings(Sema& sema, const SymbolFunction& fn, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        appendFunctionGenericBindings(sema, fn, outBindings);
        appendOwnerStructGenericBindings(sema, fn, outBindings);
    }

    bool directInlineContextOverrideTarget(const Sema& sema, const SemaInlinePayload*& outTarget, AstNodeRef nodeRef)
    {
        const auto* overridePayload = sema.inlineContextOverride<SemaInlineContextOverride>(nodeRef);
        if (!overridePayload || !overridePayload->targetInlinePayload)
            return false;

        outTarget = overridePayload->targetInlinePayload;
        return true;
    }

    AstNodeRef compilerCodeInnerRef(const AstNode& node)
    {
        if (node.is(AstNodeId::CompilerCodeExpr))
            return node.cast<AstCompilerCodeExpr>().nodeExprRef;
        if (node.is(AstNodeId::CompilerCodeBlock))
            return node.cast<AstCompilerCodeBlock>().nodeBodyRef;
        return AstNodeRef::invalid();
    }

    const SemaClone::ParamBinding* findInlineBinding(Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return nullptr;

        const auto* identifier = sema.node(nodeRef).safeCast<AstIdentifier>();
        if (!identifier)
            return nullptr;

        const IdentifierRef      idRef         = sema.idMgr().addIdentifier(sema.ctx(), identifier->codeRef());
        const SemaInlinePayload* inlinePayload = sema.frame().currentInlinePayload();
        if (!inlinePayload)
            inlinePayload = SemaHelpers::effectiveInlinePayload(sema);

        while (inlinePayload)
        {
            for (const auto& binding : inlinePayload->argMappings)
            {
                if (binding.idRef == idRef)
                    return &binding;
            }
            inlinePayload = inlinePayload->parentInlinePayload;
        }

        return nullptr;
    }

    bool codeArgumentInlineContextTarget(Sema& sema, const SemaInlinePayload*& outTarget, AstNodeRef argRef)
    {
        if (argRef.isInvalid())
            return false;

        if (directInlineContextOverrideTarget(sema, outTarget, argRef))
            return true;

        if (const auto* binding = findInlineBinding(sema, argRef); binding && binding->exprRef.isValid() && binding->exprRef != argRef)
        {
            if (codeArgumentInlineContextTarget(sema, outTarget, binding->exprRef))
                return true;
        }

        const AstNodeRef resolvedRef = sema.viewZero(argRef).nodeRef();
        if (resolvedRef.isValid() && resolvedRef != argRef && codeArgumentInlineContextTarget(sema, outTarget, resolvedRef))
            return true;

        const AstNodeRef innerRef = compilerCodeInnerRef(sema.node(argRef));
        if (innerRef.isValid() && innerRef != argRef)
            return codeArgumentInlineContextTarget(sema, outTarget, innerRef);

        return false;
    }

    AstNodeRef setCodeArgumentContext(Sema& sema, AstNodeRef wrappedRef, AstNodeRef argRef)
    {
        const SemaInlinePayload* targetInlinePayload = nullptr;
        if (!codeArgumentInlineContextTarget(sema, targetInlinePayload, argRef))
            targetInlinePayload = sema.frame().currentInlinePayload();

        auto* inlineOverridePayload                = sema.compiler().allocate<SemaInlineContextOverride>();
        inlineOverridePayload->targetInlinePayload = targetInlinePayload;
        sema.setInlineContextOverride(wrappedRef, inlineOverridePayload);
        return wrappedRef;
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
            return setCodeArgumentContext(sema, wrappedRef, argRef);
        }

        if (argNode.is(AstNodeId::CompilerCodeExpr))
        {
            auto [wrappedRef, wrappedPtr] = sema.ast().makeNode<AstNodeId::CompilerCodeExpr>(argNode.tokRef());
            wrappedPtr->setCodeRef(argNode.codeRef());
            wrappedPtr->nodeExprRef    = argNode.cast<AstCompilerCodeExpr>().nodeExprRef;
            wrappedPtr->payloadTypeRef = payloadTypeRef;
            return setCodeArgumentContext(sema, wrappedRef, argRef);
        }

        if (argNode.is(AstNodeId::EmbeddedBlock))
        {
            auto [wrappedRef, wrappedPtr] = sema.ast().makeNode<AstNodeId::CompilerCodeBlock>(argNode.tokRef());
            wrappedPtr->setCodeRef(argNode.codeRef());
            wrappedPtr->nodeBodyRef    = argRef;
            wrappedPtr->payloadTypeRef = payloadTypeRef;
            return setCodeArgumentContext(sema, wrappedRef, argRef);
        }

        auto [wrappedRef, wrappedPtr] = sema.ast().makeNode<AstNodeId::CompilerCodeExpr>(argNode.tokRef());
        wrappedPtr->setCodeRef(argNode.codeRef());
        wrappedPtr->nodeExprRef    = argRef;
        wrappedPtr->payloadTypeRef = payloadTypeRef;
        return setCodeArgumentContext(sema, wrappedRef, argRef);
    }

    AstNodeRef bindingValueArgumentRef(Sema& sema, AstNodeRef argRef)
    {
        if (argRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNode& argNode = sema.node(argRef);
        if (argNode.is(AstNodeId::CastExpr) || argNode.is(AstNodeId::AutoCastExpr))
            return argRef;

        if (argNode.is(AstNodeId::EmbeddedBlock))
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

    AstNodeRef referenceBindingArgumentRef(Sema& sema, AstNodeRef argRef)
    {
        const AstNodeRef sourceRef = SemaHelpers::resolveTransparentExprSourceRef(sema, argRef);
        if (sourceRef.isValid())
        {
            const AstNode& sourceNode = sema.node(sourceRef);
            if (sourceNode.is(AstNodeId::UnaryExpr) && sourceNode.codeRef().isValid())
            {
                const auto&   unary = sourceNode.cast<AstUnaryExpr>();
                const TokenId op    = sema.token(sourceNode.codeRef()).id;
                if (op == TokenId::SymAmpersand)
                    return unary.nodeExprRef;

                if (op == TokenId::KwdMoveRef && unary.nodeExprRef.isValid())
                {
                    const AstNodeRef moveSourceRef = SemaHelpers::resolveTransparentExprSourceRef(sema, unary.nodeExprRef);
                    if (moveSourceRef.isValid())
                    {
                        const AstNode& moveNode = sema.node(moveSourceRef);
                        if (moveNode.is(AstNodeId::UnaryExpr) && moveNode.codeRef().isValid())
                        {
                            const auto&   moveUnary = moveNode.cast<AstUnaryExpr>();
                            const TokenId moveOp    = sema.token(moveNode.codeRef()).id;
                            if (moveOp == TokenId::SymAmpersand)
                                return moveUnary.nodeExprRef;
                        }
                    }

                    return unary.nodeExprRef;
                }
            }
        }

        const AstNodeRef valueRef = bindingValueArgumentRef(sema, argRef);
        if (valueRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNode& node = sema.node(valueRef);
        if (!node.is(AstNodeId::UnaryExpr) || !node.codeRef().isValid())
            return valueRef;

        const auto&   unary = node.cast<AstUnaryExpr>();
        const TokenId op    = sema.token(node.codeRef()).id;
        if (op == TokenId::SymAmpersand)
            return unary.nodeExprRef;

        if (op != TokenId::KwdMoveRef || unary.nodeExprRef.isInvalid())
            return valueRef;

        const AstNode& moveExpr = sema.node(unary.nodeExprRef);
        if (!moveExpr.is(AstNodeId::UnaryExpr) || !moveExpr.codeRef().isValid())
            return valueRef;

        const auto&   moveUnary = moveExpr.cast<AstUnaryExpr>();
        const TokenId moveOp    = sema.token(moveExpr.codeRef()).id;
        return moveOp == TokenId::SymAmpersand ? moveUnary.nodeExprRef : unary.nodeExprRef;
    }

    AstNodeRef moveReferenceBindingArgumentRef(Sema& sema, AstNodeRef argRef)
    {
        const AstNodeRef sourceRef = SemaHelpers::resolveTransparentExprSourceRef(sema, argRef);
        if (sourceRef.isValid())
        {
            const AstNode& sourceNode = sema.node(sourceRef);
            if (sourceNode.is(AstNodeId::UnaryExpr) && sourceNode.codeRef().isValid())
            {
                const TokenId op = sema.token(sourceNode.codeRef()).id;
                if (op == TokenId::KwdMoveRef)
                    return sourceRef;
            }
        }

        return bindingValueArgumentRef(sema, argRef);
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
        if (paramType.isMoveReference())
            return moveReferenceBindingArgumentRef(sema, sourceArgRef.isValid() ? sourceArgRef : argRef);
        if (paramType.isReference())
            return referenceBindingArgumentRef(sema, sourceArgRef.isValid() ? sourceArgRef : argRef);

        if (paramType.isCodeBlock())
        {
            if (sourceArgRef.isValid())
                return wrapCodeArgument(sema, param, sourceArgRef);

            const AstNode& argNode = sema.node(argRef);
            if (argNode.is(AstNodeId::CompilerCodeExpr) || argNode.is(AstNodeId::CompilerCodeBlock))
                return wrapCodeArgument(sema, param, argRef);

            const AstNodeRef resolvedRef = sema.viewZero(argRef).nodeRef();
            if (resolvedRef.isValid() && resolvedRef != argRef)
            {
                const AstNode& resolvedNode = sema.node(resolvedRef);
                if (resolvedNode.is(AstNodeId::CompilerCodeExpr) || resolvedNode.is(AstNodeId::CompilerCodeBlock))
                    return wrapCodeArgument(sema, param, resolvedRef);
            }

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

        const TypeInfo& paramType = param.type(sema.ctx());
        if (!paramType.isCodeBlock() && !paramType.isReference())
        {
            const AstNodeRef resolvedArgRef = bindingResolvedArgumentRef(sema, param, context.resolvedArgs, paramIndex, argRef);
            if (resolvedArgRef.isValid())
            {
                const AstNode& resolvedArgNode = sema.node(resolvedArgRef);
                if (resolvedArgNode.is(AstNodeId::CastExpr) || resolvedArgNode.is(AstNodeId::AutoCastExpr))
                    argValueRef = resolvedArgRef;
            }
        }

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

    // A materialized inline body is cloned and re-sema'd in the caller's scope. Identifier symbols
    // are pinned (PreResolvedSymbol) so file-private references survive, but a nested `CallExpr`
    // re-runs overload selection AND drives re-resolution/coercion in downstream subsystems that the
    // clone does not reproduce faithfully: a lambda argument loses the contextual parameter-type
    // inference it took from the callee signature, a const `typeinfo` member access const-folds a
    // func-typed field that cannot be evaluated at compile time, intrinsic calls lose their argument
    // typing, etc. These failures live in const-folding / typeinfo / lambda-inference, not in the
    // inliner, so until they are addressed there, any body containing a call stays out of line. The
    // guard is shared by the auto-inline heuristic (same-Ast) and the explicit cross-Ast inline path.
    bool bodyHasNestedCallExpr(const Ast& ast, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid() || !ast.hasNode(nodeRef))
            return false;

        const AstNode& node = ast.node(nodeRef);
        if (node.is(AstNodeId::CallExpr))
            return true;

        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, ast);
        for (const AstNodeRef childRef : children)
        {
            if (bodyHasNestedCallExpr(ast, childRef))
                return true;
        }

        return false;
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

    void collectAliasUsage(const Ast& sourceAst, SourceViewRef ownerSrcViewRef, AstNodeRef nodeRef, AliasRefArray& outAliasRefs)
    {
        if (nodeRef.isInvalid() || !sourceAst.hasNode(nodeRef))
            return;

        const AstNode& node = sourceAst.node(nodeRef);
        if (node.tokRef().isInvalid())
            return;

        // Alias placeholders belong to the macro declaration source itself.
        // Injected/generated child nodes can carry foreign source views and AST ownership,
        // so alias detection must stay lexical and limited to the declaration body range.
        if (node.srcViewRef().isInvalid() || node.srcViewRef() != ownerSrcViewRef)
            return;

        const SourceView& sourceView = sourceAst.srcView();
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
    }

    Result collectAliasUsageInfo(const Sema& sema, const Ast& sourceAst, const AstFunctionDecl& decl, AliasUsageInfo& outInfo)
    {
        SWC_UNUSED(sema);

        outInfo = {};
        if (decl.nodeBodyRef.isInvalid())
            return Result::Continue;

        AliasRefArray       aliasRefs       = {};
        const SourceViewRef ownerSrcViewRef = sourceAst.srcView().ref();
        collectAliasUsage(sourceAst, ownerSrcViewRef, decl.nodeBodyRef, aliasRefs);

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

    TokenRef materializedInlineBindingTokRef(Sema& sema, const SymbolVariable& sourceParam, AstNodeRef exprRef)
    {
        const AstNode* const paramDecl = sourceParam.decl();
        if (paramDecl &&
            paramDecl->srcViewRef() == sema.curNode().srcViewRef() &&
            sourceParam.tokRef().isValid())
        {
            return sourceParam.tokRef();
        }

        if (exprRef.isValid() && sema.node(exprRef).tokRef().isValid())
            return sema.node(exprRef).tokRef();
        if (sema.curNodeRef().isValid())
            return sema.node(sema.curNodeRef()).tokRef();
        return TokenRef::invalid();
    }

    SymbolVariable* makeMaterializedInlineBindingSymbol(Sema& sema, const SymbolVariable& sourceParam, TokenRef tokRef, const AstSingleVarDecl& materializedDecl, const bool materializedAsLet)
    {
        SWC_UNUSED(sourceParam);
        const IdentifierRef idRef  = SemaHelpers::getUniqueIdentifier(sema, "__inline_arg");
        const SymbolFlags   flags  = sema.frame().flagsForCurrentAccess();
        auto*               symVar = Symbol::make<SymbolVariable>(sema.ctx(), &materializedDecl, tokRef, idRef, flags);
        if (materializedAsLet)
            symVar->addExtraFlag(SymbolVariableFlagsE::Let);
        symVar->addExtraFlag(SymbolVariableFlagsE::RuntimeStorage);
        return symVar;
    }

    AstNodeRef makeMaterializedInlineBindingUse(Sema& sema, TokenRef tokRef, SymbolVariable& materializedSym)
    {
        auto [identRef, identPtr] = sema.ast().makeNode<AstNodeId::Identifier>(tokRef);
        identPtr->addFlag(AstIdentifierFlagsE::PreResolvedSymbol);
        sema.setSymbol(identRef, &materializedSym);
        return identRef;
    }

    void appendInlineLocalIdentifier(Sema& sema, const AstNode& node, TokenRef tokNameRef, SmallVector<IdentifierRef>& outIdentifiers)
    {
        if (!tokNameRef.isValid())
            return;

        const TokenId tokenId = sema.token({node.srcViewRef(), tokNameRef}).id;
        if (Token::isCompilerUniq(tokenId))
            return;

        outIdentifiers.push_back(SemaHelpers::resolveIdentifier(sema, {node.srcViewRef(), tokNameRef}));
    }

    void appendInlineLocalIdentifiers(Sema& sema, const Ast& sourceAst, const AstNode& node, SpanRef spanNamesRef, SmallVector<IdentifierRef>& outIdentifiers)
    {
        SmallVector<TokenRef> tokNames;
        sourceAst.appendTokens(tokNames, spanNamesRef);
        for (const TokenRef tokNameRef : tokNames)
            appendInlineLocalIdentifier(sema, node, tokNameRef, outIdentifiers);
    }

    const Ast* resolveInlineAnalysisNodeAst(Sema& sema, const Ast& sourceAst, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return nullptr;
        if (sourceAst.hasNode(nodeRef))
            return &sourceAst;
        if (sema.ast().hasNode(nodeRef))
            return &sema.ast();
        return nullptr;
    }

    const Ast* resolveInlineAnalysisSpanAst(Sema& sema, const Ast& sourceAst, SpanRef spanRef)
    {
        if (spanRef.isInvalid())
            return nullptr;
        if (sourceAst.hasSpan(spanRef))
            return &sourceAst;
        if (sema.ast().hasSpan(spanRef))
            return &sema.ast();
        return nullptr;
    }

    void collectInlineAnalysisChildren(Sema& sema, const Ast& sourceAst, const Ast& nodeAst, const AstNode& node, SmallVector<AstNodeRef>& outChildren)
    {
        if (const auto* inject = node.safeCast<AstCompilerInject>())
        {
            AstNode::collectChildren(outChildren, {inject->nodeExprRef});
            if (const Ast* replaceAst = resolveInlineAnalysisSpanAst(sema, sourceAst, inject->spanReplaceNodeRef))
                AstNode::collectChildren(outChildren, *replaceAst, inject->spanReplaceNodeRef);
            return;
        }

        node.collectChildrenFromAst(outChildren, nodeAst);
    }

    void collectInlineLocalIdentifiers(Sema& sema, const Ast& sourceAst, AstNodeRef nodeRef, SmallVector<IdentifierRef>& outIdentifiers)
    {
        const Ast* nodeAst = resolveInlineAnalysisNodeAst(sema, sourceAst, nodeRef);
        if (!nodeAst)
            return;

        const AstNode& node = nodeAst->node(nodeRef);
        if (const auto* singleVar = node.safeCast<AstSingleVarDecl>())
            appendInlineLocalIdentifier(sema, node, singleVar->tokNameRef, outIdentifiers);
        else if (const auto* multiVar = node.safeCast<AstMultiVarDecl>())
            appendInlineLocalIdentifiers(sema, *nodeAst, node, multiVar->spanNamesRef, outIdentifiers);
        else if (const auto* destructuring = node.safeCast<AstVarDeclDestructuring>())
            appendInlineLocalIdentifiers(sema, *nodeAst, node, destructuring->spanNamesRef, outIdentifiers);
        else if (const auto* forStmt = node.safeCast<AstForStmt>())
            appendInlineLocalIdentifier(sema, node, forStmt->tokNameRef, outIdentifiers);
        else if (const auto* foreachStmt = node.safeCast<AstForeachStmt>())
            appendInlineLocalIdentifiers(sema, *nodeAst, node, foreachStmt->spanNamesRef, outIdentifiers);

        SmallVector<AstNodeRef> children;
        collectInlineAnalysisChildren(sema, sourceAst, *nodeAst, node, children);
        for (const AstNodeRef childRef : children)
            collectInlineLocalIdentifiers(sema, sourceAst, childRef, outIdentifiers);
    }

    IdentifierRef collectResolvedIdentifier(Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return IdentifierRef::invalid();

        if (const Symbol* symbol = sema.viewStored(nodeRef, SemaNodeViewPartE::Symbol).sym())
            return symbol->idRef();

        const AstNode&      node    = sema.node(nodeRef);
        const SourceCodeRef codeRef = node.codeRef();
        if (!codeRef.isValid())
            return IdentifierRef::invalid();

        const TokenId tokenId = sema.token(codeRef).id;
        if (tokenId == TokenId::Identifier || Token::isCompilerAlias(tokenId) || Token::isCompilerUniq(tokenId))
            return SemaHelpers::resolveIdentifier(sema, codeRef);

        return IdentifierRef::invalid();
    }

    void collectIdentifierUses(Sema& sema, AstNodeRef nodeRef, SmallVector<IdentifierRef>& outIdentifiers)
    {
        if (nodeRef.isInvalid())
            return;

        const AstNode& node = sema.node(nodeRef);
        if (node.is(AstNodeId::Identifier))
        {
            if (const IdentifierRef idRef = collectResolvedIdentifier(sema, nodeRef); idRef.isValid())
                outIdentifiers.push_back(idRef);
        }

        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, sema.ast());
        for (const AstNodeRef childRef : children)
            collectIdentifierUses(sema, childRef, outIdentifiers);
    }

    void collectSourceIdentifierUses(Sema& sema, const Ast& sourceAst, AstNodeRef nodeRef, SmallVector<IdentifierRef>& outIdentifiers)
    {
        const Ast* nodeAst = resolveInlineAnalysisNodeAst(sema, sourceAst, nodeRef);
        if (!nodeAst)
            return;

        const AstNode& node = nodeAst->node(nodeRef);
        if (node.is(AstNodeId::Identifier))
            outIdentifiers.push_back(SemaHelpers::resolveIdentifier(sema, node.codeRef()));

        SmallVector<AstNodeRef> children;
        collectInlineAnalysisChildren(sema, sourceAst, *nodeAst, node, children);
        for (const AstNodeRef childRef : children)
            collectSourceIdentifierUses(sema, sourceAst, childRef, outIdentifiers);
    }

    void collectInlineClosureCaptureIdentifiers(Sema& sema, const Ast& sourceAst, AstNodeRef nodeRef, SmallVector<IdentifierRef>& outIdentifiers, const bool byRefOnly)
    {
        const Ast* nodeAst = resolveInlineAnalysisNodeAst(sema, sourceAst, nodeRef);
        if (!nodeAst)
            return;

        const AstNode& node = nodeAst->node(nodeRef);
        if (const auto* closureArg = node.safeCast<AstClosureArgument>())
        {
            if (!byRefOnly || closureArg->hasFlag(AstClosureArgumentFlagsE::Address))
                collectSourceIdentifierUses(sema, sourceAst, closureArg->nodeIdentifierRef, outIdentifiers);
            return;
        }

        SmallVector<AstNodeRef> children;
        collectInlineAnalysisChildren(sema, sourceAst, *nodeAst, node, children);
        for (const AstNodeRef childRef : children)
            collectInlineClosureCaptureIdentifiers(sema, sourceAst, childRef, outIdentifiers, byRefOnly);
    }

    bool inlineBindingIsCaptured(IdentifierRef idRef, const std::unordered_set<IdentifierRef>& capturedIdentifiers)
    {
        return idRef.isValid() && capturedIdentifiers.contains(idRef);
    }

    bool inlineBindingNeedsMaterialization(Sema& sema, AstNodeRef exprRef, const std::unordered_set<IdentifierRef>& localIdentifiers)
    {
        if (exprRef.isInvalid() || localIdentifiers.empty())
            return false;

        SmallVector<IdentifierRef> exprIdentifiers;
        collectIdentifierUses(sema, exprRef, exprIdentifiers);
        for (const IdentifierRef exprIdRef : exprIdentifiers)
        {
            if (localIdentifiers.contains(exprIdRef))
                return true;
        }

        return false;
    }

    bool inlineBindingHasNonCountOfUse(Sema& sema, const Ast& sourceAst, AstNodeRef nodeRef, IdentifierRef idRef, AstNodeRef parentRef = AstNodeRef::invalid())
    {
        const Ast* nodeAst = resolveInlineAnalysisNodeAst(sema, sourceAst, nodeRef);
        if (!nodeAst || !idRef.isValid())
            return false;

        const AstNode& node = nodeAst->node(nodeRef);
        if (node.is(AstNodeId::Identifier) &&
            sema.idMgr().addIdentifier(sema.ctx(), node.codeRef()) == idRef)
        {
            const Ast* parentAst = resolveInlineAnalysisNodeAst(sema, sourceAst, parentRef);
            return !parentAst || parentAst->node(parentRef).isNot(AstNodeId::CountOfExpr);
        }

        SmallVector<AstNodeRef> children;
        collectInlineAnalysisChildren(sema, sourceAst, *nodeAst, node, children);
        for (const AstNodeRef childRef : children)
        {
            if (inlineBindingHasNonCountOfUse(sema, sourceAst, childRef, idRef, nodeRef))
                return true;
        }

        return false;
    }

    bool forceMaterializeInlineVariadicBinding(const SemaClone::ParamBinding& binding, const TypeInfo& paramType, const bool hasNonCountOfUse)
    {
        if (!binding.forceMaterialize || !binding.exprRef.isValid() || !binding.typeRef.isValid())
            return false;
        if (!paramType.isAnyVariadic())
            return false;
        return hasNonCountOfUse;
    }

    uint32_t inlineBindingUseCount(Sema& sema, const Ast& sourceAst, AstNodeRef nodeRef, IdentifierRef idRef)
    {
        const Ast* nodeAst = resolveInlineAnalysisNodeAst(sema, sourceAst, nodeRef);
        if (!nodeAst || !idRef.isValid())
            return 0;

        uint32_t       count = 0;
        const AstNode& node  = nodeAst->node(nodeRef);
        if (node.is(AstNodeId::Identifier) &&
            sema.idMgr().addIdentifier(sema.ctx(), node.codeRef()) == idRef)
        {
            count += 1;
        }

        SmallVector<AstNodeRef> children;
        collectInlineAnalysisChildren(sema, sourceAst, *nodeAst, node, children);
        for (const AstNodeRef childRef : children)
            count += inlineBindingUseCount(sema, sourceAst, childRef, idRef);

        return count;
    }

    // Resolves through transparent cast/paren wrappers to decide whether an expression is
    // ultimately a direct reference to a stable storage variable (a local, parameter, or `me`).
    bool inlineBindingExprIsStableVariableRef(Sema& sema, AstNodeRef exprRef)
    {
        AstNodeRef ref = exprRef;
        for (uint32_t depth = 0; depth < 8 && ref.isValid(); ++depth)
        {
            if (const Symbol* sym = sema.viewStored(ref, SemaNodeViewPartE::Symbol).sym(); sym && sym->isVariable())
                return true;

            const AstNode& node = sema.node(ref);
            if (const auto* castNode = node.safeCast<AstCastExpr>())
            {
                ref = castNode->nodeExprRef;
                continue;
            }
            if (const auto* autoCastNode = node.safeCast<AstAutoCastExpr>())
            {
                ref = autoCastNode->nodeExprRef;
                continue;
            }
            if (const auto* parenNode = node.safeCast<AstParenExpr>())
            {
                ref = parenNode->nodeExprRef;
                continue;
            }
            break;
        }

        return false;
    }

    bool inlineBindingNeedsRepeatedRValueMaterialization(Sema& sema, const Ast& sourceAst, AstNodeRef nodeRef, const SemaClone::ParamBinding& binding)
    {
        if (!binding.exprRef.isValid() || !binding.idRef.isValid())
            return false;
        if (sema.viewConstant(binding.exprRef).hasConstant())
            return false;
        if (sema.isLValue(binding.exprRef))
            return false;

        // Aggregate parameters are passed by reference, so a value-copy materialization of the
        // argument is read back through the by-reference access convention of the inlined body
        // (a dereference). When the argument is a plain variable reference such as `me`, that is
        // both unnecessary (re-evaluating a stable storage reference is free and side effect
        // free) and incorrect (the copied value would be dereferenced as a pointer). Substitute
        // the reference directly instead of materializing a mismatched value local.
        if (binding.sourceParam)
        {
            const TypeInfo& paramType = binding.sourceParam->type(sema.ctx());
            if ((paramType.isStruct() || paramType.isArray() || paramType.isAggregate()) &&
                inlineBindingExprIsStableVariableRef(sema, binding.exprRef))
                return false;
        }

        return inlineBindingUseCount(sema, sourceAst, nodeRef, binding.idRef) > 1;
    }

    bool inlineBindingExprIsDirectStableLValue(Sema& sema, AstNodeRef exprRef)
    {
        AstNodeRef ref = exprRef;
        for (uint32_t depth = 0; depth < 8 && ref.isValid(); ++depth)
        {
            const AstNode& node = sema.node(ref);
            if (node.is(AstNodeId::Identifier))
                return true;
            if (const auto* castNode = node.safeCast<AstCastExpr>())
            {
                ref = castNode->nodeExprRef;
                continue;
            }
            if (const auto* autoCastNode = node.safeCast<AstAutoCastExpr>())
            {
                ref = autoCastNode->nodeExprRef;
                continue;
            }
            if (const auto* parenNode = node.safeCast<AstParenExpr>())
            {
                ref = parenNode->nodeExprRef;
                continue;
            }
            return false;
        }

        return false;
    }

    bool inlineBindingNeedsRepeatedLValueMaterialization(Sema& sema, const Ast& sourceAst, AstNodeRef nodeRef, const SemaClone::ParamBinding& binding)
    {
        if (!binding.exprRef.isValid() || !binding.idRef.isValid())
            return false;
        if (!sema.isLValue(binding.exprRef))
            return false;
        if (inlineBindingExprIsDirectStableLValue(sema, binding.exprRef))
            return false;
        return inlineBindingUseCount(sema, sourceAst, nodeRef, binding.idRef) > 1;
    }

    bool sourceSubtreeUsesIdentifier(Sema& sema, const Ast& sourceAst, AstNodeRef nodeRef, IdentifierRef idRef)
    {
        const Ast* nodeAst = resolveInlineAnalysisNodeAst(sema, sourceAst, nodeRef);
        if (!nodeAst || !idRef.isValid())
            return false;

        const AstNode& node = nodeAst->node(nodeRef);
        if (node.is(AstNodeId::Identifier) &&
            sema.idMgr().addIdentifier(sema.ctx(), node.codeRef()) == idRef)
        {
            return true;
        }

        SmallVector<AstNodeRef> children;
        collectInlineAnalysisChildren(sema, sourceAst, *nodeAst, node, children);
        for (const AstNodeRef childRef : children)
        {
            if (sourceSubtreeUsesIdentifier(sema, sourceAst, childRef, idRef))
                return true;
        }

        return false;
    }

    bool inlineBindingNeedsMutableMaterialization(Sema& sema, const Ast& sourceAst, AstNodeRef nodeRef, IdentifierRef idRef)
    {
        const Ast* nodeAst = resolveInlineAnalysisNodeAst(sema, sourceAst, nodeRef);
        if (!nodeAst || !idRef.isValid())
            return false;

        const AstNode& node = nodeAst->node(nodeRef);
        if (const auto* assignStmt = node.safeCast<AstAssignStmt>())
        {
            if (sourceSubtreeUsesIdentifier(sema, sourceAst, assignStmt->nodeLeftRef, idRef))
                return true;
        }

        SmallVector<AstNodeRef> children;
        collectInlineAnalysisChildren(sema, sourceAst, *nodeAst, node, children);
        for (const AstNodeRef childRef : children)
        {
            if (inlineBindingNeedsMutableMaterialization(sema, sourceAst, childRef, idRef))
                return true;
        }

        return false;
    }

    bool inlineBindingNeedsIndexOrForeachMaterialization(Sema& sema, const Ast& sourceAst, AstNodeRef nodeRef, IdentifierRef idRef, AstNodeRef parentRef = AstNodeRef::invalid())
    {
        const Ast* nodeAst = resolveInlineAnalysisNodeAst(sema, sourceAst, nodeRef);
        if (!nodeAst || !idRef.isValid())
            return false;

        const AstNode& node = nodeAst->node(nodeRef);
        if (const auto* foreachStmt = node.safeCast<AstForeachStmt>())
        {
            if (sourceSubtreeUsesIdentifier(sema, sourceAst, foreachStmt->nodeExprRef, idRef))
                return true;
        }

        if (node.is(AstNodeId::Identifier) &&
            sema.idMgr().addIdentifier(sema.ctx(), node.codeRef()) == idRef &&
            parentRef.isValid())
        {
            const Ast* parentAst = resolveInlineAnalysisNodeAst(sema, sourceAst, parentRef);
            return parentAst && parentAst->node(parentRef).is(AstNodeId::IndexExpr);
        }

        SmallVector<AstNodeRef> children;
        collectInlineAnalysisChildren(sema, sourceAst, *nodeAst, node, children);
        for (const AstNodeRef childRef : children)
        {
            if (inlineBindingNeedsIndexOrForeachMaterialization(sema, sourceAst, childRef, idRef, nodeRef))
                return true;
        }

        return false;
    }

    bool inlineBindingNeedsAddressMaterialization(Sema& sema, const Ast& sourceAst, AstNodeRef nodeRef, IdentifierRef idRef, AstNodeRef parentRef = AstNodeRef::invalid())
    {
        const Ast* nodeAst = resolveInlineAnalysisNodeAst(sema, sourceAst, nodeRef);
        if (!nodeAst || !idRef.isValid())
            return false;

        const AstNode& node = nodeAst->node(nodeRef);
        if (node.is(AstNodeId::Identifier) &&
            sema.idMgr().addIdentifier(sema.ctx(), node.codeRef()) == idRef &&
            parentRef.isValid())
        {
            const Ast* parentAst = resolveInlineAnalysisNodeAst(sema, sourceAst, parentRef);
            if (parentAst)
            {
                const AstNode& parentNode = parentAst->node(parentRef);
                if (parentNode.is(AstNodeId::UnaryExpr) && parentNode.codeRef().isValid())
                    return sema.token(parentNode.codeRef()).id == TokenId::SymAmpersand;
            }
        }

        SmallVector<AstNodeRef> children;
        collectInlineAnalysisChildren(sema, sourceAst, *nodeAst, node, children);
        for (const AstNodeRef childRef : children)
        {
            if (inlineBindingNeedsAddressMaterialization(sema, sourceAst, childRef, idRef, nodeRef))
                return true;
        }

        return false;
    }

    AstNodeRef makeInlineMaterializedTypeNode(Sema& sema, TokenRef tokRef, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return AstNodeRef::invalid();

        auto [typeNodeRef, typeNodePtr] = sema.ast().makeNode<AstNodeId::Identifier>(tokRef);
        typeNodePtr->addFlag(AstIdentifierFlagsE::GenericTypeBinding);
        sema.setType(typeNodeRef, typeRef);
        return typeNodeRef;
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

    Result materializeInlineReceiverBinding(Sema& sema, SmallVector<SemaClone::ParamBinding>& ioBindings, SmallVector<AstNodeRef>& outStatements)
    {
        const IdentifierRef meId = sema.idMgr().predefined(IdentifierManager::PredefinedName::Me);
        for (SemaClone::ParamBinding& binding : ioBindings)
        {
            if (binding.idRef != meId || !binding.exprRef.isValid() || binding.sourceParam == nullptr)
                continue;
            if (sema.viewConstant(binding.exprRef).hasConstant() || sema.isLValue(binding.exprRef))
                return Result::Continue;

            const TypeInfo& paramType = binding.sourceParam->type(sema.ctx());
            if (paramType.isCodeBlock() || paramType.isAnyVariadic())
                return Result::Continue;

            const TokenRef tokRef = materializedInlineBindingTokRef(sema, *binding.sourceParam, binding.exprRef);
            // The receiver is an already-resolved CALLER expression (e.g. `me.slab[i]`, where
            // `.slab` resolved against the caller's `me`). Materializing it into the inline body
            // prologue means a plain re-expanding clone would re-resolve its auto-members in the
            // *callee* inline frame — where the caller's `me` is gone — and stall on the `.` marker.
            // Preserve the resolved identifier symbols so the receiver stays bound to the caller.
            const SemaClone::CloneContext noBindings{std::span<const SemaClone::ParamBinding>{}};
            const AstNodeRef              clonedInitRef = SemaClone::cloneAstPreservingResolvedIdentifierSymbols(sema, binding.exprRef, noBindings);
            if (clonedInitRef.isInvalid())
                return Result::Error;

            auto [declRef, declPtr] = sema.ast().makeNode<AstNodeId::SingleVarDecl>(tokRef);
            declPtr->flags()        = AstVarDeclFlagsE::Let;
            declPtr->tokNameRef     = tokRef;
            declPtr->nodeInitRef    = clonedInitRef;

            SymbolVariable* materializedSym = makeMaterializedInlineBindingSymbol(sema, *binding.sourceParam, tokRef, *declPtr, true);
            sema.setSymbol(declRef, materializedSym);
            outStatements.push_back(declRef);

            binding.exprRef          = makeMaterializedInlineBindingUse(sema, tokRef, *materializedSym);
            binding.typeRef          = TypeRef::invalid();
            binding.forceMaterialize = false;
            return Result::Continue;
        }

        return Result::Continue;
    }

    Result materializeInlineBindings(Sema& sema, const SymbolFunction& fn, const Ast& sourceAst, const AstFunctionDecl& decl, SmallVector<SemaClone::ParamBinding>& ioBindings, SmallVector<AstNodeRef>& outStatements)
    {
        if (ioBindings.empty())
            return Result::Continue;

        SmallVector<IdentifierRef> localIdentifiers;
        collectInlineLocalIdentifiers(sema, sourceAst, decl.nodeBodyRef, localIdentifiers);
        SmallVector<IdentifierRef> capturedIdentifiers;
        collectInlineClosureCaptureIdentifiers(sema, sourceAst, decl.nodeBodyRef, capturedIdentifiers, false);
        SmallVector<IdentifierRef> capturedByRefIdentifiers;
        collectInlineClosureCaptureIdentifiers(sema, sourceAst, decl.nodeBodyRef, capturedByRefIdentifiers, true);
        const std::unordered_set<IdentifierRef> localIdentifierSet{localIdentifiers.begin(), localIdentifiers.end()};
        const std::unordered_set<IdentifierRef> capturedIdentifierSet{capturedIdentifiers.begin(), capturedIdentifiers.end()};
        const std::unordered_set<IdentifierRef> capturedByRefIdentifierSet{capturedByRefIdentifiers.begin(), capturedByRefIdentifiers.end()};

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

            const bool      bindingIsCaptured                 = inlineBindingIsCaptured(binding.idRef, capturedIdentifierSet);
            const bool      bindingNeedsMaterialization       = inlineBindingNeedsMaterialization(sema, binding.exprRef, localIdentifierSet);
            const TypeInfo& paramType                         = param->type(sema.ctx());
            const bool      forceExplicitMaterialization      = !bindingIsCaptured && binding.forceMaterialize && !paramType.isAnyVariadic();
            const bool      forceRuntimeSafetyMaterialization = !bindingIsCaptured &&
                                                           !fn.attributes().runtimeSafetyOverrides.empty() &&
                                                           !paramType.isCodeBlock() &&
                                                           !paramType.isReference() &&
                                                           !paramType.isAnyVariadic();
            const bool hasNonCountOfUse                   = inlineBindingHasNonCountOfUse(sema, sourceAst, decl.nodeBodyRef, binding.idRef);
            const bool forceVariadicMaterialization       = !bindingIsCaptured && forceMaterializeInlineVariadicBinding(binding, paramType, hasNonCountOfUse);
            const bool canInlineReferenceBindingDirectly  = paramType.isReference() && inlineBindingExprIsDirectStableLValue(sema, binding.exprRef);
            const bool forceIndexOrForeachMaterialization = !bindingIsCaptured &&
                                                            !canInlineReferenceBindingDirectly &&
                                                            inlineBindingNeedsIndexOrForeachMaterialization(sema, sourceAst, decl.nodeBodyRef, binding.idRef);
            const bool bindingHasAddressUse        = inlineBindingNeedsAddressMaterialization(sema, sourceAst, decl.nodeBodyRef, binding.idRef);
            const bool forceAddressMaterialization = !bindingIsCaptured && bindingHasAddressUse &&
                                                     (!paramType.isReference() || !sema.isLValue(binding.exprRef));
            const bool forceRepeatedRValueMaterialization = !bindingIsCaptured &&
                                                            inlineBindingNeedsRepeatedRValueMaterialization(sema, sourceAst, decl.nodeBodyRef, binding);
            const bool forceRepeatedLValueMaterialization = !bindingIsCaptured &&
                                                            inlineBindingNeedsRepeatedLValueMaterialization(sema, sourceAst, decl.nodeBodyRef, binding);
            const bool bindingNeedsMutableMaterialization = inlineBindingNeedsMutableMaterialization(sema, sourceAst, decl.nodeBodyRef, binding.idRef);
            const bool forceBindingMaterialization        = forceExplicitMaterialization ||
                                                     forceRuntimeSafetyMaterialization ||
                                                     forceVariadicMaterialization ||
                                                     forceIndexOrForeachMaterialization ||
                                                     forceAddressMaterialization ||
                                                     forceRepeatedRValueMaterialization ||
                                                     forceRepeatedLValueMaterialization;
            if (paramType.isCodeBlock() || (paramType.isAnyVariadic() && !forceBindingMaterialization && !bindingIsCaptured && !bindingNeedsMaterialization))
            {
                remainingBindings.push_back(binding);
                continue;
            }

            if (!forceBindingMaterialization && !bindingIsCaptured && !bindingNeedsMaterialization)
            {
                remainingBindings.push_back(binding);
                continue;
            }

            const TokenRef paramNameRef = materializedInlineBindingTokRef(sema, *param, binding.exprRef);

            AstNodeRef clonedInitRef = SemaClone::cloneDetachedExpr(sema, binding.exprRef);
            if (clonedInitRef.isInvalid())
                return Result::Error;

            auto [declRef, declPtr]      = sema.ast().makeNode<AstNodeId::SingleVarDecl>(paramNameRef);
            const bool materializedAsLet = !forceRuntimeSafetyMaterialization &&
                                           !bindingNeedsMutableMaterialization &&
                                           !inlineBindingIsCaptured(binding.idRef, capturedByRefIdentifierSet);
            declPtr->flags()    = materializedAsLet ? AstVarDeclFlagsE::Let : AstVarDeclFlagsE::Zero;
            declPtr->tokNameRef = paramNameRef;
            if (forceAddressMaterialization && paramType.isReference())
            {
                declPtr->nodeTypeRef = makeInlineMaterializedTypeNode(sema, paramNameRef, paramType.payloadTypeRef());
            }
            else if (!paramType.isAnyVariadic() && (forceRuntimeSafetyMaterialization || isInlineCoercibleLiteralArg(sema.node(binding.exprRef)) || SemaHelpers::canUseContextualBinding(sema, binding.exprRef)))
            {
                AstNodeRef materializedTypeRef = AstNodeRef::invalid();
                if (const auto* paramDecl = param->decl()->safeCast<AstSingleVarDecl>())
                {
                    const SemaClone::CloneContext noBindingsSource{std::span<const SemaClone::ParamBinding>{}, std::span<const SemaClone::NodeReplacement>{}, false, &sourceAst};
                    materializedTypeRef = SemaClone::cloneAst(sema, paramDecl->nodeTypeRef, noBindingsSource);
                }
                if (materializedTypeRef.isInvalid())
                    clonedInitRef = Cast::createCastNode(sema, param->typeRef(), clonedInitRef);
                else
                    declPtr->nodeTypeRef = materializedTypeRef;
            }
            declPtr->nodeInitRef            = clonedInitRef;
            SymbolVariable* materializedSym = makeMaterializedInlineBindingSymbol(sema, *param, paramNameRef, *declPtr, materializedAsLet);
            sema.setSymbol(declRef, materializedSym);
            outStatements.push_back(declRef);

            binding.exprRef            = makeMaterializedInlineBindingUse(sema, paramNameRef, *materializedSym);
            binding.preserveUseCodeRef = forceRuntimeSafetyMaterialization;
            if (!forceVariadicMaterialization)
                binding.typeRef = TypeRef::invalid();
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

    void setInlinePayloadRecursive(Sema& sema, AstNodeRef nodeRef, SemaInlinePayload* inlinePayload)
    {
        if (nodeRef.isInvalid())
            return;

        sema.setInlinePayload(nodeRef, inlinePayload);

        SmallVector<AstNodeRef> children;
        sema.node(nodeRef).collectChildrenFromAst(children, sema.ast());
        for (const AstNodeRef childRef : children)
            setInlinePayloadRecursive(sema, childRef, inlinePayload);
    }

    void collectInlineLocalFunctionDecls(Sema& sema, AstNodeRef nodeRef, SmallVector<AstNodeRef>& outFunctionRefs)
    {
        if (nodeRef.isInvalid())
            return;

        const AstNode& node = sema.node(nodeRef);
        if (node.is(AstNodeId::FunctionDecl))
        {
            outFunctionRefs.push_back(nodeRef);
            return;
        }

        if (node.is(AstNodeId::FunctionExpr) || node.is(AstNodeId::ClosureExpr))
            return;

        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, sema.ast());
        for (const AstNodeRef childRef : children)
            collectInlineLocalFunctionDecls(sema, childRef, outFunctionRefs);
    }

    Result predeclareInlineLocalFunctions(Sema& sema, AstNodeRef inlineRootRef, SemaInlinePayload& inlinePayload)
    {
        if (inlineRootRef.isInvalid())
            return Result::Continue;

        SmallVector<AstNodeRef> functionRefs;
        collectInlineLocalFunctionDecls(sema, inlineRootRef, functionRefs);
        for (const AstNodeRef childRef : functionRefs)
        {
            const auto* functionDecl = sema.node(childRef).safeCast<AstFunctionDecl>();
            if (!functionDecl)
                continue;

            if (const auto* existingPayload = sema.inlinePayload(childRef))
                SWC_ASSERT(existingPayload == &inlinePayload);
            else
                sema.setInlinePayload(childRef, &inlinePayload);

            if (!sema.viewSymbol(childRef).hasSymbol())
            {
                Sema         declSema(sema.ctx(), sema, childRef, true);
                const Result declResult = declSema.execResult();
                if (declResult != Result::Continue)
                    return declResult;
            }

            if (Symbol* sym = sema.viewSymbol(childRef).sym())
            {
                SemaHelpers::ensureCurrentLocalScopeSymbol(sema, sym);
                if (!sym->isDeclared())
                {
                    sym->registerAttributes(sema);
                    sym->setDeclared(sema.ctx());
                }

                // Mark local functions inside inline macro expansions so the native backend
                // assigns them a unique private symbol name instead of a shared public API
                // name. Without this, the same macro expanded at multiple call sites in
                // different translation units produces functions with identical public
                // symbol names, causing multiply-defined-symbol linker errors.
                if (sym->isFunction())
                    sym->cast<SymbolFunction>().addExtraFlag(SymbolFunctionFlagsE::InlineLocalFunction);
            }

            SWC_RESULT(sema.prepareFunctionSignature(childRef));
        }

        return Result::Continue;
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

    Result createVariadicInlineExpression(Sema& sema, AstNodeRef callRef, InlineVariadicBinding& variadicBinding, AstNodeRef& outExprRef, TypeRef& outExprTypeRef)
    {
        outExprRef                      = AstNodeRef::invalid();
        outExprTypeRef                  = TypeRef::invalid();
        variadicBinding.allArgsConstant = false;
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
        if (!variadicBinding.untypedVariadic && variadicBinding.argRefs.size() == 1)
        {
            const AstNodeRef argRef = bindingValueArgumentRef(sema, variadicBinding.argRefs.front());
            if (argRef.isInvalid())
                return Result::Continue;

            const TypeRef argTypeRef = sema.viewType(argRef).typeRef();
            if (argTypeRef.isValid())
            {
                const TypeInfo& argType = sema.typeMgr().get(argTypeRef);
                if (argType.isTypedVariadic() && argType.payloadTypeRef() == targetElemTypeRef)
                {
                    // Preserve resolved symbols so the code gen can resolve the caller variable
                    // directly instead of relying on the implicit-cast substitute chain, which
                    // can cycle when copyImplicitCastSubstitute wraps the identifier back in itself.
                    outExprRef = SemaClone::cloneAstPreservingResolvedIdentifierSymbols(sema, argRef, noBindings);
                    if (outExprRef.isInvalid())
                        return Result::Continue;
                    outExprTypeRef = argTypeRef;
                    return Result::Continue;
                }
            }
        }

        SmallVector<AstNodeRef> clonedValues;
        clonedValues.reserve(variadicBinding.argRefs.size());

        for (const AstNodeRef rawArgRef : variadicBinding.argRefs)
        {
            AstNodeRef argRef = bindingValueArgumentRef(sema, rawArgRef);
            if (argRef.isInvalid())
                return Result::Continue;
            variadicBinding.allArgsConstant = (clonedValues.empty() ? true : variadicBinding.allArgsConstant) && sema.viewConstant(argRef).hasConstant();

            AstNodeRef clonedArgRef = SemaClone::cloneAst(sema, argRef, noBindings);
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
                assignInlineBindingExpr(sema, bound[0], *params[0], ufcsRef);
                // UFCS receivers are consumed through implicit `.member` accesses, so clone-time
                // identifier scans cannot see every use of `me`. Non-lvalue temporaries therefore
                // need a concrete local up front to avoid re-evaluating the receiver expression.
                bound[0].forceMaterialize = !sema.viewConstant(ufcsRef).hasConstant() && !sema.isLValue(ufcsRef);
                nextParam                 = 1;
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
            if (!fn.tryGetParameterIndexByName(paramIndex, idRef))
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

            assignInlineBindingExpr(sema, bound[paramIndex], *params[paramIndex], argValueRef);
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
                const size_t trailingParamIndex = numFixed - 1;
                assignInlineBindingExpr(sema, bound[trailingParamIndex], *params[trailingParamIndex], bindingInlineArgumentRef(sema, context, *params[trailingParamIndex], trailingParamIndex, numFixed, argRef, sourceArgRef));
                continue;
            }

            while (nextParam < numFixed && isBindingAssigned(bound[nextParam]))
                nextParam++;

            AstNodeRef argValueRef = nextParam < numFixed ? bindingInlineArgumentRef(sema, context, *params[nextParam], nextParam, numFixed, argRef, sourceArgRef) : bindingValueArgumentRef(sema, argRef);
            if (nextParam < numFixed)
            {
                assignInlineBindingExpr(sema, bound[nextParam], *params[nextParam], argValueRef);
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
                    assignInlineBindingExpr(sema, bound[i], *param, defaultRef);
                }
            }

            if (bound[i].idRef.isValid())
                outBindings.push_back(bound[i]);
        }

        outMapped = true;
        return Result::Continue;
    }

    // Auto-inline budget: a candidate body wider than this many source tokens is left out of
    // line. Tokens are a cheap, stable proxy for body size (no AST walk).
    constexpr uint32_t K_AUTO_INLINE_MAX_BODY_TOKENS = 80;

    // Auto mode candidate selection. Beyond canInlineCall's structural guards:
    //  - skip generics (cross-Ast generic inlining re-binds generic params in the caller, not
    //    handled here);
    //  - only volunteer SAME-Ast callees: a cross-module callee's Ast is owned by another,
    //    possibly concurrently running, compilation job, so reading its node/paged stores from
    //    this thread is unsafe. Marked cross-module functions still inline through
    //    tryInlineCall's explicit cross-Ast path;
    //  - bound the body size to keep code growth in check.
    // Body shape is otherwise unrestricted: correct materialization (preserved resolved symbols
    // + inline-scope isolation) handles arbitrary statements/locals/calls.
    // An aggregate/by-value-struct type whose inline materialization is not yet reliable
    // (struct-typed constant payloads, the `retval` placeholder of a struct-returning callee,
    // by-value aggregate parameters). Auto-inline restricts itself to scalar/pointer signatures
    // to stay clear of these until the codegen materialization handles moved aggregates.
    bool isInlineAggregateType(const TypeInfo& ti)
    {
        return ti.isStruct() || ti.isArray() || ti.isAggregateStruct() || ti.isAggregateArray() ||
               ti.isAny() || ti.isInterface() || ti.isString() || ti.isSlice();
    }

    // `#offsetof(local)` yields the byte offset of a local within its function's stack frame.
    // That value is frame-relative: inlining materializes the callee's locals into the caller's
    // frame (after the caller's own locals), so every offset shifts by the caller prefix. The
    // relative layout is preserved but the absolute base is not, so a body that takes `#offsetof`
    // of one of its locals cannot be auto-inlined without changing its observable result. (Struct
    // `#offsetof` is layout-invariant, but distinguishing the operand needs full resolution; a
    // body using `#offsetof` at all is rare enough that the conservative gate costs nothing.)
    bool bodyUsesCompilerOffsetOf(Sema& sema, const Ast& ast, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return false;
        const AstNode& node = ast.node(nodeRef);
        if (node.is(AstNodeId::CompilerCallOne) && sema.token(node.codeRef()).id == TokenId::CompilerOffsetOf)
            return true;
        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, ast);
        for (const AstNodeRef childRef : children)
            if (bodyUsesCompilerOffsetOf(sema, ast, childRef))
                return true;
        return false;
    }

    bool shouldAutoInline(Sema& sema, const SymbolFunction& fn)
    {
        if (fn.isGenericRoot() || fn.isGenericInstance())
            return false;
        if (!fn.isSemaCompleted())
            return false;

        // A typed variadic (`T...`) callee packs its trailing call-site args into a typed slice.
        // Auto-inlining it materializes that packing into the caller and drops the per-argument
        // coercion (e.g. a `null` arg to a `*void...` is no longer coerced to `*void`, leaving an
        // un-lowerable `null`-typed constant tuple element). Explicit #[Inline]/macro/mixin callees
        // opt into this deliberately and keep working; the auto heuristic must not volunteer it.
        if (fn.hasVariadicParam())
        {
            const auto& params = fn.parameters();
            if (!params.empty() && params.back()->type(sema.ctx()).isAnyVariadic())
                return false;
        }

        // Inlining a throwable callee requires materializing its error-propagation ABI at the
        // call site. Routing an inlined `throw` to an enclosing `assume` is not yet wired in
        // codegen — it crashes even for an explicit #[Inline] throwable callee under `assume` —
        // so the auto heuristic must not volunteer throwable callees until that lands. (`try` /
        // `catch` routing of an inlined throw already works; only the `assume` panic path does
        // not, but the gate stays at the callee granularity for safety.)
        if (fn.isThrowable())
            return false;

        // Scalar/pointer signature only — see isInlineAggregateType.
        if (fn.returnTypeRef().isValid() && isInlineAggregateType(sema.ctx().typeMgr().get(fn.returnTypeRef())))
            return false;
        for (const SymbolVariable* param : fn.parameters())
        {
            if (!param)
                continue;
            const TypeInfo& paramType = param->type(sema.ctx());
            if (isInlineAggregateType(paramType))
                return false;
            // A reference parameter to an aggregate (e.g. `const &{x, y}`) is excluded for the same
            // reason its by-value form is: the aggregate is not a scalar/pointer the auto-inline clone
            // can carry faithfully. For an ANONYMOUS aggregate this is also unsafe under concurrency —
            // the clone re-resolves a member access (`param.x`) by name against that ephemeral tuple
            // type, whose member-symbol map may not yet be published on the thread doing the inline,
            // intermittently yielding a spurious "unknown symbol". Look through the reference and
            // apply the same scalar/pointer-only boundary to the pointee.
            if (paramType.isReference() && paramType.payloadTypeRef().isValid() &&
                isInlineAggregateType(sema.ctx().typeMgr().get(paramType.payloadTypeRef())))
                return false;
        }

        const AstFunctionDecl* decl    = nullptr;
        const Ast*             declAst = nullptr;
        if (!resolveFunctionDecl(sema, fn, decl, declAst))
            return false;
        if (declAst != &sema.ast())
            return false;
        if (decl->nodeBodyRef.isInvalid())
            return false;

        // Exclude bodies containing constructs whose materialization is not yet reproduced
        // faithfully when moved into the caller (any nested call — see bodyHasNestedCallExpr — and
        // nested local functions that re-bind their outer-scope access). Preserving resolved
        // identifier symbols (above) already lets a body reference the callee's file-private
        // globals/helpers safely; this guard keeps the remaining, not-yet-handled re-resolution
        // cases out of line. Leaf computational callees (member access, indexing, arithmetic,
        // casts, assignments, control flow over params/`me`/locals/globals) still inline.
        if (bodyHasNestedCallExpr(*declAst, decl->nodeBodyRef))
            return false;
        if (bodyUsesCompilerOffsetOf(sema, *declAst, decl->nodeBodyRef))
            return false;
        SmallVector<AstNodeRef> localFns;
        collectInlineLocalFunctionDecls(sema, decl->nodeBodyRef, localFns);
        if (!localFns.empty())
            return false;

        const AstNode& body     = declAst->node(decl->nodeBodyRef);
        const TokenRef startTok = body.tokRef();
        const TokenRef endTok   = body.tokRefEnd(*declAst);
        if (startTok.isInvalid() || endTok.isInvalid() || endTok.get() < startTok.get())
            return false;

        const uint32_t tokenSpan = endTok.get() - startTok.get();
        return tokenSpan <= K_AUTO_INLINE_MAX_BODY_TOKENS;
    }

    bool isDynamicInterfaceDispatchCall(Sema& sema, const SymbolFunction& fn, AstNodeRef ufcsArg, std::span<const ResolvedCallArgument> resolvedArgs)
    {
        if (!fn.hasInterfaceMethodSlot())
            return false;

        if (ufcsArg.isValid())
        {
            const SemaNodeView receiverView = sema.viewType(ufcsArg);
            if (receiverView.type() && receiverView.type()->isInterface())
                return true;
        }

        for (const ResolvedCallArgument& arg : resolvedArgs)
            if (arg.passKind == CallArgumentPassKind::InterfaceObject)
                return true;

        return false;
    }

}

bool SemaInline::canInlineCall(Sema& sema, const SymbolFunction& fn)
{
    // Structural guards that hold in every inline mode.
    if (fn.isClosure() || fn.isEmpty() || fn.isForeign())
        return false;
    if (fn.attributes().hasRtFlag(RtAttributeFlagsE::NoInline))
        return false;

    // An untyped (`...`) variadic callee can never be inlined in any mode: there is no materialized
    // arg pack. (A TYPED `T...` variadic is fine for macros/mixins and explicit #[Inline], and is
    // gated out of the AUTO heuristic separately in shouldAutoInline.)
    if (fn.hasVariadicParam())
    {
        const auto& params = fn.parameters();
        if (!params.empty() && params.back()->type(sema.ctx()).isVariadic())
            return false;
    }

    const AttributeList& attributes = fn.attributes();

    // Macros and mixins are not ordinary functions: they must always be expanded, regardless
    // of the inline mode.
    if (attributes.hasRtFlag(RtAttributeFlagsE::Macro) || attributes.hasRtFlag(RtAttributeFlagsE::Mixin))
        return true;

    const Runtime::BuildCfgBackendInlineMode mode = sema.buildCfgBackend().inlineMode;
    if (mode == Runtime::BuildCfgBackendInlineMode::Never)
        return false;

    // Explicitly tagged functions inline in both MarkedOnly and Auto.
    if (attributes.hasRtFlag(RtAttributeFlagsE::Inline))
        return true;

    // Auto additionally lets the compiler pick small, cheap callees.
    if (mode == Runtime::BuildCfgBackendInlineMode::Auto)
        return shouldAutoInline(sema, fn);

    return false;
}

Result SemaInline::tryInlineCall(Sema& sema, AstNodeRef callRef, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, std::span<AstNodeRef> sourceArgs)
{
    if (sema.hasSubstitute(callRef))
        return Result::Continue;
    if (isInlineRecursion(sema, fn))
        return Result::Continue;
    if (!canInlineCall(sema, fn))
        return Result::Continue;

    SmallVector<ResolvedCallArgument> resolvedArgs;
    sema.appendResolvedCallArguments(callRef, resolvedArgs);
    if (isDynamicInterfaceDispatchCall(sema, fn, ufcsArg, resolvedArgs.span()))
        return Result::Continue;

    const AstFunctionDecl* decl    = nullptr;
    const Ast*             declAst = nullptr;
    if (!resolveFunctionDecl(sema, fn, decl, declAst))
        return Result::Continue;
    SWC_ASSERT(declAst != nullptr);

    const bool isMacro          = fn.attributes().hasRtFlag(RtAttributeFlagsE::Macro);
    const bool isMixin          = fn.attributes().hasRtFlag(RtAttributeFlagsE::Mixin);
    const bool isCrossAstInline = declAst != &sema.ast();

    // An "ordinary" inline is any inline that is not a macro/mixin expansion: an explicit
    // #[Inline] callee or an auto-selected one. Macros/mixins keep their established re-resolving
    // materialization; ordinary inlines use the hardened (preserved-resolved-symbol) path.
    const bool isOrdinaryInline = !isMacro && !isMixin;

    // Auto-selected = inlined purely by the size/shape heuristic, not by an explicit #[Inline]
    // tag, macro or mixin. Auto candidates opt into the hardened same-Ast materialization
    // (callee-completion wait, preserved resolved symbols, isolated inline scope). Marked /
    // macro / mixin inlines keep their established behavior to avoid any regression.
    const bool isAutoSelected = isOrdinaryInline &&
                                !fn.attributes().hasRtFlag(RtAttributeFlagsE::Inline) &&
                                sema.buildCfgBackend().inlineMode == Runtime::BuildCfgBackendInlineMode::Auto;

    // A cross-Ast (cross-file) inline materializes the callee's body into the caller's Ast.
    // Regular inline relies on the body's identifiers already carrying their resolved symbols
    // so cloning can preserve them (PreResolvedSymbol) instead of re-resolving by name in the
    // caller's scope (which can't see the callee's file/module-private symbols, picks wrong
    // overloads, and trips shadowing). That resolution only exists once the callee has been
    // sema-completed, so wait for it before proceeding.
    // Generic functions instantiated cross-Ast still re-bind their generic parameters and
    // intrinsic argument matching in the caller's Ast, which isn't handled yet; keep them on
    // the previous (no cross-Ast inline) path. The hot inline accessors are non-generic.
    if (isCrossAstInline && isOrdinaryInline && (fn.isGenericInstance() || fn.isGenericRoot()))
        return Result::Continue;
    if (isCrossAstInline && isOrdinaryInline && bodyHasNestedCallExpr(*declAst, decl->nodeBodyRef))
        return Result::Continue;

    // Wait for the callee to be sema-completed before materializing its body. A cross-Ast inline
    // needs this so its identifiers carry resolved symbols (they cannot be re-resolved by name in
    // another file); an auto-selected same-Ast inline that pins resolved symbols needs it for the
    // same reason — a not-yet-resolved reference (e.g. a file-scope const used in the body) would
    // otherwise be cloned with nothing to pin and fail to re-resolve. Self-recursive callees are
    // already filtered out above, so this does not wait on the function being expanded.
    if ((isCrossAstInline || isAutoSelected) && isOrdinaryInline)
        SWC_RESULT(sema.waitSemaCompleted(&fn, sema.node(callRef).codeRef()));

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
        return Result::Continue;

    if (isCrossAstInline || isMacro || isMixin)
        appendGenericInstanceBindings(sema, fn, bindings);

    for (const SemaClone::ParamBinding& binding : bindings)
    {
        if (shouldValidateInlineBindingOuterScope(sema, binding, isMacro || isMixin))
            SWC_RESULT(validateInlineBindingOuterScopeVariables(sema, binding.exprRef));
    }

    AliasIdentifierArray aliasIdentifiers = {};
    SWC_RESULT(collectAliasIdentifiers(sema, callRef, *declAst, *decl, aliasIdentifiers));

    AstNodeRef variadicExprRef     = AstNodeRef::invalid();
    TypeRef    variadicExprTypeRef = TypeRef::invalid();
    SWC_RESULT(createVariadicInlineExpression(sema, callRef, variadicBinding, variadicExprRef, variadicExprTypeRef));
    if (variadicBinding.param)
    {
        if (variadicExprRef.isInvalid() || variadicExprTypeRef.isInvalid())
            return Result::Continue;
        if (variadicBinding.param->idRef().isValid())
            bindings.push_back({variadicBinding.param->idRef(), variadicExprRef, variadicExprTypeRef, ConstantRef::invalid(), variadicBinding.allArgsConstant});
    }

    TypeRef returnTypeRef = fn.returnTypeRef();
    if (!returnTypeRef.isValid())
        returnTypeRef = sema.typeMgr().typeVoid();

    SWC_RESULT(waitInlineResultTypeIfNeeded(sema, callRef, returnTypeRef));

    SmallVector<AstNodeRef> materializedBindings;
    materializedBindings.clear();
    SWC_RESULT(materializeInlineReceiverBinding(sema, bindings, materializedBindings));
    // Inline functions, mixins, and macros all substitute runtime bindings into the caller body.
    // Closure captures and non-addressable aggregate uses still need concrete locals before
    // cloning, while #code parameters are explicitly skipped inside materializeInlineBindings.
    SWC_RESULT(materializeInlineBindings(sema, fn, *declAst, *decl, bindings, materializedBindings));
    SemaClone::CloneContext cloneContext{bindings.span(), std::span<const SemaClone::NodeReplacement>{}, false, declAst};
    // An auto-selected inline body resolves in the callee's context: pin its already-resolved
    // identifier symbols so a same-Ast inline does not re-resolve the callee's file-private
    // references by name in the caller. Marked / macro / mixin inlines keep their established
    // (re-resolving) behavior to avoid regressing intrinsic-argument and overload handling.
    cloneContext.preserveResolvedSymbols = isAutoSelected;
    const AstNodeRef inlineRootRef       = isMixin ? mixinBodyRef(sema, *decl, cloneContext, materializedBindings.span()) : inlineBodyRef(sema, *decl, cloneContext, materializedBindings.span());
    if (inlineRootRef.isInvalid())
        return Result::Continue;
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
    inlinePayload->callerImpl          = sema.frame().currentImpl();
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

    setInlinePayloadRecursive(sema, inlineRootRef, inlinePayload);

    // Lookup-scope overrides are expression-local. A fresh inline body must start from
    // its own lexical scope so nested macro locals do not inherit a caller #inject scope.
    frame.setLookupScope(nullptr);
    frame.setLookupScopeOverrideNodes(nullptr);

    if (returnTypeRef != sema.typeMgr().typeVoid())
        frame.pushBindingType(returnTypeRef);
    frame.setCurrentInlinePayload(inlinePayload);
    frame.setInlineContextRootRef(inlineRootRef);
    if (isOrdinaryInline)
    {
        const auto callerSafetyOverrides = frame.currentAttributes().runtimeSafetyOverrides;
        frame.currentAttributes()        = fn.attributes();
        // Inlining is transparent to the call site's disabled safety guards: a guard turned OFF at
        // the call site (e.g. an `#[Swag.Safety(.Overflow, false)]` caller) must stay off in the
        // materialized body, otherwise an inlined helper re-introduces overflow/bound checks the
        // caller deliberately suppressed for its own argument expressions (e.g. CityHash's wrapping
        // `fetch(...) * C1` once `Math.ror` is inlined into it). Re-apply the caller's disable
        // overrides on top of the callee attributes — the union of disabled guards. The callee's
        // own deliberate disables are preserved untouched; enables are not propagated so a wrapping
        // callee body never starts trapping when inlined into a safety-on caller.
        for (const auto& ov : callerSafetyOverrides)
            if (!ov.value)
                frame.currentAttributes().runtimeSafetyOverrides.push_back(ov);
        frame.setCurrentImpl(fn.declImplContext());
        frame.setCurrentInterface(fn.declInterfaceContext());
    }
    if (isMacro || isMixin)
    {
        if (SymbolVariable* receiver = receiverBinding(sema, fn))
        {
            if (SymbolVariable* materializedReceiver = materializedReceiverBinding(sema, *receiver, bindings.span()))
                frame.pushBindingVar(materializedReceiver);
            else
                frame.pushBindingVar(receiver);
        }
    }

    const bool needsOwnerScope = isMacro;
    SemaScope* ownerScope      = nullptr;
    if (needsOwnerScope)
    {
        ownerScope = sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local, inlineRootRef);
        if (fn.ownerSymMap())
            ownerScope->setSymMap(const_cast<SymbolMap*>(fn.ownerSymMap()));
        ownerScope->setLookupParent(callerScope);
    }

    inlinePayload->upLookupScope = ownerScope ? ownerScope : callerScope;
    if (isMacro)
        frame.setUpLookupScope(inlinePayload->upLookupScope);
    sema.pushFramePopOnPostNode(frame, inlineRootRef);
    if (!isMixin)
    {
        if (needsOwnerScope)
        {
            SemaScope* inlineScope = sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local, inlineRootRef);
            inlineScope->setSymMap(const_cast<SymbolFunction*>(&fn));
            inlineScope->setLookupParent(ownerScope);
        }
        else
        {
            SemaScope* inlineScope = sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local, inlineRootRef);

            // An inline body is its own function body materialized at the caller site. Keep the
            // caller lookup chain reachable for nested inline expressions, but bind declarations
            // in the cloned body to the callee function so local names do not collide with caller
            // parameters at the same lookup priority.
            inlineScope->setSymMap(const_cast<SymbolFunction*>(&fn));
        }
    }

    SWC_RESULT(predeclareInlineLocalFunctions(sema, inlineRootRef, *inlinePayload));

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
    sema.restartCurrentNode(inlineRootRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
