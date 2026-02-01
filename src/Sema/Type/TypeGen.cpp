#include "pch.h"
#include "Sema/Type/TypeGen.h"
#include "Sema/Core/Sema.h"
#include "Sema/Type/TypeGen.Internal.h"

SWC_BEGIN_NAMESPACE();

TypeGen::TypeGenCache& TypeGen::cacheFor(const DataSegment& storage)
{
    std::scoped_lock lk(cachesMutex_);
    auto&            ptr = caches_[&storage];
    if (!ptr)
        ptr = std::make_unique<TypeGenCache>();
    return *ptr;
}

Result TypeGen::makeTypeInfo(Sema& sema, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGenResult& result)
{
    auto&            cache = cacheFor(storage);
    std::scoped_lock lk(cache.mutex);

    // Each call progresses as much as possible without relying on recursion.
    // It returns Result::Continue only when the requested type AND all its dependencies are fully done.
    return TypeGenInternal::processTypeInfo(sema, storage, typeRef, ownerNodeRef, result, cache);
}

SWC_END_NAMESPACE();
