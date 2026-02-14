#include "pch.h"
#include "Compiler/Sema/Core/NodePayloadContext.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Main/TaskContext.h"
#if SWC_HAS_REF_DEBUG_INFO
#include "Compiler/Sema/Type/TypeManager.h"
#endif

SWC_BEGIN_NAMESPACE();

namespace
{
    bool isCallLikeNode(const AstNode& node)
    {
        return node.is(AstNodeId::CallExpr) ||
               node.is(AstNodeId::IntrinsicCallExpr) ||
               node.is(AstNodeId::AliasCallExpr) ||
               node.is(AstNodeId::CompilerCall) ||
               node.is(AstNodeId::CompilerCallOne);
    }

    TypeRef unwrapFunctionReturnTypeIfCall(const TaskContext& ctx, const AstNode& node, TypeRef typeRef)
    {
        if (!typeRef.isValid() || !isCallLikeNode(node))
            return typeRef;

        const TypeInfo& type = ctx.typeMgr().get(typeRef);
        if (type.isFunction())
        {
            const TypeRef returnTypeRef = type.payloadSymFunction().returnTypeRef();
            return returnTypeRef.isValid() ? returnTypeRef : typeRef;
        }

        if (type.isAlias())
        {
            const TypeRef unaliasedRef = type.unwrap(ctx, TypeRef::invalid(), TypeExpandE::Alias);
            if (unaliasedRef.isValid())
            {
                const TypeInfo& unaliased = ctx.typeMgr().get(unaliasedRef);
                if (unaliased.isFunction())
                {
                    const TypeRef returnTypeRef = unaliased.payloadSymFunction().returnTypeRef();
                    return returnTypeRef.isValid() ? returnTypeRef : typeRef;
                }
            }
        }

        return typeRef;
    }
}

bool NodePayloadContext::hasConstant(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const ConstantRef cstRef = getConstantRef(ctx, nodeRef);
    return cstRef.isValid();
}

const ConstantValue& NodePayloadContext::getConstant(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasConstant(ctx, nodeRef));
    const ConstantRef cstRef = getConstantRef(ctx, nodeRef);
    SWC_ASSERT(cstRef.isValid());
    return ctx.cstMgr().get(cstRef);
}

ConstantRef NodePayloadContext::getConstantRef(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return ConstantRef::invalid();

    const AstNode& node = ast().node(nodeRef);
    const auto     info = payloadInfo(node);
    switch (info.kind)
    {
        case NodePayloadKind::ConstantRef:
        {
            ConstantRef value{info.ref};
#if SWC_HAS_REF_DEBUG_INFO
            value.dbgPtr = &ctx.cstMgr().get(value);
#endif
            return value;
        }

        case NodePayloadKind::SymbolRef:
        {
            const Symbol& sym = getSymbol(ctx, nodeRef);
            if (sym.isConstant())
                return sym.cast<SymbolConstant>().cstRef();
            if (sym.isEnumValue())
                return sym.cast<SymbolEnumValue>().cstRef();
            break;
        }

        case NodePayloadKind::SymbolList:
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

void NodePayloadContext::setConstant(AstNodeRef nodeRef, ConstantRef ref)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(ref.isValid());
    AstNode& node = ast().node(nodeRef);
    setPayloadKind(node, NodePayloadKind::ConstantRef);
    node.setPayloadRef(ref.get());
    addPayloadFlags(node, NodePayloadFlags::Value);
}

bool NodePayloadContext::hasSubstitute(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return payloadInfo(node).kind == NodePayloadKind::Substitute;
}

void NodePayloadContext::setSubstitute(AstNodeRef nodeRef, AstNodeRef substNodeRef)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(substNodeRef.isValid());
    AstNode& node = ast().node(nodeRef);
    setPayloadKind(node, NodePayloadKind::Substitute);
    node.setPayloadRef(substNodeRef.get());
}

AstNodeRef NodePayloadContext::getSubstituteRef(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return nodeRef;

    const AstNode* node = &ast().node(nodeRef);
    while (payloadInfo(*node).kind == NodePayloadKind::Substitute)
    {
        nodeRef = AstNodeRef{payloadInfo(*node).ref};
        node    = &ast().node(nodeRef);
    }

#if SWC_HAS_REF_DEBUG_INFO
    nodeRef.dbgPtr = &ast().node(nodeRef);
#endif
    return nodeRef;
}

bool NodePayloadContext::hasType(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const TypeRef typeRef = getTypeRef(ctx, nodeRef);
    return typeRef.isValid();
}

TypeRef NodePayloadContext::getTypeRef(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return TypeRef::invalid();

    const AstNode&        node  = ast().node(nodeRef);
    const auto            info  = payloadInfo(node);
    const NodePayloadKind kind  = info.kind;
    TypeRef               value = TypeRef::invalid();
    switch (kind)
    {
        case NodePayloadKind::ConstantRef:
            value = getConstant(ctx, nodeRef).typeRef();
            break;
        case NodePayloadKind::TypeRef:
            value = TypeRef{info.ref};
            break;
        case NodePayloadKind::SymbolRef:
            value = getSymbol(ctx, nodeRef).typeRef();
            break;
        case NodePayloadKind::SymbolList:
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
    return unwrapFunctionReturnTypeIfCall(ctx, node, value);
}

void NodePayloadContext::setType(AstNodeRef nodeRef, TypeRef ref)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(ref.isValid());
    AstNode& node = ast().node(nodeRef);
    setPayloadKind(node, NodePayloadKind::TypeRef);
    node.setPayloadRef(ref.get());
}

