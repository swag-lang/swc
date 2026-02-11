// ReSharper disable CppPossiblyUninitializedMember
#pragma once
#include "Compiler/Parser/Ast/AstNode.h"
#include "Compiler/Parser/Ast/AstNodeId.h"
#include "Support/Core/SmallVector.h"

SWC_BEGIN_NAMESPACE();

// -----------------------------------------------------------------------------
template<AstNodeId I, typename E = void>
struct AstNamedNodeT : AstNodeT<I, E>
{
    TokenRef tokNameRef;

    explicit AstNamedNodeT(SourceCodeRef codeRef) :
        AstNodeT<I, E>(codeRef)
    {
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I, typename E = void>
struct AstCompoundT : AstNodeT<I, E>
{
    SpanRef spanChildrenRef;

    explicit AstCompoundT(SourceCodeRef codeRef) :
        AstNodeT<I, E>(codeRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, ast, spanChildrenRef);
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I, typename E = void>
struct AstCallExprT : AstCompoundT<I, E>
{
    AstNodeRef nodeExprRef;

    explicit AstCallExprT(SourceCodeRef codeRef) :
        AstCompoundT<I, E>(codeRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, {nodeExprRef});
        AstCompoundT<I, E>::collectChildren(out, ast);
    }

    void collectArguments(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstCompoundT<I, E>::collectChildren(out, ast);
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I, typename E = void>
struct AstLambdaExprT : AstNodeT<I, E>
{
    SpanRef    spanArgsRef;
    AstNodeRef nodeReturnTypeRef;
    AstNodeRef nodeBodyRef;

    explicit AstLambdaExprT(SourceCodeRef codeRef) :
        AstNodeT<I, E>(codeRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast) const
    {
        AstNode::collectChildren(out, ast, spanArgsRef);
        AstNode::collectChildren(out, {nodeReturnTypeRef, nodeBodyRef});
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I, typename E = void>
struct AstBinaryT : AstNodeT<I, E>
{
    AstNodeRef nodeLeftRef;
    AstNodeRef nodeRightRef;

    explicit AstBinaryT(SourceCodeRef codeRef) :
        AstNodeT<I, E>(codeRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const
    {
        AstNode::collectChildren(out, {nodeLeftRef, nodeRightRef});
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I, typename E = void>
struct AstLiteralT : AstNodeT<I, E>
{
    explicit AstLiteralT(SourceCodeRef codeRef) :
        AstNodeT<I, E>(codeRef)
    {
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I, typename E = void>
struct AstAggregateDeclT : AstNodeT<I, E>
{
    TokenRef   tokNameRef;
    SpanRef    spanGenericParamsRef;
    SpanRef    spanWhereRef;
    AstNodeRef nodeBodyRef;

    explicit AstAggregateDeclT(SourceCodeRef codeRef) :
        AstNodeT<I, E>(codeRef)
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
template<AstNodeId I, typename E = void>
struct AstAnonymousAggregateDeclT : AstNodeT<I, E>
{
    AstNodeRef nodeBodyRef;

    explicit AstAnonymousAggregateDeclT(SourceCodeRef codeRef) :
        AstNodeT<I, E>(codeRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const
    {
        AstNode::collectChildren(out, {nodeBodyRef});
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I, typename E = void>
struct AstIfBaseT : AstNodeT<I, E>
{
    AstNodeRef nodeIfBlockRef;
    AstNodeRef nodeElseBlockRef;

    explicit AstIfBaseT(SourceCodeRef codeRef) :
        AstNodeT<I, E>(codeRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const
    {
        AstNode::collectChildren(out, {nodeIfBlockRef, nodeElseBlockRef});
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I, typename E = void>
struct AstIntrinsicInitDropCopyMoveT : AstNodeT<I, E>
{
    AstNodeRef nodeWhatRef;
    AstNodeRef nodeCountRef;

    explicit AstIntrinsicInitDropCopyMoveT(SourceCodeRef codeRef) :
        AstNodeT<I, E>(codeRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const
    {
        AstNode::collectChildren(out, {nodeWhatRef, nodeCountRef});
    }
};

// -----------------------------------------------------------------------------
struct AstVarDeclBase
{
    AstNodeRef nodeTypeRef;
    AstNodeRef nodeInitRef;

    void collectVarChildren(SmallVector<AstNodeRef>& out) const
    {
        AstNode::collectChildren(out, {nodeTypeRef, nodeInitRef});
    }

    AstNodeRef typeOrInitRef() const
    {
        return nodeTypeRef.isValid() ? nodeTypeRef : nodeInitRef;
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I, typename E = void>
struct AstInternalCallZeroT : AstNodeT<I, E>
{
    explicit AstInternalCallZeroT(SourceCodeRef codeRef) :
        AstNodeT<I, E>(codeRef)
    {
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I, typename E = void>
struct AstInternalCallUnaryT : AstNodeT<I, E>
{
    AstNodeRef nodeArgRef;

    explicit AstInternalCallUnaryT(SourceCodeRef codeRef) :
        AstNodeT<I, E>(codeRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const
    {
        AstNode::collectChildren(out, {nodeArgRef});
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I, typename E = void>
struct AstInternalCallBinaryT : AstNodeT<I, E>
{
    AstNodeRef nodeArg1Ref;
    AstNodeRef nodeArg2Ref;

    explicit AstInternalCallBinaryT(SourceCodeRef codeRef) :
        AstNodeT<I, E>(codeRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const
    {
        AstNode::collectChildren(out, {nodeArg1Ref, nodeArg2Ref});
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I, typename E = void>
struct AstInternalCallTernaryT : AstNodeT<I, E>
{
    AstNodeRef nodeArg1Ref;
    AstNodeRef nodeArg2Ref;
    AstNodeRef nodeArg3Ref;

    explicit AstInternalCallTernaryT(SourceCodeRef codeRef) :
        AstNodeT<I, E>(codeRef)
    {
    }

    void collectChildren(SmallVector<AstNodeRef>& out, const Ast&) const
    {
        AstNode::collectChildren(out, {nodeArg1Ref, nodeArg2Ref, nodeArg3Ref});
    }
};

// -----------------------------------------------------------------------------
template<AstNodeId I, typename E = void>
struct AstGenericParamT : AstNodeT<I, E>
{
    AstNodeRef nodeAssignRef;

    explicit AstGenericParamT(SourceCodeRef codeRef) :
        AstNodeT<I, E>(codeRef)
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
#include "Compiler/Parser/Ast/AstNodes.Struct.inc"

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
#include "Compiler/Parser/Ast/AstNodes.Def.inc"
#undef SWC_NODE_DEF

template<class F>
decltype(auto) visitAstNodeId(AstNodeId id, F f)
{
    switch (id)
    {
#define SWC_NODE_DEF(__enum, __flags) \
    case AstNodeId::__enum:           \
        return std::forward<F>(f).template operator()<AstNodeId::__enum>();
#include "Compiler/Parser/Ast/AstNodes.Def.inc"

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
    using SemaPreNode        = Result (*)(Sema&, AstNode&);
    using SemaPreNodeChild   = Result (*)(Sema&, AstNode&, AstNodeRef&);
    using SemaPostNodeChild  = Result (*)(Sema&, AstNode&, AstNodeRef&);
    using SemaPostNode       = Result (*)(Sema&, AstNode&);
    using SemaErrorCleanup   = void (*)(Sema&, AstNode&, AstNodeRef);
    using SemaInlineClone    = AstNodeRef (*)(Sema&, AstNode&, const CloneContext&);

    AstCollectChildren collectChildren;

    SemaPreNode       semaPreDecl;
    SemaPreNodeChild  semaPreDeclChild;
    SemaPostNodeChild semaPostDeclChild;
    SemaPostNode      semaPostDecl;

    SemaPreNode       semaPreNode;
    SemaPreNodeChild  semaPreNodeChild;
    SemaPostNodeChild semaPostNodeChild;
    SemaPostNode      semaPostNode;
    SemaErrorCleanup  semaErrorCleanup;
    SemaInlineClone   semaInlineClone;

    bool hasFlag(AstNodeIdFlagsE flag) const { return flags.has(flag); }
};

template<AstNodeId ID>
void collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast, const AstNode& node)
{
    using NodeType = AstTypeOf<ID>::type;
    node.cast<NodeType>()->collectChildren(out, ast);
}

template<AstNodeId ID>
Result semaPreDecl(Sema& sema, AstNode& node)
{
    using NodeType = AstTypeOf<ID>::type;
    return node.cast<NodeType>()->semaPreDecl(sema);
}

template<AstNodeId ID>
Result semaPreDeclChild(Sema& sema, AstNode& node, AstNodeRef& childRef)
{
    using NodeType = AstTypeOf<ID>::type;
    return node.cast<NodeType>()->semaPreDeclChild(sema, childRef);
}

template<AstNodeId ID>
Result semaPostDeclChild(Sema& sema, AstNode& node, AstNodeRef& childRef)
{
    using NodeType = AstTypeOf<ID>::type;
    return node.cast<NodeType>()->semaPostDeclChild(sema, childRef);
}

template<AstNodeId ID>
Result semaPostDecl(Sema& sema, AstNode& node)
{
    using NodeType = AstTypeOf<ID>::type;
    return node.cast<NodeType>()->semaPostDecl(sema);
}

template<AstNodeId ID>
Result semaPreNode(Sema& sema, AstNode& node)
{
    using NodeType = AstTypeOf<ID>::type;
    return node.cast<NodeType>()->semaPreNode(sema);
}

template<AstNodeId ID>
Result semaPreNodeChild(Sema& sema, AstNode& node, AstNodeRef& childRef)
{
    SWC_ASSERT(childRef.isValid());
    using NodeType = AstTypeOf<ID>::type;
    return node.cast<NodeType>()->semaPreNodeChild(sema, childRef);
}

template<AstNodeId ID>
Result semaPostNodeChild(Sema& sema, AstNode& node, AstNodeRef& childRef)
{
    SWC_ASSERT(childRef.isValid());
    using NodeType = AstTypeOf<ID>::type;
    return node.cast<NodeType>()->semaPostNodeChild(sema, childRef);
}

template<AstNodeId ID>
Result semaPostNode(Sema& sema, AstNode& node)
{
    using NodeType = AstTypeOf<ID>::type;
    return node.cast<NodeType>()->semaPostNode(sema);
}

template<AstNodeId ID>
void semaErrorCleanup(Sema& sema, AstNode& node, AstNodeRef nodeRef)
{
    using NodeType = AstTypeOf<ID>::type;
    node.cast<NodeType>()->semaErrorCleanup(sema, nodeRef);
}

template<AstNodeId ID>
AstNodeRef semaInlineClone(Sema& sema, AstNode& node, const CloneContext& cloneContext)
{
    using NodeType = AstTypeOf<ID>::type;
    return node.cast<NodeType>()->semaClone(sema, cloneContext);
}

constexpr std::array AST_NODE_ID_INFOS = {
#define SWC_NODE_DEF(__enum, __flags) AstNodeIdInfo{                             \
                                          #__enum,                               \
                                          __flags,                               \
                                          &collectChildren<AstNodeId::__enum>,   \
                                          &semaPreDecl<AstNodeId::__enum>,       \
                                          &semaPreDeclChild<AstNodeId::__enum>,  \
                                          &semaPostDeclChild<AstNodeId::__enum>, \
                                          &semaPostDecl<AstNodeId::__enum>,      \
                                          &semaPreNode<AstNodeId::__enum>,       \
                                          &semaPreNodeChild<AstNodeId::__enum>,  \
                                          &semaPostNodeChild<AstNodeId::__enum>, \
                                          &semaPostNode<AstNodeId::__enum>,      \
                                          &semaErrorCleanup<AstNodeId::__enum>,  \
                                          &semaInlineClone<AstNodeId::__enum>},
#include "Compiler/Parser/Ast/AstNodes.Def.inc"

#undef SWC_NODE_DEF
};

SWC_END_NAMESPACE();
