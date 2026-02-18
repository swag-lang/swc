#include "pch.h"

#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE();

Result AstBuiltinType::semaPostNode(Sema& sema) const
{
    const auto&      tok     = sema.token(codeRef());
    const TypeManager& typeMgr = sema.typeMgr();
    const AstNodeRef nodeRef = sema.curNodeRef();

    switch (tok.id)
    {
        case TokenId::TypeS8:
            sema.setType(nodeRef, typeMgr.typeInt(8, TypeInfo::Sign::Signed));
            return Result::Continue;
        case TokenId::TypeS16:
            sema.setType(nodeRef, typeMgr.typeInt(16, TypeInfo::Sign::Signed));
            return Result::Continue;
        case TokenId::TypeS32:
            sema.setType(nodeRef, typeMgr.typeInt(32, TypeInfo::Sign::Signed));
            return Result::Continue;
        case TokenId::TypeS64:
            sema.setType(nodeRef, typeMgr.typeInt(64, TypeInfo::Sign::Signed));
            return Result::Continue;

        case TokenId::TypeU8:
            sema.setType(nodeRef, typeMgr.typeInt(8, TypeInfo::Sign::Unsigned));
            return Result::Continue;
        case TokenId::TypeU16:
            sema.setType(nodeRef, typeMgr.typeInt(16, TypeInfo::Sign::Unsigned));
            return Result::Continue;
        case TokenId::TypeU32:
            sema.setType(nodeRef, typeMgr.typeInt(32, TypeInfo::Sign::Unsigned));
            return Result::Continue;
        case TokenId::TypeU64:
            sema.setType(nodeRef, typeMgr.typeInt(64, TypeInfo::Sign::Unsigned));
            return Result::Continue;

        case TokenId::TypeF32:
            sema.setType(nodeRef, typeMgr.typeF32());
            return Result::Continue;
        case TokenId::TypeF64:
            sema.setType(nodeRef, typeMgr.typeF64());
            return Result::Continue;

        case TokenId::TypeBool:
            sema.setType(nodeRef, typeMgr.typeBool());
            return Result::Continue;
        case TokenId::TypeString:
            sema.setType(nodeRef, typeMgr.typeString());
            return Result::Continue;

        case TokenId::TypeVoid:
            sema.setType(nodeRef, typeMgr.typeVoid());
            return Result::Continue;
        case TokenId::TypeAny:
            sema.setType(nodeRef, typeMgr.typeAny());
            return Result::Continue;
        case TokenId::TypeCString:
            sema.setType(nodeRef, typeMgr.typeCString());
            return Result::Continue;
        case TokenId::TypeRune:
            sema.setType(nodeRef, typeMgr.typeRune());
            return Result::Continue;
        case TokenId::TypeTypeInfo:
            sema.setType(nodeRef, typeMgr.typeTypeInfo());
            return Result::Continue;

        default:
            break;
    }

    SWC_INTERNAL_ERROR();
}

Result AstVariadicType::semaPostNode(Sema& sema)
{
    sema.setType(sema.curNodeRef(), sema.typeMgr().typeVariadic());
    return Result::Continue;
}

Result AstTypedVariadicType::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeView = sema.nodeView(nodeTypeRef);
    const TypeInfo     ty       = TypeInfo::makeTypedVariadic(nodeView.typeRef);
    const TypeRef      typeRef  = sema.typeMgr().addType(ty);
    sema.setType(sema.curNodeRef(), typeRef);
    return Result::Continue;
}

Result AstValuePointerType::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeView = sema.nodeView(nodePointeeTypeRef);
    const TypeInfo     ty       = TypeInfo::makeValuePointer(nodeView.typeRef);
    const TypeRef      typeRef  = sema.typeMgr().addType(ty);
    sema.setType(sema.curNodeRef(), typeRef);
    return Result::Continue;
}

Result AstBlockPointerType::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeView = sema.nodeView(nodePointeeTypeRef);
    const TypeInfo     ty       = TypeInfo::makeBlockPointer(nodeView.typeRef);
    const TypeRef      typeRef  = sema.typeMgr().addType(ty);
    sema.setType(sema.curNodeRef(), typeRef);
    return Result::Continue;
}

