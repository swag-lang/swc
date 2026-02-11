#include "pch.h"
#include "Compiler/Sema/Constant/ConstantEval.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantExtract.h"
#include "Compiler/Sema/Constant/ConstantFold.h"
#include "Compiler/Sema/Constant/ConstantIntrinsic.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

ConstantEval::ConstantEval(Sema& sema, std::span<const ConstantEval::ParamBinding> bindings) :
    sema_(&sema),
    bindings_(bindings)
{
}

Result ConstantEval::evalExpr(AstNodeRef exprRef, ConstantRef& out)
{
    return evalExprInternal(exprRef, out, true);
}

Result ConstantEval::evalExprInternal(AstNodeRef exprRef, ConstantRef& out, bool allowSubstitute)
{
    out = ConstantRef::invalid();
    if (allowSubstitute)
        exprRef = sema_->getSubstituteRef(exprRef);
    if (exprRef.isInvalid())
        return Result::Continue;

    const ConstantRef directRef = sema_->constantRefOf(exprRef);
    if (directRef.isValid())
    {
        out = directRef;
        return Result::Continue;
    }

    const AstNode& node = sema_->node(exprRef);
    switch (node.id())
    {
        case AstNodeId::Identifier:
            return evalIdentifier(exprRef, out);
        case AstNodeId::ParenExpr:
            return evalExprInternal(node.cast<AstParenExpr>()->nodeExprRef, out, allowSubstitute);
        case AstNodeId::UnaryExpr:
            return evalUnary(exprRef, node.cast<AstUnaryExpr>(), out);
        case AstNodeId::BinaryExpr:
            return evalBinary(exprRef, node.cast<AstBinaryExpr>(), out);
        case AstNodeId::RelationalExpr:
            return evalRelational(exprRef, node.cast<AstRelationalExpr>(), out);
        case AstNodeId::LogicalExpr:
            return evalLogical(exprRef, node.cast<AstLogicalExpr>(), out);
        case AstNodeId::ConditionalExpr:
            return evalConditional(exprRef, node.cast<AstConditionalExpr>(), out);
        case AstNodeId::NullCoalescingExpr:
            return evalNullCoalescing(exprRef, node.cast<AstNullCoalescingExpr>(), out);
        case AstNodeId::ExplicitCastExpr:
            return evalExplicitCast(exprRef, node.cast<AstExplicitCastExpr>(), out);
        case AstNodeId::ImplicitCastExpr:
            return evalImplicitCast(exprRef, node.cast<AstImplicitCastExpr>(), out);
        case AstNodeId::AutoCastExpr:
            return evalAutoCast(exprRef, node.cast<AstAutoCastExpr>(), out);
        case AstNodeId::MemberAccessExpr:
            return evalMemberAccess(exprRef, node.cast<AstMemberAccessExpr>(), out);
        case AstNodeId::IndexExpr:
            return evalIndex(exprRef, node.cast<AstIndexExpr>(), out);
        case AstNodeId::IndexListExpr:
            return evalIndexList(exprRef, node.cast<AstIndexListExpr>(), out);
        case AstNodeId::CountOfExpr:
            return evalCountOf(exprRef, node.cast<AstCountOfExpr>()->nodeExprRef, out);
        case AstNodeId::CallExpr:
            return evalCall(exprRef, node.cast<AstCallExpr>(), out);
        case AstNodeId::IntrinsicCallExpr:
            return evalIntrinsicCall(exprRef, node.cast<AstIntrinsicCallExpr>(), out);
        default:
            return Result::Continue;
    }
}
Result ConstantEval::evalIdentifier(AstNodeRef nodeRef, ConstantRef& out) const
{
    if (const SymbolVariable* param = lookupParameter(nodeRef))
    {
        for (const auto& binding : bindings_)
        {
            if (binding.sym == param)
            {
                out = binding.cstRef;
                return Result::Continue;
            }
        }
    }

    return Result::Continue;
}

const SymbolVariable* ConstantEval::lookupParameter(AstNodeRef nodeRef) const
{
    const Symbol* sym = nullptr;
    if (sema_->hasSymbol(nodeRef))
        sym = &sema_->symbolOf(nodeRef);
    else if (sema_->hasSymbolList(nodeRef))
    {
        const auto symbols = sema_->getSymbolList(nodeRef);
        if (symbols.size() == 1)
            sym = symbols.front();
    }

    if (sym && sym->isVariable())
    {
        const auto* var = sym->safeCast<SymbolVariable>();
        if (var)
        {
            for (const auto& binding : bindings_)
            {
                if (binding.sym == var)
                    return var;
            }

            return nullptr;
        }
    }

    const AstNode& node = sema_->node(nodeRef);
    if (!node.is(AstNodeId::Identifier))
        return nullptr;

    const IdentifierRef idRef = sema_->idMgr().addIdentifier(sema_->ctx(), node.codeRef());
    for (const auto& binding : bindings_)
    {
        if (binding.sym && binding.sym->idRef() == idRef)
            return binding.sym;
    }

    return nullptr;
}

