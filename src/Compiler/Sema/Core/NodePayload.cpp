#include "pch.h"
#include "Compiler/Sema/Core/NodePayload.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeInfo.h"
#include "Main/TaskContext.h"
#include "Support/Report/Assert.h"
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
               node.is(AstNodeId::CompilerCall) ||
               node.is(AstNodeId::CompilerCallOne);
    }

    TypeRef unwrapFunctionReturnTypeIfCall(const NodePayload& payloadContext, const TaskContext& ctx, AstNodeRef nodeRef, const AstNode& node, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return typeRef;

        const bool shouldUnwrap = isCallLikeNode(node) || payloadContext.hasResolvedCallArguments(nodeRef);
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

    // An atomic count lets readers skip locking empty payload tables.
    void* findSharedPayload(const RefPointerMap<AstNodeRef>& map, std::shared_mutex& mutex, const std::atomic<uint32_t>& count, AstNodeRef nodeRef)
    {
        if (!count.load(std::memory_order_acquire))
            return nullptr;

        const std::shared_lock lock(mutex);
        return map.find(nodeRef);
    }

    void storeSharedPayload(RefPointerMap<AstNodeRef>& map, std::shared_mutex& mutex, std::atomic<uint32_t>& count, AstNodeRef nodeRef, void* payload, bool mustBeNew)
    {
        const std::unique_lock lock(mutex);
        SWC_ASSERT(!mustBeNew || !map.find(nodeRef));
        map.set(nodeRef, payload);
        count.store(static_cast<uint32_t>(map.size()), std::memory_order_release);
    }

    // Aligned node refs make shard counts poor filters. Per-node bits record
    // which tables ever held an entry; refs outside this AST still need a lookup.
    constexpr uint8_t SIDE_TABLE_LOWERING        = 1 << 0;
    constexpr uint8_t SIDE_TABLE_INLINE          = 1 << 1;
    constexpr uint8_t SIDE_TABLE_INLINE_OVERRIDE = 1 << 2;
    constexpr uint8_t SIDE_TABLE_SEMA            = 1 << 3;
    constexpr uint8_t SIDE_TABLE_CALL_ARGS       = 1 << 4;
    constexpr uint8_t SIDE_TABLE_CONST_ASSIGN    = 1 << 5;

    void markSideTable(Ast& ast, AstNodeRef nodeRef, uint8_t table)
    {
        if (ast.hasNode(nodeRef))
            ast.node(nodeRef).markSideTable(table);
    }

    bool maySideTable(const Ast& ast, AstNodeRef nodeRef, uint8_t table)
    {
        return !ast.hasNode(nodeRef) || ast.node(nodeRef).maySideTable(table);
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
    node.updatePayloadBits(NODE_PAYLOAD_KIND_MASK, static_cast<uint16_t>(value));
}

void NodePayload::addPayloadFlags(AstNode& node, NodePayloadFlags value)
{
    node.updatePayloadBits(0, static_cast<uint16_t>(value));
}

void NodePayload::removePayloadFlags(AstNode& node, NodePayloadFlags value)
{
    node.updatePayloadBits(static_cast<uint16_t>(value), 0);
}

uint16_t NodePayload::applySymbolPayloadFlags(uint16_t bits, std::span<const Symbol* const> symbols)
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

    AstNode& node = ast().node(nodeRef);
    recordFoldedSourceSymbol(nodeRef, node);
    const uint16_t setBits = static_cast<uint16_t>(NodePayloadKind::ConstantRef) | static_cast<uint16_t>(NodePayloadFlags::Value);
    node.updatePayloadState(NODE_PAYLOAD_KIND_MASK, setBits, ref.get());
}

