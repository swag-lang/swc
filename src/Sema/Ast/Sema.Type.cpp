#include "pch.h"
#include "Sema/Core/Sema.h"
#include "Parser/AstVisit.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Core/SemaNodeView.h"
#include "Sema/Helpers/SemaCheck.h"
#include "Sema/Helpers/SemaError.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

AstStepResult AstBuiltinType::semaPostNode(Sema& sema) const
{
    const auto&      tok     = sema.token(srcViewRef(), tokRef());
    const auto&      typeMgr = sema.typeMgr();
    const AstNodeRef nodeRef = sema.curNodeRef();

    switch (tok.id)
    {
        case TokenId::TypeS8:
            sema.setType(nodeRef, typeMgr.typeInt(8, TypeInfo::Sign::Signed));
            return AstStepResult::Continue;
        case TokenId::TypeS16:
            sema.setType(nodeRef, typeMgr.typeInt(16, TypeInfo::Sign::Signed));
            return AstStepResult::Continue;
        case TokenId::TypeS32:
            sema.setType(nodeRef, typeMgr.typeInt(32, TypeInfo::Sign::Signed));
            return AstStepResult::Continue;
        case TokenId::TypeS64:
            sema.setType(nodeRef, typeMgr.typeInt(64, TypeInfo::Sign::Signed));
            return AstStepResult::Continue;

        case TokenId::TypeU8:
            sema.setType(nodeRef, typeMgr.typeInt(8, TypeInfo::Sign::Unsigned));
            return AstStepResult::Continue;
        case TokenId::TypeU16:
            sema.setType(nodeRef, typeMgr.typeInt(16, TypeInfo::Sign::Unsigned));
            return AstStepResult::Continue;
        case TokenId::TypeU32:
            sema.setType(nodeRef, typeMgr.typeInt(32, TypeInfo::Sign::Unsigned));
            return AstStepResult::Continue;
        case TokenId::TypeU64:
            sema.setType(nodeRef, typeMgr.typeInt(64, TypeInfo::Sign::Unsigned));
            return AstStepResult::Continue;

        case TokenId::TypeF32:
            sema.setType(nodeRef, typeMgr.typeFloat(32));
            return AstStepResult::Continue;
        case TokenId::TypeF64:
            sema.setType(nodeRef, typeMgr.typeFloat(64));
            return AstStepResult::Continue;

        case TokenId::TypeBool:
            sema.setType(nodeRef, typeMgr.typeBool());
            return AstStepResult::Continue;
        case TokenId::TypeString:
            sema.setType(nodeRef, typeMgr.typeString());
            return AstStepResult::Continue;

        case TokenId::TypeVoid:
            sema.setType(nodeRef, typeMgr.typeVoid());
            return AstStepResult::Continue;
        case TokenId::TypeAny:
            sema.setType(nodeRef, typeMgr.typeAny());
            return AstStepResult::Continue;
        case TokenId::TypeCString:
            sema.setType(nodeRef, typeMgr.typeCString());
            return AstStepResult::Continue;
        case TokenId::TypeRune:
            sema.setType(nodeRef, typeMgr.typeRune());
            return AstStepResult::Continue;

        default:
            break;
    }

    return SemaError::raiseInternal(sema, *this);
}

AstStepResult AstValueType::semaPostNode(Sema& sema) const
{
    auto&               ctx     = sema.ctx();
    const TypeRef       typeRef = sema.typeRefOf(nodeTypeRef);
    const ConstantValue cst     = ConstantValue::makeTypeValue(ctx, typeRef);
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, cst));
    return AstStepResult::Continue;
}

AstStepResult AstValuePointerType::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeView(sema, nodePointeeTypeRef);
    const TypeInfo     ty      = TypeInfo::makeValuePointer(nodeView.typeRef);
    const TypeRef      typeRef = sema.typeMgr().addType(ty);
    sema.setType(sema.curNodeRef(), typeRef);
    return AstStepResult::Continue;
}

AstStepResult AstBlockPointerType::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeView(sema, nodePointeeTypeRef);
    const TypeInfo     ty      = TypeInfo::makeBlockPointer(nodeView.typeRef);
    const TypeRef      typeRef = sema.typeMgr().addType(ty);
    sema.setType(sema.curNodeRef(), typeRef);
    return AstStepResult::Continue;
}

AstStepResult AstSliceType::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeView(sema, nodePointeeTypeRef);

    if (nodeView.typeRef == sema.typeMgr().typeVoid())
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_bad_slice_element_type, nodePointeeTypeRef);
        diag.addArgument(Diagnostic::ARG_TYPE, nodeView.typeRef);
        diag.report(sema.ctx());
        return AstStepResult::Stop;
    }

    const TypeInfo ty      = TypeInfo::makeSlice(nodeView.typeRef);
    const TypeRef  typeRef = sema.typeMgr().addType(ty);
    sema.setType(sema.curNodeRef(), typeRef);
    return AstStepResult::Continue;
}

