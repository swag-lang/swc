#pragma once
#include "Core/Types.h"
#include "Core/PagedStore.h"
#include "Parser/AstNode.h"

SWC_BEGIN_NAMESPACE();

class Ast
{
protected:
    friend class Parser;
    PagedStore<AstNode>    nodes_;
    PagedStore<AstNodeRef> nodeRefs_;
    AstNodeRef             root_ = INVALID_REF;

public:
    Ast();

    AstNode* node(AstNodeRef ref)
    {
        SWC_ASSERT(ref != INVALID_REF);
        SWC_ASSERT(ref < nodes_.size());
        return nodes_.ptr(ref);
    }

    const AstNode* node(AstNodeRef ref) const
    {
        SWC_ASSERT(ref != INVALID_REF);
        SWC_ASSERT(ref < nodes_.size());
        return nodes_.ptr(ref);
    }

    static constexpr const AstNodeIdInfo& nodeIdInfos(AstNodeId id)
    {
        return AST_NODE_ID_INFOS[static_cast<size_t>(id)];
    }

    static constexpr std::string_view nodeIdName(AstNodeId id) noexcept
    {
        return nodeIdInfos(id).name;
    }

    AstChildrenView children(const AstNode& n) const;

    AstNodeRef makeNode(AstNodeId id, TokenRef token);
    AstNodeRef makeNode(AstNodeId id, TokenRef token, const AstChildrenOne& kids);
    AstNodeRef makeNode(AstNodeId id, TokenRef token, const AstChildrenTwo& kids);
    AstNodeRef makeNode(AstNodeId id, TokenRef token, const AstChildrenMany& kids);
    AstNodeRef makeBlock(AstNodeId id, TokenRef token, const std::span<AstNodeRef>& span);
};

SWC_END_NAMESPACE();
