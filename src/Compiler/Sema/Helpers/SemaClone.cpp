#include "pch.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Loop.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaAstLookup.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Helpers/SemaReexpandExpr.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Support/Core/PointerSet.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    const SemaClone::CloneContext& cloneContextAsInline(const CloneContext& cloneContext)
    {
        return static_cast<const SemaClone::CloneContext&>(cloneContext); // NOLINT(cppcoreguidelines-pro-type-static-cast-downcast)
    }

    const Ast& cloneSourceAst(Sema& sema, const SemaClone::CloneContext& cloneContext)
    {
        return cloneContext.sourceAst ? *cloneContext.sourceAst : sema.ast();
    }

    void inheritCloneContextOptions(SemaClone::CloneContext& outContext, const SemaClone::CloneContext& sourceContext)
    {
        outContext.preserveResolvedSymbols              = sourceContext.preserveResolvedSymbols;
        outContext.resolveBindingExprWithParentBindings = sourceContext.resolveBindingExprWithParentBindings;
        outContext.suppressedImplicitCastSubstituteRef  = sourceContext.suppressedImplicitCastSubstituteRef;
        outContext.nestedCallableDepth                  = sourceContext.nestedCallableDepth;
    }

    const Ast* resolveCloneNodeAst(Sema& sema, AstNodeRef nodeRef, const SemaClone::CloneContext& cloneContext)
    {
        if (nodeRef.isInvalid())
            return nullptr;

        const Ast& sourceAst = cloneSourceAst(sema, cloneContext);
        return SemaAstLookup::resolveValidNodeAst(sema, sourceAst, nodeRef);
    }

    const SourceView* resolveCloneSourceView(Sema& sema, const Ast& sourceAst, const AstNode& node)
    {
        if (sema.compiler().hasSourceView(node.srcViewRef()))
            return &sema.srcView(node.srcViewRef());
        if (sourceAst.hasSourceView())
            return &sourceAst.srcView();
        return nullptr;
    }

    const Ast* resolveCloneSpanAst(Sema& sema, SpanRef spanRef, const SemaClone::CloneContext& cloneContext)
    {
        if (spanRef.isInvalid())
            return nullptr;

        const Ast& sourceAst = cloneSourceAst(sema, cloneContext);
        return SemaAstLookup::resolveValidSpanAst(sema, sourceAst, spanRef);
    }

    bool canReadSourcePayload(Sema& sema, const SemaClone::CloneContext& cloneContext)
    {
        return &cloneSourceAst(sema, cloneContext) == &sema.ast();
    }

    bool hasStoredFlag(const NodePayload::StoredView& view, NodePayloadFlags flag)
    {
        return (static_cast<uint16_t>(view.flags) & static_cast<uint16_t>(flag)) != 0;
    }

    bool isNonParameterVariableDecl(const Symbol& symbol)
    {
        const AstNode* decl = symbol.decl();
        if (!decl)
            return false;

        if (const auto* singleVar = decl->safeCast<AstSingleVarDecl>())
            return !singleVar->hasFlag(AstVarDeclFlagsE::Parameter);
        if (const auto* multiVar = decl->safeCast<AstMultiVarDecl>())
            return !multiVar->hasFlag(AstVarDeclFlagsE::Parameter);
        return decl->is(AstNodeId::VarDeclDestructuring) ||
               decl->is(AstNodeId::ForStmt) ||
               decl->is(AstNodeId::ForeachStmt) ||
               decl->is(AstNodeId::SwitchCaseStmt);
    }

    bool containsAutoMemberAccess(Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid() || !sema.ast().hasNode(nodeRef))
            return false;

        const AstNode& node = sema.node(nodeRef);
        if (node.is(AstNodeId::AutoMemberAccessExpr))
            return true;

        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, sema.ast());
        for (const AstNodeRef childRef : children)
        {
            if (containsAutoMemberAccess(sema, childRef))
                return true;
        }

        return false;
    }

    NodePayload::StoredView currentStoredView(Sema& sema, AstNodeRef sourceRef)
    {
        NodePayload::StoredView view;
        const SemaNodeView      storedView = sema.viewStored(sourceRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant | SemaNodeViewPartE::Symbol);
        view.typeRef                       = storedView.typeRef();
        view.cstRef                        = storedView.cstRef();
        view.sym                           = storedView.sym();
        view.hasSymbol                     = storedView.hasSymbol();
        view.hasSymbolList                 = storedView.hasSymbolList();
        if (view.hasSymbolList)
            view.symList = {const_cast<const Symbol**>(storedView.symList().data()), storedView.symList().size()};

        uint16_t flags = 0;
        if (sema.isValueStored(sourceRef))
            flags = static_cast<uint16_t>(flags | static_cast<uint16_t>(NodePayloadFlags::Value));
        if (sema.isLValueStored(sourceRef))
            flags = static_cast<uint16_t>(flags | static_cast<uint16_t>(NodePayloadFlags::LValue));
        if (sema.isFoldedTypedConstStored(sourceRef))
            flags = static_cast<uint16_t>(flags | static_cast<uint16_t>(NodePayloadFlags::FoldedTypedConst));
        view.flags = static_cast<NodePayloadFlags>(flags);
        return view;
    }

    void inheritStoredPayload(Sema& sema, AstNodeRef clonedRef, AstNodeRef sourceRef)
    {
        // Keep the source node's original semantic payload without importing a
        // Substitute target that still belongs to the uncloned source expression.
        const NodePayload::StoredView storedView = currentStoredView(sema, sourceRef);
        if (storedView.hasSymbolList)
            sema.setSymbolList(clonedRef, storedView.symList);
        else if (storedView.hasSymbol)
            sema.setSymbol(clonedRef, storedView.sym);
        else if (storedView.cstRef.isValid())
            sema.setConstant(clonedRef, storedView.cstRef);
        else if (storedView.typeRef.isValid())
            sema.setType(clonedRef, storedView.typeRef);

        if (hasStoredFlag(storedView, NodePayloadFlags::Value))
            sema.setIsValue(clonedRef);
        if (hasStoredFlag(storedView, NodePayloadFlags::LValue))
            sema.setIsLValue(clonedRef);
        if (hasStoredFlag(storedView, NodePayloadFlags::FoldedTypedConst))
            sema.setFoldedTypedConst(clonedRef);
    }

    void inheritStoredPayloadUnderSubstitute(Sema& sema, AstNodeRef clonedRef, AstNodeRef sourceRef)
    {
        const AstNodeRef substituteRef = sema.resolvedNodeRef(clonedRef);
        SWC_ASSERT(substituteRef.isValid() && substituteRef != clonedRef);
        inheritStoredPayload(sema, clonedRef, sourceRef);
        sema.setSubstitute(clonedRef, substituteRef);
    }

    std::optional<NodePayload::StoredView> sourceStoredView(Sema& sema, const Ast* sourceAst, AstNodeRef sourceRef)
    {
        if (!sourceAst || sourceRef.isInvalid())
            return std::nullopt;

        if (sourceAst == &sema.ast())
            return currentStoredView(sema, sourceRef);

        // A previously cloned node retains its original token location. Its node
        // reference and payload belong to the AST holding the clone, not that file.
        const SourceFile* sourceFile = sourceAst->sourceFile();
        if (!sourceFile)
            return std::nullopt;

        SWC_ASSERT(&sourceFile->ast() == sourceAst);
        return sourceFile->nodePayloadContext().viewStored(sema.ctx(), sourceRef);
    }

    SemaClone::CloneContext cloneContextWithoutReplacements(const SemaClone::CloneContext& cloneContext)
    {
        // Binding expressions are cloned independently from replacement nodes; stripping
        // replacements here prevents a replacement meant for the outer clone from
        // rewriting the binding source itself.
        SemaClone::CloneContext result{cloneContext.bindings, {}, cloneContext.preserveFunctionGenerics, cloneContext.sourceAst, cloneContext.preserveBindingExprState, cloneContext.duplicateRuntimeStorage, cloneContext.breakableDepth};
        inheritCloneContextOptions(result, cloneContext);
        return result;
    }

    SemaClone::CloneContext cloneContextWithoutBindings(const SemaClone::CloneContext& cloneContext)
    {
        SemaClone::CloneContext result{std::span<const SemaClone::ParamBinding>{}, cloneContext.replacements, cloneContext.preserveFunctionGenerics, cloneContext.sourceAst, cloneContext.preserveBindingExprState, cloneContext.duplicateRuntimeStorage, cloneContext.breakableDepth};
        inheritCloneContextOptions(result, cloneContext);
        return result;
    }

    SemaClone::CloneContext cloneContextForDestinationAst(const SemaClone::CloneContext& cloneContext)
    {
        // Once a cloned child has been inserted in the destination AST, nested refs must
        // resolve against that destination, not against the original source AST.
        SemaClone::CloneContext result{cloneContext.bindings, cloneContext.replacements, cloneContext.preserveFunctionGenerics, nullptr, cloneContext.preserveBindingExprState, cloneContext.duplicateRuntimeStorage, cloneContext.breakableDepth};
        inheritCloneContextOptions(result, cloneContext);
        result.suppressedImplicitCastSubstituteRef = AstNodeRef::invalid();
        return result;
    }

    SemaClone::CloneContext cloneContextInsideBreakable(const SemaClone::CloneContext& cloneContext)
    {
        // Break/continue targets are valid only up to the nearest cloned breakable
        // construct. Track nesting so an outer replacement does not capture an inner
        // loop or switch control-flow edge.
        SemaClone::CloneContext result{cloneContext.bindings, cloneContext.replacements, cloneContext.preserveFunctionGenerics, cloneContext.sourceAst, cloneContext.preserveBindingExprState, cloneContext.duplicateRuntimeStorage, cloneContext.breakableDepth + 1};
        inheritCloneContextOptions(result, cloneContext);
        return result;
    }

    SemaClone::CloneContext cloneContextSuppressingImplicitCastSubstitute(const SemaClone::CloneContext& cloneContext, AstNodeRef castRef)
    {
        SemaClone::CloneContext result             = cloneContext;
        result.suppressedImplicitCastSubstituteRef = castRef;
        return result;
    }

    // A 'scope' is not one of these: a bare 'break' or 'continue' written inside it still
    // belongs to the enclosing loop or switch, so an injected one keeps being substituted.
    bool startsNestedBreakableContext(const AstNode& node)
    {
        return node.is(AstNodeId::WhileStmt) ||
               node.is(AstNodeId::ForeachStmt) ||
               node.is(AstNodeId::ForCStyleStmt) ||
               node.is(AstNodeId::ForStmt) ||
               node.is(AstNodeId::InfiniteLoopStmt) ||
               node.is(AstNodeId::SwitchStmt);
    }

    bool sameBindingIdentity(const SemaClone::ParamBinding& lhs, const SemaClone::ParamBinding& rhs)
    {
        return lhs.idRef == rhs.idRef &&
               lhs.sourceParam == rhs.sourceParam &&
               lhs.exprRef == rhs.exprRef &&
               lhs.typeRef == rhs.typeRef &&
               lhs.cstRef == rhs.cstRef;
    }

    const SemaClone::ParamBinding* findInlinePayloadBinding(const SemaInlinePayload* inlinePayload, const Symbol* sourceSymbol)
    {
        if (!inlinePayload || !sourceSymbol || !sourceSymbol->isVariable())
            return nullptr;

        for (const SemaClone::ParamBinding& binding : inlinePayload->argMappings)
        {
            if (binding.sourceParam == sourceSymbol)
                return &binding;
        }

        return nullptr;
    }

    const SemaClone::ParamBinding* findBinding(const SemaClone::CloneContext& cloneContext, IdentifierRef idRef, const Symbol* sourceSymbol, const SemaInlinePayload* sourceInlinePayload)
    {
        if (const SemaClone::ParamBinding* payloadBinding = findInlinePayloadBinding(sourceInlinePayload, sourceSymbol))
        {
            for (const SemaClone::ParamBinding& binding : cloneContext.bindings)
            {
                if (sameBindingIdentity(binding, *payloadBinding))
                    return &binding;
            }
        }

        if (sourceSymbol && sourceSymbol->isVariable())
        {
            for (const SemaClone::ParamBinding& binding : cloneContext.bindings)
            {
                if (binding.sourceParam == sourceSymbol)
                    return &binding;
            }
        }

        for (const SemaClone::ParamBinding& binding : cloneContext.bindings)
        {
            if (binding.idRef == idRef)
            {
                if (sourceSymbol && binding.sourceParam && binding.sourceParam != sourceSymbol)
                    continue;
                return &binding;
            }
        }

        return nullptr;
    }

    SemaClone::CloneContext cloneContextAfterBinding(const SemaClone::CloneContext& cloneContext, const SemaClone::ParamBinding& binding)
    {
        std::span<const SemaClone::ParamBinding> nestedBindings;
        if (!cloneContext.bindings.empty())
        {
            const SemaClone::ParamBinding* begin      = cloneContext.bindings.data();
            const SemaClone::ParamBinding* end        = begin + cloneContext.bindings.size();
            const SemaClone::ParamBinding* bindingPtr = &binding;
            SWC_ASSERT(bindingPtr >= begin && bindingPtr < end);
            if (bindingPtr >= begin && bindingPtr < end)
                nestedBindings = std::span{bindingPtr + 1, static_cast<size_t>(end - bindingPtr - 1)};
        }

        SemaClone::CloneContext result{nestedBindings, cloneContext.replacements, cloneContext.preserveFunctionGenerics, cloneContext.sourceAst, cloneContext.preserveBindingExprState, cloneContext.duplicateRuntimeStorage, cloneContext.breakableDepth};
        inheritCloneContextOptions(result, cloneContext);
        result.suppressedImplicitCastSubstituteRef = AstNodeRef::invalid();
        return result;
    }

    bool isImplicitCastSubstitute(const Sema& sema, AstNodeRef sourceRef, AstNodeRef resolvedRef)
    {
        if (sourceRef.isInvalid() || resolvedRef.isInvalid() || resolvedRef == sourceRef)
            return false;

        const auto* castNode = sema.node(resolvedRef).safeCast<AstCastExpr>();
        if (!castNode || castNode->hasFlag(AstCastExprFlagsE::Explicit))
            return false;

        return castNode->nodeExprRef == sourceRef;
    }

    void collectSourceIdentifierUses(Sema& sema, const Ast& sourceAst, AstNodeRef nodeRef, SmallVector<IdentifierRef>& outIdentifiers)
    {
        if (nodeRef.isInvalid())
            return;

        const AstNode& node = sourceAst.node(nodeRef);
        if (node.is(AstNodeId::Identifier))
            outIdentifiers.push_back(sema.idMgr().addIdentifier(sema.ctx(), node.codeRef()));

        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, sourceAst);
        for (const AstNodeRef childRef : children)
            collectSourceIdentifierUses(sema, sourceAst, childRef, outIdentifiers);
    }

    void collectClosureCaptureIdentifiers(Sema& sema, const Ast& sourceAst, SpanRef captureArgsRef, SmallVector<IdentifierRef>& outIdentifiers)
    {
        const auto captures = sourceAst.nodeSpan(captureArgsRef);
        for (auto chunk = captures.chunksBegin(); chunk != captures.chunksEnd(); ++chunk)
        {
            for (const AstNodeRef captureRef : std::span(static_cast<const AstNodeRef*>(chunk->ptr), chunk->count))
            {
                const auto& captureArg = sourceAst.node(captureRef).cast<AstClosureArgument>();
                collectSourceIdentifierUses(sema, sourceAst, captureArg.nodeIdentifierRef, outIdentifiers);
            }
        }
    }

    // Captures and a callable's own parameters both hide outer bindings by name.
    void excludeNamedBindings(SmallVector<SemaClone::ParamBinding>& outBindings, std::span<const SemaClone::ParamBinding> bindings, std::span<const IdentifierRef> excludedIdentifiers)
    {
        if (excludedIdentifiers.empty())
        {
            for (const SemaClone::ParamBinding& binding : bindings)
                outBindings.push_back(binding);
            return;
        }

        // Captures and parameters are a handful of names: scanning them beats building a set.
        for (const SemaClone::ParamBinding& binding : bindings)
        {
            if (std::ranges::find(excludedIdentifiers, binding.idRef) == excludedIdentifiers.end())
                outBindings.push_back(binding);
        }
    }

    void excludeCapturedClosureBindings(Sema& sema, const AstClosureExpr& node, const SemaClone::CloneContext& cloneContext, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        if (cloneContext.bindings.empty())
            return;

        SmallVector<IdentifierRef> captureIdentifiers;
        collectClosureCaptureIdentifiers(sema, cloneSourceAst(sema, cloneContext), node.nodeCaptureArgsRef, captureIdentifiers);
        excludeNamedBindings(outBindings, cloneContext.bindings, captureIdentifiers.span());
    }

    // The identifier a declaration token names, or invalid when the token is not a plain name.
    IdentifierRef declaredTokenIdentifier(Sema& sema, const AstNode& node, TokenRef tokNameRef)
    {
        if (tokNameRef.isInvalid())
            return IdentifierRef::invalid();

        const SourceCodeRef codeRef{node.srcViewRef(), tokNameRef};
        if (sema.token(codeRef).id != TokenId::Identifier)
            return IdentifierRef::invalid();
        return sema.idMgr().addIdentifier(sema.ctx(), codeRef);
    }

    // The names a callable declares as its own parameters, 'me' included. Inside that callable
    // such a name is the parameter's, whatever the enclosing expansion binds it to: a macro body
    // carries no resolved symbols, so the declared NAME is all the cloner has to tell the two
    // apart.
    void collectCallableParameterIdentifiers(Sema& sema, const Ast& sourceAst, AstNodeRef paramListRef, SpanRef lambdaParamsRef, SmallVector<IdentifierRef>& outIdentifiers)
    {
        SmallVector<AstNodeRef> paramRefs;
        if (paramListRef.isValid() && sourceAst.hasNode(paramListRef))
            sourceAst.appendNodes(paramRefs, sourceAst.node(paramListRef).cast<AstFunctionParamList>().spanChildrenRef);
        if (lambdaParamsRef.isValid())
            sourceAst.appendNodes(paramRefs, lambdaParamsRef);

        for (size_t i = 0; i < paramRefs.size(); ++i)
        {
            const AstNodeRef paramRef = paramRefs[i];
            if (paramRef.isInvalid() || !sourceAst.hasNode(paramRef))
                continue;

            const AstNode* node = &sourceAst.node(paramRef);
            while (const auto* attributes = node->safeCast<AstAttributeList>())
            {
                if (attributes->nodeBodyRef.isInvalid() || !sourceAst.hasNode(attributes->nodeBodyRef))
                    break;
                node = &sourceAst.node(attributes->nodeBodyRef);
            }

            if (const auto* declList = node->safeCast<AstVarDeclList>())
            {
                // Several declarations sharing one type: each of them names a parameter.
                sourceAst.appendNodes(paramRefs, declList->spanChildrenRef);
                continue;
            }

            if (node->is(AstNodeId::FunctionParamMe))
            {
                outIdentifiers.push_back(sema.idMgr().predefined(IdentifierManager::PredefinedName::Me));
            }
            else if (const auto* singleVar = node->safeCast<AstSingleVarDecl>())
            {
                if (const IdentifierRef idRef = declaredTokenIdentifier(sema, *node, singleVar->tokNameRef); idRef.isValid())
                    outIdentifiers.push_back(idRef);
            }
            else if (const auto* multiVar = node->safeCast<AstMultiVarDecl>())
            {
                SmallVector<TokenRef> tokNames;
                sourceAst.appendTokens(tokNames, multiVar->spanNamesRef);
                for (const TokenRef tokNameRef : tokNames)
                {
                    if (const IdentifierRef idRef = declaredTokenIdentifier(sema, *node, tokNameRef); idRef.isValid())
                        outIdentifiers.push_back(idRef);
                }
            }
            else if (const auto* lambdaParam = node->safeCast<AstLambdaParam>(); lambdaParam && lambdaParam->hasFlag(AstLambdaParamFlagsE::Named))
            {
                if (const IdentifierRef idRef = declaredTokenIdentifier(sema, *node, node->tokRef()); idRef.isValid())
                    outIdentifiers.push_back(idRef);
            }
        }
    }

    // The same context over another binding set, every option carried over.
    SemaClone::CloneContext cloneContextWithBindings(const SemaClone::CloneContext& cloneContext, std::span<const SemaClone::ParamBinding> bindings)
    {
        SemaClone::CloneContext result{bindings, cloneContext.replacements, cloneContext.preserveFunctionGenerics, cloneContext.sourceAst, cloneContext.preserveBindingExprState, cloneContext.duplicateRuntimeStorage, cloneContext.breakableDepth};
        inheritCloneContextOptions(result, cloneContext);
        return result;
    }

    const SemaClone::NodeReplacement* findReplacement(const SemaClone::CloneContext& cloneContext, AstNodeId nodeId)
    {
        for (const SemaClone::NodeReplacement& replacement : cloneContext.replacements)
        {
            if (replacement.nodeId == nodeId)
                return &replacement;
        }

        return nullptr;
    }

    template<AstNodeId ID>
    AstNodeRef cloneNodeCopy(Sema& sema, const AstNode& node)
    {
        using NodeType            = AstTypeOf<ID>::type;
        auto [newRef, newNodePtr] = sema.ast().makeNode<ID>(node.tokRef());
        *newNodePtr               = node.cast<NodeType>();
        newNodePtr->clearPayload();
        return newRef;
    }

    AstNodeRef cloneNodeRef(Sema& sema, AstNodeRef nodeRef, const SemaClone::CloneContext& cloneContext)
    {
        if (nodeRef.isInvalid())
            return AstNodeRef::invalid();
        return SemaClone::cloneAst(sema, nodeRef, cloneContext);
    }

    SpanRef cloneSpan(Sema& sema, SpanRef spanRef, const SemaClone::CloneContext& cloneContext);

    // End each field's temporary clone context before cloning the next field.
    template<auto Member, typename T>
    __forceinline void cloneInlineMember(Sema& sema, T& cloned, const T& node, const CloneContext& cloneContext)
    {
        if constexpr (std::is_same_v<std::remove_cvref_t<decltype(node.*Member)>, AstNodeRef>)
            cloned.*Member = cloneNodeRef(sema, node.*Member, cloneContextAsInline(cloneContext));
        else
        {
            static_assert(std::is_same_v<std::remove_cvref_t<decltype(node.*Member)>, SpanRef>);
            cloned.*Member = cloneSpan(sema, node.*Member, cloneContextAsInline(cloneContext));
        }
    }

    // Retain the callbacks' original call boundaries, including the larger variable nodes.
    template<AstNodeId ID, auto... Members, typename T>
    __forceinline AstNodeRef cloneNodeMembers(Sema& sema, const T& node, const CloneContext& cloneContext)
    {
        const AstNodeRef newRef = cloneNodeCopy<ID>(sema, node);
        auto&            cloned = sema.node(newRef).cast<T>();
        (cloneInlineMember<Members>(sema, cloned, node, cloneContext), ...);
        return newRef;
    }

    AstNodeRef cloneNodeRefWithoutReplacements(Sema& sema, AstNodeRef nodeRef, const SemaClone::CloneContext& cloneContext)
    {
        if (nodeRef.isInvalid())
            return AstNodeRef::invalid();

        const auto noReplacements = cloneContextWithoutReplacements(cloneContext);
        return SemaClone::cloneAst(sema, nodeRef, noReplacements);
    }

    AstNodeRef cloneNodeRefWithoutBindings(Sema& sema, AstNodeRef nodeRef, const SemaClone::CloneContext& cloneContext)
    {
        if (nodeRef.isInvalid())
            return AstNodeRef::invalid();

        const auto noBindings = cloneContextWithoutBindings(cloneContext);
        return SemaClone::cloneAst(sema, nodeRef, noBindings);
    }

    AstNodeRef cloneCodeNodeRefWithoutReplacements(Sema& sema, AstNodeRef nodeRef, const SemaClone::CloneContext& cloneContext)
    {
        if (nodeRef.isInvalid())
            return AstNodeRef::invalid();

        const Ast& sourceAst = cloneSourceAst(sema, cloneContext);
        if (sourceAst.hasNode(nodeRef))
            return cloneNodeRefWithoutReplacements(sema, nodeRef, cloneContext);

        return nodeRef;
    }

    AstNodeRef markConstParamBindingTarget(Sema& sema, const SemaClone::ParamBinding& binding, AstNodeRef targetRef)
    {
        // A mutable materialized home is the callee's own copy: writing it can never
        // reach the caller's expression, so the by-value parameter keeps the mutable
        // local semantics it has in the non-inlined function.
        if (binding.mutableHomeUse)
            return targetRef;

        if (binding.sourceParam != nullptr && targetRef.isValid())
        {
            const TypeInfo& paramType = binding.sourceParam->type(sema.ctx());
            if (paramType.isReference() && !paramType.isConst())
                return targetRef;

            // A mutable non-null pointer parameter writes through to the pointee, exactly
            // like a mutable reference: inlining must not freeze the bound expression.
            if (paramType.isNonNullValuePointer() && !sema.typeMgr().get(paramType.payloadTypeRef()).isConst())
                return targetRef;

            sema.setConstAssignBinding(targetRef, binding.sourceParam);
            if (!paramType.isPointerOrReference() || paramType.isReference())
                sema.setConstAssignTarget(targetRef);
        }
        return targetRef;
    }

    bool bindingInlineContextOverrideTarget(Sema& sema, const SemaInlinePayload*& outTarget, const SemaClone::ParamBinding& binding)
    {
        if (!binding.sourceParam || !binding.sourceParam->type(sema.ctx()).isCodeBlock() || binding.exprRef.isInvalid())
            return false;

        const auto* overridePayload = sema.inlineContextOverride<SemaInlineContextOverride>(binding.exprRef);
        if (!overridePayload)
            return false;

        outTarget = overridePayload->targetInlinePayload;
        return true;
    }

    void setCallerInlineContextOverride(Sema& sema, AstNodeRef targetRef, const SemaClone::ParamBinding& binding)
    {
        if (targetRef.isInvalid())
            return;

        const SemaInlinePayload* targetInlinePayload = nullptr;
        if (!bindingInlineContextOverrideTarget(sema, targetInlinePayload, binding))
            targetInlinePayload = sema.frame().currentInlinePayload();

        auto* inlineOverridePayload                = sema.compiler().allocate<SemaInlineContextOverride>();
        inlineOverridePayload->targetInlinePayload = targetInlinePayload;
        sema.setInlineContextOverride(targetRef, inlineOverridePayload);
    }

    AstNodeRef makeConstantBindingIdentifier(Sema& sema, const AstIdentifier& node, TypeRef typeRef, ConstantRef cstRef, bool foldedTypedConst)
    {
        auto [newRef, newNodePtr] = sema.ast().makeNode<AstNodeId::Identifier>(node.tokRef());
        newNodePtr->flags()       = node.flags();
        newNodePtr->addFlag(AstIdentifierFlagsE::ConstantBinding);
        newNodePtr->setCodeRef(node.codeRef());
        if (typeRef.isValid())
            sema.setType(newRef, typeRef);
        sema.setConstant(newRef, cstRef);
        if (foldedTypedConst)
            sema.setFoldedTypedConst(newRef);
        return newRef;
    }

    ConstantRef foldImplicitCastConstant(Sema& sema, ConstantRef sourceCstRef, TypeRef dstTypeRef, AstNodeRef errorNodeRef)
    {
        if (sourceCstRef.isInvalid() || dstTypeRef.isInvalid())
            return ConstantRef::invalid();

        const ConstantValue& value      = sema.cstMgr().get(sourceCstRef);
        const TypeRef        srcTypeRef = value.typeRef();
        CastRequest          castRequest(CastKind::Implicit);
        castRequest.errorNodeRef = errorNodeRef;
        castRequest.setConstantFoldingSrc(sourceCstRef);
        if (Cast::castAllowed(sema, castRequest, srcTypeRef, dstTypeRef) != Result::Continue)
            return ConstantRef::invalid();

        ConstantRef castedCstRef = castRequest.constantFoldingResult();
        if (castedCstRef.isInvalid())
            return ConstantRef::invalid();

        const ConstantValue& castedValue = sema.cstMgr().get(castedCstRef);
        if (castedValue.typeRef() != dstTypeRef)
        {
            const TypeInfo& srcType = sema.typeMgr().get(srcTypeRef);
            const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);
            if (!srcType.isAnyTypeInfo(sema.ctx()) || !dstType.isAnyTypeInfo(sema.ctx()))
                return ConstantRef::invalid();

            ConstantValue castedCst = castedValue;
            castedCst.setTypeRef(dstTypeRef);
            castedCstRef = sema.cstMgr().addConstant(sema.ctx(), castedCst);
        }

        return castedCstRef;
    }

    void setFoldedImplicitCastConstant(Sema& sema, AstNodeRef castRef, ConstantRef sourceCstRef)
    {
        if (castRef.isInvalid() || sourceCstRef.isInvalid())
            return;

        const TypeRef     dstTypeRef   = sema.viewStored(castRef, SemaNodeViewPartE::Type).typeRef();
        const ConstantRef castedCstRef = foldImplicitCastConstant(sema, sourceCstRef, dstTypeRef, castRef);
        if (castedCstRef.isInvalid())
            return;

        sema.setFoldedTypedConst(castRef);
        sema.setConstant(castRef, castedCstRef);
    }

    void foldTypedBindingConstant(Sema& sema, const SemaClone::ParamBinding& binding, AstNodeRef castRef)
    {
        if (!binding.typeRef.isValid() || binding.exprRef.isInvalid())
            return;

        const SemaNodeView sourceView = sema.viewConstant(binding.exprRef);
        if (!sourceView.hasConstant())
            return;

        setFoldedImplicitCastConstant(sema, castRef, sourceView.cstRef());
    }

    AstNodeRef cloneNodeReplacement(Sema& sema, const AstNode& node, const SemaClone::CloneContext& cloneContext)
    {
        const auto* replacement = findReplacement(cloneContext, node.id());
        if (!replacement)
            return AstNodeRef::invalid();
        if (replacement->topLevelBreakableOnly && cloneContext.breakableDepth != 0)
            return AstNodeRef::invalid();

        const auto destinationContext = cloneContextForDestinationAst(cloneContext);
        return cloneNodeRefWithoutReplacements(sema, replacement->replacementRef, destinationContext);
    }

    void copyCallableClonePayload(Sema& sema, const SemaClone::CloneContext& cloneContext, AstNodeRef sourceRef, AstNodeRef clonedRef)
    {
        if (!canReadSourcePayload(sema, cloneContext))
            return;

        const AstNode& sourceNode = sema.node(sourceRef);
        if (sourceNode.isNot(AstNodeId::FunctionExpr) && sourceNode.isNot(AstNodeId::ClosureExpr))
            return;
        // Inline clones must build fresh callable symbols so captures bind to the cloned locals.
        if (cloneContext.sourceAst)
            return;
        // A copy with substitutions has a body of its own, so it builds a fresh symbol
        // too. A plain copy is the source function again, and sema reuses it.
        if (!cloneContext.bindings.empty() || !cloneContext.replacements.empty())
            return;

        const SemaNodeView storedView = sema.viewStored(sourceRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol);
        if (storedView.hasSymbol())
            sema.setSymbol(clonedRef, storedView.sym());
        else if (storedView.typeRef().isValid())
            sema.setType(clonedRef, storedView.typeRef());

        if (sema.isValueStored(sourceRef))
            sema.setIsValue(clonedRef);

        if (sema.isLValueStored(sourceRef))
            sema.setIsLValue(clonedRef);
        else
            sema.unsetIsLValue(clonedRef);
    }

    SymbolVariable* duplicateRuntimeStorageSymbol(Sema& sema, AstNodeRef clonedRef, SymbolVariable& sourceStorageSym)
    {
        if (!sourceStorageSym.typeRef().isValid())
            return &sourceStorageSym;

        auto&        clonedStorage = SemaHelpers::registerUniqueRuntimeStorageSymbol(sema, sema.node(clonedRef), "__cast_runtime_storage");
        const Result result        = SemaHelpers::ensureRuntimeStorageDeclaredAndCompleted(sema, clonedStorage, sourceStorageSym.typeRef());
        SWC_ASSERT(result == Result::Continue);
        if (result != Result::Continue)
            return &sourceStorageSym;

        return &clonedStorage;
    }

    void copyImplicitCastLoweringPayload(Sema& sema, const SemaClone::CloneContext& cloneContext, AstNodeRef sourceRef, AstNodeRef clonedRef)
    {
        const auto* sourcePayload = sema.loweringPayload<CodeGenLoweringPayload>(sourceRef);
        if (!sourcePayload)
            return;

        auto& clonedPayload = SemaHelpers::ensureCodeGenLoweringPayload(sema, clonedRef);
        if (!clonedPayload.runtimeStorageSym && sourcePayload->runtimeStorageSym)
        {
            if (cloneContext.duplicateRuntimeStorage)
                clonedPayload.runtimeStorageSym = duplicateRuntimeStorageSymbol(sema, clonedRef, *sourcePayload->runtimeStorageSym);
            else
                clonedPayload.runtimeStorageSym = sourcePayload->runtimeStorageSym;
        }
        if (!clonedPayload.runtimeFunctionSymbol && sourcePayload->runtimeFunctionSymbol)
            clonedPayload.runtimeFunctionSymbol = sourcePayload->runtimeFunctionSymbol;
        if (!clonedPayload.runtimeArrayFillTypeRef.isValid() && sourcePayload->runtimeArrayFillTypeRef.isValid())
            clonedPayload.runtimeArrayFillTypeRef = sourcePayload->runtimeArrayFillTypeRef;
        if (!clonedPayload.runtimeArrayFillCstRef.isValid() && sourcePayload->runtimeArrayFillCstRef.isValid())
            clonedPayload.runtimeArrayFillCstRef = sourcePayload->runtimeArrayFillCstRef;
        clonedPayload.runtimeSafetyMask |= sourcePayload->runtimeSafetyMask;
        clonedPayload.valueBorrowSafetyOverride = sourcePayload->valueBorrowSafetyOverride;
        clonedPayload.notNullUnwrap |= sourcePayload->notNullUnwrap;
        clonedPayload.ufcsReceiverAddress |= sourcePayload->ufcsReceiverAddress;
        clonedPayload.dynamicCast |= sourcePayload->dynamicCast;
        clonedPayload.assumedDynamicCast |= sourcePayload->assumedDynamicCast;
        clonedPayload.fallibleDynamicCast |= sourcePayload->fallibleDynamicCast;
        clonedPayload.runtimeTypeCast |= sourcePayload->runtimeTypeCast;
        clonedPayload.runtimeValueCast |= sourcePayload->runtimeValueCast;
    }

    void copyClonedCastCallArguments(Sema& sema, AstNodeRef sourceRef, AstNodeRef clonedRef)
    {
        const auto* sourceCast = sema.node(sourceRef).safeCast<AstCastExpr>();
        const auto* clonedCast = sema.node(clonedRef).safeCast<AstCastExpr>();
        if (!sourceCast || !clonedCast)
        {
            sema.copyResolvedCallArguments(clonedRef, sourceRef);
            return;
        }

        SmallVector<ResolvedCallArgument> args;
        sema.appendResolvedCallArguments(sourceRef, args);
        for (ResolvedCallArgument& arg : args)
        {
            // A conversion's operator call must consume the cloned operand. The
            // original expression may never be emitted in the caller's expansion.
            if (arg.argRef == sourceCast->nodeExprRef)
                arg.argRef = clonedCast->nodeExprRef;
        }
        sema.setResolvedCallArguments(clonedRef, args.span());
    }

    // Implicit casts (created by Cast::createCast) store part of their semantic
    // state outside the AST node shape itself. semaPostNode skips them, so that
    // state must be preserved across cloning.
    void copyImplicitCastPayload(Sema& sema, const SemaClone::CloneContext& cloneContext, const AstNode& sourceNode, AstNodeRef sourceRef, AstNodeRef clonedRef)
    {
        if (!canReadSourcePayload(sema, cloneContext))
            return;

        if (sourceNode.isNot(AstNodeId::CastExpr))
            return;
        if (sourceNode.cast<AstCastExpr>().hasFlag(AstCastExprFlagsE::Explicit))
            return;
        const SemaNodeView storedView = sema.viewStored(sourceRef, SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        // Always preserve the cast's target type: semaPostNode is skipped for implicit casts
        // and the clone must carry the type even when the source was constant-folded.
        if (sema.isValueStored(sourceRef))
            sema.setIsValue(clonedRef);
        if (sema.isLValueStored(sourceRef))
            sema.setIsLValue(clonedRef);
        if (sema.isFoldedTypedConstStored(sourceRef))
            sema.setFoldedTypedConst(clonedRef);
        if (storedView.typeRef().isValid())
            sema.setType(clonedRef, storedView.typeRef());
        if (storedView.hasConstant())
            return;

        if (auto* payload = sema.semaPayload<CastSpecOpPayload>(sourceRef))
            sema.setSemaPayload(clonedRef, payload);
        copyClonedCastCallArguments(sema, sourceRef, clonedRef);
        copyImplicitCastLoweringPayload(sema, cloneContext, sourceRef, clonedRef);

        // The conversion can retarget an aggregate literal's storage to its concrete
        // destination layout. The implicit cast is not analyzed again, so its cloned
        // operand must keep that layout too: unsized fields have no storage in the
        // original aggregate type and would otherwise disappear from the value.
        const auto& sourceCast = sourceNode.cast<AstCastExpr>();
        const auto& clonedCast = sema.node(clonedRef).cast<AstCastExpr>();
        copyImplicitCastLoweringPayload(sema, cloneContext, sourceCast.nodeExprRef, clonedCast.nodeExprRef);
    }

    void foldClonedImplicitCastConstant(Sema& sema, AstNodeRef clonedExprRef, AstNodeRef clonedCastRef)
    {
        const SemaNodeView exprView = sema.viewConstant(clonedExprRef);
        if (!exprView.hasConstant())
            return;

        setFoldedImplicitCastConstant(sema, clonedCastRef, exprView.cstRef());
    }

    void copyImplicitCastSubstitute(Sema& sema, const SemaClone::CloneContext& cloneContext, AstNodeRef sourceRef, AstNodeRef clonedRef)
    {
        if (!canReadSourcePayload(sema, cloneContext))
            return;

        const AstNodeRef resolvedRef = sema.resolvedNodeRef(sourceRef);
        if (resolvedRef.isInvalid() || resolvedRef == sourceRef)
            return;
        if (resolvedRef == cloneContext.suppressedImplicitCastSubstituteRef)
            return;

        const auto* sourceCast = sema.node(resolvedRef).safeCast<AstCastExpr>();
        if (!sourceCast)
            return;
        if (sourceCast->hasFlag(AstCastExprFlagsE::Explicit))
            return;
        if (sourceCast->nodeExprRef != sourceRef)
            return;

        auto [castRef, castPtr] = sema.ast().makeNode<AstNodeId::CastExpr>(sourceCast->tokRef());
        castPtr->flags()        = sourceCast->flags();
        castPtr->modifierFlags  = sourceCast->modifierFlags;
        castPtr->setCodeRef(sourceCast->codeRef());
        castPtr->nodeTypeRef = cloneNodeRef(sema, sourceCast->nodeTypeRef, cloneContext);
        castPtr->nodeExprRef = clonedRef;

        copyImplicitCastPayload(sema, cloneContext, *sourceCast, resolvedRef, castRef);
        foldClonedImplicitCastConstant(sema, clonedRef, castRef);
        sema.setSubstitute(clonedRef, castRef);
    }

    void copyVarInitSpecOpPayload(Sema& sema, const SemaClone::CloneContext& cloneContext, const AstNode& sourceNode, AstNodeRef sourceRef, AstNodeRef clonedRef)
    {
        if (!canReadSourcePayload(sema, cloneContext))
            return;
        if (sourceNode.isNot(AstNodeId::SingleVarDecl) && sourceNode.isNot(AstNodeId::MultiVarDecl))
            return;
        auto* payload = sema.semaPayload<VarInitSpecOpPayload>(sourceRef);
        if (!payload)
            return;

        sema.setSemaPayload(clonedRef, payload);
        sema.copyResolvedCallArguments(clonedRef, sourceRef);
    }

    void copyLoopPayload(Sema& sema, const SemaClone::CloneContext& cloneContext, const AstNode& sourceNode, AstNodeRef sourceRef, AstNodeRef clonedRef)
    {
        if (!canReadSourcePayload(sema, cloneContext))
            return;

        switch (sourceNode.id())
        {
            case AstNodeId::ForStmt:
            case AstNodeId::ForeachStmt:
                if (const auto* sourcePayload = sema.semaPayload<LoopSemaPayload>(sourceRef))
                {
                    auto* clonedPayload = sema.compiler().allocate<LoopSemaPayload>();
                    *clonedPayload      = *sourcePayload;
                    clonedPayload->localSymbols.clear();
                    sema.setSemaPayload(clonedRef, clonedPayload);
                }
                break;

            default:
                return;
        }
    }

    SpanRef cloneSpan(Sema& sema, SpanRef spanRef, const SemaClone::CloneContext& cloneContext)
    {
        if (spanRef.isInvalid())
            return SpanRef::invalid();

        const Ast* spanAst = resolveCloneSpanAst(sema, spanRef, cloneContext);
        if (!spanAst)
            return SpanRef::invalid();

        SmallVector<AstNodeRef> children;
        spanAst->appendNodes(children, spanRef);
        if (children.empty())
            return SpanRef::invalid();

        for (AstNodeRef& childRef : children)
        {
            childRef = SemaClone::cloneAst(sema, childRef, cloneContext);
            if (childRef.isInvalid())
                return SpanRef::invalid();
        }

        return sema.ast().pushSpan(children.span());
    }

    SpanRef cloneTokenSpan(Sema& sema, SpanRef spanRef, const SemaClone::CloneContext& cloneContext)
    {
        if (spanRef.isInvalid())
            return SpanRef::invalid();

        const Ast* spanAst = resolveCloneSpanAst(sema, spanRef, cloneContext);
        if (!spanAst)
            return SpanRef::invalid();
        // Token lists are immutable and can retain their span within the same owner.
        if (spanAst == &sema.ast())
            return spanRef;

        SmallVector<TokenRef> tokens;
        spanAst->appendTokens(tokens, spanRef);
        if (tokens.empty())
            return SpanRef::invalid();

        return sema.ast().pushSpan(tokens.span());
    }

    AstNodeRef cloneMemberSelector(Sema& sema, AstNodeRef nodeRef, const SemaClone::CloneContext& cloneContext)
    {
        const Ast* sourceAst = resolveCloneNodeAst(sema, nodeRef, cloneContext);
        if (!sourceAst)
            return AstNodeRef::invalid();

        // The member's name belongs to the left-hand scope. Its quoted arguments still belong
        // to the enclosing generic context: Ns.Box'T must substitute T without substituting Box.
        const AstNode& sourceNode       = sourceAst->node(nodeRef);
        const auto     argumentsContext = cloneContextWithoutReplacements(cloneContext);
        if (const auto* quoted = sourceNode.safeCast<AstQuotedExpr>())
        {
            const AstNodeRef newRef = cloneNodeCopy<AstNodeId::QuotedExpr>(sema, *quoted);
            auto&            cloned = sema.node(newRef).cast<AstQuotedExpr>();
            cloned.nodeExprRef      = cloneMemberSelector(sema, quoted->nodeExprRef, argumentsContext);
            cloned.nodeSuffixRef    = cloneNodeRef(sema, quoted->nodeSuffixRef, argumentsContext);
            return newRef;
        }
        if (const auto* quoted = sourceNode.safeCast<AstQuotedListExpr>())
        {
            const AstNodeRef newRef = cloneNodeCopy<AstNodeId::QuotedListExpr>(sema, *quoted);
            auto&            cloned = sema.node(newRef).cast<AstQuotedListExpr>();
            cloned.nodeExprRef      = cloneMemberSelector(sema, quoted->nodeExprRef, argumentsContext);
            cloned.spanChildrenRef  = cloneSpan(sema, quoted->spanChildrenRef, argumentsContext);
            return newRef;
        }
        return cloneNodeRefWithoutBindings(sema, nodeRef, cloneContext);
    }

    SpanRef cloneSpanWithoutReplacements(Sema& sema, SpanRef spanRef, const SemaClone::CloneContext& cloneContext)
    {
        if (spanRef.isInvalid())
            return SpanRef::invalid();

        const auto noReplacements = cloneContextWithoutReplacements(cloneContext);
        return cloneSpan(sema, spanRef, noReplacements);
    }

    void copyDetachedBindingExprState(Sema& sema, AstNodeRef sourceRef, AstNodeRef clonedRef, WalkPath<AstNodeRef>& activeSourceRefSet, bool* needsReanalysis);

    void pinResolvedCallCallee(Sema& sema, AstNodeRef calleeRef, const SymbolFunction& fn)
    {
        // An indirect call resolves to a signature, not an executable declaration.
        // Its cloned local may not have been rebound yet, so inspecting only the
        // cloned identifier can mistake a function-valued variable for an overload.
        if (fn.decl() && fn.decl()->is(AstNodeId::LambdaType))
            return;

        const AstNodeRef identifierRef = SemaHelpers::unwrapCallCalleeRef(sema, calleeRef);
        if (identifierRef.isInvalid() || !sema.node(identifierRef).is(AstNodeId::Identifier))
            return;

        const Symbol* calleeSymbol = sema.viewSymbol(identifierRef).sym();
        if (calleeSymbol && calleeSymbol->isVariable())
            return;

        // A quoted callee applies its explicit generic arguments again. Preserve the
        // selected overload's root, rather than the first overload stored on its name.
        const SymbolFunction* target = identifierRef != calleeRef ? fn.genericRootOrSelf() : &fn;
        sema.setSymbol(identifierRef, target);
        sema.node(identifierRef).cast<AstIdentifier>().addFlag(AstIdentifierFlagsE::PreResolvedSymbol);
    }

    void copyResolvedIdentifierSymbols(Sema& sema, AstNodeRef sourceRef, AstNodeRef clonedRef, bool rebindLocals = false)
    {
        SWC_ASSERT(sourceRef.isValid());
        SWC_ASSERT(clonedRef.isValid());

        if (sema.node(sourceRef).is(AstNodeId::Identifier) && sema.node(clonedRef).is(AstNodeId::Identifier))
        {
            // Prefer committed symbols. A synthesized implicit receiver may only have a
            // current-pass binding when cloned for inline materialization. Preserve that
            // binding too, or the clone tries to resolve the caller's receiver in the
            // callee's scope and stalls.
            SemaNodeView  symbolView = sema.viewStored(sourceRef, SemaNodeViewPartE::Symbol);
            const Symbol* symbol     = symbolView.sym();
            if (!symbol)
            {
                symbolView = sema.viewSymbol(sourceRef);
                symbol     = symbolView.sym();
            }

            // A cloned callable owns fresh locals and captures. Pinning its
            // identifiers back to the source callable shares mutable storage
            // metadata between the two independent code-generation jobs.
            if (rebindLocals && symbol && symbol->isVariable())
            {
                const auto& variable = symbol->cast<SymbolVariable>();
                if (variable.hasExtraFlag(SymbolVariableFlagsE::FunctionLocal) ||
                    variable.hasExtraFlag(SymbolVariableFlagsE::Parameter) || variable.isClosureCapture())
                    return;
            }

            if (symbol)
            {
                if (symbolView.hasSymbolList())
                    sema.setSymbolList(clonedRef, symbolView.symList());
                else
                    sema.setSymbol(clonedRef, symbol);

                sema.node(clonedRef).cast<AstIdentifier>().addFlag(AstIdentifierFlagsE::PreResolvedSymbol);
            }
            else
            {
                // A folded local read (`let n = <constant>` used as an inline-call argument) resolves
                // to a bare constant with no symbol at all. Carry that constant onto the clone, or it
                // degenerates to a name-only identifier that re-resolves in the destination scope —
                // where a same-named declaration (an inlined callee's parameter shadowing the caller's
                // argument local) rebinds it to the wrong symbol.
                const SemaNodeView sourceView = sema.viewTypeConstant(sourceRef);
                if (sourceView.hasConstant())
                {
                    if (sourceView.typeRef().isValid())
                        sema.setType(clonedRef, sourceView.typeRef());

                    sema.setConstant(clonedRef, sourceView.cstRef());
                    sema.setIsValue(clonedRef);
                    sema.node(clonedRef).cast<AstIdentifier>().addFlag(AstIdentifierFlagsE::ConstantBinding);
                }
            }
        }

        SmallVector<AstNodeRef> sourceChildren;
        SmallVector<AstNodeRef> clonedChildren;
        sema.node(sourceRef).collectChildrenFromAst(sourceChildren, sema.ast());
        sema.node(clonedRef).collectChildrenFromAst(clonedChildren, sema.ast());
        SWC_ASSERT(sourceChildren.size() == clonedChildren.size());
        if (sourceChildren.size() != clonedChildren.size())
            return;

        for (size_t i = 0; i < sourceChildren.size(); ++i)
        {
            const AstNodeRef sourceChildRef = sourceChildren[i];
            const AstNodeRef clonedChildRef = clonedChildren[i];
            if (sourceChildRef.isInvalid() || clonedChildRef.isInvalid())
                continue;

            const AstNode& parent       = sema.node(sourceRef);
            bool           childRebinds = rebindLocals;
            if (const auto* closure = parent.safeCast<AstClosureExpr>())
                childRebinds |= sourceChildRef == closure->nodeBodyRef;
            else if (const auto* function = parent.safeCast<AstFunctionExpr>())
                childRebinds |= sourceChildRef == function->nodeBodyRef;
            else if (const auto* function = parent.safeCast<AstFunctionDecl>())
                childRebinds |= sourceChildRef == function->nodeBodyRef;
            copyResolvedIdentifierSymbols(sema, sourceChildRef, clonedChildRef, childRebinds);
        }

        // A call's overload was selected against the call node, not its callee identifier, so
        // the recursion above copied the callee's whole overload set / first overload. Override
        // the cloned callee with the function the call actually resolved to, so the preserved
        // body doesn't re-run (and mis-pick) overload selection in a foreign scope. Overloaded
        // intrinsics (Swag.min, Swag.vecWidenLo, ...) resolve through the same declaration matching, so
        // their calls need the same override.
        const AstNode& sourceNode   = sema.node(sourceRef);
        const AstNode& clonedNode   = sema.node(clonedRef);
        AstNodeRef     clonedCallee = AstNodeRef::invalid();
        if (sourceNode.is(AstNodeId::CallExpr) && clonedNode.is(AstNodeId::CallExpr))
            clonedCallee = clonedNode.cast<AstCallExpr>().nodeExprRef;
        else if (sourceNode.is(AstNodeId::IntrinsicCallExpr) && clonedNode.is(AstNodeId::IntrinsicCallExpr))
            clonedCallee = clonedNode.cast<AstIntrinsicCallExpr>().nodeExprRef;

        if (clonedCallee.isValid())
        {
            if (const Symbol* callSym = sema.viewStored(sourceRef, SemaNodeViewPartE::Symbol).sym())
            {
                if (const auto* fn = callSym->safeCast<SymbolFunction>(); fn && (!rebindLocals || !fn->parentLexicalFunction()))
                    pinResolvedCallCallee(sema, clonedCallee, *fn);
            }
        }
    }

    AstNodeRef cloneExprPreservingResolvedIdentifierSymbols(Sema& sema, AstNodeRef sourceRef)
    {
        SWC_ASSERT(sourceRef.isValid());
        const SemaClone::CloneContext noBindings{std::span<const SemaClone::ParamBinding>{}};
        const AstNodeRef              clonedRef = SemaClone::cloneAstPreservingResolvedIdentifierSymbols(sema, sourceRef, noBindings);
        if (clonedRef.isInvalid())
            return AstNodeRef::invalid();
        return clonedRef;
    }

    AstNodeRef cloneDetachedExprImpl(Sema& sema, AstNodeRef sourceRef, bool* needsReanalysis = nullptr)
    {
        SWC_ASSERT(sourceRef.isValid());
        const SemaClone::CloneContext noBindings{std::span<const SemaClone::ParamBinding>{}, std::span<const SemaClone::NodeReplacement>{}, false, nullptr, false, true};
        const AstNodeRef              clonedRef = SemaClone::cloneAst(sema, sourceRef, noBindings);
        if (clonedRef.isInvalid())
            return AstNodeRef::invalid();

        WalkPath<AstNodeRef> activeSourceRefSet;
        copyDetachedBindingExprState(sema, sourceRef, clonedRef, activeSourceRefSet, needsReanalysis);
        return clonedRef;
    }

    bool shouldReexpandDetachedExpr(Sema& sema, AstNodeRef sourceRef, AstNodeRef resolvedRef)
    {
        if (resolvedRef.isInvalid() || resolvedRef == sourceRef || !SemaReexpandExpr::isReexpandableExpr(sema.node(sourceRef)))
            return false;

        // An inlined opIndexPtr keeps its element load outside the expansion. Rebuild
        // the original index in the detached caller context, just like an inline call,
        // rather than cloning the expanded body's receiver bindings into a new scope.
        return SemaInline::expansionPayload(sema, resolvedRef) != nullptr;
    }

    void copyDetachedBindingExprState(Sema& sema, AstNodeRef sourceRef, AstNodeRef clonedRef, WalkPath<AstNodeRef>& activeSourceRefSet, bool* needsReanalysis)
    {
        SWC_ASSERT(sourceRef.isValid());
        SWC_ASSERT(clonedRef.isValid());

        const AstNodeRef resolvedRef                     = sema.resolvedNodeRef(sourceRef);
        const bool       shouldReexpand                  = shouldReexpandDetachedExpr(sema, sourceRef, resolvedRef);
        const bool       sourceHasImplicitCastSubstitute = isImplicitCastSubstitute(sema, sourceRef, resolvedRef);

        if (shouldReexpand && needsReanalysis)
            *needsReanalysis = true;
        activeSourceRefSet.insert(sourceRef);
        if (!shouldReexpand && !sourceHasImplicitCastSubstitute)
            sema.inheritPayload(sema.node(clonedRef), sourceRef);
        else if (!shouldReexpand && sourceHasImplicitCastSubstitute)
        {
            if (sema.hasSubstitute(clonedRef))
                inheritStoredPayloadUnderSubstitute(sema, clonedRef, sourceRef);
            else
                inheritStoredPayload(sema, clonedRef, sourceRef);
        }

        // The clone is an exact resolved replica, and its inherited type state makes sema
        // treat it as already resolved. The spec-op selection (an index or cast payload)
        // and the resolved call arguments live in side maps keyed by the node: without
        // carrying them, codegen would lower the resolved clone through the raw fallback.
        if (!shouldReexpand)
        {
            if (void* semaPayload = sema.semaPayload<void>(sourceRef); semaPayload && !sema.semaPayload<void>(clonedRef))
                sema.setSemaPayload(clonedRef, semaPayload);
            copyClonedCastCallArguments(sema, sourceRef, clonedRef);
            if (sema.node(sourceRef).is(AstNodeId::CastExpr) || sema.node(sourceRef).is(AstNodeId::AutoCastExpr))
            {
                const SemaClone::CloneContext detachedContext{std::span<const SemaClone::ParamBinding>{}, {}, false, nullptr, false, true};
                copyImplicitCastLoweringPayload(sema, detachedContext, sourceRef, clonedRef);
            }
        }
        if (sema.node(sourceRef).is(AstNodeId::Identifier))
        {
            auto& identifier = sema.node(clonedRef).cast<AstIdentifier>();
            if (sema.viewStored(sourceRef, SemaNodeViewPartE::Symbol).hasSymbol())
                identifier.addFlag(AstIdentifierFlagsE::PreResolvedSymbol);
            // Injection's caller binding is provisional until its expression is resolved.
            // A detached, typed argument must keep that result: rechecking shadowing in
            // the callee can bind its initializer to its own not-yet-typed argument home.
            if (sema.viewType(sourceRef).typeRef().isValid())
                identifier.flags().remove(AstIdentifierFlagsE::MacroInjectCallerBinding);
        }

        if (!shouldReexpand &&
            resolvedRef.isValid() &&
            resolvedRef != sourceRef &&
            !sourceHasImplicitCastSubstitute &&
            !activeSourceRefSet.contains(resolvedRef))
        {
            const AstNodeRef clonedResolvedRef = cloneDetachedExprImpl(sema, resolvedRef, needsReanalysis);
            sema.setSubstitute(clonedRef, clonedResolvedRef);
        }

        SmallVector<AstNodeRef> sourceChildren;
        SmallVector<AstNodeRef> clonedChildren;
        sema.node(sourceRef).collectChildrenFromAst(sourceChildren, sema.ast());
        sema.node(clonedRef).collectChildrenFromAst(clonedChildren, sema.ast());
        SWC_ASSERT(sourceChildren.size() == clonedChildren.size());

        for (size_t i = 0; i < sourceChildren.size(); ++i)
        {
            const AstNodeRef sourceChildRef = sourceChildren[i];
            const AstNodeRef clonedChildRef = clonedChildren[i];
            if (sourceChildRef.isInvalid() || clonedChildRef.isInvalid())
                continue;

            const AstNodeRef resolvedChildRef                     = sema.resolvedNodeRef(sourceChildRef);
            const bool       shouldReexpandChild                  = shouldReexpandDetachedExpr(sema, sourceChildRef, resolvedChildRef);
            const bool       sourceChildHasImplicitCastSubstitute = isImplicitCastSubstitute(sema, sourceChildRef, resolvedChildRef);
            if (!shouldReexpandChild && !sourceChildHasImplicitCastSubstitute)
                sema.inheritPayload(sema.node(clonedChildRef), sourceChildRef);
            else if (!shouldReexpandChild && sourceChildHasImplicitCastSubstitute)
            {
                if (sema.hasSubstitute(clonedChildRef))
                    inheritStoredPayloadUnderSubstitute(sema, clonedChildRef, sourceChildRef);
                else
                    inheritStoredPayload(sema, clonedChildRef, sourceChildRef);
            }

            if (!shouldReexpandChild &&
                resolvedChildRef.isValid() &&
                resolvedChildRef != sourceChildRef &&
                !sourceChildHasImplicitCastSubstitute &&
                !activeSourceRefSet.contains(resolvedChildRef))
            {
                const AstNodeRef clonedResolvedChildRef = cloneDetachedExprImpl(sema, resolvedChildRef, needsReanalysis);
                sema.setSubstitute(clonedChildRef, clonedResolvedChildRef);
                continue;
            }

            copyDetachedBindingExprState(sema, sourceChildRef, clonedChildRef, activeSourceRefSet, needsReanalysis);
        }

        activeSourceRefSet.erase(sourceRef);
    }

    AstNodeRef cloneIdentifier(Sema& sema, const AstIdentifier& node, const SemaClone::CloneContext& cloneContext)
    {
        const Ast* sourceAst = &cloneSourceAst(sema, cloneContext);
        AstNodeRef sourceRef = sourceAst->tryFindNodeRef(&node);
        if (sourceRef.isInvalid() && sourceAst != &sema.ast())
        {
            sourceAst = &sema.ast();
            sourceRef = sourceAst->tryFindNodeRef(&node);
        }

        const std::optional<NodePayload::StoredView> storedView = sourceStoredView(sema, sourceAst, sourceRef);

        // A cloned identifier's codeRef can name a token that does not exist in its source view (a
        // synthetic node carries a borrowed/out-of-range token location). Reading such a token is an
        // out-of-bounds access, so only consult the source token when its location is in range;
        // otherwise the node's resolved symbol below is the authoritative identifier.
        const SourceCodeRef nodeCodeRef    = node.codeRef();
        const bool          nodeTokInRange = nodeCodeRef.isValid() && nodeCodeRef.tokRef.get() < sema.ctx().compiler().srcView(nodeCodeRef.srcViewRef).tokens().size();

        IdentifierRef idRef = IdentifierRef::invalid();
        if (nodeTokInRange && sema.token(nodeCodeRef).id == TokenId::Identifier)
            idRef = sema.idMgr().addIdentifier(sema.ctx(), nodeCodeRef);
        if (!idRef.isValid() && storedView && storedView->sym)
            idRef = storedView->sym->idRef();
        if (!idRef.isValid() && nodeTokInRange)
            idRef = sema.idMgr().addIdentifier(sema.ctx(), nodeCodeRef);

        const SemaInlinePayload* sourceInlinePayload = nullptr;
        if (sourceRef.isValid() && sourceAst == &sema.ast())
            sourceInlinePayload = sema.inlinePayload(sourceRef);

        const SemaClone::ParamBinding* binding = findBinding(cloneContext, idRef, storedView ? storedView->sym : nullptr, sourceInlinePayload);

        // A nested callable is a function of its own, with a frame of its own: an expression
        // the expansion bound to this name lives in the caller's frame and cannot be read from
        // inside it. A constant crosses that boundary as a value, and a '#code' block through
        // '#inject'; anything else is reported here, where the read is met, rather than left to
        // address the caller's frame from another function.
        if (binding &&
            cloneContext.nestedCallableDepth != 0 &&
            binding->exprRef.isValid() &&
            binding->cstRef.isInvalid() &&
            !(binding->sourceParam && binding->sourceParam->type(sema.ctx()).isCodeBlock()) &&
            !sema.viewConstant(binding->exprRef).hasConstant())
        {
            const SourceCodeRef errorRef = nodeTokInRange ? nodeCodeRef : sema.curNode().codeRef();
            auto                diag     = SemaError::report(sema, DiagnosticId::sema_err_local_function_expansion_parameter, errorRef);
            diag.addArgument(Diagnostic::ARG_SYM, sema.idMgr().get(binding->idRef).name);

            // The expansion has no payload yet while its body is being cloned, so the call it
            // comes from is named here rather than by the usual expansion chain.
            const Symbol* calleeSym = sema.viewSymbol(sema.curNodeRef()).sym();
            if (const auto* callee = calleeSym ? calleeSym->safeCast<SymbolFunction>() : nullptr)
            {
                const bool isMacro = callee->attributes().hasRtFlag(RtAttributeFlagsE::Macro);
                const bool isMixin = callee->attributes().hasRtFlag(RtAttributeFlagsE::Mixin);
                diag.addNote(DiagnosticId::sema_note_expansion_invoked_here);
                diag.last().addArgument(Diagnostic::ARG_WHAT, isMacro ? "macro" : isMixin ? "mixin"
                                                                                          : "function");
                diag.last().addArgument(Diagnostic::ARG_SYM, callee->name(sema.ctx()));
                SemaError::addSpan(sema, diag.last(), sema.curNodeRef());
            }
            diag.report(sema.ctx());
            binding = nullptr;
        }

        if (binding)
        {
            if (binding->cstRef.isValid())
            {
                return makeConstantBindingIdentifier(sema, node, binding->typeRef, binding->cstRef, false);
            }

            if (binding->exprRef.isInvalid() && binding->typeRef.isValid())
            {
                auto [newRef, newNodePtr] = sema.ast().makeNode<AstNodeId::Identifier>(node.tokRef());
                newNodePtr->flags()       = node.flags();
                newNodePtr->addFlag(AstIdentifierFlagsE::GenericTypeBinding);
                newNodePtr->setCodeRef(node.codeRef());
                sema.setType(newRef, binding->typeRef);
                return newRef;
            }

            if (binding->typeRef.isValid() && binding->exprRef.isValid())
            {
                const SemaNodeView sourceView = sema.viewConstant(binding->exprRef);
                if (sourceView.hasConstant())
                {
                    const ConstantRef cstRef = foldImplicitCastConstant(sema, sourceView.cstRef(), binding->typeRef, AstNodeRef::invalid());
                    if (cstRef.isValid())
                        return markConstParamBindingTarget(sema, *binding, makeConstantBindingIdentifier(sema, node, binding->typeRef, cstRef, true));
                }
            }

            AstNodeRef clonedExprRef                         = AstNodeRef::invalid();
            const bool bindingNeedsContextualAutoMemberClone = binding->typeRef.isValid() && containsAutoMemberAccess(sema, binding->exprRef);
            const bool bindingNeedsReferenceStateClone       = binding->sourceParam && binding->sourceParam->type(sema.ctx()).isReference();
            if (cloneContext.preserveBindingExprState || bindingNeedsContextualAutoMemberClone || bindingNeedsReferenceStateClone || binding->valueBorrowHomeRef.isValid())
                clonedExprRef = cloneDetachedExprImpl(sema, binding->exprRef);
            else if (cloneContext.resolveBindingExprWithParentBindings)
            {
                const SemaClone::CloneContext nestedCloneContext = cloneContextAfterBinding(cloneContext, *binding);
                if (nestedCloneContext.bindings.empty() && nestedCloneContext.replacements.empty())
                    clonedExprRef = cloneExprPreservingResolvedIdentifierSymbols(sema, binding->exprRef);
                else
                    clonedExprRef = SemaClone::cloneAst(sema, binding->exprRef, nestedCloneContext);
            }
            else
                clonedExprRef = cloneExprPreservingResolvedIdentifierSymbols(sema, binding->exprRef);
            if (binding->preserveUseCodeRef && clonedExprRef.isValid())
                sema.node(clonedExprRef).setCodeRef(node.codeRef());
            if (!binding->typeRef.isValid())
            {
                if (!cloneContext.resolveBindingExprWithParentBindings)
                    setCallerInlineContextOverride(sema, clonedExprRef, *binding);
                return markConstParamBindingTarget(sema, *binding, clonedExprRef);
            }

            const AstNodeRef castRef = Cast::createCast(sema, binding->typeRef, clonedExprRef);
            if (castRef.isInvalid())
                return AstNodeRef::invalid();

            if (binding->preserveUseCodeRef)
                sema.node(castRef).setCodeRef(node.codeRef());

            foldTypedBindingConstant(sema, *binding, castRef);
            if (!cloneContext.resolveBindingExprWithParentBindings)
                setCallerInlineContextOverride(sema, castRef, *binding);

            return markConstParamBindingTarget(sema, *binding, castRef);
        }

        const bool crossAstSource    = sourceAst != &sema.ast();
        const bool pinResolvedSymbol = crossAstSource || cloneContext.preserveResolvedSymbols;
        auto [nodeRef, nodePtr]      = sema.ast().makeNode<AstNodeId::Identifier>(node.tokRef());
        nodePtr->flags()             = node.flags();
        nodePtr->setCodeRef(node.codeRef());

        // Intrinsic identifiers store the first overload; each call selects one from its
        // argument types. A folded source call may no longer carry that selection, so copying
        // its identifier's symbol could pin the clone to the wrong overload. Resolve intrinsic
        // names again; calls with a stored selection pin it afterwards.
        const auto* intrinsicFunction           = storedView && storedView->sym ? storedView->sym->safeCast<SymbolFunction>() : nullptr;
        const bool  intrinsicName               = intrinsicFunction && intrinsicFunction->intrinsicId() != TokenId::Invalid;
        const bool  sourceSymbolOwnedByFunction = storedView && storedView->sym && storedView->sym->ownerSymMap() && storedView->sym->ownerSymMap()->isFunction();

        const bool sourceFunctionLocalIdentifier = storedView &&
                                                   storedView->sym &&
                                                   storedView->sym->isFunctionLocalVariable() &&
                                                   nodeTokInRange &&
                                                   sema.token(node.codeRef()).id == TokenId::Identifier;

        const bool sourceLexicalLocalIdentifier = storedView &&
                                                  storedView->sym &&
                                                  !storedView->sym->ownerSymMap() &&
                                                  storedView->sym->isValueExpr() &&
                                                  isNonParameterVariableDecl(*storedView->sym) &&
                                                  nodeTokInRange &&
                                                  sema.token(node.codeRef()).id == TokenId::Identifier;

        const bool sourceRebindableLocalIdentifier = sourceSymbolOwnedByFunction ||
                                                     sourceFunctionLocalIdentifier ||
                                                     sourceLexicalLocalIdentifier;

        const bool sourceLocalIdentifierPinned = pinResolvedSymbol && (sourceSymbolOwnedByFunction || sourceFunctionLocalIdentifier || sourceLexicalLocalIdentifier);

        const bool preserveSyntheticSymbol = storedView && storedView->sym && !intrinsicName &&
                                             ((node.hasFlag(AstIdentifierFlagsE::PreResolvedSymbol) && !sourceLocalIdentifierPinned && !sourceRebindableLocalIdentifier) ||
                                              (!sourceLocalIdentifierPinned &&
                                               !sourceRebindableLocalIdentifier &&
                                               (!storedView->sym->isFunctionLocalVariable() ||
                                                !nodeTokInRange ||
                                                sema.token(node.codeRef()).id != TokenId::Identifier)));
        if (preserveSyntheticSymbol)
        {
            // A folded call may no longer carry its selected function. Keep the identifier's
            // complete overload set so that rechecking the cloned call can select it again.
            if (storedView->hasSymbolList)
                sema.setSymbolList(nodeRef, storedView->symList);
            else
                sema.setSymbol(nodeRef, storedView->sym);

            // Cross-AST clones and opted-in same-AST inlining must keep the source symbol:
            // destination lookup may hide it or choose another overload. Rebindable locals
            // are excluded above so they still resolve to cloned declarations or arguments.
            if (pinResolvedSymbol)
                nodePtr->addFlag(AstIdentifierFlagsE::PreResolvedSymbol);
        }

        const bool carryResolvedTypeId = storedView &&
                                         storedView->typeRef.isValid() &&
                                         !storedView->cstRef.isValid() &&
                                         (node.hasFlag(AstIdentifierFlagsE::GenericTypeBinding) || (storedView->sym && storedView->sym->isType()));

        const bool carryInline = storedView &&
                                 ((!storedView->hasSymbol && (storedView->typeRef.isValid() || storedView->cstRef.isValid())) ||
                                  carryResolvedTypeId ||
                                  (crossAstSource && storedView->cstRef.isValid()));

        if (carryInline)
        {
            // Nested generic cloning can hit identifiers that were already substituted by an
            // outer specialization pass. Preserve that pre-resolved type/constant payload so
            // later clones do not resurrect the original generic identifier, especially for
            // type-only operands such as `#sizeof(T)` that may no longer carry a direct binding.
            if (storedView->typeRef.isValid())
                sema.setType(nodeRef, storedView->typeRef);
            if (storedView->cstRef.isValid())
                sema.setConstant(nodeRef, storedView->cstRef);
            if (hasStoredFlag(*storedView, NodePayloadFlags::Value))
                sema.setIsValue(nodeRef);
            if (hasStoredFlag(*storedView, NodePayloadFlags::LValue))
                sema.setIsLValue(nodeRef);
            if (hasStoredFlag(*storedView, NodePayloadFlags::FoldedTypedConst))
                sema.setFoldedTypedConst(nodeRef);
        }

        return nodeRef;
    }

    // Pin the call's resolved overload onto the cloned callee identifier. Overload selection ran
    // against the call node, not its callee identifier (which only carries the overload set / first
    // overload), so a clone that re-resolves by name in a foreign scope (cross-Ast inline, or a
    // same-Ast inline that opted into preserving resolved symbols) can pick the wrong overload.
    // Carry the actually-selected function, mirroring copyResolvedIdentifierSymbols for the
    // semaClone-based inline path.
    void pinClonedCallResolvedFunction(Sema& sema, const SemaClone::CloneContext& cloneContext, AstNodeRef sourceCallRef, AstNodeRef clonedCalleeRef)
    {
        if (sourceCallRef.isInvalid() || clonedCalleeRef.isInvalid())
            return;

        const Ast& sourceAst         = cloneSourceAst(sema, cloneContext);
        const bool pinResolvedSymbol = (&sourceAst != &sema.ast()) || cloneContext.preserveResolvedSymbols;
        if (!pinResolvedSymbol)
            return;

        const std::optional<NodePayload::StoredView> storedView = sourceStoredView(sema, resolveCloneNodeAst(sema, sourceCallRef, cloneContext), sourceCallRef);
        if (!storedView || !storedView->sym || !storedView->sym->safeCast<SymbolFunction>())
            return;

        pinResolvedCallCallee(sema, clonedCalleeRef, storedView->sym->cast<SymbolFunction>());
    }
}