AstStepResult AstQualifiedType::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeView(sema, nodeTypeRef);
    SWC_ASSERT(nodeView.type);

    TypeInfoFlags flags = TypeInfoFlagsE::Zero;
    if (hasParserFlag(Const))
    {
        switch (nodeView.type->kind())
        {
            case TypeInfoKind::ValuePointer:
            case TypeInfoKind::BlockPointer:
            case TypeInfoKind::Slice:
                break;
            default:
                const SourceView& srcView     = sema.compiler().srcView(srcViewRef());
                const TokenRef    constTokRef = srcView.findRightFrom(tokRef(), {TokenId::KwdConst});
                auto              diag        = SemaError::report(sema, DiagnosticId::sema_err_bad_type_qualifier, srcViewRef(), constTokRef);
                diag.addArgument(Diagnostic::ARG_TYPE, nodeView.typeRef);
                diag.report(sema.ctx());
                return AstStepResult::Stop;
        }

        flags.add(TypeInfoFlagsE::Const);
    }

    if (hasParserFlag(Nullable))
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
                auto              diag        = SemaError::report(sema, DiagnosticId::sema_err_bad_type_qualifier, srcViewRef(), constTokRef);
                diag.addArgument(Diagnostic::ARG_TYPE, nodeView.typeRef);
                diag.report(sema.ctx());
                return AstStepResult::Stop;
        }

        flags.add(TypeInfoFlagsE::Nullable);
    }

    TypeRef      typeRef;
    TypeManager& typeMgr = sema.typeMgr();
    switch (nodeView.type->kind())
    {
        case TypeInfoKind::ValuePointer:
            typeRef = typeMgr.addType(TypeInfo::makeValuePointer(nodeView.type->typeRef(), flags));
            break;
        case TypeInfoKind::BlockPointer:
            typeRef = typeMgr.addType(TypeInfo::makeBlockPointer(nodeView.type->typeRef(), flags));
            break;
        case TypeInfoKind::Slice:
            typeRef = typeMgr.addType(TypeInfo::makeSlice(nodeView.type->typeRef(), flags));
            break;
        case TypeInfoKind::String:
            typeRef = typeMgr.addType(TypeInfo::makeString(flags));
            break;
        case TypeInfoKind::CString:
            typeRef = typeMgr.addType(TypeInfo::makeCString(flags));
            break;
        case TypeInfoKind::Any:
            typeRef = typeMgr.addType(TypeInfo::makeAny(flags));
            break;
        default:
            SWC_UNREACHABLE();
    }

    sema.setType(sema.curNodeRef(), typeRef);
    return AstStepResult::Continue;
}

AstStepResult AstNamedType::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeView(sema, nodeIdentRef);

    SWC_ASSERT(nodeView.sym);
    if (!nodeView.sym->isType())
    {
        AstNodeRef nodeRef  = nodeIdentRef;
        const auto nodeQual = nodeView.node->safeCast<AstMemberAccessExpr>();
        if (nodeQual)
            nodeRef = nodeQual->nodeRightRef;
        SemaError::raise(sema, DiagnosticId::sema_err_not_type, nodeRef);
        return AstStepResult::Stop;
    }

    sema.semaInherit(*this, nodeIdentRef);
    return AstStepResult::Continue;
}

AstStepResult AstArrayType::semaPostNode(Sema& sema) const
{
    auto&              ctx = sema.ctx();
    const SemaNodeView nodeView(sema, nodePointeeTypeRef);

    // Unknown dimension [?]
    if (spanDimensionsRef.isInvalid())
    {
        const TypeInfo tyA     = TypeInfo::makeArray({}, nodeView.typeRef);
        const TypeRef  typeRef = sema.typeMgr().addType(tyA);
        sema.setType(sema.curNodeRef(), typeRef);
        return AstStepResult::Continue;
    }

    // Value-check
    SmallVector<AstNodeRef> out;
    sema.ast().nodes(out, spanDimensionsRef);

    std::vector<uint64_t> dims;
    for (const auto& dimRef : out)
    {
        if (SemaCheck::isValueExpr(sema, dimRef) != AstStepResult::Continue)
            return AstStepResult::Stop;
        if (SemaCheck::isConstant(sema, dimRef) != AstStepResult::Continue)
            return AstStepResult::Stop;

        const ConstantRef    cstRef = sema.constantRefOf(dimRef);
        const ConstantValue& cst    = sema.constantOf(dimRef);
        if (!cst.isInt())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_dim_not_int, dimRef);
            diag.addArgument(Diagnostic::ARG_TYPE, cst.typeRef());
            diag.report(ctx);
            return AstStepResult::Stop;
        }

        if (cst.getInt().isNegative())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_dim_negative, dimRef);
            diag.addArgument(Diagnostic::ARG_VALUE, cst.toString(ctx));
            diag.report(ctx);
            return AstStepResult::Stop;
        }

        const ConstantRef newCstRef = sema.cstMgr().concretizeConstant(sema, dimRef, cstRef, TypeInfo::Sign::Unsigned);
        if (newCstRef.isInvalid())
            return AstStepResult::Stop;

        const ConstantValue& newCst = sema.cstMgr().get(newCstRef);
        const uint64_t       dim    = newCst.getInt().as64();
        if (dim == 0)
            return SemaError::raise(sema, DiagnosticId::sema_err_array_dim_zero, dimRef);
        dims.push_back(dim);
    }

    const TypeInfo ty      = TypeInfo::makeArray(dims, nodeView.typeRef);
    const TypeRef  typeRef = sema.typeMgr().addType(ty);
    sema.setType(sema.curNodeRef(), typeRef);
    return AstStepResult::Continue;
}

AstStepResult AstCompilerTypeExpr::semaPostNode(Sema& sema)
{
    sema.semaInherit(*this, nodeTypeRef);
    return AstStepResult::Continue;
}

SWC_END_NAMESPACE()