void NodePayload::clearConstant(AstNodeRef nodeRef)
{
    SWC_ASSERT(nodeRef.isValid());
    AstNode& node     = ast().node(nodeRef);
    uint64_t expected = node.payloadState();
    while (static_cast<NodePayloadKind>(AstNode::payloadBitsFromState(expected) & NODE_PAYLOAD_KIND_MASK) == NodePayloadKind::ConstantRef)
    {
        const uint64_t desired = AstNode::makePayloadState(AstNode::payloadBitsFromState(expected), ConstantRef::invalid().get());
        if (node.compareExchangePayloadState(expected, desired))
            return;
    }
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
    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*                 shard    = ensureShard(shardIdx);
    const std::scoped_lock lock(shard->storeMutex);
    // Readers may retain older payload snapshots, so published records stay immutable.
    const Ref value  = shard->store.pushBack(SubstituteStorage{});
    auto*     stored = shard->store.ptr<SubstituteStorage>(value);
    SWC_ASSERT(stored);

    uint64_t expected = node.payloadState();
    while (true)
    {
        const uint16_t bits = AstNode::payloadBitsFromState(expected);

        *stored = {
            .substNodeRef  = substNodeRef,
            .originalKind  = static_cast<NodePayloadKind>(bits & NODE_PAYLOAD_KIND_MASK),
            .originalFlags = static_cast<NodePayloadFlags>(bits & NODE_PAYLOAD_FLAGS_MASK),
            .originalRef   = AstNode::payloadRefFromState(expected),
            .originalShard = static_cast<uint32_t>((bits & NODE_PAYLOAD_SHARD_MASK) >> NODE_PAYLOAD_SHARD_SHIFT),
        };

        const uint16_t newBits = static_cast<uint16_t>((bits & ~(NODE_PAYLOAD_KIND_MASK | NODE_PAYLOAD_SHARD_MASK)) |
                                                       static_cast<uint16_t>(NodePayloadKind::Substitute) |
                                                       static_cast<uint16_t>(shardIdx << NODE_PAYLOAD_SHARD_SHIFT));
        const uint64_t desired = AstNode::makePayloadState(newBits, value);
        if (node.compareExchangePayloadState(expected, desired))
            return;
    }
}

// Follow the uncommon replacement chain until reaching an unsubstituted node.
AstNodeRef NodePayload::followSubstituteChain(AstNodeRef nodeRef) const
{
    while (true)
    {
        const AstNode& node  = ast().node(nodeRef);
        const uint64_t state = node.payloadState();

        const PayloadInfo info = {
            .kind     = static_cast<NodePayloadKind>(AstNode::payloadBitsFromState(state) & NODE_PAYLOAD_KIND_MASK),
            .ref      = AstNode::payloadRefFromState(state),
            .shardIdx = static_cast<uint32_t>((AstNode::payloadBitsFromState(state) & NODE_PAYLOAD_SHARD_MASK) >> NODE_PAYLOAD_SHARD_SHIFT)};
        if (info.kind != NodePayloadKind::Substitute)
        {
#if SWC_HAS_REF_DEBUG_INFO
            nodeRef.dbgPtr = &node;
#endif
            return nodeRef;
        }

        const Shard* shard = tryGetShard(info.shardIdx);
        SWC_ASSERT(shard != nullptr);
        const SubstituteStorage* storage = shard->store.ptr<SubstituteStorage>(info.ref);
        SWC_ASSERT(storage);
        nodeRef = storage->substNodeRef;
    }
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
    // Transparent wrappers inherit the callee symbol. A zero-argument call has
    // no argument-map entry, so its syntax must retain the result-type distinction.
    const AstNode* expression = &node;
    while (true)
    {
        AstNodeRef childRef;
        if (expression->is(AstNodeId::NamedArgument))
            childRef = expression->cast<AstNamedArgument>().nodeArgRef;
        else if (expression->is(AstNodeId::ParenExpr))
            childRef = expression->cast<AstParenExpr>().nodeExprRef;
        else
            break;

        expression = &ast().node(getSubstituteRef(childRef));
    }

    return unwrapFunctionReturnTypeIfCall(*this, ctx, nodeRef, *expression, value);
}

void NodePayload::setType(AstNodeRef nodeRef, TypeRef ref)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(ref.isValid());

    AstNode& node = ast().node(nodeRef);
    recordFoldedSourceSymbol(nodeRef, node);
    node.updatePayloadState(NODE_PAYLOAD_KIND_MASK, static_cast<uint16_t>(NodePayloadKind::TypeRef), ref.get());
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
    SWC_ASSERT(nodeRef.isValid());

    const AstNode&    node = ast().node(nodeRef);
    const PayloadInfo info = payloadInfo(node);
    SWC_ASSERT(info.kind == NodePayloadKind::SymbolRef);
    const uint32_t shardIdx = info.shardIdx;
    const Shard*   shard    = tryGetShard(shardIdx);
    SWC_ASSERT(shard != nullptr);

    const Symbol* const* slot  = (shard->store.ptr<Symbol*>(info.ref));
    const Symbol&        value = *(*slot);
    return value;
}

