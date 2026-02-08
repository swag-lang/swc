#include "pch.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"
#include "Runtime/Runtime.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    void lowerConstantToBytes(Sema& sema, ByteSpan dstBytes, TypeRef dstTypeRef, ConstantRef cstRef);

    bool lowerAggregateArrayToBytesInternal(Sema& sema, ByteSpan dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values)
    {
        auto&           ctx         = sema.ctx();
        const auto      elemTypeRef = dstType.payloadArrayElemTypeRef();
        const TypeInfo& elemType    = sema.typeMgr().get(elemTypeRef);
        const uint64_t  elemSize    = elemType.sizeOf(ctx);
        uint64_t        totalCount  = 1;
        const auto&     dims        = dstType.payloadArrayDims();

        for (const auto dim : dims)
            totalCount *= dim;

        if (elemSize && elemSize * totalCount > dstBytes.size())
            return false;

        const uint64_t maxCount = std::min<uint64_t>(values.size(), totalCount);
        for (uint64_t i = 0; i < maxCount; ++i)
        {
            lowerConstantToBytes(sema, ByteSpan{dstBytes.data() + (i * elemSize), elemSize}, elemTypeRef, values[i]);
        }

        return true;
    }

    void lowerConstantToBytes(Sema& sema, ByteSpan dstBytes, TypeRef dstTypeRef, ConstantRef cstRef)
    {
        const ConstantValue& cst     = sema.cstMgr().get(cstRef);
        const TypeInfo&      dstType = sema.typeMgr().get(dstTypeRef);

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
                if (bytes.size() != dstBytes.size())
                {
                    SWC_ASSERT(false);
                    return;
                }
                if (!dstBytes.empty())
                    std::memcpy(const_cast<std::byte*>(dstBytes.data()), bytes.data(), dstBytes.size());
                return;
            }

            if (cst.isAggregateStruct())
            {
                ConstantHelpers::lowerAggregateStructToBytes(sema, dstBytes, dstType, cst.getAggregateStruct());
                return;
            }

            SWC_ASSERT(false);
            return;
        }

        if (dstType.isArray())
        {
            if (!cst.isAggregateArray())
            {
                SWC_ASSERT(false);
                return;
            }
            if (!lowerAggregateArrayToBytesInternal(sema, dstBytes, dstType, cst.getAggregateArray()))
            {
                SWC_ASSERT(false);
                return;
            }
            return;
        }

        if (dstType.isBool())
        {
            if (!cst.isBool() || dstBytes.size() != 1)
            {
                SWC_ASSERT(false);
                return;
            }
            const uint8_t v = cst.getBool() ? 1 : 0;
            std::memcpy(const_cast<std::byte*>(dstBytes.data()), &v, sizeof(v));
            return;
        }

        if (dstType.isChar())
        {
            if (!cst.isChar() || dstBytes.size() != sizeof(char32_t))
            {
                SWC_ASSERT(false);
                return;
            }
            const char32_t v = cst.getChar();
            std::memcpy(const_cast<std::byte*>(dstBytes.data()), &v, sizeof(v));
            return;
        }

        if (dstType.isRune())
        {
            if (!cst.isRune() || dstBytes.size() != sizeof(char32_t))
            {
                SWC_ASSERT(false);
                return;
            }
            const char32_t v = cst.getRune();
            std::memcpy(const_cast<std::byte*>(dstBytes.data()), &v, sizeof(v));
            return;
        }

        if (dstType.isInt())
        {
            if (!cst.isInt())
            {
                SWC_ASSERT(false);
                return;
            }
            const uint64_t v = cst.getInt().as64();
            if (dstBytes.size() > sizeof(v))
            {
                SWC_ASSERT(false);
                return;
            }
            std::memcpy(const_cast<std::byte*>(dstBytes.data()), &v, dstBytes.size());
            return;
        }

        if (dstType.isFloat())
        {
            if (!cst.isFloat())
            {
                SWC_ASSERT(false);
                return;
            }
            if (dstType.payloadFloatBits() == 32)
            {
                const float v = cst.getFloat().asFloat();
                if (dstBytes.size() != sizeof(v))
                {
                    SWC_ASSERT(false);
                    return;
                }
                std::memcpy(const_cast<std::byte*>(dstBytes.data()), &v, sizeof(v));
                return;
            }

            if (dstType.payloadFloatBits() == 64)
            {
                const double v = cst.getFloat().asDouble();
                if (dstBytes.size() != sizeof(v))
                {
                    SWC_ASSERT(false);
                    return;
                }
                std::memcpy(const_cast<std::byte*>(dstBytes.data()), &v, sizeof(v));
                return;
            }

            SWC_ASSERT(false);
            return;
        }

        if (dstType.isString())
        {
            if (!cst.isString() || dstBytes.size() != sizeof(Runtime::String))
            {
                SWC_ASSERT(false);
                return;
            }
            const std::string_view str = cst.getString();
            const Runtime::String  rt  = {.ptr = str.data(), .length = str.size()};
            std::memcpy(const_cast<std::byte*>(dstBytes.data()), &rt, sizeof(rt));
            return;
        }

        if (dstType.isSlice())
        {
            if (!cst.isSlice() || dstBytes.size() != sizeof(Runtime::Slice<uint8_t>))
            {
                SWC_ASSERT(false);
                return;
            }
            const ByteSpan       bytes = cst.getSlice();
            const Runtime::Slice rt    = {.ptr = reinterpret_cast<uint8_t*>(const_cast<std::byte*>(bytes.data())), .count = bytes.size()};
            std::memcpy(const_cast<std::byte*>(dstBytes.data()), &rt, sizeof(rt));
            return;
        }

        if (dstType.isAnyPointer() || dstType.isReference() || dstType.isTypeInfo() || dstType.isCString())
        {
            if (dstBytes.size() != sizeof(uint64_t))
            {
                SWC_ASSERT(false);
                return;
            }
            uint64_t ptr = 0;
            if (cst.isNull())
                ptr = 0;
            else if (cst.isValuePointer())
                ptr = cst.getValuePointer();
            else if (cst.isBlockPointer())
                ptr = cst.getBlockPointer();
            else
            {
                SWC_ASSERT(false);
                return;
            }
            std::memcpy(const_cast<std::byte*>(dstBytes.data()), &ptr, sizeof(ptr));
            return;
        }

        SWC_ASSERT(false);
        return;
    }
}

