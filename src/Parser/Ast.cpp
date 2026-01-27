#include "pch.h"
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE();

AstNode& Ast::node(AstNodeRef nodeRef)
{
    SWC_ASSERT(nodeRef.isValid());
    const uint32_t g = nodeRef.get();
    return *nodePtr(g);
}

const AstNode& Ast::node(AstNodeRef nodeRef) const
{
    SWC_ASSERT(nodeRef.isValid());
    const uint32_t g = nodeRef.get();
    return *nodePtr(g);
}

void Ast::nodes(SmallVector<AstNodeRef>& out, SpanRef spanRef) const
{
    if (spanRef.isInvalid())
        return;

    const uint32_t g = spanRef.get();
    const uint32_t s = refShard(g);
    const uint32_t l = refLocal(g);

    std::shared_lock lk(shards_[s].mutex);
    const Store::SpanView view = shards_[s].store.span<AstNodeRef>(l);
    for (Store::SpanView::chunk_iterator it = view.chunks_begin(); it != view.chunks_end(); ++it)
    {
        const Store::SpanView::chunk& c = *it;
        out.append(static_cast<const AstNodeRef*>(c.ptr), c.count);
    }
}

AstNodeRef Ast::oneNode(SpanRef spanRef) const
{
    SmallVector<AstNodeRef> res;
    nodes(res, spanRef);
    SWC_ASSERT(res.size() == 1);
    return res.front();
}

void Ast::tokens(SmallVector<TokenRef>& out, SpanRef spanRef) const
{
    if (spanRef.isInvalid())
        return;

    const uint32_t g = spanRef.get();
    const uint32_t s = refShard(g);
    const uint32_t l = refLocal(g);

    std::shared_lock lk(shards_[s].mutex);
    const Store::SpanView view = shards_[s].store.span<AstNodeRef>(l);
    for (Store::SpanView::chunk_iterator it = view.chunks_begin(); it != view.chunks_end(); ++it)
    {
        const Store::SpanView::chunk& c = *it;
        out.append(static_cast<const TokenRef*>(c.ptr), c.count);
    }
}

AstNodeRef Ast::findNodeRef(const AstNode* node) const
{
    for (uint32_t i = 0; i < SHARD_COUNT; i++)
    {
        std::shared_lock lk(shards_[i].mutex);
        const Ref        local = shards_[i].store.findRef(node);
        if (local != std::numeric_limits<Ref>::max())
            return AstNodeRef{packRef(i, local)};
    }

    SWC_ASSERT(false);
    return AstNodeRef::invalid();
}

SWC_END_NAMESPACE();