Symbol& NodePayload::getSymbol(const TaskContext& ctx, AstNodeRef nodeRef)
{
    SWC_UNUSED(ctx);
    SWC_ASSERT(nodeRef.isValid());

    const AstNode&    node = ast().node(nodeRef);
    const PayloadInfo info = payloadInfo(node);
    SWC_ASSERT(info.kind == NodePayloadKind::SymbolRef);
    const uint32_t shardIdx = info.shardIdx;
    Shard*         shard    = tryGetShard(shardIdx);
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

    const Ref value = shard->store.pushBack(symbol);

    const uint16_t symbolFlags = applySymbolPayloadFlags(0, std::span{&symbol, 1});
    const uint16_t clearMask   = NODE_PAYLOAD_KIND_MASK | NODE_PAYLOAD_SHARD_MASK | static_cast<uint16_t>(NodePayloadFlags::Value) | static_cast<uint16_t>(NodePayloadFlags::LValue);
    const uint16_t setBits     = static_cast<uint16_t>(NodePayloadKind::SymbolRef) |
                             static_cast<uint16_t>(shardIdx << NODE_PAYLOAD_SHARD_SHIFT) | symbolFlags;

    node.updatePayloadState(clearMask, setBits, value);
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
    SWC_ASSERT(nodeRef.isValid());

    const AstNode&    node = ast().node(nodeRef);
    const PayloadInfo info = payloadInfo(node);
    SWC_ASSERT(info.kind == NodePayloadKind::SymbolList);
    const uint32_t shardIdx = info.shardIdx;
    const Shard*   shard    = tryGetShard(shardIdx);
    SWC_ASSERT(shard != nullptr);

    const auto spanView = shard->store.span<const Symbol*>(info.ref);
    const auto it       = spanView.chunksBegin();

    if (!it.total)
        return {};

    const auto& chunk = *it;
    SWC_ASSERT(chunk.count == it.total);
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

void NodePayload::setSymbolListImpl(AstNodeRef nodeRef, std::span<const Symbol* const> symbols)
{
    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*                 shard    = ensureShard(shardIdx);
    const std::scoped_lock lock(shard->storeMutex);

    AstNode&  node  = ast().node(nodeRef);
    const Ref value = shard->store.pushSpanContiguous(symbols).get();

    const uint16_t symbolFlags = applySymbolPayloadFlags(0, symbols);
    const uint16_t clearMask   = NODE_PAYLOAD_KIND_MASK | NODE_PAYLOAD_SHARD_MASK | static_cast<uint16_t>(NodePayloadFlags::Value) | static_cast<uint16_t>(NodePayloadFlags::LValue);
    const uint16_t setBits     = static_cast<uint16_t>(NodePayloadKind::SymbolList) |
                             static_cast<uint16_t>(shardIdx << NODE_PAYLOAD_SHARD_SHIFT) | symbolFlags;

    node.updatePayloadState(clearMask, setBits, value);
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
    const uint16_t clearMask = static_cast<uint16_t>(NodePayloadFlags::Value) | static_cast<uint16_t>(NodePayloadFlags::LValue);
    node.updatePayloadBits(clearMask, applySymbolPayloadFlags(0, symbols));
}

void NodePayload::setResolvedCallArguments(AstNodeRef nodeRef, std::span<const ResolvedCallArgument> args)
{
    SWC_ASSERT(nodeRef.isValid());
    const uint32_t shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    if (args.empty())
    {
        // Empty calls usually have no entry to erase. Check the shard count and
        // node bit first, avoiding the lock when no entry can exist.
        Shard* shard = tryGetShard(shardIdx);
        if (!shard || !shard->resolvedCallArgsCount.load(std::memory_order_acquire) || !maySideTable(ast(), nodeRef, SIDE_TABLE_CALL_ARGS))
            return;

        const std::unique_lock lock(shard->resolvedCallArgsMutex);
        shard->resolvedCallArgsByNode.erase(nodeRef);
        shard->resolvedCallArgsCount.store(static_cast<uint32_t>(shard->resolvedCallArgsByNode.size()), std::memory_order_release);
        return;
    }

    Shard*                 shard = ensureShard(shardIdx);
    const std::unique_lock lock(shard->resolvedCallArgsMutex);
    shard->resolvedCallArgsByNode[nodeRef].assign(args.begin(), args.end());
    shard->resolvedCallArgsCount.store(static_cast<uint32_t>(shard->resolvedCallArgsByNode.size()), std::memory_order_release);
    markSideTable(ast(), nodeRef, SIDE_TABLE_CALL_ARGS);
}

bool NodePayload::hasResolvedCallArguments(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;

    const uint32_t shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    const Shard*   shard    = tryGetShard(shardIdx);
    if (!shard)
        return false;

    if (!shard->resolvedCallArgsCount.load(std::memory_order_acquire) || !maySideTable(ast(), nodeRef, SIDE_TABLE_CALL_ARGS))
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

    if (!shard->resolvedCallArgsCount.load(std::memory_order_acquire) || !maySideTable(ast(), nodeRef, SIDE_TABLE_CALL_ARGS))
        return;

    const std::shared_lock lock(shard->resolvedCallArgsMutex);
    const auto             it = shard->resolvedCallArgsByNode.find(nodeRef);
    if (it == shard->resolvedCallArgsByNode.end())
        return;

    out.append(it->second.data(), it->second.size());
}

ResolvedCallArgument NodePayload::getResolvedCallArgument(AstNodeRef nodeRef, uint32_t index) const
{
    SWC_ASSERT(nodeRef.isValid());
    const Shard* shard = tryGetShard(nodeRef.get() % NODE_PAYLOAD_SHARD_NUM);
    SWC_ASSERT(shard != nullptr);

    const std::shared_lock lock(shard->resolvedCallArgsMutex);
    const auto             it = shard->resolvedCallArgsByNode.find(nodeRef);
    SWC_ASSERT(it != shard->resolvedCallArgsByNode.end());
    SWC_ASSERT(index < it->second.size());
    return it->second[index];
}

std::optional<ResolvedCallArgument> NodePayload::tryGetResolvedCallArgument(AstNodeRef nodeRef, uint32_t index) const
{
    if (nodeRef.isInvalid())
        return std::nullopt;

    const Shard* shard = tryGetShard(nodeRef.get() % NODE_PAYLOAD_SHARD_NUM);
    if (!shard || !shard->resolvedCallArgsCount.load(std::memory_order_acquire) || !maySideTable(ast(), nodeRef, SIDE_TABLE_CALL_ARGS))
        return std::nullopt;

    const std::shared_lock lock(shard->resolvedCallArgsMutex);
    const auto             it = shard->resolvedCallArgsByNode.find(nodeRef);
    if (it == shard->resolvedCallArgsByNode.end() || index >= it->second.size())
        return std::nullopt;

    return it->second[index];
}

bool NodePayload::hasLoweringPayload(AstNodeRef nodeRef) const
{
    return getLoweringPayload(nodeRef) != nullptr;
}

void NodePayload::setLoweringPayload(AstNodeRef nodeRef, void* payload)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(payload);

    const uint32_t shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*         shard    = ensureShard(shardIdx);
    storeSharedPayload(shard->loweringPayloads, shard->loweringPayloadsMutex, shard->loweringPayloadsCount, nodeRef, payload, false);
    markSideTable(ast(), nodeRef, SIDE_TABLE_LOWERING);
}

