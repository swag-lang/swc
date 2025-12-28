// ReSharper disable CppPossiblyUninitializedMember
#pragma once
#include "Core/SmallVector.h"
#include "Parser/AstNode.h"
#include "Parser/AstNodeId.h"

SWC_BEGIN_NAMESPACE()
enum class AstVisitStepResult;

// -----------------------------------------------------------------------------
template<AstNodeId I>
struct AstNamedNodeT : AstNodeT<I>
{
    TokenRef tokNameRef;

    explicit AstNamedNodeT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I>
struct AstCompoundT : AstNodeT<I>
{
    SpanRef spanChildrenRef;

    explicit AstCompoundT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, ast, spanChildrenRef);
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I>
struct AstLambdaExprT : AstNodeT<I>
{
    SpanRef    spanArgsRef;
    AstNodeRef nodeReturnTypeRef;
    AstNodeRef nodeBodyRef;

    explicit AstLambdaExprT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, ast, spanArgsRef);
        AstNode::collectChildren(out, {nodeReturnTypeRef, nodeBodyRef});
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I>
struct AstBinaryT : AstNodeT<I>
{
    AstNodeRef nodeLeftRef;
    AstNodeRef nodeRightRef;

    explicit AstBinaryT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const
    {
        AstNode::collectChildren(out, {nodeLeftRef, nodeRightRef});
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I>
struct AstLiteralT : AstNodeT<I>
{
    explicit AstLiteralT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I>
struct AstAggregateDeclT : AstNodeT<I>
{
    TokenRef   tokNameRef;
    SpanRef    spanGenericParamsRef;
    SpanRef    spanWhereRef;
    AstNodeRef nodeBodyRef;

    explicit AstAggregateDeclT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, ast, spanGenericParamsRef);
        AstNode::collectChildren(out, ast, spanWhereRef);
        AstNode::collectChildren(out, {nodeBodyRef});
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I>
struct AstAnonymousAggregateDeclT : AstNodeT<I>
{
    AstNodeRef nodeBodyRef;

    explicit AstAnonymousAggregateDeclT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const
    {
        AstNode::collectChildren(out, {nodeBodyRef});
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I>
struct AstIfBaseT : AstNodeT<I>
{
    AstNodeRef nodeIfBlockRef;
    AstNodeRef nodeElseBlockRef;

    explicit AstIfBaseT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const
    {
        AstNode::collectChildren(out, {nodeIfBlockRef, nodeElseBlockRef});
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I>
struct AstIntrinsicInitDropCopyMoveT : AstNodeT<I>
{
    AstNodeRef nodeWhatRef;
    AstNodeRef nodeCountRef;

    explicit AstIntrinsicInitDropCopyMoveT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const
    {
        AstNode::collectChildren(out, {nodeWhatRef, nodeCountRef});
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I>
struct AstInternalCallZeroT : AstNodeT<I>
{
    explicit AstInternalCallZeroT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I>
struct AstInternalCallUnaryT : AstNodeT<I>
{
    AstNodeRef nodeArgRef;

    explicit AstInternalCallUnaryT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const
    {
        AstNode::collectChildren(out, {nodeArgRef});
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I>
struct AstInternalCallBinaryT : AstNodeT<I>
{
    AstNodeRef nodeArg1Ref;
    AstNodeRef nodeArg2Ref;

    explicit AstInternalCallBinaryT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const
    {
        AstNode::collectChildren(out, {nodeArg1Ref, nodeArg2Ref});
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I>
struct AstInternalCallTernaryT : AstNodeT<I>
{
    AstNodeRef nodeArg1Ref;
    AstNodeRef nodeArg2Ref;
    AstNodeRef nodeArg3Ref;

    explicit AstInternalCallTernaryT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const
    {
        AstNode::collectChildren(out, {nodeArg1Ref, nodeArg2Ref, nodeArg3Ref});
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I>
struct AstGenericParamT : AstNodeT<I>
{
    AstNodeRef nodeAssignRef;

    explicit AstGenericParamT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const
    {
        AstNode::collectChildren(out, {nodeAssignRef});
    }
};

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

// ReSharper disable once CppUnusedIncludeDirective
#include "Parser/AstNodesStruct.inc"

// -----------------------------------------------------------------------------
// -----------------------------------------------------------------------------

template<AstNodeId ID>
struct AstTypeOf;

#define SWC_NODE_DEF(__enum, __flags)   \
    template<>                          \
    struct AstTypeOf<AstNodeId::__enum> \
    {                                   \
        using type = Ast##__enum;       \
    };
#include "Parser/AstNodesDef.inc"
#undef SWC_NODE_DEF

template<class F>
decltype(auto) visitAstNodeId(AstNodeId id, F f)
{
    switch (id)
    {
#define SWC_NODE_DEF(__enum, __flags) \
    case AstNodeId::__enum:           \
        return std::forward<F>(f).template operator()<AstNodeId::__enum>();
#include "Parser/AstNodesDef.inc"

#undef SWC_NODE_DEF
        default:
            SWC_UNREACHABLE();
    }
}

enum class AstNodeIdFlagsE
{
    Zero    = 0,
    SemaJob = 1 << 0,
};
using AstNodeIdFlags = EnumFlags<AstNodeIdFlagsE>;

struct AstNodeIdInfo
{
    std::string_view name;
    AstNodeIdFlags   flags;

    using AstCollectChildren = void (*)(SmallVector<AstNodeRef>&, const Ast&, const AstNode&);
    using SemaEnterNode      = void (*)(Sema&, AstNode&);
    using SemaPreNode        = AstVisitStepResult (*)(Sema&, AstNode&);
    using SemaPreNodeChild   = AstVisitStepResult (*)(Sema&, AstNode&, AstNodeRef&);
    using SemaPostNode       = AstVisitStepResult (*)(Sema&, AstNode&);

    AstCollectChildren collectChildren;

    SemaPreNode      semaPreDecl;
    SemaPreNodeChild semaPreDeclChild;
    SemaPostNode     semaPostDecl;

    SemaEnterNode    semaEnterNode;
    SemaPreNode      semaPreNode;
    SemaPreNodeChild semaPreNodeChild;
    SemaPostNode     semaPostNode;

    bool hasFlag(AstNodeIdFlagsE flag) const { return flags.has(flag); }
};

template<AstNodeId ID>
void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast, const AstNode& node)
{
    using NodeType = AstTypeOf<ID>::type;
    castAst<NodeType>(&node)->collectChildren(out, ast);
}

template<AstNodeId ID>
AstVisitStepResult semaPreDecl(Sema& sema, AstNode& node)
{
    using NodeType = AstTypeOf<ID>::type;
    return castAst<NodeType>(&node)->semaPreDecl(sema);
}

template<AstNodeId ID>
AstVisitStepResult semaPreDeclChild(Sema& sema, AstNode& node, AstNodeRef& childRef)
{
    using NodeType = AstTypeOf<ID>::type;
    return castAst<NodeType>(&node)->semaPreDeclChild(sema, childRef);
}

template<AstNodeId ID>
AstVisitStepResult semaPostDecl(Sema& sema, AstNode& node)
{
    using NodeType = AstTypeOf<ID>::type;
    return castAst<NodeType>(&node)->semaPostDecl(sema);
}

template<AstNodeId ID>
void semaEnterNode(Sema& sema, AstNode& node)
{
    using NodeType = AstTypeOf<ID>::type;
    castAst<NodeType>(&node)->semaEnterNode(sema);
}

template<AstNodeId ID>
AstVisitStepResult semaPreNode(Sema& sema, AstNode& node)
{
    using NodeType = AstTypeOf<ID>::type;
    return castAst<NodeType>(&node)->semaPreNode(sema);
}

template<AstNodeId ID>
AstVisitStepResult semaPreNodeChild(Sema& sema, AstNode& node, AstNodeRef& childRef)
{
    using NodeType = AstTypeOf<ID>::type;
    return castAst<NodeType>(&node)->semaPreNodeChild(sema, childRef);
}

template<AstNodeId ID>
AstVisitStepResult semaPostNode(Sema& sema, AstNode& node)
{
    using NodeType = AstTypeOf<ID>::type;
    return castAst<NodeType>(&node)->semaPostNode(sema);
}

constexpr std::array AST_NODE_ID_INFOS = {
#define SWC_NODE_DEF(__enum, __flags) AstNodeIdInfo{                            \
                                          #__enum,                              \
                                          __flags,                              \
                                          &collectChildren<AstNodeId::__enum>,  \
                                          &semaPreDecl<AstNodeId::__enum>,      \
                                          &semaPreDeclChild<AstNodeId::__enum>, \
                                          &semaPostDecl<AstNodeId::__enum>,     \
                                          &semaEnterNode<AstNodeId::__enum>,    \
                                          &semaPreNode<AstNodeId::__enum>,      \
                                          &semaPreNodeChild<AstNodeId::__enum>, \
                                          &semaPostNode<AstNodeId::__enum>},
#include "Parser/AstNodesDef.inc"

#undef SWC_NODE_DEF
};

SWC_END_NAMESPACE()
