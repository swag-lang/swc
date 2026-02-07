#include "pch.h"
#include "Compiler/Parser/Ast/Ast.h"

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

void Ast::appendNodes(SmallVector<AstNodeRef>& out, SpanRef spanRef) const
{
    if (spanRef.isInvalid())
        return;

    const uint32_t g = spanRef.get();
    const uint32_t s = refShard(g);
    const uint32_t l = refLocal(g);

    std::shared_lock      lk(shards_[s].mutex);
    const Store::SpanView view = shards_[s].store.span<AstNodeRef>(l);
    for (Store::SpanView::ChunkIterator it = view.chunksBegin(); it != view.chunksEnd(); ++it)
    {
        const Store::SpanView::Chunk& c = *it;
        out.append(static_cast<const AstNodeRef*>(c.ptr), c.count);
    }
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

    std::shared_lock      lk(shards_[s].mutex);
    const Store::SpanView view = shards_[s].store.span<AstNodeRef>(l);
    for (Store::SpanView::ChunkIterator it = view.chunksBegin(); it != view.chunksEnd(); ++it)
    {
        const Store::SpanView::Chunk& c = *it;
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

void Ast::visit(const Ast& ast, AstNodeRef root, const Visitor& f)
{
    SmallVector<AstNodeRef> children;
    SmallVector<AstNodeRef> stack;
    stack.push_back(root);

    while (!stack.empty())
    {
        const auto nodeRef = stack.back();
        stack.pop_back();
        if (!nodeRef.isValid())
            continue;

        const auto& node = ast.node(nodeRef);
        const auto  res  = f(nodeRef, node);
        if (res == VisitResult::Stop)
            break;
        if (res == VisitResult::Skip)
            continue;

        children.clear();
        nodeIdInfos(node.id()).collectChildren(children, ast, node);
        for (auto& it : std::ranges::reverse_view(children))
            stack.push_back(it);
    }
}

SWC_END_NAMESPACE();
