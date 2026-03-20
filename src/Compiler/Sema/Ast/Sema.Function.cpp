#include "pch.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Backend/ABI/ABITypeNormalize.h"
#include "Backend/ABI/CallConv.h"
#include "Backend/Runtime.h"
#include "Compiler/CodeGen/Core/CodeGen.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantIntrinsic.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Core/SemaNodeView.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Compiler/Sema/Helpers/SemaPurity.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Match/MatchContext.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Support/Math/Helpers.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    CodeGenNodePayload& ensureCodeGenNodePayload(Sema& sema, AstNodeRef nodeRef)
    {
        auto* payload = sema.codeGenPayload<CodeGenNodePayload>(nodeRef);
        if (payload)
            return *payload;

        payload = sema.compiler().allocate<CodeGenNodePayload>();
        sema.setCodeGenPayload(nodeRef, payload);
        return *payload;
    }

    bool isAttributeContextCall(const AstCallExpr& node)
    {
        return node.hasFlag(AstCallExprFlagsE::AttributeContext);
    }

    bool isAttributeContextCall(const AstIntrinsicCallExpr& node)
    {
        return node.hasFlag(AstCallExprFlagsE::AttributeContext);
    }

    bool isAttributeContextCall(const AstAliasCallExpr&)
    {
        return false;
    }
}

Result AstFunctionDecl::semaPreDecl(Sema& sema) const
{
    auto& sym = SemaHelpers::registerSymbol<SymbolFunction>(sema, *this, tokNameRef);

    sym.setExtraFlags(flags());
    sym.setDeclNodeRef(sema.curNodeRef());
    sym.setSpecOpKind(SemaSpecOp::computeSymbolKind(sema, sym));
    if (nodeBodyRef.isInvalid())
        sym.addExtraFlag(SymbolFunctionFlagsE::Empty);

    return Result::SkipChildren;
}

Result AstFunctionDecl::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
        SemaHelpers::declareSymbol(sema, *this);

    auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    if (sym.isMethod() && !sema.frame().currentImpl() && !sema.frame().currentInterface())
    {
        const SourceView& srcView   = sema.srcView(srcViewRef());
        const TokenRef    mtdTokRef = srcView.findLeftFrom(tokNameRef, {TokenId::KwdMtd});
        return SemaError::raise(sema, DiagnosticId::sema_err_method_outside_impl, SourceCodeRef{srcViewRef(), mtdTokRef});
    }

    SemaFrame frame           = sema.frame();
    frame.currentAttributes() = sym.attributes();
    frame.setCurrentFunction(&sym);
    sema.pushFramePopOnPostNode(frame);
    return Result::Continue;
}

Result AstFunctionExpr::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
    {
        TaskContext& ctx = sema.ctx();
        auto*        sym = Symbol::make<SymbolFunction>(ctx, this, tokRef(), SemaHelpers::getUniqueIdentifier(sema, "__lambda"), sema.frame().flagsForCurrentAccess());
        SymbolMap*   map = SemaFrame::currentSymMap(sema);
        SWC_ASSERT(map != nullptr);
        map->addSymbol(ctx, sym, true);

        sym->setExtraFlags(flags());
        sym->setDeclNodeRef(sema.curNodeRef());
        sym->setSpecOpKind(SemaSpecOp::computeSymbolKind(sema, *sym));
        sym->setDeclared(ctx);
        sema.setSymbol(sema.curNodeRef(), sym);

        SemaHelpers::addCurrentFunctionCallDependency(sema, sym);
    }

    auto&     sym   = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    SemaFrame frame = sema.frame();
    frame.setCurrentFunction(&sym);
    sema.pushFramePopOnPostNode(frame);
    return Result::Continue;
}

Result AstClosureExpr::semaPreNode(Sema& sema) const
{
    if (sema.enteringState())
    {
        TaskContext& ctx = sema.ctx();
        auto*        sym = Symbol::make<SymbolFunction>(ctx, this, tokRef(), SemaHelpers::getUniqueIdentifier(sema, "__closure"), sema.frame().flagsForCurrentAccess());
        SymbolMap*   map = SemaFrame::currentSymMap(sema);
        SWC_ASSERT(map != nullptr);
        map->addSymbol(ctx, sym, true);

        sym->setExtraFlags(flags());
        sym->setDeclNodeRef(sema.curNodeRef());
        sym->setSpecOpKind(SemaSpecOp::computeSymbolKind(sema, *sym));
        sym->setDeclared(ctx);
        sema.setSymbol(sema.curNodeRef(), sym);

        SemaHelpers::addCurrentFunctionCallDependency(sema, sym);
    }

    auto&     sym   = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    SemaFrame frame = sema.frame();
    frame.setCurrentFunction(&sym);
    sema.pushFramePopOnPostNode(frame);
    return Result::Continue;
}

namespace
{
    Result reportCodeTypeRestricted(Sema& sema, AstNodeRef nodeRef, TypeRef typeRef)
    {
        auto diag = SemaError::report(sema, DiagnosticId::sema_err_code_type_restricted, nodeRef);
        diag.addArgument(Diagnostic::ARG_TYPE, typeRef);
        diag.report(sema.ctx());
        return Result::Error;
    }

    SymbolFunction& functionExprSymbol(Sema& sema, AstNodeRef nodeRef)
    {
        if (Symbol* sym = sema.viewSymbol(nodeRef).sym())
            return sym->cast<SymbolFunction>();

        const TypeRef typeRef = sema.viewType(nodeRef).typeRef();
        SWC_ASSERT(typeRef.isValid());
        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        SWC_ASSERT(typeInfo.isFunction());
        return typeInfo.payloadSymFunction();
    }

    void registerRuntimeFunctionSymbol(Sema& sema, SymbolFunction& sym)
    {
        const SourceFile* file = sema.file();
        if (!file || !file->isRuntime())
            return;

        if (sym.isForeign() || sym.isEmpty())
            return;

        const auto kind = sema.idMgr().runtimeFunctionKind(sym.idRef());
        if (kind == IdentifierManager::RuntimeFunctionKind::Count)
            return;

        sema.compiler().registerRuntimeFunctionSymbol(sym.idRef(), &sym);
    }

    TypeRef unwrapLambdaBindingType(TaskContext& ctx, TypeRef typeRef)
    {
        while (typeRef.isValid())
        {
            const TypeInfo& typeInfo  = ctx.typeMgr().get(typeRef);
            const TypeRef   unwrapped = typeInfo.unwrap(ctx, TypeRef::invalid(), TypeExpandE::Alias | TypeExpandE::Enum);
            if (unwrapped.isValid())
            {
                typeRef = unwrapped;
                continue;
            }

            if (typeInfo.isReference())
            {
                typeRef = typeInfo.payloadTypeRef();
                continue;
            }

            break;
        }

        return typeRef;
    }