AstNodeRef SemaClone::cloneAst(Sema& sema, AstNodeRef nodeRef, const CloneContext& cloneContext)
{
    SWC_ASSERT(nodeRef.isValid());
    const Ast* sourceAst = resolveCloneNodeAst(sema, nodeRef, cloneContext);
    SWC_ASSERT(sourceAst != nullptr);
    if (!sourceAst)
        return AstNodeRef::invalid();

    auto&             node           = const_cast<AstNode&>(sourceAst->node(nodeRef));
    const SourceView* nodeSourceView = resolveCloneSourceView(sema, *sourceAst, node);
    SWC_ASSERT(nodeSourceView != nullptr);
    SourceView* previousSrcView = Ast::setThreadSourceViewOverride(const_cast<SourceView*>(nodeSourceView));

    AstNodeRef clonedRef = cloneNodeReplacement(sema, node, cloneContext);
    if (clonedRef.isValid())
    {
        Ast::setThreadSourceViewOverride(previousSrcView);
        return clonedRef;
    }

    CloneContext childCloneContext = startsNestedBreakableContext(node) ? cloneContextInsideBreakable(cloneContext) : cloneContext;
    if (const auto* castNode = node.safeCast<AstCastExpr>(); castNode && !castNode->hasFlag(AstCastExprFlagsE::Explicit))
        childCloneContext = cloneContextSuppressingImplicitCastSubstitute(childCloneContext, nodeRef);
    clonedRef = Ast::nodeIdInfos(node.id()).semaClone(sema, node, childCloneContext);
    SWC_ASSERT(clonedRef.isValid());
    if (clonedRef.isInvalid())
    {
        Ast::setThreadSourceViewOverride(previousSrcView);
        return AstNodeRef::invalid();
    }

    Ast::setThreadSourceViewOverride(previousSrcView);
    copyCallableClonePayload(sema, cloneContext, nodeRef, clonedRef);
    copyImplicitCastSubstitute(sema, cloneContext, nodeRef, clonedRef);
    copyImplicitCastPayload(sema, cloneContext, node, nodeRef, clonedRef);
    copyVarInitSpecOpPayload(sema, cloneContext, node, nodeRef, clonedRef);
    copyLoopPayload(sema, cloneContext, node, nodeRef, clonedRef);
    return clonedRef;
}

