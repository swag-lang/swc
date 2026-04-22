#include "pch.h"
#include "Compiler/Sema/Type/TypeGen.h"
#include "Backend/Runtime.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Main/TaskContext.h"
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

        const auto** ptrField = storage.ptr<const Runtime::TypeInfo*>(baseOffset + fieldOffset);
        *ptrField             = storage.ptr<Runtime::TypeInfo>(targetOffset);
    }

    template<typename T>
    std::pair<uint32_t, Runtime::TypeInfo*> reservePayload(DataSegment& storage, Runtime::TypeInfoKind kind)
    {
        const auto res = storage.reserve<T>();
        const auto off = res.first;
        T*         ptr = res.second;
        ptr->base.kind = kind;
        return {off, &ptr->base};
    }

    void initCommon(Sema& sema, DataSegment& storage, Runtime::TypeInfo& rtType, uint32_t offset, const TypeInfo& type)
    {
        TaskContext& ctx = sema.ctx();

        rtType.sizeofType = static_cast<uint32_t>(type.sizeOf(ctx));
        // Runtime metadata must stay stable across identical builds, so do not reuse the
        // allocator-dependent interning hash here.
        rtType.crc = type.runtimeHash(ctx);

        rtType.flags = Runtime::TypeInfoFlags::Zero;
        if (type.isConst())
            addFlag(rtType, Runtime::TypeInfoFlags::Const);
        if (type.isNullable())
            addFlag(rtType, Runtime::TypeInfoFlags::Nullable);
        if (type.isTypeInfo())
            addFlag(rtType, Runtime::TypeInfoFlags::PointerTypeInfo);

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

    bool compareEnumValueOrder(const SymbolEnumValue* left, const SymbolEnumValue* right)
    {
        SWC_ASSERT(left);
        SWC_ASSERT(right);
        return left->tokRef().get() < right->tokRef().get();
    }

    std::vector<const SymbolEnumValue*> collectEnumValues(const SymbolEnum& symEnum)
    {
        std::vector<const Symbol*> symbols;
        symEnum.getAllSymbols(symbols);

        std::vector<const SymbolEnumValue*> result;
        result.reserve(symbols.size());
        for (const Symbol* symbol : symbols)
        {
            const auto* enumValue = symbol ? symbol->safeCast<SymbolEnumValue>() : nullptr;
            if (enumValue)
                result.push_back(enumValue);
        }

        std::ranges::sort(result, compareEnumValueOrder);
        return result;
    }

    const TypeGen::TypeGenCache::Entry& requireCacheEntry(const TypeGen::TypeGenCache& cache, TypeRef depKey)
    {
        const auto it = cache.entries.find(depKey);
        SWC_ASSERT(it != cache.entries.end() && "Missing TypeInfo dependency in cache");
        return it->second;
    }

    const TypeGen::TypeGenCache::Entry& payloadDepEntry(const TypeManager& typeMgr, const TypeGen::TypeGenCache& cache, TypeRef key)
    {
        return requireCacheEntry(cache, typeMgr.get(key).payloadTypeRef());
    }

    TypeRef pointerLayoutDepTypeRef(const TypeManager& typeMgr, const TypeInfo& type)
    {
        if (type.isTypeInfo())
            return typeMgr.structTypeInfo();
        return type.payloadTypeRef();
    }

    void wireTypeValueArrayPointedRelocations(const TypeGen::TypeGenCache& cache, DataSegment& storage, const SmallVector<TypeRef>& types, uint32_t baseOffset)
    {
        for (uint32_t i = 0; i < types.size(); ++i)
        {
            const auto&    dep        = requireCacheEntry(cache, types[i]);
            const uint32_t elemOffset = baseOffset + static_cast<uint32_t>(i * sizeof(Runtime::TypeValue));
            addTypeRelocation(storage, elemOffset, offsetof(Runtime::TypeValue, pointedType), dep.offset);
        }
    }

    void materializeInlineAny(Sema& sema, const TypeGen::TypeGenCache& cache, DataSegment& storage, uint32_t baseOffset, uint32_t fieldOffset, ConstantRef valueCstRef)
    {
        Runtime::Any* const dstAny = storage.ptr<Runtime::Any>(baseOffset + fieldOffset);
        *dstAny                    = {};

        const ConstantValue& cst = sema.ctx().cstMgr().get(valueCstRef);
        if (cst.isNull())
            return;

        const TypeRef valueTypeRef = cst.typeRef();
        SWC_ASSERT(valueTypeRef.isValid());

        const auto& typeEntry = requireCacheEntry(cache, valueTypeRef);
        storage.addRelocation(baseOffset + fieldOffset + offsetof(Runtime::Any, type), typeEntry.offset);
        dstAny->type = storage.ptr<Runtime::TypeInfo>(typeEntry.offset);

        const uint64_t valueSize = sema.typeMgr().get(valueTypeRef).sizeOf(sema.ctx());
        if (!valueSize)
            return;

        std::vector valueBytes(valueSize, std::byte{0});
        SWC_INTERNAL_CHECK(ConstantLower::lowerToBytes(sema, valueBytes, valueCstRef, valueTypeRef) == Result::Continue);

        uint32_t valueOffset = INVALID_REF;
        SWC_INTERNAL_CHECK(ConstantLower::materializeStaticPayload(
                               valueOffset,
                               sema,
                               storage,
                               valueTypeRef,
                               ByteSpan{valueBytes.data(), valueBytes.size()}) ==
                           Result::Continue);
        SWC_ASSERT(valueOffset != INVALID_REF);

        storage.addRelocation(baseOffset + fieldOffset + offsetof(Runtime::Any, value), valueOffset);
        dstAny->value = storage.ptr<std::byte>(valueOffset);
    }

    void exportAttributeParams(Sema& sema, const TypeGen::TypeGenCache& cache, DataSegment& storage, uint32_t attributeOffset, Runtime::Attribute& rtAttribute, const AttributeInstance& attribute)
    {
        rtAttribute.params.ptr   = nullptr;
        rtAttribute.params.count = attribute.params.size();
        if (attribute.params.empty())
            return;

        const auto [paramsOffset, paramsPtr] = storage.reserveSpan<Runtime::AttributeParam>(static_cast<uint32_t>(attribute.params.size()));
        rtAttribute.params.ptr               = paramsPtr;
        storage.addRelocation(attributeOffset + offsetof(Runtime::Attribute, params.ptr), paramsOffset);

        const TaskContext& ctx = sema.ctx();
        for (uint32_t i = 0; i < attribute.params.size(); ++i)
        {
            const AttributeParamInstance& srcParam    = attribute.params[i];
            Runtime::AttributeParam&      dstParam    = paramsPtr[i];
            const uint32_t                paramOffset = paramsOffset + static_cast<uint32_t>(i * sizeof(Runtime::AttributeParam));

            dstParam.value = {};
            if (srcParam.nameIdRef.isValid())
            {
                const auto& id       = ctx.idMgr().get(srcParam.nameIdRef);
                dstParam.name.length = storage.addString(paramOffset, offsetof(Runtime::AttributeParam, name.ptr), Utf8{id.name});
            }

            if (srcParam.valueCstRef.isValid())
                materializeInlineAny(sema, cache, storage, paramOffset, offsetof(Runtime::AttributeParam, value), srcParam.valueCstRef);
        }
    }

    void exportAttributes(Sema& sema, const TypeGen::TypeGenCache& cache, DataSegment& storage, uint32_t ownerOffset, uint32_t attributesFieldOffset, const AttributeList& attributes)
    {
        auto* const attrsSlice = storage.ptr<Runtime::Slice<Runtime::Attribute>>(ownerOffset + attributesFieldOffset);
        attrsSlice->ptr        = nullptr;
        attrsSlice->count      = attributes.attributes.size();
        if (attributes.attributes.empty())
            return;

        const auto [attrsOffset, attrsPtr] = storage.reserveSpan<Runtime::Attribute>(static_cast<uint32_t>(attributes.attributes.size()));
        attrsSlice->ptr                    = attrsPtr;
        storage.addRelocation(ownerOffset + attributesFieldOffset + offsetof(Runtime::Slice<Runtime::Attribute>, ptr), attrsOffset);

        for (uint32_t i = 0; i < attributes.attributes.size(); ++i)
        {
            const AttributeInstance& attribute  = attributes.attributes[i];
            Runtime::Attribute&      rtAttr     = attrsPtr[i];
            const uint32_t           attrOffset = attrsOffset + static_cast<uint32_t>(i * sizeof(Runtime::Attribute));

            rtAttr.type = nullptr;
            if (attribute.symbol)
            {
                const TypeRef attributeTypeRef = attribute.symbol->typeRef();
                SWC_ASSERT(attributeTypeRef.isValid());

                const auto& typeEntry = requireCacheEntry(cache, attributeTypeRef);
                storage.addRelocation(attrOffset + offsetof(Runtime::Attribute, type), typeEntry.offset);
                rtAttr.type = storage.ptr<Runtime::TypeInfo>(typeEntry.offset);
            }

            exportAttributeParams(sema, cache, storage, attrOffset, rtAttr, attribute);
        }
    }

    void initEnum(Sema& sema, DataSegment& storage, Runtime::TypeInfoEnum& rtType, uint32_t offset, const TypeInfo& type, TypeGen::TypeGenCache::Entry& entry)
    {
        TaskContext&      ctx        = sema.ctx();
        const SymbolEnum& symEnum    = type.payloadSymEnum();
        const TypeRef     rawTypeRef = symEnum.underlyingTypeRef();
        const auto        values     = collectEnumValues(symEnum);

        rtType.values.ptr       = nullptr;
        rtType.values.count     = values.size();
        rtType.rawType          = nullptr;
        rtType.attributes.ptr   = nullptr;
        rtType.attributes.count = 0;
        entry.enumValuesOffset  = 0;
        entry.enumValuesCount   = static_cast<uint32_t>(values.size());

        if (values.empty())
            return;

        const auto [valuesOffset, valuesPtr] = storage.reserveSpan<Runtime::TypeValue>(static_cast<uint32_t>(values.size()));
        rtType.values.ptr                    = valuesPtr;
        entry.enumValuesOffset               = valuesOffset;
        storage.addRelocation(offset + offsetof(Runtime::TypeInfoEnum, values.ptr), valuesOffset);

        const uint64_t valueSize = ctx.typeMgr().get(rawTypeRef).sizeOf(ctx);
        for (uint32_t i = 0; i < values.size(); ++i)
        {
            const SymbolEnumValue* symValue = values[i];
            SWC_ASSERT(symValue);

            Runtime::TypeValue& tv         = valuesPtr[i];
            const uint32_t      elemOffset = valuesOffset + static_cast<uint32_t>(i * sizeof(Runtime::TypeValue));
            const Utf8          name{symValue->name(ctx)};
            tv.name.length = storage.addString(elemOffset, offsetof(Runtime::TypeValue, name.ptr), name);

            // Enum values keep their declared enum type, while the pointed payload stores the lowered raw bytes.
            storage.addRelocation(elemOffset + offsetof(Runtime::TypeValue, pointedType), offset);
            tv.pointedType = storage.ptr<Runtime::TypeInfo>(offset);

            if (!valueSize)
                continue;

            const ConstantValue& enumCst     = ctx.cstMgr().get(symValue->cstRef());
            const ConstantRef    rawValueRef = enumCst.isEnumValue() ? enumCst.getEnumValue() : symValue->cstRef();
            std::vector          valueBytes(valueSize, std::byte{0});
            ConstantLower::lowerToBytes(sema, valueBytes, rawValueRef, rawTypeRef);

            uint32_t     valueOffset    = INVALID_REF;
            const Result materializeRes = ConstantLower::materializeStaticPayload(valueOffset, sema, storage, rawTypeRef, valueBytes);
            SWC_ASSERT(materializeRes == Result::Continue);
            SWC_ASSERT(valueOffset != INVALID_REF);
            storage.addRelocation(elemOffset + offsetof(Runtime::TypeValue, value), valueOffset);
            tv.value = storage.ptr<std::byte>(valueOffset);
        }
    }

    void initStruct(Sema& sema, DataSegment& storage, Runtime::TypeInfoStruct& rtType, uint32_t offset, const TypeInfo& type, TypeGen::TypeGenCache::Entry& entry)
    {
        TaskContext& ctx = sema.ctx();

        const Utf8 name          = type.toName(ctx);
        rtType.structName.length = storage.addString(offset, offsetof(Runtime::TypeInfoStruct, structName.ptr), name);

        if (type.isAggregateStruct())
        {
            const auto& aggregate    = type.payloadAggregate();
            rtType.fields.count      = aggregate.types.size();
            rtType.usingFields.ptr   = nullptr;
            rtType.usingFields.count = 0;

            entry.structFieldsCount = static_cast<uint32_t>(aggregate.types.size());
            entry.structFieldTypes.clear();
            entry.usingFieldsCount = 0;
            entry.usingFieldTypes.clear();
            entry.usingFieldsOffset = 0;

            if (aggregate.types.empty())
            {
                rtType.fields.ptr        = nullptr;
                entry.structFieldsOffset = 0;
                return;
            }

            const auto [fieldsOffset, fieldsPtr] = storage.reserveSpan<Runtime::TypeValue>(entry.structFieldsCount);
            entry.structFieldsOffset             = fieldsOffset;
            rtType.fields.ptr                    = fieldsPtr;
            storage.addRelocation(offset + offsetof(Runtime::TypeInfoStruct, fields.ptr), fieldsOffset);

            uint64_t curOffset = 0;
            for (uint32_t i = 0; i < entry.structFieldsCount; ++i)
            {
                const TypeRef fieldTypeRef = aggregate.types[i];
                entry.structFieldTypes.push_back(fieldTypeRef);

                Runtime::TypeValue& tv         = fieldsPtr[i];
                const uint32_t      elemOffset = fieldsOffset + static_cast<uint32_t>(i * sizeof(Runtime::TypeValue));
                if (aggregate.names.size() > i && aggregate.names[i].isValid())
                {
                    const auto& id = ctx.idMgr().get(aggregate.names[i]);
                    tv.name.length = storage.addString(elemOffset, offsetof(Runtime::TypeValue, name.ptr), Utf8{id.name});
                }

                const TypeInfo& fieldType = ctx.typeMgr().get(fieldTypeRef);
                const uint32_t  align     = std::max<uint32_t>(fieldType.alignOf(ctx), 1);
                curOffset                 = ((curOffset + align - 1) / align) * align;
                tv.offset                 = static_cast<uint32_t>(curOffset);
                curOffset += fieldType.sizeOf(ctx);
            }

            return;
        }

        const auto& fields     = type.payloadSymStruct().fields();
        uint32_t    usingCount = 0;
        for (const SymbolVariable* symField : fields)
        {
            if (symField && symField->isUsingField())
                ++usingCount;
        }

        rtType.fields.count      = fields.size();
        rtType.usingFields.count = usingCount;

        entry.structFieldsCount = static_cast<uint32_t>(fields.size());
        entry.structFieldTypes.clear();
        entry.usingFieldsCount = usingCount;
        entry.usingFieldTypes.clear();

        if (fields.empty())
        {
            rtType.fields.ptr        = nullptr;
            rtType.usingFields.ptr   = nullptr;
            entry.structFieldsOffset = 0;
            entry.usingFieldsOffset  = 0;
            return;
        }

        const auto [fieldsOffset, fieldsPtr] = storage.reserveSpan<Runtime::TypeValue>(static_cast<uint32_t>(fields.size()));
        entry.structFieldsOffset             = fieldsOffset;
        rtType.fields.ptr                    = fieldsPtr;
        storage.addRelocation(offset + offsetof(Runtime::TypeInfoStruct, fields.ptr), fieldsOffset);

        Runtime::TypeValue* usingFieldsPtr    = nullptr;
        uint32_t            usingFieldsOffset = 0;
        if (usingCount)
        {
            const auto usingStorage = storage.reserveSpan<Runtime::TypeValue>(usingCount);
            usingFieldsOffset       = usingStorage.first;
            usingFieldsPtr          = usingStorage.second;
            entry.usingFieldsOffset = usingFieldsOffset;
            rtType.usingFields.ptr  = usingFieldsPtr;
            storage.addRelocation(offset + offsetof(Runtime::TypeInfoStruct, usingFields.ptr), usingFieldsOffset);
        }
        else
        {
            entry.usingFieldsOffset = 0;
            rtType.usingFields.ptr  = nullptr;
        }

        uint32_t usingIndex = 0;
        for (uint32_t i = 0; i < fields.size(); ++i)
        {
            const SymbolVariable* symField = fields[i];
            SWC_ASSERT(symField);

            Runtime::TypeValue& tv = fieldsPtr[i];

            const auto&    id = ctx.idMgr().get(symField->idRef());
            const Utf8     fName{id.name};
            const uint32_t elemOffset = fieldsOffset + static_cast<uint32_t>(i * sizeof(Runtime::TypeValue));
            tv.name.length            = storage.addString(elemOffset, offsetof(Runtime::TypeValue, name.ptr), fName);
            tv.offset                 = symField->offset();
            if (symField->isUsingField())
                tv.flags = enumOr(tv.flags, Runtime::TypeValueFlags::HasUsing);

            entry.structFieldTypes.push_back(symField->typeRef());

            if (!symField->isUsingField())
                continue;

            SWC_ASSERT(usingFieldsPtr != nullptr);
            SWC_ASSERT(usingIndex < usingCount);

            Runtime::TypeValue& usingTv = usingFieldsPtr[usingIndex];
            const uint32_t      usingElemOffset =
                usingFieldsOffset + static_cast<uint32_t>(usingIndex * sizeof(Runtime::TypeValue));
            usingTv.name.length = storage.addString(usingElemOffset, offsetof(Runtime::TypeValue, name.ptr), fName);
            usingTv.offset      = symField->offset();
            usingTv.flags       = enumOr(usingTv.flags, Runtime::TypeValueFlags::HasUsing);
            entry.usingFieldTypes.push_back(symField->typeRef());
            ++usingIndex;
        }
    }

    void initFunc(Sema& sema, DataSegment& storage, Runtime::TypeInfoFunc& rtType, uint32_t offset, const TypeInfo& type, TypeGen::TypeGenCache::Entry& entry)
    {
        const TaskContext&    ctx        = sema.ctx();
        const SymbolFunction& symFunc    = type.payloadSymFunction();
        const auto&           parameters = symFunc.parameters();

        rtType.generics.ptr     = nullptr;
        rtType.generics.count   = 0;
        rtType.parameters.ptr   = nullptr;
        rtType.parameters.count = 0;
        rtType.returnType       = nullptr;
        rtType.attributes.ptr   = nullptr;
        rtType.attributes.count = 0;

        entry.funcParamsOffset = 0;
        entry.funcParamsCount  = static_cast<uint32_t>(parameters.size());
        entry.funcParamTypes.clear();
        entry.funcReturnTypeRef = TypeRef::invalid();

        if (!parameters.empty())
        {
            const auto [paramsOffset, paramsPtr] = storage.reserveSpan<Runtime::TypeValue>(entry.funcParamsCount);
            entry.funcParamsOffset               = paramsOffset;
            rtType.parameters.ptr                = paramsPtr;
            rtType.parameters.count              = entry.funcParamsCount;
            storage.addRelocation(offset + offsetof(Runtime::TypeInfoFunc, parameters.ptr), paramsOffset);

            for (uint32_t i = 0; i < entry.funcParamsCount; ++i)
            {
                const SymbolVariable* symParam = parameters[i];
                SWC_ASSERT(symParam);

                Runtime::TypeValue& tv = paramsPtr[i];

                Utf8 paramName;
                if (symParam->idRef().isValid())
                {
                    const auto& id = ctx.idMgr().get(symParam->idRef());
                    paramName      = Utf8{id.name};
                }

                const uint32_t elemOffset = paramsOffset + static_cast<uint32_t>(i * sizeof(Runtime::TypeValue));
                tv.name.length            = storage.addString(elemOffset, offsetof(Runtime::TypeValue, name.ptr), paramName);

                entry.funcParamTypes.push_back(symParam->typeRef());
            }
        }

        if (symFunc.returnTypeRef().isValid())
        {
            const TypeRef returnTypeRef = symFunc.returnTypeRef();
            if (!ctx.typeMgr().get(returnTypeRef).isVoid())
                entry.funcReturnTypeRef = returnTypeRef;
        }
    }
}

