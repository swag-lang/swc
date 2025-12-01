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
        return TypeRef{node.sema()};
    return TypeRef::invalid();
}

void SemaInfo::setConstant(AstNodeRef nodeRef, ConstantRef ref)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(ref.isValid());
    AstNode& node = ast().node(nodeRef);
    node.semaFlags().clearMask(SemaFlagE::SemaRefMask);
    node.semaFlags().add(SemaFlagE::SemaIsConst);
    node.setSema(ref.get());
}

bool SemaInfo::hasConstant(AstNodeRef nodeRef) const
{
    SWC_ASSERT(nodeRef.isValid());
    const AstNode& node = ast().node(nodeRef);
    return node.hasSemaFlag(SemaFlagE::SemaIsConst);
}

bool SemaInfo::hasType(AstNodeRef nodeRef) const
{
    SWC_ASSERT(nodeRef.isValid());
    const AstNode& node = ast().node(nodeRef);
    return node.hasSemaFlag(SemaFlagE::SemaIsType);
}

void SemaInfo::setType(AstNodeRef nodeRef, TypeRef ref)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(ref.isValid());
    AstNode& node = ast().node(nodeRef);
    node.semaFlags().clearMask(SemaFlagE::SemaRefMask);
    node.semaFlags().add(SemaFlagE::SemaIsType);
    node.setSema(ref.get());
}

ConstantRef SemaInfo::getConstantRef(AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasConstant(nodeRef));
    const AstNode& node = ast().node(nodeRef);
    return ConstantRef{node.sema()};
}

const ConstantValue& SemaInfo::getConstant(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasConstant(nodeRef));
    const AstNode& node = ast().node(nodeRef);
    return ctx.compiler().constMgr().get(ConstantRef{node.sema()});
}

SemaRef SemaInfo::setSymbol(AstNodeRef nodeRef, Symbol* symbol)
{
    const uint32_t   shardIdx = nodeRef.get() % NUM_SHARDS;
    std::unique_lock lock(shards_[shardIdx].mutex);
    return SemaRef{shards_[shardIdx].store.push_back(symbol)};
}

SWC_END_NAMESPACE()
