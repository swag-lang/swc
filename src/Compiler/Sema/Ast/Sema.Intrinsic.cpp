#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantLower.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"

SWC_BEGIN_NAMESPACE();

Result AstIntrinsicValue::semaPostNode(Sema& sema)
{
    sema.setIsValue(*this);

    const Token& tok = sema.token(codeRef());
    switch (tok.id)
    {
        case TokenId::IntrinsicIndex:
            return Result::Continue;

        default:
            SWC_INTERNAL_ERROR();
    }
}

namespace
{
    void setDataOfPointerConstant(Sema& sema, TypeRef resultTypeRef, uint64_t ptrValue)
    {
        auto&           ctx        = sema.ctx();
        const TypeInfo& resultType = sema.typeMgr().get(resultTypeRef);

        ConstantValue resultCst;
        if (resultType.isValuePointer())
        {
            resultCst = ConstantValue::makeValuePointer(ctx, resultType.payloadTypeRef(), ptrValue, resultType.flags());
        }
        else
        {
            SWC_ASSERT(resultType.isBlockPointer());
            resultCst = ConstantValue::makeBlockPointer(ctx, resultType.payloadTypeRef(), ptrValue, resultType.flags());
        }

        resultCst.setTypeRef(resultTypeRef);
        sema.setConstant(sema.curNodeRef(), sema.cstMgr().addConstant(ctx, resultCst));
    }

    uint64_t materializeConstantAndGetAddress(Sema& sema, const SemaNodeView& nodeView)
    {
        SWC_ASSERT(nodeView.type);
        const uint64_t sizeOf = nodeView.type->sizeOf(sema.ctx());
        if (!sizeOf)
            return 0;

        SmallVector<std::byte> storage(sizeOf);
        ByteSpanRW             storageSpan{storage.data(), storage.size()};
        std::memset(storageSpan.data(), 0, storageSpan.size());
        ConstantLower::lowerToBytes(sema, storageSpan, nodeView.cstRef, nodeView.typeRef);

        const std::string_view persistentStorage = sema.cstMgr().addPayloadBuffer(asStringView(asByteSpan(storageSpan)));
        return reinterpret_cast<uint64_t>(persistentStorage.data());
    }

    void trySetDataOfConstant(Sema& sema, TypeRef resultTypeRef, const SemaNodeView& nodeView)
    {
        if (!nodeView.cstRef.isValid())
            return;

        const ConstantValue& cst  = sema.cstMgr().get(nodeView.cstRef);
        const TypeInfo*      type = nodeView.type;
        SWC_ASSERT(type);

        uint64_t ptrValue = 0;

        if (cst.isNull())
        {
            ptrValue = 0;
        }
        else if (type->isString())
        {
            if (!cst.isString())
                return;

            ptrValue = reinterpret_cast<uint64_t>(cst.getString().data());
        }
        else if (type->isSlice())
        {
            if (cst.isSlice())
                ptrValue = reinterpret_cast<uint64_t>(cst.getSlice().data());
            else if (cst.isString())
                ptrValue = reinterpret_cast<uint64_t>(cst.getString().data());
            else
                return;
        }
        else if (type->isArray())
        {
            if (cst.isArray())
                ptrValue = reinterpret_cast<uint64_t>(cst.getArray().data());
            else if (cst.isAggregateArray())
                ptrValue = materializeConstantAndGetAddress(sema, nodeView);
            else
                return;
        }
        else if (type->isAnyPointer() || type->isCString())
        {
            if (cst.isString())
                ptrValue = reinterpret_cast<uint64_t>(cst.getString().data());
            else if (cst.isValuePointer())
                ptrValue = cst.getValuePointer();
            else if (cst.isBlockPointer())
                ptrValue = cst.getBlockPointer();
            else
                return;
        }
        else
        {
            return;
        }

        setDataOfPointerConstant(sema, resultTypeRef, ptrValue);
    }

