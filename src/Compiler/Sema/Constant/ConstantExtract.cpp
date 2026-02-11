#include "pch.h"
#include "Compiler/Sema/Constant/ConstantExtract.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Struct.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result failStructMemberType(Sema& sema, const SymbolVariable& symVar, AstNodeRef nodeMemberRef)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_cst_struct_member_type, nodeMemberRef);
        diag.addArgument(Diagnostic::ARG_TYPE, symVar.typeRef());
        diag.report(sema.ctx());
        return Result::Error;
    }

    ConstantRef makeStructConstantFromBytes(Sema& sema, TypeRef structTypeRef, ByteSpan bytes)
    {
        auto&           ctx        = sema.ctx();
        const TypeInfo& structType = sema.typeMgr().get(structTypeRef);
        SWC_ASSERT(structType.isStruct());
        SWC_ASSERT(structType.sizeOf(ctx) <= bytes.size());

        const ConstantValue cv = ConstantValue::makeStructBorrowed(ctx, structTypeRef, bytes);
        return sema.cstMgr().addConstant(ctx, cv);
    }

    ConstantRef makeArrayConstantFromBytes(Sema& sema, TypeRef arrayTypeRef, ByteSpan bytes)
    {
        auto&           ctx       = sema.ctx();
        const TypeInfo& arrayType = sema.typeMgr().get(arrayTypeRef);
        SWC_ASSERT(arrayType.isArray());
        SWC_ASSERT(arrayType.sizeOf(ctx) <= bytes.size());

        const ConstantValue cv = ConstantValue::makeArrayBorrowed(ctx, arrayTypeRef, bytes);
        return sema.cstMgr().addConstant(ctx, cv);
    }

    Result getStructBytesFromConstant(Sema& sema, ByteSpan& bytes, const ConstantValue& cst, const SymbolVariable& symVar, AstNodeRef nodeMemberRef)
    {
        if (cst.isStruct())
        {
            bytes = cst.getStruct();
            return Result::Continue;
        }

        if (cst.isValuePointer() || cst.isBlockPointer())
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
            bytes = ByteSpan{reinterpret_cast<const std::byte*>(static_cast<uintptr_t>(ptr)), pointedType.sizeOf(sema.ctx())};
            return Result::Continue;
        }

        if (cst.isSlice())
        {
            bytes = cst.getSlice();
            return Result::Continue;
        }

        return failStructMemberType(sema, symVar, nodeMemberRef);
    }

    Result extractAggregateStructMember(Sema& sema, const ConstantValue& cst, const SymbolVariable& symVar, ConstantRef& outCstRef, AstNodeRef nodeMemberRef)
    {
        const auto& values = cst.getAggregateStruct();
        const auto* owner  = symVar.ownerSymMap();
        const auto* sym    = owner ? owner->safeCast<SymbolStruct>() : nullptr;
        if (!sym)
        {
            return failStructMemberType(sema, symVar, nodeMemberRef);
        }

        size_t      fieldIndex = 0;
        const auto& fields     = sym->fields();
        const auto  it         = std::ranges::find_if(fields, [&](const auto* field) {
            return field == &symVar;
        });

        if (it == fields.end())
        {
            return failStructMemberType(sema, symVar, nodeMemberRef);
        }

        fieldIndex = static_cast<size_t>(std::distance(fields.begin(), it));
        if (std::cmp_greater_equal(fieldIndex, values.size()))
        {
            return failStructMemberType(sema, symVar, nodeMemberRef);
        }

        outCstRef = values[fieldIndex];
        return Result::Continue;
    }

    Result makeFieldConstantFromBytes(Sema& sema, TypeRef fieldTypeRef, const TypeInfo& typeField, ByteSpan bytes, ConstantRef& outCstRef, const SymbolVariable& symVar, AstNodeRef nodeMemberRef)
    {
        auto& ctx = sema.ctx();
        if (typeField.isArray())
        {
            outCstRef = makeArrayConstantFromBytes(sema, fieldTypeRef, bytes);
            if (outCstRef.isInvalid())
                return failStructMemberType(sema, symVar, nodeMemberRef);
            return Result::Continue;
        }
        if (typeField.isStruct())
        {
            outCstRef = makeStructConstantFromBytes(sema, fieldTypeRef, bytes);
            if (outCstRef.isInvalid())
                return failStructMemberType(sema, symVar, nodeMemberRef);
            return Result::Continue;
        }

        TypeRef valueTypeRef = fieldTypeRef;
        if (typeField.isEnum())
            valueTypeRef = typeField.payloadSymEnum().underlyingTypeRef();

        ConstantValue cv = ConstantValue::make(ctx, bytes.data(), valueTypeRef, ConstantValue::PayloadOwnership::Borrowed);
        if (!cv.isValid())
            return failStructMemberType(sema, symVar, nodeMemberRef);

        ConstantRef cstRef = sema.cstMgr().addConstant(ctx, cv);
        if (typeField.isEnum())
        {
            ConstantValue enumCv = ConstantValue::makeEnumValue(ctx, cstRef, valueTypeRef);
            enumCv.setTypeRef(fieldTypeRef);
            cstRef = sema.cstMgr().addConstant(ctx, enumCv);
        }

        outCstRef = cstRef;
        return Result::Continue;
    }
}