AstNodeRef SemaClone::cloneDetachedExpr(Sema& sema, AstNodeRef nodeRef, bool* needsReanalysis)
{
    if (needsReanalysis)
        *needsReanalysis = false;
    return cloneDetachedExprImpl(sema, nodeRef, needsReanalysis);
}

AstNodeRef SemaClone::cloneAstPreservingResolvedIdentifierSymbols(Sema& sema, AstNodeRef nodeRef, const CloneContext& cloneContext)
{
    if (nodeRef.isInvalid())
        return AstNodeRef::invalid();

    const AstNodeRef clonedRef = cloneAst(sema, nodeRef, cloneContext);
    if (clonedRef.isInvalid())
        return AstNodeRef::invalid();

    copyResolvedIdentifierSymbols(sema, nodeRef, clonedRef);
    return clonedRef;
}

AstNodeRef AstInvalid::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return cloneNodeCopy<AstNodeId::Invalid>(sema, *this);
}

AstNodeRef AstFile::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::File, &AstFile::spanGlobalsRef, &AstFile::spanUsingsRef, &AstFile::spanChildrenRef>(sema, *this, cloneContext);
}

AstNodeRef AstTopLevelBlock::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::TopLevelBlock, &AstTopLevelBlock::spanChildrenRef>(sema, *this, cloneContext);
}

