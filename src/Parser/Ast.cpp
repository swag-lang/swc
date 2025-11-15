#include "pch.h"
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE()

void Ast::nodes(SmallVector<AstNodeRef>& out, SpanRef spanRef) const
{
    out.clear();
    if (spanRef.isInvalid())
        return;

    const RefStore<>::SpanView<AstNodeRef> view{&store_, spanRef.get()};
    for (auto it = view.chunks_begin(); it != view.chunks_end(); ++it)
    {
    }
}

SWC_END_NAMESPACE()
