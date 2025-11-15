#include "pch.h"
#include "Parser/Ast.h"
#include "Parser/AstNodes.h"

SWC_BEGIN_NAMESPACE()

void AstNode::collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast, SpanRef spanRef)
{
    ast->nodes(out, spanRef);
}

SWC_END_NAMESPACE()