AstNodeRef AstEmbeddedBlock::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::EmbeddedBlock>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstEmbeddedBlock>();
    cloned.flags().remove(AstEmbeddedBlockFlagsE::ImplicitCodeBlockArg);
    cloned.spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstImpl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::Impl, &AstImpl::nodeIdentRef, &AstImpl::nodeForRef, &AstImpl::spanChildrenRef>(sema, *this, cloneContext);
}

AstNodeRef AstNamespaceDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::NamespaceDecl>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstNamespaceDecl>();
    cloned.spanNameRef      = cloneTokenSpan(sema, spanNameRef, cloneContextAsInline(cloneContext));
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstUsingNamespaceStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::UsingNamespaceStmt, &AstUsingNamespaceStmt::nodeNameRef>(sema, *this, cloneContext);
}

AstNodeRef AstCompilerGlobal::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::CompilerGlobal>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstCompilerGlobal>();
    cloned.spanNameRef      = cloneTokenSpan(sema, spanNameRef, cloneContextAsInline(cloneContext));
    cloned.nodeModeRef      = cloneNodeRef(sema, nodeModeRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCompilerImport::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return cloneNodeCopy<AstNodeId::CompilerImport>(sema, *this);
}

AstNodeRef AstFunctionBody::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::FunctionBody, &AstFunctionBody::spanChildrenRef>(sema, *this, cloneContext);
}

