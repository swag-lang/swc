#include "pch.h"
#include "Runtime/Runtime.h"
#include "Sema/Constant/ConstantExtract.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/Sema.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Symbol.Enum.h"
#include "Sema/Symbol/Symbol.Variable.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

Result ConstantExtract::extractConstantStructMember(Sema& sema, const ConstantValue& cst, const SymbolVariable& symVar, AstNodeRef nodeRef, AstNodeRef nodeMemberRef)
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
        SWC_ASSERT(cstType.isAnyPointer());
        const TypeInfo& pointedType = sema.typeMgr().get(cstType.payloadTypeRef());
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

    if (typeField->isEnum())
        typeField = &sema.typeMgr().get(typeField->payloadSymEnum().underlyingTypeRef());

    ConstantValue cv;
    if (typeField->isStruct())
    {
        cv = ConstantValue::makeStruct(ctx, typeField->payloadTypeRef(), fieldBytes);
    }
    else if (typeField->isBool())
    {
        cv = ConstantValue::makeBool(ctx, *reinterpret_cast<const bool*>(fieldBytes.data()));
    }
    else if (typeField->isIntLike())
    {
        const ApsInt apsInt(reinterpret_cast<const char*>(fieldBytes.data()), typeField->payloadIntLikeBits(), typeField->isIntUnsigned());
        cv = ConstantValue::makeFromIntLike(ctx, apsInt, *typeField);
    }
    else if (typeField->isFloat())
    {
        const ApFloat apFloat(reinterpret_cast<const char*>(fieldBytes.data()), typeField->payloadFloatBits());
        cv = ConstantValue::makeFloat(ctx, apFloat, typeField->payloadFloatBits());
    }
    else if (typeField->isString())
    {
        const auto str = reinterpret_cast<const Runtime::String*>(fieldBytes.data());
        cv             = ConstantValue::makeString(ctx, std::string_view(str->ptr, str->length));
    }
    else if (typeField->isValuePointer())
    {
        const auto val = *reinterpret_cast<const uint64_t*>(fieldBytes.data());
        cv             = ConstantValue::makeValuePointer(ctx, typeField->payloadTypeRef(), val);
    }
    else if (typeField->isSlice())
    {
        const auto     slice = reinterpret_cast<const Runtime::Slice<uint8_t>*>(fieldBytes.data());
        const ByteSpan span{reinterpret_cast<std::byte*>(slice->ptr), slice->count};
        cv = ConstantValue::makeSlice(ctx, typeField->payloadTypeRef(), span);
    }
    else
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

Result ConstantExtract::constantFoldIndex(Sema& sema, AstNodeRef nodeArgRef, const SemaNodeView& nodeExprView, int64_t constIndex, bool hasConstIndex)
{
    if (!hasConstIndex || !nodeExprView.cst)
        return Result::Continue;

    ////////////////////////////////////////////////////////
    if (nodeExprView.cst->isAggregateArray())
    {
        if (nodeExprView.type->payloadArrayDims().size() > 1)
            return Result::Continue;
        const auto& values = nodeExprView.cst->getAggregateArray();
        if (std::cmp_greater_equal(constIndex, values.size()))
            return SemaError::raiseIndexOutOfRange(sema, constIndex, values.size(), nodeArgRef);
        sema.setConstant(sema.curNodeRef(), values[constIndex]);
        return Result::Continue;
    }

    ////////////////////////////////////////////////////////
    if (nodeExprView.cst->isString())
    {
        const std::string_view s = nodeExprView.cst->getString();
        if (std::cmp_greater_equal(constIndex, s.size()))
            return SemaError::raiseIndexOutOfRange(sema, constIndex, s.size(), nodeArgRef);
        const ConstantValue cst = ConstantValue::makeIntSized(sema.ctx(), static_cast<uint8_t>(s[constIndex]));
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(sema.ctx(), cst));
        return Result::Continue;
    }

    ////////////////////////////////////////////////////////
    if (nodeExprView.cst->isSlice())
    {
        auto&          ctx         = sema.ctx();
        const TypeRef  elemTypeRef = nodeExprView.type->payloadTypeRef();
        const TypeInfo elemType    = sema.typeMgr().get(elemTypeRef);

        const uint64_t elemSize = elemType.sizeOf(ctx);
        if (!elemSize)
            return Result::Continue;

        const ByteSpan bytes      = nodeExprView.cst->getSlice();
        const uint64_t numEntries = bytes.size() / elemSize;
        if (std::cmp_greater_equal(constIndex, numEntries))
            return SemaError::raiseIndexOutOfRange(sema, constIndex, numEntries, nodeArgRef);

        const auto elemBytes = ByteSpan{bytes.data() + (constIndex * elemSize), elemSize};

        const TypeInfo* typeField = &elemType;
        if (typeField->isEnum())
            typeField = &sema.typeMgr().get(typeField->payloadSymEnum().underlyingTypeRef());

        ConstantValue cv;
        if (typeField->isStruct())
        {
            cv = ConstantValue::makeStruct(ctx, typeField->payloadTypeRef(), elemBytes);
        }
        else if (typeField->isBool())
        {
            cv = ConstantValue::makeBool(ctx, *reinterpret_cast<const bool*>(elemBytes.data()));
        }
        else if (typeField->isIntLike())
        {
            const ApsInt apsInt(reinterpret_cast<const char*>(elemBytes.data()), typeField->payloadIntLikeBits(), typeField->isIntUnsigned());
            cv = ConstantValue::makeFromIntLike(ctx, apsInt, *typeField);
        }
        else if (typeField->isFloat())
        {
            const ApFloat apFloat(reinterpret_cast<const char*>(elemBytes.data()), typeField->payloadFloatBits());
            cv = ConstantValue::makeFloat(ctx, apFloat, typeField->payloadFloatBits());
        }
        else if (typeField->isString())
        {
            const auto str = reinterpret_cast<const Runtime::String*>(elemBytes.data());
            cv             = ConstantValue::makeString(ctx, std::string_view(str->ptr, str->length));
        }
        else if (typeField->isValuePointer())
        {
            const auto val = *reinterpret_cast<const uint64_t*>(elemBytes.data());
            cv             = ConstantValue::makeValuePointer(ctx, typeField->payloadTypeRef(), val);
        }
        else
        {
            return Result::Continue;
        }

        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, cv));
        return Result::Continue;
    }

    return Result::Continue;
}

SWC_END_NAMESPACE();
