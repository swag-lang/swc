#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Lexer/LangSpec.h"
#include "Parser/AstNodes.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Symbol/SemaMatch.h"
#include "Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

Result AstStructDecl::semaPreDecl(Sema& sema) const
{
    SemaHelpers::registerSymbol<SymbolStruct>(sema, *this, tokNameRef);
    return Result::SkipChildren;
}

Result AstStructDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);
    const Symbol& sym = sema.symbolOf(sema.curNodeRef());
    return SemaMatch::ghosting(sema, sym);
}

Result AstStructDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    auto& ctx = sema.ctx();

    // Creates symbol with type
    SymbolStruct&  sym           = sema.symbolOf(sema.curNodeRef()).cast<SymbolStruct>();
    const TypeInfo structType    = TypeInfo::makeStruct(&sym);
    const TypeRef  structTypeRef = ctx.typeMgr().addType(structType);
    sym.setTypeRef(structTypeRef);
    sym.setTyped(sema.ctx());

    sema.pushScope(SemaScopeFlagsE::Type);
    sema.curScope().setSymMap(&sym);

    return Result::Continue;
}

Result AstStructDecl::semaPostNode(Sema& sema)
{
    SymbolStruct& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolStruct>();

    // Runtime struct
    if (sym.symMap()->isSwagNamespace(sema.ctx()))
    {
        const auto&         idMgr   = sema.idMgr();
        auto&               typeMgr = sema.typeMgr();
        const IdentifierRef idRef   = sym.idRef();

        bool isTypeInfo = true;
        if (idRef == idMgr.nameTypeInfo())
            typeMgr.setStructTypeInfo(sym.typeRef());
        else if (idRef == idMgr.nameTypeInfoNative())
            typeMgr.setStructTypeInfoNative(sym.typeRef());
        else if (idRef == idMgr.nameTypeInfoPointer())
            typeMgr.setStructTypeInfoPointer(sym.typeRef());
        else if (idRef == idMgr.nameTypeInfoStruct())
            typeMgr.setStructTypeInfoStruct(sym.typeRef());
        else if (idRef == idMgr.nameTypeInfoFunc())
            typeMgr.setStructTypeInfoFunc(sym.typeRef());
        else if (idRef == idMgr.nameTypeInfoEnum())
            typeMgr.setStructTypeInfoEnum(sym.typeRef());
        else if (idRef == idMgr.nameTypeInfoArray())
            typeMgr.setStructTypeInfoArray(sym.typeRef());
        else if (idRef == idMgr.nameTypeInfoSlice())
            typeMgr.setStructTypeInfoSlice(sym.typeRef());
        else if (idRef == idMgr.nameTypeInfoAlias())
            typeMgr.setStructTypeInfoAlias(sym.typeRef());
        else if (idRef == idMgr.nameTypeInfoVariadic())
            typeMgr.setStructTypeInfoVariadic(sym.typeRef());
        else if (idRef == idMgr.nameTypeInfoGeneric())
            typeMgr.setStructTypeInfoGeneric(sym.typeRef());
        else if (idRef == idMgr.nameTypeInfoNamespace())
            typeMgr.setStructTypeInfoNamespace(sym.typeRef());
        else if (idRef == idMgr.nameTypeInfoCodeBlock())
            typeMgr.setStructTypeInfoCodeBlock(sym.typeRef());
        else
            isTypeInfo = false;
        if (isTypeInfo)
            sym.addStructFlag(SymbolStructFlagsE::TypeInfo);

        if (idRef == idMgr.nameTypeValue())
            typeMgr.setStructTypeValue(sym.typeRef());
        else if (idRef == idMgr.nameAttribute())
            typeMgr.setStructAttribute(sym.typeRef());
        else if (idRef == idMgr.nameAttributeParam())
            typeMgr.setStructAttributeParam(sym.typeRef());
        else if (idRef == idMgr.nameInterface())
            typeMgr.setStructInterface(sym.typeRef());
        else if (idRef == idMgr.nameSourceCodeLocation())
            typeMgr.setStructSourceCodeLocation(sym.typeRef());
    }

    RESULT_VERIFY(sym.canBeCompleted(sema));
    sym.computeLayout(sema);
    sym.setCompleted(sema.ctx());
    sema.popScope();
    return Result::Continue;
}

SWC_END_NAMESPACE();