    const SymbolFunction* resolveLambdaBindingFunction(Sema& sema)
    {
        const std::span<const TypeRef> bindingTypes = sema.frame().bindingTypes();
        for (size_t bindingIndex = bindingTypes.size(); bindingIndex > 0; --bindingIndex)
        {
            const TypeRef bindingTypeRef = unwrapLambdaBindingType(sema.ctx(), bindingTypes[bindingIndex - 1]);
            if (!bindingTypeRef.isValid())
                continue;

            const TypeInfo& bindingType = sema.typeMgr().get(bindingTypeRef);
            if (bindingType.isFunction())
                return &bindingType.payloadSymFunction();
        }

        return nullptr;
    }

    Result findCompatibleReturnBindingType(Sema& sema, AstNodeRef exprRef, TypeRef& outTypeRef)
    {
        outTypeRef = TypeRef::invalid();
        if (exprRef.isInvalid())
            return Result::Continue;

        const SemaNodeView exprView = sema.viewNodeTypeConstant(exprRef);
        const auto         frames   = sema.frames();
        for (size_t frameIndex = frames.size(); frameIndex > 0; --frameIndex)
        {
            const std::span<const TypeRef> bindingTypes = frames[frameIndex - 1].bindingTypes();
            for (size_t bindingIndex = bindingTypes.size(); bindingIndex > 0; --bindingIndex)
            {
                const TypeRef bindingTypeRef = bindingTypes[bindingIndex - 1];
                if (!bindingTypeRef.isValid())
                    continue;

                CastRequest castRequest(CastKind::Implicit);
                castRequest.errorNodeRef = exprRef;
                const Result castResult  = Cast::castAllowed(sema, castRequest, exprView.typeRef(), bindingTypeRef);
                if (castResult == Result::Pause)
                    return Result::Pause;
                if (castResult != Result::Continue)
                    continue;

                outTypeRef = bindingTypeRef;
                return Result::Continue;
            }
        }

        return Result::Continue;
    }

    bool isCallResultIgnored(const Sema& sema)
    {
        const AstNode* parent = sema.visit().parentNode();
        if (!parent)
            return false;

        if (parent->is(AstNodeId::DiscardExpr))
            return false;

        switch (parent->id())
        {
            case AstNodeId::EmbeddedBlock:
            case AstNodeId::FunctionBody:
            case AstNodeId::SwitchCaseBody:
            case AstNodeId::TopLevelBlock:
                return true;
            default:
                return false;
        }
    }

    TypeRef deduceHomogeneousAggregateArrayType(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& type = sema.typeMgr().get(typeRef);
        if (type.isArray())
            return typeRef;
        if (!type.isAggregateArray())
            return TypeRef::invalid();

        const auto& elemTypes = type.payloadAggregate().types;
        if (elemTypes.empty())
            return TypeRef::invalid();

        TypeRef concreteElemTypeRef = TypeRef::invalid();
        for (TypeRef elemTypeRef : elemTypes)
        {
            const TypeInfo& elemType = sema.typeMgr().get(elemTypeRef);
            if (elemType.isAggregateArray())
                elemTypeRef = deduceHomogeneousAggregateArrayType(sema, elemTypeRef);

            if (!elemTypeRef.isValid())
                return TypeRef::invalid();

            if (!concreteElemTypeRef.isValid())
                concreteElemTypeRef = elemTypeRef;
            else if (concreteElemTypeRef != elemTypeRef)
                return TypeRef::invalid();
        }

        SmallVector4<uint64_t> dims;
        dims.push_back(elemTypes.size());
        return sema.typeMgr().addType(TypeInfo::makeArray(dims.span(), concreteElemTypeRef));
    }

    Result concretizeImplicitReturnTypeIfNeeded(Sema& sema, AstNodeRef exprRef, TypeRef& ioTypeRef)
    {
        if (exprRef.isInvalid() || !ioTypeRef.isValid())
            return Result::Continue;

        const TypeInfo& typeInfo = sema.typeMgr().get(ioTypeRef);
        if ((typeInfo.isIntUnsized() || typeInfo.isFloatUnsized()) && sema.viewConstant(exprRef).hasConstant())
        {
            const ConstantRef exprCstRef = sema.viewConstant(exprRef).cstRef();
            SWC_ASSERT(exprCstRef.isValid());

            ConstantRef concretizedCstRef = ConstantRef::invalid();
            SWC_RESULT(Cast::concretizeConstant(sema, concretizedCstRef, exprRef, exprCstRef, TypeInfo::Sign::Unknown));
            if (concretizedCstRef.isValid())
            {
                sema.setConstant(exprRef, concretizedCstRef);
                ioTypeRef = sema.cstMgr().get(concretizedCstRef).typeRef();
            }
        }

        const TypeRef concreteArrayTypeRef = deduceHomogeneousAggregateArrayType(sema, ioTypeRef);
        if (!concreteArrayTypeRef.isValid())
            return Result::Continue;

        SemaNodeView castView = sema.viewNodeTypeConstant(exprRef);
        SWC_RESULT(Cast::cast(sema, castView, concreteArrayTypeRef, CastKind::Implicit));
        ioTypeRef = concreteArrayTypeRef;
        return Result::Continue;
    }

    Result inferCompilerRunBlockReturnType(Sema& sema, SymbolFunction& sym, AstNodeRef exprRef, TypeRef& outTypeRef)
    {
        outTypeRef = TypeRef::invalid();
        if (exprRef.isInvalid())
        {
            outTypeRef = sema.typeMgr().typeVoid();
            sym.setReturnTypeRef(outTypeRef);
            return Result::Continue;
        }

        SWC_RESULT(findCompatibleReturnBindingType(sema, exprRef, outTypeRef));
        if (!outTypeRef.isValid())
        {
            const SemaNodeView exprView = sema.viewNodeTypeConstant(exprRef);
            if (exprView.cstRef().isValid())
            {
                ConstantRef newCstRef = ConstantRef::invalid();
                SWC_RESULT(Cast::concretizeConstant(sema, newCstRef, exprRef, exprView.cstRef(), TypeInfo::Sign::Unknown));
                if (newCstRef.isValid() && newCstRef != exprView.cstRef())
                    sema.setConstant(exprRef, newCstRef);
            }

            outTypeRef = sema.viewNodeTypeConstant(exprRef).typeRef();
            SWC_RESULT(concretizeImplicitReturnTypeIfNeeded(sema, exprRef, outTypeRef));
        }

        sym.setReturnTypeRef(outTypeRef);
        return Result::Continue;
    }

    Result resolveReturnTypeRef(Sema& sema, AstNodeRef exprRef, TypeRef& outTypeRef)
    {
        outTypeRef                             = TypeRef::invalid();
        const SemaInlinePayload* inlinePayload = sema.frame().currentInlinePayload();
        if (inlinePayload)
        {
            outTypeRef = inlinePayload->returnTypeRef;
            return Result::Continue;
        }

        auto* sym = SemaHelpers::currentFunction(sema);
        SWC_ASSERT(sym);
        if (!sym)
            return Result::Error;

        outTypeRef = sym->returnTypeRef();
        if (!outTypeRef.isValid() && sym->decl() && sym->decl()->is(AstNodeId::CompilerRunBlock))
            return inferCompilerRunBlockReturnType(sema, *sym, exprRef, outTypeRef);

        return Result::Continue;
    }

