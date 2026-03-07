#include "pch.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Core/Sema.h"

SWC_BEGIN_NAMESPACE();

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
        SWC_RESULT_VERIFY(processTypeInfo(sema, result, storage, typeRef, ownerNodeRef, cache));
    }

    {
        // Now that we are done, store back reference
        const std::scoped_lock lk2(ptrToTypeMutex_);
        ptrToType_[result.span.data()] = typeRef;
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
