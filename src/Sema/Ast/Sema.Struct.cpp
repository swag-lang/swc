#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Lexer/LangSpec.h"
#include "Parser/AstNodes.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Match/Match.h"

SWC_BEGIN_NAMESPACE();

Result AstStructDecl::semaPreDecl(Sema& sema) const
{
    auto& sym = SemaHelpers::registerSymbol<SymbolStruct>(sema, *this, tokNameRef);

    // Runtime struct
    if (sym.inSwagNamespace(sema.ctx()))
    {
        const auto&         idMgr = sema.idMgr();
        const IdentifierRef idRef = sym.idRef();

        if (idRef == idMgr.nameTypeInfo() ||
            idRef == idMgr.nameTypeInfoNative() ||
            idRef == idMgr.nameTypeInfoPointer() ||
            idRef == idMgr.nameTypeInfoStruct() ||
            idRef == idMgr.nameTypeInfoFunc() ||
            idRef == idMgr.nameTypeInfoEnum() ||
            idRef == idMgr.nameTypeInfoArray() ||
            idRef == idMgr.nameTypeInfoSlice() ||
            idRef == idMgr.nameTypeInfoAlias() ||
            idRef == idMgr.nameTypeInfoVariadic() ||
            idRef == idMgr.nameTypeInfoGeneric() ||
            idRef == idMgr.nameTypeInfoNamespace() ||
            idRef == idMgr.nameTypeInfoCodeBlock())
        {
            sym.addExtraFlag(SymbolStructFlagsE::TypeInfo);
        }
    }

    return Result::SkipChildren;
}

Result AstStructDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);
    const Symbol& sym = sema.symbolOf(sema.curNodeRef());
    return Match::ghosting(sema, sym);
}

Result AstStructDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeBodyRef)
    {
        auto& ctx = sema.ctx();

        // Creates symbol with type
        SymbolStruct&  sym           = sema.symbolOf(sema.curNodeRef()).cast<SymbolStruct>();
        const TypeInfo structType    = TypeInfo::makeStruct(&sym);
        const TypeRef  structTypeRef = ctx.typeMgr().addType(structType);
        sym.setTypeRef(structTypeRef);
        sym.setTyped(sema.ctx());

        sema.pushScopeAutoPopOnPostNode(SemaScopeFlagsE::Type);
        sema.curScope().setSymMap(&sym);
    }

    return Result::Continue;
}

Result AstStructDecl::semaPostNode(Sema& sema)
{
    SymbolStruct& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolStruct>();

    // Runtime struct
    if (sym.inSwagNamespace(sema.ctx()))
    {
        const auto&         idMgr   = sema.idMgr();
        auto&               typeMgr = sema.typeMgr();
        const IdentifierRef idRef   = sym.idRef();
        const TypeRef       typeRef = sym.typeRef();

        if (idRef == idMgr.nameTypeInfo())
            typeMgr.setStructTypeInfo(typeRef);
        else if (idRef == idMgr.nameTypeInfoNative())
            typeMgr.setStructTypeInfoNative(typeRef);
        else if (idRef == idMgr.nameTypeInfoPointer())
            typeMgr.setStructTypeInfoPointer(typeRef);
        else if (idRef == idMgr.nameTypeInfoStruct())
            typeMgr.setStructTypeInfoStruct(typeRef);
        else if (idRef == idMgr.nameTypeInfoFunc())
            typeMgr.setStructTypeInfoFunc(typeRef);
        else if (idRef == idMgr.nameTypeInfoEnum())
            typeMgr.setStructTypeInfoEnum(typeRef);
        else if (idRef == idMgr.nameTypeInfoArray())
            typeMgr.setStructTypeInfoArray(typeRef);
        else if (idRef == idMgr.nameTypeInfoSlice())
            typeMgr.setStructTypeInfoSlice(typeRef);
        else if (idRef == idMgr.nameTypeInfoAlias())
            typeMgr.setStructTypeInfoAlias(typeRef);
        else if (idRef == idMgr.nameTypeInfoVariadic())
            typeMgr.setStructTypeInfoVariadic(typeRef);
        else if (idRef == idMgr.nameTypeInfoGeneric())
            typeMgr.setStructTypeInfoGeneric(typeRef);
        else if (idRef == idMgr.nameTypeInfoNamespace())
            typeMgr.setStructTypeInfoNamespace(typeRef);
        else if (idRef == idMgr.nameTypeInfoCodeBlock())
            typeMgr.setStructTypeInfoCodeBlock(typeRef);
        else if (idRef == idMgr.nameTypeValue())
            typeMgr.setStructTypeValue(typeRef);
        else if (idRef == idMgr.nameAttribute())
            typeMgr.setStructAttribute(typeRef);
        else if (idRef == idMgr.nameAttributeParam())
            typeMgr.setStructAttributeParam(typeRef);
        else if (idRef == idMgr.nameInterface())
            typeMgr.setStructInterface(typeRef);
        else if (idRef == idMgr.nameSourceCodeLocation())
            typeMgr.setStructSourceCodeLocation(typeRef);
        else if (idRef == idMgr.nameErrorValue())
            typeMgr.setStructErrorValue(typeRef);
        else if (idRef == idMgr.nameScratchAllocator())
            typeMgr.setStructScratchAllocator(typeRef);
        else if (idRef == idMgr.nameContext())
            typeMgr.setStructContext(typeRef);
        else if (idRef == idMgr.nameModule())
            typeMgr.setStructModule(typeRef);
        else if (idRef == idMgr.nameProcessInfos())
            typeMgr.setStructProcessInfos(typeRef);
        else if (idRef == idMgr.nameGvtd())
            typeMgr.setStructGvtd(typeRef);
    }

    RESULT_VERIFY(sym.canBeCompleted(sema));
    sym.computeLayout(sema);
    sym.setCompleted(sema.ctx());
    return Result::Continue;
}

Result AstAnonymousStructDecl::semaPreNode(Sema& sema)
{
    // TODO
    sema.setType(sema.curNodeRef(), sema.typeMgr().typeBool());
    return Result::SkipChildren;
}

SWC_END_NAMESPACE();
