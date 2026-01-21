#include "pch.h"
#include "Sema/Core/SemaInfo.h"
#include "Main/TaskContext.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Constant/ConstantValue.h"
#include "Sema/Symbol/Symbols.h"
#if SWC_HAS_REF_DEBUG_INFO
#include "Sema/Type/TypeManager.h"
#endif

SWC_BEGIN_NAMESPACE();

bool SemaInfo::hasConstant(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;

    const AstNode& node = ast().node(nodeRef);
    switch (semaKind(node))
    {
        case NodeSemaKind::ConstantRef:
            return true;

        case NodeSemaKind::SymbolRef:
        {
            const Symbol& sym = getSymbol(ctx, nodeRef);
            return sym.isConst() || sym.isEnumValue();
        }

        case NodeSemaKind::SymbolList:
        {
            const auto symbols = getSymbolList(nodeRef);
            SWC_ASSERT(!symbols.empty());
            if (symbols.size() == 1)
                return symbols.front()->isConst() || symbols.front()->isEnumValue();
            break;
        }

        default:
            break;
    }

    return false;
}

const ConstantValue& SemaInfo::getConstant(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasConstant(ctx, nodeRef));
    const ConstantRef cstRef = getConstantRef(ctx, nodeRef);
    SWC_ASSERT(cstRef.isValid());
    return ctx.cstMgr().get(cstRef);
}

ConstantRef SemaInfo::getConstantRef(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return ConstantRef::invalid();

    SWC_ASSERT(hasConstant(ctx, nodeRef));

    const AstNode& node = ast().node(nodeRef);
    switch (semaKind(node))
    {
        case NodeSemaKind::ConstantRef:
        {
            ConstantRef value{node.semaRef()};
#if SWC_HAS_REF_DEBUG_INFO
            value.setDbgPtr(&ctx.cstMgr().get(value));
#endif
            return value;
        }

        case NodeSemaKind::SymbolRef:
        {
            const Symbol& sym = getSymbol(ctx, nodeRef);
            if (sym.isConst())
                return sym.cast<SymbolConstant>().cstRef();
            if (sym.isEnumValue())
                return sym.cast<SymbolEnumValue>().cstRef();
            break;
        }

        case NodeSemaKind::SymbolList:
        {
            const std::span<const Symbol*> symList = getSymbolList(nodeRef);
            SWC_ASSERT(symList.size() == 1);
            if (symList.front()->isConst())
                return symList.front()->cast<SymbolConstant>().cstRef();
            if (symList.front()->isEnumValue())
                return symList.front()->cast<SymbolEnumValue>().cstRef();
            break;
        }

        default:
            break;
    }

    SWC_UNREACHABLE();
}

void SemaInfo::setConstant(AstNodeRef nodeRef, ConstantRef ref)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(ref.isValid());
    AstNode& node = ast().node(nodeRef);
    setSemaKind(node, NodeSemaKind::ConstantRef);
    node.setSemaRef(ref.get());
    setIsValue(node);
}

bool SemaInfo::hasSubstitute(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return semaKind(node) == NodeSemaKind::Substitute;
}

void SemaInfo::setSubstitute(AstNodeRef nodeRef, AstNodeRef substNodeRef)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(substNodeRef.isValid());
    AstNode& node = ast().node(nodeRef);
    setSemaKind(node, NodeSemaKind::Substitute);
    node.setSemaRef(substNodeRef.get());
}

AstNodeRef SemaInfo::getSubstituteRef(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return nodeRef;

    const AstNode* node = &ast().node(nodeRef);
    while (semaKind(*node) == NodeSemaKind::Substitute)
    {
        nodeRef = AstNodeRef{node->semaRef()};
        node    = &ast().node(nodeRef);
    }

#if SWC_HAS_REF_DEBUG_INFO
    nodeRef.setDbgPtr(&ast().node(nodeRef));
#endif
    return nodeRef;
}

bool SemaInfo::hasType(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return semaKind(node) == NodeSemaKind::TypeRef;
}

TypeRef SemaInfo::getTypeRef(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return TypeRef::invalid();

    const AstNode&     node = ast().node(nodeRef);
    const NodeSemaKind kind = semaKind(node);
    TypeRef            value;
    switch (kind)
    {
        case NodeSemaKind::ConstantRef:
            value = getConstant(ctx, nodeRef).typeRef();
            break;
        case NodeSemaKind::TypeRef:
            value = TypeRef{node.semaRef()};
            break;
        case NodeSemaKind::SymbolRef:
            value = getSymbol(ctx, nodeRef).typeRef();
            break;
        case NodeSemaKind::SymbolList:
        {
            const auto symbols = getSymbolList(nodeRef);
            SWC_ASSERT(!symbols.empty());
            value = symbols.back()->typeRef();
            break;
        }
        case NodeSemaKind::Invalid:
            return TypeRef::invalid();

        default:
            SWC_UNREACHABLE();
    }

#if SWC_HAS_REF_DEBUG_INFO
    if (value.isValid())
        value.setDbgPtr(&ctx.typeMgr().get(value));
#endif
    return value;
}

