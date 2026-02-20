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

    AstNode&         node     = ast().node(nodeRef);
    const auto       info     = payloadInfo(node);
    const uint32_t   shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    auto&            shard    = shards_[shardIdx];
    std::unique_lock lock(shard.mutex);

    const Ref value = shard.store.pushBack(SubstituteStorage{
        .substNodeRef  = substNodeRef,
        .originalKind  = info.kind,
        .originalRef   = info.ref,
        .originalShard = info.shardIdx,
    });

    setPayloadKind(node, NodePayloadKind::Substitute);
    setPayloadShard(node, shardIdx);
    node.setPayloadRef(value);
}

AstNodeRef NodePayload::getSubstituteRef(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return nodeRef;

    const AstNode* node = &ast().node(nodeRef);
    while (payloadKind(*node) == NodePayloadKind::Substitute)
    {
        const SubstituteStorage* storage = substituteStorage(*node);
        SWC_ASSERT(storage);
        nodeRef = storage->substNodeRef;
        node    = &ast().node(nodeRef);
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
    const auto           info     = payloadInfo(node);
    const uint32_t       shardIdx = info.shardIdx;
    auto&                shard    = shards_[shardIdx];
    const Symbol* const* slot     = SWC_CHECK_NOT_NULL(shard.store.ptr<Symbol*>(info.ref));
    const Symbol&        value    = *SWC_CHECK_NOT_NULL(*slot);
    return value;
}

Symbol& NodePayload::getSymbol(const TaskContext& ctx, AstNodeRef nodeRef)
{
    SWC_UNUSED(ctx);
    SWC_ASSERT(hasSymbol(nodeRef));
    const AstNode& node     = ast().node(nodeRef);
    const auto     info     = payloadInfo(node);
    const uint32_t shardIdx = info.shardIdx;
    auto&          shard    = shards_[shardIdx];
    Symbol**       slot     = SWC_CHECK_NOT_NULL(shard.store.ptr<Symbol*>(info.ref));
    Symbol&        value    = *SWC_CHECK_NOT_NULL(*slot);
    return value;
}

void NodePayload::setSymbol(AstNodeRef nodeRef, const Symbol* symbol)
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

void NodePayload::setSymbolListImpl(AstNodeRef nodeRef, std::span<Symbol*> symbols)
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

bool NodePayload::hasPayload(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return payloadInfo(node).kind == NodePayloadKind::Payload;
}

void NodePayload::setPayload(AstNodeRef nodeRef, void* payload)
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

void* NodePayload::getPayload(AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasPayload(nodeRef));
    const AstNode& node     = ast().node(nodeRef);
    const auto     info     = payloadInfo(node);
    const uint32_t shardIdx = info.shardIdx;
    auto&          shard    = shards_[shardIdx];
    return *SWC_CHECK_NOT_NULL(shard.store.ptr<void*>(info.ref));
}

void NodePayload::setResolvedCallArguments(AstNodeRef nodeRef, std::span<const ResolvedCallArgument> args)
{
    SWC_ASSERT(nodeRef.isValid());

    AstNode& node = ast().node(nodeRef);
    if (payloadKind(node) == NodePayloadKind::ResolvedCallArgs)
    {
        const uint32_t           shardIdx = payloadShard(node);
        auto&                    shard    = shards_[shardIdx];
        std::unique_lock         lock(shard.mutex);
        ResolvedCallArgsStorage* storage = resolvedCallArgsStorage(node);
        SWC_ASSERT(storage);
        storage->argsSpan = args.empty() ? SpanRef::invalid() : shard.store.pushSpan(args);
        return;
    }

    const NodePayloadKind originalKind  = payloadKind(node);
    const uint32_t        originalRef   = node.payloadRef();
    const uint32_t        originalShard = payloadShard(node);

    const uint32_t   shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    auto&            shard    = shards_[shardIdx];
    std::unique_lock lock(shard.mutex);

    const ResolvedCallArgsStorage storage = {
        .argsSpan      = args.empty() ? SpanRef::invalid() : shard.store.pushSpan(args),
        .originalKind  = originalKind,
        .originalRef   = originalRef,
        .originalShard = originalShard,
    };
    const Ref value = shard.store.pushBack(storage);
    setPayloadKind(node, NodePayloadKind::ResolvedCallArgs);
    setPayloadShard(node, shardIdx);
    node.setPayloadRef(value);
}

