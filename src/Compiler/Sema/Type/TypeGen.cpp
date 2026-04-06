#include "pch.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Core/Sema.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    template<typename T, size_t InlineCapacity>
    size_t smallVectorStorageReserved(const SmallVector<T, InlineCapacity>& values)
    {
        if (values.isInline())
            return 0;
        return values.capacity() * sizeof(T);
    }

    template<typename K, typename V, typename H, typename E, typename A>
    size_t unorderedMapStorageReserved(const std::unordered_map<K, V, H, E, A>& map)
    {
        return map.bucket_count() * sizeof(void*) +
               map.size() * (sizeof(std::pair<const K, V>) + sizeof(void*));
    }

    size_t typeGenEntryStorageReserved(const TypeGen::TypeGenCache::Entry& entry)
    {
        return smallVectorStorageReserved(entry.deps) +
               smallVectorStorageReserved(entry.structFieldTypes) +
               smallVectorStorageReserved(entry.usingFieldTypes) +
               smallVectorStorageReserved(entry.funcParamTypes);
    }
}

TypeGen::TypeGenCache& TypeGen::cacheFor(const DataSegment& storage)
{
    std::scoped_lock lk(cachesMutex_);

    auto [it, inserted] = caches_.try_emplace(&storage);
    if (!it->second)
        it->second = std::make_unique<TypeGenCache>();

    return *it->second;
}

Result TypeGen::makeTypeInfo(Sema& sema, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGenResult& result)
{
    auto& cache = cacheFor(storage);

    // Each call progresses as much as possible without relying on recursion.
    // It returns Result::Continue only when the requested type AND all its dependencies are fully done.
    {
        const std::scoped_lock lk(cache.mutex);
        SWC_RESULT(processTypeInfo(sema, result, storage, typeRef, ownerNodeRef, cache));
    }

    {
        // Register every completed payload in this cache so nested typeinfos can be
        // resolved back to their semantic TypeRef as well.
        const std::scoped_lock lk2(ptrToTypeMutex_);
        for (const auto& [cachedTypeRef, entry] : cache.entries)
        {
            if (entry.state != TypeGenCache::State::Done)
                continue;

            ptrToType_[storage.ptr<std::byte>(entry.offset)] = cachedTypeRef;
        }
    }

    return Result::Continue;
}

TypeRef TypeGen::getBackTypeRef(const void* ptr) const
{
    const std::scoped_lock lk(ptrToTypeMutex_);
    const auto             it = ptrToType_.find(ptr);
    if (it != ptrToType_.end())
        return it->second;
    return TypeRef::invalid();
}

SWC_END_NAMESPACE();
