#include "pch.h"

#include "Lexer/SourceFile.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseTopLevelCall()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::TopLevelCall>();
    nodePtr->nodeIdentifier = parseQualifiedIdentifier();
    nodePtr->nodeArgs       = parseCompound<AstNodeId::NamedArgList>(TokenId::SymLeftParen);

    return nodeRef;
}

AstNodeRef Parser::parseGlobalAccessModifier()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AccessModifier>();
    nodePtr->tokAccess      = consume();
    nodePtr->nodeWhat       = parseTopLevelStmt();
    return nodeRef;
}

AstNodeRef Parser::parseUsing()
{
    if (nextIs(TokenId::KwdNamespace))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::UsingNamespace>();
        consume();
        nodePtr->nodeName = parseNamespace();
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::UsingDecl>();
    consume();
    nodePtr->spanChildren = parseCompoundContent(AstNodeId::UsingDecl, TokenId::Invalid, true);

    return nodeRef;
}

AstNodeRef Parser::parseConstraint()
{
    if (nextIs(TokenId::SymLeftCurly))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ConstraintBlock>();
        nodePtr->tokConstraint  = consume();
        nodePtr->spanChildren   = parseCompoundContent(AstNodeId::EmbeddedBlock, TokenId::SymLeftCurly);
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ConstraintExpr>();
    nodePtr->tokConstraint  = consume();
    nodePtr->nodeExpr       = parseExpression();
    return nodeRef;
}

AstNodeRef Parser::parseAlias()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Alias>();
    consume();
    nodePtr->tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
    expectAndConsume(TokenId::SymEqual, DiagnosticId::parser_err_expected_token_fam);

    if (isAny(TokenId::CompilerDeclType, TokenId::SymLeftBracket, TokenId::SymLeftCurly, TokenId::KwdFunc, TokenId::KwdMtd))
        nodePtr->nodeExpr = parseType();
    else if (Token::isType(id()))
        nodePtr->nodeExpr = parseType();
    else
        nodePtr->nodeExpr = parseExpression();

    return nodeRef;
}

AstNodeRef Parser::parseReturn()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Return>();
    consume();
    if (is(TokenId::SymSemiColon) || tok().startsLine())
        nodePtr->nodeExpr.setInvalid();
    else
        nodePtr->nodeExpr = parseExpression();

    return nodeRef;
}

AstNodeRef Parser::parseUnreachable()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Unreachable>();
    consume();

    return nodeRef;
}

AstNodeRef Parser::parseContinue()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Continue>();
    consume();

    return nodeRef;
}

AstNodeRef Parser::parseBreak()
{
    if (nextIs(TokenId::KwdTo))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ScopedBreak>();
        consumeAssert(TokenId::KwdBreak);
        consumeAssert(TokenId::KwdTo);
        nodePtr->tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);

        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Break>();
    consume();

    return nodeRef;
}

AstNodeRef Parser::parseFallThrough()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FallThrough>();
    consume();

    return nodeRef;
}

AstNodeRef Parser::parseDefer()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::DeferDecl>();
    consume();
    nodePtr->modifierFlags = parseModifiers();
    nodePtr->nodeBody      = parseEmbeddedStmt();

    return nodeRef;
}

AstNodeRef Parser::parseIf()
{
    if (nextIsAny(TokenId::KwdVar, TokenId::KwdLet, TokenId::KwdConst))
    {
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::VarIf>();
        consume();

        // Parse the variable declaration and the constraint
        nodePtr->nodeVar = parseVarDecl();
        if (consumeIf(TokenId::KwdWhere).isValid())
            nodePtr->nodeWhere = parseExpression();
        else
            nodePtr->nodeWhere.setInvalid();

        nodePtr->nodeIfBlock = parseDoCurlyBlock();
        if (is(TokenId::KwdElseIf))
            nodePtr->nodeElseBlock = parseIf();
        else if (consumeIf(TokenId::KwdElse).isValid())
            nodePtr->nodeElseBlock = parseDoCurlyBlock();
        else
            nodePtr->nodeElseBlock.setInvalid();

        return nodeRef;
    }

    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::If>();
    consume();

    // Parse the condition expression
    nodePtr->nodeCondition = parseExpression();
    if (nodePtr->nodeCondition.isInvalid())
        skipTo({TokenId::KwdDo, TokenId::SymLeftCurly});

    nodePtr->nodeIfBlock = parseDoCurlyBlock();
    if (is(TokenId::KwdElseIf))
        nodePtr->nodeElseBlock = parseIf();
    else if (consumeIf(TokenId::KwdElse).isValid())
        nodePtr->nodeElseBlock = parseDoCurlyBlock();
    else
        nodePtr->nodeElseBlock.setInvalid();

    return nodeRef;
}