Result ConstantHelpers::extractStructMember(Sema& sema, const ConstantValue& cst, const SymbolVariable& symVar, AstNodeRef nodeRef, AstNodeRef nodeMemberRef)
{
    auto&    ctx = sema.ctx();
    ByteSpan bytes;
    if (cst.isStruct())
    {
        bytes = cst.getStruct();
    }
    else if (cst.isValuePointer() || cst.isBlockPointer())
    {
        const TypeInfo& cstType = sema.typeMgr().get(cst.typeRef());
        TypeRef         pointedTypeRef;
        if (cstType.isAnyPointer())
            pointedTypeRef = cstType.payloadTypeRef();
        else if (cstType.isTypeInfo())
            pointedTypeRef = sema.typeMgr().structTypeInfo();
        else
            SWC_UNREACHABLE();

        const TypeInfo& pointedType = sema.typeMgr().get(pointedTypeRef);
        SWC_ASSERT(pointedType.isStruct());
        const uint64_t ptr = cst.isValuePointer() ? cst.getValuePointer() : cst.getBlockPointer();
        SWC_ASSERT(ptr);
        bytes = ByteSpan{reinterpret_cast<const std::byte*>(static_cast<uintptr_t>(ptr)), pointedType.sizeOf(ctx)};
    }
    else if (cst.isSlice())
    {
        bytes = cst.getSlice();
    }
    else if (cst.isAggregateStruct())
    {
        const auto& values = cst.getAggregateStruct();
        const auto* owner  = symVar.ownerSymMap();
        const auto* sym    = owner ? owner->safeCast<SymbolStruct>() : nullptr;
        if (!sym)
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_cst_struct_member_type, nodeMemberRef);
            diag.addArgument(Diagnostic::ARG_TYPE, symVar.typeRef());
            diag.report(ctx);
            return Result::Error;
        }

        size_t fieldIndex = 0;
        bool   found      = false;
        for (const auto* field : sym->fields())
        {
            if (!field || field->isIgnored())
                continue;

            if (field == &symVar)
            {
                found = true;
                break;
            }

            ++fieldIndex;
        }

        if (!found || std::cmp_greater_equal(fieldIndex, values.size()))
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_cst_struct_member_type, nodeMemberRef);
            diag.addArgument(Diagnostic::ARG_TYPE, symVar.typeRef());
            diag.report(ctx);
            return Result::Error;
        }

        sema.setConstant(nodeRef, values[fieldIndex]);
        return Result::Continue;
    }
    else
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_cst_struct_member_type, nodeMemberRef);
        diag.addArgument(Diagnostic::ARG_TYPE, symVar.typeRef());
        diag.report(ctx);
        return Result::Error;
    }

    const TypeInfo& typeVar   = symVar.typeInfo(ctx);
    const TypeInfo* typeField = &typeVar;
    SWC_ASSERT(symVar.offset() + typeField->sizeOf(ctx) <= bytes.size());
    const auto fieldBytes = ByteSpan{bytes.data() + symVar.offset(), typeField->sizeOf(ctx)};

    TypeRef valueTypeRef = symVar.typeRef();
    if (typeField->isEnum())
    {
        valueTypeRef = typeField->payloadSymEnum().underlyingTypeRef();
        typeField    = &sema.typeMgr().get(typeField->payloadSymEnum().underlyingTypeRef());
    }

    ConstantValue cv = ConstantValue::make(ctx, fieldBytes.data(), valueTypeRef, ConstantValue::PayloadOwnership::Borrowed);
    if (!cv.isValid())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_cst_struct_member_type, nodeMemberRef);
        diag.addArgument(Diagnostic::ARG_TYPE, symVar.typeRef());
        diag.report(sema.ctx());
        return Result::Error;
    }

    ConstantRef cstRef = sema.cstMgr().addConstant(ctx, cv);

    if (typeVar.isEnum())
    {
        cv = ConstantValue::makeEnumValue(ctx, cstRef, typeVar.payloadSymEnum().underlyingTypeRef());
        cv.setTypeRef(symVar.typeRef());
        cstRef = sema.cstMgr().addConstant(ctx, cv);
    }

    sema.setConstant(nodeRef, cstRef);
    return Result::Continue;
}

