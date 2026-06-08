#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/SymbolMap.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/CompilerInstance.h"
#include "Main/TaskContext.h"
#include "Support/Math/Hash.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    const AttributeList EMPTY_ATTRIBUTES;

#if SWC_DEV_MODE
    Utf8 formatLazyFunctionMarkedSemaComplete(const TaskContext& ctx, const SymbolFunction& function)
    {
        Utf8 detail = "lazy-function-marked-sema-complete:\n";
        detail += std::format("  function={} full={} declNodeRef={} lazyRunning={} genericRoot={} genericInstance={} semaCompleted={}\n",
                              static_cast<const void*>(&function),
                              function.getFullScopedName(ctx).c_str(),
                              function.declNodeRef().isValid() ? function.declNodeRef().get() : 0,
                              function.hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBodyRunning),
                              function.isGenericRoot(),
                              function.isGenericInstance(),
                              function.isSemaCompleted());

        const SymbolStruct* owner = function.ownerStruct();
        if (owner)
        {
            detail += std::format("  owner={} full={} typeRef={} genericRoot={} genericInstance={} root={}\n",
                                  static_cast<const void*>(owner),
                                  owner->getFullScopedName(ctx).c_str(),
                                  owner->typeRef().isValid() ? owner->typeRef().get() : 0,
                                  owner->isGenericRoot(),
                                  owner->isGenericInstance(),
                                  static_cast<const void*>(owner->genericRootSym()));
        }

        return detail;
    }
#endif
}

namespace SymbolInternal
{
    bool sameGenericEvalBindings(std::span<const GenericEvalBindingKey> lhs, std::span<const SemaClone::ParamBinding> rhs)
    {
        if (lhs.size() != rhs.size())
            return false;

        for (size_t i = 0; i < lhs.size(); ++i)
        {
            if (lhs[i].idRef != rhs[i].idRef ||
                lhs[i].exprRef != rhs[i].exprRef ||
                lhs[i].typeRef != rhs[i].typeRef ||
                lhs[i].cstRef != rhs[i].cstRef)
                return false;
        }

        return true;
    }

    void copyGenericEvalBindings(std::vector<GenericEvalBindingKey>& out, std::span<const SemaClone::ParamBinding> bindings)
    {
        out.clear();
        out.reserve(bindings.size());
        for (const auto& binding : bindings)
            out.push_back({.idRef = binding.idRef, .exprRef = binding.exprRef, .typeRef = binding.typeRef, .cstRef = binding.cstRef});
    }

    AstNodeRef findGenericEvalNode(std::span<const GenericEvalEntry> entries, const NodePayload* payloadContext, const Ast& ownerAst, const AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings)
    {
        for (const auto& entry : entries)
        {
            if (entry.payloadContext != payloadContext)
                continue;
            if (entry.ownerAst != &ownerAst)
                continue;
            if (entry.sourceRef != sourceRef)
                continue;
            if (!sameGenericEvalBindings(entry.bindings, bindings))
                continue;

            return entry.evalRef;
        }

        return AstNodeRef::invalid();
    }

    void cacheGenericEvalNode(std::vector<GenericEvalEntry>& entries, const NodePayload* payloadContext, const Ast& ownerAst, const AstNodeRef sourceRef, std::span<const SemaClone::ParamBinding> bindings, const AstNodeRef evalRef)
    {
        for (auto& entry : entries)
        {
            if (entry.payloadContext != payloadContext)
                continue;
            if (entry.ownerAst != &ownerAst)
                continue;
            if (entry.sourceRef != sourceRef)
                continue;
            if (!sameGenericEvalBindings(entry.bindings, bindings))
                continue;

            entry.evalRef = evalRef;
            return;
        }

        auto& newEntry          = entries.emplace_back();
        newEntry.payloadContext = payloadContext;
        newEntry.ownerAst       = &ownerAst;
        newEntry.sourceRef      = sourceRef;
        newEntry.evalRef        = evalRef;
        copyGenericEvalBindings(newEntry.bindings, bindings);
    }
}

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
        default: return "symbol";
    }
}

bool Symbol::isAttribute() const noexcept
{
    if (!isFunction())
        return false;
    return cast<SymbolFunction>().isAttribute();
}

bool Symbol::isLetVariable() const noexcept
{
    if (!isVariable())
        return false;
    return cast<SymbolVariable>().hasExtraFlag(SymbolVariableFlagsE::Let);
}

bool Symbol::isFunctionLocalVariable() const noexcept
{
    if (!isVariable())
        return false;
    return cast<SymbolVariable>().isFunctionLocalVariable();
}

const SymbolFunction* SymbolVariable::ownerFunction() const noexcept
{
    if (!hasExtraFlag(SymbolVariableFlagsE::FunctionLocal))
        return nullptr;

    const SymbolMap* map = ownerSymMap();
    while (map)
    {
        if (map->isFunction())
            return &map->cast<SymbolFunction>();
        map = map->ownerSymMap();
    }

    return nullptr;
}

