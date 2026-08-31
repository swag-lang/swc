#include "pch.h"
#include "Compiler/Parser/Parser/Parser.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    struct AutoInlineBodyShape
    {
        uint32_t numCalls = 0;
        bool     blocked  = false;
    };

    // A local function or closure re-binds its outer-scope access and owns a distinct code symbol.
    // `#offsetof(local)` yields an offset within
    // the function's own frame, and inlining moves the callee's locals behind the caller's,
    // shifting every one of them. An implicit `.member` would likewise be rebound against the
    // caller's contextual receiver. Struct
    // `#offsetof` would survive, but telling the two operands apart needs full resolution, and a
    // body using `#offsetof` at all is rare enough that refusing all of them costs nothing.
    void measureAutoInlineBody(AutoInlineBodyShape& result, const Ast& ast, AstNodeRef nodeRef, const Token* firstToken)
    {
        if (result.blocked || nodeRef.isInvalid() || !ast.hasNode(nodeRef))
            return;

        const AstNode& node = ast.node(nodeRef);
        if (node.is(AstNodeId::AutoMemberAccessExpr))
        {
            result.blocked = true;
            return;
        }
        // `try`/`catch`/`expect` record fallibility on their lexical owner while their managed
        // child is analysed. Moving the whole construct into a caller can make that owner finish
        // before the cloned fallible call publishes its state, so leave error-management scopes
        // to explicit inlining until their payload is remapped with the clone.
        if (node.is(AstNodeId::ErrorManagementExpr) || node.is(AstNodeId::ErrorManagementStmt))
        {
            result.blocked = true;
            return;
        }
        if (node.is(AstNodeId::CallExpr))
            result.numCalls++;
        else if (node.is(AstNodeId::FunctionDecl) || node.is(AstNodeId::FunctionExpr) || node.is(AstNodeId::ClosureExpr))
        {
            result.blocked = true;
            return;
        }
        if (node.is(AstNodeId::CompilerCallOne) && firstToken[node.tokRef().get()].id == TokenId::CompilerOffsetOf)
        {
            result.blocked = true;
            return;
        }

        SmallVector<AstNodeRef> children;
        node.collectChildrenFromAst(children, ast);
        for (const AstNodeRef childRef : children)
            measureAutoInlineBody(result, ast, childRef, firstToken);
    }
}

// Measure the body's stable parse-time cost. Sema rewrites body nodes in place, so the same walk
// run during analysis can read nodes whose id and payload disagree.
uint32_t Parser::computeAutoInlineBodyCost(bool& outHasCalls, AstNodeRef bodyRef, TokenRef bodyStartRef) const
{
    outHasCalls = false;
    if (bodyRef.isInvalid() || bodyStartRef.isInvalid())
        return UINT32_MAX;

    const TokenRef bodyEndRef = ref();
    if (bodyEndRef.isInvalid() || bodyEndRef.get() < bodyStartRef.get())
        return UINT32_MAX;

    AutoInlineBodyShape shape;
    measureAutoInlineBody(shape, *ast_, bodyRef, firstToken_);
    outHasCalls = shape.numCalls != 0;
    if (shape.blocked)
        return UINT32_MAX;

    const uint64_t cost = static_cast<uint64_t>(bodyEndRef.get() - bodyStartRef.get()) +
                          static_cast<uint64_t>(shape.numCalls) * K_AUTO_INLINE_CALL_PENALTY;
    return cost > UINT32_MAX ? UINT32_MAX : static_cast<uint32_t>(cost);
}

