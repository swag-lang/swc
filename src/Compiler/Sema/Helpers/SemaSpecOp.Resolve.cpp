#include "pch.h"
#include "Compiler/Sema/Helpers/SemaSpecOp.h"
#include "Compiler/Lexer/Lexer.h"
#include "Compiler/Parser/Ast/AstNodes.h"
#include "Compiler/Parser/Parser/Parser.h"
#include "Compiler/Sema/Ast/Sema.Index.h"
#include "Compiler/Sema/Cast/Cast.h"
#include "Compiler/Sema/Constant/ConstantManager.h"
#include "Compiler/Sema/Constant/ConstantValue.h"
#include "Compiler/Sema/Core/Sema.h"
#include "Compiler/Sema/Generic/SemaGeneric.h"
#include "Compiler/Sema/Helpers/SemaCheck.h"
#include "Compiler/Sema/Helpers/SemaError.h"
#include "Compiler/Sema/Helpers/SemaHelpers.h"
#include "Compiler/Sema/Helpers/SemaInline.h"
#include "Compiler/Sema/Helpers/SemaJIT.h"
#include "Compiler/Sema/Match/Match.h"
#include "Compiler/Sema/Symbol/IdentifierManager.h"
#include "Compiler/Sema/Symbol/Symbol.Enum.h"
#include "Compiler/Sema/Symbol/Symbol.Impl.h"
#include "Compiler/Sema/Symbol/Symbol.Variable.h"
#include "Compiler/Sema/Symbol/Symbols.h"
#include "Compiler/SourceFile.h"
#include "Main/CompilerInstance.h"
#include "Support/Os/Os.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
#if SWC_DEV_MODE
    Utf8 formatSyntheticCallUnmaterializedLazyBody(const Sema& sema, const SymbolFunction& calledFn, const bool allowConstEval, const bool allowInline)
    {
        const SymbolFunction* currentFunction = sema.currentFunction();
        Utf8                  detail          = "synthetic-call-unmaterialized-lazy-body:\n";
        detail += std::format("  caller={} callee={} currentNode={} allowConstEval={} allowInline={} lazyRunning={} typed={}\n",
                              currentFunction ? currentFunction->getFullScopedName(sema.ctx()).c_str() : "",
                              calledFn.getFullScopedName(sema.ctx()).c_str(),
                              sema.curNodeRef().isValid() ? sema.curNodeRef().get() : 0,
                              allowConstEval,
                              allowInline,
                              calledFn.hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBodyRunning),
                              calledFn.isTyped());
        return detail;
    }
