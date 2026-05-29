#include "pch.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Ast/Sema.Loop.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/CodeGenLoweringPayload.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/SourceFile.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void clearClonedNodePayload(AstNode& node)
    {
        node.clearPayload();
    }

    const SemaClone::CloneContext& cloneContextAsInline(const CloneContext& cloneContext)
    {
        return static_cast<const SemaClone::CloneContext&>(cloneContext); // NOLINT(cppcoreguidelines-pro-type-static-cast-downcast)
    }

    const Ast& cloneSourceAst(Sema& sema, const SemaClone::CloneContext& cloneContext)
    {
        return cloneContext.sourceAst ? *cloneContext.sourceAst : sema.ast();
    }

    const Ast* resolveCloneNodeAst(Sema& sema, AstNodeRef nodeRef, const SemaClone::CloneContext& cloneContext)
    {
        if (nodeRef.isInvalid())
            return nullptr;

        const Ast& sourceAst = cloneSourceAst(sema, cloneContext);
        if (sourceAst.hasNode(nodeRef))
            return &sourceAst;
        if (sema.ast().hasNode(nodeRef))
            return &sema.ast();
        return nullptr;
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
        if (sourceAst.hasSpan(spanRef))
            return &sourceAst;
        if (sema.ast().hasSpan(spanRef))
            return &sema.ast();
        return nullptr;
    }

    bool canReadSourcePayload(Sema& sema, const SemaClone::CloneContext& cloneContext)
    {
        return &cloneSourceAst(sema, cloneContext) == &sema.ast();
    }

    bool hasStoredFlag(const NodePayload::StoredView& view, NodePayloadFlags flag)
    {
        return (static_cast<uint16_t>(view.flags) & static_cast<uint16_t>(flag)) != 0;
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

    std::optional<NodePayload::StoredView> sourceStoredView(Sema& sema, const SemaClone::CloneContext& cloneContext, AstNodeRef sourceRef)
    {
        if (sourceRef.isInvalid())
            return std::nullopt;

        const Ast* sourceAst = resolveCloneNodeAst(sema, sourceRef, cloneContext);
        if (!sourceAst)
            return std::nullopt;
        if (sourceAst == &sema.ast())
            return currentStoredView(sema, sourceRef);

        const AstNode&      sourceNode     = sourceAst->node(sourceRef);
        const SourceView*   sourceView     = resolveCloneSourceView(sema, *sourceAst, sourceNode);
        const SourceFile*   sourceFile     = sourceView ? sourceView->file() : nullptr;
        if (!sourceFile)
            return std::nullopt;

        return sourceFile->nodePayloadContext().viewStored(sema.ctx(), sourceRef);
    }

    SemaClone::CloneContext cloneContextWithoutReplacements(const SemaClone::CloneContext& cloneContext)
    {
        return SemaClone::CloneContext{cloneContext.bindings, {}, cloneContext.preserveFunctionGenerics, cloneContext.sourceAst, cloneContext.preserveBindingExprState, cloneContext.duplicateRuntimeStorage, cloneContext.breakableDepth};
    }

    SemaClone::CloneContext cloneContextWithoutBindings(const SemaClone::CloneContext& cloneContext)
    {
        return SemaClone::CloneContext{std::span<const SemaClone::ParamBinding>{}, cloneContext.replacements, cloneContext.preserveFunctionGenerics, cloneContext.sourceAst, cloneContext.preserveBindingExprState, cloneContext.duplicateRuntimeStorage, cloneContext.breakableDepth};
    }

    SemaClone::CloneContext cloneContextForDestinationAst(const SemaClone::CloneContext& cloneContext)
    {
        return SemaClone::CloneContext{cloneContext.bindings, cloneContext.replacements, cloneContext.preserveFunctionGenerics, nullptr, cloneContext.preserveBindingExprState, cloneContext.duplicateRuntimeStorage, cloneContext.breakableDepth};
    }

    SemaClone::CloneContext cloneContextInsideBreakable(const SemaClone::CloneContext& cloneContext)
    {
        return SemaClone::CloneContext{cloneContext.bindings, cloneContext.replacements, cloneContext.preserveFunctionGenerics, cloneContext.sourceAst, cloneContext.preserveBindingExprState, cloneContext.duplicateRuntimeStorage, cloneContext.breakableDepth + 1};
    }

    bool startsNestedBreakableContext(const AstNode& node)
    {
        return node.is(AstNodeId::WhileStmt) ||
               node.is(AstNodeId::ForeachStmt) ||
               node.is(AstNodeId::ForCStyleStmt) ||
               node.is(AstNodeId::ForStmt) ||
               node.is(AstNodeId::InfiniteLoopStmt) ||
               node.is(AstNodeId::SwitchStmt) ||
               node.is(AstNodeId::CompilerScope);
    }

    const SemaClone::ParamBinding* findBinding(const SemaClone::CloneContext& cloneContext, IdentifierRef idRef)
    {
        for (const SemaClone::ParamBinding& binding : cloneContext.bindings)
        {
            if (binding.idRef == idRef)
                return &binding;
        }

        return nullptr;
    }

    bool isDetachedReexpandableExpr(const AstNode& node)
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
        SmallVector<AstNodeRef> captures;
        sourceAst.appendNodes(captures, captureArgsRef);
        for (const AstNodeRef captureRef : captures)
        {
            const auto& captureArg = sourceAst.node(captureRef).cast<AstClosureArgument>();
            collectSourceIdentifierUses(sema, sourceAst, captureArg.nodeIdentifierRef, outIdentifiers);
        }
    }

    void excludeCapturedClosureBindings(Sema& sema, const AstClosureExpr& node, const SemaClone::CloneContext& cloneContext, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        outBindings.clear();
        if (cloneContext.bindings.empty())
            return;

        SmallVector<IdentifierRef> captureIdentifiers;
        collectClosureCaptureIdentifiers(sema, cloneSourceAst(sema, cloneContext), node.nodeCaptureArgsRef, captureIdentifiers);
        const std::unordered_set<IdentifierRef> captureIdentifierSet{captureIdentifiers.begin(), captureIdentifiers.end()};
        for (const SemaClone::ParamBinding& binding : cloneContext.bindings)
        {
            if (!captureIdentifierSet.contains(binding.idRef))
                outBindings.push_back(binding);
        }
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
        clearClonedNodePayload(*newNodePtr);
        return newRef;
    }

    AstNodeRef cloneNodeRef(Sema& sema, AstNodeRef nodeRef, const SemaClone::CloneContext& cloneContext)
    {
        if (nodeRef.isInvalid())
            return AstNodeRef::invalid();
        return SemaClone::cloneAst(sema, nodeRef, cloneContext);
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
        if (binding.sourceParam != nullptr && targetRef.isValid())
        {
            sema.setConstAssignBinding(targetRef);

            const TypeInfo& paramType = binding.sourceParam->type(sema.ctx());
            if (!paramType.isPointerOrReference())
                sema.setConstAssignTarget(targetRef);
        }
        return targetRef;
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
        if (storedView.hasConstant())
            return;
        if (storedView.typeRef().isValid())
            sema.setType(clonedRef, storedView.typeRef());
        if (sema.isValueStored(sourceRef))
            sema.setIsValue(clonedRef);
        if (sema.isLValueStored(sourceRef))
            sema.setIsLValue(clonedRef);
        if (sema.isFoldedTypedConstStored(sourceRef))
            sema.setFoldedTypedConst(clonedRef);

        if (sema.hasSemaPayload(sourceRef))
            sema.setSemaPayload(clonedRef, sema.semaPayload<CastSpecOpPayload>(sourceRef));
        sema.copyResolvedCallArguments(clonedRef, sourceRef);
        copyImplicitCastLoweringPayload(sema, cloneContext, sourceRef, clonedRef);
    }

    void copyImplicitCastSubstitute(Sema& sema, const SemaClone::CloneContext& cloneContext, AstNodeRef sourceRef, AstNodeRef clonedRef)
    {
        if (!canReadSourcePayload(sema, cloneContext))
            return;

        const AstNodeRef resolvedRef = sema.viewZero(sourceRef).nodeRef();
        if (resolvedRef.isInvalid() || resolvedRef == sourceRef)
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
        castPtr->nodeTypeRef    = cloneNodeRef(sema, sourceCast->nodeTypeRef, cloneContext);
        castPtr->nodeExprRef    = clonedRef;

        copyImplicitCastPayload(sema, cloneContext, *sourceCast, resolvedRef, castRef);
        sema.setSubstitute(clonedRef, castRef);
    }

    void copyVarInitSpecOpPayload(Sema& sema, const SemaClone::CloneContext& cloneContext, const AstNode& sourceNode, AstNodeRef sourceRef, AstNodeRef clonedRef)
    {
        if (!canReadSourcePayload(sema, cloneContext))
            return;
        if (sourceNode.isNot(AstNodeId::SingleVarDecl) && sourceNode.isNot(AstNodeId::MultiVarDecl))
            return;
        if (!sema.hasSemaPayload(sourceRef))
            return;

        sema.setSemaPayload(clonedRef, sema.semaPayload<VarInitSpecOpPayload>(sourceRef));
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

        SmallVector<AstNodeRef> cloned;
        cloned.reserve(children.size());
        for (const AstNodeRef childRef : children)
        {
            const AstNodeRef clonedRef = SemaClone::cloneAst(sema, childRef, cloneContext);
            if (clonedRef.isInvalid())
                return SpanRef::invalid();
            cloned.push_back(clonedRef);
        }

        return sema.ast().pushSpan(cloned.span());
    }

    SpanRef cloneTokenSpan(Sema& sema, SpanRef spanRef, const SemaClone::CloneContext& cloneContext)
    {
        if (spanRef.isInvalid())
            return SpanRef::invalid();

        const Ast* spanAst = resolveCloneSpanAst(sema, spanRef, cloneContext);
        if (!spanAst)
            return SpanRef::invalid();

        SmallVector<TokenRef> tokens;
        spanAst->appendTokens(tokens, spanRef);
        if (tokens.empty())
            return SpanRef::invalid();

        return sema.ast().pushSpan(tokens.span());
    }

    SpanRef cloneSpanWithoutReplacements(Sema& sema, SpanRef spanRef, const SemaClone::CloneContext& cloneContext)
    {
        if (spanRef.isInvalid())
            return SpanRef::invalid();

        const auto noReplacements = cloneContextWithoutReplacements(cloneContext);
        return cloneSpan(sema, spanRef, noReplacements);
    }

    void copyDetachedBindingExprState(Sema& sema, AstNodeRef sourceRef, AstNodeRef clonedRef, std::unordered_set<AstNodeRef>& activeSourceRefSet);

    void copyResolvedIdentifierSymbols(Sema& sema, AstNodeRef sourceRef, AstNodeRef clonedRef)
    {
        SWC_ASSERT(sourceRef.isValid());
        SWC_ASSERT(clonedRef.isValid());

        if (sema.node(sourceRef).is(AstNodeId::Identifier) && sema.node(clonedRef).is(AstNodeId::Identifier))
        {
            if (const Symbol* symbol = sema.viewStored(sourceRef, SemaNodeViewPartE::Symbol).sym())
            {
                sema.setSymbol(clonedRef, symbol);
                sema.node(clonedRef).cast<AstIdentifier>().addFlag(AstIdentifierFlagsE::PreResolvedSymbol);
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

            copyResolvedIdentifierSymbols(sema, sourceChildRef, clonedChildRef);
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

    AstNodeRef cloneDetachedExprImpl(Sema& sema, AstNodeRef sourceRef)
    {
        SWC_ASSERT(sourceRef.isValid());
        const SemaClone::CloneContext noBindings{std::span<const SemaClone::ParamBinding>{}, std::span<const SemaClone::NodeReplacement>{}, false, nullptr, false, true};
        const AstNodeRef              clonedRef = SemaClone::cloneAst(sema, sourceRef, noBindings);
        if (clonedRef.isInvalid())
            return AstNodeRef::invalid();

        std::unordered_set<AstNodeRef> activeSourceRefSet;
        copyDetachedBindingExprState(sema, sourceRef, clonedRef, activeSourceRefSet);
        return clonedRef;
    }

    void copyDetachedBindingExprState(Sema& sema, AstNodeRef sourceRef, AstNodeRef clonedRef, std::unordered_set<AstNodeRef>& activeSourceRefSet)
    {
        SWC_ASSERT(sourceRef.isValid());
        SWC_ASSERT(clonedRef.isValid());

        const AstNodeRef resolvedRef    = sema.viewZero(sourceRef).nodeRef();
        const bool       shouldReexpand = resolvedRef.isValid() &&
                                    resolvedRef != sourceRef &&
                                    sema.node(resolvedRef).is(AstNodeId::EmbeddedBlock) &&
                                    isDetachedReexpandableExpr(sema.node(sourceRef));

        activeSourceRefSet.insert(sourceRef);
        if (!shouldReexpand)
            sema.inheritPayload(sema.node(clonedRef), sourceRef);
        if (sema.node(sourceRef).is(AstNodeId::Identifier) && sema.viewStored(sourceRef, SemaNodeViewPartE::Symbol).hasSymbol())
            sema.node(clonedRef).cast<AstIdentifier>().addFlag(AstIdentifierFlagsE::PreResolvedSymbol);

        if (!shouldReexpand &&
            resolvedRef.isValid() &&
            resolvedRef != sourceRef &&
            !isImplicitCastSubstitute(sema, sourceRef, resolvedRef) &&
            !activeSourceRefSet.contains(resolvedRef))
        {
            const AstNodeRef clonedResolvedRef = cloneDetachedExprImpl(sema, resolvedRef);
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

            const AstNodeRef resolvedChildRef    = sema.viewZero(sourceChildRef).nodeRef();
            const bool       shouldReexpandChild = resolvedChildRef.isValid() &&
                                             resolvedChildRef != sourceChildRef &&
                                             sema.node(resolvedChildRef).is(AstNodeId::EmbeddedBlock) &&
                                             isDetachedReexpandableExpr(sema.node(sourceChildRef));
            if (!shouldReexpandChild)
                sema.inheritPayload(sema.node(clonedChildRef), sourceChildRef);

            if (!shouldReexpandChild &&
                resolvedChildRef.isValid() &&
                resolvedChildRef != sourceChildRef &&
                !isImplicitCastSubstitute(sema, sourceChildRef, resolvedChildRef) &&
                !activeSourceRefSet.contains(resolvedChildRef))
            {
                const AstNodeRef clonedResolvedChildRef = cloneDetachedExprImpl(sema, resolvedChildRef);
                sema.setSubstitute(clonedChildRef, clonedResolvedChildRef);
                continue;
            }

            copyDetachedBindingExprState(sema, sourceChildRef, clonedChildRef, activeSourceRefSet);
        }

        activeSourceRefSet.erase(sourceRef);
    }

    AstNodeRef cloneIdentifier(Sema& sema, const AstIdentifier& node, const SemaClone::CloneContext& cloneContext)
    {
        const Ast&                                   sourceAst  = cloneSourceAst(sema, cloneContext);
        const AstNodeRef                             sourceRef  = node.nodeRef(sourceAst);
        const std::optional<NodePayload::StoredView> storedView = sourceStoredView(sema, cloneContext, sourceRef);

        IdentifierRef idRef = IdentifierRef::invalid();
        if (storedView && storedView->sym)
            idRef = storedView->sym->idRef();
        if (!idRef.isValid())
            idRef = sema.idMgr().addIdentifier(sema.ctx(), node.codeRef());

        if (const SemaClone::ParamBinding* binding = findBinding(cloneContext, idRef))
        {
            if (binding->cstRef.isValid())
            {
                auto [newRef, newNodePtr] = sema.ast().makeNode<AstNodeId::Identifier>(node.tokRef());
                newNodePtr->flags()       = node.flags();
                newNodePtr->setCodeRef(node.codeRef());
                if (binding->typeRef.isValid())
                    sema.setType(newRef, binding->typeRef);
                sema.setConstant(newRef, binding->cstRef);
                return newRef;
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

            AstNodeRef clonedExprRef = AstNodeRef::invalid();
            if (cloneContext.preserveBindingExprState)
                clonedExprRef = cloneDetachedExprImpl(sema, binding->exprRef);
            else
                clonedExprRef = cloneExprPreservingResolvedIdentifierSymbols(sema, binding->exprRef);
            if (!binding->typeRef.isValid())
                return markConstParamBindingTarget(sema, *binding, clonedExprRef);

            const AstNodeRef castRef = Cast::createCast(sema, binding->typeRef, clonedExprRef);
            if (castRef.isInvalid())
                return AstNodeRef::invalid();
            return markConstParamBindingTarget(sema, *binding, castRef);
        }

        const bool crossAstSource      = &sourceAst != &sema.ast();
        auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::Identifier>(node.tokRef());
        nodePtr->flags()        = node.flags();
        nodePtr->setCodeRef(node.codeRef());
        const bool sourceSymbolOwnedByFunction = storedView &&
                                                 storedView->sym &&
                                                 storedView->sym->ownerSymMap() &&
                                                 storedView->sym->ownerSymMap()->isFunction();
        const bool preserveSyntheticSymbol = storedView && storedView->sym &&
                                             (node.hasFlag(AstIdentifierFlagsE::PreResolvedSymbol) ||
                                              ((!crossAstSource || !sourceSymbolOwnedByFunction) &&
                                               (!storedView->sym->isFunctionLocalVariable() ||
                                                !node.codeRef().isValid() ||
                                                sema.token(node.codeRef()).id != TokenId::Identifier)));
        if (preserveSyntheticSymbol)
            sema.setSymbol(nodeRef, storedView->sym);
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
}

AstNodeRef SemaClone::cloneAst(Sema& sema, AstNodeRef nodeRef, const CloneContext& cloneContext)
{
    SWC_ASSERT(nodeRef.isValid());
    const Ast* sourceAst = resolveCloneNodeAst(sema, nodeRef, cloneContext);
    SWC_ASSERT(sourceAst != nullptr);
    if (!sourceAst)
        return AstNodeRef::invalid();

    auto&       node            = const_cast<AstNode&>(sourceAst->node(nodeRef));
    const SourceView* nodeSourceView = resolveCloneSourceView(sema, *sourceAst, node);
    SWC_ASSERT(nodeSourceView != nullptr);
    SourceView*      previousSrcView = Ast::setThreadSourceViewOverride(const_cast<SourceView*>(nodeSourceView));

    AstNodeRef clonedRef = cloneNodeReplacement(sema, node, cloneContext);
    if (clonedRef.isValid())
    {
        Ast::setThreadSourceViewOverride(previousSrcView);
        return clonedRef;
    }

    const CloneContext childCloneContext = startsNestedBreakableContext(node) ? cloneContextInsideBreakable(cloneContext) : cloneContext;
    clonedRef                            = Ast::nodeIdInfos(node.id()).semaClone(sema, node, childCloneContext);
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

AstNodeRef SemaClone::cloneDetachedExpr(Sema& sema, AstNodeRef nodeRef)
{
    return cloneDetachedExprImpl(sema, nodeRef);
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
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::File>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstFile>();
    cloned.spanGlobalsRef   = cloneSpan(sema, spanGlobalsRef, cloneContextAsInline(cloneContext));
    cloned.spanUsingsRef    = cloneSpan(sema, spanUsingsRef, cloneContextAsInline(cloneContext));
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstTopLevelBlock::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::TopLevelBlock>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstTopLevelBlock>();
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
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
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::Impl>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstImpl>();
    cloned.nodeIdentRef     = cloneNodeRef(sema, nodeIdentRef, cloneContextAsInline(cloneContext));
    cloned.nodeForRef       = cloneNodeRef(sema, nodeForRef, cloneContextAsInline(cloneContext));
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
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
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::UsingNamespaceStmt>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstUsingNamespaceStmt>();
    cloned.nodeNameRef      = cloneNodeRef(sema, nodeNameRef, cloneContextAsInline(cloneContext));
    return newRef;
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
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::FunctionBody>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstFunctionBody>();
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstAttribute::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::Attribute>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstAttribute>();
    cloned.nodeCallRef      = cloneNodeRef(sema, nodeCallRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstAttributeList::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::AttributeList>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstAttributeList>();
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstDependenciesBlock::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::DependenciesBlock>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstDependenciesBlock>();
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstUsingDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::UsingDecl>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstUsingDecl>();
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstAccessModifier::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::AccessModifier>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstAccessModifier>();
    cloned.nodeWhatRef      = cloneNodeRef(sema, nodeWhatRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstAttrDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::AttrDecl>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstAttrDecl>();
    cloned.nodeParamsRef    = cloneNodeRef(sema, nodeParamsRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstFunctionDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::FunctionDecl>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstFunctionDecl>();
    if (cloneContextAsInline(cloneContext).preserveFunctionGenerics)
    {
        cloned.spanGenericParamsRef = cloneSpan(sema, spanGenericParamsRef, cloneContextAsInline(cloneContext));
        cloned.spanConstraintsRef   = cloneSpan(sema, spanConstraintsRef, cloneContextAsInline(cloneContext));
    }
    else
    {
        cloned.spanGenericParamsRef = SpanRef::invalid();
        cloned.spanConstraintsRef   = SpanRef::invalid();
    }
    cloned.nodeParamsRef     = cloneNodeRef(sema, nodeParamsRef, cloneContextAsInline(cloneContext));
    cloned.nodeReturnTypeRef = cloneNodeRef(sema, nodeReturnTypeRef, cloneContextAsInline(cloneContext));
    cloned.nodeBodyRef       = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstFunctionParamList::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::FunctionParamList>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstFunctionParamList>();
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstFunctionParamMe::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return cloneNodeCopy<AstNodeId::FunctionParamMe>(sema, *this);
}

AstNodeRef AstVarDeclList::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::VarDeclList>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstVarDeclList>();
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstElseStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::ElseStmt>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstElseStmt>();
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstElseIfStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::ElseIfStmt>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstElseIfStmt>();
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstSwitchCaseBody::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::SwitchCaseBody>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstSwitchCaseBody>();
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstAssignList::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::AssignList>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstAssignList>();
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstAssignIgnore::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return cloneNodeCopy<AstNodeId::AssignIgnore>(sema, *this);
}

AstNodeRef AstReturnStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::ReturnStmt>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstReturnStmt>();
    cloned.nodeExprRef      = cloneNodeRef(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstSingleVarDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::SingleVarDecl>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstSingleVarDecl>();
    cloned.nodeTypeRef      = cloneNodeRef(sema, nodeTypeRef, cloneContextAsInline(cloneContext));
    cloned.nodeInitRef      = cloneNodeRef(sema, nodeInitRef, cloneContextAsInline(cloneContext));
    return newRef;
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
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::VarDeclDestructuring>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstVarDeclDestructuring>();
    cloned.spanNamesRef     = cloneTokenSpan(sema, spanNamesRef, cloneContextAsInline(cloneContext));
    cloned.nodeInitRef      = cloneNodeRef(sema, nodeInitRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstAssignStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::AssignStmt>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstAssignStmt>();
    cloned.nodeLeftRef      = cloneNodeRef(sema, nodeLeftRef, cloneContextAsInline(cloneContext));
    cloned.nodeRightRef     = cloneNodeRef(sema, nodeRightRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstIfStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::IfStmt>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstIfStmt>();
    cloned.nodeConditionRef = cloneNodeRef(sema, nodeConditionRef, cloneContextAsInline(cloneContext));
    cloned.nodeIfBlockRef   = cloneNodeRef(sema, nodeIfBlockRef, cloneContextAsInline(cloneContext));
    cloned.nodeElseBlockRef = cloneNodeRef(sema, nodeElseBlockRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstIfVarDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::IfVarDecl>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstIfVarDecl>();
    cloned.nodeVarRef       = cloneNodeRef(sema, nodeVarRef, cloneContextAsInline(cloneContext));
    cloned.nodeWhereRef     = cloneNodeRef(sema, nodeWhereRef, cloneContextAsInline(cloneContext));
    cloned.nodeIfBlockRef   = cloneNodeRef(sema, nodeIfBlockRef, cloneContextAsInline(cloneContext));
    cloned.nodeElseBlockRef = cloneNodeRef(sema, nodeElseBlockRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstWithStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::WithStmt>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstWithStmt>();
    cloned.nodeExprRef      = cloneNodeRef(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstWithVarDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::WithVarDecl>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstWithVarDecl>();
    cloned.nodeVarRef       = cloneNodeRef(sema, nodeVarRef, cloneContextAsInline(cloneContext));
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstDeferStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::DeferStmt>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstDeferStmt>();
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstWhileStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::WhileStmt>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstWhileStmt>();
    cloned.nodeExprRef      = cloneNodeRef(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
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
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::ForCStyleStmt>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstForCStyleStmt>();
    cloned.nodeVarDeclRef   = cloneNodeRef(sema, nodeVarDeclRef, cloneContextAsInline(cloneContext));
    cloned.nodeExprRef      = cloneNodeRef(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    cloned.nodePostStmtRef  = cloneNodeRef(sema, nodePostStmtRef, cloneContextAsInline(cloneContext));
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstForStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::ForStmt>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstForStmt>();
    cloned.nodeExprRef      = cloneNodeRef(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    cloned.nodeWhereRef     = cloneNodeRef(sema, nodeWhereRef, cloneContextAsInline(cloneContext));
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstInfiniteLoopStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::InfiniteLoopStmt>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstInfiniteLoopStmt>();
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstTryCatchStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::TryCatchStmt>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstTryCatchStmt>();
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
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
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::SwitchStmt>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstSwitchStmt>();
    cloned.nodeExprRef      = cloneNodeRef(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstSwitchCaseStmt::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::SwitchCaseStmt>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstSwitchCaseStmt>();
    cloned.nodeWhereRef     = cloneNodeRef(sema, nodeWhereRef, cloneContextAsInline(cloneContext));
    cloned.spanExprRef      = cloneSpan(sema, spanExprRef, cloneContextAsInline(cloneContext));
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCompilerExpression::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::CompilerExpression>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstCompilerExpression>();
    cloned.nodeExprRef      = cloneNodeRef(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCompilerIf::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::CompilerIf>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstCompilerIf>();
    cloned.nodeConditionRef = cloneNodeRef(sema, nodeConditionRef, cloneContextAsInline(cloneContext));
    cloned.nodeIfBlockRef   = cloneNodeRef(sema, nodeIfBlockRef, cloneContextAsInline(cloneContext));
    cloned.nodeElseBlockRef = cloneNodeRef(sema, nodeElseBlockRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCompilerElse::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::CompilerElse>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstCompilerElse>();
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCompilerScope::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::CompilerScope>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstCompilerScope>();
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCompilerRunBlock::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::CompilerRunBlock>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstCompilerRunBlock>();
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCompilerCodeBlock::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::CompilerCodeBlock>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstCompilerCodeBlock>();
    cloned.nodeBodyRef      = cloneCodeNodeRefWithoutReplacements(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    cloned.payloadTypeRef   = payloadTypeRef;
    return newRef;
}

AstNodeRef AstCompilerShortFunc::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::CompilerShortFunc>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstCompilerShortFunc>();
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCompilerFunc::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::CompilerFunc>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstCompilerFunc>();
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCompilerMessageFunc::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::CompilerMessageFunc>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstCompilerMessageFunc>();
    cloned.nodeParamRef     = cloneNodeRef(sema, nodeParamRef, cloneContextAsInline(cloneContext));
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCompilerMacro::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::CompilerMacro>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstCompilerMacro>();
    cloned.nodeBodyRef      = cloneNodeRefWithoutBindings(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCompilerInject::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef          = cloneNodeCopy<AstNodeId::CompilerInject>(sema, *this);
    auto&            cloned          = sema.node(newRef).cast<AstCompilerInject>();
    cloned.nodeExprRef               = cloneNodeRef(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    cloned.spanReplaceInstructionRef = cloneTokenSpan(sema, spanReplaceInstructionRef, cloneContextAsInline(cloneContext));
    cloned.spanReplaceNodeRef        = cloneSpanWithoutReplacements(sema, spanReplaceNodeRef, cloneContextAsInline(cloneContext));
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
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::CompilerDiagnostic>(tokRef());
    newPtr->nodeArgRef    = SemaClone::cloneAst(sema, nodeArgRef, cloneContextAsInline(cloneContext));
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
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstIntrinsicCallVariadic::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::IntrinsicCallVariadic>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstIntrinsicCallVariadic>();
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
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

AstNodeRef AstUndefinedExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return sema.ast().makeNode<AstNodeId::UndefinedExpr>(tokRef()).first;
}

AstNodeRef AstAliasDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::AliasDecl>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstAliasDecl>();
    cloned.nodeExprRef      = cloneNodeRef(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstIntrinsicValue::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return sema.ast().makeNode<AstNodeId::IntrinsicValue>(tokRef()).first;
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
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
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
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::DiscardExpr>(tokRef());
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstTryCatchExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::TryCatchExpr>(tokRef());
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstThrowExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::ThrowExpr>(tokRef());
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstIdentifier::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    return cloneIdentifier(sema, *this, cloneContextAsInline(cloneContext));
}

AstNodeRef AstAncestorIdentifier::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::AncestorIdentifier>(tokRef());
    newPtr->nodeValueRef  = cloneNodeRef(sema, nodeValueRef, cloneContextAsInline(cloneContext));
    newPtr->nodeIdentRef  = cloneNodeRef(sema, nodeIdentRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstFunctionExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]     = sema.ast().makeNode<AstNodeId::FunctionExpr>(tokRef());
    newPtr->flags()           = flags();
    newPtr->spanArgsRef       = cloneSpan(sema, spanArgsRef, cloneContextAsInline(cloneContext));
    newPtr->nodeReturnTypeRef = cloneNodeRef(sema, nodeReturnTypeRef, cloneContextAsInline(cloneContext));
    newPtr->nodeBodyRef       = SemaClone::cloneAst(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstClosureExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const auto& inlineContext  = cloneContextAsInline(cloneContext);
    auto [newRef, newPtr]      = sema.ast().makeNode<AstNodeId::ClosureExpr>(tokRef());
    newPtr->flags()            = flags();
    newPtr->nodeCaptureArgsRef = cloneSpan(sema, nodeCaptureArgsRef, inlineContext);
    newPtr->spanArgsRef        = cloneSpan(sema, spanArgsRef, inlineContext);
    newPtr->nodeReturnTypeRef  = cloneNodeRef(sema, nodeReturnTypeRef, inlineContext);

    SmallVector<SemaClone::ParamBinding> bodyBindings;
    excludeCapturedClosureBindings(sema, *this, inlineContext, bodyBindings);
    const SemaClone::CloneContext bodyContext{bodyBindings.span(), inlineContext.replacements, inlineContext.preserveFunctionGenerics, inlineContext.sourceAst};
    newPtr->nodeBodyRef = SemaClone::cloneAst(sema, nodeBodyRef, bodyContext);
    return newRef;
}

AstNodeRef AstClosureArgument::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]     = sema.ast().makeNode<AstNodeId::ClosureArgument>(tokRef());
    newPtr->flags()           = flags();
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
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::CallExpr>(tokRef());
    newPtr->flags()         = flags();
    newPtr->nodeExprRef     = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstIntrinsicCallExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::IntrinsicCallExpr>(tokRef());
    newPtr->flags()         = flags();
    newPtr->nodeExprRef     = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstAliasCallExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::AliasCallExpr>(tokRef());
    newPtr->nodeExprRef     = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    newPtr->spanAliasesRef  = cloneSpan(sema, spanAliasesRef, cloneContextAsInline(cloneContext));
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
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
    newPtr->flags()       = flags();
    newPtr->nodeIdentRef  = cloneNodeRefWithoutBindings(sema, nodeIdentRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstMemberAccessExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::MemberAccessExpr>(tokRef());
    newPtr->flags()       = flags();
    newPtr->nodeLeftRef   = SemaClone::cloneAst(sema, nodeLeftRef, cloneContextAsInline(cloneContext));
    newPtr->nodeRightRef  = cloneNodeRefWithoutBindings(sema, nodeRightRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstQualifiedType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::QualifiedType>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstQualifiedType>();
    cloned.nodeTypeRef      = cloneNodeRef(sema, nodeTypeRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstReferenceType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef   = cloneNodeCopy<AstNodeId::ReferenceType>(sema, *this);
    auto&            cloned   = sema.node(newRef).cast<AstReferenceType>();
    cloned.nodePointeeTypeRef = cloneNodeRef(sema, nodePointeeTypeRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstMoveRefType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef   = cloneNodeCopy<AstNodeId::MoveRefType>(sema, *this);
    auto&            cloned   = sema.node(newRef).cast<AstMoveRefType>();
    cloned.nodePointeeTypeRef = cloneNodeRef(sema, nodePointeeTypeRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstValuePointerType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef   = cloneNodeCopy<AstNodeId::ValuePointerType>(sema, *this);
    auto&            cloned   = sema.node(newRef).cast<AstValuePointerType>();
    cloned.nodePointeeTypeRef = cloneNodeRef(sema, nodePointeeTypeRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstBlockPointerType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef   = cloneNodeCopy<AstNodeId::BlockPointerType>(sema, *this);
    auto&            cloned   = sema.node(newRef).cast<AstBlockPointerType>();
    cloned.nodePointeeTypeRef = cloneNodeRef(sema, nodePointeeTypeRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstSliceType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef   = cloneNodeCopy<AstNodeId::SliceType>(sema, *this);
    auto&            cloned   = sema.node(newRef).cast<AstSliceType>();
    cloned.nodePointeeTypeRef = cloneNodeRef(sema, nodePointeeTypeRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstArrayType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef   = cloneNodeCopy<AstNodeId::ArrayType>(sema, *this);
    auto&            cloned   = sema.node(newRef).cast<AstArrayType>();
    cloned.spanDimensionsRef  = cloneSpan(sema, spanDimensionsRef, cloneContextAsInline(cloneContext));
    cloned.nodePointeeTypeRef = cloneNodeRef(sema, nodePointeeTypeRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstNamedType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::NamedType>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstNamedType>();
    cloned.nodeIdentRef     = cloneNodeRef(sema, nodeIdentRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstBuiltinType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return cloneNodeCopy<AstNodeId::BuiltinType>(sema, *this);
}

AstNodeRef AstRetValType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return cloneNodeCopy<AstNodeId::RetValType>(sema, *this);
}

AstNodeRef AstVariadicType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return cloneNodeCopy<AstNodeId::VariadicType>(sema, *this);
}

AstNodeRef AstTypedVariadicType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::TypedVariadicType>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstTypedVariadicType>();
    cloned.nodeTypeRef      = cloneNodeRef(sema, nodeTypeRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCodeType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::CodeType>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstCodeType>();
    cloned.nodeTypeRef      = cloneNodeRef(sema, nodeTypeRef, cloneContextAsInline(cloneContext));
    return newRef;
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
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::GenericParamList>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstGenericParamList>();
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstGenericParamValue::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::GenericParamValue>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstGenericParamValue>();
    cloned.nodeTypeRef      = cloneNodeRef(sema, nodeTypeRef, cloneContextAsInline(cloneContext));
    cloned.nodeAssignRef    = cloneNodeRef(sema, nodeAssignRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstGenericParamType::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::GenericParamType>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstGenericParamType>();
    cloned.nodeAssignRef    = cloneNodeRef(sema, nodeAssignRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCastExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::CastExpr>(tokRef());
    newPtr->flags()       = flags();
    newPtr->modifierFlags = modifierFlags;
    newPtr->nodeTypeRef   = cloneNodeRef(sema, nodeTypeRef, cloneContextAsInline(cloneContext));
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
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

AstNodeRef AstStructLiteral::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::StructLiteral>(tokRef());
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstStructDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::StructDecl>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstStructDecl>();
    // Keep local generic declarations intact when they are cloned as part of an
    // enclosing generic/function instantiation. Actual generic struct instances
    // still clear their own generic signature in createGenericInstanceSymbol.
    cloned.spanGenericParamsRef = cloneSpan(sema, spanGenericParamsRef, cloneContextAsInline(cloneContext));
    cloned.spanWhereRef         = cloneSpan(sema, spanWhereRef, cloneContextAsInline(cloneContext));
    cloned.nodeBodyRef          = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstInterfaceDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef     = cloneNodeCopy<AstNodeId::InterfaceDecl>(sema, *this);
    auto&            cloned     = sema.node(newRef).cast<AstInterfaceDecl>();
    cloned.spanGenericParamsRef = cloneSpan(sema, spanGenericParamsRef, cloneContextAsInline(cloneContext));
    cloned.spanWhereRef         = cloneSpan(sema, spanWhereRef, cloneContextAsInline(cloneContext));
    cloned.nodeBodyRef          = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstUnionDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef     = cloneNodeCopy<AstNodeId::UnionDecl>(sema, *this);
    auto&            cloned     = sema.node(newRef).cast<AstUnionDecl>();
    cloned.spanGenericParamsRef = cloneSpan(sema, spanGenericParamsRef, cloneContextAsInline(cloneContext));
    cloned.spanWhereRef         = cloneSpan(sema, spanWhereRef, cloneContextAsInline(cloneContext));
    cloned.nodeBodyRef          = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstAnonymousStructDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::AnonymousStructDecl>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstAnonymousStructDecl>();
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstAnonymousUnionDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::AnonymousUnionDecl>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstAnonymousUnionDecl>();
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstAggregateBody::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::AggregateBody>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstAggregateBody>();
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstInterfaceBody::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::InterfaceBody>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstInterfaceBody>();
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstEnumBody::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::EnumBody>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstEnumBody>();
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstEnumDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::EnumDecl>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstEnumDecl>();
    cloned.nodeTypeRef      = cloneNodeRef(sema, nodeTypeRef, cloneContextAsInline(cloneContext));
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstEnumValue::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::EnumValue>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstEnumValue>();
    cloned.nodeInitRef      = cloneNodeRef(sema, nodeInitRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstUsingEnumDecl::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::UsingEnumDecl>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstUsingEnumDecl>();
    cloned.nodeNameRef      = cloneNodeRef(sema, nodeNameRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstSuffixLiteral::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const auto&      inlineContext = cloneContextAsInline(cloneContext);
    const Ast&       sourceAst     = cloneSourceAst(sema, inlineContext);
    const AstNodeRef sourceRef     = nodeRef(sourceAst);
    const auto       storedView    = sourceStoredView(sema, inlineContext, sourceRef);

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
    auto [newRef, newPtr]  = sema.ast().makeNode<AstNodeId::CompilerCodeExpr>(tokRef());
    newPtr->nodeExprRef    = cloneCodeNodeRefWithoutReplacements(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    newPtr->payloadTypeRef = payloadTypeRef;
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
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstConstraintBlock::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::ConstraintBlock>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstConstraintBlock>();
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

SWC_END_NAMESPACE();
