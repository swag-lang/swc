#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Lexer/LangSpec.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbols.h"

SWC_BEGIN_NAMESPACE();

Result AstEnumDecl::semaPreDecl(Sema& sema) const
{
    SemaHelpers::registerSymbol<SymbolEnum>(sema, *this, tokNameRef);
    return Result::Continue;
}

Result AstEnumDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
    {
        SemaHelpers::declareSymbol(sema, *this);

        // Runtime: enum 'AttributeUsage' is forced to be in flag mode.
        // (we can't rely on #[Swag.EnumFlags] as attributes are constructed there)
        Symbol& sym = sema.symbolOf(sema.curNodeRef());
        if (sym.inSwagNamespace(sema.ctx()))
        {
            if (sym.idRef() == sema.idMgr().predefined(IdentifierManager::PredefinedName::AttributeUsage))
                sym.attributes().addRtFlag(RtAttributeFlagsE::EnumFlags);
        }
    }

    const Symbol& sym = sema.symbolOf(sema.curNodeRef());
    return Match::ghosting(sema, sym);
}

namespace
{
    Result validateEnumUnderlyingType(Sema& sema, const SymbolEnum& sym, const SemaNodeView& typeView, AstNodeRef typeNodeRef)
    {
        if (sym.isEnumFlags() && !typeView.type->isIntUnsigned())
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_enum_flags_type, typeNodeRef);

        if (!typeView.type->isScalarNumeric() &&
            !typeView.type->isBool() &&
            !typeView.type->isRune() &&
            !typeView.type->isString())
            return SemaError::raise(sema, DiagnosticId::sema_err_invalid_enum_type, typeNodeRef);

        return Result::Continue;
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
        const auto bits       = underlyingType.payloadIntBits();

        if (sym.isEnumFlags())
            sym.setNextValue(ApsInt{1, bits, isUnsigned});
        else
            sym.setNextValue(ApsInt{bits, isUnsigned});
    }
}

Result AstEnumDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    SymbolEnum&  sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolEnum>();
    SemaNodeView typeView(sema, nodeTypeRef);

    if (nodeTypeRef.isValid())
    {
        RESULT_VERIFY(validateEnumUnderlyingType(sema, sym, typeView, nodeTypeRef));
    }

    const TypeRef  underlyingTypeRef = resolveEnumUnderlyingType(sema, sym, typeView);
    const TypeInfo enumType          = TypeInfo::makeEnum(&sym);
    const TypeRef  enumTypeRef       = sema.typeMgr().addType(enumType);
    sym.setTypeRef(enumTypeRef);
    sym.setUnderlyingTypeRef(underlyingTypeRef);
    sym.setTyped(sema.ctx());

    initEnumNextValue(sym, *typeView.type);

    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Type);
    sema.curScope().setSymMap(&sym);

    return Result::Continue;
}

Result AstEnumDecl::semaPostNode(Sema& sema) const
{
    SymbolEnum& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolEnum>();
    if (sym.empty())
        return SemaError::raise(sema, DiagnosticId::sema_err_empty_enum, SourceCodeRef{srcViewRef(), tokNameRef});

    // Runtime enum
    if (sym.inSwagNamespace(sema.ctx()))
        sema.typeMgr().registerRuntimeType(sym.idRef(), sym.typeRef());

    sym.setSemaCompleted(sema.ctx());
    return Result::Continue;
}

Result AstEnumValue::semaPostNode(Sema& sema) const
{
    auto&        ctx = sema.ctx();
    SemaNodeView nodeInitView(sema, nodeInitRef);

    SymbolEnum&     symEnum           = sema.curSymMap()->cast<SymbolEnum>();
    const TypeRef   underlyingTypeRef = symEnum.underlyingTypeRef();
    const TypeInfo& underlyingType    = symEnum.underlyingType(ctx);

    ConstantRef valueCst;
    if (nodeInitView.nodeRef.isValid())
    {
        // Must be constant
        if (nodeInitView.cstRef.isInvalid())
            return SemaError::raiseExprNotConst(sema, nodeInitRef);

        // Cast initializer constant to the underlying type
        RESULT_VERIFY(Cast::cast(sema, nodeInitView, underlyingTypeRef, CastKind::Initialization));
        valueCst = nodeInitView.cstRef;
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
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_missing_enum_value, codeRef());
            diag.addArgument(Diagnostic::ARG_TYPE, underlyingTypeRef);
            diag.report(ctx);
            return Result::Error;
        }

        if (symEnum.hasNextValue() && !symEnum.computeNextValue(sema, codeRef()))
            return Result::Error;

        ConstantValue val = ConstantValue::makeInt(ctx, symEnum.nextValue(), underlyingType.payloadIntBits(), underlyingType.payloadIntSign());
        valueCst          = sema.cstMgr().addConstant(ctx, val);
        symEnum.setHasNextValue();
    }

    // Create a symbol for this enum value
    const IdentifierRef idRef    = sema.idMgr().addIdentifier(ctx, codeRef());
    SymbolFlags         flags    = SymbolFlagsE::Declared | SymbolFlagsE::SemaCompleted;
    SymbolEnumValue*    symValue = Symbol::make<SymbolEnumValue>(ctx, this, tokRef(), idRef, flags);
    symValue->registerCompilerIf(sema);

    ConstantValue enumCst    = ConstantValue::makeEnumValue(ctx, valueCst, symEnum.typeRef());
    ConstantRef   enumCstRef = sema.cstMgr().addConstant(ctx, enumCst);
    symValue->setCstRef(enumCstRef);
    symValue->setTypeRef(symEnum.typeRef());
    symValue->setTyped(ctx);

    if (!sema.curSymMap()->addSingleSymbolOrError(sema, symValue))
        return Result::Error;

    return Result::Continue;
}

SWC_END_NAMESPACE();