#endif

    TypeRef unwrapAlias(TaskContext& ctx, TypeRef typeRef)
    {
        if (typeRef.isInvalid())
            return typeRef;
        return ctx.typeMgr().get(typeRef).unwrap(ctx, typeRef, TypeExpandE::Alias);
    }

    TypeRef resolveIndexOperandTypeRef(Sema& sema, const SemaNodeView& argView)
    {
        TypeRef       indexTypeRef = argView.typeRef();
        const TypeRef aliasTypeRef = argView.type()->unwrap(sema.ctx(), argView.typeRef(), TypeExpandE::Alias);
        if (aliasTypeRef.isValid())
            indexTypeRef = aliasTypeRef;

        return indexTypeRef;
    }

    ConstantRef resolveIndexOperandConstantRef(const SemaNodeView& argView)
    {
        if (argView.cstRef().isInvalid())
            return ConstantRef::invalid();
        if (!argView.cst() || !argView.cst()->isEnumValue())
            return argView.cstRef();
        return argView.cst()->getEnumValue();
    }

    Result checkSliceSpecOpBound(Sema& sema, AstNodeRef argRef, const SemaNodeView& argView, int64_t& constIndex, bool& hasConstIndex)
    {
        if (argRef.isInvalid())
            return Result::Continue;

        const TypeRef   indexTypeRef = resolveIndexOperandTypeRef(sema, argView);
        const TypeInfo* indexType    = &sema.typeMgr().get(indexTypeRef);
        if (indexType->isReference())
            indexType = &sema.typeMgr().get(indexType->payloadTypeRef());

        if (!indexType->isInt())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_index_not_int, argRef);
            diag.addArgument(Diagnostic::ARG_TYPE, argView.typeRef());
            diag.report(sema.ctx());
            return Result::Error;
        }

        if (!argView.cst())
            return Result::Continue;

        const ConstantRef resolvedCstRef = resolveIndexOperandConstantRef(argView);
        SWC_ASSERT(resolvedCstRef.isValid());
        const auto& idxInt = sema.cstMgr().get(resolvedCstRef).getInt();
        if (!idxInt.fits64())
            return SemaError::raise(sema, DiagnosticId::sema_err_index_too_large, argRef);

        constIndex = idxInt.asI64();
        if (indexType->isIntSigned() && idxInt.isNegative())
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_index_negative, argRef);
            diag.addArgument(Diagnostic::ARG_VALUE, constIndex);
            diag.report(sema.ctx());
            return Result::Error;
        }

        hasConstIndex = true;
        return Result::Continue;
    }

    AstNodeRef makeSyntheticStringConstantArg(Sema& sema, const SourceCodeRef& codeRef, std::string_view value)
    {
        // Synthetic overload arguments bypass the parser and the regular literal
        // visitor. Seed the semantic payload immediately so Match can consume them
        // exactly like already-checked source expressions.
        const auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::StringLiteral>(codeRef.tokRef);
        nodePtr->setCodeRef(codeRef);

        const TaskContext& ctx      = sema.ctx();
        ConstantValue      constant = ConstantValue::makeString(ctx, value);
        constant.setTypeRef(sema.typeMgr().addType(TypeInfo::makeString()));
        const ConstantRef constantRef = sema.cstMgr().addConstant(ctx, constant);
        sema.setConstant(nodeRef, constantRef);
        sema.setIsValue(*nodePtr);
        return nodeRef;
    }

    std::optional<SpecOperator> binarySpecOperator(TokenId tokId)
    {
        switch (tokId)
        {
            case TokenId::SymPlus: return SpecOperator::Add;
            case TokenId::SymMinus: return SpecOperator::Sub;
            case TokenId::SymAsterisk: return SpecOperator::Mul;
            case TokenId::SymSlash: return SpecOperator::Div;
            case TokenId::SymPercent: return SpecOperator::Mod;
            case TokenId::SymAmpersand: return SpecOperator::BitAnd;
            case TokenId::SymPipe: return SpecOperator::BitOr;
            case TokenId::SymCircumflex: return SpecOperator::BitXor;
            case TokenId::SymLowerLower: return SpecOperator::Shl;
            case TokenId::SymGreaterGreater: return SpecOperator::Shr;
            default: return std::nullopt;
        }
    }

    std::optional<SpecOperator> unarySpecOperator(TokenId tokId)
    {
        switch (tokId)
        {
            case TokenId::SymBang: return SpecOperator::Not;
            case TokenId::SymPlus: return SpecOperator::Pos;
            case TokenId::SymMinus: return SpecOperator::Neg;
            case TokenId::SymTilde: return SpecOperator::BitNot;
            default: return std::nullopt;
        }
    }

    std::optional<SpecOperator> assignSpecOperator(TokenId tokId)
    {
        switch (tokId)
        {
            case TokenId::SymPlusEqual: return SpecOperator::AddAssign;
            case TokenId::SymMinusEqual: return SpecOperator::SubAssign;
            case TokenId::SymAsteriskEqual: return SpecOperator::MulAssign;
            case TokenId::SymSlashEqual: return SpecOperator::DivAssign;
            case TokenId::SymPercentEqual: return SpecOperator::ModAssign;
            case TokenId::SymAmpersandEqual: return SpecOperator::BitAndAssign;
            case TokenId::SymPipeEqual: return SpecOperator::BitOrAssign;
            case TokenId::SymCircumflexEqual: return SpecOperator::BitXorAssign;
            case TokenId::SymLowerLowerEqual: return SpecOperator::ShlAssign;
            case TokenId::SymGreaterGreaterEqual: return SpecOperator::ShrAssign;
            default: return std::nullopt;
        }
    }

    // The operator reaches the hook as a 'Swag.Operator' value, so a misspelled member is a
    // symbol error instead of a comparison that silently never matches. Resolving the runtime
    // enum can suspend, hence the Result-returning shape.
    Result makeSyntheticOperatorArg(AstNodeRef& outNodeRef, Sema& sema, const SourceCodeRef& codeRef, SpecOperator op)
    {
        outNodeRef = AstNodeRef::invalid();

        TypeRef typeRef = TypeRef::invalid();
        SWC_RESULT(sema.waitPredefined(IdentifierManager::PredefinedName::Operator, typeRef, codeRef));

        const auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::IntegerLiteral>(codeRef.tokRef);
        nodePtr->setCodeRef(codeRef);

        const TaskContext&  ctx          = sema.ctx();
        const ConstantRef   valueCstRef  = sema.cstMgr().addS32(ctx, static_cast<int32_t>(op));
        const ConstantValue enumValue    = ConstantValue::makeEnumValue(ctx, valueCstRef, typeRef);
        const ConstantRef   enumValueRef = sema.cstMgr().addConstant(ctx, enumValue);
        sema.setType(nodeRef, typeRef);
        sema.setConstant(nodeRef, enumValueRef);
        sema.setIsValue(*nodePtr);

        outNodeRef = nodeRef;
        return Result::Continue;
    }

    AstNodeRef makeSyntheticBoolConstantArg(Sema& sema, const SourceCodeRef& codeRef, bool value)
    {
        // Same contract as makeSyntheticStringConstantArg: this node is created
        // after sema has already reached the special-op path, so no later literal
        // pass will come back to fill type/constant/value flags.
        const auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::BoolLiteral>(codeRef.tokRef);
        nodePtr->setCodeRef(codeRef);
        sema.setType(nodeRef, sema.typeMgr().typeBool());
        sema.setConstant(nodeRef, sema.cstMgr().cstBool(value));
        sema.setIsValue(*nodePtr);
        return nodeRef;
    }

    AstNodeRef makeSyntheticU64Arg(Sema& sema, const SourceCodeRef& codeRef, std::optional<uint64_t> value = std::nullopt)
    {
        // U64 placeholders are used both for known bounds and for "runtime value"
        // positions. The type is always fixed; the constant is optional.
        const auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::IntegerLiteral>(codeRef.tokRef);
        nodePtr->setCodeRef(codeRef);
        sema.setType(nodeRef, sema.typeMgr().typeU64());

        if (value.has_value())
        {
            const TaskContext&  ctx      = sema.ctx();
            const ConstantValue constant = ConstantValue::makeIntSized<uint64_t>(ctx, *value);
            sema.setConstant(nodeRef, sema.cstMgr().addConstant(ctx, constant));
        }

        sema.setIsValue(*nodePtr);
        return nodeRef;
    }

    AstNodeRef makeForeachVisitBodyRef(Sema& sema, const AstForeachStmt& node)
    {
        if (node.nodeWhereRef.isInvalid())
            return node.nodeBodyRef;

        // 'foreach where' is passed to opVisit as a code block. Represent the
        // filter as an if-statement around the user body so the visit function sees
        // the same control-flow shape the source would have produced.
        auto [ifRef, ifPtr]     = sema.ast().makeNode<AstNodeId::IfStmt>(node.tokRef());
        ifPtr->nodeConditionRef = node.nodeWhereRef;
        ifPtr->nodeIfBlockRef   = node.nodeBodyRef;
        ifPtr->nodeElseBlockRef = AstNodeRef::invalid();
        ifPtr->setCodeRef(node.codeRef());
        return ifRef;
    }

    AstNodeRef makeSyntheticCodeBlockArg(Sema& sema, const AstForeachStmt& node)
    {
        auto [nodeRef, nodePtr] = sema.ast().makeNode<AstNodeId::CompilerCodeBlock>(node.tokRef());
        nodePtr->setCodeRef(node.codeRef());
        nodePtr->nodeBodyRef    = makeForeachVisitBodyRef(sema, node);
        nodePtr->payloadTypeRef = sema.typeMgr().typeVoid();
        return nodeRef;
    }

    AstNodeRef unwrapVisitFunctionDeclRef(const Ast& ast, AstNodeRef childRef)
    {
        const AstNode& childNode = ast.node(childRef);
        if (const auto* accessNode = childNode.safeCast<AstAccessModifier>())
            return accessNode->nodeWhatRef;
        return childRef;
    }

    bool collectImplPendingChildren(Sema& sema, const SymbolImpl& symImpl, SmallVector<AstNodeRef>& outChildren, const Ast*& outAst)
    {
        outChildren.clear();
        outAst = nullptr;

        // An impl can be represented in three places while sema is still moving:
        // the instantiated generic block, the current worker AST, or the original
        // source-file AST. Return the matching AST together with its child refs.
        const AstNodeRef genericBlockRef = symImpl.genericBlockRef();
        if (genericBlockRef.isValid() && sema.ast().hasNode(genericBlockRef))
        {
            outAst = &sema.ast();
            sema.node(genericBlockRef).collectChildrenFromAst(outChildren, sema.ast());
            return true;
        }

        const auto* implDecl = symImpl.decl() ? symImpl.decl()->safeCast<AstImpl>() : nullptr;
        if (!implDecl)
            return false;

        if (sema.ast().tryFindNodeRef(implDecl).isValid())
        {
            outAst = &sema.ast();
            outAst->appendNodes(outChildren, implDecl->spanChildrenRef);
            return true;
        }

        const SourceFile* sourceFile = sema.srcView(implDecl->srcViewRef()).file();
        if (!sourceFile)
            return false;

        outAst = &sourceFile->ast();
        outAst->appendNodes(outChildren, implDecl->spanChildrenRef);
        return true;
    }

    bool implDeclContainsFunctionId(Sema& sema, const SymbolImpl& symImpl, IdentifierRef idRef)
    {
        const Ast*              implAst = nullptr;
        SmallVector<AstNodeRef> children;
        if (!collectImplPendingChildren(sema, symImpl, children, implAst))
            return false;
        for (const AstNodeRef childRef : children)
        {
            const AstNodeRef declRef  = unwrapVisitFunctionDeclRef(*implAst, childRef);
            const auto*      funcDecl = implAst->node(declRef).safeCast<AstFunctionDecl>();
            if (!funcDecl || funcDecl->tokNameRef.isInvalid())
                continue;

            const IdentifierRef childId = sema.idMgr().addIdentifier(sema.ctx(), SourceCodeRef{funcDecl->srcViewRef(), funcDecl->tokNameRef});
            if (childId == idRef)
                return true;
        }

        return false;
    }

    Result waitVisitSpecOpRegistration(Sema& sema, const SymbolStruct& ownerStruct, IdentifierRef idRef, const SourceCodeRef& codeRef)
    {
        if (idRef.isInvalid())
            return Result::Continue;

        bool foundDecl       = false;
        bool foundRegistered = false;
        for (const SymbolImpl* symImpl : ownerStruct.impls())
        {
            if (!symImpl || symImpl->isIgnored())
                continue;
            if (!implDeclContainsFunctionId(sema, *symImpl, idRef))
                continue;

            foundDecl = true;
            if (symImpl->findFunction(idRef))
            {
                foundRegistered = true;
                break;
            }
        }

        if (foundDecl && !foundRegistered)
            return sema.waitIdentifier(idRef, codeRef);
        return Result::Continue;
    }

    Result waitPendingVisitSpecOp(Sema& sema, const SymbolStruct& ownerStruct, const AstForeachStmt& node)
    {
        const IdentifierRef opVisitId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpVisit);
        return waitVisitSpecOpRegistration(sema, ownerStruct, opVisitId, node.codeRef());
    }

    const SymbolStruct* structSpecOpOwner(Sema& sema, const SemaNodeView& view)
    {
        if (!view.type())
            return nullptr;

        // A reference or a non-null single-value pointer to a container is looked through,
        // like member access: the operator receiver is the pointed-to object.
        TypeRef         unwrappedTypeRef = view.typeRef();
        const TypeInfo& valueType        = sema.typeMgr().get(unwrappedTypeRef);
        if (valueType.isReference() || (valueType.isValuePointer() && !valueType.isNullable()))
            unwrappedTypeRef = unwrapAlias(sema.ctx(), valueType.payloadTypeRef());
        else
            unwrappedTypeRef = unwrapAlias(sema.ctx(), unwrappedTypeRef);
        if (!unwrappedTypeRef.isValid())
            unwrappedTypeRef = view.typeRef();

        const TypeInfo& type = sema.typeMgr().get(unwrappedTypeRef);
        if (!type.isStruct())
            return nullptr;

        return &type.payloadSymStruct();
    }

    // The receiver's mutability for operator selection: a pointer or reference receiver
    // takes it from the pointee.
    bool indexReceiverIsConst(Sema& sema, const SemaNodeView& view)
    {
        if (!view.type())
            return false;
        if (view.type()->isConst())
            return true;
        if (view.type()->isReference() || view.type()->isAnyPointer())
            return sema.typeMgr().get(view.type()->payloadTypeRef()).isConst();
        return false;
    }

    bool canExplicitlySpecializeSpecOp(Sema& sema, const SymbolFunction& symFunc, std::span<const AstNodeRef> genericArgNodes)
    {
        if (!symFunc.isGenericRoot() || genericArgNodes.empty())
            return false;

        const auto* decl = symFunc.decl() ? symFunc.decl()->safeCast<AstFunctionDecl>() : nullptr;
        if (!decl || !decl->spanGenericParamsRef.isValid())
            return false;

        SmallVector<SemaGeneric::GenericParamDesc> params;
        SemaGeneric::collectGenericParams(sema, *decl, decl->spanGenericParamsRef, params);
        if (genericArgNodes.size() > params.size())
            return false;

        for (size_t i = 0; i < genericArgNodes.size(); ++i)
        {
            if (params[i].kind != SemaGeneric::GenericParamKind::Value)
                return false;
        }

        return true;
    }

    const Symbol* currentSpecOpWaiterSymbol(Sema& sema)
    {
        const AstNodeRef   rootRef  = sema.visit().root();
        const SemaNodeView rootView = sema.viewSymbol(rootRef);
        if (rootView.hasSymbol())
            return rootView.sym();
        return sema.topSymMap();
    }

    Result waitSpecOpCandidateReady(Sema& sema, const SymbolFunction& symFunc)
    {
        if (!symFunc.isGenericRoot())
        {
            SWC_RESULT(sema.waitTyped(&symFunc, symFunc.codeRef()));
            return Result::Continue;
        }

        // Literal operator overloads are published during pre-decl and can be specialized before
        // declaration finishes, which silently drops the candidate. Generic `opVisit` can also be
        // queried from `foreach` before the declaration is fully ready in some build modes, so make
        // both cases wait for declaration completion unless we are currently resolving that same
        // operator overload.
        if (symFunc.specOpKind() != SpecOpKind::OpSetLiteral &&
            symFunc.specOpKind() != SpecOpKind::OpVisit)
            return Result::Continue;
        if (currentSpecOpWaiterSymbol(sema) == &symFunc)
            return Result::Continue;

        SWC_RESULT(sema.waitDeclared(&symFunc, symFunc.codeRef()));
        return Result::Continue;
    }

    Result collectDeclaredSpecOps(Sema& sema, const SymbolStruct& ownerStruct, IdentifierRef idRef, std::span<const AstNodeRef> genericArgNodes, SmallVector<Symbol*>& outCandidates, bool requireDeclaredGenericRoots)
    {
        for (const SymbolImpl* symImpl : ownerStruct.impls())
        {
            if (!symImpl || symImpl->isIgnored())
                continue;

            for (SymbolFunction* symFunc : symImpl->specOps())
            {
                if (!symFunc || symFunc->idRef() != idRef)
                    continue;

                if (requireDeclaredGenericRoots && symFunc->isGenericRoot() && currentSpecOpWaiterSymbol(sema) != symFunc)
                    SWC_RESULT(sema.waitDeclared(symFunc, symFunc->codeRef()));
                else
                    SWC_RESULT(waitSpecOpCandidateReady(sema, *symFunc));

                if (!canExplicitlySpecializeSpecOp(sema, *symFunc, genericArgNodes))
                {
                    outCandidates.push_back(symFunc);
                    continue;
                }

                SymbolFunction* specialized = nullptr;
                CastFailure     whereFailure;
                const Result    specResult = SemaGeneric::instantiateFunctionExplicit(sema, *symFunc, genericArgNodes, specialized, &whereFailure);
                if (specResult == Result::Pause)
                    return Result::Pause;
                if (specResult != Result::Continue)
                    continue;
                if (whereFailure.diagId != DiagnosticId::None)
                {
                    if (whereFailure.diagId == DiagnosticId::sema_err_function_where_failed)
                        continue;
                    return SemaGeneric::instantiateFunctionExplicit(sema, *symFunc, genericArgNodes, specialized);
                }
                if (specialized)
                {
                    SWC_RESULT(sema.waitSemaCompleted(specialized, specialized->codeRef()));
                    SWC_RESULT(SemaSpecOp::validateSymbol(sema, *specialized));
                    outCandidates.push_back(specialized);
                }
            }
        }

        return Result::Continue;
    }

    // Value using-fields extend the owner's operator surface, while pointer using-fields do not
    // own the target storage and are skipped.
    Result collectUsingTargets(Sema& sema, const SymbolStruct& ownerStruct, SmallVector<const SymbolStruct*>& outTargets)
    {
        for (const Symbol* field : ownerStruct.fields())
        {
            const auto& symVar = field->cast<SymbolVariable>();
            if (!symVar.isUsingField())
                continue;

            bool                isPointer = false;
            const SymbolStruct* target    = symVar.usingTargetStruct(sema.ctx(), isPointer);
            if (!target || isPointer)
                continue;

            SWC_RESULT(sema.waitSemaCompleted(target, sema.curNode().codeRef()));
            outTargets.push_back(target);
        }

        return Result::Continue;
    }

    // Comparison is the one operator family an embedded struct must not compete for. Every other
    // family widens what the embedder can do — an embedded 'opCast' or 'opBinary' adds a target
    // type or an operand type the embedder does not handle itself — but two structs comparing
    // equal is a question only one of them can answer, so an embedded 'opEquals' taking over for
    // the whole embedder is never what was meant. It ties with the embedder's own, which is
    // reported as an ambiguity rather than resolved.
    bool specOpHidesUsingCandidates(Sema& sema, IdentifierRef idRef)
    {
        return idRef == sema.idMgr().predefined(IdentifierManager::PredefinedName::OpEquals) ||
               idRef == sema.idMgr().predefined(IdentifierManager::PredefinedName::OpCompare);
    }

    // The type a relational operand compares as: a reference compares as what it refers to, and an
    // alias as what it names.
    TypeRef relationalOperandTypeRef(Sema& sema, TypeRef typeRef)
    {
        if (!typeRef.isValid())
            return typeRef;

        const TypeInfo& valueType = sema.typeMgr().get(typeRef);
        if (valueType.isReference())
            typeRef = valueType.payloadTypeRef();

        const TypeRef unwrappedTypeRef = unwrapAlias(sema.ctx(), typeRef);
        return unwrappedTypeRef.isValid() ? unwrappedTypeRef : typeRef;
    }

    // Whether one of the collected operators can actually take the right operand. Asking the
    // matcher is what keeps a comparison promoted through a 'using' member — which no signature
    // test would recognize as taking the embedder — from being mistaken for no answer at all.
    Result hasViableRelationalCandidate(bool& outViable, Sema& sema, const AstRelationalExpr& node, std::span<Symbol* const> candidates)
    {
        outViable = false;

        SmallVector<AstNodeRef> args;
        args.push_back(node.nodeRightRef);

        const SemaNodeView            calleeView(sema, sema.curNodeRef(), SemaNodeViewPartE::Node);
        Match::FunctionCandidateProbe probe;
        SWC_RESULT(Match::probeFunctionCandidates(sema, calleeView, candidates, args.span(), node.nodeLeftRef, probe, true));
        outViable = probe.matched && probe.fn != nullptr;
        return Result::Continue;
    }

    Result collectSpecOpCandidates(Sema& sema, const SymbolStruct& ownerStruct, IdentifierRef idRef, std::span<const AstNodeRef> genericArgNodes, SmallVector<Symbol*>& outCandidates, bool requireDeclaredGenericRoots = false)
    {
        outCandidates.clear();

        // The search widens one using-level at a time, so a comparison can stop as soon as a level
        // answers instead of merging every level into one overload set.
        const bool                              stopAtAnsweringLevel = specOpHidesUsingCandidates(sema, idRef);
        std::unordered_set<const SymbolStruct*> visited{&ownerStruct};
        SmallVector<const SymbolStruct*>        level{&ownerStruct};

        while (!level.empty())
        {
            SmallVector<const SymbolStruct*> nextLevel;
            for (const SymbolStruct* current : level)
            {
                SWC_RESULT(collectDeclaredSpecOps(sema, *current, idRef, genericArgNodes, outCandidates, requireDeclaredGenericRoots));
                SWC_RESULT(collectUsingTargets(sema, *current, nextLevel));
            }

            if (stopAtAnsweringLevel && !outCandidates.empty())
                return Result::Continue;

            level.clear();
            for (const SymbolStruct* target : nextLevel)
            {
                if (visited.insert(target).second)
                    level.push_back(target);
            }
        }

        return Result::Continue;
    }

    // Candidates for an assignment written on a struct: 'opSet'/'opAssign' for a plain receiver,
    // 'opIndexSet'/'opIndexAssign' for an indexed one. A compound assignment carries the operator
    // it stands for as a synthetic generic argument.
    Result collectAssignSpecOpCandidates(Sema& sema, const SymbolStruct& ownerStruct, const SourceCodeRef& codeRef, TokenId tokId, bool indexed, SmallVector<Symbol*>& outCandidates)
    {
        outCandidates.clear();
        if (!Token::isOpAssign(tokId))
            return Result::Continue;

        using Name                     = IdentifierManager::PredefinedName;
        const bool          isSimple   = tokId == TokenId::SymEqual;
        const Name          setName    = indexed ? Name::OpIndexSet : Name::OpSet;
        const Name          assignName = indexed ? Name::OpIndexAssign : Name::OpAssign;
        const IdentifierRef opId       = sema.idMgr().predefined(isSimple ? setName : assignName);

        if (isSimple)
            return collectSpecOpCandidates(sema, ownerStruct, opId, std::span<const AstNodeRef>{}, outCandidates);

        const std::optional<SpecOperator> op = assignSpecOperator(tokId);
        SWC_ASSERT(op.has_value());
        AstNodeRef genericArg = AstNodeRef::invalid();
        SWC_RESULT(makeSyntheticOperatorArg(genericArg, sema, codeRef, *op));
        if (genericArg.isInvalid())
            return collectSpecOpCandidates(sema, ownerStruct, opId, std::span<const AstNodeRef>{}, outCandidates);

        return collectSpecOpCandidates(sema, ownerStruct, opId, std::span{&genericArg, 1}, outCandidates);
    }

    bool canConsumeLambdaBinding(Sema& sema, AstNodeRef nodeRef)
    {
        if (nodeRef.isInvalid())
            return false;

        const AstNode& node = sema.node(nodeRef);
        switch (node.id())
        {
            case AstNodeId::FunctionExpr:
            case AstNodeId::ClosureExpr:
                return true;

            case AstNodeId::NamedArgument:
                return canConsumeLambdaBinding(sema, node.cast<AstNamedArgument>().nodeArgRef);

            case AstNodeId::ParenExpr:
                return canConsumeLambdaBinding(sema, node.cast<AstParenExpr>().nodeExprRef);

            default:
                return false;
        }
    }

    const SymbolVariable* assignSpecOpValueParam(const SymbolFunction& fn, AstNodeRef receiverRef)
    {
        const auto& params = fn.parameters();
        const auto  index  = receiverRef.isValid() ? 1u : 0u;
        if (index >= params.size())
            return nullptr;
        return params[index];
    }

    void splitMutableReceiverCandidates(Sema& sema, std::span<Symbol* const> inCandidates, SmallVector<Symbol*>& outMutableCandidates, SmallVector<Symbol*>& outConstCandidates)
    {
        outMutableCandidates.clear();
        outConstCandidates.clear();

        for (Symbol* sym : inCandidates)
        {
            auto* symFunc = sym ? sym->safeCast<SymbolFunction>() : nullptr;
            if (!symFunc || symFunc->parameters().empty())
            {
                outConstCandidates.push_back(sym);
                continue;
            }

            const SymbolVariable* receiver = symFunc->parameters().front();
            if (receiver && !sema.typeMgr().get(receiver->typeRef()).isConst())
                outMutableCandidates.push_back(sym);
            else
                outConstCandidates.push_back(sym);
        }
    }

    SymbolFunction* selectReceiverOnlyCandidate(Sema& sema, std::span<Symbol* const> candidates, bool receiverIsConst)
    {
        SmallVector<Symbol*> mutableCandidates;
        SmallVector<Symbol*> constCandidates;
        splitMutableReceiverCandidates(sema, candidates, mutableCandidates, constCandidates);

        const auto preferredCandidates = receiverIsConst || mutableCandidates.empty() ? constCandidates.span() : mutableCandidates.span();
        for (Symbol* sym : preferredCandidates)
        {
            if (auto* symFunc = sym ? sym->safeCast<SymbolFunction>() : nullptr)
                return symFunc;
        }

        if (!receiverIsConst)
        {
            for (Symbol* sym : constCandidates)
            {
                if (auto* symFunc = sym ? sym->safeCast<SymbolFunction>() : nullptr)
                    return symFunc;
            }
        }

        return nullptr;
    }

    void appendIndexArgs(const Ast& ast, const AstIndexListExpr& node, SmallVector<AstNodeRef>& outArgs)
    {
        ast.appendNodes(outArgs, node.spanChildrenRef);
    }

    AstNodeRef normalizeIndexSpecOpArgRef(Sema& sema, AstNodeRef argRef)
    {
        if (argRef.isInvalid())
            return AstNodeRef::invalid();

        const SemaNodeView argView(sema, argRef, SemaNodeViewPartE::Type);
        if (!argView.type())
            return argRef;

        const TypeRef   argTypeRef = sema.typeMgr().unwrapAliasEnum(sema.ctx(), argView.typeRef());
        const TypeInfo& argType    = sema.typeMgr().get(argTypeRef.isValid() ? argTypeRef : argView.typeRef());
        if (!argType.isReference())
            return argRef;

        return Cast::createCastNode(sema, argType.payloadTypeRef(), argRef);
    }

    bool collectIndexAccessArgs(Sema& sema, AstNodeRef& outIndexedExprRef, SmallVector<AstNodeRef>& outArgs, AstNodeRef indexNodeRef)
    {
        outIndexedExprRef = AstNodeRef::invalid();
        outArgs.clear();
        if (indexNodeRef.isInvalid())
            return false;

        const AstNode& node = sema.node(indexNodeRef);
        if (node.is(AstNodeId::IndexExpr))
        {
            const auto& indexNode = node.cast<AstIndexExpr>();
            if (sema.node(indexNode.nodeArgRef).is(AstNodeId::RangeExpr))
                return false;
            outIndexedExprRef = indexNode.nodeExprRef;
            outArgs.push_back(indexNode.nodeArgRef);
            return true;
        }

        if (node.is(AstNodeId::IndexListExpr))
        {
            const auto& indexNode = node.cast<AstIndexListExpr>();
            outIndexedExprRef     = indexNode.nodeExprRef;
            appendIndexArgs(sema.ast(), indexNode, outArgs);
            for (const AstNodeRef argRef : outArgs)
            {
                if (sema.node(argRef).is(AstNodeId::RangeExpr))
                    return false;
            }
            return !outArgs.empty();
        }

        return false;
    }

    Result matchSyntheticCall(Sema& sema, std::span<Symbol* const> candidates, std::span<AstNodeRef> args, AstNodeRef ufcsArg, bool allowNoMatch, SmallVector<ResolvedCallArgument>& outResolvedArgs, bool& outMatched)
    {
        outResolvedArgs.clear();
        outMatched = false;

        const SemaNodeView calleeView(sema, sema.curNodeRef(), SemaNodeViewPartE::Node);
        if (allowNoMatch)
        {
            const bool savedSilent = sema.ctx().silentDiagnostic();
            sema.ctx().setSilentDiagnostic(true);
            const Result matchResult = Match::resolveFunctionCandidates(sema, calleeView, candidates, args, ufcsArg, &outResolvedArgs);
            sema.ctx().setSilentDiagnostic(savedSilent);
            if (matchResult == Result::Pause)
                return Result::Pause;
            if (matchResult != Result::Continue)
                return Result::Continue;
        }
        else
        {
            SWC_RESULT(Match::resolveFunctionCandidates(sema, calleeView, candidates, args, ufcsArg, &outResolvedArgs));
        }

        outMatched = true;
        return Result::Continue;
    }

    Result canAssignThroughIndexLValue(Sema& sema, const AstAssignStmt& node, AstNodeRef leftExprRef, const SemaNodeView& leftView, bool& outCanAssign)
    {
        outCanAssign = false;
        if (!leftView.type() || leftView.type()->isConst())
            return Result::Continue;

        const bool savedSilent = sema.ctx().silentDiagnostic();
        sema.ctx().setSilentDiagnostic(true);

        const Result assignableResult = SemaCheck::isAssignable(sema, leftExprRef, leftView);
        if (assignableResult == Result::Pause)
        {
            sema.ctx().setSilentDiagnostic(savedSilent);
            return Result::Pause;
        }

        if (assignableResult != Result::Continue)
        {
            sema.ctx().setSilentDiagnostic(savedSilent);
            return Result::Continue;
        }

        const SemaNodeView rightView = sema.viewType(node.nodeRightRef);
        if (!rightView.type())
        {
            sema.ctx().setSilentDiagnostic(savedSilent);
            return Result::Continue;
        }

        CastRequest castRequest(CastKind::Assignment);
        castRequest.errorNodeRef = node.nodeRightRef;
        const Result castResult  = Cast::castAllowed(sema, castRequest, rightView.typeRef(), leftView.typeRef());
        sema.ctx().setSilentDiagnostic(savedSilent);
        if (castResult == Result::Pause)
            return Result::Pause;

        outCanAssign = castResult == Result::Continue;
        return Result::Continue;
    }

    Result probeIndexAssignSpecOp(Sema& sema, const AstAssignStmt& node, AstNodeRef indexedExprRef, std::span<const AstNodeRef> indexArgRefs, std::span<Symbol* const> candidates, SymbolFunction*& outCalledFn, bool& outMatched)
    {
        outCalledFn = nullptr;
        outMatched  = false;

        SmallVector<AstNodeRef> args;
        args.reserve(indexArgRefs.size() + 1);
        for (const AstNodeRef indexArgRef : indexArgRefs)
            args.push_back(normalizeIndexSpecOpArgRef(sema, indexArgRef));
        args.push_back(node.nodeRightRef);

        SmallVector<ResolvedCallArgument> resolvedArgs;
        SWC_RESULT(matchSyntheticCall(sema, candidates, args.span(), indexedExprRef, true, resolvedArgs, outMatched));
        if (!outMatched)
            return Result::Continue;

        const auto symView = sema.curViewSymbol();
        SWC_ASSERT(symView.sym() && symView.sym()->isFunction());
        outCalledFn = &symView.sym()->cast<SymbolFunction>();
        return Result::Continue;
    }

    Result collectVisitSpecOpCandidates(Sema& sema, const SymbolStruct& ownerStruct, std::span<const AstNodeRef> genericArgNodes, SmallVector<Symbol*>& outCandidates)
    {
        outCandidates.clear();

        const IdentifierRef opVisitId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpVisit);
        return collectSpecOpCandidates(sema, ownerStruct, opVisitId, genericArgNodes, outCandidates);
    }

    bool foreachRequestsByAddress(const Sema& sema, const AstForeachStmt& node)
    {
        if (node.hasFlag(AstForeachStmtFlagsE::ByAddress))
            return true;

        SmallVector<TokenRef> foreachNames;
        sema.ast().appendTokens(foreachNames, node.spanNamesRef);
        if (foreachNames.empty())
            return false;

        const SourceView& srcView = sema.srcView(node.srcViewRef());
        for (uint32_t tokIndex = node.tokRef().get(); tokIndex < foreachNames.front().get(); ++tokIndex)
        {
            if (srcView.token(TokenRef{tokIndex}).id == TokenId::SymAmpersand)
                return true;
        }

        const SourceCodeRange codeRange = node.codeRangeWithChildren(sema.ctx(), sema.ast());
        if (codeRange.srcView && codeRange.len)
        {
            const std::string_view code   = codeRange.srcView->codeView(codeRange.offset, codeRange.len);
            const size_t           inPos  = code.find(" in ");
            const size_t           ampPos = code.find('&');
            if (ampPos != std::string_view::npos && (inPos == std::string_view::npos || ampPos < inPos))
                return true;
        }

        return false;
    }

    Result resolveSyntheticCall(Sema& sema, const AstNode& node, std::span<Symbol* const> candidates, std::span<AstNodeRef> args, AstNodeRef ufcsArg, bool allowNoMatch = false, bool* outMatched = nullptr, bool allowConstEval = true, bool allowInline = true, SymbolFunction** outCalledFn = nullptr)
    {
        SmallVector<ResolvedCallArgument> resolvedArgs;
        bool                              matched = false;
        SWC_RESULT(matchSyntheticCall(sema, candidates, args, ufcsArg, allowNoMatch, resolvedArgs, matched));
        if (!matched)
            return Result::Continue;
        if (outMatched)
            *outMatched = true;
        sema.setResolvedCallArguments(sema.curNodeRef(), resolvedArgs);

        auto& calledFn = sema.curViewSymbol().sym()->cast<SymbolFunction>();
        if (outCalledFn)
            *outCalledFn = &calledFn;
        sema.setType(sema.curNodeRef(), calledFn.returnTypeRef());
        sema.setIsValue(sema.curNode());
        sema.unsetIsLValue(sema.curNodeRef());
        SemaHelpers::addCurrentFunctionCallDependency(sema, &calledFn);

#if SWC_DEV_MODE
        if (calledFn.hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBody) && !calledFn.isSemaCompleted())
        {
            const Utf8 detail = formatSyntheticCallUnmaterializedLazyBody(sema, calledFn, allowConstEval, allowInline);
            swcAssertDetail("!calledFn.hasExtraFlag(SymbolFunctionFlagsE::LazyGenericBody) || calledFn.isSemaCompleted()", __FILE__, __LINE__, detail.view());
        }
