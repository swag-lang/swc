#include "pch.h"

#include "Helpers/SemaCheck.h"
#include "Helpers/SemaError.h"
#include "Helpers/SemaNodeView.h"
#include "Os/Os.h"
#include "Parser/AstVisit.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Sema.h"
#include "Sema/Type/TypeManager.h"

SWC_BEGIN_NAMESPACE()

AstVisitStepResult AstBuiltinType::semaPostNode(Sema& sema) const
{
    const auto&      tok     = sema.token(srcViewRef(), tokRef());
    const auto&      typeMgr = sema.typeMgr();
    const AstNodeRef nodeRef = sema.curNodeRef();

    switch (tok.id)
    {
        case TokenId::TypeS8:
            sema.setType(nodeRef, typeMgr.getTypeInt(8, TypeInfo::Sign::Signed));
            return AstVisitStepResult::Continue;
        case TokenId::TypeS16:
            sema.setType(nodeRef, typeMgr.getTypeInt(16, TypeInfo::Sign::Signed));
            return AstVisitStepResult::Continue;
        case TokenId::TypeS32:
            sema.setType(nodeRef, typeMgr.getTypeInt(32, TypeInfo::Sign::Signed));
            return AstVisitStepResult::Continue;
        case TokenId::TypeS64:
            sema.setType(nodeRef, typeMgr.getTypeInt(64, TypeInfo::Sign::Signed));
            return AstVisitStepResult::Continue;

        case TokenId::TypeU8:
            sema.setType(nodeRef, typeMgr.getTypeInt(8, TypeInfo::Sign::Unsigned));
            return AstVisitStepResult::Continue;
        case TokenId::TypeU16:
            sema.setType(nodeRef, typeMgr.getTypeInt(16, TypeInfo::Sign::Unsigned));
            return AstVisitStepResult::Continue;
        case TokenId::TypeU32:
            sema.setType(nodeRef, typeMgr.getTypeInt(32, TypeInfo::Sign::Unsigned));
            return AstVisitStepResult::Continue;
        case TokenId::TypeU64:
            sema.setType(nodeRef, typeMgr.getTypeInt(64, TypeInfo::Sign::Unsigned));
            return AstVisitStepResult::Continue;

        case TokenId::TypeF32:
            sema.setType(nodeRef, typeMgr.getTypeFloat(32));
            return AstVisitStepResult::Continue;
        case TokenId::TypeF64:
            sema.setType(nodeRef, typeMgr.getTypeFloat(64));
            return AstVisitStepResult::Continue;

        case TokenId::TypeBool:
            sema.setType(nodeRef, typeMgr.getTypeBool());
            return AstVisitStepResult::Continue;
        case TokenId::TypeString:
            sema.setType(nodeRef, typeMgr.getTypeString());
            return AstVisitStepResult::Continue;

        case TokenId::TypeVoid:
            sema.setType(nodeRef, typeMgr.getTypeVoid());
            return AstVisitStepResult::Continue;
        case TokenId::TypeAny:
            sema.setType(nodeRef, typeMgr.getTypeAny());
            return AstVisitStepResult::Continue;
        case TokenId::TypeCString:
            sema.setType(nodeRef, typeMgr.getTypeCString());
            return AstVisitStepResult::Continue;
        case TokenId::TypeRune:
            sema.setType(nodeRef, typeMgr.getTypeRune());
            return AstVisitStepResult::Continue;

        default:
            break;
    }

    SemaError::raiseInternal(sema, *this);
    return AstVisitStepResult::Stop;
}

