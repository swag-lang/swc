#include "pch.h"
#include "Compiler/Sema/Core/SemaContext.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Main/TaskContext.h"
#if SWC_HAS_REF_DEBUG_INFO
#include "Compiler/Sema/Type/TypeManager.h"
#endif

SWC_BEGIN_NAMESPACE();

bool SemaContext::hasConstant(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const ConstantRef cstRef = getConstantRef(ctx, nodeRef);
    return cstRef.isValid();
}

const ConstantValue& SemaContext::getConstant(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasConstant(ctx, nodeRef));
    const ConstantRef cstRef = getConstantRef(ctx, nodeRef);
    SWC_ASSERT(cstRef.isValid());
    return ctx.cstMgr().get(cstRef);
}

ConstantRef SemaContext::getConstantRef(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return ConstantRef::invalid();

    const AstNode& node = ast().node(nodeRef);
    switch (semaKind(node))
    {
        case NodeSemaKind::ConstantRef:
        {
            ConstantRef value{node.semaRef()};
#if SWC_HAS_REF_DEBUG_INFO
            value.dbgPtr = &ctx.cstMgr().get(value);
#endif
            return value;
        }

        case NodeSemaKind::SymbolRef:
        {
            const Symbol& sym = getSymbol(ctx, nodeRef);
            if (sym.isConstant())
                return sym.cast<SymbolConstant>().cstRef();
            if (sym.isEnumValue())
                return sym.cast<SymbolEnumValue>().cstRef();
            break;
        }

        case NodeSemaKind::SymbolList:
        {
            const std::span<const Symbol*> symList = getSymbolList(nodeRef);
            if (symList.size() > 1)
                return ConstantRef::invalid();
            if (symList.front()->isConstant())
                return symList.front()->cast<SymbolConstant>().cstRef();
            if (symList.front()->isEnumValue())
                return symList.front()->cast<SymbolEnumValue>().cstRef();
            break;
        }

        default:
            break;
    }

    return ConstantRef::invalid();
}

void SemaContext::setConstant(AstNodeRef nodeRef, ConstantRef ref)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(ref.isValid());
    AstNode& node = ast().node(nodeRef);
    setSemaKind(node, NodeSemaKind::ConstantRef);
    node.setSemaRef(ref.get());
    addSemaFlags(node, NodeSemaFlags::Value);
}

bool SemaContext::hasSubstitute(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return semaKind(node) == NodeSemaKind::Substitute;
}

void SemaContext::setSubstitute(AstNodeRef nodeRef, AstNodeRef substNodeRef)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(substNodeRef.isValid());
    AstNode& node = ast().node(nodeRef);
    setSemaKind(node, NodeSemaKind::Substitute);
    node.setSemaRef(substNodeRef.get());
}

AstNodeRef SemaContext::getSubstituteRef(AstNodeRef nodeRef) const
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
    nodeRef.dbgPtr = &ast().node(nodeRef);
#endif
    return nodeRef;
}

bool SemaContext::hasType(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const TypeRef typeRef = getTypeRef(ctx, nodeRef);
    return typeRef.isValid();
}

TypeRef SemaContext::getTypeRef(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return TypeRef::invalid();

    const AstNode&     node  = ast().node(nodeRef);
    const NodeSemaKind kind  = semaKind(node);
    TypeRef            value = TypeRef::invalid();
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

        default:
            return TypeRef::invalid();
    }

#if SWC_HAS_REF_DEBUG_INFO
    if (value.isValid())
        value.dbgPtr = &ctx.typeMgr().get(value);
#endif
    return value;
}

void SemaContext::setType(AstNodeRef nodeRef, TypeRef ref)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(ref.isValid());
    AstNode& node = ast().node(nodeRef);
    setSemaKind(node, NodeSemaKind::TypeRef);
    node.setSemaRef(ref.get());
}

bool SemaContext::hasSymbol(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return semaKind(node) == NodeSemaKind::SymbolRef;
}

const Symbol& SemaContext::getSymbol(const TaskContext&, AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasSymbol(nodeRef));
    const AstNode& node     = ast().node(nodeRef);
    const uint32_t shardIdx = semaShard(node);
    auto&          shard    = shards_[shardIdx];
    const Symbol&  value    = **shard.store.ptr<Symbol*>(node.semaRef());
    return value;
}

Symbol& SemaContext::getSymbol(const TaskContext&, AstNodeRef nodeRef)
{
    SWC_ASSERT(hasSymbol(nodeRef));
    const AstNode& node     = ast().node(nodeRef);
    const uint32_t shardIdx = semaShard(node);
    auto&          shard    = shards_[shardIdx];
    Symbol&        value    = **shard.store.ptr<Symbol*>(node.semaRef());
    return value;
}