void SemaInfo::setType(AstNodeRef nodeRef, TypeRef ref)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(ref.isValid());
    AstNode& node = ast().node(nodeRef);
    setSemaKind(node, NodeSemaKind::TypeRef);
    node.setSemaRef(ref.get());
}

bool SemaInfo::hasSymbol(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return semaKind(node) == NodeSemaKind::SymbolRef;
}

const Symbol& SemaInfo::getSymbol(const TaskContext&, AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasSymbol(nodeRef));
    const AstNode& node     = ast().node(nodeRef);
    const uint32_t shardIdx = semaShard(node);
    auto&          shard    = shards_[shardIdx];
    const Symbol&  value    = **shard.store.ptr<Symbol*>(node.semaRef());
    return value;
}

Symbol& SemaInfo::getSymbol(const TaskContext&, AstNodeRef nodeRef)
{
    SWC_ASSERT(hasSymbol(nodeRef));
    const AstNode& node     = ast().node(nodeRef);
    const uint32_t shardIdx = semaShard(node);
    auto&          shard    = shards_[shardIdx];
    Symbol&        value    = **shard.store.ptr<Symbol*>(node.semaRef());
    return value;
}

void SemaInfo::setSymbol(AstNodeRef nodeRef, const Symbol* symbol)
{
    const uint32_t   shardIdx = nodeRef.get() % SEMA_SHARD_NUM;
    auto&            shard    = shards_[shardIdx];
    std::unique_lock lock(shard.mutex);

    AstNode& node = ast().node(nodeRef);
    setSemaKind(node, NodeSemaKind::SymbolRef);
    setSemaShard(node, shardIdx);

    const Ref value = shard.store.push_back(symbol);
    node.setSemaRef(value);
    updateSemaFlags(node, std::span{&symbol, 1});
}

bool SemaInfo::hasSymbolList(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return semaKind(node) == NodeSemaKind::SymbolList;
}

std::span<const Symbol*> SemaInfo::getSymbolListImpl(AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasSymbolList(nodeRef));
    const AstNode& node     = ast().node(nodeRef);
    const uint32_t shardIdx = semaShard(node);
    auto&          shard    = shards_[shardIdx];
    const auto     spanView = shard.store.span<const Symbol*>(node.semaRef());

    if (spanView.empty())
        return {};

    const auto  it    = spanView.chunks_begin();
    const auto& chunk = *it;
    SWC_ASSERT(chunk.count == spanView.size());
    return std::span{static_cast<const Symbol**>(const_cast<void*>(chunk.ptr)), chunk.count};
}

std::span<const Symbol*> SemaInfo::getSymbolList(AstNodeRef nodeRef) const
{
    return getSymbolListImpl(nodeRef);
}

std::span<Symbol*> SemaInfo::getSymbolList(AstNodeRef nodeRef)
{
    const auto res = getSymbolListImpl(nodeRef);
    return {const_cast<Symbol**>(res.data()), res.size()};
}

void SemaInfo::setSymbolList(AstNodeRef nodeRef, std::span<const Symbol*> symbols)
{
    setSymbolListImpl(nodeRef, symbols);
}

void SemaInfo::setSymbolList(AstNodeRef nodeRef, std::span<Symbol*> symbols)
{
    setSymbolListImpl(nodeRef, symbols);
}

bool SemaInfo::hasPayload(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return semaKind(node) == NodeSemaKind::Payload;
}

void SemaInfo::setPayload(AstNodeRef nodeRef, void* payload)
{
    SWC_ASSERT(nodeRef.isValid());

    const uint32_t   shardIdx = nodeRef.get() % SEMA_SHARD_NUM;
    auto&            shard    = shards_[shardIdx];
    std::unique_lock lock(shard.mutex);

    AstNode& node = ast().node(nodeRef);
    setSemaKind(node, NodeSemaKind::Payload);
    setSemaShard(node, shardIdx);

    const Ref value = shard.store.push_back(payload);
    node.setSemaRef(value);
}

void* SemaInfo::getPayload(AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasPayload(nodeRef));
    const AstNode& node     = ast().node(nodeRef);
    const uint32_t shardIdx = semaShard(node);
    auto&          shard    = shards_[shardIdx];
    return *shard.store.ptr<void*>(node.semaRef());
}

void SemaInfo::inheritSemaFlags(AstNode& nodeDst, const AstNode& nodeSrc)
{
    constexpr uint16_t mask = SEMA_FLAGS_MASK;
    nodeDst.semaBits()      = (nodeDst.semaBits() & ~mask) | (nodeSrc.semaBits() & mask);
}

void SemaInfo::inheritSemaKindRef(AstNode& nodeDst, const AstNode& nodeSrc)
{
    constexpr uint16_t mask = SEMA_KIND_MASK | SEMA_SHARD_MASK;
    nodeDst.semaBits()      = (nodeDst.semaBits() & ~mask) | (nodeSrc.semaBits() & mask);
    nodeDst.setSemaRef(nodeSrc.semaRef());
}

void SemaInfo::inheritSema(AstNode& nodeDst, const AstNode& nodeSrc)
{
    inheritSemaFlags(nodeDst, nodeSrc);
    inheritSemaKindRef(nodeDst, nodeSrc);
}

SWC_END_NAMESPACE();
