#include "pch.h"
#include "Compiler/Parser/Ast/Ast.h"

SWC_BEGIN_NAMESPACE();

AstNode& Ast::node(AstNodeRef nodeRef)
{
    SWC_ASSERT(nodeRef.isValid());
    const uint32_t g = nodeRef.get();
    return *SWC_CHECK_NOT_NULL(nodePtr(g));
}

const AstNode& Ast::node(AstNodeRef nodeRef) const
{
    SWC_ASSERT(nodeRef.isValid());
    const uint32_t g = nodeRef.get();
    return *SWC_CHECK_NOT_NULL(nodePtr(g));
}

void Ast::captureParsedNodeBoundary()
{
    std::fill_n(parsedNodeBoundaryByShard_, SHARD_COUNT, 0u);
    if (root_.isInvalid())
    {
        hasParsedNodeBoundary_ = true;
        return;
    }

    visit(*this, root_, [this](AstNodeRef nodeRef, const AstNode&) {
        const uint32_t globalRef = nodeRef.get();
        const uint32_t shard     = refShard(globalRef);
        const uint32_t local     = refLocal(globalRef);
        SWC_ASSERT(shard < SHARD_COUNT);
        parsedNodeBoundaryByShard_[shard] = std::max(parsedNodeBoundaryByShard_[shard], local + 1);
        return VisitResult::Continue;
    });

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

void Ast::appendNodes(SmallVector<AstNodeRef>& out, SpanRef spanRef) const
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
        out.append(static_cast<const AstNodeRef*>(c.ptr), c.count);
    }
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
    SmallVector<AstNodeRef> res;
    appendNodes(res, spanRef);
    SWC_ASSERT(res.size() == 1);
    return res.front();
}

void Ast::appendTokens(SmallVector<TokenRef>& out, SpanRef spanRef) const
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
        out.append(static_cast<const TokenRef*>(c.ptr), c.count);
    }
}

AstNodeRef Ast::findNodeRef(const AstNode* node) const
{
    for (uint32_t i = 0; i < SHARD_COUNT; i++)
    {
        const Ref local = shards_[i].store.findRef(node);
        if (local != std::numeric_limits<Ref>::max())
            return AstNodeRef{packRef(i, local)};
    }

    SWC_ASSERT(false);
    return AstNodeRef::invalid();
}

void Ast::visit(const Ast& ast, AstNodeRef root, const Visitor& f)
{
    SmallVector<AstNodeRef> children;
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

        children.clear();
        nodeIdInfos(node.id()).collectChildren(children, ast, node);
        for (const AstNodeRef it : std::ranges::reverse_view(children))
            stack.push_back(it);
    }
}

AstNode* Ast::nodePtr(uint32_t globalRef)
{
    const uint32_t s = refShard(globalRef);
    const uint32_t l = refLocal(globalRef);
    return shards_[s].store.ptr<AstNode>(l);
}

const AstNode* Ast::nodePtr(uint32_t globalRef) const
{
    const uint32_t s = refShard(globalRef);
    const uint32_t l = refLocal(globalRef);
    return shards_[s].store.ptr<AstNode>(l);
}

SWC_END_NAMESPACE();