#endif

        if (allowConstEval)
        {
            SWC_RESULT(SemaJIT::tryRunConstCall(sema, calledFn, sema.curNodeRef(), resolvedArgs.span()));
            if (sema.viewConstant(sema.curNodeRef()).hasConstant())
                return Result::Continue;
        }

        if (allowInline)
            SWC_RESULT(SemaInline::tryInlineCall(sema, sema.curNodeRef(), calledFn, args, ufcsArg));
        SWC_RESULT(SemaHelpers::attachIndirectReturnRuntimeStorageIfNeeded(sema, node, calledFn, "__spec_op_runtime_storage"));
        return Result::Continue;
    }

    void applyIndexReadSpecOpResult(Sema& sema, AstNodeRef indexExprRef, SymbolFunction& calledFn)
    {
        auto* payload     = sema.compiler().allocate<IndexSpecOpSemaPayload>();
        payload->calledFn = &calledFn;
        sema.setSemaPayload(indexExprRef, payload);

        const TypeRef   returnTypeRef = calledFn.returnTypeRef();
        const TypeInfo& returnType    = sema.typeMgr().get(returnTypeRef);

        // 'opIndexPtr' hands back the element's address, so the indexed expression is an
        // lvalue of the pointee type, exactly like a reference-returning 'opIndex'.
        if (returnType.isReference() || calledFn.specOpKind() == SpecOpKind::OpIndexPtr)
        {
            sema.setType(indexExprRef, returnType.payloadTypeRef());
            sema.setIsValue(indexExprRef);
            sema.setIsLValue(indexExprRef);
        }
        else
        {
            sema.setType(indexExprRef, returnTypeRef);
            sema.setIsValue(indexExprRef);
            sema.unsetIsLValue(indexExprRef);
        }
    }

    Result tryResolveReceiverOnlySpecOp(Sema& sema, SymbolFunction*& outCalledFn, bool& outHandled, AstNodeRef exprRef, IdentifierRef opId, bool allowConstEval)
    {
        outCalledFn = nullptr;
        outHandled  = false;

        const SemaNodeView  exprView(sema, exprRef, SemaNodeViewPartE::Type);
        const SymbolStruct* ownerStruct = structSpecOpOwner(sema, exprView);
        if (!ownerStruct)
            return Result::Continue;

        SWC_RESULT(sema.waitSemaCompleted(ownerStruct, sema.node(exprRef).codeRef()));

        SmallVector<Symbol*> candidates;
        SWC_RESULT(collectSpecOpCandidates(sema, *ownerStruct, opId, std::span<const AstNodeRef>{}, candidates));
        if (candidates.empty())
            return Result::Continue;

        SmallVector<AstNodeRef> args;
        bool                    matched = false;
        SWC_RESULT(resolveSyntheticCall(sema, sema.node(sema.curNodeRef()), candidates.span(), args.span(), exprRef, true, &matched, allowConstEval, false));
        if (!matched)
        {
            auto* calledFn = candidates.size() == 1 ? candidates.front()->safeCast<SymbolFunction>() : nullptr;
            if (!calledFn)
                return Result::Continue;

            SmallVector<ResolvedCallArgument> resolvedArgs;
            ResolvedCallArgument              resolvedArg;
            resolvedArg.argRef = exprRef;

            const SymbolVariable* receiver = calledFn->parameters().empty() ? nullptr : calledFn->parameters().front();
            if (receiver && sema.typeMgr().get(receiver->typeRef()).isReference())
            {
                resolvedArg.bindsReferenceToValue = true;

                bool               needsRuntimeStorage = !sema.isGlobalScope();
                const SemaNodeView operandView         = sema.viewNodeTypeSymbol(exprRef);
                if (operandView.sym() &&
                    operandView.sym()->isVariable() &&
                    operandView.type() &&
                    !operandView.type()->isReference() &&
                    !operandView.type()->isAnyPointer())
                {
                    auto& symVar = operandView.sym()->cast<SymbolVariable>();
                    if (symVar.hasExtraFlag(SymbolVariableFlagsE::Parameter))
                    {
                        symVar.addExtraFlag(SymbolVariableFlagsE::NeedsAddressableStorage);
                        needsRuntimeStorage = false;
                    }
                }

                if (needsRuntimeStorage)
                {
                    const TypeRef storageTypeRef = sema.typeMgr().get(receiver->typeRef()).payloadTypeRef();
                    SWC_RESULT(SemaHelpers::attachRuntimeStorageIfNeeded(sema, exprRef, sema.node(exprRef), storageTypeRef, "__call_arg_ref_storage"));
                }
            }

            if (receiver)
                SWC_RESULT(SemaHelpers::attachBorrowedAggregateArgumentRuntimeStorageIfNeeded(sema, *calledFn, receiver->typeRef(), exprRef));

            resolvedArgs.push_back(resolvedArg);
            sema.setResolvedCallArguments(sema.curNodeRef(), resolvedArgs);
            sema.setSymbol(sema.curNodeRef(), calledFn);
            sema.setType(sema.curNodeRef(), calledFn->returnTypeRef());
            sema.setIsValue(sema.curNode());
            sema.unsetIsLValue(sema.curNodeRef());

            SemaHelpers::addCurrentFunctionCallDependency(sema, calledFn);
            if (allowConstEval)
            {
                SWC_RESULT(SemaJIT::tryRunConstCall(sema, *calledFn, sema.curNodeRef(), resolvedArgs.span()));
            }

            if (!allowConstEval || !sema.viewConstant(sema.curNodeRef()).hasConstant())
            {
                SWC_UNUSED(args);
                SWC_RESULT(SemaHelpers::attachIndirectReturnRuntimeStorageIfNeeded(sema, sema.node(sema.curNodeRef()), *calledFn, "__spec_op_runtime_storage"));
            }

            outCalledFn = calledFn;
            outHandled  = true;
            return Result::Continue;
        }

        const SemaNodeView currentSymView = sema.curViewSymbol();
        if (currentSymView.sym() && currentSymView.sym()->isFunction())
            outCalledFn = &currentSymView.sym()->cast<SymbolFunction>();
        else if (candidates.size() == 1)
            outCalledFn = candidates.front()->safeCast<SymbolFunction>();

        if (outCalledFn && !sema.viewType(sema.curNodeRef()).typeRef().isValid() && outCalledFn->returnTypeRef().isValid())
        {
            sema.setType(sema.curNodeRef(), outCalledFn->returnTypeRef());
            sema.setIsValue(sema.curNode());
            sema.unsetIsLValue(sema.curNodeRef());
        }

        outHandled = true;
        return Result::Continue;
    }

}

