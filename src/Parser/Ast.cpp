#include "pch.h"
#include "Parser/Ast.h"

SWC_BEGIN_NAMESPACE()

void Ast::nodes(SmallVector<const AstNode*>& out, SpanRef nodes)
{
    const RefStore<>::SpanView<AstNodeRef> view{&store_, nodes.get()};
    for (auto it = view.chunks_begin(); it != view.chunks_end(); ++it)
    {
    }
}

SWC_END_NAMESPACE()