bool NodePayloadContext::hasSymbol(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return payloadInfo(node).kind == NodePayloadKind::SymbolRef;
}

const Symbol& NodePayloadContext::getSymbol(const TaskContext&, AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasSymbol(nodeRef));
    const AstNode& node     = ast().node(nodeRef);
    const auto     info     = payloadInfo(node);
    const uint32_t shardIdx = info.shardIdx;
    auto&          shard    = shards_[shardIdx];
    const Symbol&  value    = **shard.store.ptr<Symbol*>(info.ref);
    return value;
}

Symbol& NodePayloadContext::getSymbol(const TaskContext&, AstNodeRef nodeRef)
{
    SWC_ASSERT(hasSymbol(nodeRef));
    const AstNode& node     = ast().node(nodeRef);
    const auto     info     = payloadInfo(node);
    const uint32_t shardIdx = info.shardIdx;
    auto&          shard    = shards_[shardIdx];
    Symbol&        value    = **shard.store.ptr<Symbol*>(info.ref);
    return value;
}

void NodePayloadContext::setSymbol(AstNodeRef nodeRef, const Symbol* symbol)
{
    SWC_ASSERT(symbol);
    const uint32_t   shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    auto&            shard    = shards_[shardIdx];
    std::unique_lock lock(shard.mutex);

    AstNode& node = ast().node(nodeRef);
    setPayloadKind(node, NodePayloadKind::SymbolRef);
    setPayloadShard(node, shardIdx);

    const Ref value = shard.store.pushBack(symbol);
    node.setPayloadRef(value);
    updatePayloadFlags(node, std::span{&symbol, 1});
}

bool NodePayloadContext::hasSymbolList(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return payloadInfo(node).kind == NodePayloadKind::SymbolList;
}

std::span<const Symbol*> NodePayloadContext::getSymbolListImpl(AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasSymbolList(nodeRef));
    const AstNode& node     = ast().node(nodeRef);
    const auto     info     = payloadInfo(node);
    const uint32_t shardIdx = info.shardIdx;
    auto&          shard    = shards_[shardIdx];
    const auto     spanView = shard.store.span<const Symbol*>(info.ref);

    if (spanView.empty())
        return {};

    const auto  it    = spanView.chunksBegin();
    const auto& chunk = *it;
    SWC_ASSERT(chunk.count == spanView.size());
    return std::span{static_cast<const Symbol**>(const_cast<void*>(chunk.ptr)), chunk.count};
}

std::span<const Symbol*> NodePayloadContext::getSymbolList(AstNodeRef nodeRef) const
{
    return getSymbolListImpl(nodeRef);
}

std::span<Symbol*> NodePayloadContext::getSymbolList(AstNodeRef nodeRef)
{
    const auto res = getSymbolListImpl(nodeRef);
    return {const_cast<Symbol**>(res.data()), res.size()};
}

void NodePayloadContext::setSymbolListImpl(AstNodeRef nodeRef, std::span<const Symbol*> symbols)
{
    const uint32_t   shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    auto&            shard    = shards_[shardIdx];
    std::unique_lock lock(shard.mutex);

    AstNode& node = ast().node(nodeRef);
    setPayloadKind(node, NodePayloadKind::SymbolList);
    setPayloadShard(node, shardIdx);

    const Ref value = shard.store.pushSpan(symbols).get();
    node.setPayloadRef(value);
    updatePayloadFlags(node, symbols);
}

void NodePayloadContext::setSymbolListImpl(AstNodeRef nodeRef, std::span<Symbol*> symbols)
{
    const uint32_t   shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    auto&            shard    = shards_[shardIdx];
    std::unique_lock lock(shard.mutex);

    AstNode& node = ast().node(nodeRef);
    setPayloadKind(node, NodePayloadKind::SymbolList);
    setPayloadShard(node, shardIdx);

    const Ref value = shard.store.pushSpan(symbols).get();
    node.setPayloadRef(value);

    SmallVector<const Symbol*> tmp;
    tmp.reserve(symbols.size());
    for (const auto* s : symbols)
        tmp.push_back(s);
    updatePayloadFlags(node, std::span{tmp.data(), tmp.size()});
}

void NodePayloadContext::setSymbolList(AstNodeRef nodeRef, std::span<const Symbol*> symbols)
{
    setSymbolListImpl(nodeRef, symbols);
}

void NodePayloadContext::setSymbolList(AstNodeRef nodeRef, std::span<Symbol*> symbols)
{
    setSymbolListImpl(nodeRef, symbols);
}