AstNodeRef Parser::parseClosureArg()
{
    EnumFlags flags = AstClosureArgumentFlagsE::Zero;

    // `var` marks the captured copy writable. Without it the copy is read-only, so a closure
    // that keeps state says so at the capture rather than at the first assignment.
    const TokenRef tokStart = ref();
    if (consumeIf(TokenId::KwdVar).isValid())
        flags.add(AstClosureArgumentFlagsE::Var);
    if (consumeIf(TokenId::SymAmpersand).isValid())
        flags.add(AstClosureArgumentFlagsE::Address);

    auto [nodeRef, nodePtr]    = ast_->makeNode<AstNodeId::ClosureArgument>(tokStart);
    nodePtr->flags()           = flags;
    nodePtr->tokAliasNameRef   = TokenRef::invalid();
    nodePtr->nodeIdentifierRef = AstNodeRef::invalid();

    if (is(TokenId::Identifier) && nextIs(TokenId::SymEqual))
    {
        // Capture alias form: `name = expr`. During the expression parse, stop at
        // the capture-list delimiter depth instead of letting commas/pipes inside
        // nested calls or aggregates prematurely end the capture.
        nodePtr->tokAliasNameRef = consume();
        consumeAssert(TokenId::SymEqual);
        const PushContextFlags pushContext(this, ParserContextFlagsE::InClosureCapture);

        const uint32_t savedStopDepthParen   = closureCaptureStopDepthParen_;
        const uint32_t savedStopDepthBracket = closureCaptureStopDepthBracket_;
        const uint32_t savedStopDepthCurly   = closureCaptureStopDepthCurly_;
        closureCaptureStopDepthParen_        = depthParen_;
        closureCaptureStopDepthBracket_      = depthBracket_;
        closureCaptureStopDepthCurly_        = depthCurly_;
        nodePtr->nodeIdentifierRef           = parseExpression();
        closureCaptureStopDepthParen_        = savedStopDepthParen;
        closureCaptureStopDepthBracket_      = savedStopDepthBracket;
        closureCaptureStopDepthCurly_        = savedStopDepthCurly;
        return nodeRef;
    }

    const PushContextFlags pushContext(this, ParserContextFlagsE::InClosureCapture);
    nodePtr->nodeIdentifierRef = parseQualifiedIdentifier();

    return nodeRef;
}

AstNodeRef Parser::parseLambdaParam(bool isType)
{
    AstNodeRef     nodeType;
    TokenRef       tokName  = TokenRef::invalid();
    EnumFlags      flags    = AstLambdaParamFlagsE::Zero;
    const TokenRef tokStart = ref();

    if (is(TokenId::CompilerType))
    {
        nodeType = parseCompilerTypeExpr();
    }
    else if (is(TokenId::Identifier) && nextIs(TokenId::SymColon))
    {
        tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_before);
        flags.add(AstLambdaParamFlagsE::Named);
        consumeAssert(TokenId::SymColon);
        nodeType = parseType();
    }
    else if (isType && is(TokenId::Identifier) && nextIs(TokenId::SymEqual))
    {
        tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_before);
        flags.add(AstLambdaParamFlagsE::Named);
        nodeType = AstNodeRef::invalid();
    }
    else if (isType && is(TokenId::SymQuestion) && nextIs(TokenId::SymEqual))
    {
        tokName = consume();
        flags.add(AstLambdaParamFlagsE::Named);
        nodeType = AstNodeRef::invalid();
    }
    else if (isType)
    {
        nodeType = parseType();
    }
    else
    {
        nodeType = AstNodeRef::invalid();
        if (is(TokenId::Identifier))
        {
            tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_before);
            flags.add(AstLambdaParamFlagsE::Named);
        }
        else if (is(TokenId::SymQuestion))
        {
            tokName = consume();
            flags.add(AstLambdaParamFlagsE::Named);
        }
        else if (!is(TokenId::SymEqual))
        {
            nodeType = parseType();
        }
    }

    // Normal parameter
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::LambdaParam>(flags.has(AstLambdaParamFlagsE::Named) ? tokName : tokStart);
    nodePtr->flags()        = flags;
    nodePtr->nodeTypeRef    = nodeType;

    const TokenRef tokAssign = consumeIf(TokenId::SymEqual);
    if (tokAssign.isValid())
        nodePtr->nodeDefaultValueRef = parseInitializerExpression(tokAssign);
    else
        nodePtr->nodeDefaultValueRef = AstNodeRef::invalid();

    return nodeRef;
}

AstNodeRef Parser::parseLambdaArgumentExpr()
{
    return parseLambdaParam(false);
}

