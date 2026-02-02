#include "pch.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Lexer/Token.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Math/Hash.h"

SWC_BEGIN_NAMESPACE();

void IdentifierManager::setup(TaskContext&)
{
    predefined_.fill(IdentifierRef::invalid());

    struct PredefinedEntry
    {
        PredefinedName   name;
        std::string_view str;
    };

    static constexpr PredefinedEntry PREDEFINED_NAMES[] = {
        {.name = PredefinedName::Swag, .str = "Swag"},
        {.name = PredefinedName::AttributeUsage, .str = "AttributeUsage"},

        {.name = PredefinedName::AttrMulti, .str = "AttrMulti"},
        {.name = PredefinedName::ConstExpr, .str = "ConstExpr"},
        {.name = PredefinedName::PrintBc, .str = "PrintBc"},
        {.name = PredefinedName::PrintBcGen, .str = "PrintBcGen"},
        {.name = PredefinedName::PrintAsm, .str = "PrintAsm"},
        {.name = PredefinedName::Compiler, .str = "Compiler"},
        {.name = PredefinedName::Inline, .str = "Inline"},
        {.name = PredefinedName::NoInline, .str = "NoInline"},
        {.name = PredefinedName::PlaceHolder, .str = "PlaceHolder"},
        {.name = PredefinedName::NoPrint, .str = "NoPrint"},
        {.name = PredefinedName::Macro, .str = "Macro"},
        {.name = PredefinedName::Mixin, .str = "Mixin"},
        {.name = PredefinedName::Implicit, .str = "Implicit"},
        {.name = PredefinedName::EnumFlags, .str = "EnumFlags"},
        {.name = PredefinedName::EnumIndex, .str = "EnumIndex"},
        {.name = PredefinedName::NoDuplicate, .str = "NoDuplicate"},
        {.name = PredefinedName::Complete, .str = "Complete"},
        {.name = PredefinedName::Overload, .str = "Overload"},
        {.name = PredefinedName::CalleeReturn, .str = "CalleeReturn"},
        {.name = PredefinedName::Discardable, .str = "Discardable"},
        {.name = PredefinedName::NotGeneric, .str = "NotGeneric"},
        {.name = PredefinedName::Tls, .str = "Tls"},
        {.name = PredefinedName::NoCopy, .str = "NoCopy"},
        {.name = PredefinedName::Opaque, .str = "Opaque"},
        {.name = PredefinedName::Incomplete, .str = "Incomplete"},
        {.name = PredefinedName::NoDoc, .str = "NoDoc"},
        {.name = PredefinedName::Strict, .str = "Strict"},
        {.name = PredefinedName::Global, .str = "Global"},
        {.name = PredefinedName::Me, .str = "me"},

        {.name = PredefinedName::TargetOs, .str = "TargetOs"},

        {.name = PredefinedName::TypeInfo, .str = "TypeInfo"},
        {.name = PredefinedName::TypeInfoNative, .str = "TypeInfoNative"},
        {.name = PredefinedName::TypeInfoPointer, .str = "TypeInfoPointer"},
        {.name = PredefinedName::TypeInfoStruct, .str = "TypeInfoStruct"},
        {.name = PredefinedName::TypeInfoFunc, .str = "TypeInfoFunc"},
        {.name = PredefinedName::TypeInfoEnum, .str = "TypeInfoEnum"},
        {.name = PredefinedName::TypeInfoArray, .str = "TypeInfoArray"},
        {.name = PredefinedName::TypeInfoSlice, .str = "TypeInfoSlice"},
        {.name = PredefinedName::TypeInfoAlias, .str = "TypeInfoAlias"},
        {.name = PredefinedName::TypeInfoVariadic, .str = "TypeInfoVariadic"},
        {.name = PredefinedName::TypeInfoGeneric, .str = "TypeInfoGeneric"},
        {.name = PredefinedName::TypeInfoNamespace, .str = "TypeInfoNamespace"},
        {.name = PredefinedName::TypeInfoCodeBlock, .str = "TypeInfoCodeBlock"},
        {.name = PredefinedName::TypeInfoKind, .str = "TypeInfoKind"},
        {.name = PredefinedName::TypeInfoNativeKind, .str = "TypeInfoNativeKind"},
        {.name = PredefinedName::TypeInfoFlags, .str = "TypeInfoFlags"},

        {.name = PredefinedName::TypeValue, .str = "TypeValue"},
        {.name = PredefinedName::TypeValueFlags, .str = "TypeValueFlags"},
        {.name = PredefinedName::Attribute, .str = "Attribute"},
        {.name = PredefinedName::AttributeParam, .str = "AttributeParam"},
        {.name = PredefinedName::Interface, .str = "Interface"},
        {.name = PredefinedName::SourceCodeLocation, .str = "SourceCodeLocation"},
        {.name = PredefinedName::ErrorValue, .str = "ErrorValue"},
        {.name = PredefinedName::ScratchAllocator, .str = "ScratchAllocator"},
        {.name = PredefinedName::Context, .str = "Context"},
        {.name = PredefinedName::ContextFlags, .str = "ContextFlags"},
        {.name = PredefinedName::Module, .str = "Module"},
        {.name = PredefinedName::ProcessInfos, .str = "ProcessInfos"},
        {.name = PredefinedName::Gvtd, .str = "Gvtd"},
    };

    for (const auto& it : PREDEFINED_NAMES)
        predefined_[static_cast<size_t>(it.name)] = addIdentifier(it.str);
}