AstNodeRef AstAttribute::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::Attribute, &AstAttribute::nodeCallRef>(sema, *this, cloneContext);
}

AstNodeRef AstAttributeList::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::AttributeList, &AstAttributeList::spanChildrenRef, &AstAttributeList::nodeBodyRef>(sema, *this, cloneContext);
}

AstNodeRef AstUsingDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::UsingDecl, &AstUsingDecl::spanChildrenRef>(sema, *this, cloneContext);
}

AstNodeRef AstAccessModifier::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::AccessModifier, &AstAccessModifier::nodeWhatRef>(sema, *this, cloneContext);
}

AstNodeRef AstAttrDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::AttrDecl, &AstAttrDecl::nodeParamsRef>(sema, *this, cloneContext);
}

AstNodeRef AstFunctionDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const auto&      inlineContext = cloneContextAsInline(cloneContext);
    const AstNodeRef newRef        = cloneNodeCopy<AstNodeId::FunctionDecl>(sema, *this);
    auto&            cloned        = sema.node(newRef).cast<AstFunctionDecl>();
    if (inlineContext.preserveFunctionGenerics)
    {
        cloned.spanGenericParamsRef = cloneSpan(sema, spanGenericParamsRef, inlineContext);
        cloned.spanConstraintsRef   = cloneSpan(sema, spanConstraintsRef, inlineContext);
    }
    else
    {
        cloned.spanGenericParamsRef = SpanRef::invalid();
        cloned.spanConstraintsRef   = SpanRef::invalid();
    }

    // A local function's own parameters shadow the expansion's bindings of the same name
    // throughout the function: its signature and its body resolve those names to the
    // parameters, never to the caller's arguments.
    SmallVector<IdentifierRef>           parameterIdentifiers;
    SmallVector<SemaClone::ParamBinding> ownBindings;
    if (!inlineContext.bindings.empty())
    {
        if (const Ast* paramsAst = resolveCloneNodeAst(sema, nodeParamsRef, inlineContext))
            collectCallableParameterIdentifiers(sema, *paramsAst, nodeParamsRef, SpanRef::invalid(), parameterIdentifiers);
        excludeNamedBindings(ownBindings, inlineContext.bindings, parameterIdentifiers.span());
    }
    SemaClone::CloneContext ownContext = cloneContextWithBindings(inlineContext, ownBindings.span());
    ownContext.nestedCallableDepth     = inlineContext.nestedCallableDepth + 1;

    cloned.nodeParamsRef     = cloneNodeRef(sema, nodeParamsRef, ownContext);
    cloned.nodeReturnTypeRef = cloneNodeRef(sema, nodeReturnTypeRef, ownContext);
    cloned.nodeBodyRef       = cloneNodeRef(sema, nodeBodyRef, ownContext);
    return newRef;
}