void NodePayload::appendResolvedCallArguments(AstNodeRef nodeRef, SmallVector<ResolvedCallArgument>& out) const
{
    if (nodeRef.isInvalid())
        return;

    PayloadInfo info = {
        .kind     = payloadKind(ast().node(nodeRef)),
        .ref      = ast().node(nodeRef).payloadRef(),
        .shardIdx = payloadShard(ast().node(nodeRef)),
    };

    while (true)
    {
        if (info.kind == NodePayloadKind::CodeGenPayload)
        {
            auto&                        shard   = const_cast<Shard&>(shards_[info.shardIdx]);
            const CodeGenPayloadStorage* storage = shard.store.ptr<CodeGenPayloadStorage>(info.ref);
            SWC_ASSERT(storage);
            info = {
                .kind     = storage->originalKind,
                .ref      = storage->originalRef,
                .shardIdx = storage->originalShard,
            };
            continue;
        }

        if (info.kind == NodePayloadKind::ResolvedCallArgs)
        {
            auto&                          shard   = const_cast<Shard&>(shards_[info.shardIdx]);
            const ResolvedCallArgsStorage* storage = shard.store.ptr<ResolvedCallArgsStorage>(info.ref);
            SWC_ASSERT(storage);
            if (storage->argsSpan.isInvalid())
                return;
            const auto spanView = shard.store.span<ResolvedCallArgument>(storage->argsSpan.get());
            for (PagedStore::SpanView::ChunkIterator it = spanView.chunksBegin(); it != spanView.chunksEnd(); ++it)
            {
                const PagedStore::SpanView::Chunk& chunk = *it;
                out.append(static_cast<const ResolvedCallArgument*>(chunk.ptr), chunk.count);
            }
            return;
        }

        return;
    }
}

bool NodePayload::hasCodeGenPayload(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode& node = ast().node(nodeRef);
    return payloadKind(node) == NodePayloadKind::CodeGenPayload;
}

void NodePayload::setCodeGenPayload(AstNodeRef nodeRef, void* payload)
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

void* NodePayload::getCodeGenPayload(AstNodeRef nodeRef) const
{
    SWC_ASSERT(nodeRef.isValid());
    if (!hasCodeGenPayload(nodeRef))
        return nullptr;
    const AstNode&               node    = ast().node(nodeRef);
    const CodeGenPayloadStorage* storage = codeGenPayloadStorage(node);
    SWC_ASSERT(storage);
    return storage->payload;
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
        if (info.kind == NodePayloadKind::CodeGenPayload)
        {
            auto&                        shard   = const_cast<Shard&>(shards_[info.shardIdx]);
            const CodeGenPayloadStorage* storage = shard.store.ptr<CodeGenPayloadStorage>(info.ref);
            SWC_ASSERT(storage);
            info = {
                .kind     = storage->originalKind,
                .ref      = storage->originalRef,
                .shardIdx = storage->originalShard,
            };
            continue;
        }

        if (info.kind == NodePayloadKind::ResolvedCallArgs)
        {
            auto&                          shard   = const_cast<Shard&>(shards_[info.shardIdx]);
            const ResolvedCallArgsStorage* storage = shard.store.ptr<ResolvedCallArgsStorage>(info.ref);
            SWC_ASSERT(storage);
            info = {
                .kind     = storage->originalKind,
                .ref      = storage->originalRef,
                .shardIdx = storage->originalShard,
            };
            continue;
        }

        if (info.kind == NodePayloadKind::Substitute)
        {
            auto&                    shard   = const_cast<Shard&>(shards_[info.shardIdx]);
            const SubstituteStorage* storage = shard.store.ptr<SubstituteStorage>(info.ref);
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

NodePayload::CodeGenPayloadStorage* NodePayload::codeGenPayloadStorage(const AstNode& node) const
{
    SWC_ASSERT(payloadKind(node) == NodePayloadKind::CodeGenPayload);
    const uint32_t shardIdx = payloadShard(node);
    auto&          shard    = const_cast<Shard&>(shards_[shardIdx]);
    return shard.store.ptr<CodeGenPayloadStorage>(node.payloadRef());
}

NodePayload::ResolvedCallArgsStorage* NodePayload::resolvedCallArgsStorage(const AstNode& node) const
{
    SWC_ASSERT(payloadKind(node) == NodePayloadKind::ResolvedCallArgs);
    const uint32_t shardIdx = payloadShard(node);
    auto&          shard    = const_cast<Shard&>(shards_[shardIdx]);
    return shard.store.ptr<ResolvedCallArgsStorage>(node.payloadRef());
}

NodePayload::SubstituteStorage* NodePayload::substituteStorage(const AstNode& node) const
{
    SWC_ASSERT(payloadKind(node) == NodePayloadKind::Substitute);
    const uint32_t shardIdx = payloadShard(node);
    auto&          shard    = const_cast<Shard&>(shards_[shardIdx]);
    return shard.store.ptr<SubstituteStorage>(node.payloadRef());
}

SWC_END_NAMESPACE();
