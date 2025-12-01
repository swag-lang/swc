#include "pch.h"
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE()

void Ast::nodes(SmallVector<AstNodeRef>& out, SpanRef spanRef) const
{
    if (spanRef.isInvalid())
        return;

    const Store::SpanView view = store_.span<AstNodeRef>(spanRef.get());
    for (Store::SpanView::chunk_iterator it = view.chunks_begin(); it != view.chunks_end(); ++it)
    {
        const Store::SpanView::chunk& c = *it;
        out.append(static_cast<const AstNodeRef*>(c.ptr), c.count);
    }
}

SWC_END_NAMESPACE()
