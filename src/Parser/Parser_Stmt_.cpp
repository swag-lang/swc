#include "pch.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"
#include "Report/Diagnostic.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseTopLevelCall()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::TopLevelCall>();
    nodePtr->nodeIdentifier = parseQualifiedIdentifier();
    nodePtr->nodeArgs       = parseCompound<AstNodeId::NamedArgList>(TokenId::SymLeftParen);
    expectEndStatement();
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
        nodePtr->nodeNamespace = parseNamespace();
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::UsingDecl>();
    consume();
    nodePtr->spanChildren = parseCompoundContent(AstNodeId::UsingDecl, TokenId::Invalid, true);
    expectEndStatement();
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
    else if (is(TokenId::Identifier))
        nodePtr->nodeExpr = parseQualifiedIdentifier();
    else
        nodePtr->nodeExpr = parsePrimaryExpression();

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
    expectEndStatement();
    return nodeRef;
}

AstNodeRef Parser::parseUnreachable()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Unreachable>();
    consume();
    expectEndStatement();
    return nodeRef;
}

AstNodeRef Parser::parseContinue()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Continue>();
    consume();
    expectEndStatement();
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
        expectEndStatement();
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Break>();
    consume();
    expectEndStatement();
    return nodeRef;
}

AstNodeRef Parser::parseFallThrough()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::FallThrough>();
    consume();
    expectEndStatement();
    return nodeRef;
}

AstNodeRef Parser::parseDefer()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::DeferDecl>();
    consume();
    nodePtr->modifierFlags = parseModifiers();
    nodePtr->nodeBody      = parseEmbeddedStmt();
    expectEndStatement();
    return nodeRef;
}

AstNodeRef Parser::parseIfStmt()
{
    if (consumeIf(TokenId::KwdDo).isValid())
    {
        if (is(TokenId::SymLeftCurly))
        {
            raiseError(DiagnosticId::parser_err_unexpected_do_block, ref().offset(-1));
            return parseCompound(AstNodeId::EmbeddedBlock, TokenId::SymLeftCurly);
        }

        return parseEmbeddedStmt();
    }

    if (is(TokenId::SymLeftCurly))
        return parseCompound(AstNodeId::EmbeddedBlock, TokenId::SymLeftCurly);

    const auto diag = reportError(DiagnosticId::parser_err_expected_do_block, ref().offset(-1));
    diag.report(*ctx_);
    return AstNodeRef::invalid();
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

        nodePtr->nodeIfBlock = parseIfStmt();
        if (is(TokenId::KwdElseIf))
            nodePtr->nodeElseBlock = parseIf();
        else if (consumeIf(TokenId::KwdElse).isValid())
            nodePtr->nodeElseBlock = parseIfStmt();

        return nodeRef;
    }

    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::If>();
    consume();

    // Parse the condition expression
    nodePtr->nodeCondition = parseExpression();
    if (nodePtr->nodeCondition.isInvalid())
        skipTo({TokenId::KwdDo, TokenId::SymLeftCurly});

    nodePtr->nodeIfBlock = parseIfStmt();
    if (is(TokenId::KwdElseIf))
        nodePtr->nodeElseBlock = parseIf();
    else if (consumeIf(TokenId::KwdElse).isValid())
        nodePtr->nodeElseBlock = parseIfStmt();

    return nodeRef;
}

AstNodeRef Parser::parseWith()
{
    if (nextIsAny(TokenId::KwdVar, TokenId::KwdLet))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::VarWith>();
        consume();
        nodePtr->nodeVar  = parseVarDecl();
        nodePtr->nodeBody = parseEmbeddedStmt();
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::With>();
    consume();
    nodePtr->nodeExpr = parseExpression();
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
    
    expectEndStatement();
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

    expectEndStatement();
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

    expectEndStatement();
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

    expectEndStatement();
    return nodeRef;
}

AstNodeRef Parser::parseTopLevelStmt()
{
    switch (id())
    {
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
            return parseAttributeList(AstNodeId::TopLevelBlock);

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
            expectEndStatement();
            return nodeRef;
        }

        case TokenId::CompilerLoad:
        case TokenId::CompilerForeignLib:
            return parseCompilerCallUnary();

        case TokenId::KwdFunc:
        case TokenId::KwdMtd:
            return parseFuncDecl();

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

        case TokenId::SymAttrStart:
            return parseAttributeList(AstNodeId::EmbeddedBlock);

        case TokenId::KwdFunc:
        case TokenId::KwdMtd:
            return parseFuncDecl();

        case TokenId::KwdConst:
        case TokenId::KwdVar:
        case TokenId::KwdLet:
        {
            AstNodeRef nodeRef;
            if (nextIs(TokenId::SymLeftParen))
                nodeRef = parseDecompositionDecl();
            else
                nodeRef = parseVarDecl();
            expectEndStatement();
            return nodeRef;
        }

        case TokenId::KwdWith:
            return parseWith();

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

        case TokenId::KwdDefer:
            return parseDefer();

        case TokenId::KwdIf:
            return parseIf();

        case TokenId::IntrinsicInit:
            return parseIntrinsicInit();
        case TokenId::IntrinsicDrop:
            return parseIntrinsicDrop();
        case TokenId::IntrinsicPostCopy:
            return parseIntrinsicPostCopy();
        case TokenId::IntrinsicPostMove:
            return parseIntrinsicPostMove();

        case TokenId::SymDot:
        case TokenId::Identifier:
        case TokenId::KwdFor:
        case TokenId::KwdForeach:
        case TokenId::CompilerInject:
        case TokenId::CompilerMacro:
        case TokenId::KwdWhile:
        case TokenId::KwdSwitch:
        case TokenId::KwdCase:
        case TokenId::KwdDefault:
        case TokenId::KwdMe:
        case TokenId::KwdUsing:
        case TokenId::KwdDRef:
        case TokenId::KwdDiscard:
        case TokenId::KwdThrow:
        case TokenId::KwdAssume:
        case TokenId::KwdCatch:
        case TokenId::KwdTry:
        case TokenId::KwdTryCatch:
        case TokenId::IntrinsicPrint:
        case TokenId::KwdAlias:
        case TokenId::CompilerUp:
        case TokenId::SymLeftParen:
        case TokenId::CompilerUniq0:
        case TokenId::CompilerUniq1:
        case TokenId::CompilerUniq2:
        case TokenId::CompilerAlias0:
        case TokenId::CompilerAlias1:
        case TokenId::CompilerAlias2:
        case TokenId::IntrinsicGetContext:
        case TokenId::IntrinsicDbgAlloc:
        case TokenId::IntrinsicProcessInfos:
            // @skip
            skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlagsE::EolBefore);
            return AstNodeRef::invalid();

        default:
            // raiseError(DiagnosticId::parser_err_unexpected_token, ref());
            skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlagsE::EolBefore);
            return AstNodeRef::invalid();
    }
}

SWC_END_NAMESPACE()