Result AstReferenceType::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeView = sema.nodeView(nodePointeeTypeRef);
    const TypeInfo     ty       = TypeInfo::makeReference(nodeView.typeRef);
    const TypeRef      typeRef  = sema.typeMgr().addType(ty);
    sema.setType(sema.curNodeRef(), typeRef);
    return Result::Continue;
}

Result AstMoveRefType::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeView = sema.nodeView(nodePointeeTypeRef);
    const TypeInfo     ty       = TypeInfo::makeMoveReference(nodeView.typeRef);
    const TypeRef      typeRef  = sema.typeMgr().addType(ty);
    sema.setType(sema.curNodeRef(), typeRef);
    return Result::Continue;
}

Result AstSliceType::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeView = sema.nodeView(nodePointeeTypeRef);

    if (nodeView.typeRef == sema.typeMgr().typeVoid())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_bad_slice_element_type, nodePointeeTypeRef);
        diag.addArgument(Diagnostic::ARG_TYPE, nodeView.typeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    const TypeInfo ty      = TypeInfo::makeSlice(nodeView.typeRef);
    const TypeRef  typeRef = sema.typeMgr().addType(ty);
    sema.setType(sema.curNodeRef(), typeRef);
    return Result::Continue;
}

Result AstQualifiedType::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeView = sema.nodeView(nodeTypeRef);
    SWC_ASSERT(nodeView.type);

    TypeInfoFlags typeFlags = TypeInfoFlagsE::Zero;
    if (this->hasFlag(AstQualifiedTypeFlagsE::Const))
    {
        switch (nodeView.type->kind())
        {
            case TypeInfoKind::ValuePointer:
            case TypeInfoKind::BlockPointer:
            case TypeInfoKind::Reference:
            case TypeInfoKind::MoveReference:
            case TypeInfoKind::Slice:
                break;
            default:
                const SourceView& srcView     = sema.compiler().srcView(srcViewRef());
                const TokenRef    constTokRef = srcView.findRightFrom(tokRef(), {TokenId::KwdConst});
                auto              diag        = SemaError::report(sema, DiagnosticId::sema_err_bad_type_qualifier, SourceCodeRef{srcViewRef(), constTokRef});
                diag.addArgument(Diagnostic::ARG_TYPE, nodeView.typeRef);
                diag.report(sema.ctx());
                return Result::Error;
        }

        typeFlags.add(TypeInfoFlagsE::Const);
    }

    if (this->hasFlag(AstQualifiedTypeFlagsE::Nullable))
    {
        switch (nodeView.type->kind())
        {
            case TypeInfoKind::ValuePointer:
            case TypeInfoKind::BlockPointer:
            case TypeInfoKind::Slice:
            case TypeInfoKind::String:
            case TypeInfoKind::CString:
            case TypeInfoKind::Any:
                break;
            default:
                const SourceView& srcView     = sema.compiler().srcView(srcViewRef());
                const TokenRef    constTokRef = srcView.findRightFrom(tokRef(), {TokenId::ModifierNullable});
                auto              diag        = SemaError::report(sema, DiagnosticId::sema_err_bad_type_qualifier, SourceCodeRef{srcViewRef(), constTokRef});
                diag.addArgument(Diagnostic::ARG_TYPE, nodeView.typeRef);
                diag.report(sema.ctx());
                return Result::Error;
        }

        typeFlags.add(TypeInfoFlagsE::Nullable);
    }

    TypeRef      typeRef;
    TypeManager& typeMgr = sema.typeMgr();
    switch (nodeView.type->kind())
    {
        case TypeInfoKind::ValuePointer:
            typeRef = typeMgr.addType(TypeInfo::makeValuePointer(nodeView.type->payloadTypeRef(), typeFlags));
            break;
        case TypeInfoKind::BlockPointer:
            typeRef = typeMgr.addType(TypeInfo::makeBlockPointer(nodeView.type->payloadTypeRef(), typeFlags));
            break;
        case TypeInfoKind::Reference:
            typeRef = typeMgr.addType(TypeInfo::makeReference(nodeView.type->payloadTypeRef(), typeFlags));
            break;
        case TypeInfoKind::MoveReference:
            typeRef = typeMgr.addType(TypeInfo::makeMoveReference(nodeView.type->payloadTypeRef(), typeFlags));
            break;
        case TypeInfoKind::Slice:
            typeRef = typeMgr.addType(TypeInfo::makeSlice(nodeView.type->payloadTypeRef(), typeFlags));
            break;
        case TypeInfoKind::String:
            typeRef = typeMgr.addType(TypeInfo::makeString(typeFlags));
            break;
        case TypeInfoKind::CString:
            typeRef = typeMgr.addType(TypeInfo::makeCString(typeFlags));
            break;
        case TypeInfoKind::Any:
            typeRef = typeMgr.addType(TypeInfo::makeAny(typeFlags));
            break;
        default:
            SWC_UNREACHABLE();
    }

    sema.setType(sema.curNodeRef(), typeRef);
    return Result::Continue;
}

