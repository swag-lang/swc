#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"

SWC_BEGIN_NAMESPACE();

SourceCodeRange Symbol::codeRange(TaskContext& ctx) const noexcept
{
    const SourceView& srcView = ctx.compiler().srcView(srcViewRef());
    const Token&      tok     = srcView.token(tokRef_);
    return tok.codeRange(ctx, srcView);
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
    if (flags_.has(SymbolFlagsE::Typed))
        return;
    flags_.add(SymbolFlagsE::Typed);
    ctx.compiler().notifyAlive();
}

void Symbol::setSemaCompleted(TaskContext& ctx)
{
    if (flags_.has(SymbolFlagsE::SemaCompleted))
        return;
    flags_.add(SymbolFlagsE::SemaCompleted);
    ctx.compiler().notifyAlive();
}

void Symbol::setCodeGenCompleted(TaskContext& ctx)
{
    if (flags_.has(SymbolFlagsE::CodeGenCompleted))
        return;
    flags_.add(SymbolFlagsE::CodeGenCompleted);
    ctx.compiler().notifyAlive();
}

void Symbol::setDeclared(TaskContext& ctx)
{
    if (flags_.has(SymbolFlagsE::Declared))
        return;
    flags_.add(SymbolFlagsE::Declared);
    ctx.compiler().notifyAlive();
}

void Symbol::setIgnored(TaskContext& ctx) noexcept
{
    if (flags_.has(SymbolFlagsE::Ignored))
        return;
    flags_.add(SymbolFlagsE::Ignored);
    ctx.compiler().notifyAlive();
}

void Symbol::registerCompilerIf(Sema& sema)
{
    if (auto* compilerIf = sema.frame().currentCompilerIf())
        compilerIf->addSymbolToChain(this);
}

void Symbol::registerAttributes(Sema& sema)
{
    setAttributes(sema.frame().currentAttributes());
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

bool Symbol::inSwagNamespace(const TaskContext& ctx) const noexcept
{
    const SymbolMap* const map = ownerSymMap();
    if (!map)
        return false;
    return map->isNamespace() && map->idRef() == ctx.idMgr().predefined(IdentifierManager::PredefinedName::Swag);
}

bool Symbol::deepCompare(const Symbol* other) const noexcept
{
    if (this == other)
        return true;
    if (kind_ != other->kind_)
        return false;
    if (isFunction())
        return cast<SymbolFunction>().deepCompare(other->cast<SymbolFunction>());
    if (isAttribute())
        return cast<SymbolAttribute>().deepCompare(other->cast<SymbolAttribute>());
    return true;
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
    SmallVector8<const Symbol*> scopeChain;

    // Add the symbol itself
    scopeChain.push_back(this);

    // Walk owner scopes
    const SymbolMap* map = ownerSymMap_;
    while (map)
    {
        scopeChain.push_back(map);
        map = map->ownerSymMap();
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
