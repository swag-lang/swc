#include "pch.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/Sema.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void clearClonedNodePayload(AstNode& node)
    {
        node.payloadBits() = 0;
        node.setPayloadRef(0);
    }

    const SemaClone::CloneContext& cloneContextAsInline(const CloneContext& cloneContext)
    {
        return reinterpret_cast<const SemaClone::CloneContext&>(cloneContext);
    }

    SemaClone::CloneContext cloneContextWithoutReplacements(const CloneContext& cloneContext)
    {
        const auto& inlineContext = cloneContextAsInline(cloneContext);
        return SemaClone::CloneContext{inlineContext.bindings};
    }

    const SemaClone::ParamBinding* findBinding(const CloneContext& cloneContext, IdentifierRef idRef)
    {
        for (const SemaClone::ParamBinding& binding : cloneContextAsInline(cloneContext).bindings)
        {
            if (binding.idRef == idRef)
                return &binding;
        }

        return nullptr;
    }

    const SemaClone::NodeReplacement* findReplacement(const CloneContext& cloneContext, AstNodeId nodeId)
    {
        for (const SemaClone::NodeReplacement& replacement : cloneContextAsInline(cloneContext).replacements)
        {
            if (replacement.nodeId == nodeId)
                return &replacement;
        }

        return nullptr;
    }

    AstNodeRef cloneShallowNode(Sema& sema, const AstNode& node)
    {
        AstNodeRef clonedRef = AstNodeRef::invalid();
        visitAstNodeId(node.id(), [&]<AstNodeId ID>() {
            using NodeType            = AstTypeOf<ID>::type;
            auto [newRef, newNodePtr] = sema.ast().makeNode<ID>(node.tokRef());
            *newNodePtr               = node.cast<NodeType>();
            clearClonedNodePayload(*newNodePtr);
            clonedRef = newRef;
        });

        return clonedRef;
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

    AstNodeRef cloneNodeRef(Sema& sema, AstNodeRef nodeRef, const CloneContext& cloneContext)
    {
        if (nodeRef.isInvalid())
            return AstNodeRef::invalid();
        return SemaClone::cloneAst(sema, nodeRef, cloneContextAsInline(cloneContext));
    }

    AstNodeRef cloneNodeRefWithoutReplacements(Sema& sema, AstNodeRef nodeRef, const CloneContext& cloneContext)
    {
        if (nodeRef.isInvalid())
            return AstNodeRef::invalid();

        const auto noReplacements = cloneContextWithoutReplacements(cloneContext);
        return SemaClone::cloneAst(sema, nodeRef, noReplacements);
    }

    AstNodeRef cloneNodeReplacement(Sema& sema, const AstNode& node, const CloneContext& cloneContext)
    {
        const auto* replacement = findReplacement(cloneContext, node.id());
        if (!replacement)
            return AstNodeRef::invalid();

        return cloneNodeRefWithoutReplacements(sema, replacement->replacementRef, cloneContext);
    }

    void copyCallableClonePayload(Sema& sema, AstNodeRef sourceRef, AstNodeRef clonedRef)
    {
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

    SpanRef cloneSpan(Sema& sema, SpanRef spanRef, const CloneContext& cloneContext)
    {
        if (spanRef.isInvalid())
            return SpanRef::invalid();

        SmallVector<AstNodeRef> children;
        sema.ast().appendNodes(children, spanRef);
        if (children.empty())
            return SpanRef::invalid();

        SmallVector<AstNodeRef> cloned;
        cloned.reserve(children.size());
        for (const AstNodeRef childRef : children)
        {
            const AstNodeRef clonedRef = SemaClone::cloneAst(sema, childRef, cloneContextAsInline(cloneContext));
            if (clonedRef.isInvalid())
                return SpanRef::invalid();
            cloned.push_back(clonedRef);
        }

        return sema.ast().pushSpan(cloned.span());
    }

    SpanRef cloneSpanWithoutReplacements(Sema& sema, SpanRef spanRef, const CloneContext& cloneContext)
    {
        if (spanRef.isInvalid())
            return SpanRef::invalid();

        const auto noReplacements = cloneContextWithoutReplacements(cloneContext);
        return cloneSpan(sema, spanRef, noReplacements);
    }

    AstNodeRef cloneIdentifier(Sema& sema, const AstIdentifier& node, const CloneContext& cloneContext)
    {
        const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), node.codeRef());
        if (const SemaClone::ParamBinding* binding = findBinding(cloneContext, idRef))
        {
            if (binding->cstRef.isValid())
            {
                auto [newRef, newNodePtr] = sema.ast().makeNode<AstNodeId::Identifier>(node.tokRef());
                newNodePtr->flags()       = node.flags();
                if (binding->typeRef.isValid())
                    sema.setType(newRef, binding->typeRef);
                sema.setConstant(newRef, binding->cstRef);
                return newRef;
            }

            const SemaClone::CloneContext noBindings{std::span<const SemaClone::ParamBinding>{}};
            const AstNodeRef              clonedExprRef = SemaClone::cloneAst(sema, binding->exprRef, noBindings);
            if (!binding->typeRef.isValid())
                return clonedExprRef;

            return Cast::createCast(sema, binding->typeRef, clonedExprRef);
        }

        auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::Identifier>(node.tokRef());
        nodePtr->flags()        = node.flags();
        return nodeRef;
    }
}

