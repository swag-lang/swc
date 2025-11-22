// ReSharper disable CppPossiblyUninitializedMember
#pragma once
#include "Core/SmallVector.h"
#include "Parser/AstNode.h"
#include "Parser/AstNodeId.h"

SWC_BEGIN_NAMESPACE()
enum class AstVisitStepResult;

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

template<AstNodeId I>
struct AstCompoundT : AstNodeT<I>
{
    SpanRef spanChildren;

    explicit AstCompoundT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, ast, spanChildren);
    }
};

template<AstNodeId I>
struct AstLambdaExprT : AstNodeT<I>
{
    SpanRef    spanArgs;
    AstNodeRef nodeReturnType;
    AstNodeRef nodeBody;

    explicit AstLambdaExprT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, ast, spanArgs);
        AstNode::collectChildren(out, {nodeReturnType, nodeBody});
    }
};

template<AstNodeId I>
struct AstBinaryT : AstNodeT<I>
{
    AstNodeRef nodeLeft;
    AstNodeRef nodeRight;

    explicit AstBinaryT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const
    {
        AstNode::collectChildren(out, {nodeLeft, nodeRight});
    }
};

template<AstNodeId I>
struct AstLiteralT : AstNodeT<I>
{
    explicit AstLiteralT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }
};

template<AstNodeId I>
struct AstAggregateDeclT : AstNodeT<I>
{
    TokenRef   tokName;
    SpanRef    spanGenericParams;
    SpanRef    spanWhere;
    AstNodeRef nodeBody;

    explicit AstAggregateDeclT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, ast, spanGenericParams);
        AstNode::collectChildren(out, ast, spanWhere);
        AstNode::collectChildren(out, {nodeBody});
    }
};

template<AstNodeId I>
struct AstAnonymousAggregateDeclT : AstNodeT<I>
{
    AstNodeRef nodeBody;

    explicit AstAnonymousAggregateDeclT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const
    {
        AstNode::collectChildren(out, {nodeBody});
    }
};

template<AstNodeId I>
struct AstIfBaseT : AstNodeT<I>
{
    AstNodeRef nodeIfBlock;
    AstNodeRef nodeElseBlock;

    explicit AstIfBaseT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const
    {
        AstNode::collectChildren(out, {nodeIfBlock, nodeElseBlock});
    }
};

template<AstNodeId I>
struct AstIntrinsicInitDropCopyMoveT : AstNodeT<I>
{
    AstNodeRef nodeWhat;
    AstNodeRef nodeCount;

    explicit AstIntrinsicInitDropCopyMoveT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const
    {
        AstNode::collectChildren(out, {nodeWhat, nodeCount});
    }
};

// ReSharper disable once CppUnusedIncludeDirective
#include "Parser/AstNodesDef.inc"

template<AstNodeId ID>
struct AstTypeOf;

#define SWC_NODE_DEF(E)            \
    template<>                     \
    struct AstTypeOf<AstNodeId::E> \
    {                              \
        using type = Ast##E;       \
    };
#include "Parser/AstNodesEnum.inc"
#undef SWC_NODE_DEF

template<class F>
decltype(auto) visitAstNodeId(AstNodeId id, F f)
{
    switch (id)
    {
#define SWC_NODE_DEF(E) \
    case AstNodeId::E:  \
        return std::forward<F>(f).operator()<AstNodeId::E>();
#include "Parser/AstNodesEnum.inc"

#undef SWC_NODE_DEF
        default:
            SWC_UNREACHABLE();
    }
}

struct AstNodeIdInfo
{
    std::string_view name;

    using CollectFunc  = void (*)(SmallVector<AstNodeRef>&, const Ast&, const AstNode&);
    using SemaPreNode  = AstVisitStepResult (*)(SemaJob&, AstNode&);
    using SemaPostNode = AstVisitStepResult (*)(SemaJob&, AstNode&);
    using SemaPreChild = AstVisitStepResult (*)(SemaJob&, AstNode&, AstNodeRef&);

    CollectFunc  collectChildren;
    SemaPreNode  semaPreNode;
    SemaPreNode  semaPostNode;
    SemaPreChild semaPreChild;
};

template<AstNodeId ID>
void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast, const AstNode& node)
{
    using NodeType = AstTypeOf<ID>::type;
    castAst<NodeType>(&node)->collectChildren(out, ast);
}

template<AstNodeId ID>
AstVisitStepResult semaPreNode(SemaJob& job, AstNode& node)
{
    using NodeType = AstTypeOf<ID>::type;
    return castAst<NodeType>(&node)->semaPreNode(job);
}

template<AstNodeId ID>
AstVisitStepResult semaPostNode(SemaJob& job, AstNode& node)
{
    using NodeType = AstTypeOf<ID>::type;
    return castAst<NodeType>(&node)->semaPostNode(job);
}

template<AstNodeId ID>
AstVisitStepResult semaPreChild(SemaJob& job, AstNode& node, AstNodeRef& childRef)
{
    using NodeType = AstTypeOf<ID>::type;
    return castAst<NodeType>(&node)->semaPreChild(job, childRef);
}

constexpr std::array AST_NODE_ID_INFOS = {
#define SWC_NODE_DEF(enum) AstNodeIdInfo{                         \
                               #enum,                             \
                               &collectChildren<AstNodeId::enum>, \
                               &semaPreNode<AstNodeId::enum>,     \
                               &semaPostNode<AstNodeId::enum>,    \
                               &semaPreChild<AstNodeId::enum>},
#include "Parser/AstNodesEnum.inc"

#undef SWC_NODE_DEF
};

SWC_END_NAMESPACE()
