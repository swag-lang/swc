#include "pch.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Lexer/SourceView.h"
#include "Compiler/Lexer/Token.h"
#include "Main/CompilerInstance.h"
#include "Main/Stats.h"
#include "Main/TaskContext.h"
#include "Support/Core/ByteSpan.h"
#include "Support/Math/Hash.h"

SWC_BEGIN_NAMESPACE();

void IdentifierManager::setup(const TaskContext& ctx)
{
    SWC_UNUSED(ctx);
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
        {.name = PredefinedName::PrintMicro, .str = "PrintMicro"},
        {.name = PredefinedName::Compiler, .str = "Compiler"},
        {.name = PredefinedName::Inline, .str = "Inline"},
        {.name = PredefinedName::NoInline, .str = "NoInline"},
        {.name = PredefinedName::Optimize, .str = "Optimize"},
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
        {.name = PredefinedName::Foreign, .str = "Foreign"},
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
        {.name = PredefinedName::OpBinary, .str = "opBinary"},
        {.name = PredefinedName::OpUnary, .str = "opUnary"},
        {.name = PredefinedName::OpAssign, .str = "opAssign"},
        {.name = PredefinedName::OpIndexAssign, .str = "opIndexAssign"},
        {.name = PredefinedName::OpCast, .str = "opCast"},
        {.name = PredefinedName::OpEquals, .str = "opEquals"},
        {.name = PredefinedName::OpCmp, .str = "opCmp"},
        {.name = PredefinedName::OpPostCopy, .str = "opPostCopy"},
        {.name = PredefinedName::OpPostMove, .str = "opPostMove"},
        {.name = PredefinedName::OpDrop, .str = "opDrop"},
        {.name = PredefinedName::OpCount, .str = "opCount"},
        {.name = PredefinedName::OpData, .str = "opData"},
        {.name = PredefinedName::OpAffect, .str = "opAffect"},
        {.name = PredefinedName::OpAffectLiteral, .str = "opAffectLiteral"},
        {.name = PredefinedName::OpSlice, .str = "opSlice"},
        {.name = PredefinedName::OpIndex, .str = "opIndex"},
        {.name = PredefinedName::OpIndexAffect, .str = "opIndexAffect"},
        {.name = PredefinedName::OpVisit, .str = "opVisit"},
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
        {.name = PredefinedName::BuildCfg, .str = "BuildCfg"},
    };

    for (const auto& it : PREDEFINED_NAMES)
        predefined_[static_cast<size_t>(it.name)] = addIdentifier(it.str);
}

IdentifierRef IdentifierManager::addIdentifier(const TaskContext& ctx, const SourceCodeRef& codeRef)
{
    const SourceView&      srcView = ctx.compiler().srcView(codeRef.srcViewRef);
    const Token&           tok     = srcView.token(codeRef.tokRef);
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
    return addIdentifierInternal(name, Math::hash(name), false);
}

IdentifierRef IdentifierManager::addIdentifier(std::string_view name, uint32_t hash)
{
    return addIdentifierInternal(name, hash, false);
}

IdentifierRef IdentifierManager::addIdentifierOwned(std::string_view name)
{
    return addIdentifierInternal(name, Math::hash(name), true);
}

IdentifierRef IdentifierManager::addIdentifierOwned(std::string_view name, uint32_t hash)
{
    return addIdentifierInternal(name, hash, true);
}

IdentifierRef IdentifierManager::addIdentifierInternal(std::string_view name, uint32_t hash, bool copyName)
{
    const uint32_t shardIndex = hash & (SHARD_COUNT - 1);
    SWC_ASSERT(shardIndex < SHARD_COUNT);
    auto& shard = shards_[shardIndex];

    {
        std::shared_lock lk(shard.mutex);
        if (const auto it = shard.map.find(name, hash))
            return *it;
    }

    std::unique_lock lk(shard.mutex);
    if (const auto it = shard.map.find(name, hash))
        return *it;

    std::string_view storedName = name;
    if (copyName && !name.empty())
    {
        const auto [span, _] = shard.stringStore.pushCopySpan(asByteSpan(name));
        storedName           = asStringView(span);
    }

    const auto [it, inserted] = shard.map.try_emplace(storedName, hash, IdentifierRef{});
    if (!inserted)
        return *it;

#if SWC_HAS_STATS
    Stats::get().numIdentifiers.fetch_add(1);
#endif

    const uint32_t localIndex = shard.store.pushBack(Identifier{storedName});
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
    SWC_ASSERT(shardIndex < SHARD_COUNT);
    const auto localIndex = idRef.get() & LOCAL_MASK;
    return *SWC_CHECK_NOT_NULL(shards_[shardIndex].store.ptr<Identifier>(localIndex));
}

const Identifier& IdentifierManager::get(IdentifierRef idRef) const
{
    const auto shardIndex = idRef.get() >> LOCAL_BITS;
    SWC_ASSERT(shardIndex < SHARD_COUNT);
    std::shared_lock lk(shards_[shardIndex].mutex);
    return getNoLock(idRef);
}

SWC_END_NAMESPACE();
