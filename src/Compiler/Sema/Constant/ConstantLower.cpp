#include "pch.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Backend/Runtime.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void lowerConstantToBytes(Sema& sema, ByteSpan dstBytes, TypeRef dstTypeRef, ConstantRef cstRef);

    void lowerAggregateArrayToBytesInternal(Sema& sema, ByteSpan dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values)
    {
        auto&           ctx         = sema.ctx();
        const auto      elemTypeRef = dstType.payloadArrayElemTypeRef();
        const TypeInfo& elemType    = sema.typeMgr().get(elemTypeRef);
        const uint64_t  elemSize    = elemType.sizeOf(ctx);
        uint64_t        totalCount  = 1;
        const auto&     dims        = dstType.payloadArrayDims();

        for (const auto dim : dims)
            totalCount *= dim;

        SWC_ASSERT(!elemSize || elemSize * totalCount <= dstBytes.size());

        const uint64_t maxCount = std::min<uint64_t>(values.size(), totalCount);
        for (uint64_t i = 0; i < maxCount; ++i)
        {
            lowerConstantToBytes(sema, ByteSpan{dstBytes.data() + (i * elemSize), elemSize}, elemTypeRef, values[i]);
        }

        return;
    }

    void lowerConstantToBytes(Sema& sema, ByteSpan dstBytes, TypeRef dstTypeRef, ConstantRef cstRef)
    {
        const ConstantValue& cst = sema.cstMgr().get(cstRef);
        if (cst.isUndefined())
            return;

        const TypeInfo& dstType = sema.typeMgr().get(dstTypeRef);

        if (dstType.isEnum())
        {
            const TypeRef underlyingTypeRef = dstType.payloadSymEnum().underlyingTypeRef();
            ConstantRef   enumValueRef      = cstRef;
            if (cst.isEnumValue())
                enumValueRef = cst.getEnumValue();
            lowerConstantToBytes(sema, dstBytes, underlyingTypeRef, enumValueRef);
            return;
        }

        if (dstType.isStruct())
        {
            if (cst.isStruct())
            {
                const auto bytes = cst.getStruct();
                SWC_ASSERT(bytes.size() == dstBytes.size());
                if (!dstBytes.empty())
                    std::memcpy(const_cast<std::byte*>(dstBytes.data()), bytes.data(), dstBytes.size());
                return;
            }

            if (cst.isAggregateStruct())
            {
                ConstantLower::lowerAggregateStructToBytes(sema, dstBytes, dstType, cst.getAggregateStruct());
                return;
            }

            SWC_ASSERT(cst.isStruct() || cst.isAggregateStruct());
            return;
        }

        if (dstType.isArray())
        {
            if (cst.isArray())
            {
                const auto bytes = cst.getArray();
                SWC_ASSERT(bytes.size() == dstBytes.size());
                if (!dstBytes.empty())
                    std::memcpy(const_cast<std::byte*>(dstBytes.data()), bytes.data(), dstBytes.size());
                return;
            }

            SWC_ASSERT(cst.isAggregateArray());
            lowerAggregateArrayToBytesInternal(sema, dstBytes, dstType, cst.getAggregateArray());
            return;
        }

        if (dstType.isBool())
        {
            SWC_ASSERT(cst.isBool() && dstBytes.size() == 1);
            const uint8_t v = cst.getBool() ? 1 : 0;
            std::memcpy(const_cast<std::byte*>(dstBytes.data()), &v, sizeof(v));
            return;
        }

        if (dstType.isChar())
        {
            SWC_ASSERT(cst.isChar() && dstBytes.size() == sizeof(char32_t));
            const char32_t v = cst.getChar();
            std::memcpy(const_cast<std::byte*>(dstBytes.data()), &v, sizeof(v));
            return;
        }

        if (dstType.isRune())
        {
            SWC_ASSERT(cst.isRune() && dstBytes.size() == sizeof(char32_t));
            const char32_t v = cst.getRune();
            std::memcpy(const_cast<std::byte*>(dstBytes.data()), &v, sizeof(v));
            return;
        }

        if (dstType.isInt())
        {
            SWC_ASSERT(cst.isInt());
            const uint64_t v = cst.getInt().as64();
            SWC_ASSERT(dstBytes.size() <= sizeof(v));
            std::memcpy(const_cast<std::byte*>(dstBytes.data()), &v, dstBytes.size());
            return;
        }

        if (dstType.isFloat())
        {
            SWC_ASSERT(cst.isFloat());
            if (dstType.payloadFloatBits() == 32)
            {
                const float v = cst.getFloat().asFloat();
                SWC_ASSERT(dstBytes.size() == sizeof(v));
                std::memcpy(const_cast<std::byte*>(dstBytes.data()), &v, sizeof(v));
                return;
            }

            if (dstType.payloadFloatBits() == 64)
            {
                const double v = cst.getFloat().asDouble();
                SWC_ASSERT(dstBytes.size() == sizeof(v));
                std::memcpy(const_cast<std::byte*>(dstBytes.data()), &v, sizeof(v));
                return;
            }

            SWC_ASSERT(dstType.payloadFloatBits() == 32 || dstType.payloadFloatBits() == 64);
            return;
        }

        if (dstType.isString())
        {
            SWC_ASSERT(cst.isString() && dstBytes.size() == sizeof(Runtime::String));
            const std::string_view str = cst.getString();
            const Runtime::String  rt  = {.ptr = str.data(), .length = str.size()};
            std::memcpy(const_cast<std::byte*>(dstBytes.data()), &rt, sizeof(rt));
            return;
        }

        if (dstType.isSlice())
        {
            SWC_ASSERT(cst.isSlice() && dstBytes.size() == sizeof(Runtime::Slice<uint8_t>));
            const ByteSpan       bytes = cst.getSlice();
            const Runtime::Slice rt    = {.ptr = reinterpret_cast<uint8_t*>(const_cast<std::byte*>(bytes.data())), .count = bytes.size()};
            std::memcpy(const_cast<std::byte*>(dstBytes.data()), &rt, sizeof(rt));
            return;
        }

        if (dstType.isAnyPointer() || dstType.isReference() || dstType.isTypeInfo() || dstType.isCString())
        {
            SWC_ASSERT(dstBytes.size() == sizeof(uint64_t));
            uint64_t ptr = 0;
            if (cst.isNull())
                ptr = 0;
            else if (cst.isValuePointer())
                ptr = cst.getValuePointer();
            else if (cst.isBlockPointer())
                ptr = cst.getBlockPointer();
            SWC_ASSERT(cst.isNull() || cst.isValuePointer() || cst.isBlockPointer());
            std::memcpy(const_cast<std::byte*>(dstBytes.data()), &ptr, sizeof(ptr));
            return;
        }

        SWC_ASSERT(dstType.isEnum() || dstType.isStruct() || dstType.isArray() || dstType.isBool() || dstType.isChar() ||
                   dstType.isRune() || dstType.isInt() || dstType.isFloat() || dstType.isString() || dstType.isSlice() ||
                   dstType.isAnyPointer() || dstType.isReference() || dstType.isTypeInfo() || dstType.isCString());
        return;
    }
}