void* NodePayload::getLoweringPayload(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return nullptr;

    const Shard* shard = tryGetShard(nodeRef.get() % NODE_PAYLOAD_SHARD_NUM);
    if (!shard || !shard->loweringPayloadsCount.load(std::memory_order_acquire) || !maySideTable(ast(), nodeRef, SIDE_TABLE_LOWERING))
        return nullptr;

    return findSharedPayload(shard->loweringPayloads, shard->loweringPayloadsMutex, shard->loweringPayloadsCount, nodeRef);
}

bool NodePayload::hasSemaPayload(AstNodeRef nodeRef) const
{
    return getSemaPayload(nodeRef) != nullptr;
}

bool NodePayload::hasInlinePayload(AstNodeRef nodeRef) const
{
    return getInlinePayload(nodeRef) != nullptr;
}

void NodePayload::setInlinePayload(AstNodeRef nodeRef, void* payload)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(payload);

    const uint32_t shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*         shard    = ensureShard(shardIdx);
    storeSharedPayload(shard->inlinePayloads, shard->inlinePayloadsMutex, shard->inlinePayloadsCount, nodeRef, payload, true);
    markSideTable(ast(), nodeRef, SIDE_TABLE_INLINE);
}

void* NodePayload::getInlinePayload(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return nullptr;

    const Shard* shard = tryGetShard(nodeRef.get() % NODE_PAYLOAD_SHARD_NUM);
    if (!shard || !shard->inlinePayloadsCount.load(std::memory_order_acquire) || !maySideTable(ast(), nodeRef, SIDE_TABLE_INLINE))
        return nullptr;

    return findSharedPayload(shard->inlinePayloads, shard->inlinePayloadsMutex, shard->inlinePayloadsCount, nodeRef);
}