AstNodeRef Parser::parseWith()
{
    if (nextIsAny(TokenId::KwdVar, TokenId::KwdLet))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::WithVar>();
        consume();
        nodePtr->nodeVar  = parseVarDecl();
        nodePtr->nodeBody = parseEmbeddedStmt();
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::With>();
    consume();
    nodePtr->nodeExpr = parseAffectStmt();
    nodePtr->nodeBody = parseEmbeddedStmt();
    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicInit()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicInit>();
    consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->nodeWhat = parseExpression();
    if (consumeIf(TokenId::SymComma).isValid())
        nodePtr->nodeCount = parseExpression();
    else
        nodePtr->nodeCount.setInvalid();
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    if (is(TokenId::SymLeftParen))
        nodePtr->spanArgs = parseCompoundContent(AstNodeId::UnnamedArgList, TokenId::SymLeftParen);
    else
        nodePtr->spanArgs.setInvalid();

    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicDrop()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicDrop>();
    consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->nodeWhat = parseExpression();
    if (consumeIf(TokenId::SymComma).isValid())
        nodePtr->nodeCount = parseExpression();
    else
        nodePtr->nodeCount.setInvalid();
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicPostCopy()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicPostCopy>();
    consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->nodeWhat = parseExpression();
    if (consumeIf(TokenId::SymComma).isValid())
        nodePtr->nodeCount = parseExpression();
    else
        nodePtr->nodeCount.setInvalid();
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseIntrinsicPostMove()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::IntrinsicPostMove>();
    consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->nodeWhat = parseExpression();
    if (consumeIf(TokenId::SymComma).isValid())
        nodePtr->nodeCount = parseExpression();
    else
        nodePtr->nodeCount.setInvalid();
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseWhile()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::While>();
    consume();
    nodePtr->nodeExpr = parseExpression();
    nodePtr->nodeBody = parseDoCurlyBlock();
    return nodeRef;
}

AstNodeRef Parser::parseForCpp()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ForCpp>();
    consumeAssert(TokenId::KwdFor);

    nodePtr->nodeVarDecl = parseVarDecl();
    expectAndConsume(TokenId::SymSemiColon, DiagnosticId::parser_err_expected_token_before);

    nodePtr->nodeExpr = parseExpression();
    expectAndConsume(TokenId::SymSemiColon, DiagnosticId::parser_err_expected_token_before);

    nodePtr->nodePostStmt = parseEmbeddedStmt();
    nodePtr->nodeBody     = parseDoCurlyBlock();
    return nodeRef;
}

AstNodeRef Parser::parseForInfinite()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ForInfinite>();
    consumeAssert(TokenId::KwdFor);
    nodePtr->nodeBody = parseDoCurlyBlock();
    return nodeRef;
}

AstNodeRef Parser::parseForLoop()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ForLoop>();
    consumeAssert(TokenId::KwdFor);

    nodePtr->modifierFlags = parseModifiers();

    nodePtr->tokName.setInvalid();
    if (isNot(TokenId::SymLeftParen))
    {
        if (nextIs(TokenId::KwdIn))
        {
            nodePtr->tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
            consumeAssert(TokenId::KwdIn);
        }
    }

    nodePtr->nodeExpr = parseRangeExpression();

    if (consumeIf(TokenId::KwdWhere).isValid())
        nodePtr->nodeWhere = parseExpression();
    else
        nodePtr->nodeWhere.setInvalid();

    nodePtr->nodeBody = parseDoCurlyBlock();
    return nodeRef;
}

AstNodeRef Parser::parseFor()
{
    if (nextIs(TokenId::KwdVar))
        return parseForCpp();
    if (nextIsAny(TokenId::SymLeftCurly, TokenId::KwdDo))
        return parseForInfinite();
    return parseForLoop();
}

