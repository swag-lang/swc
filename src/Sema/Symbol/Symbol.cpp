#include "pch.h"

#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Sema/Core/Sema.h"
#include "Sema/Symbol/IdentifierManager.h"
#include "Sema/Symbol/Symbol.h"
#include "Sema/Symbol/SymbolMap.h"
#include "Sema/Type/TypeManager.h"
#include "Sema/Symbol/Symbol.Alias.h"

SWC_BEGIN_NAMESPACE();

SourceCodeLocation Symbol::loc(TaskContext& ctx) const noexcept
{
    const SourceView& srcView = ctx.compiler().srcView(srcViewRef());
    const Token&      tok     = srcView.token(tokRef_);
    return tok.location(ctx, srcView);
}

Utf8 Symbol::toFamily() const
{
    switch (kind_)
    {
        case SymbolKind::Namespace: return "namespace";
        case SymbolKind::Variable: return "variable";
        case SymbolKind::Constant: return "constant";
        case SymbolKind::Enum: return "enum";
        case SymbolKind::EnumValue: return "enum value";
        case SymbolKind::Attribute: return "attribute";
        default: return "symbol";
    }
}

void Symbol::setTyped(TaskContext& ctx)
{
    SWC_ASSERT(flags_.hasNot(SymbolFlagsE::Typed));
    flags_.add(SymbolFlagsE::Typed);
    ctx.compiler().notifySymbolTyped();
}

void Symbol::setCompleted(TaskContext& ctx)
{
    SWC_ASSERT(flags_.hasNot(SymbolFlagsE::Completed));
    flags_.add(SymbolFlagsE::Completed);
    ctx.compiler().notifySymbolCompleted();
}

void Symbol::setDeclared(TaskContext& ctx)
{
    SWC_ASSERT(flags_.hasNot(SymbolFlagsE::Declared));
    flags_.add(SymbolFlagsE::Declared);
    ctx.compiler().notifySymbolDeclared();
}

void Symbol::setIgnored(TaskContext& ctx) noexcept
{
    if (flags_.has(SymbolFlagsE::Ignored))
        return;
    flags_.add(SymbolFlagsE::Ignored);
    ctx.compiler().notifySymbolIgnored();
}

void Symbol::registerCompilerIf(Sema& sema)
{
    if (auto* compilerIf = sema.frame().compilerIf())
        compilerIf->addSymbol(this);
}

void Symbol::registerAttributes(Sema& sema)
{
    setAttributes(sema.frame().attributes());
}

bool Symbol::isType() const
{
    if (isEnum() || isStruct() || isInterface())
        return true;

    if (isAlias())
    {
        const SymbolAlias& symAlias = cast<SymbolAlias>();
        if (symAlias.aliasedSymbol())
            return symAlias.aliasedSymbol()->isType();
        return symAlias.typeRef().isValid();
    }

    return false;
}

bool Symbol::isSwagNamespace(const TaskContext& ctx) const noexcept
{
    return isNamespace() && idRef() == ctx.idMgr().nameSwag();
}

std::string_view Symbol::name(const TaskContext& ctx) const
{
    if (idRef_.isInvalid())
        return "";
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

SWC_END_NAMESPACE();
