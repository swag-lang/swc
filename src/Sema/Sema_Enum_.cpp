#include "pch.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisitResult.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaFrame.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Helpers/SemaNodeView.h"
#include "Sema/Sema.h"
#include "Sema/Symbol/Symbols.h"
#include "Type/CastContext.h"
#include "Type/SemaCast.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstEnumDecl::semaPreChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return AstVisitStepResult::Continue;

    auto& ctx = sema.ctx();

    // Check type if specified
    SemaNodeView typeView(sema, nodeTypeRef);
    if (nodeTypeRef.isValid())
    {
        if (!typeView.type->isScalarNumeric())
        {
            SemaError::raise(sema, DiagnosticId::sema_err_invalid_enum_type, nodeTypeRef);
            return AstVisitStepResult::Stop;
        }
    }

    // Default enum type is 's32'
    else
    {
        typeView.typeRef = sema.typeMgr().getTypeInt(32, TypeInfo::Sign::Signed);
    }

    const IdentifierRef idRef = sema.idMgr().addIdentifier(ctx, srcViewRef(), tokNameRef);

    // Get the destination symbolMap
    SymbolFlags        flags     = SymbolFlagsE::Zero;
    SymbolMap*         symbolMap = sema.curSymMap();
    const SymbolAccess access    = sema.frame().currentAccess.value_or(sema.frame().defaultAccess);
    if (access == SymbolAccess::Internal)
        symbolMap = &sema.semaInfo().fileNamespace();
    else if (access == SymbolAccess::Public)
        flags.add(SymbolFlagsE::Public);

    // Creates symbol with type
    auto*          sym         = Symbol::make<SymbolEnum>(ctx, this, idRef, flags);
    const TypeInfo enumType    = TypeInfo::makeEnum(sym);
    const TypeRef  enumTypeRef = ctx.typeMgr().addType(enumType);
    sym->setTypeRef(enumTypeRef);
    sym->setUnderlyingTypeRef(typeView.typeRef);
    sema.setSymbol(sema.curNodeRef(), sym);

    if (!symbolMap->addSingleSymbol(sema, sym))
        return AstVisitStepResult::Stop;

    sema.pushScope(SemaScopeFlagsE::Type);
    sema.curScope().setSymMap(sym);

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstEnumDecl::semaPostNode(Sema& sema)
{
    sema.curSymMap()->setFullComplete(sema.ctx());
    sema.popScope();
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstEnumValue::semaPostNode(Sema& sema) const
{
    auto&             ctx = sema.ctx();
    SemaNodeView      nodeInitView(sema, nodeInitRef);
    const SymbolEnum& symEnum = sema.curSymMap()->cast<SymbolEnum>();
    SWC_ASSERT(symEnum.underlyingTypeRef().isValid());

    if (nodeInitView.nodeRef.isValid())
    {
        // Verify that the initializer is constant
        if (nodeInitView.cstRef.isInvalid())
        {
            SemaError::raiseExprNotConst(sema, nodeInitRef);
            return AstVisitStepResult::Stop;
        }

        // Verify constant type
        CastContext castCtx(CastKind::Implicit);
        castCtx.errorNodeRef = nodeInitRef;
        nodeInitView.cstRef  = SemaCast::castConstant(sema, castCtx, nodeInitView.cstRef, symEnum.underlyingTypeRef());
        if (nodeInitView.cstRef.isInvalid())
            return AstVisitStepResult::Stop;
    }
    else
    {
        // If no initializer, verify that the underlying type is integer to deduce the value
        const auto& type = sema.typeMgr().get(symEnum.underlyingTypeRef());
        if (!type.isInt())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_missing_enum_value, srcViewRef(), tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, symEnum.underlyingTypeRef());
            diag.report(sema.ctx());
            return AstVisitStepResult::Stop;
        }
    }

    const IdentifierRef idRef    = sema.idMgr().addIdentifier(ctx, srcViewRef(), tokRef());
    auto*               symValue = Symbol::make<SymbolEnumValue>(ctx, this, idRef, SymbolFlagsE::Zero);
    symValue->setCstRef(nodeInitView.cstRef);
    symValue->setTypeRef(nodeInitView.typeRef);

    if (!sema.curSymMap()->addSingleSymbol(sema, symValue))
        return AstVisitStepResult::Stop;

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
