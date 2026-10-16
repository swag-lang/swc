#include "pch.h"
#include "Compiler/Parser/Ast/Ast.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

bool Ast::hasNode(AstNodeRef nodeRef) const
{
    if (nodeRef.isInvalid())
        return false;

    const uint32_t globalRef = nodeRef.get();
    const uint32_t shard     = refShard(globalRef);
    if (shard >= SHARD_COUNT)
        return false;

    // The test reads the store's published page snapshot and a page's atomic fill, the same way
    // every unlocked node access does, so it takes no lock either.
    const uint32_t localRef = refLocal(globalRef);
    return shards_[shard].store.containsRef(localRef, sizeof(AstNode));
}

bool Ast::hasSpan(SpanRef spanRef) const
{
    if (spanRef.isInvalid())
        return false;

    const uint32_t globalRef = spanRef.get();
    const uint32_t shard     = refShard(globalRef);
    if (shard >= SHARD_COUNT)
        return false;

    const uint32_t localRef = refLocal(globalRef);
    return shards_[shard].store.containsRef(localRef);
}

void Ast::captureParsedNodeBoundary()
{
    // The parser fills a fresh Ast, and each shard's store only ever grows at its end: every
    // node of the tree lies below the shard's extent here, and every node made afterwards (a
    // generated parse, a clone, a sema expansion) lands at or above it. The extents draw that
    // line without walking the tree.
    for (uint32_t i = 0; i < SHARD_COUNT; i++)
    {
        std::shared_lock lock(shards_[i].mutex);
        parsedNodeBoundaryByShard_[i] = shards_[i].store.extentSize();
    }

    hasParsedNodeBoundary_ = true;
}

bool Ast::isAdditionalNode(AstNodeRef nodeRef) const
{
    if (!hasParsedNodeBoundary_ || nodeRef.isInvalid())
        return false;

    const uint32_t globalRef = nodeRef.get();
    const uint32_t shard     = refShard(globalRef);
    const uint32_t local     = refLocal(globalRef);
    SWC_ASSERT(shard < SHARD_COUNT);
    return local >= parsedNodeBoundaryByShard_[shard];
}

template<typename T>
void Ast::appendSpan(SmallVector<T>& out, SpanRef spanRef) const
{
    if (spanRef.isInvalid())
        return;

    const uint32_t g = spanRef.get();
    const uint32_t s = refShard(g);
    const uint32_t l = refLocal(g);

    const PagedStore::SpanView view = shards_[s].store.span<AstNodeRef>(l);
    for (PagedStore::SpanView::ChunkIterator it = view.chunksBegin(); it != view.chunksEnd(); ++it)
    {
        const PagedStore::SpanView::Chunk& c = *it;
        out.append(static_cast<const T*>(c.ptr), c.count);
    }
}

void Ast::appendNodes(SmallVector<AstNodeRef>& out, SpanRef spanRef) const
{
    appendSpan(out, spanRef);
}

size_t Ast::spanSize(SpanRef spanRef) const
{
    if (spanRef.isInvalid())
        return 0;

    const uint32_t g = spanRef.get();
    const uint32_t s = refShard(g);
    const uint32_t l = refLocal(g);

    const PagedStore::SpanView view = shards_[s].store.span<AstNodeRef>(l);
    return view.size();
}

AstNodeRef Ast::nthNode(SpanRef spanRef, size_t index) const
{
    if (spanRef.isInvalid())
        return AstNodeRef::invalid();

    const uint32_t g = spanRef.get();
    const uint32_t s = refShard(g);
    const uint32_t l = refLocal(g);

    const PagedStore::SpanView view = shards_[s].store.span<AstNodeRef>(l);
    if (index >= view.size())
        return AstNodeRef::invalid();

    size_t remaining = index;
    for (PagedStore::SpanView::ChunkIterator it = view.chunksBegin(); it != view.chunksEnd(); ++it)
    {
        const PagedStore::SpanView::Chunk& c = *it;
        if (remaining < c.count)
            return static_cast<const AstNodeRef*>(c.ptr)[remaining];
        remaining -= c.count;
    }

    return AstNodeRef::invalid();
}

AstNodeRef Ast::oneNode(SpanRef spanRef) const
{
    SWC_ASSERT(spanSize(spanRef) == 1);
    return nthNode(spanRef, 0);
}

std::optional<size_t> Ast::findNodeIndex(SpanRef spanRef, AstNodeRef nodeRef) const
{
    if (spanRef.isInvalid())
        return std::nullopt;

    const uint32_t             globalRef = spanRef.get();
    const PagedStore::SpanView view      = shards_[refShard(globalRef)].store.span<AstNodeRef>(refLocal(globalRef));
    size_t                     offset    = 0;
    for (auto it = view.chunksBegin(); it != view.chunksEnd(); ++it)
    {
        const std::span nodes(static_cast<const AstNodeRef*>(it->ptr), it->count);
        const auto      found = std::ranges::find(nodes, nodeRef);
        if (found != nodes.end())
            return offset + static_cast<size_t>(found - nodes.begin());
        offset += nodes.size();
    }

    return std::nullopt;
}

void Ast::appendTokens(SmallVector<TokenRef>& out, SpanRef spanRef) const
{
    appendSpan(out, spanRef);
}

AstNodeRef Ast::findNodeRef(const AstNode* node) const
{
    const AstNodeRef ref = tryFindNodeRef(node);
    if (ref.isValid())
        return ref;

    SWC_UNREACHABLE();
}