AstNodeRef ConstantEval::mapArgumentRef(AstNodeRef argRef) const
{
    if (const SymbolVariable* param = lookupParameter(argRef))
    {
        for (const auto& binding : bindings_)
        {
            if (binding.sym == param && binding.argRef.isValid())
                return binding.argRef;
        }
    }

    return argRef;
}

Result ConstantEval::castConstant(AstNodeRef nodeRef, ConstantRef srcCstRef, TypeRef dstTypeRef, CastKind castKind, CastFlags castFlags, ConstantRef& out, TypeRef srcTypeRef) const
{
    out = ConstantRef::invalid();
    if (srcCstRef.isInvalid() || dstTypeRef.isInvalid())
        return Result::Continue;

    CastRequest castRequest(castKind);
    castRequest.flags        = castFlags;
    castRequest.errorNodeRef = nodeRef;
    castRequest.setConstantFoldingSrc(srcCstRef);

    if (srcTypeRef.isInvalid())
        srcTypeRef = sema_->cstMgr().get(srcCstRef).typeRef();
    if (srcTypeRef.isInvalid())
        return Result::Continue;
    const Result result = Cast::castAllowed(*sema_, castRequest, srcTypeRef, dstTypeRef);
    if (result == Result::Continue)
    {
        out = castRequest.constantFoldingResult();
        return Result::Continue;
    }

    if (result == Result::Error && castRequest.failure.diagId != DiagnosticId::None)
        return Cast::emitCastFailure(*sema_, castRequest.failure);

    return result;
}

Result ConstantEval::getConstIndex(AstNodeRef nodeArgRef, ConstantRef indexCstRef, int64_t& outIndex) const
{
    if (indexCstRef.isInvalid())
        return Result::Continue;

    const ConstantValue& indexCst = sema_->cstMgr().get(indexCstRef);
    const auto&          idxInt   = indexCst.getInt();
    if (!idxInt.fits64())
        return SemaError::raise(*sema_, DiagnosticId::sema_err_index_too_large, nodeArgRef);

    const TypeInfo& idxType = sema_->typeMgr().get(indexCst.typeRef());
    if (idxType.isIntSigned() && idxInt.isNegative())
    {
        auto diag = SemaError::report(*sema_, DiagnosticId::sema_err_index_negative, nodeArgRef);
        diag.addArgument(Diagnostic::ARG_VALUE, idxInt.asI64());
        diag.report(sema_->ctx());
        return Result::Error;
    }

    outIndex = idxInt.asI64();
    return Result::Continue;
}

Result ConstantEval::evalUnary(AstNodeRef, const AstUnaryExpr* node, ConstantRef& out)
{
    ConstantRef exprCst = ConstantRef::invalid();
    RESULT_VERIFY(evalExpr(node->nodeExprRef, exprCst));
    if (exprCst.isInvalid())
        return Result::Continue;

    SemaNodeView nodeView(*sema_, node->nodeExprRef);
    nodeView.setCstRef(*sema_, exprCst);

    ConstantRef  result;
    const Token& tok = sema_->token(node->codeRef());
    switch (tok.id)
    {
        case TokenId::SymMinus:
            RESULT_VERIFY(ConstantFold::unary(*sema_, result, tok.id, *node, nodeView));
            out = result;
            return Result::Continue;
        case TokenId::SymPlus:
            RESULT_VERIFY(ConstantFold::unary(*sema_, result, tok.id, *node, nodeView));
            out = result;
            return Result::Continue;
        case TokenId::SymBang:
            RESULT_VERIFY(ConstantFold::unary(*sema_, result, tok.id, *node, nodeView));
            out = result;
            return Result::Continue;
        case TokenId::SymTilde:
            RESULT_VERIFY(ConstantFold::unary(*sema_, result, tok.id, *node, nodeView));
            out = result;
            return Result::Continue;
        default:
            break;
    }

    return Result::Continue;
}

