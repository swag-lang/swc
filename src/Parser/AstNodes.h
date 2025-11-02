// ReSharper disable CppPossiblyUninitializedMember
#pragma once
#include "Parser/AstNode.h"

SWC_BEGIN_NAMESPACE()

struct AstNodeBlock : AstNode
{
    explicit AstNodeBlock(AstNodeId nodeId) :
        AstNode(nodeId)
    {
    }

    Ref nodeChildren;
};

struct AstNodeInvalid : AstNode
{
    static constexpr auto ID = AstNodeId::Invalid;
    AstNodeInvalid() :
        AstNode(ID)
    {
    }
};

struct AstNodeIdentifier : AstNode
{
    static constexpr auto ID = AstNodeId::Identifier;
    AstNodeIdentifier() :
        AstNode(ID)
    {
    }

    TokenRef tknName;
};

struct AstNodeFile : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::File;
    AstNodeFile() :
        AstNodeBlock(ID)
    {
    }
};

struct AstNodeTopLevelBlock : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::TopLevelBlock;
    AstNodeTopLevelBlock() :
        AstNodeBlock(ID)
    {
    }
};

struct AstNodeEnumDecl : AstNode
{
    static constexpr auto ID = AstNodeId::EnumDecl;
    AstNodeEnumDecl() :
        AstNode(ID)
    {
    }

    TokenRef   tknName;
    AstNodeRef nodeType;
    AstNodeRef nodeBody;
};

struct AstNodeEnumBlock : AstNodeBlock
{
    static constexpr auto ID = AstNodeId::EnumBlock;
    AstNodeEnumBlock() :
        AstNodeBlock(ID)
    {
    }
};

struct AstNodeEnumValue : AstNode
{
    static constexpr auto ID = AstNodeId::EnumValue;
    AstNodeEnumValue() :
        AstNode(ID)
    {
    }

    TokenRef   tknName;
    AstNodeRef nodeValue;
};

struct AstNodeEnumUsingValue : AstNode
{
    static constexpr auto ID = AstNodeId::EnumUsingValue;
    AstNodeEnumUsingValue() :
        AstNode(ID)
    {
    }

    TokenRef tknName;
};

struct AstNodeEnumImpl : AstNode
{
    static constexpr auto ID = AstNodeId::EnumImpl;
    AstNodeEnumImpl() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeName;
    AstNodeRef nodeBody;
};

struct AstNodeQualifiedType : AstNode
{
    static constexpr auto ID = AstNodeId::QualifiedType;
    AstNodeQualifiedType() :
        AstNode(ID)
    {
    }

    TokenRef   tknQual;
    AstNodeRef nodeType;
};

struct AstNodeLRefType : AstNode
{
    static constexpr auto ID = AstNodeId::LRefType;
    explicit AstNodeLRefType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeType;
};

struct AstNodeRRefType : AstNode
{
    static constexpr auto ID = AstNodeId::RRefType;
    explicit AstNodeRRefType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeType;
};

struct AstNodePointerType : AstNode
{
    static constexpr auto ID = AstNodeId::PointerType;
    AstNodePointerType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstNodeBlockPointerType : AstNode
{
    static constexpr auto ID = AstNodeId::BlockPointerType;
    AstNodeBlockPointerType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstNodeSliceType : AstNode
{
    static constexpr auto ID = AstNodeId::SliceType;
    AstNodeSliceType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstNodeIncompleteArrayType : AstNode
{
    static constexpr auto ID = AstNodeId::IncompleteArrayType;
    AstNodeIncompleteArrayType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodePointeeType;
};

struct AstNodeArrayType : AstNode
{
    static constexpr auto ID = AstNodeId::ArrayType;
    AstNodeArrayType() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeDim;
    AstNodeRef nodePointeeType;
};

struct AstNodeNamedType : AstNode
{
    static constexpr auto ID = AstNodeId::NamedType;
    AstNodeNamedType() :
        AstNode(ID)
    {
    }

    TokenRef tknName;
};

struct AstNodeBuiltinType : AstNode
{
    static constexpr auto ID = AstNodeId::BuiltinType;
    AstNodeBuiltinType() :
        AstNode(ID)
    {
    }

    TokenRef tknType;
};

struct AstNodeCompilerAssert : AstNode
{
    static constexpr auto ID = AstNodeId::CompilerAssert;
    AstNodeCompilerAssert() :
        AstNode(ID)
    {
    }

    AstNodeRef nodeExpr;
};

template<typename T>
T* castAst(AstNode* node)
{
    SWC_ASSERT(node);
    SWC_ASSERT(node->id == T::ID);
    return reinterpret_cast<T*>(node);
}

template<AstNodeId Id>
struct AstTypeOf;

#define SWC_NODE_ID_DEF(enum)         \
    template<>                        \
    struct AstTypeOf<AstNodeId::enum> \
    {                                 \
        using type = AstNode##enum;   \
    };
#include "AstNodeIds.inc"
#undef SWC_NODE_ID_DEF

SWC_END_NAMESPACE()
