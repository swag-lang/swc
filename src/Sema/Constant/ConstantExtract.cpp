#include "pch.h"
#include "Sema/Constant/ConstantExtract.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/Sema.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Symbol.Enum.h"
#include "Sema/Symbol/Symbol.Variable.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

Result ConstantExtract::structMember(Sema& sema, const ConstantValue& cst, const SymbolVariable& symVar, AstNodeRef nodeRef, AstNodeRef nodeMemberRef)
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

Result ConstantExtract::atIndex(Sema& sema, const ConstantValue& cst, int64_t constIndex, AstNodeRef nodeArgRef)
{
    const TypeInfo& typeInfo = sema.typeMgr().get(cst.typeRef());

    ////////////////////////////////////////////////////////
    if (cst.isAggregateArray())
    {
        if (typeInfo.payloadArrayDims().size() > 1)
            return Result::Continue;
        const auto& values = cst.getAggregateArray();
        if (std::cmp_greater_equal(constIndex, values.size()))
            return SemaError::raiseIndexOutOfRange(sema, constIndex, values.size(), nodeArgRef);
        sema.setConstant(sema.curNodeRef(), values[constIndex]);
        return Result::Continue;
    }

    ////////////////////////////////////////////////////////
    if (cst.isString())
    {
        const std::string_view s = cst.getString();
        if (std::cmp_greater_equal(constIndex, s.size()))
            return SemaError::raiseIndexOutOfRange(sema, constIndex, s.size(), nodeArgRef);
        const ConstantValue cstInt = ConstantValue::makeIntSized(sema.ctx(), static_cast<uint8_t>(s[constIndex]));
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(sema.ctx(), cstInt));
        return Result::Continue;
    }

    ////////////////////////////////////////////////////////
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
            return SemaError::raiseIndexOutOfRange(sema, constIndex, numEntries, nodeArgRef);

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

SWC_END_NAMESPACE();
