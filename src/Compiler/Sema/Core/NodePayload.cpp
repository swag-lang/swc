#include "pch.h"
#include "Compiler/Sema/Core/NodePayload.h"
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
    bool canFoldLetVariableOnNode(const AstNode& node)
    {
        return node.isNot(AstNodeId::SingleVarDecl) &&
               node.isNot(AstNodeId::MultiVarDecl) &&
               node.isNot(AstNodeId::VarDeclList) &&
               node.isNot(AstNodeId::VarDeclDestructuring) &&
               node.isNot(AstNodeId::IfVarDecl) &&
               node.isNot(AstNodeId::WithVarDecl);
    }

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

    bool canFoldLetVariable(const AstNode& node, const Symbol& sym)
    {
        if (!canFoldLetVariableOnNode(node))
            return false;
        if (!sym.isLetVariable())
            return false;
        const auto& symVar = sym.cast<SymbolVariable>();
        if (symVar.cstRef().isInvalid())
            return false;
        return symVar.typeRef().isValid();
    }
}

NodePayload::~NodePayload()
{
    for (auto& shardRef : shards_)
        delete shardRef.load(std::memory_order_acquire);
}

NodePayload::Shard* NodePayload::ensureShard(uint32_t shardIdx)
{
    SWC_ASSERT(shardIdx < NODE_PAYLOAD_SHARD_NUM);

    Shard* shard = tryGetShard(shardIdx);
    if (shard)
        return shard;

    auto*  newShard = new Shard;
    Shard* expected = nullptr;
    if (shards_[shardIdx].compare_exchange_strong(expected, newShard, std::memory_order_release, std::memory_order_acquire))
        return newShard;

    delete newShard;
    SWC_ASSERT(expected != nullptr);
    return expected;
}

NodePayload::Shard* NodePayload::tryGetShard(uint32_t shardIdx)
{
    SWC_ASSERT(shardIdx < NODE_PAYLOAD_SHARD_NUM);
    return shards_[shardIdx].load(std::memory_order_acquire);
}

const NodePayload::Shard* NodePayload::tryGetShard(uint32_t shardIdx) const
{
    SWC_ASSERT(shardIdx < NODE_PAYLOAD_SHARD_NUM);
    return shards_[shardIdx].load(std::memory_order_acquire);
}

#if SWC_HAS_STATS
size_t NodePayload::memStorageUsed() const
{
    size_t result = 0;
    for (const auto& shardRef : shards_)
    {
        const Shard* shard = shardRef.load(std::memory_order_acquire);
        if (!shard)
            continue;

        const std::shared_lock lock(shard->mutex);
        result += shard->store.size();
    }

    return result;
}

size_t NodePayload::memStorageReserved() const
{
    size_t result = 0;
    for (const auto& shardRef : shards_)
    {
        const Shard* shard = shardRef.load(std::memory_order_acquire);
        if (!shard)
            continue;

        const std::shared_lock lock(shard->mutex);
        result += shard->store.allocatedBytes();
        result += shard->codeGenPayloads.bucket_count() * sizeof(void*);
        result += shard->codeGenPayloads.size() * (sizeof(std::pair<const AstNodeRef, void*>) + sizeof(void*));
        result += shard->semaPayloads.bucket_count() * sizeof(void*);
        result += shard->semaPayloads.size() * (sizeof(std::pair<const AstNodeRef, void*>) + sizeof(void*));
        result += shard->resolvedCallArgsByNode.bucket_count() * sizeof(void*);
        result += shard->resolvedCallArgsByNode.size() * (sizeof(std::pair<const AstNodeRef, SpanRef>) + sizeof(void*));
    }

    return result;
}
#endif

bool NodePayload::hasConstant(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const ConstantRef cstRef = getConstantRef(ctx, nodeRef);
    return cstRef.isValid();
}

const ConstantValue& NodePayload::getConstant(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasConstant(ctx, nodeRef));
    const ConstantRef cstRef = getConstantRef(ctx, nodeRef);
    SWC_ASSERT(cstRef.isValid());
    return ctx.cstMgr().get(cstRef);
}