    Result semaIntrinsicDataOf(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        SemaNodeView nodeView = sema.nodeView(children[0]);
        if (nodeView.sym && nodeView.sym->isConstant() && nodeView.cstRef.isInvalid())
        {
            RESULT_VERIFY(sema.waitSemaCompleted(nodeView.sym, sema.node(nodeView.nodeRef).codeRef()));
            nodeView.compute(sema, children[0]);
        }

        RESULT_VERIFY(SemaCheck::isValue(sema, nodeView.nodeRef));

        const TypeInfo* type = nodeView.type;

        TypeRef resultTypeRef = TypeRef::invalid();
        if (type->isString() || type->isCString())
        {
            resultTypeRef = sema.typeMgr().typeConstBlockPtrU8();
        }
        else if (type->isSlice())
        {
            const TypeInfo ty = TypeInfo::makeBlockPointer(type->payloadTypeRef(), type->flags());
            resultTypeRef     = sema.typeMgr().addType(ty);
        }
        else if (type->isArray())
        {
            const TypeInfo ty = TypeInfo::makeBlockPointer(type->payloadArrayElemTypeRef(), type->flags());
            resultTypeRef     = sema.typeMgr().addType(ty);
        }
        else if (type->isAny())
        {
            resultTypeRef = sema.typeMgr().typeBlockPtrVoid();
        }
        else if (type->isAnyPointer())
        {
            resultTypeRef = nodeView.typeRef;
        }

        if (!resultTypeRef.isValid())
            return SemaError::raiseInvalidType(sema, nodeView.nodeRef, nodeView.typeRef, sema.typeMgr().typeBlockPtrVoid());

        sema.setType(sema.curNodeRef(), resultTypeRef);
        trySetDataOfConstant(sema, resultTypeRef, nodeView);
        sema.setIsValue(node);
        return Result::Continue;
    }

    Result semaIntrinsicKindOf(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        const SemaNodeView nodeView = sema.nodeView(children[0]);

        RESULT_VERIFY(SemaCheck::isValue(sema, nodeView.nodeRef));

        if (!nodeView.type || !nodeView.type->isAny())
            return SemaError::raiseRequestedTypeFam(sema, nodeView.nodeRef, nodeView.typeRef, sema.typeMgr().typeAny());

        sema.setType(sema.curNodeRef(), sema.typeMgr().typeTypeInfo());
        sema.setIsValue(node);
        return Result::Continue;
    }

    Result semaIntrinsicCountOf(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        SWC_UNUSED(node);
        return SemaHelpers::intrinsicCountOf(sema, sema.curNodeRef(), children[0]);
    }

