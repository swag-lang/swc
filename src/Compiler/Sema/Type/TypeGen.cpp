#include "pch.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

TypeRef TypeGen::resolveArrayPointedTypeRef(TypeManager& tm, const TypeInfo& arrayType)
{
    SWC_ASSERT(arrayType.isArray());
    const auto& dims = arrayType.payloadArrayDims();
    if (dims.empty())
        return arrayType.payloadArrayElemTypeRef();

    if (dims.size() == 1)
        return arrayType.payloadArrayElemTypeRef();

    SmallVector<uint64_t> remainingDims;
    remainingDims.reserve(dims.size() - 1);
    for (size_t i = 1; i < dims.size(); ++i)
        remainingDims.push_back(dims[i]);

    return tm.addType(TypeInfo::makeArray(remainingDims.span(), arrayType.payloadArrayElemTypeRef(), arrayType.flags()));
}

TypeRef TypeGen::resolveArrayFinalTypeRef(const TypeManager& tm, const TaskContext& ctx, const TypeInfo& arrayType)
{
    SWC_ASSERT(arrayType.isArray());

    TypeRef finalTypeRef = arrayType.payloadArrayElemTypeRef();
    while (tm.get(finalTypeRef).isArray())
        finalTypeRef = tm.get(finalTypeRef).payloadArrayElemTypeRef();

    return tm.get(finalTypeRef).unwrap(ctx, finalTypeRef, TypeExpandE::Alias);
}

TypeGen::TypeGenCache& TypeGen::cacheFor(const DataSegment& storage)
{
    {
        const std::shared_lock lk(cachesMutex_);
        const auto             it = caches_.find(&storage);
        if (it != caches_.end())
            return *it->second;
    }

    const std::unique_lock lk(cachesMutex_);
    auto [it, inserted] = caches_.try_emplace(&storage);
    if (!it->second)
        it->second = std::make_unique<TypeGenCache>();

    return *it->second;
}

Result TypeGen::makeTypeInfo(Sema& sema, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGenResult& result)
{
    auto& cache = cacheFor(storage);
    std::vector<std::pair<const void*, TypeRef>> backRefsToPublish;

    // Each call progresses as much as possible without relying on recursion.
    // It returns Result::Continue only when the requested type AND all its dependencies are fully done.
    {
        const std::scoped_lock lk(cache.mutex);
        SWC_RESULT(processTypeInfo(sema, result, storage, typeRef, ownerNodeRef, cache));

        if (!cache.pendingBackRefs.empty())
        {
            backRefsToPublish.reserve(cache.pendingBackRefs.size());
            for (const TypeRef cachedTypeRef : cache.pendingBackRefs)
            {
                auto it = cache.entries.find(cachedTypeRef);
                SWC_ASSERT(it != cache.entries.end());
                if (it == cache.entries.end())
                    continue;

                auto& entry = it->second;
                if (entry.state != TypeGenCache::State::Done || entry.backRefPublished)
                    continue;

                const auto* ptr        = storage.ptr<std::byte>(entry.offset);
                backRefsToPublish.emplace_back(ptr, cachedTypeRef);
                entry.backRefPublished = true;
            }

            cache.pendingBackRefs.clear();
        }
    }

    if (!backRefsToPublish.empty())
    {
        const std::unique_lock lk(ptrToTypeMutex_);
        for (const auto& [ptr, cachedTypeRef] : backRefsToPublish)
            ptrToType_[ptr] = cachedTypeRef;
    }

    return Result::Continue;
}

TypeRef TypeGen::getBackTypeRef(const void* ptr) const
{
    const std::shared_lock lk(ptrToTypeMutex_);
    const auto             it = ptrToType_.find(ptr);
    if (it != ptrToType_.end())
        return it->second;
    return TypeRef::invalid();
}

SWC_END_NAMESPACE();
