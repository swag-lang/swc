#include "pch.h"
#include "Compiler/Sema/Constant/ConstantEval.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Symbol/Symbol.Function.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct ParamBinding
    {
        const SymbolVariable* sym    = nullptr;
        ConstantRef           cstRef = ConstantRef::invalid();
    };

    class ConstEval
    {
    public:
        ConstEval(Sema& sema, std::span<const ParamBinding> bindings) :
            sema_(&sema),
            bindings_(bindings)
        {
        }

        Result evalExpr(AstNodeRef exprRef, ConstantRef& out)
        {
            out     = ConstantRef::invalid();
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
                    return evalExpr(node.cast<AstParenExpr>()->nodeExprRef, out);
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
                default:
                    return Result::Continue;
            }
        }

    private:
        Result evalIdentifier(AstNodeRef nodeRef, ConstantRef& out) const
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

        const SymbolVariable* lookupParameter(AstNodeRef nodeRef) const
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

            if (!sym || !sym->isVariable())
                return nullptr;

            const auto* var = sym->safeCast<SymbolVariable>();
            if (!var)
                return nullptr;

            for (const auto& binding : bindings_)
            {
                if (binding.sym == var)
                    return var;
            }

            return nullptr;
        }

        Result evalUnary(AstNodeRef nodeRef, const AstUnaryExpr* node, ConstantRef& out)
        {
            (void) nodeRef;
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
                    return constantFoldMinus(result, *node, nodeView, out);
                case TokenId::SymPlus:
                    return constantFoldPlus(result, nodeView, out);
                case TokenId::SymBang:
                    return constantFoldBang(result, nodeView, out);
                case TokenId::SymTilde:
                    return constantFoldTilde(result, *node, nodeView, out);
                default:
                    break;
            }

            return Result::Continue;
        }

        Result evalBinary(AstNodeRef nodeRef, const AstBinaryExpr* node, ConstantRef& out)
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
                    RESULT_VERIFY(constantFoldPlusPlus(result, nodeLeftView, nodeRightView));
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
                    RESULT_VERIFY(checkRightConstant(tok.id, node->nodeRightRef, nodeRightView));
                    RESULT_VERIFY(constantFoldOp(result, nodeRef, tok.id, *node, nodeLeftView, nodeRightView));
                    out = result;
                    return Result::Continue;
                default:
                    break;
            }

            return Result::Continue;
        }

        Result evalRelational(AstNodeRef nodeRef, const AstRelationalExpr* node, ConstantRef& out)
        {
            (void) nodeRef;
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
            RESULT_VERIFY(constantFoldRelational(result, tok.id, nodeLeftView, nodeRightView));
            out = result;
            return Result::Continue;
        }

        Result evalLogical(AstNodeRef nodeRef, const AstLogicalExpr* node, ConstantRef& out)
        {
            (void) nodeRef;
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
            RESULT_VERIFY(constantFoldLogical(result, tok.id, nodeLeftView, nodeRightView));
            out = result;
            return Result::Continue;
        }

        Result evalConditional(AstNodeRef nodeRef, const AstConditionalExpr* node, ConstantRef& out)
        {
            ConstantRef condCst = ConstantRef::invalid();
            RESULT_VERIFY(evalExpr(node->nodeCondRef, condCst));
            if (condCst.isInvalid())
                return Result::Continue;

            const auto& condVal = sema_->cstMgr().get(condCst);
            if (!condVal.isBool())
                return Result::Continue;
            const bool       takeTrue  = condVal.getBool();
            const AstNodeRef branchRef = takeTrue ? node->nodeTrueRef : node->nodeFalseRef;
            ConstantRef      branchCst = ConstantRef::invalid();
            RESULT_VERIFY(evalExpr(branchRef, branchCst));
            if (branchCst.isInvalid())
                return Result::Continue;

            out = branchCst;
            return Result::Continue;
        }

        Result constantFoldPlus(ConstantRef& result, const SemaNodeView& nodeView, ConstantRef& out) const
        {
            if (nodeView.type->isInt())
            {
                ApsInt value = nodeView.cst->getInt();
                value.setUnsigned(true);
                result = sema_->cstMgr().addConstant(sema_->ctx(), ConstantValue::makeInt(sema_->ctx(), value, nodeView.type->payloadIntBits(), TypeInfo::Sign::Unsigned));
            }
            else
            {
                result = nodeView.cstRef;
            }
            out = result;
            return Result::Continue;
        }

        Result constantFoldMinus(ConstantRef& result, const AstUnaryExpr& expr, const SemaNodeView& nodeView, ConstantRef& out) const
        {
            (void) expr;
            if (nodeView.node->is(AstNodeId::SuffixLiteral))
            {
                result = nodeView.cstRef;
                out    = result;
                return Result::Continue;
            }

            if (nodeView.type->isInt())
            {
                ApsInt value    = nodeView.cst->getInt();
                bool   overflow = false;
                value.negate(overflow);
                if (overflow)
                    return SemaError::raiseLiteralOverflow(*sema_, nodeView.nodeRef, *nodeView.cst, nodeView.typeRef);

                value.setUnsigned(false);
                result = sema_->cstMgr().addConstant(sema_->ctx(), ConstantValue::makeInt(sema_->ctx(), value, nodeView.type->payloadIntBits(), TypeInfo::Sign::Signed));
                out    = result;
                return Result::Continue;
            }

            if (nodeView.type->isFloat())
            {
                ApFloat value = nodeView.cst->getFloat();
                value.negate();
                result = sema_->cstMgr().addConstant(sema_->ctx(), ConstantValue::makeFloat(sema_->ctx(), value, nodeView.type->payloadFloatBits()));
                out    = result;
                return Result::Continue;
            }

            return Result::Error;
        }

        Result constantFoldBang(ConstantRef& result, const SemaNodeView& nodeView, ConstantRef& out) const
        {
            const auto& cstMgr = sema_->cstMgr();
            if (nodeView.cst->isBool())
                result = cstMgr.cstNegBool(nodeView.cstRef);
            else if (nodeView.cst->isInt())
                result = cstMgr.cstBool(nodeView.cst->getInt().isZero());
            else if (nodeView.cst->isChar())
                result = cstMgr.cstBool(nodeView.cst->getChar());
            else if (nodeView.cst->isRune())
                result = cstMgr.cstBool(nodeView.cst->getRune());
            else if (nodeView.cst->isString())
                result = cstMgr.cstFalse();
            else
                SWC_INTERNAL_ERROR(sema_->ctx());

            out = result;
            return Result::Continue;
        }

        Result constantFoldTilde(ConstantRef& result, const AstUnaryExpr&, const SemaNodeView& nodeView, ConstantRef& out) const
        {
            ApsInt value = nodeView.cst->getInt();
            value.invertAllBits();
            result = sema_->cstMgr().addConstant(sema_->ctx(), ConstantValue::makeInt(sema_->ctx(), value, nodeView.type->payloadIntBits(), nodeView.type->payloadIntSign()));
            out    = result;
            return Result::Continue;
        }

        Result constantFoldPlusPlus(ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView) const
        {
            Utf8 str = nodeLeftView.cst->toString(sema_->ctx());
            str += nodeRightView.cst->toString(sema_->ctx());
            result = sema_->cstMgr().addConstant(sema_->ctx(), ConstantValue::makeString(sema_->ctx(), str));
            return Result::Continue;
        }

        Result constantFoldOp(ConstantRef& result, AstNodeRef nodeRef, TokenId op, const AstBinaryExpr& node, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView) const
        {
            ConstantRef leftCstRef  = nodeLeftView.cstRef;
            ConstantRef rightCstRef = nodeRightView.cstRef;

            const bool promote = node.modifierFlags.has(AstModifierFlagsE::Promote);
            RESULT_VERIFY(Cast::promoteConstants(*sema_, nodeLeftView, nodeRightView, leftCstRef, rightCstRef, promote));

            const ConstantValue& leftCst  = sema_->cstMgr().get(leftCstRef);
            const ConstantValue& rightCst = sema_->cstMgr().get(rightCstRef);
            const TypeInfo&      type     = leftCst.type(sema_->ctx());

            if (node.modifierFlags.hasAny({AstModifierFlagsE::Wrap, AstModifierFlagsE::Promote}))
            {
                if (!type.isInt())
                    return Result::Error;
            }

            if (type.isFloat())
            {
                auto val1 = leftCst.getFloat();
                switch (op)
                {
                    case TokenId::SymPlus:
                        val1.add(rightCst.getFloat());
                        break;
                    case TokenId::SymMinus:
                        val1.sub(rightCst.getFloat());
                        break;
                    case TokenId::SymAsterisk:
                        val1.mul(rightCst.getFloat());
                        break;
                    case TokenId::SymSlash:
                        val1.div(rightCst.getFloat());
                        break;
                    default:
                        SWC_UNREACHABLE();
                }

                result = sema_->cstMgr().addConstant(sema_->ctx(), ConstantValue::makeFloat(sema_->ctx(), val1, type.payloadFloatBits()));
                return Result::Continue;
            }

            if (type.isInt())
            {
                ApsInt val1 = leftCst.getInt();
                ApsInt val2 = rightCst.getInt();

                const bool wrap     = node.modifierFlags.has(AstModifierFlagsE::Wrap);
                bool       overflow = false;

                if (type.isIntUnsized())
                {
                    val1.setSigned(true);
                    val2.setSigned(true);
                }

                switch (op)
                {
                    case TokenId::SymPlus:
                        val1.add(val2, overflow);
                        break;
                    case TokenId::SymMinus:
                        val1.sub(val2, overflow);
                        break;
                    case TokenId::SymAsterisk:
                        val1.mul(val2, overflow);
                        break;
                    case TokenId::SymSlash:
                        val1.div(val2, overflow);
                        break;
                    case TokenId::SymPercent:
                        val1.mod(val2, overflow);
                        break;
                    case TokenId::SymAmpersand:
                        val1.bitwiseAnd(val2);
                        break;
                    case TokenId::SymPipe:
                        val1.bitwiseOr(val2);
                        break;
                    case TokenId::SymCircumflex:
                        val1.bitwiseXor(val2);
                        break;
                    case TokenId::SymGreaterGreater:
                        if (val2.isNegative())
                        {
                            auto diag = SemaError::report(*sema_, DiagnosticId::sema_err_negative_shift, node.nodeRightRef);
                            diag.addArgument(Diagnostic::ARG_RIGHT, rightCstRef);
                            diag.report(sema_->ctx());
                            return Result::Error;
                        }
                        if (!val2.fits64())
                            overflow = true;
                        else
                            val1.shiftRight(val2.asI64());
                        break;
                    case TokenId::SymLowerLower:
                        if (val2.isNegative())
                        {
                            auto diag = SemaError::report(*sema_, DiagnosticId::sema_err_negative_shift, node.nodeRightRef);
                            diag.addArgument(Diagnostic::ARG_RIGHT, rightCstRef);
                            diag.report(sema_->ctx());
                            return Result::Error;
                        }
                        if (!val2.fits64())
                            overflow = true;
                        else
                            val1.shiftLeft(val2.asI64(), overflow);
                        overflow = false;
                        break;
                    default:
                        SWC_UNREACHABLE();
                }

                if (!wrap && type.payloadIntBits() != 0 && overflow)
                {
                    auto diag = SemaError::report(*sema_, DiagnosticId::sema_err_integer_overflow, sema_->node(nodeRef));
                    diag.addArgument(Diagnostic::ARG_TYPE, leftCst.typeRef());
                    diag.addArgument(Diagnostic::ARG_LEFT, leftCstRef);
                    diag.addArgument(Diagnostic::ARG_RIGHT, rightCstRef);
                    diag.report(sema_->ctx());
                    return Result::Error;
                }

                result = sema_->cstMgr().addConstant(sema_->ctx(), ConstantValue::makeInt(sema_->ctx(), val1, type.payloadIntBits(), type.payloadIntSign()));
                return Result::Continue;
            }

            return Result::Error;
        }

        Result constantFoldRelational(ConstantRef& result, TokenId op, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView) const
        {
            switch (op)
            {
                case TokenId::SymEqualEqual:
                    return constantFoldEqual(result, nodeLeftView, nodeRightView);
                case TokenId::SymBangEqual:
                    RESULT_VERIFY(constantFoldEqual(result, nodeLeftView, nodeRightView));
                    result = sema_->cstMgr().cstNegBool(result);
                    return Result::Continue;
                case TokenId::SymLess:
                    return constantFoldLess(result, nodeLeftView, nodeRightView);
                case TokenId::SymLessEqual:
                    return constantFoldLessEqual(result, nodeLeftView, nodeRightView);
                case TokenId::SymGreater:
                    return constantFoldGreater(result, nodeLeftView, nodeRightView);
                case TokenId::SymGreaterEqual:
                    return constantFoldGreaterEqual(result, nodeLeftView, nodeRightView);
                case TokenId::SymLessEqualGreater:
                    return constantFoldCompareEqual(result, nodeLeftView, nodeRightView);
                default:
                    return Result::Error;
            }
        }

        Result constantFoldEqual(ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView) const
        {
            if (nodeLeftView.cstRef == nodeRightView.cstRef)
            {
                result = sema_->cstMgr().cstTrue();
                return Result::Continue;
            }

            if (nodeLeftView.type->isTypeValue() && nodeRightView.type->isTypeValue())
            {
                result = sema_->cstMgr().cstBool(*nodeLeftView.type == *nodeRightView.type);
                return Result::Continue;
            }

            if (nodeLeftView.type->isAnyTypeInfo(sema_->ctx()) && nodeRightView.type->isAnyTypeInfo(sema_->ctx()))
            {
                const auto& leftCst  = sema_->cstMgr().get(nodeLeftView.cstRef);
                const auto& rightCst = sema_->cstMgr().get(nodeRightView.cstRef);
                result               = sema_->cstMgr().cstBool(leftCst.getValuePointer() == rightCst.getValuePointer());
                return Result::Continue;
            }

            if (nodeLeftView.cst->isNull() || nodeRightView.cst->isNull())
            {
                result = sema_->cstMgr().cstBool(nodeLeftView.cst->isNull() && nodeRightView.cst->isNull());
                return Result::Continue;
            }

            auto leftCstRef  = nodeLeftView.cstRef;
            auto rightCstRef = nodeRightView.cstRef;
            RESULT_VERIFY(Cast::promoteConstants(*sema_, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));

            const auto& left = sema_->cstMgr().get(leftCstRef);
            if (left.isFloat())
            {
                const auto& right = sema_->cstMgr().get(rightCstRef);
                result            = sema_->cstMgr().cstBool(left.eq(right));
                return Result::Continue;
            }

            result = sema_->cstMgr().cstBool(leftCstRef == rightCstRef);
            return Result::Continue;
        }

        Result constantFoldLess(ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView) const
        {
            if (nodeLeftView.cstRef == nodeRightView.cstRef)
            {
                result = sema_->cstMgr().cstFalse();
                return Result::Continue;
            }

            auto leftCstRef  = nodeLeftView.cstRef;
            auto rightCstRef = nodeRightView.cstRef;
            RESULT_VERIFY(Cast::promoteConstants(*sema_, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));
            if (leftCstRef == rightCstRef)
            {
                result = sema_->cstMgr().cstFalse();
                return Result::Continue;
            }

            const auto& leftCst  = sema_->cstMgr().get(leftCstRef);
            const auto& rightCst = sema_->cstMgr().get(rightCstRef);
            result               = sema_->cstMgr().cstBool(leftCst.lt(rightCst));
            return Result::Continue;
        }

        Result constantFoldLessEqual(ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView) const
        {
            if (nodeLeftView.cstRef == nodeRightView.cstRef)
            {
                result = sema_->cstMgr().cstTrue();
                return Result::Continue;
            }

            auto leftCstRef  = nodeLeftView.cstRef;
            auto rightCstRef = nodeRightView.cstRef;
            RESULT_VERIFY(Cast::promoteConstants(*sema_, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));
            if (leftCstRef == rightCstRef)
            {
                result = sema_->cstMgr().cstTrue();
                return Result::Continue;
            }

            const auto& leftCst  = sema_->cstMgr().get(leftCstRef);
            const auto& rightCst = sema_->cstMgr().get(rightCstRef);
            result               = sema_->cstMgr().cstBool(leftCst.le(rightCst));
            return Result::Continue;
        }

        Result constantFoldGreater(ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView) const
        {
            auto leftCstRef  = nodeLeftView.cstRef;
            auto rightCstRef = nodeRightView.cstRef;
            RESULT_VERIFY(Cast::promoteConstants(*sema_, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));
            if (leftCstRef == rightCstRef)
            {
                result = sema_->cstMgr().cstFalse();
                return Result::Continue;
            }

            const auto& leftCst  = sema_->cstMgr().get(leftCstRef);
            const auto& rightCst = sema_->cstMgr().get(rightCstRef);
            result               = sema_->cstMgr().cstBool(leftCst.gt(rightCst));
            return Result::Continue;
        }

        Result constantFoldGreaterEqual(ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView) const
        {
            if (nodeLeftView.cstRef == nodeRightView.cstRef)
            {
                result = sema_->cstMgr().cstTrue();
                return Result::Continue;
            }

            auto leftCstRef  = nodeLeftView.cstRef;
            auto rightCstRef = nodeRightView.cstRef;
            RESULT_VERIFY(Cast::promoteConstants(*sema_, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));
            if (leftCstRef == rightCstRef)
            {
                result = sema_->cstMgr().cstTrue();
                return Result::Continue;
            }

            const auto& leftCst  = sema_->cstMgr().get(leftCstRef);
            const auto& rightCst = sema_->cstMgr().get(rightCstRef);
            result               = sema_->cstMgr().cstBool(leftCst.ge(rightCst));
            return Result::Continue;
        }

        Result constantFoldCompareEqual(ConstantRef& result, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView) const
        {
            auto leftCstRef  = nodeLeftView.cstRef;
            auto rightCstRef = nodeRightView.cstRef;
            RESULT_VERIFY(Cast::promoteConstants(*sema_, nodeLeftView, nodeRightView, leftCstRef, rightCstRef));
            const auto& left  = sema_->cstMgr().get(leftCstRef);
            const auto& right = sema_->cstMgr().get(rightCstRef);

            int val = 0;
            if (leftCstRef == rightCstRef)
                val = 0;
            else if (left.lt(right))
                val = -1;
            else if (right.lt(left))
                val = 1;

            result = sema_->cstMgr().cstS32(val);
            return Result::Continue;
        }

        Result constantFoldLogical(ConstantRef& result, TokenId op, const SemaNodeView& nodeLeftView, const SemaNodeView& nodeRightView) const
        {
            const ConstantRef leftCstRef  = nodeLeftView.cstRef;
            const ConstantRef rightCstRef = nodeRightView.cstRef;
            const ConstantRef cstFalseRef = sema_->cstMgr().cstFalse();
            const ConstantRef cstTrueRef  = sema_->cstMgr().cstTrue();

            switch (op)
            {
                case TokenId::KwdAnd:
                    if (leftCstRef == cstFalseRef || rightCstRef == cstFalseRef)
                        result = cstFalseRef;
                    else
                        result = cstTrueRef;
                    return Result::Continue;
                case TokenId::KwdOr:
                    if (leftCstRef == cstTrueRef || rightCstRef == cstTrueRef)
                        result = cstTrueRef;
                    else
                        result = cstFalseRef;
                    return Result::Continue;
                default:
                    SWC_UNREACHABLE();
            }
        }

        Result checkRightConstant(TokenId op, AstNodeRef nodeRef, const SemaNodeView& nodeRightView) const
        {
            switch (op)
            {
                case TokenId::SymSlash:
                case TokenId::SymPercent:
                    if (nodeRightView.type->isFloat() && nodeRightView.cst->getFloat().isZero())
                        return SemaError::raiseDivZero(*sema_, nodeRef, nodeRightView.nodeRef);
                    if (nodeRightView.type->isInt() && nodeRightView.cst->getInt().isZero())
                        return SemaError::raiseDivZero(*sema_, nodeRef, nodeRightView.nodeRef);
                    break;
                default:
                    break;
            }

            return Result::Continue;
        }

        Sema*                         sema_ = nullptr;
        std::span<const ParamBinding> bindings_;
    };

    bool collectParamBindings(Sema& sema, const SymbolFunction& selectedFn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, std::vector<ParamBinding>& outBindings)
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
            if (argView.cstRef.isInvalid())
                return false;

            outBindings.push_back({.sym = params[i], .cstRef = argView.cstRef});
        }

        return true;
    }
}

Result ConstantEval::tryConstantFoldPureCall(Sema& sema, const SymbolFunction& selectedFn, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
{
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

    std::vector<ParamBinding> bindings;
    if (!collectParamBindings(sema, selectedFn, args, ufcsArg, bindings))
        return Result::Continue;

    ConstEval   evaluator(sema, bindings);
    ConstantRef result = ConstantRef::invalid();
    RESULT_VERIFY(evaluator.evalExpr(funcDecl->nodeBodyRef, result));
    if (result.isInvalid())
        return Result::Continue;

    sema.setConstant(sema.curNodeRef(), result);
    return Result::Continue;
}

SWC_END_NAMESPACE();