AstNodeRef Parser::parseLambdaExpression()
{
    EnumFlags      flags    = AstFunctionFlagsE::Zero;
    const TokenRef tokStart = ref();

    if (consumeIf(TokenId::KwdMtd).isValid())
        flags.add(AstFunctionFlagsE::Method);
    else
        consumeAssert(TokenId::KwdFunc);

    // Capture
    SpanRef captureArgs = SpanRef::invalid();
    if (is(TokenId::SymPipe))
    {
        flags.add(AstFunctionFlagsE::Closure);
        captureArgs = parseCompoundContent(AstNodeId::ClosureExpr, TokenId::SymPipe);
    }
    else if (consumeIf(TokenId::SymPipePipe).isValid())
    {
        flags.add(AstFunctionFlagsE::Closure);
    }
    else if (flags.has(AstFunctionFlagsE::Method))
    {
        // A method lambda needs a capture list so sema can bind the receiver. Keep
        // producing a closure node after the diagnostic to preserve recovery shape.
        raiseError(DiagnosticId::parser_err_mtd_missing_capture, tokStart);
        flags.add(AstFunctionFlagsE::Closure);
    }

    // Arguments
    const SpanRef args = parseCompoundContent(AstNodeId::FunctionExpr, TokenId::SymLeftParen);

    // Return type
    AstNodeRef returnType = AstNodeRef::invalid();
    if (consumeIf(TokenId::SymMinusGreater).isValid())
        returnType = parseType();

    // Can raise errors
    if (consumeIf(TokenId::KwdFail).isValid())
        flags.add(AstFunctionFlagsE::Fallible);

    // Body
    AstNodeRef body = AstNodeRef::invalid();
    if (is(TokenId::SymLeftCurly))
        body = parseFunctionBody();
    else
    {
        expectAndConsume(TokenId::SymEqualGreater, DiagnosticId::parser_err_expected_token_before);
        body = parseExpression();
    }

    if (flags.has(AstFunctionFlagsE::Closure))
    {
        auto [nodeRef, nodePtr]     = ast_->makeNode<AstNodeId::ClosureExpr>(ref());
        nodePtr->flags()            = flags;
        nodePtr->nodeCaptureArgsRef = captureArgs;
        nodePtr->spanArgsRef        = args;
        nodePtr->nodeReturnTypeRef  = returnType;
        nodePtr->nodeBodyRef        = body;
        return nodeRef;
    }

    auto [nodeRef, nodePtr]    = ast_->makeNode<AstNodeId::FunctionExpr>(ref());
    nodePtr->flags()           = flags;
    nodePtr->spanArgsRef       = args;
    nodePtr->nodeReturnTypeRef = returnType;
    nodePtr->nodeBodyRef       = body;
    return nodeRef;
}

