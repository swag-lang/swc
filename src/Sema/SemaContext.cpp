#include "pch.h"
#include "Sema/SemaContext.h"
#include "Constant/ConstantValue.h"

SWC_BEGIN_NAMESPACE()

TypeInfoRef SemaContext::getTypeRef(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    const AstNode& node = ast().node(nodeRef);
    if (node.isSemaConstant())
        return node.getSemaConstant(ctx).typeRef();
    if (node.isSemaType())
        return node.getSemaTypeRef();
    return TypeInfoRef::invalid();
}

SWC_END_NAMESPACE()
