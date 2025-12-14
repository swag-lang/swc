#include "pch.h"
#include "Parser/AstVisit.h"
#include "Sema/Constant/ConstantManager.h"
#include "Sema/Helpers/SemaInfo.h"
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
            sema.setType(nodeRef, typeMgr.getTypeInt(8, false));
            return AstVisitStepResult::Continue;
        case TokenId::TypeS16:
            sema.setType(nodeRef, typeMgr.getTypeInt(16, false));
            return AstVisitStepResult::Continue;
        case TokenId::TypeS32:
            sema.setType(nodeRef, typeMgr.getTypeInt(32, false));
            return AstVisitStepResult::Continue;
        case TokenId::TypeS64:
            sema.setType(nodeRef, typeMgr.getTypeInt(64, false));
            return AstVisitStepResult::Continue;

        case TokenId::TypeU8:
            sema.setType(nodeRef, typeMgr.getTypeInt(8, true));
            return AstVisitStepResult::Continue;
        case TokenId::TypeU16:
            sema.setType(nodeRef, typeMgr.getTypeInt(16, true));
            return AstVisitStepResult::Continue;
        case TokenId::TypeU32:
            sema.setType(nodeRef, typeMgr.getTypeInt(32, true));
            return AstVisitStepResult::Continue;
        case TokenId::TypeU64:
            sema.setType(nodeRef, typeMgr.getTypeInt(64, true));
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

    sema.raiseInternalError(*this);
    return AstVisitStepResult::Stop;
}

AstVisitStepResult AstValueType::semaPostNode(Sema& sema) const
{
    auto&               ctx     = sema.ctx();
    const TypeRef       typeRef = sema.typeRefOf(nodeTypeRef);
    const ConstantValue cst     = ConstantValue::makeTypeInfo(ctx, typeRef);
    sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, cst));
    return AstVisitStepResult::Continue;
}

SWC_END_NAMESPACE()
