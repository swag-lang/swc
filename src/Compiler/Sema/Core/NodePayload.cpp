#include "pch.h"
#include "Support/Report/Assert.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Compiler/Parser/Ast/AstNodes.h"
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

    TypeRef unwrapFunctionReturnTypeIfCall(const NodePayload& payloadContext, const TaskContext& ctx, AstNodeRef nodeRef, const AstNode& node, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return typeRef;

        const bool shouldUnwrap =
            isCallLikeNode(node) ||
            payloadContext.hasResolvedCallArguments(nodeRef);
        if (!shouldUnwrap)
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

NodePayload::StoredView NodePayload::viewStored(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    StoredView view;
    if (nodeRef.isInvalid())
        return view;

    const AstNode& node = ast().node(nodeRef);
    view.flags          = payloadFlagsStored(node);
    view.typeRef        = getTypeRef(ctx, nodeRef);
    view.cstRef         = getConstantRef(ctx, nodeRef);

    const ResolvedSymbols resolved = resolveSymbols(nodeRef);
    if (resolved.isSymbolList)
    {
        view.hasSymbolList = true;
        view.symList       = {const_cast<const Symbol**>(resolved.symbols.data()), resolved.symbols.size()};
        view.hasSymbol     = !view.symList.empty();
        if (view.hasSymbol)
            view.sym = view.symList.front();
    }
    else if (!resolved.symbols.empty())
    {
        view.hasSymbol = true;
        view.sym       = resolved.symbols.front();
    }

    return view;
}

NodePayload::ResolvedSymbols NodePayload::resolveSymbols(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return {};

    const AstNode&    node = ast().node(nodeRef);
    const PayloadInfo info = payloadInfo(node);
    if (info.kind != NodePayloadKind::SymbolRef && info.kind != NodePayloadKind::SymbolList)
        return {};

    if (!tryGetShard(info.shardIdx))
        return {};

    return {.symbols = symbolsFromInfo(info), .isSymbolList = info.kind == NodePayloadKind::SymbolList};
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

void NodePayload::storePayload(AstNode& node, uint16_t bits, uint32_t ref)
{
    node.storePayloadState(AstNode::makePayloadState(bits, ref));
}

void NodePayload::setPayloadKind(AstNode& node, NodePayloadKind value)
{
    const uint64_t state   = node.payloadState();
    const uint16_t bits    = AstNode::payloadBitsFromState(state);
    const uint32_t ref     = AstNode::payloadRefFromState(state);
    const uint16_t newBits = static_cast<uint16_t>((bits & ~NODE_PAYLOAD_KIND_MASK) | static_cast<uint16_t>(value));
    storePayload(node, newBits, ref);
}

void NodePayload::setPayloadShard(AstNode& node, uint32_t shard)
{
    const uint64_t state   = node.payloadState();
    const uint16_t bits    = AstNode::payloadBitsFromState(state);
    const uint32_t ref     = AstNode::payloadRefFromState(state);
    const uint16_t newBits = static_cast<uint16_t>((bits & ~NODE_PAYLOAD_SHARD_MASK) | static_cast<uint16_t>(shard << NODE_PAYLOAD_SHARD_SHIFT));
    storePayload(node, newBits, ref);
}

void NodePayload::addPayloadFlags(AstNode& node, NodePayloadFlags value)
{
    const uint64_t state   = node.payloadState();
    const uint16_t bits    = AstNode::payloadBitsFromState(state);
    const uint32_t ref     = AstNode::payloadRefFromState(state);
    const uint16_t newBits = static_cast<uint16_t>(bits | static_cast<uint16_t>(value));
    storePayload(node, newBits, ref);
}

void NodePayload::removePayloadFlags(AstNode& node, NodePayloadFlags value)
{
    const uint64_t state   = node.payloadState();
    const uint16_t bits    = AstNode::payloadBitsFromState(state);
    const uint32_t ref     = AstNode::payloadRefFromState(state);
    const uint16_t newBits = static_cast<uint16_t>(bits & ~static_cast<uint16_t>(value));
    storePayload(node, newBits, ref);
}

uint16_t NodePayload::applySymbolPayloadFlags(uint16_t bits, std::span<const Symbol*> symbols)
{
    bits = static_cast<uint16_t>(bits & ~static_cast<uint16_t>(NodePayloadFlags::Value));
    bits = static_cast<uint16_t>(bits & ~static_cast<uint16_t>(NodePayloadFlags::LValue));

    bool isValue  = true;
    bool isLValue = true;
    for (const Symbol* sym : symbols)
    {
        const Symbol* effective = sym;
        if (sym->isAlias())
        {
            const auto* aliased = sym->cast<SymbolAlias>().aliasedSymbol();
            if (aliased)
                effective = aliased;
        }

        if (!effective->isValueExpr())
            isValue = false;
        if (!effective->isVariable() && !effective->isFunction())
            isLValue = false;
    }

    if (isValue)
        bits = static_cast<uint16_t>(bits | static_cast<uint16_t>(NodePayloadFlags::Value));

    if (isLValue)
        bits = static_cast<uint16_t>(bits | static_cast<uint16_t>(NodePayloadFlags::LValue));

    return bits;
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
            if (!value.isValid())
                return ConstantRef::invalid();
#if SWC_HAS_REF_DEBUG_INFO
            value.dbgPtr = &ctx.cstMgr().get(value);
#endif
            return value;
        }

        case NodePayloadKind::SymbolRef:
        case NodePayloadKind::SymbolList:
        {
            const auto symbols = symbolsFromInfo(info);
            if (symbols.empty())
                break;
            if (info.kind == NodePayloadKind::SymbolList && symbols.size() > 1)
                break;

            const Symbol* front = symbols.front();
            if (!front)
                break;

            if (front->isConstant())
                return front->cast<SymbolConstant>().cstRef();
            if (front->isEnumValue())
                return front->cast<SymbolEnumValue>().cstRef();
            if (canFoldLetVariable(node, *front))
            {
                const auto& symVar = front->cast<SymbolVariable>();
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
    AstNode& node    = ast().node(nodeRef);
    uint16_t newBits = static_cast<uint16_t>((node.payloadBits() & ~NODE_PAYLOAD_KIND_MASK) | static_cast<uint16_t>(NodePayloadKind::ConstantRef));
    newBits          = static_cast<uint16_t>(newBits | static_cast<uint16_t>(NodePayloadFlags::Value));
    storePayload(node, newBits, ref.get());
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
    const std::scoped_lock lock(shard->storeMutex);

    const Ref value = shard->store.pushBack(SubstituteStorage{
        .substNodeRef  = substNodeRef,
        .originalKind  = info.kind,
        .originalRef   = info.ref,
        .originalShard = info.shardIdx,
        .originalFlags = payloadFlags(node),
    });

    const uint16_t newBits = static_cast<uint16_t>((node.payloadBits() & ~(NODE_PAYLOAD_KIND_MASK | NODE_PAYLOAD_SHARD_MASK)) |
                                                   static_cast<uint16_t>(NodePayloadKind::Substitute) |
                                                   static_cast<uint16_t>(shardIdx << NODE_PAYLOAD_SHARD_SHIFT));
    storePayload(node, newBits, value);
}

AstNodeRef NodePayload::getSubstituteRef(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return nodeRef;

    while (true)
    {
        const AstNode&    node  = ast().node(nodeRef);
        const uint64_t    state = node.payloadState();
        const PayloadInfo info  = {.kind     = static_cast<NodePayloadKind>(AstNode::payloadBitsFromState(state) & NODE_PAYLOAD_KIND_MASK),
                                   .ref      = AstNode::payloadRefFromState(state),
                                   .shardIdx = static_cast<uint32_t>((AstNode::payloadBitsFromState(state) & NODE_PAYLOAD_SHARD_MASK) >> NODE_PAYLOAD_SHARD_SHIFT)};
        if (info.kind != NodePayloadKind::Substitute)
            break;

        const Shard* shard = tryGetShard(info.shardIdx);
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
        {
            const ConstantRef cstRef{info.ref};
            if (cstRef.isInvalid())
                return TypeRef::invalid();
            value = ctx.cstMgr().get(cstRef).typeRef();
            break;
        }
        case NodePayloadKind::TypeRef:
            value = TypeRef{info.ref};
            break;
        case NodePayloadKind::SymbolRef:
        case NodePayloadKind::SymbolList:
        {
            const auto symbols = symbolsFromInfo(info);
            if (symbols.empty() || !symbols.back())
                return TypeRef::invalid();
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
    return unwrapFunctionReturnTypeIfCall(*this, ctx, nodeRef, node, value);
}

void NodePayload::setType(AstNodeRef nodeRef, TypeRef ref)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(ref.isValid());
    AstNode&       node    = ast().node(nodeRef);
    const uint16_t newBits = static_cast<uint16_t>((node.payloadBits() & ~NODE_PAYLOAD_KIND_MASK) | static_cast<uint16_t>(NodePayloadKind::TypeRef));
    storePayload(node, newBits, ref.get());
}

bool NodePayload::hasSymbol(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode&    node = ast().node(nodeRef);
    const PayloadInfo info = payloadInfo(node);
    if (info.kind != NodePayloadKind::SymbolRef)
        return false;

    return tryGetShard(info.shardIdx) != nullptr;
}

const Symbol& NodePayload::getSymbol(const TaskContext& ctx, AstNodeRef nodeRef) const
{
    SWC_UNUSED(ctx);
    SWC_ASSERT(hasSymbol(nodeRef));
    const AstNode&    node     = ast().node(nodeRef);
    const PayloadInfo info     = payloadInfo(node);
    const uint32_t    shardIdx = info.shardIdx;
    const Shard*      shard    = tryGetShard(shardIdx);
    SWC_ASSERT(shard != nullptr);
    const Symbol* const* slot  = (shard->store.ptr<Symbol*>(info.ref));
    const Symbol&        value = *(*slot);
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
    Symbol** slot  = (shard->store.ptr<Symbol*>(info.ref));
    Symbol&  value = *(*slot);
    return value;
}

void NodePayload::setSymbol(AstNodeRef nodeRef, const Symbol* symbol)
{
    SWC_ASSERT(symbol);
    AstNode& node = ast().node(nodeRef);
    // Constant binding identifiers are synthetic value nodes created while cloning inline
    // arguments; a later name lookup must not turn them back into source-scope variables.
    if (node.is(AstNodeId::Identifier) &&
        node.cast<AstIdentifier>().hasFlag(AstIdentifierFlagsE::ConstantBinding) &&
        payloadKind(node) == NodePayloadKind::ConstantRef)
        return;

    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*                 shard    = ensureShard(shardIdx);
    const std::scoped_lock lock(shard->storeMutex);

    const Ref value   = shard->store.pushBack(symbol);
    uint16_t  newBits = static_cast<uint16_t>((node.payloadBits() & ~(NODE_PAYLOAD_KIND_MASK | NODE_PAYLOAD_SHARD_MASK)) |
                                              static_cast<uint16_t>(NodePayloadKind::SymbolRef) |
                                              static_cast<uint16_t>(shardIdx << NODE_PAYLOAD_SHARD_SHIFT));
    newBits           = applySymbolPayloadFlags(newBits, std::span{&symbol, 1});
    storePayload(node, newBits, value);
}

bool NodePayload::hasSymbolList(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const AstNode&    node = ast().node(nodeRef);
    const PayloadInfo info = payloadInfo(node);
    if (info.kind != NodePayloadKind::SymbolList)
        return false;

    return tryGetShard(info.shardIdx) != nullptr;
}

std::span<const Symbol* const> NodePayload::getSymbolListImpl(AstNodeRef nodeRef) const
{
    SWC_ASSERT(hasSymbolList(nodeRef));
    const AstNode&    node     = ast().node(nodeRef);
    const PayloadInfo info     = payloadInfo(node);
    const uint32_t    shardIdx = info.shardIdx;
    const Shard*      shard    = tryGetShard(shardIdx);
    SWC_ASSERT(shard != nullptr);
    const auto spanView = shard->store.span<const Symbol*>(info.ref);

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
    const std::scoped_lock lock(shard->storeMutex);

    AstNode&  node    = ast().node(nodeRef);
    const Ref value   = shard->store.pushSpanContiguous(symbols).get();
    uint16_t  newBits = static_cast<uint16_t>((node.payloadBits() & ~(NODE_PAYLOAD_KIND_MASK | NODE_PAYLOAD_SHARD_MASK)) |
                                              static_cast<uint16_t>(NodePayloadKind::SymbolList) |
                                              static_cast<uint16_t>(shardIdx << NODE_PAYLOAD_SHARD_SHIFT));
    newBits           = applySymbolPayloadFlags(newBits, symbols);
    storePayload(node, newBits, value);
}

void NodePayload::setSymbolListImpl(AstNodeRef nodeRef, std::span<Symbol*> symbols)
{
    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*                 shard    = ensureShard(shardIdx);
    const std::scoped_lock lock(shard->storeMutex);

    AstNode&                   node  = ast().node(nodeRef);
    const Ref                  value = shard->store.pushSpanContiguous(symbols).get();
    SmallVector<const Symbol*> tmp;
    tmp.reserve(symbols.size());
    for (const Symbol* s : symbols)
        tmp.push_back(s);
    uint16_t newBits = static_cast<uint16_t>((node.payloadBits() & ~(NODE_PAYLOAD_KIND_MASK | NODE_PAYLOAD_SHARD_MASK)) |
                                             static_cast<uint16_t>(NodePayloadKind::SymbolList) |
                                             static_cast<uint16_t>(shardIdx << NODE_PAYLOAD_SHARD_SHIFT));
    newBits          = applySymbolPayloadFlags(newBits, std::span{tmp.data(), tmp.size()});
    storePayload(node, newBits, value);
}

void NodePayload::setSymbolList(AstNodeRef nodeRef, std::span<const Symbol*> symbols)
{
    setSymbolListImpl(nodeRef, symbols);
}

void NodePayload::setSymbolList(AstNodeRef nodeRef, std::span<Symbol*> symbols)
{
    setSymbolListImpl(nodeRef, symbols);
}

void NodePayload::copyResolvedCallArguments(AstNodeRef dstNodeRef, AstNodeRef srcNodeRef)
{
    if (dstNodeRef.isInvalid() || srcNodeRef.isInvalid() || dstNodeRef == srcNodeRef)
        return;

    SmallVector<ResolvedCallArgument> args;
    appendResolvedCallArguments(srcNodeRef, args);
    setResolvedCallArguments(dstNodeRef, args.span());
}

void NodePayload::updatePayloadFlags(AstNode& node, std::span<const Symbol*> symbols)
{
    const uint64_t state   = node.payloadState();
    const uint16_t newBits = applySymbolPayloadFlags(AstNode::payloadBitsFromState(state), symbols);
    storePayload(node, newBits, AstNode::payloadRefFromState(state));
}

void NodePayload::setResolvedCallArguments(AstNodeRef nodeRef, std::span<const ResolvedCallArgument> args)
{
    SWC_ASSERT(nodeRef.isValid());
    const uint32_t shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    if (args.empty())
    {
        Shard* shard = tryGetShard(shardIdx);
        if (!shard)
            return;

        const std::unique_lock lock(shard->resolvedCallArgsMutex);
        shard->resolvedCallArgsByNode.erase(nodeRef);
        return;
    }

    Shard*                 shard = ensureShard(shardIdx);
    const std::unique_lock lock(shard->resolvedCallArgsMutex);
    shard->resolvedCallArgsByNode[nodeRef].assign(args.begin(), args.end());
}

bool NodePayload::hasResolvedCallArguments(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const uint32_t shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    const Shard*   shard    = tryGetShard(shardIdx);
    if (!shard)
        return false;

    const std::shared_lock lock(shard->resolvedCallArgsMutex);
    return shard->resolvedCallArgsByNode.contains(nodeRef);
}

void NodePayload::appendResolvedCallArguments(AstNodeRef nodeRef, SmallVector<ResolvedCallArgument>& out) const
{
    if (nodeRef.isInvalid())
        return;
    const uint32_t shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    const Shard*   shard    = tryGetShard(shardIdx);
    if (!shard)
        return;

    const std::shared_lock lock(shard->resolvedCallArgsMutex);
    const auto             it = shard->resolvedCallArgsByNode.find(nodeRef);
    if (it == shard->resolvedCallArgsByNode.end())
        return;

    out.append(it->second.data(), it->second.size());
}

bool NodePayload::hasLoweringPayload(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const uint32_t shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    const Shard*   shard    = tryGetShard(shardIdx);
    if (!shard)
        return false;

    const std::shared_lock lock(shard->loweringPayloadsMutex);
    const auto             it = shard->loweringPayloads.find(nodeRef);
    return it != shard->loweringPayloads.end() && it->second != nullptr;
}

void NodePayload::setLoweringPayload(AstNodeRef nodeRef, void* payload)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(payload);
    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*                 shard    = ensureShard(shardIdx);
    const std::unique_lock lock(shard->loweringPayloadsMutex);
    shard->loweringPayloads[nodeRef] = payload;
}

void* NodePayload::getLoweringPayload(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return nullptr;
    const uint32_t shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    const Shard*   shard    = tryGetShard(shardIdx);
    if (!shard)
        return nullptr;

    const std::shared_lock lock(shard->loweringPayloadsMutex);
    const auto             it = shard->loweringPayloads.find(nodeRef);
    if (it == shard->loweringPayloads.end())
        return nullptr;
    return it->second;
}

bool NodePayload::hasSemaPayload(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const uint32_t shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    const Shard*   shard    = tryGetShard(shardIdx);
    if (!shard)
        return false;

    const std::shared_lock lock(shard->semaPayloadsMutex);
    const auto             it = shard->semaPayloads.find(nodeRef);
    return it != shard->semaPayloads.end() && it->second != nullptr;
}

bool NodePayload::hasInlinePayload(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const uint32_t shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    const Shard*   shard    = tryGetShard(shardIdx);
    if (!shard)
        return false;

    const std::shared_lock lock(shard->inlinePayloadsMutex);
    const auto             it = shard->inlinePayloads.find(nodeRef);
    return it != shard->inlinePayloads.end() && it->second != nullptr;
}

void NodePayload::setInlinePayload(AstNodeRef nodeRef, void* payload)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(payload);
    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*                 shard    = ensureShard(shardIdx);
    const std::unique_lock lock(shard->inlinePayloadsMutex);
    SWC_ASSERT(!shard->inlinePayloads.contains(nodeRef));
    shard->inlinePayloads[nodeRef] = payload;
}

void* NodePayload::getInlinePayload(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return nullptr;
    const uint32_t shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    const Shard*   shard    = tryGetShard(shardIdx);
    if (!shard)
        return nullptr;

    const std::shared_lock lock(shard->inlinePayloadsMutex);
    const auto             it = shard->inlinePayloads.find(nodeRef);
    if (it == shard->inlinePayloads.end())
        return nullptr;
    return it->second;
}

bool NodePayload::hasInlineContextOverride(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;
    const uint32_t shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    const Shard*   shard    = tryGetShard(shardIdx);
    if (!shard)
        return false;

    const std::shared_lock lock(shard->inlineContextOverridesMutex);
    const auto             it = shard->inlineContextOverrides.find(nodeRef);
    return it != shard->inlineContextOverrides.end() && it->second != nullptr;
}

void NodePayload::setInlineContextOverride(AstNodeRef nodeRef, void* payload)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(payload);
    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*                 shard    = ensureShard(shardIdx);
    const std::unique_lock lock(shard->inlineContextOverridesMutex);
    SWC_ASSERT(!shard->inlineContextOverrides.contains(nodeRef));
    shard->inlineContextOverrides[nodeRef] = payload;
}

void* NodePayload::getInlineContextOverride(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return nullptr;
    const uint32_t shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    const Shard*   shard    = tryGetShard(shardIdx);
    if (!shard)
        return nullptr;

    const std::shared_lock lock(shard->inlineContextOverridesMutex);
    const auto             it = shard->inlineContextOverrides.find(nodeRef);
    if (it == shard->inlineContextOverrides.end())
        return nullptr;
    return it->second;
}

void NodePayload::setSemaPayload(AstNodeRef nodeRef, void* payload)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(payload);
    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*                 shard    = ensureShard(shardIdx);
    const std::unique_lock lock(shard->semaPayloadsMutex);
    SWC_ASSERT(!shard->semaPayloads.contains(nodeRef));
    shard->semaPayloads[nodeRef] = payload;
}

