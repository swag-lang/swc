#include "pch.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    Result finalizeInlinedCall(Sema& sema, AstNodeRef inlinedRef, AstNodeRef callRef, TypeRef returnTypeRef)
    {
        SemaNodeView inlineView(sema, inlinedRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Constant);
        if (returnTypeRef != sema.typeMgr().typeVoid())
            SWC_RESULT_VERIFY(Cast::cast(sema, inlineView, returnTypeRef, CastKind::Implicit));

        if (inlineView.cstRef().isValid())
        {
            sema.setFoldedTypedConst(callRef);
            sema.setConstant(callRef, inlineView.cstRef());
        }

        return Result::Continue;
    }

    bool isNamedArgument(const AstNode& node)
    {
        return node.is(AstNodeId::NamedArgument);
    }

    AstNodeRef inlineExprRef(const Sema& sema, const SymbolFunction& fn)
    {
        const AstNode* const declNode = fn.decl();
        if (!declNode)
            return AstNodeRef::invalid();
        if (!declNode->is(AstNodeId::FunctionDecl))
            return AstNodeRef::invalid();

        const Ast* const declAst = declNode->sourceAst(sema.ctx());
        if (!declAst || declAst != &sema.ast())
            return AstNodeRef::invalid();

        const auto& decl = declNode->cast<AstFunctionDecl>();
        if (decl.srcViewRef() != sema.ast().srcView().ref())
            return AstNodeRef::invalid();

        if (decl.hasFlag(AstFunctionFlagsE::Short))
            return decl.nodeBodyRef;

        if (decl.nodeBodyRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNode& bodyNode = declAst->node(decl.nodeBodyRef);
        if (!bodyNode.is(AstNodeId::EmbeddedBlock))
            return AstNodeRef::invalid();
        const auto& block = bodyNode.cast<AstEmbeddedBlock>();

        SmallVector<AstNodeRef> statements;
        declAst->appendNodes(statements, block.spanChildrenRef);
        if (statements.size() != 1)
            return AstNodeRef::invalid();

        const AstNode& retNode = declAst->node(statements[0]);
        if (!retNode.is(AstNodeId::ReturnStmt))
            return AstNodeRef::invalid();
        const auto& retStmt = retNode.cast<AstReturnStmt>();
        if (retStmt.nodeExprRef.isInvalid())
            return AstNodeRef::invalid();

        return retStmt.nodeExprRef;
    }

    bool mapArguments(Sema& sema, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg, SmallVector<SemaClone::ParamBinding>& outBindings)
    {
        const auto& params = fn.parameters();
        if (params.empty() && (ufcsArg.isValid() || !args.empty()))
            return false;

        std::vector bound(params.size(), AstNodeRef::invalid());
        size_t      nextParam = 0;

        if (ufcsArg.isValid())
        {
            if (params.empty())
                return false;
            bound[0]  = sema.viewZero(ufcsArg).nodeRef();
            nextParam = 1;
        }

        for (const auto argRef : args)
        {
            const AstNode& argNode = sema.node(argRef);
            if (!isNamedArgument(argNode))
                continue;

            const auto&         namedArg = argNode.cast<AstNamedArgument>();
            const IdentifierRef idRef    = sema.idMgr().addIdentifier(sema.ctx(), namedArg.codeRef());

            size_t paramIndex = params.size();
            for (size_t i = 0; i < params.size(); i++)
            {
                if (params[i]->idRef() == idRef)
                {
                    paramIndex = i;
                    break;
                }
            }

            if (paramIndex >= params.size())
                return false;
            if (bound[paramIndex].isValid())
                return false;

            bound[paramIndex] = sema.viewZero(namedArg.nodeArgRef).nodeRef();
        }

        for (const auto argRef : args)
        {
            const AstNode& argNode = sema.node(argRef);
            if (isNamedArgument(argNode))
                continue;

            while (nextParam < params.size() && bound[nextParam].isValid())
                nextParam++;
            if (nextParam >= params.size())
                return false;

            bound[nextParam++] = sema.viewZero(argRef).nodeRef();
        }

        if (bound.size() != params.size())
            return false;

        for (size_t i = 0; i < params.size(); i++)
        {
            if (!bound[i].isValid())
                return false;

            if (params[i]->idRef().isValid())
                outBindings.push_back({params[i]->idRef(), bound[i]});
        }

        return true;
    }

    bool hasVariadicParam(Sema& sema, const SymbolFunction& fn)
    {
        for (const SymbolVariable* param : fn.parameters())
        {
            SWC_ASSERT(param != nullptr);
            const TypeInfo& typeInfo = sema.typeMgr().get(param->typeRef());
            if (typeInfo.isAnyVariadic())
                return true;
        }

        return false;
    }

    bool isAutoInlineEnabled(const Sema& sema)
    {
        return sema.compiler().buildCfg().backend.optimize;
    }

    bool isAutoInlineScalarType(const TypeInfo& type)
    {
        return type.isBool() || type.isInt() || type.isFloat() || type.isRune() || type.isChar() || type.isEnum();
    }

    bool isPureInlineExpressionNode(AstNodeId id)
    {
        switch (id)
        {
            case AstNodeId::Identifier:
            case AstNodeId::AncestorIdentifier:
            case AstNodeId::ParenExpr:
            case AstNodeId::BinaryExpr:
            case AstNodeId::LogicalExpr:
            case AstNodeId::RelationalExpr:
            case AstNodeId::NullCoalescingExpr:
            case AstNodeId::ConditionalExpr:
            case AstNodeId::IndexExpr:
            case AstNodeId::MemberAccessExpr:
            case AstNodeId::AutoMemberAccessExpr:
            case AstNodeId::CastExpr:
            case AstNodeId::AutoCastExpr:
            case AstNodeId::AsCastExpr:
            case AstNodeId::IsTypeExpr:
            case AstNodeId::BoolLiteral:
            case AstNodeId::CharacterLiteral:
            case AstNodeId::FloatLiteral:
            case AstNodeId::IntegerLiteral:
            case AstNodeId::BinaryLiteral:
            case AstNodeId::HexaLiteral:
            case AstNodeId::NullLiteral:
            case AstNodeId::SuffixLiteral:
                return true;
            default:
                return false;
        }
    }

    bool isPureInlineExpressionTree(const Sema& sema, AstNodeRef rootRef, uint32_t& budget)
    {
        if (rootRef.isInvalid())
            return false;
        if (!budget)
            return false;
        budget--;

        const AstNode& node = sema.node(rootRef);
        if (!isPureInlineExpressionNode(node.id()))
            return false;

        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, sema.ast());
        for (const AstNodeRef childRef : children)
        {
            if (!isPureInlineExpressionTree(sema, childRef, budget))
                return false;
        }

        return true;
    }

    bool canAutoInlineFunction(Sema& sema, const SymbolFunction& fn)
    {
        if (fn.attributes().hasRtFlag(RtAttributeFlagsE::NoInline))
            return false;
        if (fn.isForeign())
            return false;
        if (fn.attributes().hasRtFlag(RtAttributeFlagsE::Inline))
            return true;
        if (!isAutoInlineEnabled(sema))
            return false;

        const TypeInfo& returnType = sema.typeMgr().get(fn.returnTypeRef());
        if (!isAutoInlineScalarType(returnType))
            return false;

        for (const SymbolVariable* const param : fn.parameters())
        {
            SWC_ASSERT(param != nullptr);
            const TypeInfo& paramType = sema.typeMgr().get(param->typeRef());
            if (!isAutoInlineScalarType(paramType))
                return false;
        }

        const AstNodeRef srcExprRef = inlineExprRef(sema, fn);
        if (srcExprRef.isInvalid())
            return false;

        uint32_t expressionBudget = 64;
        return isPureInlineExpressionTree(sema, srcExprRef, expressionBudget);
    }

    bool canAutoInlineArguments(Sema& sema, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
    {
        if (ufcsArg.isValid())
        {
            const AstNodeRef ufcsNodeRef = sema.viewZero(ufcsArg).nodeRef();
            uint32_t         argBudget   = 64;
            if (ufcsNodeRef.isInvalid() || !isPureInlineExpressionTree(sema, ufcsNodeRef, argBudget))
                return false;
        }

        for (const AstNodeRef argRef : args)
        {
            const AstNode& argNode = sema.node(argRef);
            if (isNamedArgument(argNode))
                continue;

            const AstNodeRef argNodeRef = sema.viewZero(argRef).nodeRef();
            uint32_t         argBudget  = 64;
            if (argNodeRef.isInvalid() || !isPureInlineExpressionTree(sema, argNodeRef, argBudget))
                return false;
        }

        return true;
    }
}