AstVisitStepResult AstValueType::semaPostNode(Sema& sema) const
{
    auto&               ctx     = sema.ctx();
    const TypeRef       typeRef = sema.typeRefOf(nodeTypeRef);
    const ConstantValue cst     = ConstantValue::makeTypeValue(ctx, typeRef);
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, cst));
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstValuePointerType::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeView(sema, nodePointeeTypeRef);
    const TypeInfo     ty      = TypeInfo::makeValuePointer(nodeView.typeRef);
    const TypeRef      typeRef = sema.typeMgr().addType(ty);
    sema.setType(sema.curNodeRef(), typeRef);
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstBlockPointerType::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeView(sema, nodePointeeTypeRef);
    const TypeInfo     ty      = TypeInfo::makeBlockPointer(nodeView.typeRef);
    const TypeRef      typeRef = sema.typeMgr().addType(ty);
    sema.setType(sema.curNodeRef(), typeRef);
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstSliceType::semaPostNode(Sema& sema) const
{
    const SemaNodeView nodeView(sema, nodePointeeTypeRef);
    const TypeInfo     ty      = TypeInfo::makeSlice(nodeView.typeRef);
    const TypeRef      typeRef = sema.typeMgr().addType(ty);
    sema.setType(sema.curNodeRef(), typeRef);
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstQualifiedType::semaPostNode(Sema& sema) const
{
    TypeInfoFlags flags = TypeInfoFlagsE::Zero;
    if (hasParserFlag(Const))
        flags.add(TypeInfoFlagsE::Const);
    if (hasParserFlag(Nullable))
        flags.add(TypeInfoFlagsE::Nullable);

    const SemaNodeView nodeView(sema, nodeTypeRef);
    TypeRef            typeRef;
    if (nodeView.type->isValuePointer())
        typeRef = sema.typeMgr().addType(TypeInfo::makeValuePointer(nodeView.type->typeRef(), flags));
    else if (nodeView.type->isBlockPointer())
        typeRef = sema.typeMgr().addType(TypeInfo::makeBlockPointer(nodeView.type->typeRef(), flags));
    else if (nodeView.type->isSlice())
        typeRef = sema.typeMgr().addType(TypeInfo::makeSlice(nodeView.type->typeRef(), flags));
    else
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_bad_type_qualifier, srcViewRef(), tokRef());
        diag.addArgument(Diagnostic::ARG_TYPE, nodeView.typeRef);
        diag.report(sema.ctx());
        return AstVisitStepResult::Stop;
    }

    sema.setType(sema.curNodeRef(), typeRef);
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstNamedType::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeView(sema, nodeIdentRef);

    SWC_ASSERT(nodeView.sym);
    if (!nodeView.sym->isType())
    {
        const auto diag = SemaError::report(sema, DiagnosticId::sema_err_not_a_type, nodeIdentRef);
        diag.report(sema.ctx());
        return AstVisitStepResult::Stop;
    }

    sema.semaInherit(*this, nodeIdentRef);
    return AstVisitStepResult::Continue;
}

AstVisitStepResult AstArrayType::semaPostNode(Sema& sema)
{
    const SemaNodeView nodeView(sema, nodePointeeTypeRef);
    
    // Unknown dimension [?]
    if (spanDimensionsRef.isInvalid())
    {
        const TypeInfo     ty      = TypeInfo::makeArray({}, nodeView.typeRef);
        const TypeRef      typeRef = sema.typeMgr().addType(ty);
        sema.setType(sema.curNodeRef(), typeRef);
        return AstVisitStepResult::Continue;
    }
    
    // Value-check
    SmallVector<AstNodeRef> out;
    sema.ast().nodes(out, spanDimensionsRef);
    
    std::vector<uint32_t> dims;
    for (const auto& dimRef : out)
    {
        if (SemaCheck::isValueExpr(sema, dimRef) != Result::Success)
            return AstVisitStepResult::Stop;
        if (SemaCheck::isConstant(sema, dimRef) != Result::Success)
            return AstVisitStepResult::Stop;
        
        const ConstantValue& cst = sema.constantOf(dimRef);
        if (!cst.isInt())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_dim_not_int, dimRef);
            diag.addArgument(Diagnostic::ARG_TYPE, cst.typeRef());
            diag.report(sema.ctx());
            return AstVisitStepResult::Stop;
        }
        
        const int64_t dim = cst.getInt().asI64();
        if (dim == 0)
        {
            SemaError::raise(sema, DiagnosticId::sema_err_array_dim_zero, dimRef);
            return AstVisitStepResult::Stop;
        }
        
        if (dim < 0)
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_array_dim_negative, dimRef);
            diag.addArgument(Diagnostic::ARG_VALUE, cst.toString(sema.ctx()));
            diag.report(sema.ctx());
            return AstVisitStepResult::Stop;
        }
        
        dims.push_back(static_cast<uint32_t>(dim));
    }
    
    const TypeInfo     ty      = TypeInfo::makeArray(dims, nodeView.typeRef);
    const TypeRef      typeRef = sema.typeMgr().addType(ty);
    sema.setType(sema.curNodeRef(), typeRef);
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