Result ConstantEval::evalBinary(AstNodeRef nodeRef, const AstBinaryExpr* node, ConstantRef& out)
{
    ConstantRef leftCst  = ConstantRef::invalid();
    ConstantRef rightCst = ConstantRef::invalid();
    RESULT_VERIFY(evalExpr(node->nodeLeftRef, leftCst));
    RESULT_VERIFY(evalExpr(node->nodeRightRef, rightCst));
    if (leftCst.isInvalid() || rightCst.isInvalid())
        return Result::Continue;

    SemaNodeView nodeLeftView(*sema_, node->nodeLeftRef);
    SemaNodeView nodeRightView(*sema_, node->nodeRightRef);
    nodeLeftView.setCstRef(*sema_, leftCst);
    nodeRightView.setCstRef(*sema_, rightCst);

    const Token& tok    = sema_->token(node->codeRef());
    ConstantRef  result = ConstantRef::invalid();
    switch (tok.id)
    {
        case TokenId::SymPlusPlus:
            RESULT_VERIFY(ConstantFold::binary(*sema_, result, tok.id, *node, nodeLeftView, nodeRightView));
            out = result;
            return Result::Continue;
        case TokenId::SymPlus:
        case TokenId::SymMinus:
        case TokenId::SymAsterisk:
        case TokenId::SymSlash:
        case TokenId::SymPercent:
        case TokenId::SymAmpersand:
        case TokenId::SymPipe:
        case TokenId::SymCircumflex:
        case TokenId::SymGreaterGreater:
        case TokenId::SymLowerLower:
            RESULT_VERIFY(ConstantFold::checkRightConstant(*sema_, tok.id, node->nodeRightRef, nodeRightView));
            RESULT_VERIFY(ConstantFold::binary(*sema_, result, tok.id, *node, nodeLeftView, nodeRightView));
            out = result;
            return Result::Continue;
        default:
            break;
    }

    return Result::Continue;
}

Result ConstantEval::evalRelational(AstNodeRef, const AstRelationalExpr* node, ConstantRef& out)
{
    ConstantRef leftCst  = ConstantRef::invalid();
    ConstantRef rightCst = ConstantRef::invalid();
    RESULT_VERIFY(evalExpr(node->nodeLeftRef, leftCst));
    RESULT_VERIFY(evalExpr(node->nodeRightRef, rightCst));
    if (leftCst.isInvalid() || rightCst.isInvalid())
        return Result::Continue;

    SemaNodeView nodeLeftView(*sema_, node->nodeLeftRef);
    SemaNodeView nodeRightView(*sema_, node->nodeRightRef);
    nodeLeftView.setCstRef(*sema_, leftCst);
    nodeRightView.setCstRef(*sema_, rightCst);

    ConstantRef  result;
    const Token& tok = sema_->token(node->codeRef());
    RESULT_VERIFY(ConstantFold::relational(*sema_, result, tok.id, nodeLeftView, nodeRightView));
    out = result;
    return Result::Continue;
}

Result ConstantEval::evalLogical(AstNodeRef, const AstLogicalExpr* node, ConstantRef& out)
{
    ConstantRef leftCst  = ConstantRef::invalid();
    ConstantRef rightCst = ConstantRef::invalid();
    RESULT_VERIFY(evalExpr(node->nodeLeftRef, leftCst));
    RESULT_VERIFY(evalExpr(node->nodeRightRef, rightCst));
    if (leftCst.isInvalid() || rightCst.isInvalid())
        return Result::Continue;

    ConstantRef leftBoolCst  = ConstantRef::invalid();
    ConstantRef rightBoolCst = ConstantRef::invalid();
    RESULT_VERIFY(castConstant(node->nodeLeftRef, leftCst, sema_->typeMgr().typeBool(), CastKind::Condition, CastFlagsE::Zero, leftBoolCst));
    RESULT_VERIFY(castConstant(node->nodeRightRef, rightCst, sema_->typeMgr().typeBool(), CastKind::Condition, CastFlagsE::Zero, rightBoolCst));
    if (leftBoolCst.isInvalid() || rightBoolCst.isInvalid())
        return Result::Continue;

    SemaNodeView nodeLeftView(*sema_, node->nodeLeftRef);
    SemaNodeView nodeRightView(*sema_, node->nodeRightRef);
    nodeLeftView.setCstRef(*sema_, leftBoolCst);
    nodeRightView.setCstRef(*sema_, rightBoolCst);

    ConstantRef  result;
    const Token& tok = sema_->token(node->codeRef());
    RESULT_VERIFY(ConstantFold::logical(*sema_, result, tok.id, nodeLeftView, nodeRightView));
    out = result;
    return Result::Continue;
}