void* NodePayload::getSemaPayload(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return nullptr;
    const uint32_t shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    const Shard*   shard    = tryGetShard(shardIdx);
    if (!shard)
        return nullptr;

    const std::shared_lock lock(shard->semaPayloadsMutex);
    const auto             it = shard->semaPayloads.find(nodeRef);
    if (it == shard->semaPayloads.end())
        return nullptr;
    return it->second;
}

void NodePayload::clearSemaPayload(AstNodeRef nodeRef)
{
    if (nodeRef.isInvalid())
        return;
    const uint32_t shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*         shard    = tryGetShard(shardIdx);
    if (!shard)
        return;

    const std::unique_lock lock(shard->semaPayloadsMutex);
    shard->semaPayloads.erase(nodeRef);
}

void NodePayload::propagatePayloadFlags(AstNode& nodeDst, const AstNode& nodeSrc, uint16_t mask, bool merge)
{
    const uint16_t srcBits = nodeSrc.payloadBits();
    const uint64_t dst     = nodeDst.payloadState();
    const uint16_t dstBits = AstNode::payloadBitsFromState(dst);
    const uint16_t newBits = merge ? static_cast<uint16_t>(dstBits | (srcBits & mask)) : static_cast<uint16_t>((dstBits & ~mask) | (srcBits & mask));
    storePayload(nodeDst, newBits, AstNode::payloadRefFromState(dst));
}