Result SemaSpecOp::collectSetCandidates(Sema& sema, const SymbolStruct& ownerStruct, const SourceCodeRef& codeRef, AstNodeRef valueRef, SmallVector<Symbol*>& outCandidates)
{
    UserDefinedLiteralSuffixInfo suffixInfo;
    if (!Cast::resolveUserDefinedLiteralSuffix(sema, valueRef, suffixInfo))
        return collectAssignSpecOpCandidates(sema, ownerStruct, codeRef, TokenId::SymEqual, false, outCandidates);

    const IdentifierRef opSetLiteralId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpSetLiteral);
    const AstNodeRef    genericArg     = makeSyntheticStringConstantArg(sema, codeRef, suffixInfo.suffix);
    return collectSpecOpCandidates(sema, ownerStruct, opSetLiteralId, std::span{&genericArg, 1}, outCandidates);
}

Result SemaSpecOp::resolveAssignLambdaBindingType(Sema& sema, const AstAssignStmt& node, const SemaNodeView& leftView, TypeRef& outBindingTypeRef)
{
    outBindingTypeRef = TypeRef::invalid();
    if (!canConsumeLambdaBinding(sema, node.nodeRightRef))
        return Result::Continue;

    const Token& tok = sema.token(node.codeRef());
    if (!Token::isOpAssign(tok.id))
        return Result::Continue;

    const SymbolStruct* ownerStruct = structSpecOpOwner(sema, leftView);
    if (!ownerStruct)
        return Result::Continue;

    SWC_RESULT(sema.waitSemaCompleted(ownerStruct, node.codeRef()));

    SmallVector<Symbol*> candidates;
    if (tok.id == TokenId::SymEqual)
        SWC_RESULT(collectSetCandidates(sema, *ownerStruct, node.codeRef(), node.nodeRightRef, candidates));
    else
        SWC_RESULT(collectAssignSpecOpCandidates(sema, *ownerStruct, node.codeRef(), tok.id, false, candidates));

    TypeRef compareTypeRef = TypeRef::invalid();
    for (const Symbol* candidate : candidates)
    {
        const auto* fn = candidate ? candidate->safeCast<SymbolFunction>() : nullptr;
        if (!fn)
            continue;

        const SymbolVariable* param = assignSpecOpValueParam(*fn, node.nodeLeftRef);
        if (!param || param->typeRef().isInvalid())
            continue;

        const TypeRef resolvedTypeRef = SemaHelpers::unwrapBindingType(sema.ctx(), param->typeRef());
        if (resolvedTypeRef.isInvalid() || !sema.typeMgr().get(resolvedTypeRef).isFunction())
            continue;

        if (compareTypeRef.isInvalid())
        {
            outBindingTypeRef = param->typeRef();
            compareTypeRef    = resolvedTypeRef;
            continue;
        }

        if (compareTypeRef != resolvedTypeRef)
        {
            outBindingTypeRef = TypeRef::invalid();
            return Result::Continue;
        }
    }

    return Result::Continue;
}