void NodePayloadContext::updatePayloadFlags(AstNode& node, std::span<const Symbol*> symbols)
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
        addPayloadFlags(node, NodePayloadFlags::Value);
    else
        removePayloadFlags(node, NodePayloadFlags::Value);

    if (isLValue)
        addPayloadFlags(node, NodePayloadFlags::LValue);
    else
        removePayloadFlags(node, NodePayloadFlags::LValue);
}

bool NodePayloadContext::hasPayload(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return payloadInfo(node).kind == NodePayloadKind::Payload;
}

void NodePayloadContext::setPayload(AstNodeRef nodeRef, void* payload)
{
    SWC_ASSERT(nodeRef.isValid());

    const uint32_t   shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    auto&            shard    = shards_[shardIdx];
    std::unique_lock lock(shard.mutex);

    AstNode& node = ast().node(nodeRef);
    setPayloadKind(node, NodePayloadKind::Payload);
    setPayloadShard(node, shardIdx);

    const Ref value = shard.store.pushBack(payload);
    node.setPayloadRef(value);
}

void* NodePayloadContext::getPayload(AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasPayload(nodeRef));
    const AstNode& node     = ast().node(nodeRef);
    const auto     info     = payloadInfo(node);
    const uint32_t shardIdx = info.shardIdx;
    auto&          shard    = shards_[shardIdx];
    return *shard.store.ptr<void*>(info.ref);
}

bool NodePayloadContext::hasCodeGenPayload(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return payloadKind(node) == NodePayloadKind::CodeGenPayload;
}

void NodePayloadContext::setCodeGenPayload(AstNodeRef nodeRef, void* payload)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(payload);

    AstNode& node = ast().node(nodeRef);
    if (payloadKind(node) == NodePayloadKind::CodeGenPayload)
    {
        CodeGenPayloadStorage* storage = codeGenPayloadStorage(node);
        SWC_ASSERT(storage);
        storage->payload = payload;
        return;
    }

    const NodePayloadKind originalKind  = payloadKind(node);
    const uint32_t        originalRef   = node.payloadRef();
    const uint32_t        originalShard = payloadShard(node);

    const uint32_t   shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    auto&            shard    = shards_[shardIdx];
    std::unique_lock lock(shard.mutex);

    const Ref value = shard.store.pushBack(CodeGenPayloadStorage{payload, originalKind, originalRef, originalShard});
    setPayloadKind(node, NodePayloadKind::CodeGenPayload);
    setPayloadShard(node, shardIdx);
    node.setPayloadRef(value);
}

void* NodePayloadContext::getCodeGenPayload(AstNodeRef nodeRef) const
{
    SWC_ASSERT(nodeRef.isValid());
    if (!hasCodeGenPayload(nodeRef))
        return nullptr;
    const AstNode&               node    = ast().node(nodeRef);
    const CodeGenPayloadStorage* storage = codeGenPayloadStorage(node);
    SWC_ASSERT(storage);
    return storage->payload;
}

void NodePayloadContext::propagatePayloadFlags(AstNode& nodeDst, const AstNode& nodeSrc, uint16_t mask, bool merge)
{
    if (merge)
        nodeDst.payloadBits() |= (nodeSrc.payloadBits() & mask);
    else
        nodeDst.payloadBits() = (nodeDst.payloadBits() & ~mask) | (nodeSrc.payloadBits() & mask);
}

void NodePayloadContext::inheritPayloadKindRef(AstNode& nodeDst, const AstNode& nodeSrc)
{
    constexpr uint16_t mask = NODE_PAYLOAD_KIND_MASK | NODE_PAYLOAD_SHARD_MASK;
    nodeDst.payloadBits()   = (nodeDst.payloadBits() & ~mask) | (nodeSrc.payloadBits() & mask);
    nodeDst.setPayloadRef(nodeSrc.payloadRef());
}

void NodePayloadContext::inheritPayload(AstNode& nodeDst, const AstNode& nodeSrc)
{
    propagatePayloadFlags(nodeDst, nodeSrc, NODE_PAYLOAD_FLAGS_MASK, false);
    inheritPayloadKindRef(nodeDst, nodeSrc);
}

NodePayloadContext::PayloadInfo NodePayloadContext::payloadInfo(const AstNode& node) const
{
    const NodePayloadKind kind = payloadKind(node);
    if (kind != NodePayloadKind::CodeGenPayload)
    {
        return {
            .kind     = kind,
            .ref      = node.payloadRef(),
            .shardIdx = payloadShard(node),
        };
    }

    const CodeGenPayloadStorage* storage = codeGenPayloadStorage(node);
    SWC_ASSERT(storage);
    return {
        .kind     = storage->originalKind,
        .ref      = storage->originalRef,
        .shardIdx = storage->originalShard,
    };
}

NodePayloadContext::CodeGenPayloadStorage* NodePayloadContext::codeGenPayloadStorage(const AstNode& node) const
{
    SWC_ASSERT(payloadKind(node) == NodePayloadKind::CodeGenPayload);
    const uint32_t shardIdx = payloadShard(node);
    auto&          shard    = const_cast<Shard&>(shards_[shardIdx]);
    return shard.store.ptr<CodeGenPayloadStorage>(node.payloadRef());
}

SWC_END_NAMESPACE();