Result ConstantEval::evalConditional(AstNodeRef nodeRef, const AstConditionalExpr* node, ConstantRef& out)
{
    ConstantRef condCst = ConstantRef::invalid();
    RESULT_VERIFY(evalExpr(node->nodeCondRef, condCst));
    if (condCst.isInvalid())
        return Result::Continue;

    ConstantRef condBoolCst = ConstantRef::invalid();
    RESULT_VERIFY(castConstant(node->nodeCondRef, condCst, sema_->typeMgr().typeBool(), CastKind::Condition, CastFlagsE::Zero, condBoolCst));
    if (condBoolCst.isInvalid())
        return Result::Continue;
    const bool       takeTrue  = sema_->cstMgr().get(condBoolCst).getBool();
    const AstNodeRef branchRef = takeTrue ? node->nodeTrueRef : node->nodeFalseRef;
    ConstantRef      branchCst = ConstantRef::invalid();
    RESULT_VERIFY(evalExpr(branchRef, branchCst));
    if (branchCst.isInvalid())
        return Result::Continue;

    const TypeRef resultTypeRef = sema_->typeRefOf(nodeRef);
    RESULT_VERIFY(castConstant(branchRef, branchCst, resultTypeRef, CastKind::Implicit, CastFlagsE::Zero, out));
    return Result::Continue;
}

Result ConstantEval::evalNullCoalescing(AstNodeRef nodeRef, const AstNullCoalescingExpr* node, ConstantRef& out)
{
    ConstantRef leftCst = ConstantRef::invalid();
    RESULT_VERIFY(evalExpr(node->nodeLeftRef, leftCst));
    if (leftCst.isInvalid())
        return Result::Continue;

    ConstantRef leftBoolCst = ConstantRef::invalid();
    RESULT_VERIFY(castConstant(node->nodeLeftRef, leftCst, sema_->typeMgr().typeBool(), CastKind::Condition, CastFlagsE::Zero, leftBoolCst));
    if (leftBoolCst.isInvalid())
        return Result::Continue;

    const bool leftIsFalse = sema_->cstMgr().get(leftBoolCst).getBool() == false;
    if (!leftIsFalse)
    {
        out = leftCst;
        return Result::Continue;
    }

    ConstantRef rightCst = ConstantRef::invalid();
    RESULT_VERIFY(evalExpr(node->nodeRightRef, rightCst));
    if (rightCst.isInvalid())
        return Result::Continue;

    const TypeRef resultTypeRef = sema_->typeRefOf(nodeRef);
    RESULT_VERIFY(castConstant(node->nodeRightRef, rightCst, resultTypeRef, CastKind::Implicit, CastFlagsE::Zero, out));
    return Result::Continue;
}

Result ConstantEval::evalExplicitCast(AstNodeRef nodeRef, const AstExplicitCastExpr* node, ConstantRef& out)
{
    ConstantRef exprCst = ConstantRef::invalid();
    RESULT_VERIFY(evalExprInternal(node->nodeExprRef, exprCst, false));
    if (exprCst.isInvalid())
        return Result::Continue;

    CastFlags castFlags = CastFlagsE::Zero;
    if (node->modifierFlags.has(AstModifierFlagsE::Bit))
        castFlags.add(CastFlagsE::BitCast);
    if (node->modifierFlags.has(AstModifierFlagsE::UnConst))
        castFlags.add(CastFlagsE::UnConst);

    const SemaNodeView nodeTypeView(*sema_, node->nodeTypeRef);
    TypeRef            dstTypeRef = sema_->typeRefOf(nodeRef);
    if (dstTypeRef.isInvalid())
        dstTypeRef = nodeTypeView.typeRef;
    if (dstTypeRef.isInvalid())
        return Result::Continue;

    return castConstant(nodeRef, exprCst, dstTypeRef, CastKind::Explicit, castFlags, out);
}

Result ConstantEval::evalImplicitCast(AstNodeRef nodeRef, const AstImplicitCastExpr* node, ConstantRef& out)
{
    ConstantRef exprCst = ConstantRef::invalid();
    RESULT_VERIFY(evalExprInternal(node->nodeExprRef, exprCst, false));
    if (exprCst.isInvalid())
        return Result::Continue;

    const TypeRef dstTypeRef = sema_->typeRefOf(nodeRef);
    const TypeRef srcTypeRef = sema_->typeRefOf(node->nodeExprRef);
    return castConstant(nodeRef, exprCst, dstTypeRef, CastKind::Implicit, CastFlagsE::Zero, out, srcTypeRef);
}

Result ConstantEval::evalAutoCast(AstNodeRef nodeRef, const AstAutoCastExpr* node, ConstantRef& out)
{
    ConstantRef exprCst = ConstantRef::invalid();
    RESULT_VERIFY(evalExprInternal(node->nodeExprRef, exprCst, false));
    if (exprCst.isInvalid())
        return Result::Continue;

    CastFlags castFlags = CastFlagsE::Zero;
    if (node->modifierFlags.has(AstModifierFlagsE::Bit))
        castFlags.add(CastFlagsE::BitCast);
    if (node->modifierFlags.has(AstModifierFlagsE::UnConst))
        castFlags.add(CastFlagsE::UnConst);

    const TypeRef dstTypeRef = sema_->typeRefOf(nodeRef);
    const TypeRef srcTypeRef = sema_->typeRefOf(node->nodeExprRef);
    return castConstant(nodeRef, exprCst, dstTypeRef, CastKind::Explicit, castFlags, out, srcTypeRef);
}

