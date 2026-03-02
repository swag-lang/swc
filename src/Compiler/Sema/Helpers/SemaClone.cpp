#include "pch.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Parser/Ast/AstNodes.h"
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

    const SemaClone::ParamBinding* findBinding(const CloneContext& cloneContext, IdentifierRef idRef)
    {
        for (const SemaClone::ParamBinding& binding : cloneContextAsInline(cloneContext).bindings)
        {
            if (binding.idRef == idRef)
                return &binding;
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

    AstNodeRef cloneStatementFallback(Sema& sema, const AstNode& node, const CloneContext& cloneContext)
    {
        switch (node.id())
        {
            case AstNodeId::TopLevelBlock:
            {
                auto*      oldNode     = node.safeCast<AstTopLevelBlock>();
                AstNodeRef newRef      = cloneNodeCopy<AstNodeId::TopLevelBlock>(sema, node);
                auto&      cloned      = sema.node(newRef).cast<AstTopLevelBlock>();
                cloned.spanChildrenRef = cloneSpan(sema, oldNode->spanChildrenRef, cloneContext);
                return newRef;
            }

            case AstNodeId::EmbeddedBlock:
            {
                auto*      oldNode     = node.safeCast<AstEmbeddedBlock>();
                AstNodeRef newRef      = cloneNodeCopy<AstNodeId::EmbeddedBlock>(sema, node);
                auto&      cloned      = sema.node(newRef).cast<AstEmbeddedBlock>();
                cloned.spanChildrenRef = cloneSpan(sema, oldNode->spanChildrenRef, cloneContext);
                return newRef;
            }

            case AstNodeId::FunctionBody:
            {
                auto*      oldNode     = node.safeCast<AstFunctionBody>();
                AstNodeRef newRef      = cloneNodeCopy<AstNodeId::FunctionBody>(sema, node);
                auto&      cloned      = sema.node(newRef).cast<AstFunctionBody>();
                cloned.spanChildrenRef = cloneSpan(sema, oldNode->spanChildrenRef, cloneContext);
                return newRef;
            }

            case AstNodeId::VarDeclList:
            {
                auto*      oldNode     = node.safeCast<AstVarDeclList>();
                AstNodeRef newRef      = cloneNodeCopy<AstNodeId::VarDeclList>(sema, node);
                auto&      cloned      = sema.node(newRef).cast<AstVarDeclList>();
                cloned.spanChildrenRef = cloneSpan(sema, oldNode->spanChildrenRef, cloneContext);
                return newRef;
            }

            case AstNodeId::ElseStmt:
            {
                auto*      oldNode     = node.safeCast<AstElseStmt>();
                AstNodeRef newRef      = cloneNodeCopy<AstNodeId::ElseStmt>(sema, node);
                auto&      cloned      = sema.node(newRef).cast<AstElseStmt>();
                cloned.spanChildrenRef = cloneSpan(sema, oldNode->spanChildrenRef, cloneContext);
                return newRef;
            }

            case AstNodeId::ElseIfStmt:
            {
                auto*      oldNode     = node.safeCast<AstElseIfStmt>();
                AstNodeRef newRef      = cloneNodeCopy<AstNodeId::ElseIfStmt>(sema, node);
                auto&      cloned      = sema.node(newRef).cast<AstElseIfStmt>();
                cloned.spanChildrenRef = cloneSpan(sema, oldNode->spanChildrenRef, cloneContext);
                return newRef;
            }

            case AstNodeId::SwitchCaseBody:
            {
                auto*      oldNode     = node.safeCast<AstSwitchCaseBody>();
                AstNodeRef newRef      = cloneNodeCopy<AstNodeId::SwitchCaseBody>(sema, node);
                auto&      cloned      = sema.node(newRef).cast<AstSwitchCaseBody>();
                cloned.spanChildrenRef = cloneSpan(sema, oldNode->spanChildrenRef, cloneContext);
                return newRef;
            }

            case AstNodeId::AssignList:
            {
                auto*      oldNode     = node.safeCast<AstAssignList>();
                AstNodeRef newRef      = cloneNodeCopy<AstNodeId::AssignList>(sema, node);
                auto&      cloned      = sema.node(newRef).cast<AstAssignList>();
                cloned.spanChildrenRef = cloneSpan(sema, oldNode->spanChildrenRef, cloneContext);
                return newRef;
            }

            case AstNodeId::ReturnStmt:
            {
                auto*      oldNode = node.safeCast<AstReturnStmt>();
                AstNodeRef newRef  = cloneNodeCopy<AstNodeId::ReturnStmt>(sema, node);
                auto&      cloned  = sema.node(newRef).cast<AstReturnStmt>();
                cloned.nodeExprRef = cloneNodeRef(sema, oldNode->nodeExprRef, cloneContext);
                return newRef;
            }

            case AstNodeId::SingleVarDecl:
            {
                auto*      oldNode = node.safeCast<AstSingleVarDecl>();
                AstNodeRef newRef  = cloneNodeCopy<AstNodeId::SingleVarDecl>(sema, node);
                auto&      cloned  = sema.node(newRef).cast<AstSingleVarDecl>();
                cloned.nodeTypeRef = cloneNodeRef(sema, oldNode->nodeTypeRef, cloneContext);
                cloned.nodeInitRef = cloneNodeRef(sema, oldNode->nodeInitRef, cloneContext);
                return newRef;
            }

            case AstNodeId::MultiVarDecl:
            {
                auto*      oldNode = node.safeCast<AstMultiVarDecl>();
                AstNodeRef newRef  = cloneNodeCopy<AstNodeId::MultiVarDecl>(sema, node);
                auto&      cloned  = sema.node(newRef).cast<AstMultiVarDecl>();
                cloned.nodeTypeRef = cloneNodeRef(sema, oldNode->nodeTypeRef, cloneContext);
                cloned.nodeInitRef = cloneNodeRef(sema, oldNode->nodeInitRef, cloneContext);
                return newRef;
            }

            case AstNodeId::VarDeclDestructuring:
            {
                auto*      oldNode = node.safeCast<AstVarDeclDestructuring>();
                AstNodeRef newRef  = cloneNodeCopy<AstNodeId::VarDeclDestructuring>(sema, node);
                auto&      cloned  = sema.node(newRef).cast<AstVarDeclDestructuring>();
                cloned.nodeInitRef = cloneNodeRef(sema, oldNode->nodeInitRef, cloneContext);
                return newRef;
            }

            case AstNodeId::AssignStmt:
            {
                auto*      oldNode  = node.safeCast<AstAssignStmt>();
                AstNodeRef newRef   = cloneNodeCopy<AstNodeId::AssignStmt>(sema, node);
                auto&      cloned   = sema.node(newRef).cast<AstAssignStmt>();
                cloned.nodeLeftRef  = cloneNodeRef(sema, oldNode->nodeLeftRef, cloneContext);
                cloned.nodeRightRef = cloneNodeRef(sema, oldNode->nodeRightRef, cloneContext);
                return newRef;
            }

            case AstNodeId::IfStmt:
            {
                auto*      oldNode      = node.safeCast<AstIfStmt>();
                AstNodeRef newRef       = cloneNodeCopy<AstNodeId::IfStmt>(sema, node);
                auto&      cloned       = sema.node(newRef).cast<AstIfStmt>();
                cloned.nodeConditionRef = cloneNodeRef(sema, oldNode->nodeConditionRef, cloneContext);
                cloned.nodeIfBlockRef   = cloneNodeRef(sema, oldNode->nodeIfBlockRef, cloneContext);
                cloned.nodeElseBlockRef = cloneNodeRef(sema, oldNode->nodeElseBlockRef, cloneContext);
                return newRef;
            }

            case AstNodeId::IfVarDecl:
            {
                auto*      oldNode      = node.safeCast<AstIfVarDecl>();
                AstNodeRef newRef       = cloneNodeCopy<AstNodeId::IfVarDecl>(sema, node);
                auto&      cloned       = sema.node(newRef).cast<AstIfVarDecl>();
                cloned.nodeVarRef       = cloneNodeRef(sema, oldNode->nodeVarRef, cloneContext);
                cloned.nodeWhereRef     = cloneNodeRef(sema, oldNode->nodeWhereRef, cloneContext);
                cloned.nodeIfBlockRef   = cloneNodeRef(sema, oldNode->nodeIfBlockRef, cloneContext);
                cloned.nodeElseBlockRef = cloneNodeRef(sema, oldNode->nodeElseBlockRef, cloneContext);
                return newRef;
            }

            case AstNodeId::WithStmt:
            {
                auto*      oldNode = node.safeCast<AstWithStmt>();
                AstNodeRef newRef  = cloneNodeCopy<AstNodeId::WithStmt>(sema, node);
                auto&      cloned  = sema.node(newRef).cast<AstWithStmt>();
                cloned.nodeExprRef = cloneNodeRef(sema, oldNode->nodeExprRef, cloneContext);
                cloned.nodeBodyRef = cloneNodeRef(sema, oldNode->nodeBodyRef, cloneContext);
                return newRef;
            }

            case AstNodeId::WithVarDecl:
            {
                auto*      oldNode = node.safeCast<AstWithVarDecl>();
                AstNodeRef newRef  = cloneNodeCopy<AstNodeId::WithVarDecl>(sema, node);
                auto&      cloned  = sema.node(newRef).cast<AstWithVarDecl>();
                cloned.nodeVarRef  = cloneNodeRef(sema, oldNode->nodeVarRef, cloneContext);
                cloned.nodeBodyRef = cloneNodeRef(sema, oldNode->nodeBodyRef, cloneContext);
                return newRef;
            }

            case AstNodeId::DeferStmt:
            {
                auto*      oldNode = node.safeCast<AstDeferStmt>();
                AstNodeRef newRef  = cloneNodeCopy<AstNodeId::DeferStmt>(sema, node);
                auto&      cloned  = sema.node(newRef).cast<AstDeferStmt>();
                cloned.nodeBodyRef = cloneNodeRef(sema, oldNode->nodeBodyRef, cloneContext);
                return newRef;
            }

            case AstNodeId::WhileStmt:
            {
                auto*      oldNode = node.safeCast<AstWhileStmt>();
                AstNodeRef newRef  = cloneNodeCopy<AstNodeId::WhileStmt>(sema, node);
                auto&      cloned  = sema.node(newRef).cast<AstWhileStmt>();
                cloned.nodeExprRef = cloneNodeRef(sema, oldNode->nodeExprRef, cloneContext);
                cloned.nodeBodyRef = cloneNodeRef(sema, oldNode->nodeBodyRef, cloneContext);
                return newRef;
            }

            case AstNodeId::ForeachStmt:
            {
                auto*      oldNode  = node.safeCast<AstForeachStmt>();
                AstNodeRef newRef   = cloneNodeCopy<AstNodeId::ForeachStmt>(sema, node);
                auto&      cloned   = sema.node(newRef).cast<AstForeachStmt>();
                cloned.nodeExprRef  = cloneNodeRef(sema, oldNode->nodeExprRef, cloneContext);
                cloned.nodeWhereRef = cloneNodeRef(sema, oldNode->nodeWhereRef, cloneContext);
                cloned.nodeBodyRef  = cloneNodeRef(sema, oldNode->nodeBodyRef, cloneContext);
                return newRef;
            }

            case AstNodeId::ForCStyleStmt:
            {
                auto*      oldNode     = node.safeCast<AstForCStyleStmt>();
                AstNodeRef newRef      = cloneNodeCopy<AstNodeId::ForCStyleStmt>(sema, node);
                auto&      cloned      = sema.node(newRef).cast<AstForCStyleStmt>();
                cloned.nodeVarDeclRef  = cloneNodeRef(sema, oldNode->nodeVarDeclRef, cloneContext);
                cloned.nodeExprRef     = cloneNodeRef(sema, oldNode->nodeExprRef, cloneContext);
                cloned.nodePostStmtRef = cloneNodeRef(sema, oldNode->nodePostStmtRef, cloneContext);
                cloned.nodeBodyRef     = cloneNodeRef(sema, oldNode->nodeBodyRef, cloneContext);
                return newRef;
            }

            case AstNodeId::ForStmt:
            {
                auto*      oldNode  = node.safeCast<AstForStmt>();
                AstNodeRef newRef   = cloneNodeCopy<AstNodeId::ForStmt>(sema, node);
                auto&      cloned   = sema.node(newRef).cast<AstForStmt>();
                cloned.nodeExprRef  = cloneNodeRef(sema, oldNode->nodeExprRef, cloneContext);
                cloned.nodeWhereRef = cloneNodeRef(sema, oldNode->nodeWhereRef, cloneContext);
                cloned.nodeBodyRef  = cloneNodeRef(sema, oldNode->nodeBodyRef, cloneContext);
                return newRef;
            }

            case AstNodeId::InfiniteLoopStmt:
            {
                auto*      oldNode = node.safeCast<AstInfiniteLoopStmt>();
                AstNodeRef newRef  = cloneNodeCopy<AstNodeId::InfiniteLoopStmt>(sema, node);
                auto&      cloned  = sema.node(newRef).cast<AstInfiniteLoopStmt>();
                cloned.nodeBodyRef = cloneNodeRef(sema, oldNode->nodeBodyRef, cloneContext);
                return newRef;
            }

            case AstNodeId::TryCatchStmt:
            {
                auto*      oldNode = node.safeCast<AstTryCatchStmt>();
                AstNodeRef newRef  = cloneNodeCopy<AstNodeId::TryCatchStmt>(sema, node);
                auto&      cloned  = sema.node(newRef).cast<AstTryCatchStmt>();
                cloned.nodeBodyRef = cloneNodeRef(sema, oldNode->nodeBodyRef, cloneContext);
                return newRef;
            }

            case AstNodeId::SwitchStmt:
            {
                auto*      oldNode     = node.safeCast<AstSwitchStmt>();
                AstNodeRef newRef      = cloneNodeCopy<AstNodeId::SwitchStmt>(sema, node);
                auto&      cloned      = sema.node(newRef).cast<AstSwitchStmt>();
                cloned.nodeExprRef     = cloneNodeRef(sema, oldNode->nodeExprRef, cloneContext);
                cloned.spanChildrenRef = cloneSpan(sema, oldNode->spanChildrenRef, cloneContext);
                return newRef;
            }

            case AstNodeId::SwitchCaseStmt:
            {
                auto*      oldNode  = node.safeCast<AstSwitchCaseStmt>();
                AstNodeRef newRef   = cloneNodeCopy<AstNodeId::SwitchCaseStmt>(sema, node);
                auto&      cloned   = sema.node(newRef).cast<AstSwitchCaseStmt>();
                cloned.nodeWhereRef = cloneNodeRef(sema, oldNode->nodeWhereRef, cloneContext);
                cloned.spanExprRef  = cloneSpan(sema, oldNode->spanExprRef, cloneContext);
                cloned.nodeBodyRef  = cloneNodeRef(sema, oldNode->nodeBodyRef, cloneContext);
                return newRef;
            }

            case AstNodeId::CompilerScope:
            {
                auto*      oldNode = node.safeCast<AstCompilerScope>();
                AstNodeRef newRef  = cloneNodeCopy<AstNodeId::CompilerScope>(sema, node);
                auto&      cloned  = sema.node(newRef).cast<AstCompilerScope>();
                cloned.nodeBodyRef = cloneNodeRef(sema, oldNode->nodeBodyRef, cloneContext);
                return newRef;
            }

            case AstNodeId::CompilerRunBlock:
            {
                auto*      oldNode = node.safeCast<AstCompilerRunBlock>();
                AstNodeRef newRef  = cloneNodeCopy<AstNodeId::CompilerRunBlock>(sema, node);
                auto&      cloned  = sema.node(newRef).cast<AstCompilerRunBlock>();
                cloned.nodeBodyRef = cloneNodeRef(sema, oldNode->nodeBodyRef, cloneContext);
                return newRef;
            }

            case AstNodeId::CompilerCodeBlock:
            {
                auto*      oldNode = node.safeCast<AstCompilerCodeBlock>();
                AstNodeRef newRef  = cloneNodeCopy<AstNodeId::CompilerCodeBlock>(sema, node);
                auto&      cloned  = sema.node(newRef).cast<AstCompilerCodeBlock>();
                cloned.nodeBodyRef = cloneNodeRef(sema, oldNode->nodeBodyRef, cloneContext);
                return newRef;
            }

            case AstNodeId::CompilerShortFunc:
            {
                auto*      oldNode = node.safeCast<AstCompilerShortFunc>();
                AstNodeRef newRef  = cloneNodeCopy<AstNodeId::CompilerShortFunc>(sema, node);
                auto&      cloned  = sema.node(newRef).cast<AstCompilerShortFunc>();
                cloned.nodeBodyRef = cloneNodeRef(sema, oldNode->nodeBodyRef, cloneContext);
                return newRef;
            }

            case AstNodeId::CompilerMessageFunc:
            {
                auto*      oldNode  = node.safeCast<AstCompilerMessageFunc>();
                AstNodeRef newRef   = cloneNodeCopy<AstNodeId::CompilerMessageFunc>(sema, node);
                auto&      cloned   = sema.node(newRef).cast<AstCompilerMessageFunc>();
                cloned.nodeParamRef = cloneNodeRef(sema, oldNode->nodeParamRef, cloneContext);
                cloned.nodeBodyRef  = cloneNodeRef(sema, oldNode->nodeBodyRef, cloneContext);
                return newRef;
            }

            case AstNodeId::CompilerMacro:
            {
                auto*      oldNode = node.safeCast<AstCompilerMacro>();
                AstNodeRef newRef  = cloneNodeCopy<AstNodeId::CompilerMacro>(sema, node);
                auto&      cloned  = sema.node(newRef).cast<AstCompilerMacro>();
                cloned.nodeBodyRef = cloneNodeRef(sema, oldNode->nodeBodyRef, cloneContext);
                return newRef;
            }

            case AstNodeId::CompilerInject:
            {
                auto*      oldNode            = node.safeCast<AstCompilerInject>();
                AstNodeRef newRef             = cloneNodeCopy<AstNodeId::CompilerInject>(sema, node);
                auto&      cloned             = sema.node(newRef).cast<AstCompilerInject>();
                cloned.nodeExprRef            = cloneNodeRef(sema, oldNode->nodeExprRef, cloneContext);
                cloned.nodeReplaceBreakRef    = cloneNodeRef(sema, oldNode->nodeReplaceBreakRef, cloneContext);
                cloned.nodeReplaceContinueRef = cloneNodeRef(sema, oldNode->nodeReplaceContinueRef, cloneContext);
                return newRef;
            }

            default:
                break;
        }

        return AstNodeRef::invalid();
    }

    AstNodeRef cloneIdentifier(Sema& sema, const AstIdentifier& node, const CloneContext& cloneContext)
    {
        const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), node.codeRef());
        if (const SemaClone::ParamBinding* binding = findBinding(cloneContext, idRef))
        {
            const SemaClone::CloneContext noBindings{std::span<const SemaClone::ParamBinding>{}};
            return SemaClone::cloneAst(sema, binding->exprRef, noBindings);
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
    AstNodeRef clonedRef = Ast::nodeIdInfos(node.id()).semaClone(sema, node, cloneContext);
    if (clonedRef.isValid())
        return clonedRef;

    clonedRef = cloneStatementFallback(sema, node, cloneContextAsInline(cloneContext));
    if (clonedRef.isValid())
        return clonedRef;

    clonedRef = cloneShallowNode(sema, node);
    SWC_ASSERT(clonedRef.isValid());
    return clonedRef;
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
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    newPtr->nodeSuffixRef = SemaClone::cloneAst(sema, nodeSuffixRef, cloneContextAsInline(cloneContext));
    return newRef;
}

AstNodeRef AstQuotedListExpr::semaClone(Sema& sema, const CloneContext& cloneContext) const
{
    auto [newRef, newPtr]   = sema.ast().makeNode<AstNodeId::QuotedListExpr>(tokRef());
    newPtr->nodeExprRef     = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
    newPtr->spanChildrenRef = cloneSpan(sema, spanChildrenRef, cloneContextAsInline(cloneContext));
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
    auto [newRef, newPtr] = sema.ast().makeNode<AstNodeId::CompilerCodeExpr>(tokRef());
    newPtr->nodeExprRef   = SemaClone::cloneAst(sema, nodeExprRef, cloneContextAsInline(cloneContext));
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
