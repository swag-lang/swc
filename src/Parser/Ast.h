#pragma once
#include "Parser/AstExtStore.h"
#include "Parser/AstNode.h"

SWC_BEGIN_NAMESPACE();

class Ast
{
    std::vector<AstNode> nodes_;
    AstExtStore          extensions_;

public:
    AstNodeRef makeNode(AstNodeId id, FileRef file, TokenRef token, AstNodeRef left = INVALID_AST_NODE_REF, uint32_t right = INVALID_AST_NODE_REF)
    {
        nodes_.emplace_back(id, AstNodeFlagsEnum::Zero, file, token, left, right);
        return static_cast<AstNodeRef>(nodes_.size() - 1);
    }

    AstNode* node(AstNodeRef ref) { return &nodes_[ref]; }
};

SWC_END_NAMESPACE();