AstNodeRef AstFunctionParamList::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::FunctionParamList, &AstFunctionParamList::spanChildrenRef>(sema, *this, cloneContext);
}

AstNodeRef AstFunctionParamMe::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return cloneNodeCopy<AstNodeId::FunctionParamMe>(sema, *this);
}

AstNodeRef AstVarDeclList::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::VarDeclList, &AstVarDeclList::spanChildrenRef>(sema, *this, cloneContext);
}

AstNodeRef AstElseStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::ElseStmt, &AstElseStmt::spanChildrenRef>(sema, *this, cloneContext);
}

AstNodeRef AstElseIfStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::ElseIfStmt, &AstElseIfStmt::spanChildrenRef>(sema, *this, cloneContext);
}

AstNodeRef AstSwitchCaseBody::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::SwitchCaseBody, &AstSwitchCaseBody::spanChildrenRef>(sema, *this, cloneContext);
}

AstNodeRef AstAssignList::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef        = cloneNodeCopy<AstNodeId::AssignList>(sema, *this);
    auto&            cloned        = sema.node(newRef).cast<AstAssignList>();
    const auto       inlineContext = cloneContextAsInline(cloneContext);
    cloned.spanChildrenRef         = cloneSpan(sema, spanChildrenRef, inlineContext);
    cloned.spanFieldNamesRef       = cloneTokenSpan(sema, spanFieldNamesRef, inlineContext);
    return newRef;
}

AstNodeRef AstAssignIgnore::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return cloneNodeCopy<AstNodeId::AssignIgnore>(sema, *this);
}

AstNodeRef AstReturnStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::ReturnStmt, &AstReturnStmt::nodeExprRef>(sema, *this, cloneContext);
}

AstNodeRef AstSingleVarDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::SingleVarDecl, &AstSingleVarDecl::nodeTypeRef, &AstSingleVarDecl::nodeInitRef>(sema, *this, cloneContext);
}

AstNodeRef AstMultiVarDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::MultiVarDecl>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstMultiVarDecl>();
    cloned.spanNamesRef     = cloneTokenSpan(sema, spanNamesRef, cloneContextAsInline(cloneContext));
    cloned.nodeTypeRef      = cloneNodeRef(sema, nodeTypeRef, cloneContextAsInline(cloneContext));
    cloned.nodeInitRef      = cloneNodeRef(sema, nodeInitRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstVarDeclDestructuring::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef        = cloneNodeCopy<AstNodeId::VarDeclDestructuring>(sema, *this);
    auto&            cloned        = sema.node(newRef).cast<AstVarDeclDestructuring>();
    const auto       inlineContext = cloneContextAsInline(cloneContext);
    cloned.spanNamesRef            = cloneTokenSpan(sema, spanNamesRef, inlineContext);
    cloned.nodePatternRef          = cloneNodeRef(sema, nodePatternRef, inlineContext);
    cloned.nodeInitRef             = cloneNodeRef(sema, nodeInitRef, inlineContext);
    return newRef;
}

AstNodeRef AstAssignStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::AssignStmt, &AstAssignStmt::nodeLeftRef, &AstAssignStmt::nodeRightRef>(sema, *this, cloneContext);
}

AstNodeRef AstIfStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::IfStmt, &AstIfStmt::nodeConditionRef, &AstIfStmt::nodeIfBlockRef, &AstIfStmt::nodeElseBlockRef>(sema, *this, cloneContext);
}

AstNodeRef AstIfVarDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::IfVarDecl, &AstIfVarDecl::nodeVarRef, &AstIfVarDecl::nodeWhereRef, &AstIfVarDecl::nodeIfBlockRef, &AstIfVarDecl::nodeElseBlockRef>(sema, *this, cloneContext);
}

AstNodeRef AstWithStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::WithStmt, &AstWithStmt::nodeExprRef, &AstWithStmt::nodeBodyRef>(sema, *this, cloneContext);
}

AstNodeRef AstWithVarDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::WithVarDecl, &AstWithVarDecl::nodeVarRef, &AstWithVarDecl::nodeBodyRef>(sema, *this, cloneContext);
}

AstNodeRef AstDeferStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::DeferStmt, &AstDeferStmt::nodeBodyRef>(sema, *this, cloneContext);
}

AstNodeRef AstWhileStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::WhileStmt, &AstWhileStmt::nodeExprRef, &AstWhileStmt::nodeBodyRef>(sema, *this, cloneContext);
}

AstNodeRef AstForeachStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::ForeachStmt>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstForeachStmt>();
    cloned.spanNamesRef     = cloneTokenSpan(sema, spanNamesRef, cloneContextAsInline(cloneContext));
    cloned.nodeExprRef      = cloneNodeRef(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    cloned.nodeWhereRef     = cloneNodeRef(sema, nodeWhereRef, cloneContextAsInline(cloneContext));
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstForCStyleStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::ForCStyleStmt, &AstForCStyleStmt::nodeVarDeclRef, &AstForCStyleStmt::nodeExprRef, &AstForCStyleStmt::nodePostStmtRef, &AstForCStyleStmt::nodeBodyRef>(sema, *this, cloneContext);
}

AstNodeRef AstForStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::ForStmt>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstForStmt>();
    cloned.spanNamesRef     = cloneTokenSpan(sema, spanNamesRef, cloneContextAsInline(cloneContext));
    cloned.nodeExprRef      = cloneNodeRef(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    cloned.nodeWhereRef     = cloneNodeRef(sema, nodeWhereRef, cloneContextAsInline(cloneContext));
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstParallelForStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::ParallelForStmt, &AstParallelForStmt::nodeBeginRef, &AstParallelForStmt::nodeEndRef, &AstParallelForStmt::nodeClosureRef>(sema, *this, cloneContext);
}

AstNodeRef AstInfiniteLoopStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::InfiniteLoopStmt, &AstInfiniteLoopStmt::nodeBodyRef>(sema, *this, cloneContext);
}

AstNodeRef AstErrorManagementStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::ErrorManagementStmt>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstErrorManagementStmt>();
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    cloned.nodeCaptureRef   = cloneNodeRef(sema, nodeCaptureRef, cloneContextAsInline(cloneContext));
    if (nodeHandlerRef.isValid())
        cloned.nodeHandlerRef = cloneNodeRef(sema, nodeHandlerRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstUnreachableStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return cloneNodeCopy<AstNodeId::UnreachableStmt>(sema, *this);
}

AstNodeRef AstContinueStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return cloneNodeCopy<AstNodeId::ContinueStmt>(sema, *this);
}

AstNodeRef AstBreakStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return cloneNodeCopy<AstNodeId::BreakStmt>(sema, *this);
}