void NodePayload::inheritPayloadKindRef(AstNode& nodeDst, const AstNode& nodeSrc)
{
    constexpr uint16_t mask    = NODE_PAYLOAD_KIND_MASK | NODE_PAYLOAD_SHARD_MASK;
    const uint64_t     dst     = nodeDst.payloadState();
    const uint16_t     dstBits = AstNode::payloadBitsFromState(dst);
    const uint64_t     src     = nodeSrc.payloadState();
    const uint16_t     srcBits = AstNode::payloadBitsFromState(src);
    const uint16_t     newBits = static_cast<uint16_t>((dstBits & ~mask) | (srcBits & mask));
    storePayload(nodeDst, newBits, AstNode::payloadRefFromState(src));
}

void NodePayload::inheritPayload(AstNode& nodeDst, const AstNode& nodeSrc)
{
    const uint64_t dst     = nodeDst.payloadState();
    const uint16_t dstBits = AstNode::payloadBitsFromState(dst);
    const uint64_t src     = nodeSrc.payloadState();
    const uint16_t srcBits = AstNode::payloadBitsFromState(src);

    constexpr uint16_t mask    = NODE_PAYLOAD_FLAGS_MASK | NODE_PAYLOAD_KIND_MASK | NODE_PAYLOAD_SHARD_MASK;
    const uint16_t     newBits = static_cast<uint16_t>((dstBits & ~mask) | (srcBits & mask));
    storePayload(nodeDst, newBits, AstNode::payloadRefFromState(src));
}

