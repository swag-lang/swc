#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeGen.Internal.h"
#include "Main/TaskContext.h"
#include "Runtime/Runtime.h"
#include "Support/Core/DataSegment.h"

SWC_BEGIN_NAMESPACE();

namespace
{
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

    void addTypeRelocation(DataSegment& storage, uint32_t baseOffset, uint32_t fieldOffset, uint32_t targetOffset)
    {
        storage.addRelocation(baseOffset + fieldOffset, targetOffset);

        auto* ptrField = storage.ptr<const Runtime::TypeInfo*>(baseOffset + fieldOffset);
        *ptrField      = storage.ptr<Runtime::TypeInfo>(targetOffset);
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
}

namespace TypeGenInternal
{
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

    void initStruct(Sema& sema, DataSegment& storage, Runtime::TypeInfoStruct& rtType, uint32_t offset, const TypeInfo& type, TypeGen::TypeGenCache::Entry& entry)
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

    void initFunc(Runtime::TypeInfoFunc& rtType, const TypeInfo& type)
    {
        (void) rtType;
        (void) type;
    }

    std::pair<uint32_t, Runtime::TypeInfo*> allocateTypeInfoPayload(DataSegment& storage, LayoutKind kind, const TypeInfo& type)
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

    void wireRelocations(Sema& sema, const TypeGen::TypeGenCache& cache, DataSegment& storage, TypeRef key, const TypeGen::TypeGenCache::Entry& entry, LayoutKind kind)
    {
        const auto&        ctx     = sema.ctx();
        const TypeManager& typeMgr = sema.typeMgr();

        const auto requireDone = [&cache](TypeRef depKey) -> const TypeGen::TypeGenCache::Entry& {
            const auto it = cache.entries.find(depKey);
            SWC_ASSERT(it != cache.entries.end() && "Missing TypeInfo dependency in cache");
            SWC_ASSERT(it->second.state == TypeGen::TypeGenCache::State::Done && "TypeInfo dependency not marked Done");
            return it->second;
        };

        switch (kind)
        {
            case LayoutKind::Pointer:
            {
                const TypeRef depKey = typeMgr.get(key).payloadTypeRef();
                const auto&   dep    = requireDone(depKey);
                addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoPointer, pointedType), dep.offset);
                break;
            }

            case LayoutKind::Slice:
            {
                const TypeRef depKey = typeMgr.get(key).payloadTypeRef();
                const auto&   dep    = requireDone(depKey);
                addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoSlice, pointedType), dep.offset);
                break;
            }

            case LayoutKind::Array:
            {
                const TypeRef elemTypeRef = typeMgr.get(key).payloadArrayElemTypeRef();
                const auto&   dep         = requireDone(elemTypeRef);
                addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoArray, pointedType), dep.offset);

                const TypeRef finalTypeRef = typeMgr.get(elemTypeRef).unwrap(ctx, elemTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
                const auto&   fin          = requireDone(finalTypeRef);
                addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoArray, finalType), fin.offset);
                break;
            }

            case LayoutKind::Alias:
            {
                const TypeRef depKey = typeMgr.get(key).payloadTypeRef();
                const auto&   dep    = requireDone(depKey);
                addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoAlias, rawType), dep.offset);
                break;
            }

            case LayoutKind::TypedVariadic:
            {
                const TypeRef depKey = typeMgr.get(key).payloadTypeRef();
                const auto&   dep    = requireDone(depKey);
                addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoVariadic, rawType), dep.offset);
                break;
            }

            case LayoutKind::Struct:
            {
                // Wire each 'TypeValue.pointedType' of 'fields'.
                if (!entry.structFieldsCount || !entry.structFieldsOffset)
                    break;

                SWC_ASSERT(entry.structFieldTypes.size() == entry.structFieldsCount);
                for (uint32_t i = 0; i < entry.structFieldsCount; ++i)
                {
                    const TypeRef depKey     = entry.structFieldTypes[i];
                    const auto&   dep        = requireDone(depKey);
                    const auto    elemOffset = entry.structFieldsOffset + static_cast<uint32_t>(i * sizeof(Runtime::TypeValue));
                    addTypeRelocation(storage, elemOffset, offsetof(Runtime::TypeValue, pointedType), dep.offset);
                }

                break;
            }

            default:
                break;
        }
    }
}

SWC_END_NAMESPACE();