Result AstNamedType::semaPostNode(Sema& sema)
{
    SemaNodeView nodeView = sema.nodeView(nodeIdentRef);
    SWC_ASSERT(nodeView.sym);

    // If we matched against the interface implementation block in a struct,
    // then we replace it with the corresponding interface type
    if (nodeView.sym->isImpl() && nodeView.type->isInterface())
    {
        sema.setSymbol(nodeIdentRef, &nodeView.type->payloadSymInterface());
        nodeView.compute(sema, nodeIdentRef);
    }

    if (!nodeView.sym->isType())
    {
        AstNodeRef                 nodeRef  = nodeIdentRef;
        const AstMemberAccessExpr* nodeQual = nodeView.node->safeCast<AstMemberAccessExpr>();
        if (nodeQual)
            nodeRef = nodeQual->nodeRightRef;
        SemaError::raise(sema, DiagnosticId::sema_err_not_type, nodeRef);
        return Result::Error;
    }

    sema.inheritPayload(*this, nodeIdentRef);
    return Result::Continue;
}

Result AstArrayType::semaPostNode(Sema& sema) const
{
    TaskContext&       ctx      = sema.ctx();
    const SemaNodeView nodeView = sema.nodeView(nodePointeeTypeRef);

    // Unknown dimension [?]
    if (spanDimensionsRef.isInvalid())
    {
        const TypeInfo tyA     = TypeInfo::makeArray({}, nodeView.typeRef);
        const TypeRef  typeRef = sema.typeMgr().addType(tyA);
        sema.setType(sema.curNodeRef(), typeRef);
        return Result::Continue;
    }

    // Value-check
    SmallVector<AstNodeRef> out;
    sema.ast().appendNodes(out, spanDimensionsRef);

    SmallVector<uint64_t> dims;
    for (const auto& dimRef : out)
    {
        SemaNodeView dimView = sema.nodeView(dimRef);

        RESULT_VERIFY(SemaCheck::isValue(sema, dimView.nodeRef));
        RESULT_VERIFY(SemaCheck::isConstant(sema, dimView.nodeRef));

        if (!dimView.cst->isInt())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_dim_not_int, dimView.nodeRef);
            diag.addArgument(Diagnostic::ARG_TYPE, dimView.cst->typeRef());
            diag.report(ctx);
            return Result::Error;
        }

        if (dimView.cst->getInt().isNegative())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_dim_negative, dimView.nodeRef);
            diag.addArgument(Diagnostic::ARG_VALUE, dimView.cst->toString(ctx));
            diag.report(ctx);
            return Result::Error;
        }

        ConstantRef newCstRef;
        RESULT_VERIFY(Cast::concretizeConstant(sema, newCstRef, dimView.nodeRef, dimView.cstRef, TypeInfo::Sign::Unsigned));

        const ConstantValue& newCst = sema.cstMgr().get(newCstRef);
        const int64_t        dim    = newCst.getInt().asI64();
        if (dim == 0)
            return SemaError::raise(sema, DiagnosticId::sema_err_array_dim_zero, dimView.nodeRef);
        dims.push_back(dim);
    }

    const TypeInfo ty      = TypeInfo::makeArray(dims, nodeView.typeRef);
    const TypeRef  typeRef = sema.typeMgr().addType(ty);
    sema.setType(sema.curNodeRef(), typeRef);
    return Result::Continue;
}