IdentifierRef IdentifierManager::addIdentifier(const TaskContext& ctx, SourceLocation loc)
{
    return addIdentifier(ctx, loc.srcViewRef, loc.tokRef);
}

IdentifierRef IdentifierManager::addIdentifier(const TaskContext& ctx, SourceViewRef srcViewRef, TokenRef tokRef)
{
    const SourceView&      srcView = ctx.compiler().srcView(srcViewRef);
    const Token&           tok     = srcView.token(tokRef);
    const std::string_view name    = tok.string(srcView);

    if (tok.id == TokenId::Identifier)
    {
        const uint32_t crc = tok.crc(srcView);
        return addIdentifier(name, crc);
    }

    return addIdentifier(name);
}

IdentifierRef IdentifierManager::addIdentifier(std::string_view name)
{
    return addIdentifier(name, Math::hash(name));
}

IdentifierRef IdentifierManager::addIdentifier(std::string_view name, uint32_t hash)
{
    const uint32_t shardIndex = hash & (SHARD_COUNT - 1);
    auto&          shard      = shards_[shardIndex];

    {
        std::shared_lock lk(shard.mutex);
        if (const auto it = shard.map.find(name, hash))
            return *it;
    }

    std::unique_lock lk(shard.mutex);
    const auto [it, inserted] = shard.map.try_emplace(name, hash, IdentifierRef{});
    if (!inserted)
        return *it;

#if SWC_HAS_STATS
    Stats::get().numIdentifiers.fetch_add(1);
#endif

    const uint32_t localIndex = shard.store.push_back(Identifier{name});
    SWC_ASSERT(localIndex < LOCAL_MASK);

    auto result = IdentifierRef{(shardIndex << LOCAL_BITS) | localIndex};
#if SWC_HAS_REF_DEBUG_INFO
    result.dbgPtr = &getNoLock(result);
#endif

    *it = result;
    return result;
}

const Identifier& IdentifierManager::getNoLock(IdentifierRef idRef) const
{
    SWC_ASSERT(idRef.isValid());
    const auto shardIndex = idRef.get() >> LOCAL_BITS;
    const auto localIndex = idRef.get() & LOCAL_MASK;
    return *shards_[shardIndex].store.ptr<Identifier>(localIndex);
}

const Identifier& IdentifierManager::get(IdentifierRef idRef) const
{
    const auto       shardIndex = idRef.get() >> LOCAL_BITS;
    std::shared_lock lk(shards_[shardIndex].mutex);
    return getNoLock(idRef);
}

SWC_END_NAMESPACE();
