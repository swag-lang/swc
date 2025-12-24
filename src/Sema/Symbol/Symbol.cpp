#include <ranges>

#include "pch.h"

#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Sema/Symbol/IdentifierManager.h"
#include "Sema/Symbol/Symbol.h"
#include "Sema/Type/TypeManager.h"
#include "SymbolMap.h"

SWC_BEGIN_NAMESPACE()

void Symbol::setFullComplete(TaskContext& ctx)
{
    SWC_ASSERT(flags_.hasNot(SymbolFlagsE::FullComplete));
    flags_.add(SymbolFlagsE::FullComplete);
    ctx.compiler().notifySymbolFullComplete();
}

std::string_view Symbol::name(const TaskContext& ctx) const
{
    const Identifier& id = ctx.idMgr().get(idRef_);
    return id.name;
}

Utf8 Symbol::getFullScopedName(const TaskContext& ctx) const
{
    Utf8 result;
    appendFullScopedName(ctx, result);
    return result;
}

void Symbol::appendFullScopedName(const TaskContext& ctx, Utf8& out) const
{
    // Walk scopes from inner → outer
    SmallVector<const Symbol*, 8> scopeChain;

    // Add the symbol itself
    scopeChain.push_back(this);

    // Walk owner scopes
    const SymbolMap* map = ownerSymMap_;
    while (map)
    {
        if (map->is(SymbolKind::Namespace))
            break;
        scopeChain.push_back(map);
        map = map->symMap();
    }

    // Emit in reverse (outer to inner)
    for (const auto& it : std::ranges::reverse_view(scopeChain))
    {
        if (!out.empty())
            out.append(".");
        out.append(it->name(ctx));
    }
}

const TypeInfo& Symbol::typeInfo(const TaskContext& ctx) const
{
    SWC_ASSERT(typeRef_.isValid());
    return ctx.typeMgr().get(typeRef_);
}

SourceCodeLocation Symbol::loc(TaskContext& ctx) const noexcept
{
    const SourceView& srcView = ctx.compiler().srcView(srcViewRef_);
    const Token&      tok     = srcView.token(tokRef_);
    return tok.location(ctx, srcView);
}

SWC_END_NAMESPACE()