Result SemaSpecOp::tryResolveAssign(Sema& sema, const AstAssignStmt& node, const SemaNodeView& leftView, bool& outHandled)
{
    outHandled = false;

    const Token& tok = sema.token(node.codeRef());
    if (!tok.isAny({TokenId::SymEqual, TokenId::SymPlusEqual, TokenId::SymMinusEqual, TokenId::SymAsteriskEqual, TokenId::SymSlashEqual, TokenId::SymAmpersandEqual, TokenId::SymPipeEqual, TokenId::SymCircumflexEqual, TokenId::SymPercentEqual, TokenId::SymLowerLowerEqual, TokenId::SymGreaterGreaterEqual}))
        return Result::Continue;

    if (!leftView.type())
        return Result::Continue;

    const SymbolStruct* ownerStruct = structSpecOpOwner(sema, leftView);
    if (!ownerStruct)
        return Result::Continue;

    SWC_RESULT(sema.waitSemaCompleted(ownerStruct, node.codeRef()));

    SmallVector<Symbol*> candidates;
    if (tok.id == TokenId::SymEqual)
        SWC_RESULT(collectSetCandidates(sema, *ownerStruct, node.codeRef(), node.nodeRightRef, candidates));
    else
        SWC_RESULT(collectAssignSpecOpCandidates(sema, *ownerStruct, node.codeRef(), tok.id, false, candidates));
    if (candidates.empty())
        return Result::Continue;

    // `#relocate`, and `#nodrop` without `#move`, write into a target that is treated as uninitialized
    // (or moved-from): the value is moved/copied into it bitwise, then opPostMove / opPostCopy fixes it
    // up. They must never be rerouted through a by-value `opSet`, which reads the (uninitialized or
    // moved-from) target - its `.buffer` aliasing check and `.allocator`/buffer reuse - corrupting
    // move-only handles such as String/Array (e.g. crashing Array.popBack's
    // `var result: retval = undefined; result = #relocate arr.buffer[...]`, or corrupting Array.insertAt
    // when it overwrites a slot whose buffer was just raw-moved to a neighbour). A plain `#move`
    // replaces an existing value, so it keeps its user `opSet` (move-only handles transfer ownership
    // via the dedicated raw modifier).
    if (tok.id == TokenId::SymEqual &&
        (node.modifierFlags.has(AstModifierFlagsE::Relocate) ||
         (node.modifierFlags.has(AstModifierFlagsE::NoDrop) && !node.modifierFlags.has(AstModifierFlagsE::Move))))
        return Result::Continue;

    SmallVector<AstNodeRef> args;
    args.push_back(node.nodeRightRef);

    bool            matched  = false;
    SymbolFunction* calledFn = nullptr;
    SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), node.nodeLeftRef, true, &matched, true, true, &calledFn));
    if (!matched)
        return Result::Continue;

    auto* assignPayload = sema.semaPayload<AssignSpecOpPayload>(sema.curNodeRef());
    if (!assignPayload)
    {
        assignPayload = sema.compiler().allocate<AssignSpecOpPayload>();
        sema.setSemaPayload(sema.curNodeRef(), assignPayload);
    }

    assignPayload->calledFn = calledFn;

    sema.setType(sema.curNodeRef(), sema.typeMgr().typeVoid());
    outHandled = true;
    return Result::Continue;
}

Result SemaSpecOp::tryResolveVarInitSet(Sema& sema, AstNodeRef receiverRef, AstNodeRef valueRef, bool& outHandled)
{
    outHandled = false;

    const SemaNodeView  receiverView(sema, receiverRef, SemaNodeViewPartE::Type);
    const SymbolStruct* ownerStruct = structSpecOpOwner(sema, receiverView);
    if (!ownerStruct)
        return Result::Continue;

    SWC_RESULT(sema.waitSemaCompleted(ownerStruct, sema.node(valueRef).codeRef()));

    SmallVector<Symbol*> candidates;
    SWC_RESULT(collectSetCandidates(sema, *ownerStruct, sema.node(valueRef).codeRef(), valueRef, candidates));
    if (candidates.empty())
        return Result::Continue;

    SmallVector<AstNodeRef> args;
    args.push_back(valueRef);

    Symbol*    savedSymbol = sema.curViewSymbol().sym();
    const bool savedLValue = sema.isLValue(sema.curNodeRef());

    bool            matched  = false;
    SymbolFunction* calledFn = nullptr;
    SWC_RESULT(resolveSyntheticCall(sema, sema.node(sema.curNodeRef()), candidates.span(), args.span(), receiverRef, true, &matched, false, false, &calledFn));

    if (savedSymbol)
        sema.setSymbol(sema.curNodeRef(), savedSymbol);
    if (savedLValue)
        sema.setIsLValue(sema.curNodeRef());
    else
        sema.unsetIsLValue(sema.curNodeRef());

    if (!matched)
        return Result::Continue;

    auto* payload = sema.semaPayload<VarInitSpecOpPayload>(sema.curNodeRef());
    if (!payload)
    {
        payload = sema.compiler().allocate<VarInitSpecOpPayload>();
        sema.setSemaPayload(sema.curNodeRef(), payload);
    }

    payload->calledFn = calledFn;

    outHandled = payload->calledFn != nullptr;
    return Result::Continue;
}

Result SemaSpecOp::tryResolveCountOf(Sema& sema, AstNodeRef exprRef, SymbolFunction*& outCalledFn, bool& outHandled)
{
    const IdentifierRef opCountId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpCount);
    return tryResolveReceiverOnlySpecOp(sema, outCalledFn, outHandled, exprRef, opCountId, true);
}

Result SemaSpecOp::tryResolveDataOf(Sema& sema, AstNodeRef exprRef, SymbolFunction*& outCalledFn, bool& outHandled)
{
    const IdentifierRef opDataId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpData);
    return tryResolveReceiverOnlySpecOp(sema, outCalledFn, outHandled, exprRef, opDataId, false);
}

Result SemaSpecOp::canResolveVisit(Sema& sema, const AstForeachStmt& node, bool& outMatched)
{
    outMatched = false;

    const SemaNodeView  exprView(sema, node.nodeExprRef, SemaNodeViewPartE::Type);
    const SymbolStruct* ownerStruct = structSpecOpOwner(sema, exprView);
    if (!ownerStruct)
        return Result::Continue;

    SWC_RESULT(sema.waitSemaCompleted(ownerStruct, node.codeRef()));

    SmallVector<AstNodeRef> genericArgs;
    genericArgs.push_back(makeSyntheticBoolConstantArg(sema, node.codeRef(), foreachRequestsByAddress(sema, node)));

    SmallVector<Symbol*> candidates;
    SWC_RESULT(collectVisitSpecOpCandidates(sema, *ownerStruct, genericArgs.span(), candidates));
    if (candidates.empty())
        return waitPendingVisitSpecOp(sema, *ownerStruct, node);

    SmallVector<AstNodeRef> args;
    args.push_back(makeSyntheticCodeBlockArg(sema, node));
    AstNodeRef receiverRef = sema.viewZero(node.nodeExprRef).nodeRef();
    if (receiverRef.isInvalid())
        receiverRef = node.nodeExprRef;
    SmallVector<ResolvedCallArgument> resolvedArgs;
    SWC_RESULT(matchSyntheticCall(sema, candidates.span(), args.span(), receiverRef, true, resolvedArgs, outMatched));
    return Result::Continue;
}

Result SemaSpecOp::tryResolveVisit(Sema& sema, const AstForeachStmt& node, SymbolFunction*& outCalledFn, bool& outHandled)
{
    outCalledFn = nullptr;
    outHandled  = false;

    const SemaNodeView  exprView(sema, node.nodeExprRef, SemaNodeViewPartE::Type);
    const SymbolStruct* ownerStruct = structSpecOpOwner(sema, exprView);
    if (!ownerStruct)
        return Result::Continue;

    SWC_RESULT(sema.waitSemaCompleted(ownerStruct, node.codeRef()));

    SmallVector<AstNodeRef> genericArgs;
    genericArgs.push_back(makeSyntheticBoolConstantArg(sema, node.codeRef(), foreachRequestsByAddress(sema, node)));

    SmallVector<Symbol*> candidates;
    SWC_RESULT(collectVisitSpecOpCandidates(sema, *ownerStruct, genericArgs.span(), candidates));
    if (candidates.empty())
        return waitPendingVisitSpecOp(sema, *ownerStruct, node);

    SmallVector<AstNodeRef> args;
    args.push_back(makeSyntheticCodeBlockArg(sema, node));
    AstNodeRef receiverRef = sema.viewZero(node.nodeExprRef).nodeRef();
    if (receiverRef.isInvalid())
        receiverRef = node.nodeExprRef;
    bool matched = false;
    SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), receiverRef, true, &matched, false, true, &outCalledFn));
    outHandled = matched;
    return Result::Continue;
}