void TypeGen::initTypeInfoPayload(Sema& sema, DataSegment& storage, Runtime::TypeInfo& rtType, uint32_t offset, LayoutKind kind, const TypeInfo& type, TypeGenCache::Entry& entry)
{
    initCommon(sema, storage, rtType, offset, type);

    switch (kind)
    {
        case LayoutKind::Native:
            initNative(*reinterpret_cast<Runtime::TypeInfoNative*>(&rtType), type);
            break;

        case LayoutKind::Enum:
            initEnum(sema, storage, *reinterpret_cast<Runtime::TypeInfoEnum*>(&rtType), offset, type, entry);
            break;

        case LayoutKind::Array:
            initArray(*reinterpret_cast<Runtime::TypeInfoArray*>(&rtType), type);
            break;

        case LayoutKind::Struct:
            initStruct(sema, storage, *reinterpret_cast<Runtime::TypeInfoStruct*>(&rtType), offset, type, entry);
            break;

        case LayoutKind::Func:
            initFunc(sema, storage, *reinterpret_cast<Runtime::TypeInfoFunc*>(&rtType), offset, type, entry);
            break;

        default:
            break;
    }
}

std::pair<uint32_t, Runtime::TypeInfo*> TypeGen::allocateTypeInfoPayload(DataSegment& storage, LayoutKind kind)
{
    switch (kind)
    {
        case LayoutKind::Native:
            return reservePayload<Runtime::TypeInfoNative>(storage, Runtime::TypeInfoKind::Native);

        case LayoutKind::Enum:
            return reservePayload<Runtime::TypeInfoEnum>(storage, Runtime::TypeInfoKind::Enum);

        case LayoutKind::Array:
            return reservePayload<Runtime::TypeInfoArray>(storage, Runtime::TypeInfoKind::Array);

        case LayoutKind::Slice:
            return reservePayload<Runtime::TypeInfoSlice>(storage, Runtime::TypeInfoKind::Slice);

        case LayoutKind::Pointer:
            return reservePayload<Runtime::TypeInfoPointer>(storage, Runtime::TypeInfoKind::Pointer);

        case LayoutKind::Interface:
        {
            const auto res   = storage.reserve<Runtime::TypeInfo>();
            res.second->kind = Runtime::TypeInfoKind::Interface;
            return res;
        }

        case LayoutKind::Struct:
            return reservePayload<Runtime::TypeInfoStruct>(storage, Runtime::TypeInfoKind::Struct);

        case LayoutKind::Alias:
            return reservePayload<Runtime::TypeInfoAlias>(storage, Runtime::TypeInfoKind::Alias);

        case LayoutKind::Variadic:
            return reservePayload<Runtime::TypeInfoVariadic>(storage, Runtime::TypeInfoKind::Variadic);

        case LayoutKind::TypedVariadic:
            return reservePayload<Runtime::TypeInfoVariadic>(storage, Runtime::TypeInfoKind::TypedVariadic);

        case LayoutKind::CodeBlock:
            return reservePayload<Runtime::TypeInfoCodeBlock>(storage, Runtime::TypeInfoKind::CodeBlock);

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

void TypeGen::wireRelocations(Sema& sema, const TypeGenCache& cache, DataSegment& storage, TypeRef key, const TypeGenCache::Entry& entry, LayoutKind kind)
{
    const TaskContext& ctx     = sema.ctx();
    TypeManager&       typeMgr = sema.typeMgr();

    switch (kind)
    {
        case LayoutKind::Enum:
        {
            const SymbolEnum& symEnum = typeMgr.get(key).payloadSymEnum();
            const TypeRef     depKey  = symEnum.underlyingTypeRef();
            const auto&       dep     = requireCacheEntry(cache, depKey);
            addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoEnum, rawType), dep.offset);

            exportAttributes(sema, cache, storage, entry.offset, offsetof(Runtime::TypeInfoEnum, attributes), symEnum.attributes());

            if (entry.enumValuesCount && entry.enumValuesOffset)
            {
                const auto values = collectEnumValues(symEnum);
                SWC_ASSERT(values.size() == entry.enumValuesCount);

                for (uint32_t i = 0; i < entry.enumValuesCount; ++i)
                {
                    const uint32_t elemOffset = entry.enumValuesOffset + static_cast<uint32_t>(i * sizeof(Runtime::TypeValue));
                    exportAttributes(sema, cache, storage, elemOffset, offsetof(Runtime::TypeValue, attributes), values[i]->attributes());
                }
            }

            break;
        }

        case LayoutKind::Pointer:
        {
            const TypeRef depKey = pointerLayoutDepTypeRef(typeMgr, typeMgr.get(key));
            const auto&   dep    = requireCacheEntry(cache, depKey);
            addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoPointer, pointedType), dep.offset);
            break;
        }

        case LayoutKind::Slice:
            addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoSlice, pointedType), payloadDepEntry(typeMgr, cache, key).offset);
            break;

        case LayoutKind::Array:
        {
            const TypeInfo& type           = typeMgr.get(key);
            const TypeRef   pointedTypeRef = resolveArrayPointedTypeRef(typeMgr, type);
            const auto&     dep            = requireCacheEntry(cache, pointedTypeRef);
            addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoArray, pointedType), dep.offset);

            const TypeRef finalTypeRef = resolveArrayFinalTypeRef(typeMgr, ctx, type);
            const auto&   fin          = requireCacheEntry(cache, finalTypeRef);
            addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoArray, finalType), fin.offset);
            break;
        }

        case LayoutKind::Alias:
            addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoAlias, rawType), payloadDepEntry(typeMgr, cache, key).offset);
            break;

        case LayoutKind::TypedVariadic:
            addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoVariadic, rawType), payloadDepEntry(typeMgr, cache, key).offset);
            break;

        case LayoutKind::CodeBlock:
            addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoCodeBlock, rawType), payloadDepEntry(typeMgr, cache, key).offset);
            break;

        case LayoutKind::Struct:
        {
            // Wire each 'TypeValue.pointedType' of 'fields' and 'usingFields'.
            SWC_ASSERT(entry.structFieldTypes.size() == entry.structFieldsCount);
            SWC_ASSERT(entry.usingFieldTypes.size() == entry.usingFieldsCount);
            wireTypeValueArrayPointedRelocations(cache, storage, entry.structFieldTypes, entry.structFieldsOffset);
            wireTypeValueArrayPointedRelocations(cache, storage, entry.usingFieldTypes, entry.usingFieldsOffset);

            const TypeInfo& keyType = typeMgr.get(key);
            if (keyType.isAggregateStruct())
                break;

            const SymbolStruct& symStruct = keyType.payloadSymStruct();
            exportAttributes(sema, cache, storage, entry.offset, offsetof(Runtime::TypeInfoStruct, attributes), symStruct.attributes());

            uint32_t usingIndex = 0;
            for (uint32_t i = 0; i < symStruct.fields().size(); ++i)
            {
                const SymbolVariable* field = symStruct.fields()[i];
                SWC_ASSERT(field);

                const uint32_t elemOffset = entry.structFieldsOffset + static_cast<uint32_t>(i * sizeof(Runtime::TypeValue));
                exportAttributes(sema, cache, storage, elemOffset, offsetof(Runtime::TypeValue, attributes), field->attributes());

                if (!field->isUsingField())
                    continue;

                SWC_ASSERT(usingIndex < entry.usingFieldsCount);
                const uint32_t usingElemOffset = entry.usingFieldsOffset + static_cast<uint32_t>(usingIndex * sizeof(Runtime::TypeValue));
                exportAttributes(sema, cache, storage, usingElemOffset, offsetof(Runtime::TypeValue, attributes), field->attributes());
                ++usingIndex;
            }

            break;
        }

        case LayoutKind::Func:
        {
            SWC_ASSERT(entry.funcParamTypes.size() == entry.funcParamsCount);
            wireTypeValueArrayPointedRelocations(cache, storage, entry.funcParamTypes, entry.funcParamsOffset);

            if (entry.funcReturnTypeRef.isValid())
            {
                const auto& dep = requireCacheEntry(cache, entry.funcReturnTypeRef);
                addTypeRelocation(storage, entry.offset, offsetof(Runtime::TypeInfoFunc, returnType), dep.offset);
            }

            const SymbolFunction& symFunc = typeMgr.get(key).payloadSymFunction();
            if (!symFunc.isAttribute())
                exportAttributes(sema, cache, storage, entry.offset, offsetof(Runtime::TypeInfoFunc, attributes), symFunc.attributes());

            for (uint32_t i = 0; i < symFunc.parameters().size(); ++i)
            {
                const SymbolVariable* param = symFunc.parameters()[i];
                SWC_ASSERT(param);

                const uint32_t elemOffset = entry.funcParamsOffset + static_cast<uint32_t>(i * sizeof(Runtime::TypeValue));
                exportAttributes(sema, cache, storage, elemOffset, offsetof(Runtime::TypeValue, attributes), param->attributes());
            }

            break;
        }

        default:
            break;
    }
}

SWC_END_NAMESPACE();