Result ConstantEval::evalMemberAccess(AstNodeRef, const AstMemberAccessExpr* node, ConstantRef& out)
{
    ConstantRef leftCst = ConstantRef::invalid();
    RESULT_VERIFY(evalExpr(node->nodeLeftRef, leftCst));
    if (leftCst.isInvalid())
        return Result::Continue;

    const ConstantValue& leftVal = sema_->cstMgr().get(leftCst);
    if (sema_->hasSymbolList(node->nodeRightRef))
    {
        const auto            symbols = sema_->getSymbolList(node->nodeRightRef);
        const SymbolVariable* symVar  = nullptr;
        if (symbols.size() == 1 && symbols.front()->isVariable())
            symVar = symbols.front()->safeCast<SymbolVariable>();
        else
        {
            for (const auto* sym : symbols)
            {
                if (sym && sym->isVariable())
                {
                    symVar = sym->safeCast<SymbolVariable>();
                    break;
                }
            }
        }

        if (symVar)
        {
            ConstantRef memberCst = ConstantRef::invalid();
            RESULT_VERIFY(ConstantExtract::structMember(*sema_, leftVal, *symVar, memberCst, node->nodeRightRef));
            out = memberCst;
            return Result::Continue;
        }
    }
    else if (sema_->hasSymbol(node->nodeRightRef))
    {
        const auto& sym = sema_->symbolOf(node->nodeRightRef);
        if (sym.isVariable())
        {
            ConstantRef memberCst = ConstantRef::invalid();
            RESULT_VERIFY(ConstantExtract::structMember(*sema_, leftVal, sym.cast<SymbolVariable>(), memberCst, node->nodeRightRef));
            out = memberCst;
            return Result::Continue;
        }
    }
    else
    {
        const SemaNodeView nodeRightView(*sema_, node->nodeRightRef);
        const auto*        symVar = nodeRightView.sym ? nodeRightView.sym->safeCast<SymbolVariable>() : nullptr;
        if (symVar)
        {
            ConstantRef memberCst = ConstantRef::invalid();
            RESULT_VERIFY(ConstantExtract::structMember(*sema_, leftVal, *symVar, memberCst, node->nodeRightRef));
            out = memberCst;
            return Result::Continue;
        }
    }

    const SemaNodeView nodeRightView(*sema_, node->nodeRightRef);
    if (nodeRightView.node && nodeRightView.node->is(AstNodeId::Identifier))
    {
        const TypeInfo& leftType = sema_->typeMgr().get(leftVal.typeRef());
        if (leftType.isStruct())
        {
            const IdentifierRef idRef  = sema_->idMgr().addIdentifier(sema_->ctx(), nodeRightView.node->codeRef());
            const auto&         fields = leftType.payloadSymStruct().fields();
            for (const auto* field : fields)
            {
                if (field && field->idRef() == idRef)
                {
                    ConstantRef memberCst = ConstantRef::invalid();
                    RESULT_VERIFY(ConstantExtract::structMember(*sema_, leftVal, *field, memberCst, node->nodeRightRef));
                    out = memberCst;
                    return Result::Continue;
                }
            }
        }
    }

    if (leftVal.isAggregateStruct())
    {
        if (!nodeRightView.node || !nodeRightView.node->is(AstNodeId::Identifier))
            return Result::Continue;

        const TypeInfo&        aggregateType = sema_->typeMgr().get(leftVal.typeRef());
        const auto&            aggregate     = aggregateType.payloadAggregate();
        const auto&            values        = leftVal.getAggregateStruct();
        const IdentifierRef    idRef         = sema_->idMgr().addIdentifier(sema_->ctx(), nodeRightView.node->codeRef());
        const std::string_view idName        = sema_->idMgr().get(idRef).name;

        size_t memberIndex = 0;
        bool   found       = false;
        for (size_t i = 0; i < aggregate.names.size(); ++i)
        {
            if (aggregate.names[i].isValid())
            {
                if (aggregate.names[i] == idRef)
                {
                    memberIndex = i;
                    found       = true;
                    break;
                }
            }
            else if (idName == ("item" + std::to_string(i)))
            {
                memberIndex = i;
                found       = true;
                break;
            }
        }

        if (!found || std::cmp_greater_equal(memberIndex, values.size()))
            return Result::Continue;

        out = values[memberIndex];
        return Result::Continue;
    }

    return Result::Continue;
}