AstNodeRef AstScopedBreakStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return cloneNodeCopy<AstNodeId::ScopedBreakStmt>(sema, *this);
}

AstNodeRef AstFallThroughStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return cloneNodeCopy<AstNodeId::FallThroughStmt>(sema, *this);
}

AstNodeRef AstSwitchStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::SwitchStmt, &AstSwitchStmt::nodeExprRef, &AstSwitchStmt::spanChildrenRef>(sema, *this, cloneContext);
}

AstNodeRef AstSwitchCaseStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::SwitchCaseStmt, &AstSwitchCaseStmt::nodeWhereRef, &AstSwitchCaseStmt::spanExprRef, &AstSwitchCaseStmt::nodeBodyRef>(sema, *this, cloneContext);
}

AstNodeRef AstCompilerExpression::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::CompilerExpression, &AstCompilerExpression::nodeExprRef>(sema, *this, cloneContext);
}

AstNodeRef AstCompilerIf::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::CompilerIf, &AstCompilerIf::nodeConditionRef, &AstCompilerIf::nodeIfBlockRef, &AstCompilerIf::nodeElseBlockRef>(sema, *this, cloneContext);
}

AstNodeRef AstCompilerSwitch::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::CompilerSwitch, &AstCompilerSwitch::nodeExprRef, &AstCompilerSwitch::spanCasesRef>(sema, *this, cloneContext);
}

AstNodeRef AstCompilerSwitchCase::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::CompilerSwitchCase, &AstCompilerSwitchCase::spanExprRef, &AstCompilerSwitchCase::nodeBodyRef>(sema, *this, cloneContext);
}

AstNodeRef AstScopeStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::ScopeStmt, &AstScopeStmt::nodeBodyRef>(sema, *this, cloneContext);
}

AstNodeRef AstCompilerRunBlock::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::CompilerRunBlock, &AstCompilerRunBlock::nodeBodyRef>(sema, *this, cloneContext);
}

AstNodeRef AstCompilerCodeBlock::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef   = cloneNodeCopy<AstNodeId::CompilerCodeBlock>(sema, *this);
    auto&            cloned   = sema.node(newRef).cast<AstCompilerCodeBlock>();
    cloned.nodeBodyRef        = cloneCodeNodeRefWithoutReplacements(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    cloned.payloadTypeRef     = payloadTypeRef;
    cloned.spanBinderNamesRef = cloneTokenSpan(sema, spanBinderNamesRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCompilerShortFunc::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::CompilerShortFunc, &AstCompilerShortFunc::nodeBodyRef, &AstCompilerShortFunc::spanPartsRef>(sema, *this, cloneContext);
}

AstNodeRef AstCompilerFunc::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::CompilerFunc, &AstCompilerFunc::nodeBodyRef>(sema, *this, cloneContext);
}

AstNodeRef AstCompilerMessageFunc::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::CompilerMessageFunc, &AstCompilerMessageFunc::nodeParamRef, &AstCompilerMessageFunc::nodeBodyRef>(sema, *this, cloneContext);
}

AstNodeRef AstCompilerInject::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef          = cloneNodeCopy<AstNodeId::CompilerInject>(sema, *this);
    auto&            cloned          = sema.node(newRef).cast<AstCompilerInject>();
    cloned.nodeExprRef               = cloneNodeRef(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    cloned.spanReplaceInstructionRef = cloneTokenSpan(sema, spanReplaceInstructionRef, cloneContextAsInline(cloneContext));
    cloned.spanReplaceNodeRef        = cloneSpanWithoutReplacements(sema, spanReplaceNodeRef, cloneContextAsInline(cloneContext));
    cloned.spanBindingNameRef        = cloneTokenSpan(sema, spanBindingNameRef, cloneContextAsInline(cloneContext));
    cloned.spanBindingNodeRef        = cloneSpanWithoutReplacements(sema, spanBindingNodeRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstBoolLiteral::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return sema.ast().makeNode<AstNodeId::BoolLiteral>(tokRef()).first;
}

AstNodeRef AstCharacterLiteral::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return sema.ast().makeNode<AstNodeId::CharacterLiteral>(tokRef()).first;
}

AstNodeRef AstFloatLiteral::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return sema.ast().makeNode<AstNodeId::FloatLiteral>(tokRef()).first;
}

AstNodeRef AstIntegerLiteral::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return sema.ast().makeNode<AstNodeId::IntegerLiteral>(tokRef()).first;
}

AstNodeRef AstBinaryLiteral::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return sema.ast().makeNode<AstNodeId::BinaryLiteral>(tokRef()).first;
}

AstNodeRef AstHexaLiteral::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return sema.ast().makeNode<AstNodeId::HexaLiteral>(tokRef()).first;
}

AstNodeRef AstNullLiteral::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return sema.ast().makeNode<AstNodeId::NullLiteral>(tokRef()).first;
}

AstNodeRef AstStringLiteral::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return sema.ast().makeNode<AstNodeId::StringLiteral>(tokRef()).first;
}

AstNodeRef AstCompilerLiteral::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return sema.ast().makeNode<AstNodeId::CompilerLiteral>(tokRef()).first;
}

AstNodeRef AstCompilerDiagnostic::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::CompilerDiagnostic>(tokRef());
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCompilerCallOne::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::CompilerCallOne>(tokRef());
    newPtr->nodeArgRef    = SemaClone::cloneAst(sema, nodeArgRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCompilerCall::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::CompilerCall>(tokRef());
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstIntrinsicCall::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::IntrinsicCall>(tokRef());
    newPtr->intrinsicId     = intrinsicId;
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstIntrinsicCallVariadic::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::IntrinsicCallVariadic, &AstIntrinsicCallVariadic::spanChildrenRef>(sema, *this, cloneContext);
}

AstNodeRef AstIntrinsicInit::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const auto& inlineContext = cloneContextAsInline(cloneContext);
    auto [newRef, newPtr]     = sema.ast().makeNode<AstNodeId::IntrinsicInit>(tokRef());
    newPtr->nodeWhatRef       = cloneNodeRef(sema, nodeWhatRef, inlineContext);
    newPtr->nodeCountRef      = cloneNodeRef(sema, nodeCountRef, inlineContext);
    newPtr->spanArgsRef       = cloneSpan(sema, spanArgsRef, inlineContext);
    return newRef;
}

AstNodeRef AstIntrinsicDrop::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const auto& inlineContext = cloneContextAsInline(cloneContext);
    auto [newRef, newPtr]     = sema.ast().makeNode<AstNodeId::IntrinsicDrop>(tokRef());
    newPtr->nodeWhatRef       = cloneNodeRef(sema, nodeWhatRef, inlineContext);
    newPtr->nodeCountRef      = cloneNodeRef(sema, nodeCountRef, inlineContext);
    return newRef;
}

AstNodeRef AstIntrinsicPostCopy::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const auto& inlineContext = cloneContextAsInline(cloneContext);
    auto [newRef, newPtr]     = sema.ast().makeNode<AstNodeId::IntrinsicPostCopy>(tokRef());
    newPtr->nodeWhatRef       = cloneNodeRef(sema, nodeWhatRef, inlineContext);
    newPtr->nodeCountRef      = cloneNodeRef(sema, nodeCountRef, inlineContext);
    return newRef;
}

AstNodeRef AstIntrinsicPostMove::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const auto& inlineContext = cloneContextAsInline(cloneContext);
    auto [newRef, newPtr]     = sema.ast().makeNode<AstNodeId::IntrinsicPostMove>(tokRef());
    newPtr->nodeWhatRef       = cloneNodeRef(sema, nodeWhatRef, inlineContext);
    newPtr->nodeCountRef      = cloneNodeRef(sema, nodeCountRef, inlineContext);
    return newRef;
}

AstNodeRef AstAliasDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::AliasDecl, &AstAliasDecl::nodeExprRef>(sema, *this, cloneContext);
}

AstNodeRef AstParenExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::ParenExpr>(tokRef());
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstUnaryExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::UnaryExpr>(tokRef());
    newPtr->setCodeRef(codeRef());
    newPtr->nodeExprRef = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCountOfExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::CountOfExpr>(tokRef());
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstDiscardExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::DiscardExpr, &AstDiscardExpr::spanExprRef>(sema, *this, cloneContext);
}

AstNodeRef AstErrorManagementExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]  = sema.ast().makeNode<AstNodeId::ErrorManagementExpr>(tokRef());
    newPtr->nodeExprRef    = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    newPtr->errNameTokRef  = errNameTokRef;
    newPtr->nodeCaptureRef = cloneNodeRef(sema, nodeCaptureRef, cloneContextAsInline(cloneContext));
    if (nodeFallbackRef.isValid())
        newPtr->nodeFallbackRef = SemaClone::cloneAst(sema, nodeFallbackRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstFailExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::FailExpr>(tokRef());
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstIdentifier::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneIdentifier(sema, *this, cloneContextAsInline(cloneContext));
}

AstNodeRef AstFunctionExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const auto& inlineContext = cloneContextAsInline(cloneContext);

    // A lambda's own parameters shadow the expansion's bindings of the same name, exactly as
    // a local function's do.
    SmallVector<IdentifierRef>           parameterIdentifiers;
    SmallVector<SemaClone::ParamBinding> ownBindings;
    if (!inlineContext.bindings.empty())
    {
        if (const Ast* argsAst = resolveCloneSpanAst(sema, spanArgsRef, inlineContext))
            collectCallableParameterIdentifiers(sema, *argsAst, AstNodeRef::invalid(), spanArgsRef, parameterIdentifiers);
        excludeNamedBindings(ownBindings, inlineContext.bindings, parameterIdentifiers.span());
    }
    SemaClone::CloneContext ownContext = cloneContextWithBindings(inlineContext, ownBindings.span());
    ownContext.nestedCallableDepth     = inlineContext.nestedCallableDepth + 1;

    auto [newRef, newPtr]     = sema.ast().makeNode<AstNodeId::FunctionExpr>(tokRef());
    newPtr->flags()           = flags();
    newPtr->spanArgsRef       = cloneSpan(sema, spanArgsRef, ownContext);
    newPtr->nodeReturnTypeRef = cloneNodeRef(sema, nodeReturnTypeRef, ownContext);
    newPtr->nodeBodyRef       = SemaClone::cloneAst(sema, nodeBodyRef, ownContext);
    return newRef;
}

AstNodeRef AstClosureExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const auto& inlineContext  = cloneContextAsInline(cloneContext);
    auto [newRef, newPtr]      = sema.ast().makeNode<AstNodeId::ClosureExpr>(tokRef());
    newPtr->flags()            = flags();
    newPtr->parallelBody       = parallelBody;
    newPtr->nodeCaptureArgsRef = cloneSpan(sema, nodeCaptureArgsRef, inlineContext);
    newPtr->spanArgsRef        = cloneSpan(sema, spanArgsRef, inlineContext);
    newPtr->nodeReturnTypeRef  = cloneNodeRef(sema, nodeReturnTypeRef, inlineContext);

    // The captures are caller-side names the expansion binds; the body then owns what it
    // captured and what its own parameters declare, so neither is substituted inside it.
    SmallVector<SemaClone::ParamBinding> capturedBindings;
    excludeCapturedClosureBindings(sema, *this, inlineContext, capturedBindings);
    SmallVector<IdentifierRef>           parameterIdentifiers;
    SmallVector<SemaClone::ParamBinding> bodyBindings;
    if (!capturedBindings.empty())
    {
        if (const Ast* argsAst = resolveCloneSpanAst(sema, spanArgsRef, inlineContext))
            collectCallableParameterIdentifiers(sema, *argsAst, AstNodeRef::invalid(), spanArgsRef, parameterIdentifiers);
        excludeNamedBindings(bodyBindings, capturedBindings.span(), parameterIdentifiers.span());
    }
    SemaClone::CloneContext bodyContext = cloneContextWithBindings(inlineContext, bodyBindings.span());
    bodyContext.nestedCallableDepth     = inlineContext.nestedCallableDepth + 1;
    newPtr->nodeBodyRef                 = SemaClone::cloneAst(sema, nodeBodyRef, bodyContext);
    return newRef;
}

