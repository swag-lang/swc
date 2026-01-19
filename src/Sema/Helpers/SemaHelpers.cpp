#include "pch.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Lexer/SourceCodeLocation.h"
#include "Lexer/SourceView.h"
#include "Runtime/Runtime.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Symbol/Symbol.Attribute.h"
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
    const auto& ctx     = sema.ctx();
    const auto  loc     = node.locationWithChildren(ctx, sema.ast());
    const auto  typeRef = sema.typeMgr().structSourceCodeLocation();

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

    const auto view   = std::string_view(reinterpret_cast<const char*>(&rtLoc), sizeof(rtLoc));
    const auto cstVal = ConstantValue::makeStruct(ctx, typeRef, view);
    return sema.cstMgr().addConstant(ctx, cstVal);
}

Result SemaHelpers::extractConstantStructMember(Sema& sema, const ConstantValue& cst, const SymbolVariable& symVar, AstNodeRef nodeRef, AstNodeRef nodeMemberRef)
{
    std::string_view bytes;
    if (cst.isStruct())
    {
        bytes = cst.getStruct();
    }
    else if (cst.isValuePointer() || cst.isBlockPointer())
    {
        const TypeInfo& cstType = sema.typeMgr().get(cst.typeRef());
        SWC_ASSERT(cstType.isAnyPointer());
        const TypeInfo& pointedType = sema.typeMgr().get(cstType.typeRef());
        SWC_ASSERT(pointedType.isStruct());
        const uint64_t ptr = cst.isValuePointer() ? cst.getValuePointer() : cst.getBlockPointer();
        bytes              = std::string_view(reinterpret_cast<const char*>(static_cast<uintptr_t>(ptr)), pointedType.sizeOf(sema.ctx()));
    }
    else
    {
        return SemaError::raiseInternal(sema, sema.node(nodeMemberRef));
    }

    const TypeInfo& typeField = symVar.typeInfo(sema.ctx());
    SWC_ASSERT(symVar.offset() + typeField.sizeOf(sema.ctx()) <= bytes.size());
    const auto fieldBytes = std::string_view(bytes.data() + symVar.offset(), typeField.sizeOf(sema.ctx()));

    ConstantValue cv;
    if (typeField.isStruct())
    {
        cv = ConstantValue::makeStruct(sema.ctx(), typeField.typeRef(), fieldBytes);
    }
    else if (typeField.isBool())
    {
        cv = ConstantValue::makeBool(sema.ctx(), *reinterpret_cast<const bool*>(fieldBytes.data()));
    }
    else if (typeField.isIntLike())
    {
        const ApsInt apsInt(fieldBytes.data(), typeField.intLikeBits(), typeField.isIntUnsigned());
        cv = ConstantValue::makeFromIntLike(sema.ctx(), apsInt, typeField);
    }
    else if (typeField.isFloat())
    {
        const ApFloat apFloat(fieldBytes.data(), typeField.floatBits());
        cv = ConstantValue::makeFloat(sema.ctx(), apFloat, typeField.floatBits());
    }
    else if (typeField.isString())
    {
        const auto str = reinterpret_cast<const Runtime::String*>(fieldBytes.data());
        cv             = ConstantValue::makeString(sema.ctx(), std::string_view(str->ptr, str->length));
    }
    else if (typeField.isValuePointer())
    {
        const auto val = *reinterpret_cast<const uint64_t*>(fieldBytes.data());
        cv             = ConstantValue::makeValuePointer(sema.ctx(), typeField.typeRef(), val);
    }
    else
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_cst_struct_member_type, nodeMemberRef);
        diag.addArgument(Diagnostic::ARG_TYPE, symVar.typeRef());
        diag.report(sema.ctx());
        return Result::Error;
    }

    const auto cstRef = sema.cstMgr().addConstant(sema.ctx(), cv);
    sema.setConstant(nodeRef, cstRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