Result ConstantEval::evalIndex(AstNodeRef, const AstIndexExpr* node, ConstantRef& out)
{
    ConstantRef baseCst = ConstantRef::invalid();
    RESULT_VERIFY(evalExpr(node->nodeExprRef, baseCst));
    if (baseCst.isInvalid())
        return Result::Continue;

    ConstantRef indexCst = ConstantRef::invalid();
    RESULT_VERIFY(evalExpr(node->nodeArgRef, indexCst));
    if (indexCst.isInvalid())
        return Result::Continue;

    if (!sema_->cstMgr().get(indexCst).isInt())
        return Result::Continue;

    int64_t constIndex = 0;
    RESULT_VERIFY(getConstIndex(node->nodeArgRef, indexCst, constIndex));

    ConstantRef elemCst = ConstantRef::invalid();
    RESULT_VERIFY(ConstantExtract::atIndex(*sema_, sema_->cstMgr().get(baseCst), constIndex, node->nodeArgRef, elemCst));
    out = elemCst;
    return Result::Continue;
}

Result ConstantEval::evalIndexList(AstNodeRef, const AstIndexListExpr* node, ConstantRef& out)
{
    ConstantRef baseCst = ConstantRef::invalid();
    RESULT_VERIFY(evalExpr(node->nodeExprRef, baseCst));
    if (baseCst.isInvalid())
        return Result::Continue;

    SmallVector<AstNodeRef> indices;
    sema_->ast().appendNodes(indices, node->spanChildrenRef);

    ConstantRef currentCst = baseCst;
    for (const auto indice : indices)
    {
        ConstantRef indexCst = ConstantRef::invalid();
        RESULT_VERIFY(evalExpr(indice, indexCst));
        if (indexCst.isInvalid())
            return Result::Continue;

        if (!sema_->cstMgr().get(indexCst).isInt())
            return Result::Continue;

        int64_t constIndex = 0;
        RESULT_VERIFY(getConstIndex(indice, indexCst, constIndex));

        ConstantRef          nextCstRef = ConstantRef::invalid();
        const ConstantValue& currentVal = sema_->cstMgr().get(currentCst);
        RESULT_VERIFY(ConstantExtract::atIndex(*sema_, currentVal, constIndex, indice, nextCstRef));
        if (nextCstRef.isInvalid())
            return Result::Continue;
        currentCst = nextCstRef;
    }

    out = currentCst;
    return Result::Continue;
}

Result ConstantEval::evalCountOf(AstNodeRef nodeRef, AstNodeRef exprRef, ConstantRef& out)
{
    exprRef = mapArgumentRef(exprRef);
    SemaNodeView nodeView(*sema_, exprRef);
    ConstantRef  exprCst = ConstantRef::invalid();
    RESULT_VERIFY(evalExpr(exprRef, exprCst));
    if (exprCst.isValid())
        nodeView.setCstRef(*sema_, exprCst);

    if (!nodeView.type)
        return Result::Continue;

    auto&         ctx           = sema_->ctx();
    const TypeRef resultTypeRef = sema_->typeRefOf(nodeRef);
    if (nodeView.cst)
    {
        if (nodeView.cst->isString())
        {
            out = sema_->cstMgr().addInt(ctx, nodeView.cst->getString().length());
            if (resultTypeRef.isValid())
                return castConstant(nodeRef, out, resultTypeRef, CastKind::Implicit, CastFlagsE::Zero, out);
            return Result::Continue;
        }

        if (nodeView.cst->isSlice())
        {
            out = sema_->cstMgr().addInt(ctx, nodeView.cst->getSlice().size());
            if (resultTypeRef.isValid())
                return castConstant(nodeRef, out, resultTypeRef, CastKind::Implicit, CastFlagsE::Zero, out);
            return Result::Continue;
        }

        if (nodeView.cst->isInt())
        {
            if (nodeView.cst->getInt().isNegative())
            {
                auto diag = SemaError::report(*sema_, DiagnosticId::sema_err_count_negative, exprRef);
                diag.addArgument(Diagnostic::ARG_VALUE, nodeView.cst->toString(ctx));
                diag.report(ctx);
                return Result::Error;
            }

            ConstantRef newCstRef = ConstantRef::invalid();
            RESULT_VERIFY(Cast::concretizeConstant(*sema_, newCstRef, exprRef, nodeView.cstRef, TypeInfo::Sign::Unsigned));
            if (resultTypeRef.isValid())
                return castConstant(nodeRef, newCstRef, resultTypeRef, CastKind::Implicit, CastFlagsE::Zero, out);
            out = newCstRef;
            return Result::Continue;
        }
    }

    if (nodeView.type->isEnum())
    {
        RESULT_VERIFY(sema_->waitCompleted(nodeView.type, exprRef));
        out = sema_->cstMgr().addInt(ctx, nodeView.type->payloadSymEnum().count());
        if (resultTypeRef.isValid())
            return castConstant(nodeRef, out, resultTypeRef, CastKind::Implicit, CastFlagsE::Zero, out);
        return Result::Continue;
    }

    if (nodeView.type->isArray())
    {
        const uint64_t  sizeOf     = nodeView.type->sizeOf(ctx);
        const TypeRef   typeRef    = nodeView.type->payloadArrayElemTypeRef();
        const TypeInfo& ty         = sema_->typeMgr().get(typeRef);
        const uint64_t  sizeOfElem = ty.sizeOf(ctx);
        SWC_ASSERT(sizeOfElem > 0);
        out = sema_->cstMgr().addInt(ctx, sizeOf / sizeOfElem);
        if (resultTypeRef.isValid())
            return castConstant(nodeRef, out, resultTypeRef, CastKind::Implicit, CastFlagsE::Zero, out);
        return Result::Continue;
    }

    return Result::Continue;
}

