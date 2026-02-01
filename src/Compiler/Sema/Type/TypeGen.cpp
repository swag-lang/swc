#include "pch.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Type/TypeGen.Internal.h"
#include "Support/Core/DataSegment.h"

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
    const auto res = TypeGenInternal::processTypeInfo(sema, storage, typeRef, ownerNodeRef, result, cache);
    if (res == Result::Continue)
    {
        std::scoped_lock lk2(ptrToTypeMutex_);
        ptrToType_[result.span.data()] = typeRef;
    }

    return res;
}

TypeRef TypeGen::getRealTypeRef(const void* ptr) const
{
    std::scoped_lock lk(ptrToTypeMutex_);
    const auto       it = ptrToType_.find(ptr);
    if (it != ptrToType_.end())
        return it->second;
    return TypeRef::invalid();
}

SWC_END_NAMESPACE();