    Result semaIntrinsicMakeAny(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children)
    {
        const SemaNodeView nodeViewPtr  = sema.nodeView(children[0]);
        SemaNodeView       nodeViewType = sema.nodeView(children[1]);

        RESULT_VERIFY(SemaCheck::isValue(sema, nodeViewPtr.nodeRef));
        RESULT_VERIFY(SemaCheck::isValueOrTypeInfo(sema, nodeViewType));

        if (!nodeViewPtr.type->isValuePointer())
            return SemaError::raiseRequestedTypeFam(sema, nodeViewPtr.nodeRef, nodeViewPtr.typeRef, sema.typeMgr().typeValuePtrVoid());
        if (!nodeViewType.type->isAnyTypeInfo(sema.ctx()))
            return SemaError::raiseRequestedTypeFam(sema, nodeViewType.nodeRef, nodeViewType.typeRef, sema.typeMgr().typeTypeInfo());

        // Check if the pointer is void* or a pointer to the type defined in the right expression
        const TypeRef typeRefPointee = nodeViewPtr.type->payloadTypeRef();
        if (!sema.typeMgr().get(typeRefPointee).isVoid() && nodeViewType.cstRef.isValid())
        {
            const TypeRef typeRefTypeInfo = sema.cstMgr().makeTypeValue(sema, nodeViewType.cstRef);
            if (typeRefPointee != typeRefTypeInfo)
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_invalid_mkany_ptr, nodeViewPtr.nodeRef);
                diag.addArgument(Diagnostic::ARG_TYPE, nodeViewPtr.typeRef);
                diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, typeRefTypeInfo);
                diag.report(sema.ctx());
                return Result::Error;
            }
        }

        TypeInfoFlags flags = TypeInfoFlagsE::Zero;
        if (nodeViewPtr.type->isConst())
            flags.add(TypeInfoFlagsE::Const);

        const TypeRef typeRef = sema.typeMgr().addType(TypeInfo::makeAny(flags));
        sema.setType(sema.curNodeRef(), typeRef);
        sema.setIsValue(node);

        return Result::Continue;
    }

    Result semaIntrinsicMakeSlice(Sema& sema, AstIntrinsicCall& node, const SmallVector<AstNodeRef>& children, bool forString)
    {
        const SemaNodeView nodeViewPtr  = sema.nodeView(children[0]);
        SemaNodeView       nodeViewSize = sema.nodeView(children[1]);

        RESULT_VERIFY(SemaCheck::isValue(sema, nodeViewPtr.nodeRef));
        RESULT_VERIFY(SemaCheck::isValue(sema, nodeViewSize.nodeRef));

        if (!nodeViewPtr.type->isAnyPointer())
            return SemaError::raiseRequestedTypeFam(sema, nodeViewPtr.nodeRef, nodeViewPtr.typeRef, sema.typeMgr().typeBlockPtrVoid());

        RESULT_VERIFY(Cast::cast(sema, nodeViewSize, sema.typeMgr().typeU64(), CastKind::Implicit));

        TypeRef typeRef;
        if (forString)
        {
            TypeInfo ty = TypeInfo::makeString();
            typeRef     = sema.typeMgr().addType(ty);
        }
        else
        {
            TypeInfo ty = TypeInfo::makeSlice(nodeViewPtr.type->payloadTypeRef());
            if (nodeViewPtr.type->isConst())
                ty.addFlag(TypeInfoFlagsE::Const);
            typeRef = sema.typeMgr().addType(ty);
        }

        sema.setType(sema.curNodeRef(), typeRef);
        sema.setIsValue(node);
        return Result::Continue;
    }
}

Result AstIntrinsicCall::semaPostNode(Sema& sema)
{
    const Token&            tok = sema.token(codeRef());
    SmallVector<AstNodeRef> children;
    sema.ast().appendNodes(children, spanChildrenRef);

    switch (tok.id)
    {
        case TokenId::IntrinsicDataOf:
            return semaIntrinsicDataOf(sema, *this, children);
        case TokenId::IntrinsicKindOf:
            return semaIntrinsicKindOf(sema, *this, children);
        case TokenId::IntrinsicCountOf:
            return semaIntrinsicCountOf(sema, *this, children);
        case TokenId::IntrinsicMakeAny:
            return semaIntrinsicMakeAny(sema, *this, children);
        case TokenId::IntrinsicMakeSlice:
            return semaIntrinsicMakeSlice(sema, *this, children, false);
        case TokenId::IntrinsicMakeString:
            return semaIntrinsicMakeSlice(sema, *this, children, true);

        case TokenId::IntrinsicCVaStart:
        case TokenId::IntrinsicCVaEnd:
        case TokenId::IntrinsicCVaArg:
        case TokenId::IntrinsicMakeCallback:
        case TokenId::IntrinsicMakeInterface:
        case TokenId::IntrinsicIs:
        case TokenId::IntrinsicAs:
        case TokenId::IntrinsicTableOf:
            // TODO
            SWC_INTERNAL_ERROR();

        default:
            SWC_INTERNAL_ERROR();
    }
}

Result AstCountOfExpr::semaPostNode(Sema& sema) const
{
    return SemaHelpers::intrinsicCountOf(sema, sema.curNodeRef(), nodeExprRef);
}

SWC_END_NAMESPACE();
