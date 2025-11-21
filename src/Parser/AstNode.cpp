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

void AstNode::setConstant(ConstantRef ref)
{
    semaFlags_.clearMask(SemaFlagE::RefMask);
    addSemaFlag(SemaFlagE::IsConst);
    sema_ = ref;
}

const ConstantValue& AstNode::getConstant(const TaskContext& ctx) const
{
    SWC_ASSERT(isConstant());
    return ctx.compiler().constMgr().get(std::get<ConstantRef>(sema_));
}

TokenRef AstNode::tokRefEnd(const Ast& ast) const
{
    const auto& info = Ast::nodeIdInfos(id_);

    SmallVector<AstNodeRef> children;
    info.collectChildren(children, ast, *this);

    if (children.empty() || children.back().isInvalid())
        return tokRef_;

    const auto& nodePtr = ast.node(children.back());
    return nodePtr->tokRefEnd(ast);
}

SWC_END_NAMESPACE()
