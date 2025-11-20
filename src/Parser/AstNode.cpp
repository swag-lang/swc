#include "pch.h"

#include "Main/TaskContext.h"
#include "Parser/Ast.h"
#include "Parser/AstNodes.h"
#include "Sema/ConstantManager.h"

SWC_BEGIN_NAMESPACE()

void AstNode::collectChildren(SmallVector<AstNodeRef>& out, const Ast& ast, SpanRef spanRef)
{
    ast.nodes(out, spanRef);
}

void AstNode::collectChildren(SmallVector<AstNodeRef>& out, std::initializer_list<AstNodeRef> nodes)
{
    for (auto n : nodes)
        out.push_back(n);
}

const ConstantValue& AstNode::getConstant(const TaskContext& ctx) const
{
    SWC_ASSERT(isConstant());
    return ctx.compiler().constMgr().get(getConstantRef());
}

SWC_END_NAMESPACE()
