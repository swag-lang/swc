#include "pch.h"
#include "Parser/Ast.h"
#include "Core/Types.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Ast::makeNode(AstNodeId id, FileRef file, TokenRef token, AstNodeRef left, AstNodeRef right)
{
    AstNode n;
    n.id    = id;
    n.file  = file;
    n.token = token;
    n.left  = left;
    n.right = right;
    nodes_.push_back(n);
    return static_cast<AstNodeRef>(nodes_.size()) - 1;
}

SWC_END_NAMESPACE();