    Result validateReturnStatementValue(Sema& sema, AstNodeRef returnRef, AstNodeRef exprRef, TypeRef returnTypeRef)
    {
        SWC_ASSERT(returnTypeRef.isValid());
        if (!returnTypeRef.isValid())
            return Result::Error;

        const TypeInfo& returnType = sema.typeMgr().get(returnTypeRef);
        if (exprRef.isValid())
        {
            if (returnType.isVoid())
                return SemaError::raise(sema, DiagnosticId::sema_err_return_value_in_void, exprRef);

            SemaNodeView view = sema.viewNodeTypeConstant(exprRef);
            SWC_RESULT(Cast::cast(sema, view, returnTypeRef, CastKind::Implicit));
            return Result::Continue;
        }

        if (!returnType.isVoid())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_return_missing_value, returnRef);
            diag.addArgument(Diagnostic::ARG_REQUESTED_TYPE, returnType.toName(sema.ctx()));
            diag.report(sema.ctx());
            return Result::Error;
        }

        return Result::Continue;
    }

    SymbolFunction* callableTypeFunction(Sema& sema, TypeRef typeRef)
    {
        typeRef = unwrapLambdaBindingType(sema.ctx(), typeRef);
        if (!typeRef.isValid())
            return nullptr;

        const TypeInfo& typeInfo = sema.typeMgr().get(typeRef);
        if (!typeInfo.isFunction())
            return nullptr;

        return &typeInfo.payloadSymFunction();
    }

    bool isVoidCodeBlockParameter(Sema& sema, const SymbolVariable& param)
    {
        const TypeInfo& paramType = param.type(sema.ctx());
        return paramType.isCodeBlock() && paramType.payloadTypeRef() == sema.typeMgr().typeVoid();
    }

    bool hasExplicitLastArgumentBinding(Sema& sema, const SymbolFunction& fn, std::span<const AstNodeRef> args, AstNodeRef ufcsArg)
    {
        const auto& params = fn.parameters();
        if (params.empty())
            return false;

        std::vector<uint8_t> assigned(params.size(), 0);
        if (ufcsArg.isValid())
            assigned[0] = 1;

        for (const AstNodeRef argRef : args)
        {
            const AstNode& argNode = sema.node(argRef);
            if (!argNode.is(AstNodeId::NamedArgument))
                continue;

            const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), argNode.codeRef());
            for (size_t paramIndex = 0; paramIndex < params.size(); ++paramIndex)
            {
                if (params[paramIndex]->idRef() == idRef)
                {
                    assigned[paramIndex] = 1;
                    break;
                }
            }
        }

        size_t nextParam = ufcsArg.isValid() ? 1 : 0;
        for (const AstNodeRef argRef : args)
        {
            const AstNode& argNode = sema.node(argRef);
            if (argNode.is(AstNodeId::NamedArgument))
                continue;

            while (nextParam < params.size() && assigned[nextParam])
                ++nextParam;
            if (nextParam >= params.size())
                break;

            assigned[nextParam] = 1;
            ++nextParam;
        }

        return assigned.back() != 0;
    }

    bool canConsumeTrailingCodeBlock(Sema& sema, const SymbolFunction& fn, std::span<const AstNodeRef> args, AstNodeRef ufcsArg)
    {
        if (!SemaInline::canInlineCall(sema, fn))
            return false;

        const auto& params = fn.parameters();
        if (params.empty())
            return false;
        if (!isVoidCodeBlockParameter(sema, *params.back()))
            return false;
        if (hasExplicitLastArgumentBinding(sema, fn, args, ufcsArg))
            return false;

        return true;
    }

    AstNodeRef findTrailingCodeBlockSibling(Sema& sema, AstNodeRef callRef)
    {
        const AstNode* parentNode = sema.visit().parentNode();
        if (!parentNode)
            return AstNodeRef::invalid();

        switch (parentNode->id())
        {
            case AstNodeId::EmbeddedBlock:
            case AstNodeId::FunctionBody:
            case AstNodeId::SwitchCaseBody:
            case AstNodeId::TopLevelBlock:
                break;
            default:
                return AstNodeRef::invalid();
        }

        SmallVector<AstNodeRef> children;
        parentNode->collectChildrenFromAst(children, sema.ast());

        for (size_t childIndex = 0; childIndex < children.size(); ++childIndex)
        {
            if (children[childIndex] != callRef)
                continue;

            for (size_t nextIndex = childIndex + 1; nextIndex < children.size(); ++nextIndex)
            {
                const AstNodeRef siblingRef = children[nextIndex];
                if (siblingRef.isInvalid())
                    continue;
                if (siblingRef == callRef)
                    continue;

                return sema.node(siblingRef).is(AstNodeId::EmbeddedBlock) ? siblingRef : AstNodeRef::invalid();
            }

            break;
        }

        return AstNodeRef::invalid();
    }

    AstNodeRef makeTrailingCodeBlockArgument(Sema& sema, AstNodeRef siblingRef, const SymbolVariable& param)
    {
        auto [wrappedRef, wrappedPtr] = sema.ast().makeNode<AstNodeId::CompilerCodeBlock>(sema.node(siblingRef).tokRef());
        wrappedPtr->setCodeRef(sema.node(siblingRef).codeRef());
        wrappedPtr->nodeBodyRef    = siblingRef;
        wrappedPtr->payloadTypeRef = param.type(sema.ctx()).payloadTypeRef();
        return wrappedRef;
    }

    AstNodeRef resolveTrailingCodeBlockArgument(Sema& sema, const SemaNodeView& nodeCallee, std::span<Symbol*> symbols, std::span<const AstNodeRef> args, AstNodeRef ufcsArg, AstNodeRef& outSiblingRef)
    {
        outSiblingRef = findTrailingCodeBlockSibling(sema, sema.curNodeRef());
        if (outSiblingRef.isInvalid())
            return AstNodeRef::invalid();

        for (Symbol* const sym : symbols)
        {
            if (!sym)
                continue;
            const SymbolFunction* fn = nullptr;
            if (sym->isFunction())
                fn = &sym->cast<SymbolFunction>();
            else if (sym->isVariable())
                fn = callableTypeFunction(sema, sym->typeRef());

            if (fn && canConsumeTrailingCodeBlock(sema, *fn, args, ufcsArg))
                return makeTrailingCodeBlockArgument(sema, outSiblingRef, *fn->parameters().back());
        }

        if (symbols.empty() && sema.isValue(nodeCallee.nodeRef()))
        {
            if (const auto* fn = callableTypeFunction(sema, nodeCallee.typeRef()); fn && canConsumeTrailingCodeBlock(sema, *fn, args, ufcsArg))
                return makeTrailingCodeBlockArgument(sema, outSiblingRef, *fn->parameters().back());
        }

        outSiblingRef.setInvalid();
        return AstNodeRef::invalid();
    }

    const SymbolFunction* uniqueInlineFunctionForCodeArgs(Sema& sema, AstNodeRef calleeRef)
    {
        SmallVector<Symbol*> symbols;
        sema.viewSymbol(calleeRef).getSymbols(symbols);

        const AstNode& calleeNode = sema.node(calleeRef);
        if (calleeNode.is(AstNodeId::MemberAccessExpr) || calleeNode.is(AstNodeId::AutoMemberAccessExpr))
            return nullptr;

        if (symbols.empty() && sema.isValue(calleeRef))
        {
            if (auto* symFunc = callableTypeFunction(sema, sema.viewType(calleeRef).typeRef()))
                symbols.push_back(symFunc);
        }

        if (symbols.size() != 1)
            return nullptr;

        const SymbolFunction* fn = nullptr;
        if (symbols.front()->isFunction())
        {
            fn = &symbols.front()->cast<SymbolFunction>();
        }
        else if (symbols.front()->isVariable())
        {
            fn = callableTypeFunction(sema, symbols.front()->typeRef());
        }

        if (!fn || !SemaInline::canInlineCall(sema, *fn))
            return nullptr;

        return fn;
    }

    template<typename T>
    const SymbolVariable* mappedCodeParameter(Sema& sema, const T& call, const SymbolFunction& fn, AstNodeRef childRef)
    {
        SmallVector<AstNodeRef> args;
        call.collectArguments(args, sema.ast());

        const auto& params = fn.parameters();
        if (params.empty())
            return nullptr;

        const AstNode& childNode = sema.node(childRef);
        if (childNode.is(AstNodeId::NamedArgument))
        {
            const IdentifierRef idRef = sema.idMgr().addIdentifier(sema.ctx(), childNode.codeRef());
            for (const SymbolVariable* param : params)
            {
                if (param && param->idRef() == idRef)
                    return param->type(sema.ctx()).isCodeBlock() ? param : nullptr;
            }

            return nullptr;
        }

        uint32_t positionalIndex = 0;
        bool     seenNamed       = false;
        for (const AstNodeRef argRef : args)
        {
            const AstNode& argNode = sema.node(argRef);
            if (argNode.is(AstNodeId::NamedArgument))
            {
                seenNamed = true;
                continue;
            }

            if (seenNamed)
                return nullptr;

            if (argRef != childRef)
            {
                ++positionalIndex;
                continue;
            }

            if (positionalIndex >= params.size())
                return nullptr;

            const SymbolVariable* param = params[positionalIndex];
            return param && param->type(sema.ctx()).isCodeBlock() ? param : nullptr;
        }

        return nullptr;
    }

    bool isCallAliasChild(const AstCallExpr&, const Ast&, AstNodeRef)
    {
        return false;
    }

    bool isCallAliasChild(const AstAliasCallExpr& call, const Ast& ast, AstNodeRef childRef)
    {
        for (size_t i = 0; i < ast.spanSize(call.spanAliasesRef); ++i)
        {
            if (ast.nthNode(call.spanAliasesRef, i) == childRef)
                return true;
        }

        return false;
    }

    template<typename T>
    Result semaCallExprPreNodeChildCommon(Sema& sema, const T& node, AstNodeRef childRef)
    {
        if (childRef == node.nodeExprRef)
            return Result::Continue;

        if (isCallAliasChild(node, sema.ast(), childRef))
            return Result::SkipChildren;

        if (const SymbolFunction* fn = uniqueInlineFunctionForCodeArgs(sema, node.nodeExprRef))
        {
            if (mappedCodeParameter(sema, node, *fn, childRef))
                return Result::SkipChildren;
        }

        if (isAttributeContextCall(node))
            SemaHelpers::pushConstExprRequirement(sema, childRef);

        return Result::Continue;
    }

    bool lambdaHasExpressionBody(Sema& sema, AstNodeRef bodyRef)
    {
        return bodyRef.isValid() && sema.node(bodyRef).isNot(AstNodeId::EmbeddedBlock);
    }

    template<typename T>
    Result buildFunctionExprParameters(Sema& sema, const T& node, SymbolFunction& sym)
    {
        if (!sym.parameters().empty())
            return Result::Continue;

        TaskContext&            ctx             = sema.ctx();
        const SymbolFunction*   bindingFunction = resolveLambdaBindingFunction(sema);
        SmallVector<AstNodeRef> params;
        sema.ast().appendNodes(params, node.spanArgsRef);

        for (size_t paramIndex = 0; paramIndex < params.size(); paramIndex++)
        {
            const AstNodeRef      paramRef  = params[paramIndex];
            const AstLambdaParam& param     = sema.node(paramRef).cast<AstLambdaParam>();
            TypeRef               paramType = TypeRef::invalid();
            if (param.nodeTypeRef.isValid())
                paramType = sema.viewType(param.nodeTypeRef).typeRef();
            else if (bindingFunction && paramIndex < bindingFunction->parameters().size())
                paramType = bindingFunction->parameters()[paramIndex]->typeRef();

            SWC_ASSERT(paramType.isValid());

            IdentifierRef idRef = IdentifierRef::invalid();
            if (param.hasFlag(AstLambdaParamFlagsE::Named))
            {
                const Token& tok = sema.token(param.codeRef());
                if (tok.id == TokenId::Identifier)
                    idRef = sema.idMgr().addIdentifier(ctx, param.codeRef());
            }

            auto* symVar = Symbol::make<SymbolVariable>(ctx, &param, param.tokRef(), idRef, SymbolFlagsE::Zero);
            symVar->setTypeRef(paramType);
            symVar->addExtraFlag(SymbolVariableFlagsE::Parameter);

            sym.addParameter(symVar);
            if (idRef.isValid())
                sym.addSymbol(ctx, symVar, false);

            symVar->setDeclared(ctx);
            symVar->setTyped(ctx);
            symVar->setSemaCompleted(ctx);
        }

        return Result::Continue;
    }

    template<typename T>
    Result prepareFunctionExprSignature(Sema& sema, const T& node, SymbolFunction& sym)
    {
        SWC_RESULT(buildFunctionExprParameters(sema, node, sym));

        if (sym.returnTypeRef().isValid())
            return Result::Continue;

        if (node.nodeReturnTypeRef.isValid())
        {
            sym.setReturnTypeRef(sema.viewType(node.nodeReturnTypeRef).typeRef());
            return Result::Continue;
        }

        if (const SymbolFunction* bindingFunction = resolveLambdaBindingFunction(sema))
        {
            sym.setReturnTypeRef(bindingFunction->returnTypeRef());
            return Result::Continue;
        }

        if (!lambdaHasExpressionBody(sema, node.nodeBodyRef))
            sym.setReturnTypeRef(sema.typeMgr().typeVoid());

        return Result::Continue;
    }

    template<typename T>
    Result finalizeFunctionExprSignature(Sema& sema, const T& node, SymbolFunction& sym)
    {
        SWC_RESULT(prepareFunctionExprSignature(sema, node, sym));

        if (!sym.returnTypeRef().isValid())
        {
            if (node.nodeBodyRef.isValid())
            {
                TypeRef returnTypeRef = sema.viewType(node.nodeBodyRef).typeRef();
                SWC_RESULT(concretizeImplicitReturnTypeIfNeeded(sema, node.nodeBodyRef, returnTypeRef));
                sym.setReturnTypeRef(returnTypeRef);
            }
            else
                sym.setReturnTypeRef(sema.typeMgr().typeVoid());
        }

        sym.setVariadicParamFlag(sema.ctx());

        const TypeInfo ti      = TypeInfo::makeFunction(&sym, TypeInfoFlagsE::Zero);
        const TypeRef  typeRef = sema.typeMgr().addType(ti);
        sym.setTypeRef(typeRef);
        SemaPurity::computePurityFlag(sema, sym);
        sym.setTyped(sema.ctx());

        SWC_RESULT(SemaCheck::isValidSignature(sema, sym.parameters(), false));
        SWC_RESULT(SemaSpecOp::validateSymbol(sema, sym));
        registerRuntimeFunctionSymbol(sema, sym);

        sema.setIsValue(sema.curNodeRef());
        sema.unsetIsLValue(sema.curNodeRef());
        return Result::Continue;
    }

    SymbolFunction* resolveEnclosingFunctionForClosureRuntimeStorage(Sema& sema)
    {
        for (size_t parentIndex = 0;; ++parentIndex)
        {
            const AstNodeRef parentRef = sema.visit().parentNodeRef(parentIndex);
            if (parentRef.isInvalid())
                break;

            if (Symbol* const symbol = sema.viewSymbol(parentRef).sym(); symbol && symbol->isFunction())
                return &symbol->cast<SymbolFunction>();
        }

        return nullptr;
    }

    Result completeRuntimeStorageSymbol(Sema& sema, SymbolVariable& symVar, TypeRef typeRef, SymbolFunction* ownerFunction)
    {
        symVar.addExtraFlag(SymbolVariableFlagsE::Initialized);
        symVar.setTypeRef(typeRef);

        if (!ownerFunction)
            ownerFunction = SemaHelpers::currentFunction(sema);
        if (ownerFunction && typeRef.isValid())
        {
            const TypeInfo& symType = sema.typeMgr().get(typeRef);
            SWC_RESULT(sema.waitSemaCompleted(&symType, sema.curNodeRef()));
            ownerFunction->addLocalVariable(sema.ctx(), &symVar);
        }

        symVar.setTyped(sema.ctx());
        symVar.setSemaCompleted(sema.ctx());
        return Result::Continue;
    }

    SymbolVariable& registerUniqueRuntimeStorageSymbol(Sema& sema, const AstNode& node, const Utf8& privateName)
    {
        TaskContext&        ctx         = sema.ctx();
        const IdentifierRef idRef       = SemaHelpers::getUniqueIdentifier(sema, privateName);
        const SymbolFlags   flags       = sema.frame().flagsForCurrentAccess();
        auto*               symVariable = Symbol::make<SymbolVariable>(ctx, &node, node.tokRef(), idRef, flags);
        if (sema.curScope().isLocal() && !sema.curScope().symMap())
        {
            sema.curScope().addSymbol(symVariable);
        }
        else
        {
            SymbolMap* symMap = SemaFrame::currentSymMap(sema);
            SWC_ASSERT(symMap != nullptr);
            symMap->addSymbol(ctx, symVariable, true);
        }

        return *(symVariable);
    }

    Result attachRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, TypeRef storageTypeRef, const Utf8& privateName, SymbolFunction* ownerFunction = nullptr)
    {
        const auto* payload = sema.codeGenPayload<CodeGenNodePayload>(sema.curNodeRef());
        if (payload && payload->runtimeStorageSym != nullptr)
            return Result::Continue;
        if (storageTypeRef.isInvalid())
            return Result::Continue;

        if (SymbolVariable* const boundStorage = SemaHelpers::currentRuntimeStorage(sema))
        {
            ensureCodeGenNodePayload(sema, sema.curNodeRef()).runtimeStorageSym = boundStorage;
            return Result::Continue;
        }

        auto& storageSym = registerUniqueRuntimeStorageSymbol(sema, node, privateName);
        storageSym.registerAttributes(sema);
        storageSym.setDeclared(sema.ctx());
        SWC_RESULT(Match::ghosting(sema, storageSym));
        SWC_RESULT(completeRuntimeStorageSymbol(sema, storageSym, storageTypeRef, ownerFunction));

        ensureCodeGenNodePayload(sema, sema.curNodeRef()).runtimeStorageSym = &storageSym;
        return Result::Continue;
    }

    Result attachClosureExprRuntimeStorageIfNeeded(Sema& sema, const AstClosureExpr& node, const SymbolFunction& sym)
    {
        if (SemaHelpers::isGlobalScope(sema))
            return Result::Continue;
        if (!sym.typeRef().isValid())
            return Result::Continue;

        SymbolFunction* const ownerFunction = resolveEnclosingFunctionForClosureRuntimeStorage(sema);
        return attachRuntimeStorageIfNeeded(sema, node, sym.typeRef(), Utf8("__closure_runtime_storage"), ownerFunction);
    }

    Result buildClosureCaptureSymbols(Sema& sema, const AstClosureExpr& node, SymbolFunction& sym)
    {
        TaskContext&            ctx = sema.ctx();
        SmallVector<AstNodeRef> captures;
        sema.ast().appendNodes(captures, node.nodeCaptureArgsRef);

        uint64_t captureOffset = 0;
        for (const AstNodeRef captureRef : captures)
        {
            const AstClosureArgument& captureArg = sema.node(captureRef).cast<AstClosureArgument>();
            const SemaNodeView        sourceView = sema.viewSymbol(captureArg.nodeIdentifierRef);
            Symbol* const             sourceSym  = sourceView.sym();
            if (!sourceSym || !sourceSym->isVariable())
                return SemaError::raise(sema, DiagnosticId::sema_err_closure_capture_invalid, captureArg.nodeIdentifierRef);

            auto&           sourceVar = sourceSym->cast<SymbolVariable>();
            const TypeRef   typeRef   = sourceVar.typeRef();
            const TypeInfo& typeInfo  = sema.typeMgr().get(typeRef);
            SWC_RESULT(sema.waitSemaCompleted(&typeInfo, captureArg.nodeIdentifierRef));

            const bool captureByRef = captureArg.hasFlag(AstClosureArgumentFlagsE::Address);
            if (captureByRef && sourceVar.hasExtraFlag(SymbolVariableFlagsE::Let))
                return SemaError::raise(sema, DiagnosticId::sema_err_take_address_constant, captureArg.nodeIdentifierRef);

            uint32_t storageSize  = static_cast<uint32_t>(typeInfo.sizeOf(ctx));
            uint32_t storageAlign = typeInfo.alignOf(ctx);
            if (captureByRef)
            {
                storageSize  = sizeof(void*);
                storageAlign = alignof(void*);
            }

            if (!storageAlign)
                storageAlign = 1;

            captureOffset = Math::alignUpU64(captureOffset, storageAlign);
            if (captureOffset + storageSize > Runtime::CLOSURE_CAPTURE_BUFFER_SIZE)
            {
                auto diag = SemaError::report(sema, DiagnosticId::sema_err_closure_capture_too_large, captureArg.nodeIdentifierRef);
                diag.addArgument(Diagnostic::ARG_TYPE, typeRef);
                diag.addArgument(Diagnostic::ARG_VALUE, Runtime::CLOSURE_CAPTURE_BUFFER_SIZE);
                diag.report(sema.ctx());
                return Result::Error;
            }

            auto* captureSym = Symbol::make<SymbolVariable>(ctx, &captureArg, captureArg.tokRef(), sourceVar.idRef(), SymbolFlagsE::Zero);
            captureSym->setTypeRef(typeRef);
            captureSym->setClosureCapturedSource(&sourceVar);
            captureSym->setClosureCaptureOffset(static_cast<uint32_t>(captureOffset));
            captureSym->setClosureCaptureByRef(captureByRef);

            if (captureByRef && sourceVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
                sourceVar.addExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage);

            if (sourceVar.idRef().isValid())
            {
                if (sym.addSingleSymbol(ctx, captureSym) != captureSym)
                    return SemaError::raise(sema, DiagnosticId::sema_err_closure_capture_invalid, captureArg.nodeIdentifierRef);
            }

            captureSym->setDeclared(ctx);
            captureSym->setTyped(ctx);
            captureSym->setSemaCompleted(ctx);
            captureOffset += storageSize;
        }

        return Result::Continue;
    }

    void addMeParameter(Sema& sema, SymbolFunction& sym)
    {
        if (sema.frame().currentImpl() && sema.frame().currentImpl()->isForStruct())
        {
            const SymbolImpl& symImpl   = sema.frame().currentImpl()->asSymMap()->cast<SymbolImpl>();
            const TypeRef     ownerType = symImpl.symStruct()->typeRef();
            TaskContext&      ctx       = sema.ctx();
            auto*             symMe     = Symbol::make<SymbolVariable>(ctx, nullptr, TokenRef::invalid(), sema.idMgr().predefined(IdentifierManager::PredefinedName::Me), SymbolFlagsE::Zero);
            TypeInfoFlags     typeFlags = TypeInfoFlagsE::Zero;
            if (sym.hasExtraFlag(SymbolFunctionFlagsE::Const))
                typeFlags.add(TypeInfoFlagsE::Const);
            symMe->setTypeRef(sema.typeMgr().addType(TypeInfo::makeReference(ownerType, typeFlags)));
            symMe->addExtraFlag(SymbolVariableFlagsE::Parameter);

            sym.addParameter(symMe);
            sym.addSymbol(ctx, symMe, true);
            symMe->setDeclared(ctx);
            symMe->setTyped(ctx);
        }
    }

    Result setupIntrinsicGetContextRuntimeCall(Sema& sema, const AstIntrinsicCallExpr& node)
    {
        if (SemaHelpers::isNativeBuild(sema))
        {
            SymbolFunction* tlsAllocFn  = nullptr;
            SymbolFunction* tlsGetPtrFn = nullptr;
            SWC_RESULT(sema.waitRuntimeFunction(IdentifierManager::RuntimeFunctionKind::TlsAlloc, tlsAllocFn, node.codeRef()));
            SWC_RESULT(sema.waitRuntimeFunction(IdentifierManager::RuntimeFunctionKind::TlsGetPtr, tlsGetPtrFn, node.codeRef()));
            SWC_ASSERT(tlsAllocFn != nullptr);
            SWC_ASSERT(tlsGetPtrFn != nullptr);

            SemaHelpers::addCurrentFunctionCallDependency(sema, tlsAllocFn);
            SemaHelpers::addCurrentFunctionCallDependency(sema, tlsGetPtrFn);

            return Result::Continue;
        }

        SymbolFunction* tlsGetValueFn = nullptr;
        SWC_RESULT(sema.waitRuntimeFunction(IdentifierManager::RuntimeFunctionKind::TlsGetValue, tlsGetValueFn, node.codeRef()));
        SWC_ASSERT(tlsGetValueFn != nullptr);

        SemaHelpers::addCurrentFunctionCallDependency(sema, tlsGetValueFn);

        auto* payload = sema.codeGenPayload<CodeGenNodePayload>(sema.curNodeRef());
        if (!payload)
        {
            payload = sema.compiler().allocate<CodeGenNodePayload>();
            sema.setCodeGenPayload(sema.curNodeRef(), payload);
        }

        payload->runtimeFunctionSymbol = tlsGetValueFn;
        return Result::Continue;
    }

    Result setupIntrinsicAssertRuntimeCall(Sema& sema, const AstIntrinsicCallExpr& node)
    {
        SymbolFunction* raiseExceptionFn = nullptr;
        SWC_RESULT(sema.waitRuntimeFunction(IdentifierManager::RuntimeFunctionKind::RaiseException, raiseExceptionFn, node.codeRef()));
        SWC_ASSERT(raiseExceptionFn != nullptr);

        SemaHelpers::addCurrentFunctionCallDependency(sema, raiseExceptionFn);

        auto* payload = sema.codeGenPayload<CodeGenNodePayload>(sema.curNodeRef());
        if (!payload)
        {
            payload = sema.compiler().allocate<CodeGenNodePayload>();
            sema.setCodeGenPayload(sema.curNodeRef(), payload);
        }

        payload->runtimeFunctionSymbol = raiseExceptionFn;
        return Result::Continue;
    }

    TypeRef callExprRuntimeStorageTypeRef(Sema& sema, const SymbolFunction& calledFn)
    {
        if (SemaHelpers::isGlobalScope(sema))
            return TypeRef::invalid();

        const TypeRef returnTypeRef = calledFn.returnTypeRef();
        if (!returnTypeRef.isValid())
            return TypeRef::invalid();

        const TypeInfo& returnType = sema.typeMgr().get(returnTypeRef);
        if (returnType.isVoid())
            return TypeRef::invalid();

        const CallConv&                        callConv      = CallConv::get(calledFn.callConvKind());
        const ABITypeNormalize::NormalizedType normalizedRet = ABITypeNormalize::normalize(sema.ctx(), callConv, returnTypeRef, ABITypeNormalize::Usage::Return);
        if (!normalizedRet.isIndirect)
            return TypeRef::invalid();

        const TypeRef storageTypeRef = returnType.unwrap(sema.ctx(), returnTypeRef, TypeExpandE::Alias | TypeExpandE::Enum);
        if (storageTypeRef.isValid())
            return storageTypeRef;

        return returnTypeRef;
    }

    Result attachCallExprRuntimeStorageIfNeeded(Sema& sema, const AstNode& node, const SymbolFunction& calledFn)
    {
        const TypeRef storageTypeRef = callExprRuntimeStorageTypeRef(sema, calledFn);
        return attachRuntimeStorageIfNeeded(sema, node, storageTypeRef, Utf8("__call_runtime_storage"));
    }

    template<typename T>
    Result semaCallExprCommon(Sema& sema, const T& node, bool tryIntrinsicFold)
    {
        const SemaNodeView nodeCallee = sema.view(node.nodeExprRef, SemaNodeViewPartE::Node | SemaNodeViewPartE::Type | SemaNodeViewPartE::Symbol);

        SmallVector<AstNodeRef> args;
        node.collectArguments(args, sema.ast());
        for (auto& arg : args)
            arg = Match::resolveCallArgumentRef(sema, arg);

        SmallVector<Symbol*> symbols;
        nodeCallee.getSymbols(symbols);
        if (symbols.empty() && sema.isValue(nodeCallee.nodeRef()))
        {
            if (auto* symFunc = callableTypeFunction(sema, nodeCallee.typeRef()))
                symbols.push_back(symFunc);
        }

        AstNodeRef ufcsArg = AstNodeRef::invalid();
        SWC_ASSERT(nodeCallee.node() != nullptr);
        const AstNodeRef resolvedCalleeRef = SemaHelpers::unwrapCallCalleeRef(sema, node.nodeExprRef);
        if (resolvedCalleeRef.isValid() && sema.node(resolvedCalleeRef).is(AstNodeId::MemberAccessExpr))
        {
            const auto&        memberAccess = sema.node(resolvedCalleeRef).cast<AstMemberAccessExpr>();
            const SemaNodeView nodeLeftView = sema.viewZero(memberAccess.nodeLeftRef);
            if (sema.isValue(nodeLeftView.nodeRef()))
                ufcsArg = nodeLeftView.nodeRef();
        }

        AstNodeRef       trailingBlockSiblingRef = AstNodeRef::invalid();
        const AstNodeRef trailingBlockArgRef     = resolveTrailingCodeBlockArgument(sema, nodeCallee, symbols, args.span(), ufcsArg, trailingBlockSiblingRef);
        if (trailingBlockArgRef.isValid())
            args.push_back(trailingBlockArgRef);

        SmallVector<ResolvedCallArgument> resolvedArgs;
        const auto                        resolveMode = isAttributeContextCall(node) ? Match::ResolveCallMode::AttributeOnly : Match::ResolveCallMode::Normal;
        SWC_RESULT(Match::resolveFunctionCandidates(sema, nodeCallee, symbols, args, ufcsArg, &resolvedArgs, resolveMode));
        sema.setResolvedCallArguments(sema.curNodeRef(), resolvedArgs);
        if (trailingBlockSiblingRef.isValid())
            sema.markImplicitCodeBlockArg(sema.visit().parentNodeRef(), trailingBlockSiblingRef);
        const SemaNodeView nodeSymView = sema.curViewSymbol();
        SWC_ASSERT(nodeSymView.hasSymbol());

        auto&      calledFn    = nodeSymView.sym()->cast<SymbolFunction>();
        const bool isMixinCall = calledFn.attributes().hasRtFlag(RtAttributeFlagsE::Mixin);
        const bool isMacroCall = calledFn.attributes().hasRtFlag(RtAttributeFlagsE::Macro);
        if (auto* currentFn = SemaHelpers::currentFunction(sema); currentFn &&
                                                                  currentFn->decl() &&
                                                                  calledFn.decl() &&
                                                                  calledFn.declNodeRef().isValid() &&
                                                                  !calledFn.isForeign() &&
                                                                  !calledFn.isEmpty() &&
                                                                  !isMixinCall &&
                                                                  !isMacroCall)
            currentFn->addCallDependency(&calledFn);

        const TypeInfo& returnType = sema.typeMgr().get(calledFn.returnTypeRef());
        if (!returnType.isVoid() &&
            !calledFn.attributes().hasRtFlag(RtAttributeFlagsE::Discardable) &&
            isCallResultIgnored(sema))
        {
            return SemaError::raise(sema, DiagnosticId::sema_err_return_value_must_be_used, sema.curNodeRef());
        }

        if (tryIntrinsicFold)
        {
            SWC_RESULT(ConstantIntrinsic::tryConstantFoldCall(sema, calledFn, args));
        }
        else
        {
            SWC_RESULT(SemaJIT::tryRunConstCall(sema, calledFn, sema.curNodeRef(), resolvedArgs.span()));
            if (sema.viewConstant(sema.curNodeRef()).hasConstant())
                return Result::Continue;
            SWC_RESULT(SemaInline::tryInlineCall(sema, sema.curNodeRef(), calledFn, args, ufcsArg));
            SWC_RESULT(attachCallExprRuntimeStorageIfNeeded(sema, node, calledFn));
        }

        return Result::Continue;
    }
}