Result AstCompilerTypeExpr::semaPostNode(Sema& sema) const
{
    TaskContext&        ctx     = sema.ctx();
    const TypeRef       typeRef = sema.typeRefOf(nodeTypeRef);
    const ConstantValue cst     = ConstantValue::makeTypeValue(ctx, typeRef);
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, cst));
    return Result::Continue;
}

Result AstAliasDecl::semaPreDecl(Sema& sema) const
{
    SemaHelpers::registerSymbol<SymbolAlias>(sema, *this, tokNameRef);
    return Result::SkipChildren;
}

Result AstAliasDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);
    const Symbol& sym = sema.symbolOf(sema.curNodeRef());
    return Match::ghosting(sema, sym);
}

Result AstAliasDecl::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeView = sema.nodeView(nodeExprRef);
    if (!nodeView.type && !nodeView.sym)
        return SemaError::raise(sema, DiagnosticId::sema_err_invalid_alias, nodeExprRef);

    SymbolAlias& sym = sema.symbolOf(sema.curNodeRef()).cast<SymbolAlias>();

    if (sym.isStrict() && nodeView.sym && !nodeView.sym->isType())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_not_type, nodeExprRef);
        diag.addNote(DiagnosticId::sema_note_strict_alias);
        diag.report(sema.ctx());
        return Result::Error;
    }

    sym.setAliasedSymbol(nodeView.sym);
    sym.setUnderlyingTypeRef(nodeView.typeRef);

    if (sym.isStrict())
    {
        const TypeInfo ty      = TypeInfo::makeAlias(&sym);
        const TypeRef  typeRef = sema.typeMgr().addType(ty);
        sym.setTypeRef(typeRef);
    }
    else
    {
        sym.setTypeRef(nodeView.typeRef);
    }

    sym.setTyped(sema.ctx());
    sym.setSemaCompleted(sema.ctx());
    return Result::Continue;
}

Result AstLambdaType::semaPostNode(Sema& sema) const
{
    TaskContext& ctx = sema.ctx();

    SymbolFunction* const symFunc = Symbol::make<SymbolFunction>(ctx, this, tokRef(), IdentifierRef::invalid(), SymbolFlagsE::Zero);

    SmallVector<AstNodeRef> params;
    sema.ast().appendNodes(params, spanParamsRef);

    for (const auto& paramRef : params)
    {
        const AstLambdaParam* param        = sema.node(paramRef).cast<AstLambdaParam>();
        TypeRef               paramTypeRef = sema.typeRefOf(param->nodeTypeRef);
        SWC_ASSERT(paramTypeRef.isValid());

        IdentifierRef idRef = IdentifierRef::invalid();
        if (param->hasFlag(AstLambdaParamFlagsE::Named))
            idRef = sema.idMgr().addIdentifier(ctx, param->codeRef());

        SymbolVariable* const symVar = Symbol::make<SymbolVariable>(ctx, param, param->tokRef(), idRef, SymbolFlagsE::Zero);
        symVar->setTypeRef(paramTypeRef);

        symFunc->addParameter(symVar);
        if (idRef.isValid())
            symFunc->addSymbol(ctx, symVar, false);
    }

    TypeRef returnType = ctx.typeMgr().typeVoid();
    if (nodeReturnTypeRef.isValid())
        returnType = sema.typeRefOf(nodeReturnTypeRef);
    symFunc->setReturnTypeRef(returnType);
    symFunc->setExtraFlags(flags());

    const TypeInfo ti      = TypeInfo::makeFunction(symFunc, TypeInfoFlagsE::Zero);
    const TypeRef  typeRef = sema.typeMgr().addType(ti);
    symFunc->setTypeRef(typeRef);
    sema.setType(sema.curNodeRef(), typeRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