void SemaContext::setSymbol(AstNodeRef nodeRef, const Symbol* symbol)
{
    SWC_ASSERT(symbol);
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

bool SemaContext::hasSymbolList(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return semaKind(node) == NodeSemaKind::SymbolList;
}

std::span<const Symbol*> SemaContext::getSymbolListImpl(AstNodeRef nodeRef) const
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

std::span<const Symbol*> SemaContext::getSymbolList(AstNodeRef nodeRef) const
{
    return getSymbolListImpl(nodeRef);
}

std::span<Symbol*> SemaContext::getSymbolList(AstNodeRef nodeRef)
{
    const auto res = getSymbolListImpl(nodeRef);
    return {const_cast<Symbol**>(res.data()), res.size()};
}

void SemaContext::setSymbolListImpl(AstNodeRef nodeRef, std::span<const Symbol*> symbols)
{
    const uint32_t   shardIdx = nodeRef.get() % SEMA_SHARD_NUM;
    auto&            shard    = shards_[shardIdx];
    std::unique_lock lock(shard.mutex);

    AstNode& node = ast().node(nodeRef);
    setSemaKind(node, NodeSemaKind::SymbolList);
    setSemaShard(node, shardIdx);

    const Ref value = shard.store.push_span(symbols).get();
    node.setSemaRef(value);
    updateSemaFlags(node, symbols);
}

void SemaContext::setSymbolListImpl(AstNodeRef nodeRef, std::span<Symbol*> symbols)
{
    const uint32_t   shardIdx = nodeRef.get() % SEMA_SHARD_NUM;
    auto&            shard    = shards_[shardIdx];
    std::unique_lock lock(shard.mutex);

    AstNode& node = ast().node(nodeRef);
    setSemaKind(node, NodeSemaKind::SymbolList);
    setSemaShard(node, shardIdx);

    const Ref value = shard.store.push_span(symbols).get();
    node.setSemaRef(value);

    SmallVector<const Symbol*> tmp;
    tmp.reserve(symbols.size());
    for (const auto* s : symbols)
        tmp.push_back(s);
    updateSemaFlags(node, std::span{tmp.data(), tmp.size()});
}

void SemaContext::setSymbolList(AstNodeRef nodeRef, std::span<const Symbol*> symbols)
{
    setSymbolListImpl(nodeRef, symbols);
}

void SemaContext::setSymbolList(AstNodeRef nodeRef, std::span<Symbol*> symbols)
{
    setSymbolListImpl(nodeRef, symbols);
}

void SemaContext::updateSemaFlags(AstNode& node, std::span<const Symbol*> symbols)
{
    bool isValue  = true;
    bool isLValue = true;
    for (const auto* sym : symbols)
    {
        if (!sym->isValueExpr())
            isValue = false;
        if (!sym->isVariable() && !sym->isFunction())
            isLValue = false;
    }

    if (isValue)
        addSemaFlags(node, NodeSemaFlags::Value);
    else
        removeSemaFlags(node, NodeSemaFlags::Value);

    if (isLValue)
        addSemaFlags(node, NodeSemaFlags::LValue);
    else
        removeSemaFlags(node, NodeSemaFlags::LValue);
}

bool SemaContext::hasPayload(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return semaKind(node) == NodeSemaKind::Payload;
}

void SemaContext::setPayload(AstNodeRef nodeRef, void* payload)
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

void* SemaContext::getPayload(AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasPayload(nodeRef));
    const AstNode& node     = ast().node(nodeRef);
    const uint32_t shardIdx = semaShard(node);
    auto&          shard    = shards_[shardIdx];
    return *shard.store.ptr<void*>(node.semaRef());
}

void SemaContext::inheritSemaFlags(AstNode& nodeDst, const AstNode& nodeSrc)
{
    constexpr uint16_t mask = SEMA_FLAGS_MASK;
    nodeDst.semaBits()      = (nodeDst.semaBits() & ~mask) | (nodeSrc.semaBits() & mask);
}

void SemaContext::inheritSemaKindRef(AstNode& nodeDst, const AstNode& nodeSrc)
{
    constexpr uint16_t mask = SEMA_KIND_MASK | SEMA_SHARD_MASK;
    nodeDst.semaBits()      = (nodeDst.semaBits() & ~mask) | (nodeSrc.semaBits() & mask);
    nodeDst.setSemaRef(nodeSrc.semaRef());
}

void SemaContext::inheritSema(AstNode& nodeDst, const AstNode& nodeSrc)
{
    inheritSemaFlags(nodeDst, nodeSrc);
    inheritSemaKindRef(nodeDst, nodeSrc);
}

SWC_END_NAMESPACE();