AstNodeRef Parser::parseFunctionDecl(const bool isInterfaceDefinition)
{
    EnumFlags flags = AstFunctionFlagsE::Zero;
    if (consumeIf(TokenId::KwdMtd).isValid())
        flags.add(AstFunctionFlagsE::Method);
    else
    {
        const TokenRef tokFunc = consumeAssert(TokenId::KwdFunc);
        if (isInterfaceDefinition)
        {
            raiseError(DiagnosticId::parser_err_interface_method_must_use_mtd, tokFunc);
            flags.add(AstFunctionFlagsE::Method);
        }
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FunctionDecl>(ref());
    nodePtr->flags()        = flags;

    // Generic parameters
    if (is(TokenId::SymLeftParen))
        nodePtr->spanGenericParamsRef = parseCompoundContent(AstNodeId::GenericParamList, TokenId::SymLeftParen);
    else
        nodePtr->spanGenericParamsRef = SpanRef::invalid();

    // Modifiers
    if (consumeIf(TokenId::KwdConst).isValid())
        flags.add(AstFunctionFlagsE::Const);
    if (consumeIf(TokenId::KwdImpl).isValid())
        flags.add(AstFunctionFlagsE::Impl);

    // Name
    nodePtr->tokNameRef = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
    if (ast_->srcView().isRuntimeFile() && !hasContextFlag(ParserContextFlagsE::InNamespace) && nodePtr->tokNameRef.isValid())
    {
        const Token& tok     = ast_->srcView().token(nodePtr->tokNameRef);
        nodePtr->intrinsicId = Token::intrinsicFromName(tok.string(ast_->srcView()));
    }

    // Parameters. A '#fwd' parameter makes this declaration dual-instantiated: the
    // enclosing statement is re-parsed to emit a copy variant and a move variant.
    const bool         savedFwdSeen   = fwdSeenParam_;
    const bool         savedFwdActive = fwdDeclActive_;
    const FwdParseMode savedFwdMode   = fwdCurMode_;
    fwdSeenParam_                     = false;
    nodePtr->nodeParamsRef            = parseFunctionParamList();
    if (fwdSeenParam_)
    {
        // '#fwd' is implemented by reparsing the enclosing declaration twice. The
        // parser records the trigger here; the statement-level driver performs the
        // second pass with the move-reference mode enabled.
        fwdDeclActive_  = true;
        fwdCurMode_     = fwdPassMode_;
        fwdStmtTrigger_ = true;
    }

    // Return type
    if (consumeIf(TokenId::SymMinusGreater).isValid())
        nodePtr->nodeReturnTypeRef = parseType();
    else
        nodePtr->nodeReturnTypeRef = AstNodeRef::invalid();

    // Fallible marker
    if (consumeIf(TokenId::KwdFail).isValid())
        flags.add(AstFunctionFlagsE::Fallible);
    nodePtr->flags() = flags;

    // Constraints
    SmallVector<AstNodeRef> whereRefs;
    while (is(TokenId::KwdWhere))
    {
        const Token*     loopStartToken = curToken_;
        const AstNodeRef whereRef       = parseConstraint();
        if (whereRef.isValid())
            whereRefs.push_back(whereRef);
        if (loopStartToken == curToken_)
            consume();
    }

    if (whereRefs.empty())
        nodePtr->spanConstraintsRef = SpanRef::invalid();
    else
        nodePtr->spanConstraintsRef = ast_->pushSpan(whereRefs.span());

    // Body
    const TokenRef bodyStartRef = ref();
    if (consumeIf(TokenId::SymEqualGreater).isValid())
    {
        nodePtr->addFlag(AstFunctionFlagsE::Short);
        nodePtr->nodeBodyRef = parseExpression();
    }
    else if (is(TokenId::SymLeftCurly))
    {
        nodePtr->nodeBodyRef = parseFunctionBody();
    }
    else
    {
        nodePtr->nodeBodyRef = AstNodeRef::invalid();
    }

    bool autoInlineHasCalls = false;
    nodePtr->autoInlineCost = computeAutoInlineBodyCost(autoInlineHasCalls, nodePtr->nodeBodyRef, bodyStartRef);
    if (autoInlineHasCalls)
        nodePtr->addFlag(AstFunctionFlagsE::AutoInlineHasCalls);

    fwdSeenParam_  = savedFwdSeen;
    fwdDeclActive_ = savedFwdActive;
    fwdCurMode_    = savedFwdMode;
    return nodeRef;
}

AstNodeRef Parser::parseAttrDecl()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AttrDecl>(consume());
    nodePtr->tokNameRef     = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);

    const bool savedFwdSeen = fwdSeenParam_;
    fwdSeenParam_           = false;
    nodePtr->nodeParamsRef  = parseFunctionParamList();
    if (fwdSeenParam_)
        raiseError(DiagnosticId::parser_err_fwd_param_only, nodePtr->tokNameRef);
    fwdSeenParam_ = savedFwdSeen;
    return nodeRef;
}

AstNodeRef Parser::parseFunctionParam()
{
    if (is(TokenId::SymAttrStart))
    {
        const AstNodeRef  nodeRef = parseCompound<AstNodeId::AttributeList>(TokenId::SymAttrStart);
        AstAttributeList* nodePtr = ast_->node<AstNodeId::AttributeList>(nodeRef);
        nodePtr->nodeBodyRef      = parseFunctionParam();
        return nodeRef;
    }

    if (is(TokenId::KwdConst))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FunctionParamMe>(consume());
        nodePtr->addFlag(AstFunctionParamMeFlagsE::Const);
        expectAndConsume(TokenId::KwdMe, DiagnosticId::parser_err_expected_token_before);
        return nodeRef;
    }

    if (is(TokenId::KwdMe))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FunctionParamMe>(consume());
        return nodeRef;
    }

    const PushContextFlags ctx(this, ParserContextFlagsE::InFunctionParam);
    return parseVarDecl();
}

AstNodeRef Parser::parseFunctionParamList()
{
    return parseCompound<AstNodeId::FunctionParamList>(TokenId::SymLeftParen);
}

AstNodeRef Parser::parseFunctionBody()
{
    return parseCompound<AstNodeId::EmbeddedBlock>(TokenId::SymLeftCurly);
}