Result AstFunctionDecl::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef == nodeParamsRef)
    {
        auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();
        sema.pushScopePopOnPostChild(SemaScopeFlagsE::Parameters, childRef);
        sema.curScope().setSymMap(&sym);
        if (sym.isMethod())
            addMeParameter(sema, sym);
    }
    else if (childRef == nodeBodyRef)
    {
        auto& sym          = sema.curViewSymbol().sym()->cast<SymbolFunction>();
        bool  hasCodeParam = false;
        for (const SymbolVariable* param : sym.parameters())
        {
            if (param && param->type(sema.ctx()).isCodeBlock())
            {
                hasCodeParam = true;
                break;
            }
        }

        if (sym.attributes().hasRtFlag(RtAttributeFlagsE::Mixin) || (sym.attributes().hasRtFlag(RtAttributeFlagsE::Macro) && hasCodeParam))
        {
            const bool shortWithoutExplicitReturnType = hasFlag(AstFunctionFlagsE::Short) && nodeReturnTypeRef.isInvalid();
            if (!shortWithoutExplicitReturnType)
                return Result::SkipChildren;
        }

        auto frame = sema.frame();
        if (sym.isMethod())
        {
            const auto& params = sym.parameters();
            if (!params.empty() && params[0]->idRef() == sema.idMgr().predefined(IdentifierManager::PredefinedName::Me))
                frame.pushBindingVar(params[0]);
        }

        frame.pushBindingType(sym.returnTypeRef());
        sema.pushFramePopOnPostNode(frame);

        sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
        sema.curScope().setSymMap(&sym);
    }

    return Result::Continue;
}