Result ConstantExtract::structMember(Sema& sema, const ConstantValue& cst, const SymbolVariable& symVar, ConstantRef& outCstRef, AstNodeRef nodeMemberRef)
{
    auto& ctx = sema.ctx();
    outCstRef = ConstantRef::invalid();

    if (cst.isAggregateStruct())
    {
        return extractAggregateStructMember(sema, cst, symVar, outCstRef, nodeMemberRef);
    }

    ByteSpan bytes;
    RESULT_VERIFY(getStructBytesFromConstant(sema, bytes, cst, symVar, nodeMemberRef));

    const TypeInfo& typeVar   = symVar.typeInfo(ctx);
    const TypeInfo* typeField = &typeVar;
    SWC_ASSERT(symVar.offset() + typeField->sizeOf(ctx) <= bytes.size());
    const auto fieldBytes = ByteSpan{bytes.data() + symVar.offset(), typeField->sizeOf(ctx)};

    ConstantRef cstRef = ConstantRef::invalid();
    RESULT_VERIFY(makeFieldConstantFromBytes(sema, symVar.typeRef(), *typeField, fieldBytes, cstRef, symVar, nodeMemberRef));
    outCstRef = cstRef;
    return Result::Continue;
}

Result ConstantExtract::structMember(Sema& sema, const ConstantValue& cst, const SymbolVariable& symVar, AstNodeRef nodeRef, AstNodeRef nodeMemberRef)
{
    ConstantRef cstRef = ConstantRef::invalid();
    RESULT_VERIFY(structMember(sema, cst, symVar, cstRef, nodeMemberRef));
    if (cstRef.isValid())
        sema.setConstant(nodeRef, cstRef);
    return Result::Continue;
}

namespace
{
    Result extractAtIndexAggregateArray(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef, ConstantRef& outCstRef)
    {
        const auto& values = cst.getAggregateArray();
        if (std::cmp_greater_equal(constIndex, values.size()))
            return SemaError::raiseIndexOutOfRange(sema, nodeArgRef, constIndex, values.size());
        outCstRef = values[constIndex];
        return Result::Continue;
    }

    Result extractAtIndexString(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef, ConstantRef& outCstRef)
    {
        const std::string_view s = cst.getString();
        if (std::cmp_greater_equal(constIndex, s.size()))
            return SemaError::raiseIndexOutOfRange(sema, nodeArgRef, constIndex, s.size());
        const ConstantValue cstInt = ConstantValue::makeIntSized(sema.ctx(), static_cast<uint8_t>(s[constIndex]));
        outCstRef                  = sema.cstMgr().addConstant(sema.ctx(), cstInt);
        return Result::Continue;
    }