ConstantRef NodePayload::getConstantRef(const TaskContext& ctx, AstNodeRef nodeRef) const
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
            if (canFoldLetVariable(node, sym))
            {
                const auto& symVar = sym.cast<SymbolVariable>();
                return symVar.cstRef();
            }
            break;
        }

        case NodePayloadKind::SymbolList:
        {
            const auto symList = getSymbolList(nodeRef);
            if (symList.size() > 1)
                return ConstantRef::invalid();
            if (symList.front()->isConstant())
                return symList.front()->cast<SymbolConstant>().cstRef();
            if (symList.front()->isEnumValue())
                return symList.front()->cast<SymbolEnumValue>().cstRef();
            if (canFoldLetVariable(node, *symList.front()))
            {
                const auto& symVar = symList.front()->cast<SymbolVariable>();
                return symVar.cstRef();
            }
            break;
        }

        default:
            break;
    }

    return ConstantRef::invalid();
}

void NodePayload::setConstant(AstNodeRef nodeRef, ConstantRef ref)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(ref.isValid());
    AstNode& node = ast().node(nodeRef);
    setPayloadKind(node, NodePayloadKind::ConstantRef);
    node.setPayloadRef(ref.get());
    addPayloadFlags(node, NodePayloadFlags::Value);
}

bool NodePayload::hasSubstitute(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;

    const AstNode& node = ast().node(nodeRef);
    return payloadKind(node) == NodePayloadKind::Substitute;
}

void NodePayload::setSubstitute(AstNodeRef nodeRef, AstNodeRef substNodeRef)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(substNodeRef.isValid());
    SWC_ASSERT(ast().node(substNodeRef).isNot(AstNodeId::Invalid));

    AstNode&               node     = ast().node(nodeRef);
    const auto             info     = payloadInfo(node);
    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*                 shard    = ensureShard(shardIdx);
    const std::unique_lock lock(shard->mutex);

    const Ref value = shard->store.pushBack(SubstituteStorage{
        .substNodeRef  = substNodeRef,
        .originalKind  = info.kind,
        .originalRef   = info.ref,
        .originalShard = info.shardIdx,
        .originalFlags = payloadFlags(node),
    });

    setPayloadKind(node, NodePayloadKind::Substitute);
    setPayloadShard(node, shardIdx);
    node.setPayloadRef(value);
}

AstNodeRef NodePayload::getSubstituteRef(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return nodeRef;

    while (true)
    {
        const AstNode&    node = ast().node(nodeRef);
        const PayloadInfo info = {.kind = payloadKind(node), .ref = node.payloadRef(), .shardIdx = payloadShard(node)};
        if (info.kind != NodePayloadKind::Substitute)
            break;

        const Shard*             shard   = tryGetShard(info.shardIdx);
        SWC_ASSERT(shard != nullptr);
        const SubstituteStorage* storage = shard->store.ptr<SubstituteStorage>(info.ref);
        SWC_ASSERT(storage);
        nodeRef = storage->substNodeRef;
    }

#if SWC_HAS_REF_DEBUG_INFO
    nodeRef.dbgPtr = &ast().node(nodeRef);
#endif
    return nodeRef;
}

bool NodePayload::hasType(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const TypeRef typeRef = getTypeRef(ctx, nodeRef);
    return typeRef.isValid();
}

TypeRef NodePayload::getTypeRef(const TaskContext& ctx, AstNodeRef nodeRef) const
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

void NodePayload::setType(AstNodeRef nodeRef, TypeRef ref)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(ref.isValid());
    AstNode& node = ast().node(nodeRef);
    setPayloadKind(node, NodePayloadKind::TypeRef);
    node.setPayloadRef(ref.get());
}

bool NodePayload::hasSymbol(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return payloadInfo(node).kind == NodePayloadKind::SymbolRef;
}

const Symbol& NodePayload::getSymbol(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    SWC_UNUSED(ctx);
    SWC_ASSERT(hasSymbol(nodeRef));
    const AstNode&       node     = ast().node(nodeRef);
    const PayloadInfo    info     = payloadInfo(node);
    const uint32_t       shardIdx = info.shardIdx;
    const Shard*         shard    = tryGetShard(shardIdx);
    SWC_ASSERT(shard != nullptr);
    const Symbol* const* slot     = (shard->store.ptr<Symbol*>(info.ref));
    const Symbol&        value    = *(*slot);
    return value;
}