Result ConstantEval::evalIntrinsicCall(AstNodeRef nodeRef, const AstIntrinsicCallExpr* node, ConstantRef& out)
{
    SmallVector<AstNodeRef> args;
    node->collectArguments(args, sema_->ast());

    std::vector<ConstantRef> argCsts;
    std::vector<AstNodeRef>  argRefs;
    argCsts.reserve(args.size());
    argRefs.reserve(args.size());
    for (const auto argRef : args)
    {
        ConstantRef argCst = ConstantRef::invalid();
        RESULT_VERIFY(evalExpr(argRef, argCst));
        if (argCst.isInvalid())
            return Result::Continue;
        argCsts.push_back(argCst);
        argRefs.push_back(mapArgumentRef(argRef));
    }

    const Symbol* sym = nullptr;
    if (sema_->hasSymbol(nodeRef))
    {
        sym = &sema_->symbolOf(nodeRef);
    }
    else if (sema_->hasSymbolList(nodeRef))
    {
        const auto symbols = sema_->getSymbolList(nodeRef);
        if (symbols.size() == 1)
            sym = symbols.front();
    }

    if (!sym || !sym->isFunction())
        return Result::Continue;

    ConstantRef result = ConstantRef::invalid();
    RESULT_VERIFY(ConstantIntrinsic::tryConstantFoldCall(*sema_, sym->cast<SymbolFunction>(), argRefs, argCsts, nodeRef, result));
    if (result.isInvalid())
    {
        const Token& tok = sema_->token(sym->codeRef());
        if (tok.id == TokenId::IntrinsicCountOf && args.size() == 1)
            return evalCountOf(nodeRef, args[0], out);
        return Result::Continue;
    }

    out = result;
    return Result::Continue;
}


namespace
{
    bool collectParamBindings(Sema& sema, const SymbolFunction& selectedFn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, std::vector<ConstantEval::ParamBinding>& outBindings)
    {
        const auto& params = selectedFn.parameters();
        if (params.empty())
            return args.empty() && !ufcsArg.isValid();

        std::vector mapping(params.size(), AstNodeRef::invalid());
        size_t      nextPos = 0;

        if (ufcsArg.isValid())
        {
            if (params.empty())
                return false;
            mapping[0] = ufcsArg;
            nextPos    = 1;
        }

        for (const auto argRef : args)
        {
            const AstNode& argNode = sema.node(argRef);
            if (argNode.is(AstNodeId::NamedArgument))
            {
                const auto*         named = argNode.cast<AstNamedArgument>();
                const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), argNode.codeRef());
                size_t              found = params.size();
                for (size_t i = 0; i < params.size(); ++i)
                {
                    if (params[i]->idRef() == idRef)
                    {
                        found = i;
                        break;
                    }
                }

                if (found == params.size() || mapping[found].isValid())
                    return false;

                mapping[found] = named->nodeArgRef;
                continue;
            }

            while (nextPos < mapping.size() && mapping[nextPos].isValid())
                ++nextPos;

            if (nextPos >= mapping.size())
                return false;