NodePayload::PayloadInfo NodePayload::payloadInfo(const AstNode& node) const
{
    const uint64_t state = node.payloadState();
    PayloadInfo    info  = {
            .kind     = static_cast<NodePayloadKind>(AstNode::payloadBitsFromState(state) & NODE_PAYLOAD_KIND_MASK),
            .ref      = AstNode::payloadRefFromState(state),
            .shardIdx = static_cast<uint32_t>((AstNode::payloadBitsFromState(state) & NODE_PAYLOAD_SHARD_MASK) >> NODE_PAYLOAD_SHARD_SHIFT),
    };

    while (true)
    {
        if (info.kind == NodePayloadKind::Substitute)
        {
            const Shard* shard = tryGetShard(info.shardIdx);
            SWC_ASSERT(shard != nullptr);
            const auto* storage = shard->store.ptr<SubstituteStorage>(info.ref);
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

std::span<const Symbol* const> NodePayload::symbolsFromInfo(const PayloadInfo& info) const
{
    // Resolve the symbol(s) from a single, already-captured payload snapshot. Callers must
    // never re-read the node's payload to fetch the symbol after switching on its kind: a
    // concurrent kind transition (e.g. SymbolRef -> ConstantRef while a shared generic `where`
    // eval node is constant-folded) would otherwise make a ConstantRef/TypeRef value be
    // reinterpreted as a PagedStore offset, indexing past the store's pages.
    if (info.kind != NodePayloadKind::SymbolRef && info.kind != NodePayloadKind::SymbolList)
        return {};

    const Shard* shard = tryGetShard(info.shardIdx);
    if (!shard)
        return {};

    if (info.kind == NodePayloadKind::SymbolRef)
    {
        const Symbol* const* slot = shard->store.ptr<Symbol*>(info.ref);
        if (!slot || !*slot)
            return {};
        return std::span{slot, 1};
    }

    const auto spanView = shard->store.span<const Symbol*>(info.ref);
    if (spanView.empty())
        return {};

    const auto  it    = spanView.chunksBegin();
    const auto& chunk = *it;
    SWC_ASSERT(chunk.count == spanView.size());
    return std::span{static_cast<const Symbol* const*>(chunk.ptr), chunk.count};
}

NodePayloadFlags NodePayload::payloadFlagsStored(const AstNode& node) const
{
    const uint64_t state = node.payloadState();
    PayloadInfo    info  = {
            .kind     = static_cast<NodePayloadKind>(AstNode::payloadBitsFromState(state) & NODE_PAYLOAD_KIND_MASK),
            .ref      = AstNode::payloadRefFromState(state),
            .shardIdx = static_cast<uint32_t>((AstNode::payloadBitsFromState(state) & NODE_PAYLOAD_SHARD_MASK) >> NODE_PAYLOAD_SHARD_SHIFT),
    };

    auto flags = static_cast<NodePayloadFlags>(AstNode::payloadBitsFromState(state) & ~NODE_PAYLOAD_KIND_MASK & ~NODE_PAYLOAD_SHARD_MASK);
    while (true)
    {
        if (info.kind == NodePayloadKind::Substitute)
        {
            const Shard* shard = tryGetShard(info.shardIdx);
            SWC_ASSERT(shard != nullptr);
            const auto* storage = shard->store.ptr<SubstituteStorage>(info.ref);
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
    const uint64_t state    = node.payloadState();
    const uint32_t shardIdx = (AstNode::payloadBitsFromState(state) & NODE_PAYLOAD_SHARD_MASK) >> NODE_PAYLOAD_SHARD_SHIFT;
    Shard*         shard    = tryGetShard(shardIdx);
    SWC_ASSERT(shard != nullptr);
    return shard->store.ptr<SubstituteStorage>(AstNode::payloadRefFromState(state));
}

const NodePayload::SubstituteStorage* NodePayload::substituteStorage(const AstNode& node) const
{
    SWC_ASSERT(payloadKind(node) == NodePayloadKind::Substitute);
    const uint64_t state    = node.payloadState();
    const uint32_t shardIdx = (AstNode::payloadBitsFromState(state) & NODE_PAYLOAD_SHARD_MASK) >> NODE_PAYLOAD_SHARD_SHIFT;
    const Shard*   shard    = tryGetShard(shardIdx);
    SWC_ASSERT(shard != nullptr);
    return shard->store.ptr<SubstituteStorage>(AstNode::payloadRefFromState(state));
}

SWC_END_NAMESPACE();