bool NodePayload::hasInlineContextOverride(AstNodeRef nodeRef) const
{
    return getInlineContextOverride(nodeRef) != nullptr;
}

void NodePayload::setInlineContextOverride(AstNodeRef nodeRef, void* payload)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(payload);

    const uint32_t shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*         shard    = ensureShard(shardIdx);
    storeSharedPayload(shard->inlineContextOverrides, shard->inlineContextOverridesMutex, shard->inlineContextOverridesCount, nodeRef, payload, true);
    markSideTable(ast(), nodeRef, SIDE_TABLE_INLINE_OVERRIDE);
}

void* NodePayload::getInlineContextOverride(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return nullptr;

    const Shard* shard = tryGetShard(nodeRef.get() % NODE_PAYLOAD_SHARD_NUM);
    if (!shard || !shard->inlineContextOverridesCount.load(std::memory_order_acquire) || !maySideTable(ast(), nodeRef, SIDE_TABLE_INLINE_OVERRIDE))
        return nullptr;

    return findSharedPayload(shard->inlineContextOverrides, shard->inlineContextOverridesMutex, shard->inlineContextOverridesCount, nodeRef);
}

// Visitor paths request both inline tables, so share their node and shard checks.
void NodePayload::getInlineContext(AstNodeRef nodeRef, void*& outPayload, void*& outOverride) const
{
    outPayload  = nullptr;
    outOverride = nullptr;

    if (nodeRef.isInvalid())
        return;

    const Shard* shard = tryGetShard(nodeRef.get() % NODE_PAYLOAD_SHARD_NUM);
    if (!shard)
        return;

    const bool anyPayload  = shard->inlinePayloadsCount.load(std::memory_order_acquire) != 0;
    const bool anyOverride = shard->inlineContextOverridesCount.load(std::memory_order_acquire) != 0;
    if (!anyPayload && !anyOverride)
        return;

    const AstNode* node = ast().hasNode(nodeRef) ? &ast().node(nodeRef) : nullptr;
    if (anyPayload && (!node || node->maySideTable(SIDE_TABLE_INLINE)))
        outPayload = findSharedPayload(shard->inlinePayloads, shard->inlinePayloadsMutex, shard->inlinePayloadsCount, nodeRef);
    if (anyOverride && (!node || node->maySideTable(SIDE_TABLE_INLINE_OVERRIDE)))
        outOverride = findSharedPayload(shard->inlineContextOverrides, shard->inlineContextOverridesMutex, shard->inlineContextOverridesCount, nodeRef);
}

void NodePayload::setSemaPayload(AstNodeRef nodeRef, void* payload)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(payload);

    const uint32_t shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*         shard    = ensureShard(shardIdx);
    storeSharedPayload(shard->semaPayloads, shard->semaPayloadsMutex, shard->semaPayloadsCount, nodeRef, payload, true);
    markSideTable(ast(), nodeRef, SIDE_TABLE_SEMA);
}

void* NodePayload::getSemaPayload(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return nullptr;

    const Shard* shard = tryGetShard(nodeRef.get() % NODE_PAYLOAD_SHARD_NUM);
    if (!shard || !shard->semaPayloadsCount.load(std::memory_order_acquire) || !maySideTable(ast(), nodeRef, SIDE_TABLE_SEMA))
        return nullptr;

    return findSharedPayload(shard->semaPayloads, shard->semaPayloadsMutex, shard->semaPayloadsCount, nodeRef);
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
    shard->semaPayloadsCount.store(static_cast<uint32_t>(shard->semaPayloads.size()), std::memory_order_release);
}

void NodePayload::setConstAssignSourceParameter(AstNodeRef nodeRef, const SymbolVariable* sourceParam)
{
    SWC_ASSERT(nodeRef.isValid());
    SWC_ASSERT(sourceParam);

    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*                 shard    = ensureShard(shardIdx);
    const std::unique_lock lock(shard->constAssignSourceParametersMutex);
    shard->constAssignSourceParameters.set(nodeRef, sourceParam);
    shard->constAssignSourceParametersCount.store(static_cast<uint32_t>(shard->constAssignSourceParameters.size()), std::memory_order_release);
    markSideTable(ast(), nodeRef, SIDE_TABLE_CONST_ASSIGN);
}

