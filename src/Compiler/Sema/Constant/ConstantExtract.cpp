#include "pch.h"
#include "Compiler/Sema/Constant/ConstantExtract.h"
#include "Compiler/Sema/Constant/ConstantHelpers.h"
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

    void extractAggregateStructMember(Sema& sema, const ConstantValue& cst, const SymbolVariable& symVar, AstNodeRef nodeRef, AstNodeRef nodeMemberRef)
    {
        const auto&      values = cst.getAggregateStruct();
        const SymbolMap* owner  = symVar.ownerSymMap();
        if (!owner || !owner->isStruct())
        {
            failStructMemberType(sema, symVar, nodeMemberRef);
            return;
        }
        const auto& sym = owner->cast<SymbolStruct>();

        size_t      fieldIndex = 0;
        const auto& fields     = sym.fields();
        const auto  it         = std::ranges::find_if(fields, [&](const SymbolVariable* field) {
            return field == &symVar;
        });

        if (it == fields.end())
        {
            failStructMemberType(sema, symVar, nodeMemberRef);
            return;
        }

        fieldIndex = static_cast<size_t>(std::distance(fields.begin(), it));
        if (std::cmp_greater_equal(fieldIndex, values.size()))
        {
            failStructMemberType(sema, symVar, nodeMemberRef);
            return;
        }

        sema.setConstant(nodeRef, values[fieldIndex]);
    }

    Result makeFieldConstantFromBytes(Sema& sema, TypeRef fieldTypeRef, const TypeInfo& typeField, ByteSpan bytes, ConstantRef& outCstRef, const SymbolVariable& symVar, AstNodeRef nodeMemberRef)
    {
        SWC_UNUSED(typeField);
        outCstRef = ConstantHelpers::materializeStaticPayloadConstant(sema, fieldTypeRef, bytes);
        if (outCstRef.isInvalid())
            return failStructMemberType(sema, symVar, nodeMemberRef);
        return Result::Continue;
    }
}

Result ConstantExtract::structMember(Sema& sema, const ConstantValue& cst, const SymbolVariable& symVar, AstNodeRef nodeRef, AstNodeRef nodeMemberRef)
{
    TaskContext& ctx = sema.ctx();

    if (cst.isAggregateStruct())
    {
        extractAggregateStructMember(sema, cst, symVar, nodeRef, nodeMemberRef);
        return Result::Continue;
    }

    ByteSpan bytes;
    SWC_RESULT(getStructBytesFromConstant(sema, bytes, cst, symVar, nodeMemberRef));

    const TypeInfo& typeVar   = symVar.typeInfo(ctx);
    const TypeInfo* typeField = &typeVar;
    SWC_ASSERT(symVar.offset() + typeField->sizeOf(ctx) <= bytes.size());
    const auto fieldBytes = ByteSpan{bytes.data() + symVar.offset(), typeField->sizeOf(ctx)};

    ConstantRef cstRef = ConstantRef::invalid();
    SWC_RESULT(makeFieldConstantFromBytes(sema, symVar.typeRef(), *typeField, fieldBytes, cstRef, symVar, nodeMemberRef));

    sema.setConstant(nodeRef, cstRef);
    return Result::Continue;
}

namespace
{
    Result extractAtIndexAggregateArray(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef)
    {
        const TypeInfo& typeInfo = sema.typeMgr().get(cst.typeRef());
        if (typeInfo.payloadArrayDims().size() > 1)
            return Result::Continue;
        const auto& values = cst.getAggregateArray();
        if (std::cmp_greater_equal(constIndex, values.size()))
            return SemaError::raiseIndexOutOfRange(sema, nodeArgRef, constIndex, values.size());
        sema.setConstant(sema.curNodeRef(), values[constIndex]);
        return Result::Continue;
    }

