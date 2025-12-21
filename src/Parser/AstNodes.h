// ReSharper disable CppPossiblyUninitializedMember
#pragma once
#include "Core/SmallVector.h"
#include "Parser/AstNode.h"
#include "Parser/AstNodeId.h"
#include "Sema/Helpers/SemaScope.h"

SWC_BEGIN_NAMESPACE()
enum class AstVisitStepResult;

// -----------------------------------------------------------------------------
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

template<AstNodeId I>
struct AstInternalCallZeroT : AstNodeT<I>
{
    explicit AstInternalCallZeroT(SourceViewRef srcViewRef, TokenRef tokRef) :
        AstNodeT<I>(srcViewRef, tokRef)
    {
    }
};

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

// ReSharper disable once CppUnusedIncludeDirective
#include "Parser/AstNodesDef.inc"

template<AstNodeId ID>
struct AstTypeOf;

#define SWC_NODE_DEF(__enum, __flags, __scopeFlags) \
    template<>                                      \
    struct AstTypeOf<AstNodeId::__enum>             \
    {                                               \
        using type = Ast##__enum;                   \
    };
#include "Parser/AstNodesEnum.inc"
#undef SWC_NODE_DEF

template<class F>
decltype(auto) visitAstNodeId(AstNodeId id, F f)
{
    switch (id)
    {
#define SWC_NODE_DEF(__enum, __flags, __scopeFlags) \
    case AstNodeId::__enum:                         \
        return std::forward<F>(f).template operator()<AstNodeId::__enum>();
#include "Parser/AstNodesEnum.inc"

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
    SemaScopeFlags   scopeFlags;

    using CollectChildren = void (*)(SmallVector<AstNodeRef>&, const Ast&, const AstNode&);
    using SemaEnterNode   = void (*)(Sema&, AstNode&);
    using SemaPreNode     = AstVisitStepResult (*)(Sema&, AstNode&);
    using SemaPostNode    = AstVisitStepResult (*)(Sema&, AstNode&);
    using SemaPreChild    = AstVisitStepResult (*)(Sema&, AstNode&, AstNodeRef&);

    CollectChildren collectChildren;
    SemaEnterNode   semaEnterNode;
    SemaPreNode     semaPreNode;
    SemaPreNode     semaPostNode;
    SemaPreChild    semaPreChild;

    bool hasFlag(AstNodeIdFlagsE flag) const { return flags.has(flag); }
};

template<AstNodeId ID>
void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast, const AstNode& node)
{
    using NodeType = AstTypeOf<ID>::type;
    castAst<NodeType>(&node)->collectChildren(out, ast);
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
AstVisitStepResult semaPostNode(Sema& sema, AstNode& node)
{
    using NodeType = AstTypeOf<ID>::type;
    return castAst<NodeType>(&node)->semaPostNode(sema);
}

template<AstNodeId ID>
AstVisitStepResult semaPreChild(Sema& sema, AstNode& node, AstNodeRef& childRef)
{
    using NodeType = AstTypeOf<ID>::type;
    return castAst<NodeType>(&node)->semaPreChild(sema, childRef);
}

constexpr std::array AST_NODE_ID_INFOS = {
#define SWC_NODE_DEF(__enum, __flags, __scopeFlags) AstNodeIdInfo{                           \
                                                        #__enum,                             \
                                                        __flags,                             \
                                                        __scopeFlags,                        \
                                                        &collectChildren<AstNodeId::__enum>, \
                                                        &semaEnterNode<AstNodeId::__enum>,   \
                                                        &semaPreNode<AstNodeId::__enum>,     \
                                                        &semaPostNode<AstNodeId::__enum>,    \
                                                        &semaPreChild<AstNodeId::__enum>},
#include "Parser/AstNodesEnum.inc"

#undef SWC_NODE_DEF
};

SWC_END_NAMESPACE()
