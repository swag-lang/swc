#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE()

void AstCompound::collectChildren(const Ast* ast, SmallVector<AstNodeRef>& out) const
{
    ast->nodes(out, spanChildren);
}

SWC_END_NAMESPACE()
