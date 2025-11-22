#include "pch.h"
#include "Sema/TypeManager.h"
#include "Main/Stats.h"

SWC_BEGIN_NAMESPACE()

void TypeManager::setup(TaskContext&)
{
    typeBool_ = registerType(TypeInfo::makeBool());
}

TypeInfoRef TypeManager::registerType(const TypeInfo& typeInfo)
{
    {
        std::shared_lock lk(mutexAdd_);
        const auto       it = map_.find(typeInfo);
        if (it != map_.end())
            return it->second;
    }

    std::unique_lock lk(mutexAdd_);
    const auto [it, inserted] = map_.try_emplace(typeInfo, TypeInfoRef{});
    if (!inserted)
        return it->second;

#if SWC_HAS_STATS
    Stats::get().numTypes.fetch_add(1);
    Stats::get().memTypes.fetch_add(sizeof(TypeInfo), std::memory_order_relaxed);
#endif

    const TypeInfoRef ref{store_.push_back(typeInfo)};
    it->second = ref;
    return ref;
}

const TypeInfo& TypeManager::get(TypeInfoRef typeInfoRef) const
{
    std::shared_lock lk(mutexAdd_);
    SWC_ASSERT(typeInfoRef.isValid());
    return *store_.ptr<TypeInfo>(typeInfoRef.get());
}

Utf8 TypeManager::toString(const TypeInfo& typeInfo, ToNameKind kind)
{
    switch (typeInfo.kind)
    {
        case TypeInfoKind::Bool:
            return "bool";

        case TypeInfoKind::Int:
        {
            Utf8 out;
            out += typeInfo.int_.isSigned ? "int" : "uint";
            out += std::to_string(typeInfo.int_.bits);
            return out;
        }

            // Always handle unknown cases for debugging
        default:
            return "<invalid-type>";
    }
}

std::string_view TypeManager::toName(TypeInfoRef typeInfoRef, ToNameKind kind) const
{
    SWC_ASSERT(typeInfoRef.isValid());
    return toName(get(typeInfoRef), kind);
}

std::string_view TypeManager::toName(const TypeInfo& typeInfo, ToNameKind kind) const
{
    const auto idx = static_cast<int>(kind);

    {
        std::shared_lock lk(mutexName_[idx]);
        const auto       it = mapName_[idx].find(typeInfo);
        if (it != mapName_[idx].end())
            return it->second;
    }

    std::unique_lock lk(mutexName_[idx]);
    const auto [it, inserted] = mapName_[idx].try_emplace(typeInfo, Utf8{});
    if (!inserted)
        return it->second;

    it->second = toString(typeInfo, kind);
    return it->second;
}

SWC_END_NAMESPACE()
