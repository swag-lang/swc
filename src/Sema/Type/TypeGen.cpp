#include "pch.h"
#include "Sema/Type/TypeGen.h"
#include "Core/DataSegment.h"
#include "Main/TaskContext.h"
#include "Runtime/Runtime.h"
#include "Sema/Core/Sema.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    TypeRef selectTypeInfoStructType(const TypeManager& tm, const TypeInfo& type)
    {
        if (type.isBool() || type.isInt() || type.isFloat() || type.isChar() || type.isString() || type.isCString() || type.isRune() || type.isAny() || type.isVoid() || type.isUndefined())
            return tm.structTypeInfoNative();
        if (type.isEnum())
            return tm.structTypeInfoEnum();
        if (type.isArray())
            return tm.structTypeInfoArray();
        if (type.isSlice())
            return tm.structTypeInfoSlice();
        if (type.isAlias())
            return tm.structTypeInfoAlias();
        if (type.isAnyVariadic())
            return tm.structTypeInfoVariadic();
        if (type.isFunction())
            return tm.structTypeInfoFunc();
        if (type.isPointerLike())
            return tm.structTypeInfoPointer();
        if (type.isStruct())
            return tm.structTypeInfoStruct();
        return tm.structTypeInfo();
    }

    Result ensureTypeInfoStructReady(Sema& sema, const TypeManager& tm, const TypeRef structTypeRef, const AstNode& node)
    {
        if (structTypeRef.isInvalid())
            return sema.waitIdentifier(sema.idMgr().nameTypeInfo(), node.srcViewRef(), node.tokRef());

        const auto& structType = tm.get(structTypeRef);
        if (!structType.isCompleted(sema.ctx()))
            return sema.waitCompleted(&structType.symStruct(), node.srcViewRef(), node.tokRef());

        return Result::Continue;
    }

    void addFlag(Runtime::TypeInfo& rt, Runtime::TypeInfoFlags f)
    {
        rt.flags = static_cast<Runtime::TypeInfoFlags>(static_cast<uint32_t>(rt.flags) | static_cast<uint32_t>(f));
    }

    void initCommon(Sema& sema, DataSegment& storage, Runtime::TypeInfo& rtType, uint32_t offset, const TypeInfo& type, TypeGen::TypeGenResult& result)
    {
        auto& ctx         = sema.ctx();
        rtType.sizeofType = static_cast<uint32_t>(type.sizeOf(ctx));
        rtType.crc        = type.hash();

        rtType.flags = Runtime::TypeInfoFlags::Zero;
        if (type.isConst())
            addFlag(rtType, Runtime::TypeInfoFlags::Const);
        if (type.isNullable())
            addFlag(rtType, Runtime::TypeInfoFlags::Nullable);

        const TypeInfo& structType = sema.typeMgr().get(result.structTypeRef);
        result.view                = std::string_view{storage.ptr<char>(offset), structType.sizeOf(ctx)};

        const Utf8 name        = type.toName(ctx);
        rtType.fullname.length = storage.addString(offset, offsetof(Runtime::TypeInfo, fullname.ptr), name);
        rtType.name.length     = storage.addString(offset, offsetof(Runtime::TypeInfo, name.ptr), name);
    }

    void initNative(Runtime::TypeInfoNative& rtType, const TypeInfo& type)
    {
        rtType.nativeKind = Runtime::TypeInfoNativeKind::Void;

        if (type.isBool())
        {
            rtType.nativeKind = Runtime::TypeInfoNativeKind::Bool;
            return;
        }

        if (type.isInt())
        {
            addFlag(rtType.base, Runtime::TypeInfoFlags::Integer);
            if (type.isIntUnsigned())
                addFlag(rtType.base, Runtime::TypeInfoFlags::Unsigned);

            switch (type.intBits())
            {
                case 8: rtType.nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U8 : Runtime::TypeInfoNativeKind::S8; break;
                case 16: rtType.nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U16 : Runtime::TypeInfoNativeKind::S16; break;
                case 32: rtType.nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U32 : Runtime::TypeInfoNativeKind::S32; break;
                case 64: rtType.nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U64 : Runtime::TypeInfoNativeKind::S64; break;
            }
            return;
        }

        if (type.isFloat())
        {
            addFlag(rtType.base, Runtime::TypeInfoFlags::Float);
            rtType.nativeKind = (type.floatBits() == 32) ? Runtime::TypeInfoNativeKind::F32 : Runtime::TypeInfoNativeKind::F64;
            return;
        }

        if (type.isString())
        {
            rtType.nativeKind = Runtime::TypeInfoNativeKind::String;
            return;
        }

        if (type.isCString())
        {
            rtType.nativeKind = Runtime::TypeInfoNativeKind::CString;
            return;
        }

        if (type.isRune())
        {
            rtType.nativeKind = Runtime::TypeInfoNativeKind::Rune;
            return;
        }

        if (type.isAny())
        {
            rtType.nativeKind = Runtime::TypeInfoNativeKind::Any;
            return;
        }

        if (type.isVoid())
        {
            rtType.nativeKind = Runtime::TypeInfoNativeKind::Void;
            return;
        }

        if (type.isUndefined())
        {
            rtType.nativeKind = Runtime::TypeInfoNativeKind::Undefined;
            return;
        }
    }

    void initArray(Runtime::TypeInfoArray& rtType, const TypeInfo& type)
    {
        const auto& dims  = type.arrayDims();
        rtType.count      = dims.empty() ? 0 : dims[0];
        rtType.totalCount = dims.empty() ? 0 : dims[0];
        for (size_t i = 1; i < dims.size(); i++)
            rtType.totalCount *= dims[i];
    }

    void initStruct(Sema& sema, DataSegment& storage, Runtime::TypeInfoStruct& rtType, uint32_t offset, const TypeInfo& type)
    {
        const Utf8 name          = type.toName(sema.ctx());
        rtType.structName.length = storage.addString(offset, offsetof(Runtime::TypeInfoStruct, structName.ptr), name);
        rtType.fields.count      = type.symStruct().fields().size();
    }

    void addTypeRelocation(DataSegment& storage, uint32_t baseOffset, uint32_t fieldOffset, uint32_t targetOffset)
    {
        storage.addRelocation(baseOffset + fieldOffset, targetOffset);
        auto* ptrField = storage.ptr<const Runtime::TypeInfo*>(baseOffset + fieldOffset);
        *ptrField      = storage.ptr<Runtime::TypeInfo>(targetOffset);
    }

    SmallVector<TypeRef> computeDeps(const TypeManager& tm, const TaskContext& ctx, const TypeInfo& type, TypeRef structTypeRef)
    {
        SmallVector<TypeRef> deps;
        if (structTypeRef == tm.structTypeInfoPointer())
        {
            deps.push_back(type.typeRef());
        }
        else if (structTypeRef == tm.structTypeInfoSlice())
        {
            deps.push_back(type.typeRef());
        }
        else if (structTypeRef == tm.structTypeInfoArray())
        {
            const TypeRef elemTypeRef = type.arrayElemTypeRef();
            deps.push_back(elemTypeRef);

            const TypeRef finalTypeRef = tm.get(elemTypeRef).ultimateTypeRef(ctx);
            if (finalTypeRef != elemTypeRef)
                deps.push_back(finalTypeRef);
        }
        else if (structTypeRef == tm.structTypeInfoAlias())
        {
            deps.push_back(type.underlyingTypeRef());
        }
        else if (structTypeRef == tm.structTypeInfoVariadic())
        {
            if (type.isTypedVariadic())
                deps.push_back(type.typeRef());
        }

        return deps;
    }

    Result processTypeInfo(Sema& sema, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGen::TypeGenResult& result, TypeGen::TypeGenCache& cache)
    {
        auto&              ctx  = sema.ctx();
        const TypeManager& tm   = ctx.typeMgr();
        const AstNode&     node = sema.node(ownerNodeRef);

        SmallVector<TypeRef>        stack;
        std::unordered_set<TypeRef> inStack;
        stack.push_back(typeRef);
        inStack.insert(typeRef);

        while (!stack.empty())
        {
            const TypeRef   key  = stack.back();
            const TypeInfo& type = tm.get(key);

            auto it = cache.entries.find(key);
            if (it == cache.entries.end())
            {
                TypeGen::TypeGenCache::Entry entry;
                entry.structTypeRef = selectTypeInfoStructType(tm, type);
                RESULT_VERIFY(ensureTypeInfoStructReady(sema, tm, entry.structTypeRef, node));

                // Allocate the correct runtime TypeInfo payload
                uint32_t           offset = 0;
                Runtime::TypeInfo* rt     = nullptr;

#define RESERVE_TYPE_INFO(T, K)                         \
    do                                                  \
    {                                                   \
        const auto res = storage.reserve<Runtime::T>(); \
        offset         = res.first;                     \
        auto* ptr      = res.second;                    \
        rt             = &ptr->base;                    \
        rt->kind       = K;                             \
    } while (0)

                if (entry.structTypeRef == tm.structTypeInfoNative())
                {
                    RESERVE_TYPE_INFO(TypeInfoNative, Runtime::TypeInfoKind::Native);
                    initNative(*reinterpret_cast<Runtime::TypeInfoNative*>(rt), type);
                }
                else if (entry.structTypeRef == tm.structTypeInfoEnum())
                {
                    RESERVE_TYPE_INFO(TypeInfoEnum, Runtime::TypeInfoKind::Enum);
                }
                else if (entry.structTypeRef == tm.structTypeInfoArray())
                {
                    RESERVE_TYPE_INFO(TypeInfoArray, Runtime::TypeInfoKind::Array);
                    initArray(*reinterpret_cast<Runtime::TypeInfoArray*>(rt), type);
                }
                else if (entry.structTypeRef == tm.structTypeInfoSlice())
                {
                    RESERVE_TYPE_INFO(TypeInfoSlice, Runtime::TypeInfoKind::Slice);
                }
                else if (entry.structTypeRef == tm.structTypeInfoPointer())
                {
                    RESERVE_TYPE_INFO(TypeInfoPointer, Runtime::TypeInfoKind::Pointer);
                }
                else if (entry.structTypeRef == tm.structTypeInfoStruct())
                {
                    RESERVE_TYPE_INFO(TypeInfoStruct, Runtime::TypeInfoKind::Struct);
                    initStruct(sema, storage, *reinterpret_cast<Runtime::TypeInfoStruct*>(rt), offset, type);
                }
                else if (entry.structTypeRef == tm.structTypeInfoAlias())
                {
                    RESERVE_TYPE_INFO(TypeInfoAlias, Runtime::TypeInfoKind::Alias);
                }
                else if (entry.structTypeRef == tm.structTypeInfoVariadic())
                {
                    RESERVE_TYPE_INFO(TypeInfoVariadic, type.isTypedVariadic() ? Runtime::TypeInfoKind::TypedVariadic : Runtime::TypeInfoKind::Variadic);
                }
                else if (entry.structTypeRef == tm.structTypeInfoFunc())
                {
                    RESERVE_TYPE_INFO(TypeInfoFunc, Runtime::TypeInfoKind::Func);
                }
                else
                {
                    const auto res = storage.reserve<Runtime::TypeInfo>();
                    offset         = res.first;
                    rt             = res.second;
                }

                entry.offset = offset;

                // Fill common fields + strings
                TypeGen::TypeGenResult tmp;
                tmp.structTypeRef = entry.structTypeRef;
                tmp.offset        = entry.offset;
                initCommon(sema, storage, *rt, offset, type, tmp);

                entry.deps = computeDeps(tm, ctx, type, entry.structTypeRef);
                it         = cache.entries.emplace(key, std::move(entry)).first;
            }

            auto& entry = it->second;
            if (entry.state == TypeGen::TypeGenCache::State::Done)
            {
                stack.pop_back();
                inStack.erase(key);
                continue;
            }

            // Ensure all dependencies are completed before wiring relocations and marking Done.
            bool pushedDep = false;
            for (const TypeRef depKey : entry.deps)
            {
                if (depKey == key)
                    continue;

                const auto depIt = cache.entries.find(depKey);
                if (depIt != cache.entries.end() && depIt->second.state == TypeGen::TypeGenCache::State::Done)
                    continue;

                if (!inStack.contains(depKey))
                {
                    stack.push_back(depKey);
                    inStack.insert(depKey);
                }

                pushedDep = true;
                break;
            }

            if (pushedDep)
                continue;

            // All deps are Done => we can now wire relocations.
            if (entry.structTypeRef == tm.structTypeInfoPointer())
            {
                const TypeRef depKey = tm.get(key).typeRef();
                const auto    depIt  = cache.entries.find(depKey);
                if (depIt != cache.entries.end())
                    addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoPointer, pointedType), depIt->second.offset);
            }
            else if (entry.structTypeRef == tm.structTypeInfoSlice())
            {
                const TypeRef depKey = tm.get(key).typeRef();
                const auto    depIt  = cache.entries.find(depKey);
                if (depIt != cache.entries.end())
                    addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoSlice, pointedType), depIt->second.offset);
            }
            else if (entry.structTypeRef == tm.structTypeInfoArray())
            {
                const TypeRef elemTypeRef = tm.get(key).arrayElemTypeRef();
                const auto    elemIt      = cache.entries.find(elemTypeRef);
                if (elemIt != cache.entries.end())
                    addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoArray, pointedType), elemIt->second.offset);

                const TypeRef finalTypeRef = tm.get(elemTypeRef).ultimateTypeRef(ctx);
                const auto    finalIt      = cache.entries.find(finalTypeRef);
                if (finalIt != cache.entries.end())
                    addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoArray, finalType), finalIt->second.offset);
            }
            else if (entry.structTypeRef == tm.structTypeInfoAlias())
            {
                const TypeRef depKey = tm.get(key).underlyingTypeRef();
                const auto    depIt  = cache.entries.find(depKey);
                if (depIt != cache.entries.end())
                    addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoAlias, rawType), depIt->second.offset);
            }
            else if (entry.structTypeRef == tm.structTypeInfoVariadic())
            {
                const TypeInfo& curType = tm.get(key);
                if (curType.isTypedVariadic())
                {
                    const TypeRef depKey = curType.typeRef();
                    const auto    depIt  = cache.entries.find(depKey);
                    if (depIt != cache.entries.end())
                        addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoVariadic, rawType), depIt->second.offset);
                }
            }

            entry.state = TypeGen::TypeGenCache::State::Done;
        }

        const auto it = cache.entries.find(typeRef);
        if (it == cache.entries.end() || it->second.state != TypeGen::TypeGenCache::State::Done)
            return Result::Pause;

        const auto& entry    = it->second;
        result.offset        = entry.offset;
        result.structTypeRef = entry.structTypeRef;

        const TypeInfo& structType = tm.get(result.structTypeRef);
        result.view                = std::string_view{storage.ptr<char>(result.offset), structType.sizeOf(ctx)};
        return Result::Continue;
    }
}

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
    return processTypeInfo(sema, storage, typeRef, ownerNodeRef, result, cache);
}

SWC_END_NAMESPACE();
