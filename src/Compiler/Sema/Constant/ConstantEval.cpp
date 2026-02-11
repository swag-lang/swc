#include "pch.h"
#include "Compiler/Sema/Constant/ConstantEval.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantFold.h"
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
            RESULT_VERIFY(ConstantFold::relational(*sema_, result, tok.id, nodeLeftView, nodeRightView));
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
            RESULT_VERIFY(ConstantFold::logical(*sema_, result, tok.id, nodeLeftView, nodeRightView));
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