AstNodeRef Parser::parseFunctionArguments(AstNodeRef nodeExpr)
{
    // Tag the callee expression so sema can allow overload sets without walking parent nodes.
    // Only a few node kinds need this context.
    if (nodeExpr.isValid())
    {
        AstNode& calleeNode = ast_->node(nodeExpr);
        switch (calleeNode.id())
        {
            case AstNodeId::Identifier:
                calleeNode.cast<AstIdentifier>().addFlag(AstIdentifierFlagsE::CallCallee);
                break;
            case AstNodeId::MemberAccessExpr:
                calleeNode.cast<AstMemberAccessExpr>().addFlag(AstMemberAccessExprFlagsE::CallCallee);
                break;
            case AstNodeId::AutoMemberAccessExpr:
                calleeNode.cast<AstAutoMemberAccessExpr>().addFlag(AstAutoMemberAccessExprFlagsE::CallCallee);
                break;
            default:
                break;
        }
    }

    const TokenRef         tokCallRef = ref();
    const PushContextFlags ctxFlags(this, ParserContextFlagsE::InCallArgument);
    const SpanRef          spanArgsRef = parseCompoundContent(AstNodeId::NamedArgumentList, TokenId::SymLeftParen);
    return lowerSwagIntrinsicCall(nodeExpr, spanArgsRef, tokCallRef);
}

TokenId Parser::swagIntrinsicId(const AstNodeRef nodeExpr) const
{
    if (nodeExpr.isInvalid())
        return TokenId::Invalid;

    const auto* member = ast_->node(nodeExpr).safeCast<AstMemberAccessExpr>();
    if (!member)
        return TokenId::Invalid;

    const auto* left  = ast_->node(member->nodeLeftRef).safeCast<AstIdentifier>();
    const auto* right = ast_->node(member->nodeRightRef).safeCast<AstIdentifier>();
    if (!left || !right)
        return TokenId::Invalid;

    const SourceView& srcView  = ast_->srcView();
    const Token&      leftTok  = srcView.token(left->tokRef());
    const Token&      rightTok = srcView.token(right->tokRef());
    if (leftTok.string(srcView) != "Swag")
        return TokenId::Invalid;

    return Token::intrinsicFromName(rightTok.string(srcView));
}

AstNodeRef Parser::lowerSwagIntrinsicValue(const AstNodeRef nodeExpr)
{
    const TokenId intrinsicId = swagIntrinsicId(nodeExpr);
    if (intrinsicId != TokenId::IntrinsicIndex)
        return nodeExpr;

    const auto& member            = ast_->node(nodeExpr).cast<AstMemberAccessExpr>();
    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicValue>(ast_->node(member.nodeRightRef).tokRef());
    nodePtr->intrinsicId          = intrinsicId;
    return nodeRef;
}