    Result extractAtIndexBytes(Sema& sema, ByteSpan bytes, TypeRef elemTypeRef, int64_t constIndex, uint64_t count, AstNodeRef nodeArgRef, ConstantRef& outCstRef)
    {
        auto&           ctx      = sema.ctx();
        const TypeInfo& elemType = sema.typeMgr().get(elemTypeRef);
        RESULT_VERIFY(sema.waitCompleted(&elemType, nodeArgRef));
        const uint64_t elemSize = elemType.sizeOf(ctx);
        SWC_ASSERT(elemSize);

        if (std::cmp_greater_equal(constIndex, count))
            return SemaError::raiseIndexOutOfRange(sema, nodeArgRef, constIndex, count);

        const auto  elemBytes  = ByteSpan{bytes.data() + (constIndex * elemSize), elemSize};
        ConstantRef elemCstRef = ConstantRef::invalid();

        if (elemType.isArray())
        {
            elemCstRef = makeArrayConstantFromBytes(sema, elemTypeRef, elemBytes);
        }
        else if (elemType.isStruct())
        {
            elemCstRef = makeStructConstantFromBytes(sema, elemTypeRef, elemBytes);
        }
        else
        {
            TypeRef valueTypeRef = elemTypeRef;
            if (elemType.isEnum())
                valueTypeRef = elemType.payloadSymEnum().underlyingTypeRef();

            ConstantValue cv = ConstantValue::make(ctx, elemBytes.data(), valueTypeRef, ConstantValue::PayloadOwnership::Borrowed);
            if (!cv.isValid())
                return Result::Continue;

            elemCstRef = sema.cstMgr().addConstant(ctx, cv);

            if (elemType.isEnum())
            {
                ConstantValue enumCv = ConstantValue::makeEnumValue(ctx, elemCstRef, elemTypeRef);
                enumCv.setTypeRef(elemTypeRef);
                elemCstRef = sema.cstMgr().addConstant(ctx, enumCv);
            }
        }

        if (elemCstRef.isInvalid())
            return Result::Continue;

        outCstRef = elemCstRef;
        return Result::Continue;
    }

    Result extractAtIndexArray(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef, ConstantRef& outCstRef)
    {
        const TypeInfo& typeInfo = sema.typeMgr().get(cst.typeRef());
        const auto&     dims     = typeInfo.payloadArrayDims();
        if (dims.size() > 1)
        {
            std::vector<uint64_t> subDims;
            subDims.reserve(dims.size() - 1);
            for (size_t i = 1; i < dims.size(); ++i)
                subDims.push_back(dims[i]);

            const TypeInfo subArrayType = TypeInfo::makeArray(subDims, typeInfo.payloadArrayElemTypeRef(), typeInfo.flags());
            const TypeRef  subArrayRef  = sema.typeMgr().addType(subArrayType);
            const uint64_t count        = dims.empty() ? 0 : dims[0];
            return extractAtIndexBytes(sema, cst.getArray(), subArrayRef, constIndex, count, nodeArgRef, outCstRef);
        }

        const uint64_t count = dims.empty() ? 0 : dims[0];
        return extractAtIndexBytes(sema, cst.getArray(), typeInfo.payloadArrayElemTypeRef(), constIndex, count, nodeArgRef, outCstRef);
    }

    Result extractAtIndexSlice(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef, ConstantRef& outCstRef)
    {
        const TypeInfo& typeInfo = sema.typeMgr().get(cst.typeRef());
        const ByteSpan  bytes    = cst.getSlice();
        return extractAtIndexBytes(sema, bytes, typeInfo.payloadTypeRef(), constIndex, bytes.size(), nodeArgRef, outCstRef);
    }
}

Result ConstantExtract::atIndex(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef, ConstantRef& outCstRef)
{
    SWC_ASSERT(cst.isValid());
    outCstRef = ConstantRef::invalid();

    if (cst.isAggregateArray())
        return extractAtIndexAggregateArray(sema, cst, constIndex, nodeArgRef, outCstRef);
    if (cst.isArray())
        return extractAtIndexArray(sema, cst, constIndex, nodeArgRef, outCstRef);
    if (cst.isString())
        return extractAtIndexString(sema, cst, constIndex, nodeArgRef, outCstRef);
    if (cst.isSlice())
        return extractAtIndexSlice(sema, cst, constIndex, nodeArgRef, outCstRef);

    return SemaError::raiseTypeNotIndexable(sema, sema.curNodeRef(), cst.typeRef());
}

Result ConstantExtract::atIndex(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef)
{
    ConstantRef cstRef = ConstantRef::invalid();
    RESULT_VERIFY(atIndex(sema, cst, constIndex, nodeArgRef, cstRef));
    if (cstRef.isValid())
        sema.setConstant(sema.curNodeRef(), cstRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