AstNodeRef Parser::parseForeach()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Foreach>();
    consumeAssert(TokenId::KwdForeach);

    // Specialization
    nodePtr->tokSpecialization = consumeIf(TokenId::SharpIdentifier);

    // Additional flags
    nodePtr->modifierFlags = parseModifiers();

    SmallVector<TokenRef> tokNames;

    // By address
    if (consumeIf(TokenId::SymAmpersand).isValid())
    {
        nodePtr->addFlag(AstForeach::FlagsE::ByAddress);
        const auto tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
        tokNames.push_back(tokName);
    }
    else if (nextIsAny(TokenId::KwdIn, TokenId::SymComma))
    {
        const auto tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
        tokNames.push_back(tokName);
    }

    while (consumeIf(TokenId::SymComma).isValid())
    {
        auto tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
        tokNames.push_back(tokName);
    }

    nodePtr->spanNames = ast_->store().push_span(tokNames.span());
    if (!tokNames.empty())
        expectAndConsume(TokenId::KwdIn, DiagnosticId::parser_err_expected_token_before);

    nodePtr->nodeExpr = parseExpression();

    if (consumeIf(TokenId::KwdWhere).isValid())
        nodePtr->nodeWhere = parseExpression();
    else
        nodePtr->nodeWhere.setInvalid();

    nodePtr->nodeBody = parseDoCurlyBlock();
    return nodeRef;
}

AstNodeRef Parser::parseTryCatch()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::TryCatch>();
    nodePtr->tokOp          = consume();
    if (is(TokenId::SymLeftCurly))
        nodePtr->nodeBody = parseCompound<AstNodeId::EmbeddedBlock>(TokenId::SymLeftCurly);
    else
        nodePtr->nodeBody = parseExpression();
    return nodeRef;
}

AstNodeRef Parser::parseThrow()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Throw>();
    consumeAssert(TokenId::KwdThrow);
    nodePtr->nodeExpr = parseExpression();
    return nodeRef;
}

AstNodeRef Parser::parseDiscard()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Discard>();
    consumeAssert(TokenId::KwdDiscard);
    nodePtr->nodeExpr = parseExpression();
    return nodeRef;
}

AstNodeRef Parser::parseSwitchCaseDefault()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::SwitchCase>();
    if (consumeIf(TokenId::KwdCase).isValid())
    {
        SmallVector<AstNodeRef> nodeExpressions;
        auto                    nodeExpr = parseRangeExpression();
        nodeExpressions.push_back(nodeExpr);
        while (consumeIf(TokenId::SymComma).isValid())
        {
            nodeExpr = parseRangeExpression();
            nodeExpressions.push_back(nodeExpr);
        }

        nodePtr->spanExpr = ast_->store().push_span(nodeExpressions.span());
    }
    else
    {
        consume();
        nodePtr->spanExpr.setInvalid();
    }

    if (consumeIf(TokenId::KwdWhere).isValid())
        nodePtr->nodeWhere = parseExpression();
    else
        nodePtr->nodeWhere.setInvalid();

    expectAndConsume(TokenId::SymColon, DiagnosticId::parser_err_expected_token_before);
    return nodeRef;
}

AstNodeRef Parser::parseSwitch()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Switch>();
    consumeAssert(TokenId::KwdSwitch);

    if (isNot(TokenId::SymLeftCurly))
        nodePtr->nodeExpr = parseExpression();
    else
        nodePtr->nodeExpr.setInvalid();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftCurly, DiagnosticId::parser_err_expected_token_before);

    SmallVector<AstNodeRef> nodeChildren;
    SmallVector<AstNodeRef> nodeStmts;
    AstSwitchCase*          currentCase = nullptr;

    while (isNot(TokenId::SymRightCurly) && !atEnd())
    {
        switch (id())
        {
            case TokenId::KwdDefault:
            case TokenId::KwdCase:
            {
                if (currentCase)
                    currentCase->spanChildren = ast_->store().push_span(nodeStmts.span());
                nodeStmts.clear();

                auto caseRef = parseSwitchCaseDefault();
                nodeChildren.push_back(caseRef);
                currentCase = ast_->node<AstNodeId::SwitchCase>(caseRef);
                break;
            }

            default:
            {
                auto stmtRef = parseEmbeddedStmt();
                nodeStmts.push_back(stmtRef);
                break;
            }
        }
    }

    if (currentCase)
        currentCase->spanChildren = ast_->store().push_span(nodeStmts.span());

    nodePtr->spanChildren = ast_->store().push_span(nodeChildren.span());
    expectAndConsumeClosing(TokenId::SymRightCurly, openRef);
    return nodeRef;
}

