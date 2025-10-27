#pragma once
#include "Core/RefStore.h"
#include "Core/Types.h"
#include "Parser/AstNode.h"

SWC_BEGIN_NAMESPACE();

class Ast
{
protected:
    friend class Parser;
    RefStore<> store_;
    AstNodeRef root_ = INVALID_REF;

public:
    AstNode*       node(AstNodeRef ref) { return store_.ptr<AstNode>(ref); }
    const AstNode* node(AstNodeRef ref) const { return store_.ptr<AstNode>(ref); }

    static constexpr const AstNodeIdInfo& nodeIdInfos(AstNodeId id) { return AST_NODE_ID_INFOS[static_cast<size_t>(id)]; }
    static constexpr std::string_view     nodeIdName(AstNodeId id) { return nodeIdInfos(id).name; }

    AstNodeRef makeNode(AstNodeId id, TokenRef token)
    {
        auto [r, p] = store_.emplace_uninit<AstNode>();
        p->id       = id;
        p->token    = token;
        return r;
    }

    AstNodeRef makeBlock(AstNodeId id, TokenRef token, const std::span<AstNodeRef>& span);
    AstNodeRef makeBlock(AstNodeId id, TokenRef openToken, TokenRef closeToken, const std::span<AstNodeRef>& span);
};

SWC_END_NAMESPACE();