AstNodeRef Parser::lowerSwagIntrinsicCall(const AstNodeRef nodeExpr, const SpanRef spanArgsRef, const TokenRef tokCallRef)
{
    const TokenId intrinsicId = swagIntrinsicId(nodeExpr);
    if (intrinsicId == TokenId::Invalid)
    {
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CallExpr>(tokCallRef);
        nodePtr->nodeExprRef          = nodeExpr;
        nodePtr->spanChildrenRef      = spanArgsRef;
        if (hasContextFlag(ParserContextFlagsE::InAttribute))
            nodePtr->addFlag(AstCallExprFlagsE::AttributeContext);
        return nodeRef;
    }

    SmallVector<AstNodeRef> args;
    ast_->appendNodes(args, spanArgsRef);
    const auto&    member     = ast_->node(nodeExpr).cast<AstMemberAccessExpr>();
    const TokenRef tokNameRef = ast_->node(member.nodeRightRef).tokRef();

    auto requireArgs = [&](const uint32_t count) {
        if (args.size() == count)
            return;
        const DiagnosticId id       = args.size() < count ? DiagnosticId::parser_err_too_few_arguments : DiagnosticId::parser_err_too_many_arguments;
        const AstNodeRef   errorRef = args.size() > count ? args[count] : AstNodeRef::invalid();
        const TokenRef     endRef   = errorRef.isValid() ? ast_->node(errorRef).tokRef() : tokCallRef;
        reportArgumentCountError(id, tokNameRef, endRef, count, static_cast<uint32_t>(args.size())).report(*ctx_);
    };

    switch (intrinsicId)
    {
        case TokenId::IntrinsicCountOf:
        {
            requireArgs(1);
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CountOfExpr>(tokNameRef);
            nodePtr->nodeExprRef    = args.empty() ? AstNodeRef::invalid() : args[0];
            return nodeRef;
        }

        case TokenId::IntrinsicKindOf:
        case TokenId::IntrinsicDataOf:
        case TokenId::IntrinsicIsSet:
        case TokenId::IntrinsicMakeAny:
        case TokenId::IntrinsicMakeSlice:
        case TokenId::IntrinsicMakeString:
        case TokenId::IntrinsicMakeInterface:
        case TokenId::IntrinsicIs:
        case TokenId::IntrinsicAs:
        case TokenId::IntrinsicTableOf:
        {
            uint32_t count = 1;
            if (intrinsicId == TokenId::IntrinsicMakeAny || intrinsicId == TokenId::IntrinsicMakeSlice ||
                intrinsicId == TokenId::IntrinsicMakeString || intrinsicId == TokenId::IntrinsicIs || intrinsicId == TokenId::IntrinsicTableOf)
                count = 2;
            else if (intrinsicId == TokenId::IntrinsicMakeInterface || intrinsicId == TokenId::IntrinsicAs)
                count = 3;
            requireArgs(count);
            auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::IntrinsicCall>(tokNameRef);
            nodePtr->intrinsicId     = intrinsicId;
            nodePtr->spanChildrenRef = spanArgsRef;
            return nodeRef;
        }

        case TokenId::IntrinsicInit:
        {
            if (args.empty() || args.size() > 2)
                requireArgs(args.empty() ? 1 : 2);
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicInit>(tokNameRef);
            nodePtr->nodeWhatRef    = args.empty() ? AstNodeRef::invalid() : args[0];
            nodePtr->nodeCountRef   = args.size() > 1 ? args[1] : AstNodeRef::invalid();
            if (is(TokenId::SymLeftParen))
                nodePtr->spanArgsRef = parseCompoundContent(AstNodeId::UnnamedArgumentList, TokenId::SymLeftParen);
            else
                nodePtr->spanArgsRef.setInvalid();
            return nodeRef;
        }

        case TokenId::IntrinsicDrop:
        case TokenId::IntrinsicPostCopy:
        case TokenId::IntrinsicPostMove:
        {
            if (args.empty() || args.size() > 2)
                requireArgs(args.empty() ? 1 : 2);

            if (intrinsicId == TokenId::IntrinsicDrop)
            {
                auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicDrop>(tokNameRef);
                nodePtr->nodeWhatRef    = args.empty() ? AstNodeRef::invalid() : args[0];
                nodePtr->nodeCountRef   = args.size() > 1 ? args[1] : AstNodeRef::invalid();
                return nodeRef;
            }
            if (intrinsicId == TokenId::IntrinsicPostCopy)
            {
                auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicPostCopy>(tokNameRef);
                nodePtr->nodeWhatRef    = args.empty() ? AstNodeRef::invalid() : args[0];
                nodePtr->nodeCountRef   = args.size() > 1 ? args[1] : AstNodeRef::invalid();
                return nodeRef;
            }

            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicPostMove>(tokNameRef);
            nodePtr->nodeWhatRef    = args.empty() ? AstNodeRef::invalid() : args[0];
            nodePtr->nodeCountRef   = args.size() > 1 ? args[1] : AstNodeRef::invalid();
            return nodeRef;
        }

        default:
        {
            uint32_t numRequiredArgs = UINT32_MAX;
            switch (intrinsicId)
            {
                case TokenId::IntrinsicBreakpoint:
                case TokenId::IntrinsicGetContext:
                case TokenId::IntrinsicCompiler:
                case TokenId::IntrinsicRtFlags:
                case TokenId::IntrinsicProcessInfos:
                case TokenId::IntrinsicArgs:
                case TokenId::IntrinsicModules:
                case TokenId::IntrinsicGvtd:
                case TokenId::IntrinsicJit:
                    numRequiredArgs = 0;
                    break;

                case TokenId::IntrinsicAssert:
                case TokenId::IntrinsicSetContext:
                case TokenId::IntrinsicAbs:
                case TokenId::IntrinsicSqrt:
                case TokenId::IntrinsicSin:
                case TokenId::IntrinsicCos:
                case TokenId::IntrinsicTan:
                case TokenId::IntrinsicSinh:
                case TokenId::IntrinsicCosh:
                case TokenId::IntrinsicTanh:
                case TokenId::IntrinsicASin:
                case TokenId::IntrinsicACos:
                case TokenId::IntrinsicATan:
                case TokenId::IntrinsicLog:
                case TokenId::IntrinsicLog2:
                case TokenId::IntrinsicLog10:
                case TokenId::IntrinsicFloor:
                case TokenId::IntrinsicCeil:
                case TokenId::IntrinsicTrunc:
                case TokenId::IntrinsicRound:
                case TokenId::IntrinsicExp:
                case TokenId::IntrinsicExp2:
                case TokenId::IntrinsicByteSwap:
                case TokenId::IntrinsicBitCountNz:
                case TokenId::IntrinsicBitCountTz:
                case TokenId::IntrinsicBitCountLz:
                case TokenId::IntrinsicVecSplat:
                case TokenId::IntrinsicVecWidenLo:
                case TokenId::IntrinsicVecWidenHi:
                case TokenId::IntrinsicVecMask:
                case TokenId::IntrinsicVecAny:
                case TokenId::IntrinsicVecAll:
                case TokenId::IntrinsicVecReduceAdd:
                case TokenId::IntrinsicVecReduceMin:
                case TokenId::IntrinsicVecReduceMax:
                case TokenId::IntrinsicVecReduceAnd:
                case TokenId::IntrinsicVecReduceOr:
                case TokenId::IntrinsicVecReduceXor:
                case TokenId::IntrinsicVecTruncS32:
                    numRequiredArgs = 1;
                    break;

                case TokenId::IntrinsicCompilerError:
                case TokenId::IntrinsicCompilerWarning:
                case TokenId::IntrinsicPanic:
                case TokenId::IntrinsicSafetyPanic:
                case TokenId::IntrinsicStringCmp:
                case TokenId::IntrinsicMin:
                case TokenId::IntrinsicMax:
                case TokenId::IntrinsicRol:
                case TokenId::IntrinsicRor:
                case TokenId::IntrinsicPow:
                case TokenId::IntrinsicATan2:
                case TokenId::IntrinsicAtomicXchg:
                case TokenId::IntrinsicAtomicXor:
                case TokenId::IntrinsicAtomicOr:
                case TokenId::IntrinsicAtomicAnd:
                case TokenId::IntrinsicAtomicAdd:
                case TokenId::IntrinsicVecSatAdd:
                case TokenId::IntrinsicVecSatSub:
                case TokenId::IntrinsicVecPackUS:
                case TokenId::IntrinsicVecPackSS:
                case TokenId::IntrinsicVecInterleaveLo:
                case TokenId::IntrinsicVecInterleaveHi:
                case TokenId::IntrinsicVecAvgR:
                case TokenId::IntrinsicVecMadd:
                case TokenId::IntrinsicVecMaddUBS:
                case TokenId::IntrinsicVecSad:
                case TokenId::IntrinsicVecMulHi:
                case TokenId::IntrinsicVecGather:
                case TokenId::IntrinsicVecPerm:
                case TokenId::IntrinsicVecShuffle:
                    numRequiredArgs = 2;
                    break;

                case TokenId::IntrinsicMemCpy:
                case TokenId::IntrinsicMemMove:
                case TokenId::IntrinsicMemSet:
                case TokenId::IntrinsicMemCmp:
                case TokenId::IntrinsicTypeCmp:
                case TokenId::IntrinsicAtomicCmpXchg:
                case TokenId::IntrinsicMulAdd:
                case TokenId::IntrinsicVecShuffle2:
                case TokenId::IntrinsicVecAlign:
                case TokenId::IntrinsicVecSelect:
                    numRequiredArgs = 3;
                    break;

                default:
                    break;
            }

            if (numRequiredArgs != UINT32_MAX)
                requireArgs(numRequiredArgs);
            else if (intrinsicId == TokenId::IntrinsicPrint && args.empty())
                reportArgumentCountError(DiagnosticId::parser_err_too_few_arguments, tokNameRef, tokCallRef, 1, 0, true).report(*ctx_);

            auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::IntrinsicCallExpr>(tokNameRef);
            nodePtr->intrinsicId     = intrinsicId;
            nodePtr->nodeExprRef     = member.nodeRightRef;
            nodePtr->spanChildrenRef = spanArgsRef;
            ast_->node(member.nodeRightRef).cast<AstIdentifier>().addFlag(AstIdentifierFlagsE::CallCallee);
            if (hasContextFlag(ParserContextFlagsE::InAttribute))
                nodePtr->addFlag(AstCallExprFlagsE::AttributeContext);
            return nodeRef;
        }
    }
}

SWC_END_NAMESPACE();