AstNodeRef Parser::parseFile()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::File>();

    // #global must be first
    SmallVector<AstNodeRef> globals;
    while (is(TokenId::CompilerGlobal))
    {
        auto global = parseCompilerGlobal();
        if (out_->hasFlag(ParserOutFlagsE::GlobalSkip))
        {
            nodePtr->spanGlobals.setInvalid();
            nodePtr->spanChildren.setInvalid();
            return nodeRef;
        }

        if (global.isValid())
            globals.push_back(global);
    }

    nodePtr->spanGlobals = ast_->store().push_span(globals.span());

    // All the rest
    nodePtr->spanChildren = parseCompoundContent(AstNodeId::TopLevelBlock, TokenId::Invalid);
    return nodeRef;
}

AstNodeRef Parser::parseNamespace()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Namespace>();
    consume();
    nodePtr->nodeName = parseQualifiedIdentifier();
    if (nodePtr->nodeName.isInvalid())
        skipTo({TokenId::SymLeftCurly});
    nodePtr->spanChildren = parseCompoundContent(AstNodeId::TopLevelBlock, TokenId::SymLeftCurly);
    return nodeRef;
}

AstNodeRef Parser::parseDoCurlyBlock()
{
    if (consumeIf(TokenId::KwdDo).isValid())
    {
        if (is(TokenId::SymLeftCurly))
        {
            raiseError(DiagnosticId::parser_err_unexpected_do_block, ref().offset(-1));
            return parseCompound<AstNodeId::EmbeddedBlock>(TokenId::SymLeftCurly);
        }

        return parseEmbeddedStmt();
    }

    if (is(TokenId::SymLeftCurly))
        return parseCompound<AstNodeId::EmbeddedBlock>(TokenId::SymLeftCurly);

    const auto diag = reportError(DiagnosticId::parser_err_expected_do_block, ref().offset(-1));
    diag.report(*ctx_);
    return AstNodeRef::invalid();
}

AstNodeRef Parser::parseAffectStmt()
{
    AstNodeRef nodeLeft;

    // Decomposition
    if (is(TokenId::SymLeftParen))
    {
        const auto openRef            = consume();
        const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::MultiAffect>();
        nodePtr->addFlag(AstMultiAffect::FlagsE::Decomposition);
        if (consumeIf(TokenId::SymQuestion).isValid())
            nodeLeft = AstNodeRef::invalid();
        else
            nodeLeft = parseExpression();

        SmallVector<AstNodeRef> nodeAffects;
        nodeAffects.push_back(nodeLeft);
        while (consumeIf(TokenId::SymComma).isValid())
        {
            if (consumeIf(TokenId::SymQuestion).isValid())
                nodeAffects.push_back(AstNodeRef::invalid());
            else
                nodeAffects.push_back(parseExpression());
        }

        expectAndConsumeClosing(TokenId::SymRightParen, openRef);

        nodePtr->spanChildren = ast_->store().push_span(nodeAffects.span());
        nodeLeft              = nodeRef;
    }
    else
    {
        // Simple affectation
        nodeLeft = parseExpression();
        if (nodeLeft.isInvalid())
            return AstNodeRef::invalid();

        // Multi affectations
        if (is(TokenId::SymComma))
        {
            const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::MultiAffect>();
            SmallVector<AstNodeRef> nodeAffects;
            nodeAffects.push_back(nodeLeft);
            while (consumeIf(TokenId::SymComma).isValid())
            {
                const auto nodeExpr = parseExpression();
                nodeAffects.push_back(nodeExpr);
            }

            nodePtr->spanChildren = ast_->store().push_span(nodeAffects.span());
            nodeLeft              = nodeRef;
        }
    }

    // Operation
    if (isAny(TokenId::SymEqual,
              TokenId::SymPlusEqual,
              TokenId::SymMinusEqual,
              TokenId::SymAsteriskEqual,
              TokenId::SymSlashEqual,
              TokenId::SymAmpersandEqual,
              TokenId::SymVerticalEqual,
              TokenId::SymCircumflexEqual,
              TokenId::SymPercentEqual,
              TokenId::SymLowerLowerEqual,
              TokenId::SymGreaterGreaterEqual))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AffectStmt>();
        nodePtr->tokOp          = consume();
        nodePtr->nodeLeft       = nodeLeft;
        nodePtr->modifierFlags  = parseModifiers();
        nodePtr->nodeRight      = parseExpression();
        return nodeRef;
    }

    return nodeLeft;
}