Symbol& NodePayload::getSymbol(const TaskContext& ctx, AstNodeRef nodeRef)
{
    SWC_UNUSED(ctx);
    SWC_ASSERT(hasSymbol(nodeRef));
    const AstNode&    node     = ast().node(nodeRef);
    const PayloadInfo info     = payloadInfo(node);
    const uint32_t    shardIdx = info.shardIdx;
    Shard*            shard    = tryGetShard(shardIdx);
    SWC_ASSERT(shard != nullptr);
    Symbol**          slot     = (shard->store.ptr<Symbol*>(info.ref));
    Symbol&           value    = *(*slot);
    return value;
}

void NodePayload::setSymbol(AstNodeRef nodeRef, const Symbol* symbol)
{
    SWC_ASSERT(symbol);
    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*                 shard    = ensureShard(shardIdx);
    const std::unique_lock lock(shard->mutex);

    AstNode&  node  = ast().node(nodeRef);
    const Ref value = shard->store.pushBack(symbol);
    setPayloadKind(node, NodePayloadKind::SymbolRef);
    setPayloadShard(node, shardIdx);
    node.setPayloadRef(value);

    updatePayloadFlags(node, std::span{&symbol, 1});
}

bool NodePayload::hasSymbolList(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return payloadInfo(node).kind == NodePayloadKind::SymbolList;
}

std::span<const Symbol* const> NodePayload::getSymbolListImpl(AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasSymbolList(nodeRef));
    const AstNode&    node     = ast().node(nodeRef);
    const PayloadInfo info     = payloadInfo(node);
    const uint32_t    shardIdx = info.shardIdx;
    const Shard*      shard    = tryGetShard(shardIdx);
    SWC_ASSERT(shard != nullptr);
    const auto        spanView = shard->store.span<const Symbol*>(info.ref);

    if (spanView.empty())
        return {};

    const auto  it    = spanView.chunksBegin();
    const auto& chunk = *it;
    SWC_ASSERT(chunk.count == spanView.size());
    return std::span{static_cast<const Symbol* const*>(chunk.ptr), chunk.count};
}

std::span<const Symbol*> NodePayload::getSymbolList(AstNodeRef nodeRef) const
{
    const auto res = getSymbolListImpl(nodeRef);
    return {const_cast<const Symbol**>(res.data()), res.size()};
}

std::span<Symbol*> NodePayload::getSymbolList(AstNodeRef nodeRef)
{
    const auto res = getSymbolListImpl(nodeRef);
    return {const_cast<Symbol**>(res.data()), res.size()};
}

void NodePayload::setSymbolListImpl(AstNodeRef nodeRef, std::span<const Symbol*> symbols)
{
    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*                 shard    = ensureShard(shardIdx);
    const std::unique_lock lock(shard->mutex);

    AstNode&  node  = ast().node(nodeRef);
    const Ref value = shard->store.pushSpan(symbols).get();
    setPayloadKind(node, NodePayloadKind::SymbolList);
    setPayloadShard(node, shardIdx);
    node.setPayloadRef(value);

    updatePayloadFlags(node, symbols);
}

void NodePayload::setSymbolListImpl(AstNodeRef nodeRef, std::span<Symbol*> symbols)
{
    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*                 shard    = ensureShard(shardIdx);
    const std::unique_lock lock(shard->mutex);

    AstNode&  node  = ast().node(nodeRef);
    const Ref value = shard->store.pushSpan(symbols).get();
    setPayloadKind(node, NodePayloadKind::SymbolList);
    setPayloadShard(node, shardIdx);
    node.setPayloadRef(value);

    SmallVector<const Symbol*> tmp;
    tmp.reserve(symbols.size());
    for (const Symbol* s : symbols)
        tmp.push_back(s);
    updatePayloadFlags(node, std::span{tmp.data(), tmp.size()});
}

