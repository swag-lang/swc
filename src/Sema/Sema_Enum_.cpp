#include "pch.h"
#include "Lexer/LangSpec.h"
#include "Parser/AstNodes.h"
#include "Parser/AstVisitResult.h"
#include "Sema/Core/Sema.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Helpers/SemaFrame.h"
#include "Sema/Helpers/SemaInfo.h"
#include "Sema/Helpers/SemaMatch.h"
#include "Sema/Helpers/SemaNodeView.h"
#include "Sema/Symbol/Symbols.h"
#include "Type/CastContext.h"
#include "Type/SemaCast.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstEnumDecl::semaPreDecl(Sema& sema) const
{
    auto& ctx = sema.ctx();

    const IdentifierRef idRef     = sema.idMgr().addIdentifier(ctx, srcViewRef(), tokNameRef);
    const SymbolFlags   flags     = sema.frame().flagsForCurrentAccess();
    SymbolMap*          symbolMap = SemaFrame::currentSymMap(sema);

    SymbolEnum* sym = Symbol::make<SymbolEnum>(ctx, srcViewRef(), tokNameRef, idRef, flags);
    if (!symbolMap->addSymbol(ctx, sym, true))
        return AstVisitStepResult::Stop;
    sym->registerCompilerIf(sema);
    sema.setSymbol(sema.curNodeRef(), sym);

    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstEnumDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return AstVisitStepResult::Continue;

    auto&       ctx = sema.ctx();
    SymbolEnum& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolEnum>();

    // Check type if specified
    SemaNodeView typeView(sema, nodeTypeRef);
    if (nodeTypeRef.isValid())
    {
        if (sym.isEnumFlags() &&
            !typeView.type->isIntUnsigned())
        {
            SemaError::raise(sema, DiagnosticId::sema_err_invalid_enum_flags_type, nodeTypeRef);
            return AstVisitStepResult::Stop;
        }

        if (!typeView.type->isScalarNumeric() &&
            !typeView.type->isBool() &&
            !typeView.type->isRune() &&
            !typeView.type->isString())
        {
            SemaError::raise(sema, DiagnosticId::sema_err_invalid_enum_type, nodeTypeRef);
            return AstVisitStepResult::Stop;
        }
    }

    // Default enum type is 's32/u32'
    else
    {
        typeView.typeRef = sema.typeMgr().getTypeInt(32, sym.isEnumFlags() ? TypeInfo::Sign::Unsigned : TypeInfo::Sign::Signed);
        typeView.type    = &sema.typeMgr().get(typeView.typeRef);
    }

    // Creates symbol with type
    const TypeInfo enumType    = TypeInfo::makeEnum(&sym);
    const TypeRef  enumTypeRef = ctx.typeMgr().addType(enumType);
    sym.setTypeRef(enumTypeRef);
    sym.setUnderlyingTypeRef(typeView.typeRef);

    // Default first value
    if (typeView.type->isInt())
    {
        if (sym.isEnumFlags())
            sym.setNextValue(ApsInt{1, typeView.type->intBits(), typeView.type->isIntUnsigned()});
        else
            sym.setNextValue(ApsInt{typeView.type->intBits(), typeView.type->isIntUnsigned()});
    }

    sema.pushScope(SemaScopeFlagsE::Type);
    sema.curScope().setSymMap(&sym);

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

AstVisitStepResult AstEnumDecl::semaPostNode(Sema& sema) const
{
    if (sema.curSymMap()->empty())
    {
        SemaError::raise(sema, DiagnosticId::sema_err_empty_enum, srcViewRef(), tokNameRef);
        return AstVisitStepResult::Stop;
    }

    sema.curSymMap()->setComplete(sema.ctx());
    sema.popScope();
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstEnumValue::semaPostNode(Sema& sema) const
{
    auto&              ctx = sema.ctx();
    const SemaNodeView nodeInitView(sema, nodeInitRef);

    SymbolEnum&   symEnum           = sema.curSymMap()->cast<SymbolEnum>();
    const TypeRef underlyingTypeRef = symEnum.underlyingTypeRef();
    SWC_ASSERT(underlyingTypeRef.isValid());

    const TypeInfo& underlyingType = sema.typeMgr().get(underlyingTypeRef);
    ConstantRef     valueCst;

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

        if (symEnum.hasNextValue())
        {
            bool overflow = false;

            // Update enum "nextValue" = value << 1
            if (symEnum.isEnumFlags())
            {
                if (symEnum.nextValue().isZero())
                {
                    ApsInt one(1, symEnum.nextValue().bitWidth(), symEnum.nextValue().isUnsigned());
                    symEnum.nextValue().add(one, overflow);
                }
                else if (!symEnum.nextValue().isPowerOf2())
                {
                    auto diag = SemaError::report(sema, DiagnosticId::sema_err_flag_enum_power_2, srcViewRef(), tokRef());
                    diag.addArgument(Diagnostic::ARG_VALUE, symEnum.nextValue().toString());
                    diag.report(ctx);
                    return AstVisitStepResult::Stop;
                }
                else
                {
                    symEnum.nextValue().shiftLeft(1, overflow);
                }
            }

            // Update enum "nextValue" = value + 1
            else
            {
                ApsInt one(1, symEnum.nextValue().bitWidth(), symEnum.nextValue().isUnsigned());
                symEnum.nextValue().add(one, overflow);
            }

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
    const IdentifierRef idRef = sema.idMgr().addIdentifier(ctx, srcViewRef(), tokRef());

    SymbolFlags      flags    = SymbolFlagsE::Complete | SymbolFlagsE::Declared;
    SymbolEnumValue* symValue = Symbol::make<SymbolEnumValue>(ctx, srcViewRef(), tokRef(), idRef, flags);
    symValue->registerCompilerIf(sema);

    ConstantValue enumCst    = ConstantValue::makeEnumValue(ctx, valueCst, symEnum.typeRef());
    ConstantRef   enumCstRef = sema.cstMgr().addConstant(ctx, enumCst);
    symValue->setCstRef(enumCstRef);
    symValue->setTypeRef(symEnum.typeRef());

    if (!sema.curSymMap()->addSingleSymbolOrError(sema, symValue))
        return AstVisitStepResult::Stop;

    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
