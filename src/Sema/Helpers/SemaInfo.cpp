#include "pch.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Main/TaskContext.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Constant/ConstantValue.h"
#if SWC_HAS_DEBUG_INFO
#include "Sema/Type/TypeManager.h"
#endif

SWC_BEGIN_NAMESPACE()

bool SemaInfo::hasConstant(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return semaNodeKind(node) == NodeSemaKind::ConstantRef;
}

const ConstantValue& SemaInfo::getConstant(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasConstant(nodeRef));
    const AstNode& node = ast().node(nodeRef);
    return ctx.cstMgr().get(ConstantRef{node.semaRaw()});
}

ConstantRef SemaInfo::getConstantRef(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return ConstantRef::invalid();

    SWC_ASSERT(hasConstant(nodeRef));
    const AstNode& node  = ast().node(nodeRef);
    auto           value = ConstantRef{node.semaRaw()};
#if SWC_HAS_DEBUG_INFO
    value.setDbgPtr(&getConstant(ctx, nodeRef));
#endif
    return value;
}

void SemaInfo::setConstant(AstNodeRef nodeRef, ConstantRef ref)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(ref.isValid());
    AstNode& node      = ast().node(nodeRef);
    semaNodeKind(node) = NodeSemaKind::ConstantRef;
    node.setSemaRaw(ref.get());
}

bool SemaInfo::hasSubstitute(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return semaNodeKind(node) == NodeSemaKind::Substitute;
}

void SemaInfo::setSubstitute(AstNodeRef nodeRef, AstNodeRef substNodeRef)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(substNodeRef.isValid());
    AstNode& node      = ast().node(nodeRef);
    semaNodeKind(node) = NodeSemaKind::Substitute;
    node.setSemaRaw(substNodeRef.get());
}

AstNodeRef SemaInfo::getSubstituteRef(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasSubstitute(nodeRef));
    const AstNode& node  = ast().node(nodeRef);
    auto           value = AstNodeRef{node.semaRaw()};
#if SWC_HAS_DEBUG_INFO
    value.setDbgPtr(&ast().node(value));
#endif
    return value;
}

bool SemaInfo::hasType(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return semaNodeKind(node) == NodeSemaKind::TypeRef;
}

TypeRef SemaInfo::getTypeRef(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return TypeRef::invalid();

    const AstNode&     node = ast().node(nodeRef);
    const NodeSemaKind kind = semaNodeKind(node);
    TypeRef            value;
    switch (kind)
    {
        case NodeSemaKind::ConstantRef:
            value = getConstant(ctx, nodeRef).typeRef();
            break;
        case NodeSemaKind::TypeRef:
            value = TypeRef{node.semaRaw()};
            break;
        default:
            SWC_UNREACHABLE();
    }

#if SWC_HAS_DEBUG_INFO
    value.setDbgPtr(&ctx.typeMgr().get(value));
#endif
    return value;
}

void SemaInfo::setType(AstNodeRef nodeRef, TypeRef ref)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(ref.isValid());
    AstNode& node      = ast().node(nodeRef);
    semaNodeKind(node) = NodeSemaKind::TypeRef;
    node.setSemaRaw(ref.get());
}

bool SemaInfo::hasSymbol(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return semaNodeKind(node) == NodeSemaKind::SymbolRef;
}

const Symbol& SemaInfo::getSymbol(const TaskContext&, AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasSymbol(nodeRef));
    const uint32_t shardIdx = nodeRef.get() % NUM_SHARDS;
    auto&          shard    = shards_[shardIdx];
    const AstNode& node     = ast().node(nodeRef);
    return **shard.store.ptr<Symbol*>(node.semaRaw());
}

SemaRef SemaInfo::setSymbol(AstNodeRef nodeRef, Symbol* symbol)
{
    const uint32_t   shardIdx = nodeRef.get() % NUM_SHARDS;
    auto&            shard    = shards_[shardIdx];
    std::unique_lock lock(shard.mutex);

    AstNode& node      = ast().node(nodeRef);
    semaNodeKind(node) = NodeSemaKind::SymbolRef;

    return SemaRef{shard.store.push_back(symbol)};
}

SWC_END_NAMESPACE()