Result SemaSpecOp::tryResolveSlice(Sema& sema, const AstIndexExpr& node, const SemaNodeView& indexedView, bool& outHandled)
{
    outHandled = false;

    const SymbolStruct* ownerStruct = structSpecOpOwner(sema, indexedView);
    if (!ownerStruct)
        return Result::Continue;

    SWC_RESULT(sema.waitSemaCompleted(ownerStruct, node.codeRef()));

    const auto&        range        = sema.node(node.nodeArgRef).cast<AstRangeExpr>();
    const SemaNodeView nodeDownView = sema.viewTypeConstant(range.nodeExprDownRef);
    const SemaNodeView nodeUpView   = sema.viewTypeConstant(range.nodeExprUpRef);
    int64_t            constDown    = 0;
    int64_t            constUp      = 0;
    bool               hasConstDown = false;
    bool               hasConstUp   = false;
    SWC_RESULT(checkSliceSpecOpBound(sema, range.nodeExprDownRef, nodeDownView, constDown, hasConstDown));
    SWC_RESULT(checkSliceSpecOpBound(sema, range.nodeExprUpRef, nodeUpView, constUp, hasConstUp));

    if (hasConstDown && hasConstUp)
    {
        if (constDown > constUp)
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_range_invalid_bounds, node.nodeArgRef);
            diag.addArgument(Diagnostic::ARG_LEFT, nodeDownView.cstRef());
            diag.addArgument(Diagnostic::ARG_RIGHT, nodeUpView.cstRef());
            diag.report(sema.ctx());
            return Result::Error;
        }

        // 'opSlice' takes an inclusive upper bound, so lowering an exclusive range subtracts
        // one from it. An empty range has no inclusive spelling and would hand the hook a
        // bound below its lower bound, so it is rejected here instead of at the hook.
        if (constDown == constUp && !range.hasFlag(AstRangeExprFlagsE::Inclusive))
        {
            auto diag = SemaError::report(sema, DiagnosticId::sema_err_range_empty_op_slice, node.nodeArgRef);
            diag.addArgument(Diagnostic::ARG_LEFT, nodeDownView.cstRef());
            diag.addArgument(Diagnostic::ARG_RIGHT, nodeUpView.cstRef());
            diag.report(sema.ctx());
            return Result::Error;
        }
    }

    SmallVector<Symbol*> candidates;
    const IdentifierRef  opSliceId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpSlice);
    SWC_RESULT(collectSpecOpCandidates(sema, *ownerStruct, opSliceId, std::span<const AstNodeRef>{}, candidates));
    if (candidates.empty())
        return Result::Continue;

    SymbolFunction* countFn = nullptr;
    if (!range.nodeExprUpRef.isValid())
    {
        SmallVector<Symbol*> countCandidates;
        const IdentifierRef  opCountId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpCount);
        SWC_RESULT(collectSpecOpCandidates(sema, *ownerStruct, opCountId, std::span<const AstNodeRef>{}, countCandidates));
        countFn = selectReceiverOnlyCandidate(sema, countCandidates.span(), indexedView.type()->isConst());
        if (!countFn)
            return Result::Continue;
    }

    std::optional<uint64_t> lowerConst;
    if (!range.nodeExprDownRef.isValid())
        lowerConst = 0;
    else if (hasConstDown)
        lowerConst = static_cast<uint64_t>(constDown);

    std::optional<uint64_t> upperConst;
    if (range.nodeExprUpRef.isValid() && hasConstUp)
    {
        const uint64_t adjustedUpper = range.hasFlag(AstRangeExprFlagsE::Inclusive) ? static_cast<uint64_t>(constUp) : static_cast<uint64_t>(constUp - 1);
        upperConst                   = adjustedUpper;
    }
    else if (!range.nodeExprUpRef.isValid())
    {
        upperConst = 0;
    }

    const AstNodeRef lowerArgRef = makeSyntheticU64Arg(sema, node.codeRef(), lowerConst);
    const AstNodeRef upperArgRef = makeSyntheticU64Arg(sema, node.codeRef(), upperConst);

    SmallVector<AstNodeRef> args;
    args.push_back(lowerArgRef);
    args.push_back(upperArgRef);

    SmallVector<ResolvedCallArgument> resolvedArgs;
    bool                              matched = false;
    if (!indexedView.type()->isConst())
    {
        SmallVector<Symbol*> mutableCandidates;
        SmallVector<Symbol*> constCandidates;
        splitMutableReceiverCandidates(sema, candidates.span(), mutableCandidates, constCandidates);

        if (!mutableCandidates.empty())
        {
            SWC_RESULT(matchSyntheticCall(sema, mutableCandidates.span(), args.span(), node.nodeExprRef, true, resolvedArgs, matched));
            if (matched)
                candidates = std::move(mutableCandidates);
            else if (!constCandidates.empty())
                candidates = std::move(constCandidates);
        }
    }

    if (!matched)
        SWC_RESULT(matchSyntheticCall(sema, candidates.span(), args.span(), node.nodeExprRef, true, resolvedArgs, matched));
    if (!matched)
        return Result::Continue;

    sema.setResolvedCallArguments(sema.curNodeRef(), resolvedArgs);

    const auto symView = sema.curViewSymbol();
    SWC_ASSERT(symView.sym() && symView.sym()->isFunction());
    auto& calledFn = symView.sym()->cast<SymbolFunction>();
    SemaHelpers::addCurrentFunctionCallDependency(sema, &calledFn);
    if (countFn)
        SemaHelpers::addCurrentFunctionCallDependency(sema, countFn);

    const TypeRef    returnTypeRef = calledFn.returnTypeRef();
    const AstNodeRef resultNodeRef = sema.viewZero(sema.curNodeRef()).nodeRef();
    auto*            payload       = sema.compiler().allocate<SliceSpecOpSemaPayload>();
    payload->calledFn              = &calledFn;
    payload->countFn               = countFn;
    payload->lowerArgRef           = lowerArgRef;
    payload->upperArgRef           = upperArgRef;
    payload->lowerBoundRef         = range.nodeExprDownRef;
    payload->upperBoundRef         = range.nodeExprUpRef;
    payload->inclusive             = range.hasFlag(AstRangeExprFlagsE::Inclusive);
    sema.setSemaPayload(sema.curNodeRef(), payload);

    sema.setSymbol(sema.curNodeRef(), &calledFn);
    sema.setType(sema.curNodeRef(), returnTypeRef);
    sema.setType(resultNodeRef, returnTypeRef);
    sema.setIsValue(sema.curNode());
    sema.setIsValue(resultNodeRef);
    sema.unsetIsLValue(sema.curNodeRef());
    sema.unsetIsLValue(resultNodeRef);
    SWC_RESULT(SemaHelpers::attachIndirectReturnRuntimeStorageIfNeeded(sema, node, calledFn, "__spec_op_runtime_storage"));

    outHandled = true;
    return Result::Continue;
}

namespace
{
    Result tryResolveIndexWithArgs(Sema& sema, AstNodeRef indexExprRef, AstNodeRef indexedExprRef, const SourceCodeRef& codeRef, std::span<const AstNodeRef> indexArgRefs, const SemaNodeView& indexedView, bool& outHandled)
    {
        outHandled = false;

        const SymbolStruct* ownerStruct = structSpecOpOwner(sema, indexedView);
        if (!ownerStruct)
            return Result::Continue;

        SWC_RESULT(sema.waitSemaCompleted(ownerStruct, codeRef));

        bool             deferToSimpleAssignWriteSpecOp = false;
        const AstNodeRef parentRef                      = sema.visit().parentNodeRef();
        if (parentRef.isValid() && sema.node(parentRef).is(AstNodeId::AssignStmt))
        {
            const auto& assignNode = sema.node(parentRef).cast<AstAssignStmt>();
            if (assignNode.nodeLeftRef == indexExprRef)
            {
                const Token&         tok = sema.token(assignNode.codeRef());
                SmallVector<Symbol*> candidates;
                SWC_RESULT(collectAssignSpecOpCandidates(sema, *ownerStruct, assignNode.codeRef(), tok.id, true, candidates));
                if (tok.id == TokenId::SymEqual)
                {
                    deferToSimpleAssignWriteSpecOp = !candidates.empty();
                }
                else if (!candidates.empty())
                {
                    auto* payload = sema.compiler().allocate<DeferredIndexAssignSpecOpPayload>();
                    sema.setSemaPayload(indexExprRef, payload);
                    outHandled = true;
                    return Result::Continue;
                }
            }
        }

        // A place context needs the element's ADDRESS rather than its value: the base of a
        // member access, the operand of an address-of, the target of an assignment, or an
        // element that is indexed again. 'opIndexPtr' is preferred there; a plain read
        // prefers the value-returning 'opIndex'.
        bool placeContext = false;
        if (parentRef.isValid())
        {
            const AstNode& parentNode = sema.node(parentRef);
            if (const auto* memberAccess = parentNode.safeCast<AstMemberAccessExpr>())
                placeContext = memberAccess->nodeLeftRef == indexExprRef;
            else if (const auto* unaryExpr = parentNode.safeCast<AstUnaryExpr>())
                placeContext = unaryExpr->nodeExprRef == indexExprRef && sema.token(unaryExpr->codeRef()).id == TokenId::SymAmpersand;
            else if (const auto* assignStmt = parentNode.safeCast<AstAssignStmt>())
                placeContext = assignStmt->nodeLeftRef == indexExprRef;
            else if (const auto* parentIndex = parentNode.safeCast<AstIndexExpr>())
                placeContext = parentIndex->nodeExprRef == indexExprRef;
            else if (const auto* parentIndexList = parentNode.safeCast<AstIndexListExpr>())
                placeContext = parentIndexList->nodeExprRef == indexExprRef;
        }

        SmallVector<Symbol*> valueCandidates;
        const IdentifierRef  opIndexId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpIndex);
        SWC_RESULT(collectSpecOpCandidates(sema, *ownerStruct, opIndexId, std::span<const AstNodeRef>{}, valueCandidates));

        SmallVector<Symbol*> ptrCandidates;
        const IdentifierRef  opIndexPtrId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpIndexPtr);
        SWC_RESULT(collectSpecOpCandidates(sema, *ownerStruct, opIndexPtrId, std::span<const AstNodeRef>{}, ptrCandidates));

        if (valueCandidates.empty() && ptrCandidates.empty())
        {
            if (deferToSimpleAssignWriteSpecOp)
            {
                auto* payload = sema.compiler().allocate<DeferredIndexAssignSpecOpPayload>();
                sema.setSemaPayload(indexExprRef, payload);
                outHandled = true;
            }
            return Result::Continue;
        }

        if (deferToSimpleAssignWriteSpecOp && !indexReceiverIsConst(sema, indexedView))
        {
            SmallVector<Symbol*> mutableCandidates;
            SmallVector<Symbol*> constCandidates;
            splitMutableReceiverCandidates(sema, valueCandidates.span(), mutableCandidates, constCandidates);
            if (mutableCandidates.empty())
                splitMutableReceiverCandidates(sema, ptrCandidates.span(), mutableCandidates, constCandidates);
            if (mutableCandidates.empty())
            {
                auto* payload = sema.compiler().allocate<DeferredIndexAssignSpecOpPayload>();
                sema.setSemaPayload(indexExprRef, payload);
                outHandled = true;
                return Result::Continue;
            }
        }

        SmallVector<AstNodeRef> args;
        args.reserve(indexArgRefs.size());
        for (const AstNodeRef indexArgRef : indexArgRefs)
            args.push_back(normalizeIndexSpecOpArgRef(sema, indexArgRef));

        bool            matched  = false;
        SymbolFunction* calledFn = nullptr;

        // 'opIndexPtr' calls are never const-evaluated: the returned pointer is an address
        // into runtime storage. They do inline — the call payload then carries the element
        // address computed by the inlined body, and codegen re-tags it like a reference return.
        const auto tryResolveIndexSet = [&](SmallVector<Symbol*>& set, bool allowConstEval, bool allowInline) -> Result
        {
            if (set.empty() || matched)
                return Result::Continue;

            if (!indexReceiverIsConst(sema, indexedView))
            {
                SmallVector<Symbol*> mutableCandidates;
                SmallVector<Symbol*> constCandidates;
                splitMutableReceiverCandidates(sema, set.span(), mutableCandidates, constCandidates);

                if (!mutableCandidates.empty())
                {
                    SWC_RESULT(resolveSyntheticCall(sema, sema.node(indexExprRef), mutableCandidates.span(), args.span(), indexedExprRef, true, &matched, allowConstEval, allowInline, &calledFn));
                    if (matched)
                        return Result::Continue;
                }

                if (!constCandidates.empty())
                    SWC_RESULT(resolveSyntheticCall(sema, sema.node(indexExprRef), constCandidates.span(), args.span(), indexedExprRef, true, &matched, allowConstEval, allowInline, &calledFn));
                return Result::Continue;
            }

            return resolveSyntheticCall(sema, sema.node(indexExprRef), set.span(), args.span(), indexedExprRef, true, &matched, allowConstEval, allowInline, &calledFn);
        };

        if (placeContext)
        {
            SWC_RESULT(tryResolveIndexSet(ptrCandidates, false, true));
            SWC_RESULT(tryResolveIndexSet(valueCandidates, true, true));
        }
        else
        {
            SWC_RESULT(tryResolveIndexSet(valueCandidates, true, true));
            SWC_RESULT(tryResolveIndexSet(ptrCandidates, false, true));
        }

        if (!matched)
        {
            if (deferToSimpleAssignWriteSpecOp)
            {
                auto* payload = sema.compiler().allocate<DeferredIndexAssignSpecOpPayload>();
                sema.setSemaPayload(indexExprRef, payload);
                outHandled = true;
            }
            return Result::Continue;
        }

        SWC_ASSERT(calledFn);

        const TypeRef   returnTypeRef = calledFn->returnTypeRef();
        const TypeInfo& returnType    = sema.typeMgr().get(returnTypeRef);

        if (deferToSimpleAssignWriteSpecOp && !returnType.isReference() && calledFn->specOpKind() != SpecOpKind::OpIndexPtr)
        {
            auto* payload = sema.compiler().allocate<DeferredIndexAssignSpecOpPayload>();
            sema.setSemaPayload(indexExprRef, payload);
            outHandled = true;
            return Result::Continue;
        }

        if (!sema.viewConstant(indexExprRef).hasConstant())
            applyIndexReadSpecOpResult(sema, indexExprRef, *calledFn);

        if (sema.hasSubstitute(indexExprRef))
        {
            outHandled = true;
            return Result::Continue;
        }

        outHandled = true;
        return Result::Continue;
    }
}

