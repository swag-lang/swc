#include "pch.h"
#include "Sema/SemaInfo.h"
#include "Constant/ConstantManager.h"
#include "Constant/ConstantValue.h"

SWC_BEGIN_NAMESPACE()

TypeRef SemaInfo::getTypeRef(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    const AstNode& node = ast().node(nodeRef);
    if (hasConstant(nodeRef))
        return getConstant(ctx, nodeRef).typeRef();
    if (hasType(nodeRef))
        return TypeRef{node.semaRaw()};
    return TypeRef::invalid();
}

void SemaInfo::setConstant(AstNodeRef nodeRef, ConstantRef ref)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(ref.isValid());
    AstNode& node = ast().node(nodeRef);
    semaFlags(node).clearMask(NodeSemaFlagE::SemaRefMask);
    semaFlags(node).add(NodeSemaFlagE::SemaIsConst);
    node.setSemaRaw(ref.get());
}

bool SemaInfo::hasConstant(AstNodeRef nodeRef) const
{
    SWC_ASSERT(nodeRef.isValid());
    const AstNode& node = ast().node(nodeRef);
    return semaFlags(node).has(NodeSemaFlagE::SemaIsConst);
}

bool SemaInfo::hasType(AstNodeRef nodeRef) const
{
    SWC_ASSERT(nodeRef.isValid());
    const AstNode& node = ast().node(nodeRef);
    return semaFlags(node).has(NodeSemaFlagE::SemaIsType);
}

void SemaInfo::setType(AstNodeRef nodeRef, TypeRef ref)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(ref.isValid());
    AstNode& node = ast().node(nodeRef);
    semaFlags(node).clearMask(NodeSemaFlagE::SemaRefMask);
    semaFlags(node).add(NodeSemaFlagE::SemaIsType);
    node.setSemaRaw(ref.get());
}

ConstantRef SemaInfo::getConstantRef(AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasConstant(nodeRef));
    const AstNode& node = ast().node(nodeRef);
    return ConstantRef{node.semaRaw()};
}

const ConstantValue& SemaInfo::getConstant(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasConstant(nodeRef));
    const AstNode& node = ast().node(nodeRef);
    return ctx.cstMgr().get(ConstantRef{node.semaRaw()});
}

SemaRef SemaInfo::setSymbol(AstNodeRef nodeRef, Symbol* symbol)
{
    const uint32_t   shardIdx = nodeRef.get() % NUM_SHARDS;
    std::unique_lock lock(shards_[shardIdx].mutex);
    return SemaRef{shards_[shardIdx].store.push_back(symbol)};
}

SWC_END_NAMESPACE()