bool SemaInline::canInlineCall(Sema& sema, const SymbolFunction& fn)
{
    if (fn.isClosure() || fn.isEmpty())
        return false;
    if (hasVariadicParam(sema, fn))
        return false;
    return canAutoInlineFunction(sema, fn);
}

Result SemaInline::tryInlineCall(Sema& sema, AstNodeRef callRef, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
{
    if (!canInlineCall(sema, fn))
        return Result::Continue;
    if (!fn.attributes().hasRtFlag(RtAttributeFlagsE::Inline) && !canAutoInlineArguments(sema, args, ufcsArg))
        return Result::Continue;

    // TODO
    const AstNodeRef srcExprRef = inlineExprRef(sema, fn);
    if (srcExprRef.isInvalid())
        return Result::Continue;

    SmallVector<SemaClone::ParamBinding> bindings;
    if (!mapArguments(sema, fn, args, ufcsArg, bindings))
        return Result::Continue;

    const SemaClone::CloneContext cloneContext{bindings.span()};
    const AstNodeRef              inlinedRef = SemaClone::cloneAst(sema, srcExprRef, cloneContext);
    SWC_ASSERT(inlinedRef.isValid());

    if (fn.returnTypeRef() != sema.typeMgr().typeVoid())
    {
        auto frame = sema.frame();
        frame.pushBindingType(fn.returnTypeRef());
        sema.pushFramePopOnPostNode(frame, inlinedRef);
    }

    sema.setSubstitute(callRef, inlinedRef);
    sema.deferPostNodeAction(inlinedRef, [callRef, returnTypeRef = fn.returnTypeRef()](Sema& inSema, AstNodeRef nodeRef) { return finalizeInlinedCall(inSema, nodeRef, callRef, returnTypeRef); });
    sema.visit().restartCurrentNode(inlinedRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