AstNodeRef SemaClone::cloneAst(Sema& sema, AstNodeRef nodeRef, const CloneContext& cloneContext)
{
    SWC_ASSERT(nodeRef.isValid());
    AstNode&   node      = sema.node(nodeRef);
    AstNodeRef clonedRef = cloneNodeReplacement(sema, node, cloneContext);
    if (clonedRef.isValid())
        return clonedRef;

    clonedRef = Ast::nodeIdInfos(node.id()).semaClone(sema, node, cloneContext);
    if (clonedRef.isValid())
    {
        copyCallableClonePayload(sema, nodeRef, clonedRef);
        return clonedRef;
    }

    clonedRef = cloneShallowNode(sema, node);
    SWC_ASSERT(clonedRef.isValid());
    copyCallableClonePayload(sema, nodeRef, clonedRef);
    return clonedRef;
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
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstFunctionBody::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::FunctionBody>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstFunctionBody>();
    cloned.spanChildrenRef  = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
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
    cloned.nodeTypeRef      = cloneNodeRef(sema, nodeTypeRef, cloneContextAsInline(cloneContext));
    cloned.nodeInitRef      = cloneNodeRef(sema, nodeInitRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstVarDeclDestructuring::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef = cloneNodeCopy<AstNodeId::VarDeclDestructuring>(sema, *this);
    auto&            cloned = sema.node(newRef).cast<AstVarDeclDestructuring>();
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
    cloned.nodeBodyRef      = cloneNodeRefWithoutReplacements(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
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
    cloned.nodeBodyRef      = cloneNodeRef(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstCompilerInject::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    const AstNodeRef newRef          = cloneNodeCopy<AstNodeId::CompilerInject>(sema, *this);
    auto&            cloned          = sema.node(newRef).cast<AstCompilerInject>();
    cloned.nodeExprRef               = cloneNodeRef(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    cloned.spanReplaceInstructionRef = spanReplaceInstructionRef;
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

AstNodeRef AstUndefinedExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    return sema.ast().makeNode<AstNodeId::UndefinedExpr>(tokRef()).first;
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
    newPtr->nodeValueRef  = SemaClone::cloneAst(sema, nodeValueRef, cloneContextAsInline(cloneContext));
    newPtr->nodeIdentRef  = SemaClone::cloneAst(sema, nodeIdentRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstFunctionExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]     = sema.ast().makeNode<AstNodeId::FunctionExpr>(tokRef());
    newPtr->flags()           = flags();
    newPtr->spanArgsRef       = cloneSpan(sema, spanArgsRef, cloneContextAsInline(cloneContext));
    newPtr->nodeReturnTypeRef = nodeReturnTypeRef;
    newPtr->nodeBodyRef       = SemaClone::cloneAst(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstClosureExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]      = sema.ast().makeNode<AstNodeId::ClosureExpr>(tokRef());
    newPtr->flags()            = flags();
    newPtr->nodeCaptureArgsRef = cloneSpan(sema, nodeCaptureArgsRef, cloneContextAsInline(cloneContext));
    newPtr->spanArgsRef        = cloneSpan(sema, spanArgsRef, cloneContextAsInline(cloneContext));
    newPtr->nodeReturnTypeRef  = nodeReturnTypeRef;
    newPtr->nodeBodyRef        = SemaClone::cloneAst(sema, nodeBodyRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstClosureArgument::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]     = sema.ast().makeNode<AstNodeId::ClosureArgument>(tokRef());
    newPtr->flags()           = flags();
    newPtr->nodeIdentifierRef = SemaClone::cloneAst(sema, nodeIdentifierRef, cloneContextAsInline(cloneContext));
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
    newPtr->nodeExprDownRef = SemaClone::cloneAst(sema, nodeExprDownRef, cloneContextAsInline(cloneContext));
    newPtr->nodeExprUpRef   = SemaClone::cloneAst(sema, nodeExprUpRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstIndexExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::IndexExpr>(tokRef());
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    newPtr->nodeArgRef    = SemaClone::cloneAst(sema, nodeArgRef, cloneContextAsInline(cloneContext));
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
    newPtr->nodeExprRef     = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstIntrinsicCallExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::IntrinsicCallExpr>(tokRef());
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
    newPtr->nodeIdentRef  = SemaClone::cloneAst(sema, nodeIdentRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstMemberAccessExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::MemberAccessExpr>(tokRef());
    newPtr->flags()       = flags();
    newPtr->nodeLeftRef   = SemaClone::cloneAst(sema, nodeLeftRef, cloneContextAsInline(cloneContext));
    newPtr->nodeRightRef  = SemaClone::cloneAst(sema, nodeRightRef, cloneContextAsInline(cloneContext));
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
    const auto noReplacements = cloneContextWithoutReplacements(cloneContext);
    newPtr->nodeExprRef       = SemaClone::cloneAst(sema, nodeExprRef, noReplacements);
    newPtr->spanChildrenRef   = cloneSpan(sema, spanChildrenRef, noReplacements);
    return newRef;
}

AstNodeRef AstCastExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::CastExpr>(tokRef());
    newPtr->flags()       = flags();
    newPtr->modifierFlags = modifierFlags;
    newPtr->nodeTypeRef   = nodeTypeRef;
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
    newPtr->nodeTypeRef   = nodeTypeRef;
    return newRef;
}

AstNodeRef AstIsTypeExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::IsTypeExpr>(tokRef());
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    newPtr->nodeTypeRef   = nodeTypeRef;
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

AstNodeRef AstSuffixLiteral::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]  = sema.ast().makeNode<AstNodeId::SuffixLiteral>(tokRef());
    newPtr->nodeLiteralRef = SemaClone::cloneAst(sema, nodeLiteralRef, cloneContextAsInline(cloneContext));
    newPtr->nodeSuffixRef  = SemaClone::cloneAst(sema, nodeSuffixRef, cloneContextAsInline(cloneContext));
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
    newPtr->nodeExprRef    = cloneNodeRefWithoutReplacements(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    newPtr->payloadTypeRef = payloadTypeRef;
    return newRef;
}

AstNodeRef AstCompilerTypeExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    SWC_UNUSED(cloneContext);
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::CompilerTypeExpr>(tokRef());
    newPtr->nodeTypeRef   = nodeTypeRef;
    return newRef;
}

AstNodeRef AstConstraintExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::ConstraintExpr>(tokRef());
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    return newRef;
}

SWC_END_NAMESPACE();