Result SemaSpecOp::tryResolveIndex(Sema& sema, const AstIndexExpr& node, const SemaNodeView& indexedView, bool& outHandled)
{
    SmallVector<AstNodeRef> args;
    args.push_back(node.nodeArgRef);
    return tryResolveIndexWithArgs(sema, sema.curNodeRef(), node.nodeExprRef, node.codeRef(), args.span(), indexedView, outHandled);
}

Result SemaSpecOp::tryResolveIndex(Sema& sema, const AstIndexListExpr& node, const SemaNodeView& indexedView, bool& outHandled)
{
    SmallVector<AstNodeRef> args;
    appendIndexArgs(sema.ast(), node, args);
    return tryResolveIndexWithArgs(sema, sema.curNodeRef(), node.nodeExprRef, node.codeRef(), args.span(), indexedView, outHandled);
}

Result SemaSpecOp::tryResolveIndexAssign(Sema& sema, const AstAssignStmt& node, bool& outHandled)
{
    outHandled = false;

    const Token& tok = sema.token(node.codeRef());
    if (!Token::isOpAssign(tok.id))
        return Result::Continue;

    const AstNodeRef leftNodeRef = node.nodeLeftRef;
    if (leftNodeRef.isInvalid())
        return Result::Continue;

    AstNodeRef              indexedExprRef = AstNodeRef::invalid();
    SmallVector<AstNodeRef> indexArgRefs;
    if (!collectIndexAccessArgs(sema, indexedExprRef, indexArgRefs, leftNodeRef))
        return Result::Continue;

    const SemaNodeView  indexedView = sema.viewType(indexedExprRef);
    const SymbolStruct* ownerStruct = structSpecOpOwner(sema, indexedView);
    if (!ownerStruct)
        return Result::Continue;

    SWC_RESULT(sema.waitSemaCompleted(ownerStruct, node.codeRef()));
    SWC_RESULT(SemaCheck::isAssignable(sema, indexedExprRef, sema.viewNodeTypeSymbol(indexedExprRef)));

    SmallVector<Symbol*> candidates;
    SWC_RESULT(collectAssignSpecOpCandidates(sema, *ownerStruct, node.codeRef(), tok.id, true, candidates));
    if (candidates.empty())
        return Result::Continue;

    if (tok.id == TokenId::SymEqual)
    {
        const SemaNodeView leftView            = sema.viewNodeTypeSymbol(leftNodeRef);
        bool               canAssignThroughRef = false;
        SWC_RESULT(canAssignThroughIndexLValue(sema, node, leftNodeRef, leftView, canAssignThroughRef));

        SymbolFunction* setFn      = nullptr;
        bool            setMatched = false;
        SWC_RESULT(probeIndexAssignSpecOp(sema, node, indexedExprRef, indexArgRefs.span(), candidates.span(), setFn, setMatched));

        // A dedicated indexed write operator is more specific than mutating through an opIndex reference.
        if (setMatched)
        {
            SWC_ASSERT(setFn);
            canAssignThroughRef = false;
        }

        if (!setMatched)
        {
            if (!canAssignThroughRef)
            {
                SmallVector<AstNodeRef> args;
                args.reserve(indexArgRefs.size() + 1);
                for (const AstNodeRef indexArgRef : indexArgRefs)
                    args.push_back(normalizeIndexSpecOpArgRef(sema, indexArgRef));
                args.push_back(node.nodeRightRef);
                sema.clearSemaPayload(leftNodeRef);
                auto* deferredPayload = sema.compiler().allocate<DeferredIndexAssignSpecOpPayload>();
                sema.setSemaPayload(leftNodeRef, deferredPayload);
                SymbolFunction* calledFn = nullptr;
                SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), indexedExprRef, false, nullptr, true, true, &calledFn));

                auto* assignPayload = sema.semaPayload<AssignSpecOpPayload>(sema.curNodeRef());
                if (!assignPayload)
                {
                    assignPayload = sema.compiler().allocate<AssignSpecOpPayload>();
                    sema.setSemaPayload(sema.curNodeRef(), assignPayload);
                }

                assignPayload->calledFn = calledFn;

                sema.setType(sema.curNodeRef(), sema.typeMgr().typeVoid());
                outHandled = true;
            }

            return Result::Continue;
        }
    }

    SmallVector<AstNodeRef> args;
    args.reserve(indexArgRefs.size() + 1);
    for (const AstNodeRef indexArgRef : indexArgRefs)
        args.push_back(normalizeIndexSpecOpArgRef(sema, indexArgRef));
    args.push_back(node.nodeRightRef);
    sema.clearSemaPayload(leftNodeRef);
    auto* deferredPayload = sema.compiler().allocate<DeferredIndexAssignSpecOpPayload>();
    sema.setSemaPayload(leftNodeRef, deferredPayload);
    SymbolFunction* calledFn = nullptr;
    SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), indexedExprRef, false, nullptr, true, true, &calledFn));

    auto* assignPayload = sema.semaPayload<AssignSpecOpPayload>(sema.curNodeRef());
    if (!assignPayload)
    {
        assignPayload = sema.compiler().allocate<AssignSpecOpPayload>();
        sema.setSemaPayload(sema.curNodeRef(), assignPayload);
    }

    assignPayload->calledFn = calledFn;

    sema.setType(sema.curNodeRef(), sema.typeMgr().typeVoid());
    outHandled = true;
    return Result::Continue;
}

Result SemaSpecOp::tryResolveUnary(Sema& sema, const AstUnaryExpr& node, const SemaNodeView& operandView, bool& outHandled)
{
    outHandled = false;

    const Token& tok = sema.token(node.codeRef());
    if (!tok.isAny({TokenId::SymPlus, TokenId::SymMinus, TokenId::SymBang, TokenId::SymTilde}))
        return Result::Continue;

    if (!operandView.type())
        return Result::Continue;

    TypeRef         unwrappedTypeRef = operandView.typeRef();
    const TypeInfo& operandValueType = sema.typeMgr().get(unwrappedTypeRef);
    if (operandValueType.isReference())
        unwrappedTypeRef = unwrapAlias(sema.ctx(), operandValueType.payloadTypeRef());
    else
        unwrappedTypeRef = unwrapAlias(sema.ctx(), unwrappedTypeRef);
    if (!unwrappedTypeRef.isValid())
        unwrappedTypeRef = operandView.typeRef();

    const TypeInfo& operandType = sema.typeMgr().get(unwrappedTypeRef);
    if (!operandType.isStruct())
        return Result::Continue;

    const auto& ownerStruct = operandType.payloadSymStruct();
    SWC_RESULT(sema.waitSemaCompleted(&ownerStruct, node.codeRef()));

    const std::optional<SpecOperator> op = unarySpecOperator(tok.id);
    SWC_ASSERT(op.has_value());
    AstNodeRef genericArg = AstNodeRef::invalid();
    SWC_RESULT(makeSyntheticOperatorArg(genericArg, sema, node.codeRef(), *op));

    const IdentifierRef  opUnaryId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpUnary);
    SmallVector<Symbol*> candidates;
    SWC_RESULT(collectSpecOpCandidates(sema, ownerStruct, opUnaryId, std::span{&genericArg, 1}, candidates));
    if (candidates.empty())
        return Result::Continue;

    SmallVector<AstNodeRef> args;
    SymbolFunction*         calledFn = nullptr;
    SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), node.nodeExprRef, false, nullptr, true, true, &calledFn));

    auto* unaryPayload = sema.semaPayload<UnarySpecOpPayload>(sema.curNodeRef());
    if (!unaryPayload)
    {
        unaryPayload = sema.compiler().allocate<UnarySpecOpPayload>();
        sema.setSemaPayload(sema.curNodeRef(), unaryPayload);
    }

    unaryPayload->calledFn = calledFn;
    outHandled             = true;
    return Result::Continue;
}

namespace
{
    struct BinarySpecOpResolution
    {
        SmallVector<Symbol*>          candidates;
        SmallVector<AstNodeRef>       args;
        Match::FunctionCandidateProbe probe;
        AstNodeRef                    receiverRef = AstNodeRef::invalid();

        bool matched() const { return probe.matched && probe.fn != nullptr; }
    };

    struct BinarySpecOpProbeRequest
    {
        const SemaNodeView* receiverView    = nullptr;
        AstNodeRef          receiverRef     = AstNodeRef::invalid();
        AstNodeRef          argRef          = AstNodeRef::invalid();
        IdentifierRef       opId            = IdentifierRef::invalid();
        AstNodeRef          genericArg      = AstNodeRef::invalid();
        SpecOperator        op              = SpecOperator::Add;
        bool                commutativeOnly = false;
    };

    std::optional<bool> commutativeAttributeApplies(Sema& sema, const SymbolFunction& fn, SpecOperator op)
    {
        const IdentifierRef commutativeId = sema.idMgr().predefined(IdentifierManager::PredefinedName::Commutative);
        for (const AttributeInstance& attr : fn.attributes().attributes)
        {
            if (!attr.symbol || attr.symbol->idRef() != commutativeId || !attr.symbol->inSwagNamespace(sema.ctx()))
                continue;
            if (attr.params.empty())
                return true;

            for (const AttributeParamInstance& param : attr.params)
            {
                SWC_ASSERT(param.valueCstRef.isValid());
                const ConstantValue& value = sema.cstMgr().get(param.valueCstRef);
                SWC_ASSERT(value.isEnumValue());
                const ConstantValue& rawValue = sema.cstMgr().get(value.getEnumValue());
                if (rawValue.getInt().asI64() == static_cast<int64_t>(op))
                    return true;
            }

            return false;
        }

        return std::nullopt;
    }

