#pragma once
#include "Core/RefStore.h"
#include "Core/Types.h"
#include "Parser/AstNode.h"

SWC_BEGIN_NAMESPACE();

class Ast
{
protected:
    friend class Parser;
    RefStore<> nodes_;
    RefStore<> nodeRefs_;
    AstNodeRef root_ = INVALID_REF;

public:
    AstNode*       node(AstNodeRef ref) { return nodes_.ptr<AstNode>(ref); }
    const AstNode* node(AstNodeRef ref) const { return nodes_.ptr<AstNode>(ref); }

    static constexpr const AstNodeIdInfo& nodeIdInfos(AstNodeId id)
    {
        return AST_NODE_ID_INFOS[static_cast<size_t>(id)];
    }

    static constexpr std::string_view nodeIdName(AstNodeId id) noexcept
    {
        return nodeIdInfos(id).name;
    }

    template<class T>
    AstNodeRef makeNode(T& node)
    {
        return nodes_.push_back<T>(node);
    }

    AstNodeRef makeNode(AstNodeId id, TokenRef token)
    {
        const AstNode node{id, token};
        return nodes_.push_back<AstNode>(node);
    }

    AstNodeRef makeBlock(AstNodeId id, TokenRef token, const std::span<AstNodeRef>& span);
    AstNodeRef makeBlock(AstNodeId id, TokenRef token, const std::span<AstNodeRef>& span, TokenRef closeToken);
};

SWC_END_NAMESPACE();
