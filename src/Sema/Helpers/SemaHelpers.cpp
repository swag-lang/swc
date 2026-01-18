#include "pch.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Lexer/SourceCodeLocation.h"
#include "Lexer/SourceView.h"
#include "Main/TaskContext.h"
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

    const std::string   fileNameStr = loc.srcView->file()->path().string();
    const ConstantValue cstFileName = ConstantValue::makeString(ctx, fileNameStr);
    rtLoc.fileName.ptr              = cstFileName.getString().data();
    rtLoc.fileName.length           = cstFileName.getString().size();

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
    const std::string_view bytes = cst.getStruct();

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
        const ApsInt apsInt(fieldBytes.data(), static_cast<uint32_t>(fieldBytes.size()), typeField.intLikeBits(), typeField.isIntUnsigned());
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