            mapping[nextPos] = argRef;
            ++nextPos;
        }

        outBindings.clear();
        outBindings.reserve(params.size());
        for (size_t i = 0; i < params.size(); ++i)
        {
            AstNodeRef argRef = mapping[i];
            if (argRef.isInvalid())
            {
                const AstNode* decl = params[i]->decl();
                if (decl && decl->is(AstNodeId::SingleVarDecl))
                {
                    const auto* varDecl = decl->cast<AstSingleVarDecl>();
                    argRef              = varDecl->nodeInitRef;
                }
            }

            if (argRef.isInvalid())
                return false;

            const SemaNodeView argView(sema, argRef);
            ConstantRef        argCstRef = argView.cstRef;
            if (argCstRef.isInvalid())
                argCstRef = sema.constantRefOf(argRef);
            if (argCstRef.isInvalid())
            {
                const AstNode& argNode = sema.node(argRef);
                if (const auto* implicitCast = argNode.safeCast<AstImplicitCastExpr>())
                {
                    ConstantRef innerCst = sema.constantRefOf(implicitCast->nodeExprRef);
                    if (innerCst.isValid())
                    {
                        const TypeRef dstTypeRef = sema.typeRefOf(argRef);
                        if (dstTypeRef.isValid())
                        {
                            const TypeRef srcTypeRef = sema.cstMgr().get(innerCst).typeRef();
                            CastRequest   castRequest(CastKind::Implicit);
                            castRequest.errorNodeRef = argRef;
                            castRequest.setConstantFoldingSrc(innerCst);
                            if (Cast::castAllowed(sema, castRequest, srcTypeRef, dstTypeRef) != Result::Continue)
                                return false;
                            argCstRef = castRequest.constantFoldingResult();
                        }
                    }
                }
            }
            if (argCstRef.isInvalid())
            {
                ConstantEval argEval(sema, {});
                if (argEval.evalExpr(argRef, argCstRef) != Result::Continue)
                    return false;
            }
            if (argCstRef.isInvalid())
                return false;

            outBindings.push_back({.sym = params[i], .cstRef = argCstRef, .argRef = argRef});
        }

        return true;
    }

    Result evalPureCall(Sema& sema, const SymbolFunction& selectedFn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, ConstantRef& outResult)
    {
        outResult = ConstantRef::invalid();
        if (!selectedFn.isPure())
            return Result::Continue;
        const AstNode* decl = selectedFn.decl();
        if (!decl || !decl->is(AstNodeId::FunctionDecl))
            return Result::Continue;

        const auto* funcDecl = decl->cast<AstFunctionDecl>();
        if (!funcDecl->hasFlag(AstFunctionFlagsE::Short))
            return Result::Continue;

        if (funcDecl->nodeBodyRef.isInvalid())
            return Result::Continue;

        const TypeRef returnTypeRef = selectedFn.returnTypeRef();
        if (returnTypeRef.isInvalid() || sema.typeMgr().get(returnTypeRef).isVoid())
            return Result::Continue;

        std::vector<ConstantEval::ParamBinding> bindings;
        if (!collectParamBindings(sema, selectedFn, args, ufcsArg, bindings))
            return Result::Continue;

        ConstantEval evaluator(sema, bindings);
        RESULT_VERIFY(evaluator.evalExpr(funcDecl->nodeBodyRef, outResult));
        return Result::Continue;
    }
}

Result ConstantEval::evalCall(AstNodeRef nodeRef, const AstCallExpr* node, ConstantRef& out) const
{
    SmallVector<AstNodeRef> args;
    node->collectArguments(args, sema_->ast());

    std::vector<AstNodeRef> argRefs;
    argRefs.reserve(args.size());
    for (const auto argRef : args)
    {
        argRefs.push_back(mapArgumentRef(argRef));
    }

    AstNodeRef ufcsArg = AstNodeRef::invalid();
    if (const auto* memberAccess = sema_->node(node->nodeExprRef).safeCast<AstMemberAccessExpr>())
    {
        const SemaNodeView nodeLeftView(*sema_, memberAccess->nodeLeftRef);
        if (nodeLeftView.node && sema_->isValue(*nodeLeftView.node))
            ufcsArg = mapArgumentRef(nodeLeftView.nodeRef);
    }

    const Symbol* sym = nullptr;
    if (sema_->hasSymbol(nodeRef))
    {
        sym = &sema_->symbolOf(nodeRef);
    }
    else if (sema_->hasSymbolList(nodeRef))
    {
        const auto symbols = sema_->getSymbolList(nodeRef);
        if (symbols.size() == 1)
            sym = symbols.front();
    }

    if (!sym || !sym->isFunction())
        return Result::Continue;

    ConstantRef result = ConstantRef::invalid();
    RESULT_VERIFY(evalPureCall(*sema_, sym->cast<SymbolFunction>(), argRefs, ufcsArg, result));
    if (result.isInvalid())
        return Result::Continue;

    out = result;
    return Result::Continue;
}

Result ConstantEval::tryConstantFoldPureCall(Sema& sema, const SymbolFunction& selectedFn, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
{
    ConstantRef result = ConstantRef::invalid();
    RESULT_VERIFY(evalPureCall(sema, selectedFn, args, ufcsArg, result));
    if (result.isInvalid())
        return Result::Continue;

    sema.setConstant(sema.curNodeRef(), result);
    return Result::Continue;
}

SWC_END_NAMESPACE();
