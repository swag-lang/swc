#include "pch.h"
#include "Sema/SemaInfo.h"
#include "Constant/ConstantManager.h"
#include "Constant/ConstantValue.h"

SWC_BEGIN_NAMESPACE()

TypeRef SemaInfo::getTypeRef(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return TypeRef::invalid();

    const AstNode&     node = ast().node(nodeRef);
    const NodeSemaKind kind = semaNodeKind(node);
    switch (kind)
    {
        case NodeSemaKind::IsConstantRef:
            return getConstant(ctx, nodeRef).typeRef();
        case NodeSemaKind::IsTypeRef:
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
    semaNodeKind(node) = NodeSemaKind::IsConstantRef;
    node.setSemaRaw(ref.get());
}

void SemaInfo::setType(AstNodeRef nodeRef, TypeRef ref)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(ref.isValid());
    AstNode& node      = ast().node(nodeRef);
    semaNodeKind(node) = NodeSemaKind::IsTypeRef;
    node.setSemaRaw(ref.get());
}

ConstantRef SemaInfo::getConstantRef(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return ConstantRef::invalid();

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
    semaNodeKind(node) = NodeSemaKind::IsSymbolRef;

    return SemaRef{shard.store.push_back(symbol)};
}

const Symbol& SemaInfo::getSymbol(const TaskContext&, AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasSymbol(nodeRef));
    const uint32_t shardIdx = nodeRef.get() % NUM_SHARDS;
    auto&          shard    = shards_[shardIdx];
    const AstNode& node     = ast().node(nodeRef);
    return **shard.store.ptr<Symbol*>(node.semaRaw());
}

bool SemaInfo::hasConstant(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return semaNodeKind(node) == NodeSemaKind::IsConstantRef;
}

bool SemaInfo::hasType(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return semaNodeKind(node) == NodeSemaKind::IsTypeRef;
}

bool SemaInfo::hasSymbol(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return semaNodeKind(node) == NodeSemaKind::IsSymbolRef;
}

SWC_END_NAMESPACE()