Result AstFunctionExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    auto& sym = functionExprSymbol(sema, sema.curNodeRef());
    SWC_RESULT(prepareFunctionExprSignature(sema, *this, sym));

    auto frame = sema.frame();
    if (sym.returnTypeRef().isValid())
        frame.pushBindingType(sym.returnTypeRef());
    sema.pushFramePopOnPostNode(frame);

    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    sema.curScope().setSymMap(&sym);
    return Result::Continue;
}

Result AstClosureExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    auto& sym = functionExprSymbol(sema, sema.curNodeRef());
    SWC_RESULT(prepareFunctionExprSignature(sema, *this, sym));
    SWC_RESULT(buildClosureCaptureSymbols(sema, *this, sym));

    auto frame = sema.frame();
    if (sym.returnTypeRef().isValid())
        frame.pushBindingType(sym.returnTypeRef());
    sema.pushFramePopOnPostNode(frame);

    sema.pushScopePopOnPostNode(SemaScopeFlagsE::Local);
    sema.curScope().setSymMap(&sym);
    return Result::Continue;
}

Result AstFunctionDecl::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();

    bool setIsTyped = false;
    if (hasFlag(AstFunctionFlagsE::Short))
    {
        if (nodeReturnTypeRef.isValid())
        {
            if (childRef == nodeReturnTypeRef)
            {
                sym.setReturnTypeRef(sema.viewType(nodeReturnTypeRef).typeRef());
                setIsTyped = true;
            }
        }
        else if (childRef == nodeBodyRef)
        {
            TypeRef returnTypeRef = sema.viewType(nodeBodyRef).typeRef();
            SWC_RESULT(concretizeImplicitReturnTypeIfNeeded(sema, nodeBodyRef, returnTypeRef));
            sym.setReturnTypeRef(returnTypeRef);
            setIsTyped = true;
        }
    }
    else if (childRef == nodeReturnTypeRef || (childRef == nodeParamsRef && nodeReturnTypeRef.isInvalid()))
    {
        TypeRef returnType = sema.typeMgr().typeVoid();
        if (nodeReturnTypeRef.isValid())
            returnType = sema.viewType(nodeReturnTypeRef).typeRef();
        sym.setReturnTypeRef(returnType);
        setIsTyped = true;
    }

    if (setIsTyped)
    {
        if (sym.returnTypeRef().isValid() && sema.typeMgr().get(sym.returnTypeRef()).isCodeBlock())
            return reportCodeTypeRestricted(sema, nodeReturnTypeRef.isValid() ? nodeReturnTypeRef : childRef, sym.returnTypeRef());

        sym.setVariadicParamFlag(sema.ctx());

        const TypeInfo ti      = TypeInfo::makeFunction(&sym, TypeInfoFlagsE::Zero);
        const TypeRef  typeRef = sema.typeMgr().addType(ti);
        sym.setTypeRef(typeRef);
        SemaPurity::computePurityFlag(sema, sym);
        sym.setTyped(sema.ctx());

        SWC_RESULT(SemaCheck::isValidSignature(sema, sym.parameters(), false));
        SWC_RESULT(SemaSpecOp::validateSymbol(sema, sym));
        if (!sym.isEmpty())
            SWC_RESULT(Match::ghosting(sema, sym));

        registerRuntimeFunctionSymbol(sema, sym);
    }

    return Result::Continue;
}