void NodePayload::recordFoldedSourceSymbol(AstNodeRef nodeRef, const AstNode& node)
{
    const PayloadInfo info = payloadInfo(node);
    if (info.kind != NodePayloadKind::SymbolRef && info.kind != NodePayloadKind::SymbolList)
        return;

    // Only a resolved name folds; an overload set still waiting for a selection does not.
    const auto symbols = symbolsFromInfo(info);
    if (symbols.size() != 1 || !symbols.front())
        return;

    const Symbol& symbol = *symbols.front();
    if (!symbol.isValueExpr() && !retainEditorSymbols_)
        return;

    bool mayHide = retainEditorSymbols_ || !symbol.isPublic();
    for (const SymbolMap* owner = symbol.ownerSymMap(); owner && !mayHide; owner = owner->ownerSymMap())
        mayHide = owner->isStruct() || owner->isEnum();
    if (!mayHide)
        return;

    const uint32_t         shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    Shard*                 shard    = ensureShard(shardIdx);
    const std::unique_lock lock(shard->foldedSourceSymbolsMutex);
    shard->foldedSourceSymbols.set(nodeRef, &symbol);
    shard->foldedSourceSymbolsCount.store(static_cast<uint32_t>(shard->foldedSourceSymbols.size()), std::memory_order_release);
}

void NodePayload::recordImplicitPropagation(AstNodeRef nodeRef)
{
    if (!retainEditorSymbols_)
        return;

    const std::unique_lock lock(implicitPropagationsMutex_);
    implicitPropagations_.push_back(nodeRef);
}

const Symbol* NodePayload::foldedSourceSymbol(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return nullptr;

    const Shard* shard = tryGetShard(nodeRef.get() % NODE_PAYLOAD_SHARD_NUM);
    if (!shard || !shard->foldedSourceSymbolsCount.load(std::memory_order_acquire))
        return nullptr;

    const std::shared_lock lock(shard->foldedSourceSymbolsMutex);
    return shard->foldedSourceSymbols.find(nodeRef);
}

const SymbolVariable* NodePayload::getConstAssignSourceParameter(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return nullptr;

    const uint32_t shardIdx = nodeRef.get() % NODE_PAYLOAD_SHARD_NUM;
    const Shard*   shard    = tryGetShard(shardIdx);
    if (!shard)
        return nullptr;

    if (!shard->constAssignSourceParametersCount.load(std::memory_order_acquire) || !maySideTable(ast(), nodeRef, SIDE_TABLE_CONST_ASSIGN))
        return nullptr;

    const std::shared_lock lock(shard->constAssignSourceParametersMutex);
    return shard->constAssignSourceParameters.find(nodeRef);
}

void NodePayload::propagatePayloadFlags(AstNode& nodeDst, const AstNode& nodeSrc, uint16_t mask, bool merge)
{
    const uint16_t srcBits = nodeSrc.payloadBits();
    nodeDst.updatePayloadBits(merge ? 0 : mask, srcBits & mask);
}

void NodePayload::inheritPayloadKindRef(AstNode& nodeDst, const AstNode& nodeSrc)
{
    constexpr uint16_t mask    = NODE_PAYLOAD_KIND_MASK | NODE_PAYLOAD_SHARD_MASK;
    const uint64_t     src     = nodeSrc.payloadState();
    const uint16_t     srcBits = AstNode::payloadBitsFromState(src);
    nodeDst.updatePayloadState(mask, srcBits & mask, AstNode::payloadRefFromState(src));
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

    PayloadInfo info = {
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
    // Use the captured kind and reference together. Re-reading after dispatch can
    // race with SymbolRef-to-ConstantRef folding on shared generic eval nodes,
    // interpreting a constant/type reference as an invalid PagedStore offset.
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
    const auto it       = spanView.chunksBegin();
    if (!it.total)
        return {};

    const auto& chunk = *it;
    SWC_ASSERT(chunk.count == it.total);
    return std::span{static_cast<const Symbol* const*>(chunk.ptr), chunk.count};
}

NodePayloadFlags NodePayload::payloadFlagsStored(const AstNode& node) const
{
    const uint64_t state = node.payloadState();

    PayloadInfo info = {
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

SWC_END_NAMESPACE();