    Result extractAtIndexString(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef)
    {
        const std::string_view s = cst.getString();
        if (std::cmp_greater_equal(constIndex, s.size()))
            return SemaError::raiseIndexOutOfRange(sema, nodeArgRef, constIndex, s.size());
        const ConstantValue cstInt = ConstantValue::makeIntSized(sema.ctx(), static_cast<uint8_t>(s[constIndex]));
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(sema.ctx(), cstInt));
        return Result::Continue;
    }

    Result extractAtIndexBytes(Sema& sema, ByteSpan bytes, TypeRef elemTypeRef, int64_t constIndex, uint64_t count, AstNodeRef nodeArgRef)
    {
        TaskContext&    ctx      = sema.ctx();
        const TypeInfo& elemType = sema.typeMgr().get(elemTypeRef);
        SWC_RESULT(sema.waitSemaCompleted(&elemType, nodeArgRef));
        const uint64_t elemSize = elemType.sizeOf(ctx);
        SWC_ASSERT(elemSize);

        if (std::cmp_greater_equal(constIndex, count))
            return SemaError::raiseIndexOutOfRange(sema, nodeArgRef, constIndex, count);

        const auto        elemBytes  = ByteSpan{bytes.data() + (constIndex * elemSize), elemSize};
        const ConstantRef elemCstRef = ConstantHelpers::materializeStaticPayloadConstant(sema, elemTypeRef, elemBytes);

        if (elemCstRef.isInvalid())
            return Result::Continue;

        sema.setConstant(sema.curNodeRef(), elemCstRef);
        return Result::Continue;
    }

    Result extractAtIndexArray(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef)
    {
        const TypeInfo& typeInfo = sema.typeMgr().get(cst.typeRef());
        if (typeInfo.payloadArrayDims().size() > 1)
            return Result::Continue;

        const uint64_t count = typeInfo.payloadArrayDims().empty() ? 0 : typeInfo.payloadArrayDims()[0];
        return extractAtIndexBytes(sema, cst.getArray(), typeInfo.payloadArrayElemTypeRef(), constIndex, count, nodeArgRef);
    }

    Result extractAtIndexSlice(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef)
    {
        const TypeInfo& typeInfo  = sema.typeMgr().get(cst.typeRef());
        const ByteSpan  bytes     = cst.getSlice();
        const TypeInfo& elemType  = sema.typeMgr().get(typeInfo.payloadTypeRef());
        const uint64_t  elemSize  = elemType.sizeOf(sema.ctx());
        const uint64_t  elemCount = elemSize ? bytes.size() / elemSize : 0;
        return extractAtIndexBytes(sema, bytes, typeInfo.payloadTypeRef(), constIndex, elemCount, nodeArgRef);
    }

    Result extractAtIndexBlockPointer(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef)
    {
        TaskContext&    ctx      = sema.ctx();
        const TypeInfo& typeInfo = sema.typeMgr().get(cst.typeRef());
        const TypeRef   elemType = typeInfo.payloadTypeRef();
        const uint64_t  elemSize = sema.typeMgr().get(elemType).sizeOf(ctx);
        SWC_ASSERT(elemSize);

        const uint64_t ptrValue = cst.getBlockPointer();
        SWC_ASSERT(ptrValue);

        const uint64_t byteOffset = static_cast<uint64_t>(constIndex) * elemSize;
        const auto*    elemPtr    = reinterpret_cast<const std::byte*>(ptrValue + byteOffset);
        const ByteSpan elemBytes{elemPtr, elemSize};
        return extractAtIndexBytes(sema, elemBytes, elemType, 0, 1, nodeArgRef);
    }
}

Result ConstantExtract::atIndex(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef)
{
    SWC_ASSERT(cst.isValid());

    if (cst.isAggregateArray())
        return extractAtIndexAggregateArray(sema, cst, constIndex, nodeArgRef);
    if (cst.isArray())
        return extractAtIndexArray(sema, cst, constIndex, nodeArgRef);
    if (cst.isString())
        return extractAtIndexString(sema, cst, constIndex, nodeArgRef);
    if (cst.isSlice())
        return extractAtIndexSlice(sema, cst, constIndex, nodeArgRef);
    if (cst.isBlockPointer())
        return extractAtIndexBlockPointer(sema, cst, constIndex, nodeArgRef);

    return SemaError::raiseTypeNotIndexable(sema, sema.curNodeRef(), cst.typeRef());
}

SWC_END_NAMESPACE();