void NodePayload::setSymbolList(AstNodeRef nodeRef, std::span<const Symbol*> symbols)
{
    setSymbolListImpl(nodeRef, symbols);
}

void NodePayload::setSymbolList(AstNodeRef nodeRef, std::span<Symbol*> symbols)
{
    setSymbolListImpl(nodeRef, symbols);
}

void NodePayload::updatePayloadFlags(AstNode& node, std::span<const Symbol*> symbols)
{
    bool isValue  = true;
    bool isLValue = true;
    for (const Symbol* sym : symbols)
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

void NodePayload::setResolvedCallArguments(AstNodeRef nodeRef, std::span<const ResolvedCallArgument> args)
{
    SWC_ASSERT(nodeRef.isValid());
    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    if (args.empty())
    {
        Shard* shard = tryGetShard(shardIdx);
        if (!shard)
            return;

        const std::unique_lock lock(shard->mutex);
        shard->resolvedCallArgsByNode.erase(nodeRef);
        return;
    }

    Shard*                 shard = ensureShard(shardIdx);
    const std::unique_lock lock(shard->mutex);
    shard->resolvedCallArgsByNode[nodeRef] = shard->store.pushSpan(args);
}

void NodePayload::appendResolvedCallArguments(AstNodeRef nodeRef, SmallVector<ResolvedCallArgument>& out) const
{
    if (nodeRef.isInvalid())
        return;
    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    const Shard*           shard    = tryGetShard(shardIdx);
    if (!shard)
        return;

    const std::shared_lock lock(shard->mutex);
    const auto             it = shard->resolvedCallArgsByNode.find(nodeRef);
    if (it == shard->resolvedCallArgsByNode.end())
        return;

    const auto spanView = shard->store.span<ResolvedCallArgument>(it->second.get());
    for (PagedStore::SpanView::ChunkIterator it1 = spanView.chunksBegin(); it1 != spanView.chunksEnd(); ++it1)
    {
        const PagedStore::SpanView::Chunk& chunk = *it1;
        out.append(static_cast<const ResolvedCallArgument*>(chunk.ptr), chunk.count);
    }
}

bool NodePayload::hasCodeGenPayload(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    const Shard*           shard    = tryGetShard(shardIdx);
    if (!shard)
        return false;

    const std::shared_lock lock(shard->mutex);
    const auto             it = shard->codeGenPayloads.find(nodeRef);
    return it != shard->codeGenPayloads.end() && it->second != nullptr;
}

void NodePayload::setCodeGenPayload(AstNodeRef nodeRef, void* payload)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(payload);
    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*                 shard    = ensureShard(shardIdx);
    const std::unique_lock lock(shard->mutex);
    shard->codeGenPayloads[nodeRef] = payload;
}

void* NodePayload::getCodeGenPayload(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return nullptr;
    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    const Shard*           shard    = tryGetShard(shardIdx);
    if (!shard)
        return nullptr;

    const std::shared_lock lock(shard->mutex);
    const auto             it = shard->codeGenPayloads.find(nodeRef);
    if (it == shard->codeGenPayloads.end())
        return nullptr;
    return it->second;
}

bool NodePayload::hasSemaPayload(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    const Shard*           shard    = tryGetShard(shardIdx);
    if (!shard)
        return false;

    const std::shared_lock lock(shard->mutex);
    const auto             it = shard->semaPayloads.find(nodeRef);
    return it != shard->semaPayloads.end() && it->second != nullptr;
}

void NodePayload::setSemaPayload(AstNodeRef nodeRef, void* payload)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(payload);
    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*                 shard    = ensureShard(shardIdx);
    const std::unique_lock lock(shard->mutex);
    SWC_ASSERT(!shard->semaPayloads.contains(nodeRef));
    shard->semaPayloads[nodeRef] = payload;
}

void* NodePayload::getSemaPayload(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return nullptr;
    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    const Shard*           shard    = tryGetShard(shardIdx);
    if (!shard)
        return nullptr;

    const std::shared_lock lock(shard->mutex);
    const auto             it = shard->semaPayloads.find(nodeRef);
    if (it == shard->semaPayloads.end())
        return nullptr;
    return it->second;
}

