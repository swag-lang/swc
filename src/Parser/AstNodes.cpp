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

void AstImpl::collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
{
    out.push_back(nodeIdent);
    AstCompound::collectChildren(out, ast);
}

void AstImplFor::collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
{
    out.push_back(nodeIdent);
    out.push_back(nodeFor);
    AstCompound::collectChildren(out, ast);
}

void AstNamespace::collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
{
    out.push_back(nodeName);
    AstCompound::collectChildren(out, ast);
}

void AstUsingNamespace::collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
{
    out.push_back(nodeName);
}

void AstCompilerGlobal::collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
{
    out.push_back(nodeMode);
}

void AstCompilerScope::collectChildren(SmallVector<AstNodeRef>& out, const Ast* ast) const
{
    out.push_back(nodeBody);
}

SWC_END_NAMESPACE()
