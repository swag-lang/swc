#include "pch.h"
#include "Sema/Symbol/Symbol.h"
#include "Lexer/SourceView.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE()

Symbol::Symbol(const TaskContext& ctx, SymbolKind kind, SourceViewRef srcViewRef, TokenRef tokRef) :
    kind_(kind)
{
    const auto& srcView = ctx.compiler().srcView(srcViewRef);
    const auto& tok     = srcView.token(tokRef);
    name_               = tok.string(srcView, &hash_);
}

SWC_END_NAMESPACE()
