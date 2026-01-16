#include "pch.h"
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE();

AstNode& Ast::node(AstNodeRef nodeRef)
{
    SWC_ASSERT(nodeRef.isValid());
    const uint32_t g = nodeRef.get();
    return *shards_[refShard(g)].store.ptr<AstNode>(refLocal(g));
}

const AstNode& Ast::node(AstNodeRef nodeRef) const
{
    SWC_ASSERT(nodeRef.isValid());
    const uint32_t g = nodeRef.get();
    return *shards_[refShard(g)].store.ptr<AstNode>(refLocal(g));
}

void Ast::nodes(SmallVector<AstNodeRef>& out, SpanRef spanRef) const
{
    if (spanRef.isInvalid())
        return;

    const uint32_t g = spanRef.get();
    const uint32_t s = refShard(g);
    const uint32_t l = refLocal(g);

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

    const Store::SpanView view = shards_[s].store.span<AstNodeRef>(l);
    for (Store::SpanView::chunk_iterator it = view.chunks_begin(); it != view.chunks_end(); ++it)
    {
        const Store::SpanView::chunk& c = *it;
        out.append(static_cast<const TokenRef*>(c.ptr), c.count);
    }
}

SWC_END_NAMESPACE();