void NodePayload::clearSemaPayload(AstNodeRef nodeRef)
{
    if (nodeRef.isInvalid())
        return;
    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*                 shard    = tryGetShard(shardIdx);
    if (!shard)
        return;

    const std::unique_lock lock(shard->mutex);
    shard->semaPayloads.erase(nodeRef);
}

void NodePayload::propagatePayloadFlags(AstNode& nodeDst, const AstNode& nodeSrc, uint16_t mask, bool merge)
{
    if (merge)
        nodeDst.payloadBits() |= (nodeSrc.payloadBits() & mask);
    else
        nodeDst.payloadBits() = (nodeDst.payloadBits() & ~mask) | (nodeSrc.payloadBits() & mask);
}

void NodePayload::inheritPayloadKindRef(AstNode& nodeDst, const AstNode& nodeSrc)
{
    constexpr uint16_t mask = NODE_PAYLOAD_KIND_MASK | NODE_PAYLOAD_SHARD_MASK;
    nodeDst.payloadBits()   = (nodeDst.payloadBits() & ~mask) | (nodeSrc.payloadBits() & mask);
    nodeDst.setPayloadRef(nodeSrc.payloadRef());
}

void NodePayload::inheritPayload(AstNode& nodeDst, const AstNode& nodeSrc)
{
    propagatePayloadFlags(nodeDst, nodeSrc, NODE_PAYLOAD_FLAGS_MASK, false);
    inheritPayloadKindRef(nodeDst, nodeSrc);
}

NodePayload::PayloadInfo NodePayload::payloadInfo(const AstNode& node) const
{
    PayloadInfo info = {
        .kind     = payloadKind(node),
        .ref      = node.payloadRef(),
        .shardIdx = payloadShard(node),
    };

    while (true)
    {
        if (info.kind == NodePayloadKind::Substitute)
        {
            const Shard* shard = tryGetShard(info.shardIdx);
            SWC_ASSERT(shard != nullptr);
            const auto*  storage = shard->store.ptr<SubstituteStorage>(info.ref);
            SWC_ASSERT(storage);
            info = {
                .kind     = storage->originalKind,
                .ref      = storage->originalRef,
                .shardIdx = storage->originalShard,
            };
            continue;
        }

        return info;
    }
}

NodePayloadFlags NodePayload::payloadFlagsStored(const AstNode& node) const
{
    PayloadInfo info = {
        .kind     = payloadKind(node),
        .ref      = node.payloadRef(),
        .shardIdx = payloadShard(node),
    };

    NodePayloadFlags flags = payloadFlags(node);
    while (true)
    {
        if (info.kind == NodePayloadKind::Substitute)
        {
            const Shard* shard = tryGetShard(info.shardIdx);
            SWC_ASSERT(shard != nullptr);
            const auto*  storage = shard->store.ptr<SubstituteStorage>(info.ref);
            SWC_ASSERT(storage);
            flags = storage->originalFlags;
            info  = {
                 .kind     = storage->originalKind,
                 .ref      = storage->originalRef,
                 .shardIdx = storage->originalShard,
            };
            continue;
        }

        return flags;
    }
}

NodePayload::SubstituteStorage* NodePayload::substituteStorage(const AstNode& node)
{
    SWC_ASSERT(payloadKind(node) == NodePayloadKind::Substitute);
    const uint32_t shardIdx = payloadShard(node);
    Shard*         shard    = tryGetShard(shardIdx);
    SWC_ASSERT(shard != nullptr);
    return shard->store.ptr<SubstituteStorage>(node.payloadRef());
}

const NodePayload::SubstituteStorage* NodePayload::substituteStorage(const AstNode& node) const
{
    SWC_ASSERT(payloadKind(node) == NodePayloadKind::Substitute);
    const uint32_t shardIdx = payloadShard(node);
    const Shard*   shard    = tryGetShard(shardIdx);
    SWC_ASSERT(shard != nullptr);
    return shard->store.ptr<SubstituteStorage>(node.payloadRef());
}

SWC_END_NAMESPACE();