void ConstantLower::lowerToBytes(Sema& sema, ByteSpan dstBytes, ConstantRef cstRef, TypeRef dstTypeRef)
{
    lowerConstantToBytes(sema, dstBytes, dstTypeRef, cstRef);
}

void ConstantLower::lowerAggregateArrayToBytes(Sema& sema, ByteSpan dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values)
{
    lowerAggregateArrayToBytesInternal(sema, dstBytes, dstType, values);
}

void ConstantLower::lowerAggregateStructToBytes(Sema& sema, ByteSpan dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values)
{
    const auto& dstFields = dstType.payloadSymStruct().fields();
    size_t      valueIdx  = 0;

    for (const auto* field : dstFields)
    {
        if (!field)
            continue;

        const TypeRef   fieldTypeRef = field->typeRef();
        const TypeInfo& fieldType    = sema.typeMgr().get(fieldTypeRef);
        const uint64_t  fieldSize    = fieldType.sizeOf(sema.ctx());
        const uint64_t  fieldOffset  = field->offset();
        SWC_ASSERT(fieldOffset + fieldSize <= dstBytes.size());

        ConstantRef valueRef = ConstantRef::invalid();
        if (valueIdx < values.size())
        {
            valueRef = values[valueIdx];
            ++valueIdx;
        }
        else
        {
            valueRef = field->defaultValueRef();
        }

        if (valueRef.isValid())
            lowerConstantToBytes(sema, ByteSpan{dstBytes.data() + fieldOffset, fieldSize}, fieldTypeRef, valueRef);
        else if (fieldSize)
            std::memset(const_cast<std::byte*>(dstBytes.data()) + fieldOffset, 0, fieldSize);
    }
    return;
}

SWC_END_NAMESPACE();
