#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Lexer/LangSpec.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisitResult.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaHelpers.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Symbol/SemaMatch.h"
#include "Sema/Symbol/Symbols.h"
#include "Sema/Type/CastContext.h"
#include "Sema/Type/SemaCast.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstEnumDecl::semaPreDecl(Sema& sema) const
{
    SemaHelpers::declareNamedSymbol<SymbolEnum>(sema, *this, tokNameRef);
    return AstVisitStepResult::Continue;
}

void AstEnumDecl::semaEnterNode(Sema& sema)
{
    Symbol& sym = sema.symbolOf(sema.curNodeRef());
    sym.registerAttributes(sema);

    // Runtime: enum 'AttributeUsage' is forced to be in flag mode.
    // (we can't rely on #[Swag.EnumFlags] as attributes are constructed there)
    if (sym.symMap()->isSwagNamespace(sema.ctx()))
    {
        if (sym.idRef() == sema.idMgr().nameAttributeUsage())
            sym.attributes().flags = AttributeFlagsE::EnumFlags;
    }

    sym.setDeclared(sema.ctx());
}

AstVisitStepResult AstEnumDecl::semaPreNode(Sema& sema)
{
    const Symbol& sym = sema.symbolOf(sema.curNodeRef());
    return SemaMatch::ghosting(sema, sym);
}

namespace
{
    bool validateEnumUnderlyingType(Sema& sema, const SymbolEnum& sym, const SemaNodeView& typeView, AstNodeRef typeNodeRef)
    {
        if (sym.isEnumFlags() && !typeView.type->isIntUnsigned())
        {
            SemaError::raise(sema, DiagnosticId::sema_err_invalid_enum_flags_type, typeNodeRef);
            return false;
        }

        if (!typeView.type->isScalarNumeric() &&
            !typeView.type->isBool() &&
            !typeView.type->isRune() &&
            !typeView.type->isString())
        {
            SemaError::raise(sema, DiagnosticId::sema_err_invalid_enum_type, typeNodeRef);
            return false;
        }

        return true;
    }

    TypeRef resolveEnumUnderlyingType(Sema& sema, const SymbolEnum& sym, SemaNodeView& typeView)
    {
        if (typeView.nodeRef.isValid())
            return typeView.typeRef;

        const auto sign  = sym.isEnumFlags() ? TypeInfo::Sign::Unsigned : TypeInfo::Sign::Signed;
        typeView.typeRef = sema.typeMgr().typeInt(32, sign);
        typeView.type    = &sema.typeMgr().get(typeView.typeRef);
        return typeView.typeRef;
    }

    void initEnumNextValue(SymbolEnum& sym, const TypeInfo& underlyingType)
    {
        if (!underlyingType.isInt())
            return;

        const bool isUnsigned = underlyingType.isIntUnsigned();
        const auto bits       = underlyingType.intBits();

        if (sym.isEnumFlags())
            sym.setNextValue(ApsInt{1, bits, isUnsigned});
        else
            sym.setNextValue(ApsInt{bits, isUnsigned});
    }
}

AstVisitStepResult AstEnumDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return AstVisitStepResult::Continue;

    SymbolEnum&  sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolEnum>();
    SemaNodeView typeView(sema, nodeTypeRef);

    if (nodeTypeRef.isValid() && !validateEnumUnderlyingType(sema, sym, typeView, nodeTypeRef))
        return AstVisitStepResult::Stop;

    const TypeRef  underlyingTypeRef = resolveEnumUnderlyingType(sema, sym, typeView);
    const TypeInfo enumType          = TypeInfo::makeEnum(&sym);
    const TypeRef  enumTypeRef       = sema.typeMgr().addType(enumType);
    sym.setTypeRef(enumTypeRef);
    sym.setUnderlyingTypeRef(underlyingTypeRef);
    sym.setTyped(sema.ctx());

    initEnumNextValue(sym, *typeView.type);

    sema.pushScope(SemaScopeFlagsE::Type);
    sema.curScope().setSymMap(&sym);

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstEnumDecl::semaPostNode(Sema& sema) const
{
    SymbolEnum& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolEnum>();
    if (sym.empty())
    {
        SemaError::raise(sema, DiagnosticId::sema_err_empty_enum, srcViewRef(), tokNameRef);
        return AstVisitStepResult::Stop;
    }

    // Runtime enum
    if (sym.symMap()->isSwagNamespace(sema.ctx()))
    {
        if (sym.idRef() == sema.idMgr().nameTargetOs())
            sema.typeMgr().setEnumTargetOs(sym.typeRef());
    }

    sym.setCompleted(sema.ctx());
    sema.popScope();
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstEnumValue::semaPostNode(Sema& sema) const
{
    auto&              ctx = sema.ctx();
    const SemaNodeView nodeInitView(sema, nodeInitRef);

    SymbolEnum&     symEnum           = sema.curSymMap()->cast<SymbolEnum>();
    const TypeRef   underlyingTypeRef = symEnum.underlyingTypeRef();
    const TypeInfo& underlyingType    = symEnum.underlyingType(ctx);

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

        if (symEnum.hasNextValue() && !symEnum.computeNextValue(sema, srcViewRef(), tokRef()))
            return AstVisitStepResult::Stop;

        ConstantValue val = ConstantValue::makeInt(ctx, symEnum.nextValue(), underlyingType.intBits(), underlyingType.intSign());
        valueCst          = sema.cstMgr().addConstant(ctx, val);
        symEnum.setHasNextValue();
    }

    // Create a symbol for this enum value
    const IdentifierRef idRef    = sema.idMgr().addIdentifier(ctx, srcViewRef(), tokRef());
    SymbolFlags         flags    = SymbolFlagsE::Declared | SymbolFlagsE::Completed;
    SymbolEnumValue*    symValue = Symbol::make<SymbolEnumValue>(ctx, this, tokRef(), idRef, flags);
    symValue->registerCompilerIf(sema);

    ConstantValue enumCst    = ConstantValue::makeEnumValue(ctx, valueCst, symEnum.typeRef());
    ConstantRef   enumCstRef = sema.cstMgr().addConstant(ctx, enumCst);
    symValue->setCstRef(enumCstRef);
    symValue->setTypeRef(symEnum.typeRef());
    symValue->setTyped(ctx);

    if (!sema.curSymMap()->addSingleSymbolOrError(sema, symValue))
        return AstVisitStepResult::Stop;

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
