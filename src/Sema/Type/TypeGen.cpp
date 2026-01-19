#include "pch.h"
#include "Sema/Type/TypeGen.h"
#include "Core/DataSegment.h"
#include "Main/TaskContext.h"
#include "Runtime/Runtime.h"
#include "Sema/Core/Sema.h"
#include "Sema/Type/TypeManager.h"
#include <unordered_map>
#include <unordered_set>

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
    }

    void addTypeRelocation(DataSegment& storage, uint32_t baseOffset, uint32_t fieldOffset, uint32_t targetOffset)
    {
        storage.addRelocation(baseOffset + fieldOffset, targetOffset);
        auto* ptrField = storage.ptr<const Runtime::TypeInfo*>(baseOffset + fieldOffset);
        *ptrField      = storage.ptr<Runtime::TypeInfo>(targetOffset);
    }

    struct TypeGenRecContext
    {
        std::unordered_set<uint32_t> inProgress;
    };

    Result makeTypeInfoRec(Sema& sema, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGen::TypeGenResult& result, std::unordered_map<uint32_t, uint32_t>& offsets, TypeGenRecContext& rec)
    {
        auto&              ctx  = sema.ctx();
        const TypeManager& tm   = ctx.typeMgr();
        const TypeInfo&    type = tm.get(typeRef);
        const AstNode&     node = sema.node(ownerNodeRef);

        const uint32_t key = typeRef.get();
        if (const auto it = offsets.find(key); it != offsets.end())
        {
            result.offset        = it->second;
            result.structTypeRef = selectTypeInfoStructType(tm, type);
            RESULT_VERIFY(ensureTypeInfoStructReady(sema, tm, result.structTypeRef, node));
            const TypeInfo& structType = tm.get(result.structTypeRef);
            result.view                = std::string_view{storage.ptr<char>(result.offset), structType.sizeOf(ctx)};
            return Result::Continue;
        }

        // Pick and validate the "TypeInfo struct" layout used to serialize this type
        result.structTypeRef = selectTypeInfoStructType(tm, type);
        RESULT_VERIFY(ensureTypeInfoStructReady(sema, tm, result.structTypeRef, node));

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

        if (result.structTypeRef == tm.structTypeInfoNative())
        {
            RESERVE_TYPE_INFO(TypeInfoNative, Runtime::TypeInfoKind::Native);
            initNative(*reinterpret_cast<Runtime::TypeInfoNative*>(rt), type);
        }
        else if (result.structTypeRef == tm.structTypeInfoEnum())
        {
            RESERVE_TYPE_INFO(TypeInfoEnum, Runtime::TypeInfoKind::Enum);
        }
        else if (result.structTypeRef == tm.structTypeInfoArray())
        {
            RESERVE_TYPE_INFO(TypeInfoArray, Runtime::TypeInfoKind::Array);
            initArray(*reinterpret_cast<Runtime::TypeInfoArray*>(rt), type);
        }
        else if (result.structTypeRef == tm.structTypeInfoSlice())
        {
            RESERVE_TYPE_INFO(TypeInfoSlice, Runtime::TypeInfoKind::Slice);
        }
        else if (result.structTypeRef == tm.structTypeInfoPointer())
        {
            RESERVE_TYPE_INFO(TypeInfoPointer, Runtime::TypeInfoKind::Pointer);
        }
        else if (result.structTypeRef == tm.structTypeInfoStruct())
        {
            RESERVE_TYPE_INFO(TypeInfoStruct, Runtime::TypeInfoKind::Struct);
            initStruct(sema, storage, *reinterpret_cast<Runtime::TypeInfoStruct*>(rt), offset, type);
        }
        else if (result.structTypeRef == tm.structTypeInfoAlias())
        {
            RESERVE_TYPE_INFO(TypeInfoAlias, Runtime::TypeInfoKind::Alias);
        }
        else if (result.structTypeRef == tm.structTypeInfoVariadic())
        {
            RESERVE_TYPE_INFO(TypeInfoVariadic, type.isTypedVariadic() ? Runtime::TypeInfoKind::TypedVariadic : Runtime::TypeInfoKind::Variadic);
        }
        else if (result.structTypeRef == tm.structTypeInfoFunc())
        {
            RESERVE_TYPE_INFO(TypeInfoFunc, Runtime::TypeInfoKind::Func);
        }
        else
        {
            const auto res = storage.reserve<Runtime::TypeInfo>();
            offset         = res.first;
            rt             = res.second;
        }

        result.offset = offset;

        // Mark as "in progress" before recursing so self-references (via pointers) can be wired.
        offsets[key] = offset;
        rec.inProgress.insert(key);

        // Fill common fields + strings + view
        initCommon(sema, storage, *rt, offset, type, result);

        // Recursively populate dependent type pointers.
        if (result.structTypeRef == tm.structTypeInfoPointer())
        {
            const TypeRef          pointedTypeRef = type.typeRef();
            TypeGen::TypeGenResult pointedRes;
            RESULT_VERIFY(makeTypeInfoRec(sema, storage, pointedTypeRef, ownerNodeRef, pointedRes, offsets, rec));
            addTypeRelocation(storage, offset, offsetof(Runtime::TypeInfoPointer, pointedType), pointedRes.offset);
        }
        else if (result.structTypeRef == tm.structTypeInfoSlice())
        {
            const TypeRef          pointedTypeRef = type.typeRef();
            TypeGen::TypeGenResult pointedRes;
            RESULT_VERIFY(makeTypeInfoRec(sema, storage, pointedTypeRef, ownerNodeRef, pointedRes, offsets, rec));
            addTypeRelocation(storage, offset, offsetof(Runtime::TypeInfoSlice, pointedType), pointedRes.offset);
        }
        else if (result.structTypeRef == tm.structTypeInfoArray())
        {
            const TypeRef          elemTypeRef = type.arrayElemTypeRef();
            TypeGen::TypeGenResult elemRes;
            RESULT_VERIFY(makeTypeInfoRec(sema, storage, elemTypeRef, ownerNodeRef, elemRes, offsets, rec));
            addTypeRelocation(storage, offset, offsetof(Runtime::TypeInfoArray, pointedType), elemRes.offset);

            // "finalType" is the ultimate (non-array) type.
            const TypeRef finalTypeRef = tm.get(elemTypeRef).ultimateTypeRef(ctx);
            if (finalTypeRef == elemTypeRef)
            {
                addTypeRelocation(storage, offset, offsetof(Runtime::TypeInfoArray, finalType), elemRes.offset);
            }
            else
            {
                TypeGen::TypeGenResult finalRes;
                RESULT_VERIFY(makeTypeInfoRec(sema, storage, finalTypeRef, ownerNodeRef, finalRes, offsets, rec));
                addTypeRelocation(storage, offset, offsetof(Runtime::TypeInfoArray, finalType), finalRes.offset);
            }
        }
        else if (result.structTypeRef == tm.structTypeInfoAlias())
        {
            const TypeRef          rawTypeRef = type.underlyingTypeRef();
            TypeGen::TypeGenResult rawRes;
            RESULT_VERIFY(makeTypeInfoRec(sema, storage, rawTypeRef, ownerNodeRef, rawRes, offsets, rec));
            addTypeRelocation(storage, offset, offsetof(Runtime::TypeInfoAlias, rawType), rawRes.offset);
        }
        else if (result.structTypeRef == tm.structTypeInfoVariadic())
        {
            if (type.isTypedVariadic())
            {
                const TypeRef          rawTypeRef = type.typeRef();
                TypeGen::TypeGenResult rawRes;
                RESULT_VERIFY(makeTypeInfoRec(sema, storage, rawTypeRef, ownerNodeRef, rawRes, offsets, rec));
                addTypeRelocation(storage, offset, offsetof(Runtime::TypeInfoVariadic, rawType), rawRes.offset);
            }
        }

        rec.inProgress.erase(key);
        return Result::Continue;
    }
}

TypeGen::StorageCache& TypeGen::cacheFor(const DataSegment& storage)
{
    std::lock_guard lk(cachesMutex_);
    auto&           ptr = caches_[&storage];
    if (!ptr)
        ptr = std::make_unique<StorageCache>();
    return *ptr;
}

Result TypeGen::makeTypeInfo(Sema& sema, DataSegment& storage, TypeRef typeRef, AstNodeRef ownerNodeRef, TypeGenResult& result)
{
    auto&           cache = cacheFor(storage);
    std::lock_guard lk(cache.mutex);

    TypeGenRecContext rec;
    return makeTypeInfoRec(sema, storage, typeRef, ownerNodeRef, result, cache.offsets, rec);
}

SWC_END_NAMESPACE();