AstNodeRef Parser::parseTopLevelStmt()
{
    switch (id())
    {
        case TokenId::CompilerAssert:
            return parseCompilerCallUnary();
        case TokenId::CompilerError:
            return parseCompilerCallUnary();
        case TokenId::CompilerWarning:
            return parseCompilerCallUnary();
        case TokenId::CompilerPrint:
            return parseCompilerCallUnary();
        case TokenId::CompilerIf:
            return parseCompilerIf<AstNodeId::TopLevelBlock>();

        case TokenId::SymLeftCurly:
            return parseCompound<AstNodeId::TopLevelBlock>(TokenId::SymLeftCurly);
        case TokenId::SymRightCurly:
            raiseError(DiagnosticId::parser_err_unexpected_token, ref());
            return AstNodeRef::invalid();

        case TokenId::SymSemiColon:
            consume();
            return AstNodeRef::invalid();

        case TokenId::KwdEnum:
            return parseEnumDecl();
        case TokenId::KwdUnion:
            return parseUnionDecl();
        case TokenId::KwdStruct:
            return parseStructDecl();
        case TokenId::KwdImpl:
            return parseImpl();

        case TokenId::CompilerFuncTest:
        case TokenId::CompilerFuncMain:
        case TokenId::CompilerFuncPreMain:
        case TokenId::CompilerFuncInit:
        case TokenId::CompilerFuncDrop:
        case TokenId::CompilerAst:
        case TokenId::CompilerRun:
            return parseCompilerFunc();

        case TokenId::CompilerFuncMessage:
            return parseCompilerMessageFunc();

        case TokenId::KwdNamespace:
            return parseNamespace();
        case TokenId::CompilerDependencies:
            return parseCompilerDependencies();

        case TokenId::SymAttrStart:
            return parseAttributeList<AstNodeId::TopLevelBlock>();

        case TokenId::KwdPublic:
        case TokenId::KwdInternal:
        case TokenId::KwdPrivate:
            return parseGlobalAccessModifier();

        case TokenId::KwdUsing:
            return parseUsing();

        case TokenId::KwdConst:
        case TokenId::KwdVar:
        {
            const AstNodeRef nodeRef = parseVarDecl();

            return nodeRef;
        }

        case TokenId::CompilerLoad:
        case TokenId::CompilerForeignLib:
            return parseCompilerCallUnary();

        case TokenId::KwdFunc:
        case TokenId::KwdMtd:
            return parseFunctionDecl();

        case TokenId::KwdAttr:
            return parseAttrDecl();

        case TokenId::KwdAlias:
            return parseAlias();

        case TokenId::CompilerImport:
            return parseCompilerImport();

        case TokenId::CompilerGlobal:
            raiseError(DiagnosticId::parser_err_misplaced_global, ref());
            return parseCompilerGlobal();

        case TokenId::KwdInterface:
            return parseInterfaceDecl();

        case TokenId::Identifier:
            return parseTopLevelCall();

        case TokenId::EndOfFile:
            return AstNodeRef::invalid();

        default:
            raiseError(DiagnosticId::parser_err_unexpected_token, ref());
            skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlagsE::EolBefore);
            return AstNodeRef::invalid();
    }
}