Result ConstantHelpers::extractAtIndex(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef)
{
    SWC_ASSERT(cst.isValid());
    const TypeInfo& typeInfo = sema.typeMgr().get(cst.typeRef());

    if (cst.isAggregateArray())
    {
        if (typeInfo.payloadArrayDims().size() > 1)
            return Result::Continue;
        const auto& values = cst.getAggregateArray();
        if (std::cmp_greater_equal(constIndex, values.size()))
            return SemaError::raiseIndexOutOfRange(sema, nodeArgRef, constIndex, values.size());
        sema.setConstant(sema.curNodeRef(), values[constIndex]);
        return Result::Continue;
    }

    if (cst.isString())
    {
        const std::string_view s = cst.getString();
        if (std::cmp_greater_equal(constIndex, s.size()))
            return SemaError::raiseIndexOutOfRange(sema, nodeArgRef, constIndex, s.size());
        const ConstantValue cstInt = ConstantValue::makeIntSized(sema.ctx(), static_cast<uint8_t>(s[constIndex]));
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(sema.ctx(), cstInt));
        return Result::Continue;
    }

    if (cst.isSlice())
    {
        auto&          ctx         = sema.ctx();
        const TypeRef  elemTypeRef = typeInfo.payloadTypeRef();
        const TypeInfo elemType    = sema.typeMgr().get(elemTypeRef);
        const uint64_t elemSize    = elemType.sizeOf(ctx);
        SWC_ASSERT(elemSize);

        const ByteSpan bytes      = cst.getSlice();
        const uint64_t numEntries = bytes.size();
        if (std::cmp_greater_equal(constIndex, numEntries))
            return SemaError::raiseIndexOutOfRange(sema, nodeArgRef, constIndex, numEntries);

        const auto elemBytes = ByteSpan{bytes.data() + (constIndex * elemSize), elemSize};

        TypeRef valueTypeRef = elemTypeRef;
        if (elemType.isEnum())
            valueTypeRef = elemType.payloadSymEnum().underlyingTypeRef();

        const ConstantValue cv = ConstantValue::make(ctx, elemBytes.data(), valueTypeRef, ConstantValue::PayloadOwnership::Borrowed);
        if (!cv.isValid())
            return Result::Continue;

        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, cv));
        return Result::Continue;
    }

    return Result::Continue;
}