Result AstFunctionExpr::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    auto& sym = functionExprSymbol(sema, sema.curNodeRef());
    return finalizeFunctionExprSignature(sema, *this, sym);
}

Result AstClosureExpr::semaPostNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeBodyRef)
        return Result::Continue;

    auto& sym = functionExprSymbol(sema, sema.curNodeRef());
    SWC_RESULT(finalizeFunctionExprSignature(sema, *this, sym));
    return attachClosureExprRuntimeStorageIfNeeded(sema, *this, sym);
}

Result AstFunctionDecl::semaPostNode(Sema& sema)
{
    auto& sym = sema.curViewSymbol().sym()->cast<SymbolFunction>();
    if (sym.isForeign() && !sym.isEmpty())
        return SemaError::raise(sema, DiagnosticId::sema_err_foreign_cannot_have_body, sema.curNodeRef());

    sym.setSemaCompleted(sema.ctx());
    sema.compiler().registerNativeCodeFunction(&sym);
    return Result::Continue;
}

Result AstFunctionExpr::semaPostNode(Sema& sema) const
{
    auto& sym = functionExprSymbol(sema, sema.curNodeRef());
    if (!sym.isTyped())
        SWC_RESULT(finalizeFunctionExprSignature(sema, *this, sym));

    sym.setSemaCompleted(sema.ctx());
    sema.compiler().registerNativeCodeFunction(&sym);
    return Result::Continue;
}

