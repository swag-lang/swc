#include "pch.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Lexer/SourceCodeLocation.h"
#include "Lexer/SourceView.h"
#include "Main/TaskContext.h"
#include "Runtime/Runtime.h"
#include "Sema/Constant/ConstantManager.h"
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

    const auto       fileNameStr = loc.srcView->file()->path().string();
    const auto       cstFileName = ConstantValue::makeString(ctx, fileNameStr);
    std::string_view fileNameView = sema.cstMgr().addStructBuffer(cstFileName);

    rtLoc.fileName.ptr    = fileNameView.data();
    rtLoc.fileName.length = fileNameView.size();

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

SWC_END_NAMESPACE();