    bool isCommutativeForOp(Sema& sema, const SymbolFunction& fn, SpecOperator op)
    {
        const std::optional<bool> applies = commutativeAttributeApplies(sema, fn, op);
        if (applies.has_value())
            return applies.value();

        const SymbolFunction* root = fn.genericRootSym();
        if (!root || root == &fn)
            return false;

        const std::optional<bool> rootApplies = commutativeAttributeApplies(sema, *root, op);
        if (rootApplies.has_value())
            return rootApplies.value();

        return false;
    }

    void filterCommutativeBinaryCandidates(Sema& sema, SmallVector<Symbol*>& candidates, SpecOperator op)
    {
        SmallVector<Symbol*> filtered;
        filtered.reserve(candidates.size());
        for (Symbol* candidate : candidates)
        {
            if (!candidate || !candidate->isFunction())
                continue;
            if (isCommutativeForOp(sema, candidate->cast<SymbolFunction>(), op))
                filtered.push_back(candidate);
        }

        candidates = std::move(filtered);
    }

    Result probeBinarySpecOp(Sema& sema, const AstBinaryExpr& node, const BinarySpecOpProbeRequest& request, BinarySpecOpResolution& out)
    {
        out             = {};
        out.receiverRef = request.receiverRef;

        SWC_ASSERT(request.receiverView != nullptr);
        const SymbolStruct* ownerStruct = structSpecOpOwner(sema, *request.receiverView);
        if (!ownerStruct)
            return Result::Continue;

        SWC_RESULT(sema.waitSemaCompleted(ownerStruct, node.codeRef()));
        SWC_RESULT(collectSpecOpCandidates(sema, *ownerStruct, request.opId, std::span{&request.genericArg, 1}, out.candidates, request.commutativeOnly));
        if (request.commutativeOnly)
            filterCommutativeBinaryCandidates(sema, out.candidates, request.op);
        if (out.candidates.empty())
            return Result::Continue;

        out.args.push_back(request.argRef);
        const SemaNodeView calleeView(sema, sema.curNodeRef(), SemaNodeViewPartE::Node);
        return Match::probeFunctionCandidates(sema, calleeView, out.candidates.span(), out.args.span(), request.receiverRef, out.probe, true);
    }

    Result finalizeBinarySpecOp(Sema& sema, const AstBinaryExpr& node, BinarySpecOpResolution& selected, bool& outHandled)
    {
        SymbolFunction* calledFn = nullptr;
        SWC_RESULT(resolveSyntheticCall(sema, node, selected.candidates.span(), selected.args.span(), selected.receiverRef, false, nullptr, true, true, &calledFn));

        auto* binaryPayload = sema.semaPayload<BinarySpecOpPayload>(sema.curNodeRef());
        if (!binaryPayload)
        {
            binaryPayload = sema.compiler().allocate<BinarySpecOpPayload>();
            sema.setSemaPayload(sema.curNodeRef(), binaryPayload);
        }

        binaryPayload->calledFn = calledFn;
        outHandled              = true;
        return Result::Continue;
    }

    Result raiseAmbiguousBinarySpecOp(Sema& sema, const BinarySpecOpResolution& left, const BinarySpecOpResolution& right)
    {
        SmallVector<const Symbol*> ambiguous;
        ambiguous.push_back(left.probe.fn);
        ambiguous.push_back(right.probe.fn);
        return SemaError::raiseAmbiguousSymbol(sema, sema.curNodeRef(), ambiguous.span());
    }
}

Result SemaSpecOp::tryResolveBinary(Sema& sema, const AstBinaryExpr& node, const SemaNodeView& leftView, const SemaNodeView& rightView, bool& outHandled)
{
    outHandled = false;

    const Token& tok = sema.token(node.codeRef());
    if (!tok.isAny({TokenId::SymPlus, TokenId::SymMinus, TokenId::SymAsterisk, TokenId::SymSlash, TokenId::SymPercent, TokenId::SymAmpersand, TokenId::SymPipe, TokenId::SymCircumflex, TokenId::SymLowerLower, TokenId::SymGreaterGreater}))
        return Result::Continue;

    const std::optional<SpecOperator> op = binarySpecOperator(tok.id);
    SWC_ASSERT(op.has_value());
    AstNodeRef genericArg = AstNodeRef::invalid();
    SWC_RESULT(makeSyntheticOperatorArg(genericArg, sema, node.codeRef(), *op));

    const IdentifierRef opBinaryId      = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpBinary);
    const IdentifierRef opBinaryRightId = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpBinaryRight);

    BinarySpecOpResolution left;
    SWC_RESULT(probeBinarySpecOp(sema, node, {.receiverView = &leftView, .receiverRef = node.nodeLeftRef, .argRef = node.nodeRightRef, .opId = opBinaryId, .genericArg = genericArg, .op = *op}, left));

    BinarySpecOpResolution rightDirect;
    SWC_RESULT(probeBinarySpecOp(sema, node, {.receiverView = &rightView, .receiverRef = node.nodeRightRef, .argRef = node.nodeLeftRef, .opId = opBinaryRightId, .genericArg = genericArg, .op = *op}, rightDirect));

    BinarySpecOpResolution rightCommutative;
    if (!rightDirect.matched())
        SWC_RESULT(probeBinarySpecOp(sema, node, {.receiverView = &rightView, .receiverRef = node.nodeRightRef, .argRef = node.nodeLeftRef, .opId = opBinaryId, .genericArg = genericArg, .op = *op, .commutativeOnly = true}, rightCommutative));

    BinarySpecOpResolution* right = &rightDirect;
    if (!rightDirect.matched() && rightCommutative.matched())
        right = &rightCommutative;

    if (left.matched() && right->matched())
    {
        const int cmp = Match::compareFunctionCandidateProbes(left.probe, right->probe);
        if (cmp == 0 && left.probe.fn != right->probe.fn)
            return raiseAmbiguousBinarySpecOp(sema, left, *right);
        return finalizeBinarySpecOp(sema, node, cmp <= 0 ? left : *right, outHandled);
    }

    if (left.matched())
        return finalizeBinarySpecOp(sema, node, left, outHandled);

    if (right->matched())
        return finalizeBinarySpecOp(sema, node, *right, outHandled);

    if (!left.candidates.empty())
        return finalizeBinarySpecOp(sema, node, left, outHandled);

    if (!rightDirect.candidates.empty())
        return finalizeBinarySpecOp(sema, node, rightDirect, outHandled);

    if (!rightCommutative.candidates.empty())
        return finalizeBinarySpecOp(sema, node, rightCommutative, outHandled);

    return Result::Continue;
}

Result SemaSpecOp::tryResolveRelational(Sema& sema, const AstRelationalExpr& node, const SemaNodeView& leftView, bool& outHandled)
{
    outHandled = false;

    const Token&  tok     = sema.token(node.codeRef());
    IdentifierRef opIdRef = IdentifierRef::invalid();
    if (Token::isOpEquality(tok.id))
        opIdRef = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpEquals);
    else if (Token::isOpOrdering(tok.id))
        opIdRef = sema.idMgr().predefined(IdentifierManager::PredefinedName::OpCompare);
    else
        return Result::Continue;

    if (!leftView.type())
        return Result::Continue;

    const TypeRef   unwrappedTypeRef = relationalOperandTypeRef(sema, leftView.typeRef());
    const TypeInfo& leftType         = sema.typeMgr().get(unwrappedTypeRef);
    if (!leftType.isStruct())
        return Result::Continue;

    const auto& ownerStruct = leftType.payloadSymStruct();
    SWC_RESULT(sema.waitSemaCompleted(&ownerStruct, node.codeRef()));

    SmallVector<Symbol*> candidates;
    SWC_RESULT(collectSpecOpCandidates(sema, ownerStruct, opIdRef, std::span<const AstNodeRef>{}, candidates));
    if (candidates.empty())
        return Result::Continue;

    // Declaring 'opEquals' adds a comparison; it never takes away the one the struct already had.
    // So when none of the overloads can take the other operand, and that operand is this same
    // struct, the built-in comparison answers instead of a bad-argument error at every call site.
    // Any other operand type keeps reporting, which is where the overload is what the author
    // meant, and ordering keeps reporting throughout because it has no built-in answer.
    if (Token::isOpEquality(tok.id) &&
        SemaSpecOp::isOwnerStructType(sema.ctx(), ownerStruct, relationalOperandTypeRef(sema, sema.viewType(node.nodeRightRef).typeRef())))
    {
        bool viable = false;
        SWC_RESULT(hasViableRelationalCandidate(viable, sema, node, candidates.span()));
        if (!viable)
            return Result::Continue;
    }

    const AstNodeRef relRef = sema.curNodeRef();

    SmallVector<AstNodeRef> args;
    args.push_back(node.nodeRightRef);
    SymbolFunction* calledFn = nullptr;
    SWC_RESULT(resolveSyntheticCall(sema, node, candidates.span(), args.span(), node.nodeLeftRef, false, nullptr, true, true, &calledFn));

    auto* relationalPayload = sema.semaPayload<RelationalSpecOpPayload>(relRef);
    if (!relationalPayload)
    {
        relationalPayload = sema.compiler().allocate<RelationalSpecOpPayload>();
        sema.setSemaPayload(relRef, relationalPayload);
    }

    relationalPayload->calledFn = calledFn;

    const ConstantRef specOpCstRef         = sema.viewConstant(relRef).cstRef();
    const AstNodeRef  relSubstRef          = sema.viewZero(relRef).nodeRef();
    relationalPayload->inlineSubstituteRef = relSubstRef.isValid() && relSubstRef != relRef ? relSubstRef : AstNodeRef::invalid();

    switch (tok.id)
    {
        case TokenId::SymEqualEqual:
            sema.setType(relRef, sema.typeMgr().typeBool());
            if (specOpCstRef.isValid())
                sema.setConstant(relRef, specOpCstRef);
            break;

        case TokenId::SymBangEqual:
        {
            sema.setType(relRef, sema.typeMgr().typeBool());
            if (specOpCstRef.isValid())
                sema.setConstant(relRef, sema.cstMgr().cstNegBool(specOpCstRef));
            break;
        }

        case TokenId::SymLess:
        case TokenId::SymLessEqual:
        case TokenId::SymGreater:
        case TokenId::SymGreaterEqual:
        {
            sema.setType(relRef, sema.typeMgr().typeBool());
            if (specOpCstRef.isValid())
            {
                const int ordering = sema.cstMgr().get(specOpCstRef).getInt().compare(ApsInt::makeSigned32(0));
                bool      cmpRes   = false;
                switch (tok.id)
                {
                    case TokenId::SymLess:
                        cmpRes = ordering < 0;
                        break;
                    case TokenId::SymLessEqual:
                        cmpRes = ordering <= 0;
                        break;
                    case TokenId::SymGreater:
                        cmpRes = ordering > 0;
                        break;
                    case TokenId::SymGreaterEqual:
                        cmpRes = ordering >= 0;
                        break;
                    default:
                        SWC_UNREACHABLE();
                }

                sema.setConstant(relRef, sema.cstMgr().cstBool(cmpRes));
            }
            break;
        }

        case TokenId::SymLessEqualGreater:
            sema.setType(relRef, sema.typeMgr().typeS32());
            if (specOpCstRef.isValid())
                sema.setConstant(relRef, specOpCstRef);
            break;

        default:
            break;
    }

    outHandled = true;
    return Result::Continue;
}

SWC_END_NAMESPACE();
