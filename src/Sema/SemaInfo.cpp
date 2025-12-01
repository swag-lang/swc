#include "pch.h"
#include "Sema/SemaInfo.h"
#include "Constant/ConstantManager.h"
#include "Constant/ConstantValue.h"

SWC_BEGIN_NAMESPACE()

TypeRef SemaInfo::getTypeRef(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    const AstNode& node = ast().node(nodeRef);
    switch (semaNodeKind(node))
    {
        case NodeSemaKind::IsConst:
            return getConstant(ctx, nodeRef).typeRef();
        case NodeSemaKind::IsType:
            return TypeRef{node.semaRaw()};
        default:
            SWC_UNREACHABLE();
    }
}

void SemaInfo::setConstant(AstNodeRef nodeRef, ConstantRef ref)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(ref.isValid());
    AstNode& node      = ast().node(nodeRef);
    semaNodeKind(node) = NodeSemaKind::IsConst;
    node.setSemaRaw(ref.get());
}

void SemaInfo::setType(AstNodeRef nodeRef, TypeRef ref)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(ref.isValid());
    AstNode& node      = ast().node(nodeRef);
    semaNodeKind(node) = NodeSemaKind::IsType;
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
    auto&            shard    = shards_[shardIdx];
    std::unique_lock lock(shard.mutex);

    AstNode& node      = ast().node(nodeRef);
    semaNodeKind(node) = NodeSemaKind::IsSymbol;

    return SemaRef{shard.store.push_back(symbol)};
}

Symbol* SemaInfo::getSymbol(AstNodeRef nodeRef, SemaRef semaRef)
{
    SWC_ASSERT(hasSymbol(nodeRef));
    const uint32_t shardIdx = nodeRef.get() % NUM_SHARDS;
    auto&          shard    = shards_[shardIdx];
    return *shard.store.ptr<Symbol*>(semaRef.get());
}

bool SemaInfo::hasConstant(AstNodeRef nodeRef) const
{
    SWC_ASSERT(nodeRef.isValid());
    const AstNode& node = ast().node(nodeRef);
    return semaNodeKind(node) == NodeSemaKind::IsConst;
}

bool SemaInfo::hasType(AstNodeRef nodeRef) const
{
    SWC_ASSERT(nodeRef.isValid());
    const AstNode& node = ast().node(nodeRef);
    return semaNodeKind(node) == NodeSemaKind::IsType;
}

bool SemaInfo::hasSymbol(AstNodeRef nodeRef) const
{
    SWC_ASSERT(nodeRef.isValid());
    const AstNode& node = ast().node(nodeRef);
    return semaNodeKind(node) == NodeSemaKind::IsSymbol;
}

SWC_END_NAMESPACE()