Result AstClosureExpr::semaPostNode(Sema& sema) const
{
    auto& sym = functionExprSymbol(sema, sema.curNodeRef());
    if (!sym.isTyped())
        SWC_RESULT(finalizeFunctionExprSignature(sema, *this, sym));

    SWC_RESULT(attachClosureExprRuntimeStorageIfNeeded(sema, *this, sym));
    sym.setSemaCompleted(sema.ctx());
    sema.compiler().registerNativeCodeFunction(&sym);
    return Result::Continue;
}

Result AstFunctionParamMe::semaPreNode(Sema& sema) const
{
    const SymbolImpl* symImpl = sema.frame().currentImpl();
    if (!symImpl)
        return SemaError::raise(sema, DiagnosticId::sema_err_tok_outside_impl, sema.curNodeRef());

    const TypeRef ownerType = symImpl->isForStruct() ? symImpl->symStruct()->typeRef() : symImpl->symEnum()->typeRef();
    auto&         sym       = SemaHelpers::registerSymbol<SymbolVariable>(sema, *this, tokRef());

    TypeInfoFlags typeFlags = TypeInfoFlagsE::Zero;
    if (hasFlag(AstFunctionParamMeFlagsE::Const))
        typeFlags.add(TypeInfoFlagsE::Const);
    sym.setTypeRef(sema.typeMgr().addType(TypeInfo::makeReference(ownerType, typeFlags)));

    return Result::Continue;
}