void ConstantHelpers::lowerToBytes(Sema& sema, ByteSpan dstBytes, ConstantRef cstRef, TypeRef dstTypeRef)
{
    lowerConstantToBytes(sema, dstBytes, dstTypeRef, cstRef);
}

bool ConstantHelpers::lowerAggregateArrayToBytes(Sema& sema, ByteSpan dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values)
{
    return lowerAggregateArrayToBytesInternal(sema, dstBytes, dstType, values);
}

void ConstantHelpers::lowerAggregateStructToBytes(Sema& sema, ByteSpan dstBytes, const TypeInfo& dstType, const std::vector<ConstantRef>& values)
{
    const auto& dstFields = dstType.payloadSymStruct().fields();
    size_t      valueIdx  = 0;

    for (const auto* field : dstFields)
    {
        if (!field || field->isIgnored())
            continue;

        const TypeRef   fieldTypeRef = field->typeRef();
        const TypeInfo& fieldType    = sema.typeMgr().get(fieldTypeRef);
        const uint64_t  fieldSize    = fieldType.sizeOf(sema.ctx());
        const uint64_t  fieldOffset  = field->offset();
        if (fieldOffset + fieldSize > dstBytes.size())
        {
            SWC_ASSERT(false);
            return;
        }

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

ConstantRef ConstantHelpers::makeDefaultStruct(Sema& sema, TypeRef typeRef)
{
    const auto& type = sema.typeMgr().get(typeRef);
    SWC_ASSERT(type.isStruct());

    const uint64_t structSize = type.sizeOf(sema.ctx());
    SWC_ASSERT(structSize);

    const std::vector<std::byte> buffer(structSize);
    const auto                   bytes = asByteSpan(buffer);
    lowerAggregateStructToBytes(sema, bytes, type, {});
    const auto cstVal = ConstantValue::makeStruct(sema.ctx(), typeRef, bytes);
    return sema.cstMgr().addConstant(sema.ctx(), cstVal);
}

ConstantRef ConstantHelpers::makeConstantLocation(Sema& sema, const AstNode& node)
{
    auto&                 ctx       = sema.ctx();
    const SourceCodeRange codeRange = node.codeRangeWithChildren(ctx, sema.ast());
    const TypeRef         typeRef   = sema.typeMgr().structSourceCodeLocation();

    Runtime::SourceCodeLocation rtLoc;

    const std::string_view nameView = sema.cstMgr().addString(ctx, codeRange.srcView->file()->path().string());
    rtLoc.fileName.ptr              = nameView.data();
    rtLoc.fileName.length           = nameView.size();

    rtLoc.funcName.ptr    = nullptr;
    rtLoc.funcName.length = 0;

    rtLoc.lineStart = codeRange.line;
    rtLoc.colStart  = codeRange.column;
    rtLoc.lineEnd   = codeRange.line;
    rtLoc.colEnd    = codeRange.column + codeRange.len;

    const auto view   = ByteSpan{reinterpret_cast<const std::byte*>(&rtLoc), sizeof(rtLoc)};
    const auto cstVal = ConstantValue::makeStruct(ctx, typeRef, view);
    return sema.cstMgr().addConstant(ctx, cstVal);
}

SWC_END_NAMESPACE();
