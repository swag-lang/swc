#include "pch.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaClone.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Type/TypeInfo.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    bool tryGetSimpleInlineConstant(Sema& sema, AstNodeRef inlineRootRef, ConstantRef& outConstant)
    {
        outConstant = ConstantRef::invalid();
        if (inlineRootRef.isInvalid())
            return false;

        const AstNode& rootNode = sema.node(inlineRootRef);
        if (!rootNode.is(AstNodeId::EmbeddedBlock))
            return false;

        SmallVector<AstNodeRef> statements;
        sema.ast().appendNodes(statements, rootNode.cast<AstEmbeddedBlock>().spanChildrenRef);
        if (statements.size() != 1)
            return false;

        const AstNode& stmtNode = sema.node(statements.front());
        if (!stmtNode.is(AstNodeId::ReturnStmt))
            return false;

        const AstNodeRef exprRef = stmtNode.cast<AstReturnStmt>().nodeExprRef;
        if (exprRef.isInvalid())
            return false;

        const SemaNodeView exprView = sema.viewConstant(exprRef);
        if (!exprView.hasConstant())
            return false;

        outConstant = exprView.cstRef();
        return outConstant.isValid();
    }

    bool isNamedArgument(const AstNode& node)
    {
        return node.is(AstNodeId::NamedArgument);
    }

    bool resolveFunctionDeclInCurrentAst(const Sema& sema, const SymbolFunction& fn, const AstFunctionDecl*& outDecl)
    {
        outDecl = nullptr;

        const AstNode* declNode = fn.decl();
        if (!declNode || !declNode->is(AstNodeId::FunctionDecl))
            return false;

        const Ast* const declAst = declNode->sourceAst(sema.ctx());
        if (!declAst || declAst != &sema.ast())
            return false;

        outDecl = &declNode->cast<AstFunctionDecl>();
        return true;
    }

    AstNodeRef makeInlineBodyFromShort(Sema& sema, const AstFunctionDecl& decl, const SemaClone::CloneContext& cloneContext)
    {
        if (decl.nodeBodyRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNodeRef clonedExprRef = SemaClone::cloneAst(sema, decl.nodeBodyRef, cloneContext);
        if (clonedExprRef.isInvalid())
            return AstNodeRef::invalid();

        auto [returnRef, returnPtr] = sema.ast().makeNode<AstNodeId::ReturnStmt>(decl.tokRef());
        returnPtr->nodeExprRef      = clonedExprRef;

        auto [blockRef, blockPtr] = sema.ast().makeNode<AstNodeId::EmbeddedBlock>(decl.tokRef());
        SmallVector<AstNodeRef> statements;
        statements.push_back(returnRef);
        blockPtr->spanChildrenRef = sema.ast().pushSpan(statements.span());
        return blockRef;
    }

    AstNodeRef inlineBodyRef(Sema& sema, const AstFunctionDecl& decl, const SemaClone::CloneContext& cloneContext)
    {
        if (decl.hasFlag(AstFunctionFlagsE::Short))
            return makeInlineBodyFromShort(sema, decl, cloneContext);

        if (decl.nodeBodyRef.isInvalid())
            return AstNodeRef::invalid();

        const AstNodeRef clonedBodyRef = SemaClone::cloneAst(sema, decl.nodeBodyRef, cloneContext);
        if (clonedBodyRef.isInvalid())
            return AstNodeRef::invalid();

        if (sema.node(clonedBodyRef).is(AstNodeId::EmbeddedBlock))
            return clonedBodyRef;

        auto [blockRef, blockPtr] = sema.ast().makeNode<AstNodeId::EmbeddedBlock>(decl.tokRef());
        SmallVector<AstNodeRef> statements;
        statements.push_back(clonedBodyRef);
        blockPtr->spanChildrenRef = sema.ast().pushSpan(statements.span());
        return blockRef;
    }

    Result createInlineResultVariable(Sema& sema, AstNodeRef callRef, TypeRef typeRef, SymbolVariable*& outResultVar)
    {
        outResultVar = nullptr;
        if (typeRef.isInvalid() || typeRef == sema.typeMgr().typeVoid())
            return Result::Continue;

        const AstNode&      callNode = sema.node(callRef);
        TaskContext&        ctx      = sema.ctx();
        const SymbolFlags   flags    = sema.frame().flagsForCurrentAccess();
        const IdentifierRef idRef    = SemaHelpers::getUniqueIdentifier(sema, "__inline_result");
        auto*               symVar   = Symbol::make<SymbolVariable>(ctx, &callNode, callNode.tokRef(), idRef, flags);
        symVar->addExtraFlag(SymbolVariableFlagsE::Initialized);
        symVar->setTypeRef(typeRef);
        symVar->setDeclared(ctx);
        symVar->setTyped(ctx);
        symVar->setSemaCompleted(ctx);

        if (SymbolFunction* currentFn = sema.frame().currentFunction())
        {
            const TypeInfo& resultType = sema.typeMgr().get(typeRef);
            SWC_RESULT_VERIFY(sema.waitSemaCompleted(&resultType, callRef));
            currentFn->addLocalVariable(ctx, symVar);
        }

        outResultVar = symVar;
        return Result::Continue;
    }

    Result finalizeInlineBlock(Sema& sema, AstNodeRef inlineRootRef, const SemaInline::Payload& payload)
    {
        SWC_ASSERT(inlineRootRef.isValid());
        SWC_ASSERT(payload.returnTypeRef.isValid());

        sema.setType(inlineRootRef, payload.returnTypeRef);
        const TypeInfo& returnType = sema.typeMgr().get(payload.returnTypeRef);
        if (!returnType.isVoid())
        {
            sema.setIsValue(inlineRootRef);
            if (returnType.isReference())
                sema.setIsLValue(inlineRootRef);
        }

        if (!returnType.isVoid())
        {
            ConstantRef cstRef = ConstantRef::invalid();
            if (tryGetSimpleInlineConstant(sema, inlineRootRef, cstRef))
            {
                sema.setFoldedTypedConst(inlineRootRef);
                sema.setConstant(inlineRootRef, cstRef);
                sema.setFoldedTypedConst(payload.callRef);
                sema.setConstant(payload.callRef, cstRef);
            }
        }

        return Result::Continue;
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
                outBindings.push_back({params[i]->idRef(), bound[i], params[i]->typeRef()});
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
}

bool SemaInline::canInlineCall(Sema& sema, const SymbolFunction& fn)
{
    if (fn.isClosure() || fn.isEmpty() || fn.isForeign())
        return false;
    if (hasVariadicParam(sema, fn))
        return false;
    if (fn.attributes().hasRtFlag(RtAttributeFlagsE::NoInline))
        return false;
    if (fn.attributes().hasRtFlag(RtAttributeFlagsE::Inline))
        return true;
    return false;
}

Result SemaInline::tryInlineCall(Sema& sema, AstNodeRef callRef, const SymbolFunction& fn, std::span<AstNodeRef> args, AstNodeRef ufcsArg)
{
    if (!canInlineCall(sema, fn))
        return Result::Continue;

    const AstFunctionDecl* decl = nullptr;
    if (!resolveFunctionDeclInCurrentAst(sema, fn, decl))
        return Result::Continue;

    SmallVector<SemaClone::ParamBinding> bindings;
    if (!mapArguments(sema, fn, args, ufcsArg, bindings))
        return Result::Continue;

    const SemaClone::CloneContext cloneContext{bindings.span()};
    const AstNodeRef              inlineRootRef = inlineBodyRef(sema, *decl, cloneContext);
    if (inlineRootRef.isInvalid())
        return Result::Continue;
    sema.node(inlineRootRef).setCodeRef(sema.node(callRef).codeRef());

    TypeRef returnTypeRef = fn.returnTypeRef();
    if (!returnTypeRef.isValid())
        returnTypeRef = sema.typeMgr().typeVoid();

    // Create payload
    auto* inlinePayload           = sema.compiler().allocate<Payload>();
    inlinePayload->callRef        = callRef;
    inlinePayload->inlineRootRef  = inlineRootRef;
    inlinePayload->sourceFunction = &fn;
    inlinePayload->returnTypeRef  = returnTypeRef;
    for (const SemaClone::ParamBinding& binding : bindings)
        inlinePayload->argMappings.push_back({binding.idRef, binding.exprRef});

    SWC_RESULT_VERIFY(createInlineResultVariable(sema, callRef, returnTypeRef, inlinePayload->resultVar));

    auto frame = sema.frame();
    if (returnTypeRef != sema.typeMgr().typeVoid())
        frame.pushBindingType(returnTypeRef);
    frame.setCurrentInlinePayload(inlinePayload);
    sema.pushFramePopOnPostNode(frame, inlineRootRef);

    sema.deferPostNodeAction(inlineRootRef, [inlinePayload](Sema& inSema, AstNodeRef nodeRef) {
        SWC_ASSERT(inlinePayload != nullptr);
        SWC_RESULT_VERIFY(finalizeInlineBlock(inSema, nodeRef, *inlinePayload));
        inSema.setCodeGenPayload(nodeRef, inlinePayload);
        return Result::Continue;
    });

    sema.setSubstitute(callRef, inlineRootRef);
    sema.visit().restartCurrentNode(inlineRootRef);
    return Result::Continue;
}

SWC_END_NAMESPACE();