Result AstCallExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    return semaCallExprPreNodeChildCommon(sema, *this, childRef);
}

Result AstCallExpr::semaPostNode(Sema& sema) const
{
    return semaCallExprCommon(sema, *this, false);
}

Result AstAliasCallExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    return semaCallExprPreNodeChildCommon(sema, *this, childRef);
}

Result AstAliasCallExpr::semaPostNode(Sema& sema) const
{
    return semaCallExprCommon(sema, *this, false);
}

Result AstIntrinsicCallExpr::semaPreNodeChild(Sema& sema, const AstNodeRef& childRef) const
{
    if (childRef != nodeExprRef && hasFlag(AstCallExprFlagsE::AttributeContext))
        SemaHelpers::pushConstExprRequirement(sema, childRef);
    return Result::Continue;
}

Result AstIntrinsicCallExpr::semaPostNode(Sema& sema) const
{
    SWC_RESULT(semaCallExprCommon(sema, *this, true));

    const Token& tok = sema.token(codeRef());
    if (tok.id == TokenId::IntrinsicGetContext)
        SWC_RESULT(setupIntrinsicGetContextRuntimeCall(sema, *this));
    else if (tok.id == TokenId::IntrinsicAssert)
        SWC_RESULT(setupIntrinsicAssertRuntimeCall(sema, *this));

    return Result::Continue;
}

Result AstReturnStmt::semaPostNode(Sema& sema) const
{
    TypeRef returnTypeRef = TypeRef::invalid();
    SWC_RESULT(resolveReturnTypeRef(sema, nodeExprRef, returnTypeRef));
    return validateReturnStatementValue(sema, sema.curNodeRef(), nodeExprRef, returnTypeRef);
}

Result AstDiscardExpr::semaPostNode(Sema& sema)
{
    sema.setType(sema.curNodeRef(), sema.typeMgr().typeVoid());
    return Result::Continue;
}

SWC_END_NAMESPACE();
