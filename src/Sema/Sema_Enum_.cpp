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
        if (!typeView.type->isScalarNumeric() &&
            !typeView.type->isBool() &&
            !typeView.type->isRune() &&
            !typeView.type->isString())
        {
            SemaError::raise(sema, DiagnosticId::sema_err_invalid_enum_type, nodeTypeRef);
            return AstVisitStepResult::Stop;
        }
    }

    // Default enum type is 's32'
    else
    {
        typeView.typeRef = sema.typeMgr().getTypeInt(32, TypeInfo::Sign::Signed);
        typeView.type    = &sema.typeMgr().get(typeView.typeRef);
    }

    // Register name
    const IdentifierRef idRef = sema.idMgr().addIdentifier(ctx, srcViewRef(), tokNameRef);

    // Get the destination symbolMap
    SymbolFlags        flags  = SymbolFlagsE::Zero;
    const SymbolAccess access = SemaFrame::currentAccess(sema);
    if (access == SymbolAccess::Public)
        flags.add(SymbolFlagsE::Public);
    SymbolMap* symbolMap = SemaFrame::currentSymMap(sema);

    // Creates symbol with type
    auto*          sym         = Symbol::make<SymbolEnum>(ctx, this, idRef, flags);
    const TypeInfo enumType    = TypeInfo::makeEnum(sym);
    const TypeRef  enumTypeRef = ctx.typeMgr().addType(enumType);
    sym->setTypeRef(enumTypeRef);
    sym->setUnderlyingTypeRef(typeView.typeRef);
    if (typeView.type->isInt())
        sym->setNextValue(ApsInt{typeView.type->intBits(), typeView.type->isIntUnsigned()});
    sema.setSymbol(sema.curNodeRef(), sym);

    if (!symbolMap->addSingleSymbol(sema, sym))
        return AstVisitStepResult::Stop;

    sema.pushScope(SemaScopeFlagsE::Type);
    sema.curScope().setSymMap(sym);

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstEnumDecl::semaPostNode(Sema& sema) const
{
    if (sema.curSymMap()->empty())
    {
        SemaError::raise(sema, DiagnosticId::sema_err_empty_enum, srcViewRef(), getTokNameRef());
        return AstVisitStepResult::Stop;
    }

    sema.curSymMap()->setFullComplete(sema.ctx());
    sema.popScope();
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstEnumValue::semaPostNode(Sema& sema) const
{
    auto&              ctx = sema.ctx();
    const SemaNodeView nodeInitView(sema, nodeInitRef);

    auto&         symEnum           = sema.curSymMap()->cast<SymbolEnum>();
    const TypeRef underlyingTypeRef = symEnum.underlyingTypeRef();
    SWC_ASSERT(underlyingTypeRef.isValid());

    const auto& underlyingType = sema.typeMgr().get(underlyingTypeRef);
    ConstantRef valueCst;

    if (nodeInitView.nodeRef.isValid())
    {
        // Must be constant
        if (nodeInitView.cstRef.isInvalid())
        {
            SemaError::raiseExprNotConst(sema, nodeInitRef);
            return AstVisitStepResult::Stop;
        }

        // Cast initializer constant to the underlying type
        CastContext castCtx(CastKind::Implicit);
        castCtx.errorNodeRef = nodeInitRef;
        valueCst             = SemaCast::castConstant(sema, castCtx, nodeInitView.cstRef, underlyingTypeRef);
        if (valueCst.isInvalid())
            return AstVisitStepResult::Stop;

        if (underlyingType.isInt())
        {
            const ConstantValue& cstVal = sema.cstMgr().get(valueCst);
            symEnum.setNextValue(cstVal.getInt());
            symEnum.setHasNextValue();
        }
    }
    else
    {
        // No initializer => auto value
        if (!underlyingType.isInt())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_missing_enum_value, srcViewRef(), tokRef());
            diag.addArgument(Diagnostic::ARG_TYPE, underlyingTypeRef);
            diag.report(ctx);
            return AstVisitStepResult::Stop;
        }

        // Update enum "nextValue" = value + 1 (so subsequent no-init enumerators work)
        if (symEnum.hasNextValue())
        {
            bool   overflow = false;
            ApsInt one(1, symEnum.nextValue().bitWidth(), symEnum.nextValue().isUnsigned());
            symEnum.nextValue().add(one, overflow);
            if (overflow)
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_literal_overflow, srcViewRef(), tokRef());
                diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, underlyingTypeRef);
                diag.report(ctx);
                return AstVisitStepResult::Stop;
            }
        }

        ConstantValue val = ConstantValue::makeInt(ctx, symEnum.nextValue(), underlyingType.intBits(), underlyingType.intSign());
        valueCst          = sema.cstMgr().addConstant(ctx, val);
        symEnum.setHasNextValue();
    }

    // Create a symbol for this enum value
    const IdentifierRef idRef    = sema.idMgr().addIdentifier(ctx, srcViewRef(), tokRef());
    auto*               symValue = Symbol::make<SymbolEnumValue>(ctx, this, idRef, SymbolFlagsE::Zero);

    ConstantValue enumCst    = ConstantValue::makeEnumValue(ctx, valueCst, symEnum.typeRef());
    ConstantRef   enumCstRef = sema.cstMgr().addConstant(ctx, enumCst);
    symValue->setCstRef(enumCstRef);
    symValue->setTypeRef(symEnum.typeRef());

    if (!sema.curSymMap()->addSingleSymbol(sema, symValue))
        return AstVisitStepResult::Stop;

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
