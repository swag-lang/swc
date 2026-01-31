#include "pch.h"
#include "Sema/Type/TypeGen.h"
#include "Main/TaskContext.h"
#include "Runtime/DataSegment.h"
#include "Runtime/Runtime.h"
#include "Sema/Core/Sema.h"
#include "Sema/Symbol/Symbol.Variable.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    enum class LayoutKind
    {
        Base,
        Native,
        Enum,
        Array,
        Slice,
        Pointer,
        Struct,
        Alias,
        Variadic,
        TypedVariadic,
        Func,
    };

    LayoutKind layoutKindOf(const TypeInfo& type)
    {
        if (type.isBool() || type.isInt() || type.isFloat() || type.isChar() || type.isString() || type.isCString() ||
            type.isRune() || type.isAny() || type.isVoid() || type.isUndefined())
            return LayoutKind::Native;

        if (type.isEnum())
            return LayoutKind::Enum;
        if (type.isArray())
            return LayoutKind::Array;
        if (type.isSlice())
            return LayoutKind::Slice;
        if (type.isAlias())
            return LayoutKind::Alias;
        if (type.isAnyVariadic())
            return type.isTypedVariadic() ? LayoutKind::TypedVariadic : LayoutKind::Variadic;
        if (type.isFunction())
            return LayoutKind::Func;
        if (type.isPointerLike())
            return LayoutKind::Pointer;
        if (type.isStruct())
            return LayoutKind::Struct;

        return LayoutKind::Base;
    }

    TypeRef rtTypeRefFor(const TypeManager& tm, LayoutKind kind)
    {
        switch (kind)
        {
            case LayoutKind::Native: return tm.structTypeInfoNative();
            case LayoutKind::Enum: return tm.structTypeInfoEnum();
            case LayoutKind::Array: return tm.structTypeInfoArray();
            case LayoutKind::Slice: return tm.structTypeInfoSlice();
            case LayoutKind::Pointer: return tm.structTypeInfoPointer();
            case LayoutKind::Struct: return tm.structTypeInfoStruct();
            case LayoutKind::Alias: return tm.structTypeInfoAlias();
            case LayoutKind::Variadic: return tm.structTypeInfoVariadic();
            case LayoutKind::TypedVariadic: return tm.structTypeInfoVariadic();
            case LayoutKind::Func: return tm.structTypeInfoFunc();
            case LayoutKind::Base: return tm.structTypeInfo();
        }

        return tm.structTypeInfo();
    }

    Result ensureTypeInfoStructReady(Sema& sema, const TypeManager& tm, TypeRef rtTypeRef, const AstNode& node)
    {
        if (rtTypeRef.isInvalid())
            return sema.waitIdentifier(sema.idMgr().predefined(IdentifierManager::PredefinedName::TypeInfo), node.srcViewRef(), node.tokRef());

        const auto& structType = tm.get(rtTypeRef);
        if (!structType.isCompleted(sema.ctx()))
            return sema.waitCompleted(&structType.payloadSymStruct(), node.srcViewRef(), node.tokRef());

        return Result::Continue;
    }

    template<typename T>
    constexpr T enumOr(T a, T b)
    {
        using U = std::underlying_type_t<T>;
        return static_cast<T>(static_cast<U>(a) | static_cast<U>(b));
    }

    void addFlag(Runtime::TypeInfo& rt, Runtime::TypeInfoFlags f)
    {
        rt.flags = enumOr(rt.flags, f);
    }

    void initCommon(Sema& sema, DataSegment& storage, Runtime::TypeInfo& rtType, uint32_t offset, const TypeInfo& type, TypeGen::TypeGenResult& result)
    {
        auto& ctx = sema.ctx();

        rtType.sizeofType = static_cast<uint32_t>(type.sizeOf(ctx));
        rtType.crc        = type.hash();

        rtType.flags = Runtime::TypeInfoFlags::Zero;
        if (type.isConst())
            addFlag(rtType, Runtime::TypeInfoFlags::Const);
        if (type.isNullable())
            addFlag(rtType, Runtime::TypeInfoFlags::Nullable);

        const TypeInfo& structType = sema.typeMgr().get(result.rtTypeRef);
        result.span                = ByteSpan{storage.ptr<std::byte>(offset), structType.sizeOf(ctx)};

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

            switch (type.payloadIntBits())
            {
                case 8: rtType.nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U8 : Runtime::TypeInfoNativeKind::S8; return;
                case 16: rtType.nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U16 : Runtime::TypeInfoNativeKind::S16; return;
                case 32: rtType.nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U32 : Runtime::TypeInfoNativeKind::S32; return;
                case 64: rtType.nativeKind = type.isIntUnsigned() ? Runtime::TypeInfoNativeKind::U64 : Runtime::TypeInfoNativeKind::S64; return;
                default: return;
            }
        }

        if (type.isFloat())
        {
            addFlag(rtType.base, Runtime::TypeInfoFlags::Float);
            rtType.nativeKind = (type.payloadFloatBits() == 32) ? Runtime::TypeInfoNativeKind::F32 : Runtime::TypeInfoNativeKind::F64;
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
        const auto& dims = type.payloadArrayDims();
        if (dims.empty())
        {
            rtType.count      = 0;
            rtType.totalCount = 0;
            return;
        }

        rtType.count      = dims[0];
        rtType.totalCount = dims[0];
        for (size_t i = 1; i < dims.size(); ++i)
            rtType.totalCount *= dims[i];
    }

    void initStruct(Sema&                         sema,
                    DataSegment&                  storage,
                    Runtime::TypeInfoStruct&      rtType,
                    uint32_t                      offset,
                    const TypeInfo&               type,
                    TypeGen::TypeGenCache::Entry& entry)
    {
        const auto& ctx = sema.ctx();

        const Utf8 name          = type.toName(ctx);
        rtType.structName.length = storage.addString(offset, offsetof(Runtime::TypeInfoStruct, structName.ptr), name);

        const auto& fields  = type.payloadSymStruct().fields();
        rtType.fields.count = fields.size();

        entry.structFieldsCount = static_cast<uint32_t>(fields.size());
        entry.structFieldTypes.clear();

        if (fields.empty())
        {
            rtType.fields.ptr        = nullptr;
            entry.structFieldsOffset = 0;
            return;
        }

        const auto [fieldsOffset, fieldsPtr] = storage.reserveSpan<Runtime::TypeValue>(static_cast<uint32_t>(fields.size()));
        entry.structFieldsOffset             = fieldsOffset;
        rtType.fields.ptr                    = fieldsPtr;
        storage.addRelocation(offset + offsetof(Runtime::TypeInfoStruct, fields.ptr), fieldsOffset);

        for (uint32_t i = 0; i < fields.size(); ++i)
        {
            const auto* symField = fields[i];
            SWC_ASSERT(symField);

            Runtime::TypeValue& tv = fieldsPtr[i];

            // Name
            const auto& id = ctx.idMgr().get(symField->idRef());
            const Utf8  fName{id.name};
            const auto  elemOffset = fieldsOffset + static_cast<uint32_t>(i * sizeof(Runtime::TypeValue));
            tv.name.length         = storage.addString(elemOffset, offsetof(Runtime::TypeValue, name.ptr), fName);

            // Offset in bytes within the struct
            tv.offset = symField->offset();

            // Type (wired later once dep TypeInfos are emitted)
            entry.structFieldTypes.push_back(symField->typeRef());
        }
    }

    void addTypeRelocation(DataSegment& storage, uint32_t baseOffset, uint32_t fieldOffset, uint32_t targetOffset)
    {
        storage.addRelocation(baseOffset + fieldOffset, targetOffset);

        auto* ptrField = storage.ptr<const Runtime::TypeInfo*>(baseOffset + fieldOffset);
        *ptrField      = storage.ptr<Runtime::TypeInfo>(targetOffset);
    }

    SmallVector<TypeRef> computeDeps(const TypeManager& tm, const TaskContext& ctx, const TypeInfo& type, LayoutKind kind)
    {
        SmallVector<TypeRef> deps;

        switch (kind)
        {
            case LayoutKind::Pointer:
            case LayoutKind::Slice:
                deps.push_back(type.payloadTypeRef());
                break;

            case LayoutKind::Array:
            {
                const TypeRef elemTypeRef = type.payloadArrayElemTypeRef();
                deps.push_back(elemTypeRef);

                const TypeRef finalTypeRef = tm.get(elemTypeRef).unwrap(ctx, elemTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
                if (finalTypeRef != elemTypeRef)
                    deps.push_back(finalTypeRef);
                break;
            }

            case LayoutKind::Alias:
                deps.push_back(type.payloadTypeRef());
                break;

            case LayoutKind::TypedVariadic:
                deps.push_back(type.payloadTypeRef());
                break;

            case LayoutKind::Struct:
            {
                for (const auto* field : type.payloadSymStruct().fields())
                {
                    if (!field)
                        continue;
                    deps.push_back(field->typeRef());
                }
                break;
            }

            default:
                break;
        }

        return deps;
    }

    template<typename T>
    std::pair<uint32_t, Runtime::TypeInfo*> reservePayload(DataSegment& storage, Runtime::TypeInfoKind kind)
    {
        const auto res = storage.reserve<T>();
        const auto off = res.first;
        auto*      ptr = res.second;
        ptr->base.kind = kind;
        return {off, &ptr->base};
    }

    std::pair<uint32_t, Runtime::TypeInfo*> allocateTypeInfoPayload(Sema& sema, DataSegment& storage, LayoutKind kind, const TypeInfo& type)
    {
        switch (kind)
        {
            case LayoutKind::Native:
            {
                auto [offset, base] = reservePayload<Runtime::TypeInfoNative>(storage, Runtime::TypeInfoKind::Native);
                initNative(*reinterpret_cast<Runtime::TypeInfoNative*>(base), type);
                return {offset, base};
            }

            case LayoutKind::Enum:
                return reservePayload<Runtime::TypeInfoEnum>(storage, Runtime::TypeInfoKind::Enum);

            case LayoutKind::Array:
            {
                auto [offset, base] = reservePayload<Runtime::TypeInfoArray>(storage, Runtime::TypeInfoKind::Array);
                initArray(*reinterpret_cast<Runtime::TypeInfoArray*>(base), type);
                return {offset, base};
            }

            case LayoutKind::Slice:
                return reservePayload<Runtime::TypeInfoSlice>(storage, Runtime::TypeInfoKind::Slice);

            case LayoutKind::Pointer:
                return reservePayload<Runtime::TypeInfoPointer>(storage, Runtime::TypeInfoKind::Pointer);

            case LayoutKind::Struct:
                return reservePayload<Runtime::TypeInfoStruct>(storage, Runtime::TypeInfoKind::Struct);

            case LayoutKind::Alias:
                return reservePayload<Runtime::TypeInfoAlias>(storage, Runtime::TypeInfoKind::Alias);

            case LayoutKind::Variadic:
                return reservePayload<Runtime::TypeInfoVariadic>(storage, Runtime::TypeInfoKind::Variadic);

            case LayoutKind::TypedVariadic:
                return reservePayload<Runtime::TypeInfoVariadic>(storage, Runtime::TypeInfoKind::TypedVariadic);

            case LayoutKind::Func:
                return reservePayload<Runtime::TypeInfoFunc>(storage, Runtime::TypeInfoKind::Func);

            case LayoutKind::Base:
            default:
            {
                const auto res = storage.reserve<Runtime::TypeInfo>();
                return {res.first, res.second};
            }
        }
    }

    const TypeGen::TypeGenCache::Entry& requireDone(const TypeGen::TypeGenCache& cache, TypeRef depKey)
    {
        const auto it = cache.entries.find(depKey);
        SWC_ASSERT(it != cache.entries.end() && "Missing TypeInfo dependency in cache");
        SWC_ASSERT(it->second.state == TypeGen::TypeGenCache::State::Done && "TypeInfo dependency not marked Done");
        return it->second;
    }

    void wireRelocations(Sema& sema, const TypeGen::TypeGenCache& cache, DataSegment& storage, TypeRef key, const TypeGen::TypeGenCache::Entry& entry, LayoutKind kind)
    {
        const auto&        ctx     = sema.ctx();
        const TypeManager& typeMgr = sema.typeMgr();

        switch (kind)
        {
            case LayoutKind::Pointer:
            {
                const TypeRef depKey = typeMgr.get(key).payloadTypeRef();
                const auto&   dep    = requireDone(cache, depKey);
                addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoPointer, pointedType), dep.offset);
                break;
            }

            case LayoutKind::Slice:
            {
                const TypeRef depKey = typeMgr.get(key).payloadTypeRef();
                const auto&   dep    = requireDone(cache, depKey);
                addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoSlice, pointedType), dep.offset);
                break;
            }

            case LayoutKind::Array:
            {
                const TypeRef elemTypeRef = typeMgr.get(key).payloadArrayElemTypeRef();
                const auto&   dep         = requireDone(cache, elemTypeRef);
                addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoArray, pointedType), dep.offset);

                const TypeRef finalTypeRef = typeMgr.get(elemTypeRef).unwrap(ctx, elemTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
                const auto&   fin          = requireDone(cache, finalTypeRef);
                addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoArray, finalType), fin.offset);
                break;
            }

            case LayoutKind::Alias:
            {
                const TypeRef depKey = typeMgr.get(key).payloadTypeRef();
                const auto&   dep    = requireDone(cache, depKey);
                addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoAlias, rawType), dep.offset);
                break;
            }

            case LayoutKind::TypedVariadic:
            {
                const TypeRef depKey = typeMgr.get(key).payloadTypeRef();
                const auto&   dep    = requireDone(cache, depKey);
                addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoVariadic, rawType), dep.offset);
                break;
            }

            case LayoutKind::Struct:
            {
                // Wire each `TypeValue.pointedType` of `fields`.
                if (!entry.structFieldsCount || !entry.structFieldsOffset)
                    break;

                SWC_ASSERT(entry.structFieldTypes.size() == entry.structFieldsCount);
                for (uint32_t i = 0; i < entry.structFieldsCount; ++i)
                {
                    const TypeRef depKey     = entry.structFieldTypes[i];
                    const auto&   dep        = requireDone(cache, depKey);
                    const auto    elemOffset = entry.structFieldsOffset + static_cast<uint32_t>(i * sizeof(Runtime::TypeValue));
                    addTypeRelocation(storage, elemOffset, offsetof(Runtime::TypeValue, pointedType), dep.offset);
                }

                break;
            }

            default:
                break;
        }
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

                const LayoutKind kind = layoutKindOf(type);
                entry.rtTypeRef       = rtTypeRefFor(tm, kind);
                RESULT_VERIFY(ensureTypeInfoStructReady(sema, tm, entry.rtTypeRef, node));

                auto [offset, rtBase] = allocateTypeInfoPayload(sema, storage, kind, type);
                entry.offset          = offset;

                TypeGen::TypeGenResult tmp;
                tmp.rtTypeRef = entry.rtTypeRef;
                tmp.offset    = entry.offset;
                initCommon(sema, storage, *rtBase, offset, type, tmp);

                if (kind == LayoutKind::Struct)
                {
                    initStruct(sema,
                               storage,
                               *reinterpret_cast<Runtime::TypeInfoStruct*>(rtBase),
                               offset,
                               type,
                               entry);
                }

                entry.deps = computeDeps(tm, ctx, type, kind);
                it         = cache.entries.emplace(key, std::move(entry)).first;
            }

            auto& entry = it->second;
            if (entry.state == TypeGen::TypeGenCache::State::Done)
            {
                stack.pop_back();
                inStack.erase(key);
                continue;
            }

            const LayoutKind kind = layoutKindOf(type);

            // Push the first unmet dependency.
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

            // All deps are Done => wire relocations, then mark Done.
            wireRelocations(sema, cache, storage, key, entry, kind);
            entry.state = TypeGen::TypeGenCache::State::Done;
        }

        const auto it = cache.entries.find(typeRef);
        if (it == cache.entries.end() || it->second.state != TypeGen::TypeGenCache::State::Done)
            return Result::Pause;

        const auto& entry = it->second;
        result.offset     = entry.offset;
        result.rtTypeRef  = entry.rtTypeRef;

        const TypeInfo& structType = tm.get(result.rtTypeRef);
        result.span                = ByteSpan{storage.ptr<std::byte>(result.offset), structType.sizeOf(ctx)};

        sema.compiler().notifyAlive();
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
