#include "pch.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Lexer/SourceCodeLocation.h"
#include "Lexer/SourceView.h"
#include "Runtime/Runtime.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Symbol.Attribute.h"
#include "Sema/Symbol/Symbol.Enum.h"
#include "Sema/Symbol/Symbol.Function.h"
#include "Sema/Symbol/Symbol.Interface.h"
#include "Sema/Type/TypeManager.h"
#include "Wmf/SourceFile.h"

SWC_BEGIN_NAMESPACE();

void SemaHelpers::handleSymbolRegistration(Sema& sema, SymbolMap* symbolMap, Symbol* sym)
{
    if (sym->isVariable())
    {
        if (const auto symStruct = symbolMap->safeCast<SymbolStruct>())
            symStruct->addField(reinterpret_cast<SymbolVariable*>(sym));

        if (sema.curScope().isParameters())
        {
            if (const auto symAttr = symbolMap->safeCast<SymbolAttribute>())
                symAttr->addParameter(reinterpret_cast<SymbolVariable*>(sym));
            if (const auto symFunc = symbolMap->safeCast<SymbolFunction>())
                symFunc->addParameter(reinterpret_cast<SymbolVariable*>(sym));
        }
    }

    if (sym->isFunction())
    {
        if (const auto symInterface = symbolMap->safeCast<SymbolInterface>())
            symInterface->addMethod(reinterpret_cast<SymbolFunction*>(sym));
    }
}

ConstantRef SemaHelpers::makeConstantLocation(Sema& sema, const AstNode& node)
{
    auto&      ctx     = sema.ctx();
    const auto loc     = node.locationWithChildren(ctx, sema.ast());
    const auto typeRef = sema.typeMgr().structSourceCodeLocation();

    Runtime::SourceCodeLocation rtLoc;

    const std::string_view nameView = sema.cstMgr().addString(ctx, loc.srcView->file()->path().string());
    rtLoc.fileName.ptr              = nameView.data();
    rtLoc.fileName.length           = nameView.size();

    rtLoc.funcName.ptr    = nullptr;
    rtLoc.funcName.length = 0;

    rtLoc.lineStart = loc.line;
    rtLoc.colStart  = loc.column;
    rtLoc.lineEnd   = loc.line;
    rtLoc.colEnd    = loc.column + loc.len;

    const auto view   = ByteSpan{reinterpret_cast<const std::byte*>(&rtLoc), sizeof(rtLoc)};
    const auto cstVal = ConstantValue::makeStruct(ctx, typeRef, view);
    return sema.cstMgr().addConstant(ctx, cstVal);
}

Result SemaHelpers::extractConstantStructMember(Sema& sema, const ConstantValue& cst, const SymbolVariable& symVar, AstNodeRef nodeRef, AstNodeRef nodeMemberRef)
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

SWC_END_NAMESPACE();