AstNodeRef AstClosureArgument::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]     = sema.ast().makeNode<AstNodeId::ClosureArgument>(tokRef());
    newPtr->flags()           = flags();
    newPtr->tokAliasNameRef   = tokAliasNameRef;
    newPtr->nodeIdentifierRef = SemaClone::cloneAst(sema, nodeIdentifierRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstLambdaParam::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]       = sema.ast().makeNode<AstNodeId::LambdaParam>(tokRef());
    newPtr->flags()             = flags();
    newPtr->nodeTypeRef         = cloneNodeRef(sema, nodeTypeRef, cloneContextAsInline(cloneContext));
    newPtr->nodeDefaultValueRef = cloneNodeRef(sema, nodeDefaultValueRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstLambdaType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]     = sema.ast().makeNode<AstNodeId::LambdaType>(tokRef());
    newPtr->flags()           = flags();
    newPtr->spanParamsRef     = cloneSpan(sema, spanParamsRef, cloneContextAsInline(cloneContext));
    newPtr->nodeReturnTypeRef = cloneNodeRef(sema, nodeReturnTypeRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstBinaryExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::BinaryExpr>(tokRef());
    newPtr->modifierFlags = modifierFlags;
    newPtr->nodeLeftRef   = SemaClone::cloneAst(sema, nodeLeftRef, cloneContextAsInline(cloneContext));
    newPtr->nodeRightRef  = SemaClone::cloneAst(sema, nodeRightRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstLogicalExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::LogicalExpr>(tokRef());
    newPtr->nodeLeftRef   = SemaClone::cloneAst(sema, nodeLeftRef, cloneContextAsInline(cloneContext));
    newPtr->nodeRightRef  = SemaClone::cloneAst(sema, nodeRightRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstRelationalExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::RelationalExpr>(tokRef());
    newPtr->nodeLeftRef   = SemaClone::cloneAst(sema, nodeLeftRef, cloneContextAsInline(cloneContext));
    newPtr->nodeRightRef  = SemaClone::cloneAst(sema, nodeRightRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstNullCoalescingExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::NullCoalescingExpr>(tokRef());
    newPtr->nodeLeftRef   = SemaClone::cloneAst(sema, nodeLeftRef, cloneContextAsInline(cloneContext));
    newPtr->nodeRightRef  = SemaClone::cloneAst(sema, nodeRightRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstOptionalChainExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::OptionalChainExpr>(tokRef());
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstConditionalExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::ConditionalExpr>(tokRef());
    newPtr->nodeCondRef   = SemaClone::cloneAst(sema, nodeCondRef, cloneContextAsInline(cloneContext));
    newPtr->nodeTrueRef   = SemaClone::cloneAst(sema, nodeTrueRef, cloneContextAsInline(cloneContext));
    newPtr->nodeFalseRef  = SemaClone::cloneAst(sema, nodeFalseRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstRangeExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::RangeExpr>(tokRef());
    newPtr->flags()         = flags();
    newPtr->nodeExprDownRef = cloneNodeRef(sema, nodeExprDownRef, cloneContextAsInline(cloneContext));
    newPtr->nodeExprUpRef   = cloneNodeRef(sema, nodeExprUpRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstIndexExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::IndexExpr>(tokRef());
    newPtr->nodeExprRef   = cloneNodeRef(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    newPtr->nodeArgRef    = cloneNodeRef(sema, nodeArgRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstIndexListExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::IndexListExpr>(tokRef());
    newPtr->nodeExprRef     = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstStructInitializerList::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::StructInitializerList>(tokRef());
    newPtr->nodeWhatRef   = SemaClone::cloneAst(sema, nodeWhatRef, cloneContextAsInline(cloneContext));
    newPtr->spanArgsRef   = cloneSpan(sema, spanArgsRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCallExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const auto& inlineContext = cloneContextAsInline(cloneContext);
    auto [newRef, newPtr]     = sema.ast().makeNode<AstNodeId::CallExpr>(tokRef());
    newPtr->flags()           = flags();
    newPtr->nodeExprRef       = SemaClone::cloneAst(sema, nodeExprRef, inlineContext);
    newPtr->spanChildrenRef   = cloneSpan(sema, spanChildrenRef, inlineContext);
    pinClonedCallResolvedFunction(sema, inlineContext, nodeRef(cloneSourceAst(sema, inlineContext)), newPtr->nodeExprRef);
    return newRef;
}

AstNodeRef AstIntrinsicCallExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const auto& inlineContext = cloneContextAsInline(cloneContext);
    auto [newRef, newPtr]     = sema.ast().makeNode<AstNodeId::IntrinsicCallExpr>(tokRef());
    newPtr->intrinsicId       = intrinsicId;
    newPtr->flags()           = flags();
    newPtr->nodeExprRef       = SemaClone::cloneAst(sema, nodeExprRef, inlineContext);
    newPtr->spanChildrenRef   = cloneSpan(sema, spanChildrenRef, inlineContext);
    // Type-overloaded intrinsics (Swag.min/Swag.max/...) pick a per-type overload by argument types. When
    // the body is inlined, typed parameters become the (possibly untyped-literal) call arguments,
    // so re-selection in the destination can land on a different overload. Pin the overload the
    // intrinsic actually resolved to, mirroring the regular-call path.
    pinClonedCallResolvedFunction(sema, inlineContext, nodeRef(cloneSourceAst(sema, inlineContext)), newPtr->nodeExprRef);
    return newRef;
}

AstNodeRef AstNamedArgument::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::NamedArgument>(tokRef());
    newPtr->nodeArgRef    = SemaClone::cloneAst(sema, nodeArgRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstUnnamedArgument::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return sema.ast().makeNode<AstNodeId::UnnamedArgument>(tokRef()).first;
}

AstNodeRef AstNamedArgumentList::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::NamedArgumentList>(tokRef());
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstUnnamedArgumentList::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::UnnamedArgumentList>(tokRef());
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstAutoMemberAccessExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::AutoMemberAccessExpr>(tokRef());
    newPtr->setCodeRef(codeRef());
    newPtr->flags()      = flags();
    newPtr->nodeIdentRef = cloneNodeRefWithoutBindings(sema, nodeIdentRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstMemberAccessExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::MemberAccessExpr>(tokRef());
    newPtr->setCodeRef(codeRef());
    newPtr->flags()      = flags();
    newPtr->nodeLeftRef  = SemaClone::cloneAst(sema, nodeLeftRef, cloneContextAsInline(cloneContext));
    newPtr->nodeRightRef = cloneMemberSelector(sema, nodeRightRef, cloneContextAsInline(cloneContext));
    newPtr->projectionId = projectionId;
    return newRef;
}

AstNodeRef AstQualifiedType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::QualifiedType, &AstQualifiedType::nodeTypeRef>(sema, *this, cloneContext);
}

AstNodeRef AstMoveRefType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::MoveRefType, &AstMoveRefType::nodePointeeTypeRef>(sema, *this, cloneContext);
}

AstNodeRef AstValuePointerType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::ValuePointerType, &AstValuePointerType::nodePointeeTypeRef>(sema, *this, cloneContext);
}

AstNodeRef AstBlockPointerType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::BlockPointerType, &AstBlockPointerType::nodePointeeTypeRef>(sema, *this, cloneContext);
}

AstNodeRef AstSliceType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::SliceType, &AstSliceType::nodePointeeTypeRef>(sema, *this, cloneContext);
}

AstNodeRef AstArrayType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::ArrayType, &AstArrayType::spanDimensionsRef, &AstArrayType::nodePointeeTypeRef>(sema, *this, cloneContext);
}

AstNodeRef AstSimdType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::SimdType, &AstSimdType::nodeArrayTypeRef>(sema, *this, cloneContext);
}

AstNodeRef AstNamedType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::NamedType, &AstNamedType::nodeIdentRef>(sema, *this, cloneContext);
}

AstNodeRef AstBuiltinType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return cloneNodeCopy<AstNodeId::BuiltinType>(sema, *this);
}

AstNodeRef AstCurrentReturnType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return cloneNodeCopy<AstNodeId::CurrentReturnType>(sema, *this);
}

AstNodeRef AstVariadicType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return cloneNodeCopy<AstNodeId::VariadicType>(sema, *this);
}

AstNodeRef AstTypedVariadicType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::TypedVariadicType, &AstTypedVariadicType::nodeTypeRef>(sema, *this, cloneContext);
}

AstNodeRef AstCodeType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::CodeType, &AstCodeType::nodeTypeRef, &AstCodeType::spanParamsRef>(sema, *this, cloneContext);
}

AstNodeRef AstCodeParam::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::CodeParam, &AstCodeParam::nodeTypeRef>(sema, *this, cloneContext);
}

AstNodeRef AstQuotedExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::QuotedExpr>(tokRef());
    newPtr->nodeExprRef   = cloneNodeRefWithoutReplacements(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    newPtr->nodeSuffixRef = cloneNodeRefWithoutReplacements(sema, nodeSuffixRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstQuotedListExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]     = sema.ast().makeNode<AstNodeId::QuotedListExpr>(tokRef());
    const auto noReplacements = cloneContextWithoutReplacements(cloneContextAsInline(cloneContext));
    newPtr->nodeExprRef       = SemaClone::cloneAst(sema, nodeExprRef, noReplacements);
    newPtr->spanChildrenRef   = cloneSpan(sema, spanChildrenRef, noReplacements);
    return newRef;
}

AstNodeRef AstGenericParamList::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::GenericParamList, &AstGenericParamList::spanChildrenRef>(sema, *this, cloneContext);
}

AstNodeRef AstGenericParamValue::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::GenericParamValue, &AstGenericParamValue::nodeTypeRef, &AstGenericParamValue::nodeAssignRef>(sema, *this, cloneContext);
}

AstNodeRef AstGenericParamType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::GenericParamType, &AstGenericParamType::nodeBoundRef, &AstGenericParamType::nodeAssignRef>(sema, *this, cloneContext);
}

AstNodeRef AstCastExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const auto& inlineContext = cloneContextAsInline(cloneContext);
    auto [newRef, newPtr]     = sema.ast().makeNode<AstNodeId::CastExpr>(tokRef());
    newPtr->flags()           = flags();
    newPtr->modifierFlags     = modifierFlags;
    newPtr->nodeTypeRef       = cloneNodeRef(sema, nodeTypeRef, inlineContext);
    newPtr->nodeExprRef       = SemaClone::cloneAst(sema, nodeExprRef, inlineContext);
    // A synthesized type-pinning cast (createCastNode) has no type AST: its target type
    // lives in the node payload only. Carry it onto the clone, or the pin evaporates on
    // the first re-clone and the operand re-derives without the proof the pin recorded.
    if (nodeTypeRef.isInvalid() && newPtr->nodeTypeRef.isInvalid())
    {
        const AstNodeRef                             sourceRef  = nodeRef(cloneSourceAst(sema, inlineContext));
        const std::optional<NodePayload::StoredView> storedView = sourceStoredView(sema, resolveCloneNodeAst(sema, sourceRef, inlineContext), sourceRef);
        if (storedView && storedView->typeRef.isValid())
        {
            sema.setType(newRef, storedView->typeRef);
            sema.setIsValue(sema.node(newRef));
        }
    }
    return newRef;
}

AstNodeRef AstAutoCastExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::AutoCastExpr>(tokRef());
    newPtr->modifierFlags = modifierFlags;
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstAsCastExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::AsCastExpr>(tokRef());
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    newPtr->nodeTypeRef   = cloneNodeRef(sema, nodeTypeRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstIsTypeExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::IsTypeExpr>(tokRef());
    newPtr->flags()       = flags();
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    newPtr->nodeTypeRef   = cloneNodeRef(sema, nodeTypeRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstInitializerExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::InitializerExpr>(tokRef());
    newPtr->modifierFlags = modifierFlags;
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstArrayLiteral::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::ArrayLiteral>(tokRef());
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstTupleType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::TupleType>(tokRef());
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstStructLiteral::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::StructLiteral>(tokRef());
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstStructDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    // Keep local generic declarations intact when they are cloned as part of an
    // enclosing generic/function instantiation. Actual generic struct instances
    // still clear their own generic signature in createGenericInstanceSymbol.
    return cloneNodeMembers<AstNodeId::StructDecl, &AstStructDecl::spanGenericParamsRef, &AstStructDecl::spanWhereRef, &AstStructDecl::nodeBodyRef>(sema, *this, cloneContext);
}

AstNodeRef AstInterfaceDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::InterfaceDecl, &AstInterfaceDecl::spanGenericParamsRef, &AstInterfaceDecl::spanWhereRef, &AstInterfaceDecl::nodeBaseRef, &AstInterfaceDecl::nodeBodyRef>(sema, *this, cloneContext);
}

AstNodeRef AstUnionDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::UnionDecl, &AstUnionDecl::spanGenericParamsRef, &AstUnionDecl::spanWhereRef, &AstUnionDecl::nodeTagTypeRef, &AstUnionDecl::nodeBodyRef>(sema, *this, cloneContext);
}

AstNodeRef AstAnonymousStructDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::AnonymousStructDecl, &AstAnonymousStructDecl::nodeBodyRef>(sema, *this, cloneContext);
}

AstNodeRef AstAnonymousUnionDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::AnonymousUnionDecl, &AstAnonymousUnionDecl::nodeTagTypeRef, &AstAnonymousUnionDecl::nodeBodyRef>(sema, *this, cloneContext);
}

AstNodeRef AstTaggedUnionCase::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::TaggedUnionCase, &AstTaggedUnionCase::spanValuesRef, &AstTaggedUnionCase::nodeMemberRef>(sema, *this, cloneContext);
}

AstNodeRef AstTaggedUnionLiteral::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::TaggedUnionLiteral, &AstTaggedUnionLiteral::nodePayloadRef>(sema, *this, cloneContext);
}

AstNodeRef AstAggregateBody::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::AggregateBody, &AstAggregateBody::spanChildrenRef>(sema, *this, cloneContext);
}

AstNodeRef AstInterfaceBody::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::InterfaceBody, &AstInterfaceBody::spanChildrenRef>(sema, *this, cloneContext);
}

AstNodeRef AstEnumBody::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::EnumBody, &AstEnumBody::spanChildrenRef>(sema, *this, cloneContext);
}

AstNodeRef AstEnumDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::EnumDecl, &AstEnumDecl::nodeTypeRef, &AstEnumDecl::nodeBodyRef>(sema, *this, cloneContext);
}

AstNodeRef AstEnumValue::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::EnumValue, &AstEnumValue::nodeInitRef>(sema, *this, cloneContext);
}

AstNodeRef AstSuffixLiteral::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const auto&      inlineContext = cloneContextAsInline(cloneContext);
    const Ast&       sourceAst     = cloneSourceAst(sema, inlineContext);
    const AstNodeRef sourceRef     = nodeRef(sourceAst);
    const auto       storedView    = sourceStoredView(sema, resolveCloneNodeAst(sema, sourceRef, inlineContext), sourceRef);

    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::SuffixLiteral>(tokRef());
    newPtr->setCodeRef(codeRef());
    newPtr->nodeLiteralRef = SemaClone::cloneAst(sema, nodeLiteralRef, cloneContextAsInline(cloneContext));
    newPtr->nodeSuffixRef  = SemaClone::cloneAst(sema, nodeSuffixRef, cloneContextAsInline(cloneContext));
    if (storedView && storedView->typeRef.isValid())
        sema.setType(newRef, storedView->typeRef);
    if (storedView && storedView->cstRef.isValid())
        sema.setConstant(newRef, storedView->cstRef);
    if (storedView && hasStoredFlag(*storedView, NodePayloadFlags::Value))
        sema.setIsValue(newRef);
    if (storedView && hasStoredFlag(*storedView, NodePayloadFlags::LValue))
        sema.setIsLValue(newRef);
    if (storedView && hasStoredFlag(*storedView, NodePayloadFlags::FoldedTypedConst))
        sema.setFoldedTypedConst(newRef);
    return newRef;
}

AstNodeRef AstCompilerRunExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::CompilerRunExpr>(tokRef());
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCompilerCodeExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]      = sema.ast().makeNode<AstNodeId::CompilerCodeExpr>(tokRef());
    newPtr->nodeExprRef        = cloneCodeNodeRefWithoutReplacements(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    newPtr->payloadTypeRef     = payloadTypeRef;
    newPtr->spanBinderNamesRef = cloneTokenSpan(sema, spanBinderNamesRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCompilerTypeExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::CompilerTypeExpr>(tokRef());
    newPtr->nodeTypeRef   = cloneNodeRef(sema, nodeTypeRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstConstraintExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::ConstraintExpr>(tokRef());
    newPtr->sourceLength  = sourceLength;
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstConstraintBlock::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneNodeMembers<AstNodeId::ConstraintBlock, &AstConstraintBlock::spanChildrenRef>(sema, *this, cloneContext);
}

SWC_END_NAMESPACE();