AstNodeRef Ast::tryFindNodeRef(const AstNode* node) const
{
    for (uint32_t i = 0; i < SHARD_COUNT; i++)
    {
        const Ref local = shards_[i].store.findRef(node);
        if (local != std::numeric_limits<Ref>::max())
            return AstNodeRef{packRef(i, local)};
    }

    return AstNodeRef::invalid();
}

bool Ast::isReachableNodeIndexCurrent(const ReachableNodeIndex& index) const
{
    for (uint32_t i = 0; i < SHARD_COUNT; i++)
    {
        std::shared_lock lock(shards_[i].mutex);
        if (index.watermarks[i] != shards_[i].store.size())
            return false;
    }
    return true;
}

void Ast::buildReachableNodeIndex() const
{
    auto index = std::make_unique<ReachableNodeIndex>();
    for (uint32_t i = 0; i < SHARD_COUNT; i++)
    {
        std::shared_lock shardLock(shards_[i].mutex);
        index->watermarks[i] = shards_[i].store.size();
    }

    // The traversal itself carries the reachability guarantee: a node parsed into this
    // storage but detached from the tree never enters the maps. Recording the first parent
    // also preserves the first root-to-node path selected by the former depth-first search.
    SmallVector<AstNodeRef>                        children;
    SmallVector<std::pair<AstNodeRef, AstNodeRef>> stack;
    stack.push_back({root_, AstNodeRef::invalid()});
    while (!stack.empty())
    {
        const auto [nodeRef, parentRef] = stack.back();
        stack.pop_back();
        if (!nodeRef.isValid())
            continue;

        // A new entry starts with an invalid node, which no recorded one has.
        const AstNode&             node  = this->node(nodeRef);
        ReachableNodeIndex::Entry& entry = index->entries.getOrInsert(reinterpret_cast<uintptr_t>(&node));
        if (entry.nodeRef.isValid())
            continue;
        entry = {.nodeRef = nodeRef, .parentRef = parentRef};

        children.clear();
        nodeIdInfos(node.id()).collectChildren(children, *this, node);
        for (const AstNodeRef childRef : std::ranges::reverse_view(children))
            stack.push_back({childRef, nodeRef});
    }

    reachableNodeIndex_ = std::move(index);
}

void Ast::releaseReachableNodeIndex() const
{
    const std::unique_lock lock(reachableNodeIndexMutex_);
    reachableNodeIndex_.reset();
}

AstNodeRef Ast::reachableNodeRef(const AstNode* targetNode) const
{
    if (!targetNode || root_.isInvalid())
        return AstNodeRef::invalid();

    {
        std::shared_lock lock(reachableNodeIndexMutex_);
        if (reachableNodeIndex_ && isReachableNodeIndexCurrent(*reachableNodeIndex_))
        {
            const ReachableNodeIndex::Entry* entry = reachableNodeIndex_->find(targetNode);
            return entry ? entry->nodeRef : AstNodeRef::invalid();
        }
    }

    std::unique_lock lock(reachableNodeIndexMutex_);
    if (!reachableNodeIndex_ || !isReachableNodeIndexCurrent(*reachableNodeIndex_))
        buildReachableNodeIndex();

    const ReachableNodeIndex::Entry* entry = reachableNodeIndex_->find(targetNode);
    return entry ? entry->nodeRef : AstNodeRef::invalid();
}

bool Ast::collectReachableNodePathFromIndex(const ReachableNodeIndex& index, SmallVector<AstNodeRef>& outPath, const AstNodeRef targetRef) const
{
    outPath.clear();
    if (!hasNode(targetRef))
        return false;

    AstNodeRef nodeRef = targetRef;
    while (nodeRef.isValid())
    {
        outPath.push_back(nodeRef);
        const ReachableNodeIndex::Entry* entry = index.find(&node(nodeRef));
        if (!entry || entry->nodeRef != nodeRef)
        {
            outPath.clear();
            return false;
        }
        nodeRef = entry->parentRef;
    }

    std::ranges::reverse(outPath);
    return !outPath.empty() && outPath.front() == root_;
}

bool Ast::collectReachableNodePath(SmallVector<AstNodeRef>& outPath, const AstNodeRef targetRef) const
{
    if (targetRef.isInvalid() || root_.isInvalid())
    {
        outPath.clear();
        return false;
    }

    {
        std::shared_lock lock(reachableNodeIndexMutex_);
        if (reachableNodeIndex_ && isReachableNodeIndexCurrent(*reachableNodeIndex_))
            return collectReachableNodePathFromIndex(*reachableNodeIndex_, outPath, targetRef);
    }

    std::unique_lock lock(reachableNodeIndexMutex_);
    if (!reachableNodeIndex_ || !isReachableNodeIndexCurrent(*reachableNodeIndex_))
        buildReachableNodeIndex();
    return collectReachableNodePathFromIndex(*reachableNodeIndex_, outPath, targetRef);
}

void Ast::visit(const Ast& ast, AstNodeRef root, const Visitor& f)
{
    SmallVector<AstNodeRef> stack;
    stack.push_back(root);

    while (!stack.empty())
    {
        const AstNodeRef nodeRef = stack.back();
        stack.pop_back();
        if (!nodeRef.isValid())
            continue;

        const AstNode&    node = ast.node(nodeRef);
        const VisitResult res  = f(nodeRef, node);
        if (res == VisitResult::Stop)
            break;
        if (res == VisitResult::Skip)
            continue;

        // Collectors append without touching pending siblings. Reverse only the new
        // suffix so the LIFO walk still visits children in their declaration order.
        const size_t firstChild = stack.size();
        nodeIdInfos(node.id()).collectChildren(stack, ast, node);
        std::reverse(stack.begin() + firstChild, stack.end());
    }
}

SWC_END_NAMESPACE();
