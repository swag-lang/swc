#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE()

void AstCompound::collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
{
    ast->nodes(out, spanChildren);
}

void AstFile::collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
{
    ast->nodes(out, spanGlobals);
    AstCompound::collectChildren(out, ast);
}

SWC_END_NAMESPACE()