AstNodeRef Parser::parseEmbeddedStmt()
{
    switch (id())
    {
        case TokenId::CompilerAssert:
            return parseCompilerCallUnary();
        case TokenId::CompilerError:
            return parseCompilerCallUnary();
        case TokenId::CompilerWarning:
            return parseCompilerCallUnary();
        case TokenId::CompilerPrint:
            return parseCompilerCallUnary();
        case TokenId::CompilerIf:
            return parseCompilerIf<AstNodeId::EmbeddedBlock>();

        case TokenId::SymLeftCurly:
            return parseCompound<AstNodeId::EmbeddedBlock>(TokenId::SymLeftCurly);
        case TokenId::SymRightCurly:
            raiseError(DiagnosticId::parser_err_unexpected_token, ref());
            return AstNodeRef::invalid();

        case TokenId::SymSemiColon:
            consume();
            return AstNodeRef::invalid();

        case TokenId::KwdEnum:
            return parseEnumDecl();
        case TokenId::KwdUnion:
            return parseUnionDecl();
        case TokenId::KwdStruct:
            return parseStructDecl();

        case TokenId::IntrinsicBcBreakpoint:
            return parseIntrinsicCallZero();

        case TokenId::IntrinsicAssert:
        case TokenId::IntrinsicFree:
        case TokenId::IntrinsicCVaStart:
        case TokenId::IntrinsicCVaEnd:
        case TokenId::IntrinsicSetContext:
            return parseIntrinsicCallUnary();
        case TokenId::IntrinsicCompilerError:
        case TokenId::IntrinsicCompilerWarning:
        case TokenId::IntrinsicPanic:
        case TokenId::IntrinsicAtomicAdd:
            return parseIntrinsicCallBinary();
        case TokenId::IntrinsicMemCpy:
        case TokenId::IntrinsicMemMove:
        case TokenId::IntrinsicMemSet:
            return parseIntrinsicCallTernary();
        case TokenId::IntrinsicPrint:
            return parseIntrinsicCallVariadic();

        case TokenId::SymAttrStart:
            return parseAttributeList<AstNodeId::EmbeddedBlock>();

        case TokenId::KwdFunc:
        case TokenId::KwdMtd:
            return parseFunctionDecl();

        case TokenId::KwdConst:
        case TokenId::KwdVar:
        case TokenId::KwdLet:
        {
            AstNodeRef nodeRef;
            if (nextIs(TokenId::SymLeftParen))
                nodeRef = parseDecompositionDecl();
            else
                nodeRef = parseVarDecl();

            return nodeRef;
        }

        case TokenId::CompilerAst:
        case TokenId::CompilerRun:
            return parseCompilerFunc();

        case TokenId::KwdReturn:
            return parseReturn();

        case TokenId::KwdUnreachable:
            return parseUnreachable();
        case TokenId::KwdBreak:
            return parseBreak();
        case TokenId::KwdContinue:
            return parseContinue();
        case TokenId::KwdFallThrough:
            return parseFallThrough();

        case TokenId::CompilerScope:
            return parseCompilerScope();
        case TokenId::CompilerMacro:
            return parseCompilerMacro();
        case TokenId::CompilerInject:
            return parseCompilerInject();

        case TokenId::KwdWith:
            return parseWith();
        case TokenId::KwdDefer:
            return parseDefer();
        case TokenId::KwdIf:
            return parseIf();
        case TokenId::KwdWhile:
            return parseWhile();
        case TokenId::KwdForeach:
            return parseForeach();
        case TokenId::KwdSwitch:
            return parseSwitch();
        case TokenId::KwdFor:
            return parseFor();

        case TokenId::KwdUsing:
            return parseUsing();
        case TokenId::KwdAlias:
            return parseAlias();

        case TokenId::IntrinsicInit:
            return parseIntrinsicInit();
        case TokenId::IntrinsicDrop:
            return parseIntrinsicDrop();
        case TokenId::IntrinsicPostCopy:
            return parseIntrinsicPostCopy();
        case TokenId::IntrinsicPostMove:
            return parseIntrinsicPostMove();

        case TokenId::KwdAssume:
        case TokenId::KwdCatch:
        case TokenId::KwdTry:
        case TokenId::KwdTryCatch:
            return parseTryCatch();
        case TokenId::KwdThrow:
            return parseThrow();

        case TokenId::KwdDiscard:
            return parseDiscard();

        case TokenId::CompilerUp:
        case TokenId::Identifier:
        case TokenId::SymDot:
        case TokenId::SymLeftParen:
        case TokenId::KwdDRef:
        case TokenId::KwdMoveRef:
        case TokenId::IntrinsicGetContext:
        case TokenId::IntrinsicProcessInfos:
        case TokenId::IntrinsicDbgAlloc:
        case TokenId::IntrinsicSysAlloc:
        case TokenId::KwdMe:
        case TokenId::CompilerUniq0:
        case TokenId::CompilerUniq1:
        case TokenId::CompilerUniq2:
        case TokenId::CompilerUniq3:
        case TokenId::CompilerUniq4:
        case TokenId::CompilerUniq5:
        case TokenId::CompilerUniq6:
        case TokenId::CompilerUniq7:
        case TokenId::CompilerUniq8:
        case TokenId::CompilerUniq9:
        case TokenId::CompilerAlias0:
        case TokenId::CompilerAlias1:
        case TokenId::CompilerAlias2:
        case TokenId::CompilerAlias3:
        case TokenId::CompilerAlias4:
        case TokenId::CompilerAlias5:
        case TokenId::CompilerAlias6:
        case TokenId::CompilerAlias7:
        case TokenId::CompilerAlias8:
        case TokenId::CompilerAlias9:
            return parseAffectStmt();

        default:
            raiseError(DiagnosticId::parser_err_unexpected_token, ref());
            skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlagsE::EolBefore);
            return AstNodeRef::invalid();
    }
}

SWC_END_NAMESPACE()