bool SymbolVariable::isUsingField() const noexcept
{
    const AstNode* fieldDecl = decl();
    if (!fieldDecl)
        return false;

    if (fieldDecl->is(AstNodeId::SingleVarDecl))
        return fieldDecl->cast<AstSingleVarDecl>().hasFlag(AstVarDeclFlagsE::Using);
    if (fieldDecl->is(AstNodeId::MultiVarDecl))
        return fieldDecl->cast<AstMultiVarDecl>().hasFlag(AstVarDeclFlagsE::Using);

    return false;
}

const SymbolStruct* SymbolVariable::usingTargetStruct(const TaskContext& ctx) const
{
    bool isPointer = false;
    return usingTargetStruct(ctx, isPointer);
}

const SymbolStruct* SymbolVariable::usingTargetStruct(const TaskContext& ctx, bool& outIsPointer) const
{
    outIsPointer = false;

    const TypeManager& typeMgr = ctx.typeMgr();
    if (!typeRef().isValid())
        return nullptr;

    const TypeRef fieldTypeRef = typeMgr.get(typeRef()).unwrapAliasEnum(ctx, typeRef());
    if (!fieldTypeRef.isValid())
        return nullptr;

    const TypeInfo& fieldType = typeMgr.get(fieldTypeRef);
    if (fieldType.isStruct())
        return &fieldType.payloadSymStruct();

    if (!fieldType.isAnyPointer())
        return nullptr;

    const TypeRef rawPointeeTypeRef = fieldType.payloadTypeRef();
    if (!rawPointeeTypeRef.isValid())
        return nullptr;

    const TypeRef pointeeTypeRef = typeMgr.get(rawPointeeTypeRef).unwrapAliasEnum(ctx, rawPointeeTypeRef);
    if (!pointeeTypeRef.isValid())
        return nullptr;

    const TypeInfo& pointeeType = typeMgr.get(pointeeTypeRef);
    if (!pointeeType.isStruct())
        return nullptr;

    outIsPointer = true;
    return &pointeeType.payloadSymStruct();
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
#if SWC_DEV_MODE
    if (const auto* function = safeCast<SymbolFunction>())
    {
        if (function->hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBody))
        {
            const Utf8 detail = formatLazyFunctionMarkedSemaComplete(ctx, *function);
            swcAssertDetail("!isFunction() || !cast<SymbolFunction>().hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBody)", __FILE__, __LINE__, detail.view());
        }
    }
#endif
    flags_.add(SymbolFlagsE::SemaCompleted);
    ctx.compiler().onSymbolSemaCompleted(ctx, *this);
    ctx.compiler().notifyAlive();
}

void Symbol::setCodeGenCompleted(TaskContext& ctx)
{
    if (flags_.has(SymbolFlagsE::CodeGenCompleted))
        return;
    flags_.add(SymbolFlagsE::CodeGenCompleted);
    ctx.compiler().notifyAlive();
}

void Symbol::setCodeGenPreSolved(TaskContext& ctx)
{
    if (flags_.has(SymbolFlagsE::CodeGenPreSolved))
        return;
    flags_.add(SymbolFlagsE::CodeGenPreSolved);
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

const AttributeList& Symbol::attributes() const
{
    if (attributes_ != nullptr)
        return *attributes_;
    return EMPTY_ATTRIBUTES;
}

AttributeList& Symbol::ensureAttributes(TaskContext& ctx)
{
    if (attributes_ == nullptr)
        attributes_ = ctx.compiler().allocate<AttributeList>();
    return *attributes_;
}

void Symbol::setAttributes(TaskContext& ctx, const AttributeList& attrs)
{
    if (attrs.empty())
    {
        attributes_ = nullptr;
        return;
    }

    if (attributes_ == nullptr)
        attributes_ = ctx.compiler().allocate<AttributeList>();

    *attributes_ = attrs;
}

void Symbol::registerCompilerIf(Sema& sema)
{
    if (SemaCompilerIf* compilerIf = sema.frame().currentCompilerIf())
        compilerIf->addSymbolToChain(this);
}

void Symbol::registerAttributes(Sema& sema)
{
    setAttributes(sema.ctx(), sema.frame().currentAttributes());
}

bool Symbol::isType() const
{
    if (isEnum() || isStruct() || isInterface())
        return true;

    if (isAlias())
    {
        const auto& symAlias = cast<SymbolAlias>();
        if (symAlias.aliasedSymbol())
            return symAlias.aliasedSymbol()->isType();
        return symAlias.typeRef().isValid();
    }

    return false;
}

bool Symbol::inSwagNamespace(const TaskContext& ctx) const noexcept
{
    const SymbolMap* map = ownerSymMap();
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

uint32_t Symbol::scopedNameHash(const TaskContext& ctx) const
{
    const uint32_t cached = scopedNameHash_.load(std::memory_order_relaxed);
    if (cached != 0)
        return cached;

    const Utf8 fullName = getFullScopedName(ctx);
    uint32_t   h        = Math::hash(fullName.view());
    if (h == 0)
        h = 1;
    scopedNameHash_.store(h, std::memory_order_relaxed);
    return h;
}

void Symbol::appendFullScopedName(const TaskContext& ctx, Utf8& out) const
{
    // Walk scopes from inner -> outer
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
