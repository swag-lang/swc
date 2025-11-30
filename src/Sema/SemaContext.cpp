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

SemaRef SemaContext::addSymbol(AstNodeRef nodeRef, Symbol* symbol)
{
    const uint32_t   shardIdx = nodeRef.get() % NUM_SHARDS;
    std::unique_lock lock(shards_[shardIdx].mutex);
    return SemaRef{shards_[shardIdx].store.push_back(symbol)};
}

SWC_END_NAMESPACE()
