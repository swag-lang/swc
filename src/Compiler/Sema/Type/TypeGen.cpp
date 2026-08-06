#include "pch.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Alias.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Main/Global.h"
#include "Main/TaskContext.h"
#include "Support/Report/Assert.h"
#include "Support/Thread/JobManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool canReflectTypeRef(TaskContext& ctx, TypeRef typeRef, std::unordered_set<TypeRef>& visiting);

    bool canReflectFunctionSignature(TaskContext& ctx, const SymbolFunction& symFunc, std::unordered_set<TypeRef>& visiting)
    {
        if (!symFunc.returnTypeRef().isValid() || !canReflectTypeRef(ctx, symFunc.returnTypeRef(), visiting))
            return false;

        for (const SymbolVariable* param : symFunc.parameters())
        {
            if (!param || !param->typeRef().isValid() || !canReflectTypeRef(ctx, param->typeRef(), visiting))
                return false;
        }

        return true;
    }

    bool canReflectTypeRef(TaskContext& ctx, TypeRef typeRef, std::unordered_set<TypeRef>& visiting)
    {
        if (!typeRef.isValid())
            return false;

        // Reflection eligibility is a graph property. A cycle already on the recursion stack
        // is acceptable: dependency collection gives every distinct TypeRef a cache entry,
        // then relocations wire the recursive edges once all payloads have offsets.
        if (!visiting.insert(typeRef).second)
            return true;

        const TypeInfo& type = ctx.typeMgr().get(typeRef);
        bool            ok   = true;

        if (type.isArray())
            ok = canReflectTypeRef(ctx, type.payloadArrayElemTypeRef(), visiting);
        else if (type.isSlice() || type.isAnyPointer() || type.isReference() || type.isMoveReference() || type.isTypeValue() || type.isTypedVariadic() || type.isCodeBlock())
            ok = canReflectTypeRef(ctx, type.payloadTypeRef(), visiting);
        else if (type.isAlias())
            ok = canReflectTypeRef(ctx, type.payloadSymAlias().underlyingTypeRef(), visiting);
        else if (type.isEnum())
            ok = canReflectTypeRef(ctx, type.payloadSymEnum().underlyingTypeRef(), visiting);
        else if (type.isAggregateStruct() || type.isAggregateArray())
        {
            for (const TypeRef fieldTypeRef : type.payloadAggregate().types)
            {
                if (!canReflectTypeRef(ctx, fieldTypeRef, visiting))
                {
                    ok = false;
                    break;
                }
            }
        }
        else if (type.isFunction())
            ok = canReflectFunctionSignature(ctx, type.payloadSymFunction(), visiting);

        visiting.erase(typeRef);
        return ok;
    }

    bool tryGetCompletedTypeInfoResult(TaskContext& ctx, DataSegment& storage, const TypeGen::TypeGenCache& cache, const TypeRef typeRef, TypeGen::TypeGenResult& result)
    {
        const auto it = cache.entries.find(typeRef);
        if (it == cache.entries.end())
            return false;

        const auto& entry = it->second;
        if (entry.state != TypeGen::TypeGenCache::State::Done || !entry.backRefPublished)
            return false;

        result.offset    = entry.offset;
        result.rtTypeRef = entry.rtTypeRef;

        const TypeInfo& structType = ctx.typeMgr().get(result.rtTypeRef);
        result.span                = std::span{storage.ptr<std::byte>(result.offset), structType.sizeOf(ctx)};
        return true;
    }
}

TypeRef TypeGen::resolveArrayPointedTypeRef(TypeManager& tm, const TypeInfo& arrayType)
{
    SWC_ASSERT(arrayType.isArray());
    const auto& dims = arrayType.payloadArrayDims();
    if (dims.empty())
        return arrayType.payloadArrayElemTypeRef();

    if (dims.size() == 1)
        return arrayType.payloadArrayElemTypeRef();

    return tm.addType(arrayType.makeArrayAfterFirstDimension());
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
    // TypeInfo offsets are relative to their data segment. Keep one cache per
    // segment so JIT constants, module data and other storages never share offsets.
    {
        const std::shared_lock lk(cachesMutex_);
        const auto             it = caches_.find(&storage);
        if (it != caches_.end())
            return *it->second;
    }

    const std::scoped_lock lk(cachesMutex_);
    auto [it, inserted] = caches_.try_emplace(&storage);
    if (!it->second)
        it->second = std::make_unique<TypeGenCache>();

    return *it->second;
}

Result TypeGen::makeTypeInfo(Sema& sema, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGenResult& result, const LockMode lockMode)
{
    auto& cache = cacheFor(storage);
    {
        std::shared_lock lock(cache.mutex, std::defer_lock);
        if (lockMode == LockMode::TryLock)
        {
            if (!lock.try_lock())
                return Result::Pause;
        }
        else
        {
            lock.lock();
        }

        if (tryGetCompletedTypeInfoResult(sema.ctx(), storage, cache, typeRef, result))
            return Result::Continue;
    }

    std::unique_lock lock(cache.mutex, std::defer_lock);

    if (lockMode == LockMode::TryLock)
    {
        // Compiler-message type-info preparation is opportunistic work: if another
        // thread already owns this shard-local cache, yield instead of parking a
        // worker on the mutex so sema/JIT can keep making forward progress.
        if (!lock.try_lock())
            return Result::Pause;
    }
    else
    {
        lock.lock();
    }

    // Each call progresses as much as possible without relying on recursion.
    // It returns Result::Continue only when the requested type AND all its dependencies are fully done.
    SWC_RESULT(processTypeInfo(sema, result, storage, typeRef, ownerNodeRef, cache));

    if (!cache.pendingBackRefs.empty())
    {
        // Back references let runtime pointers be mapped to compiler TypeRefs.
        // Publish them only after the payload is Done, otherwise a concurrent lookup
        // could observe a pointer to partially-emitted metadata.
        const std::scoped_lock lk(ptrToTypeMutex_);
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
            ptrToType_[ptr]        = cachedTypeRef;
            entry.backRefPublished = true;
        }

        cache.pendingBackRefs.clear();
    }

    // The type-info (and all its dependencies) is now published. Release the shard lock
    // first, then notify every job parked on type-info generation so they re-drive at once
    // instead of relying on the bounded barrier drain. This keeps the scheduler "alive"
    // each time a type-info is produced and prevents an all-sleeping cycle on contention.
    lock.unlock();
    sema.ctx().global().jobMgr().wakeTypeInfoGeneration();

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

TypeRef TypeGen::reflectedMethodTypeRef(TaskContext& ctx, const SymbolFunction& symFunc)
{
    if (symFunc.attributes().hasRtFlag(RtAttributeFlagsE::Macro) ||
        symFunc.attributes().hasRtFlag(RtAttributeFlagsE::Mixin) ||
        symFunc.attributes().hasRtFlag(RtAttributeFlagsE::Compiler))
        return TypeRef::invalid();

    std::unordered_set<TypeRef> visiting;
    if (!canReflectFunctionSignature(ctx, symFunc, visiting))
        return TypeRef::invalid();

    if (symFunc.typeRef().isValid())
        return symFunc.typeRef();

    return ctx.typeMgr().addType(TypeInfo::makeFunction(const_cast<SymbolFunction*>(&symFunc), TypeInfoFlagsE::Zero));
}

SWC_END_NAMESPACE();
