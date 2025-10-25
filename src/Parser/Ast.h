#pragma once
#include "Core/Types.h"
#include "Memory/PagedStore.h"
#include "Parser/AstExtStore.h"
#include "Parser/AstNode.h"

SWC_BEGIN_NAMESPACE();

class Ast
{
protected:
    friend class Parser;
    Arena               arena_;
    PagedStore<AstNode> nodes_{arena_};
    AstNodeRef          root_ = INVALID_AST_NODE_REF;
    AstExtStore         extensions_;

public:
    AstNodeRef makeNode(AstNodeId id, FileRef file, TokenRef token = INVALID_TOKEN_REF, AstNodeRef left = INVALID_AST_NODE_REF, uint32_t right = INVALID_AST_NODE_REF)
    {
        return nodes_.emplace_back(id, AstNodeFlagsEnum::Zero, file, token, left, right);
    }

    AstNode* node(AstNodeRef ref)
    {
        return nodes_.ptr(ref);
    }
};

SWC_END_NAMESPACE();
