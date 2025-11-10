#include "pch.h"

#include "Lexer/SourceFile.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseCompilerFunc()
{
    const auto what = id();

    if (nextIs(TokenId::SymLeftCurly))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerFunc>();
        nodePtr->tokName        = consume();
        nodePtr->nodeBody       = parseCompound(AstNodeId::FunctionBody, TokenId::SymLeftCurly);
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerShortFunc>();
    nodePtr->tokName        = consume();
    if (what == TokenId::CompilerAst)
        nodePtr->nodeBody = parseExpression();
    else
        nodePtr->nodeBody = parseEmbeddedStmt();
    return nodeRef;
}

AstNodeRef Parser::parseCompilerExpr()
{
    if (nextIs(TokenId::SymLeftCurly))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerEmbeddedFunc>();
        nodePtr->tokName        = consume();
        nodePtr->nodeBody       = parseCompound(AstNodeId::FunctionBody, TokenId::SymLeftCurly);
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerExpr>();
    nodePtr->tokName        = consume();
    nodePtr->nodeExpr       = parseExpression();
    return nodeRef;
}

AstNodeRef Parser::parseCompilerTypeExpr()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerTypeExpr>();
    consume();
    nodePtr->nodeType = parseType();
    return nodeRef;
}

AstNodeRef Parser::parseCompilerIfStmt(AstNodeId blockNodeId)
{
    if (consumeIf(TokenId::KwdDo) != INVALID_REF)
    {
        if (is(TokenId::SymLeftCurly))
        {
            raiseError(DiagnosticId::parser_err_unexpected_do_block, ref() - 1);
            return parseCompound(blockNodeId, TokenId::SymLeftCurly);
        }

        return parseCompoundValue(blockNodeId);
    }

    if (is(TokenId::SymLeftCurly))
    {
        return parseCompound(blockNodeId, TokenId::SymLeftCurly);
    }

    const auto diag = reportError(DiagnosticId::parser_err_expected_do_block, ref() - 1);
    diag.report(*ctx_);
    return INVALID_REF;
}

AstNodeRef Parser::parseCompilerIf(AstNodeId blockNodeId)
{
    SWC_ASSERT(isAny(TokenId::CompilerIf, TokenId::CompilerElseIf));
    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerIf>();
    nodePtr->tokIf                = consume();

    // Parse the condition expression
    nodePtr->nodeCondition = parseExpression();
    if (invalid(nodePtr->nodeCondition))
        skipTo({TokenId::KwdDo, TokenId::SymLeftCurly});

    nodePtr->nodeIfBlock = parseCompilerIfStmt(blockNodeId);

    // Parse optional 'else' or 'elif' block
    if (is(TokenId::CompilerElseIf))
        nodePtr->nodeElseBlock = parseCompilerIf(blockNodeId);
    else if (consumeIf(TokenId::CompilerElse) != INVALID_REF)
        nodePtr->nodeElseBlock = parseCompilerIfStmt(blockNodeId);

    return nodeRef;
}

AstNodeRef Parser::parseCompilerDependencies()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Dependencies>();
    consume();
    nodePtr->nodeBody = parseCompound(AstNodeId::TopLevelBlock, TokenId::SymLeftCurly);
    return nodeRef;
}

AstNodeRef Parser::parseCompilerTypeOf()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstInternalCallUnaryBase>(AstNodeId::CompilerCallUnary);
    nodePtr->tokName        = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    if (isAny(TokenId::KwdFunc, TokenId::KwdMtd))
        nodePtr->nodeArg1 = parseType();
    else
        nodePtr->nodeArg1 = parseExpression();

    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseCompilerGlobal()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerGlobal>();
    consume();

    const auto tokStr = tok().string(*file_);

    // @temp
    if (tokStr == "testerror" || tokStr == "testerrors" || tokStr == "testwarning" || tokStr == "testwarnings" || tokStr == "testpass")
    {
        skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlagsE::EolBefore);
        file_->addFlag(FileFlagsE::LexOnly);
        expectEndStatement();
        return nodeRef;
    }

    if (tokStr == Token::toName(TokenId::KwdSkip))
    {
        nodePtr->mode     = AstCompilerGlobal::Mode::Skip;
        nodePtr->nodeMode = INVALID_REF;
        file_->addFlag(FileFlagsE::LexOnly);
        consume();
    }
    else if (tokStr == Token::toName(TokenId::KwdSkipFmt))
    {
        nodePtr->mode     = AstCompilerGlobal::Mode::SkipFmt;
        nodePtr->nodeMode = INVALID_REF;
        consume();
    }
    else if (tokStr == Token::toName(TokenId::KwdGenerated))
    {
        nodePtr->mode     = AstCompilerGlobal::Mode::Generated;
        nodePtr->nodeMode = INVALID_REF;
        consume();
    }
    else if (tokStr == Token::toName(TokenId::KwdExport))
    {
        nodePtr->mode     = AstCompilerGlobal::Mode::Export;
        nodePtr->nodeMode = INVALID_REF;
        consume();
    }
    else if (is(TokenId::SymAttrStart))
    {
        nodePtr->mode     = AstCompilerGlobal::Mode::AttributeList;
        nodePtr->nodeMode = parseCompound(AstNodeId::AttributeList, TokenId::SymAttrStart);
    }
    else if (is(TokenId::KwdPublic))
    {
        nodePtr->mode     = AstCompilerGlobal::Mode::AccessPublic;
        nodePtr->nodeMode = INVALID_REF;
        consume();
    }
    else if (is(TokenId::KwdInternal))
    {
        nodePtr->mode     = AstCompilerGlobal::Mode::AccessInternal;
        nodePtr->nodeMode = INVALID_REF;
        consume();
    }
    else if (is(TokenId::KwdNamespace))
    {
        nodePtr->mode = AstCompilerGlobal::Mode::Namespace;
        consume();
        nodePtr->nodeMode = parseQualifiedIdentifier();
    }
    else if (is(TokenId::CompilerIf))
    {
        nodePtr->mode = AstCompilerGlobal::Mode::CompilerIf;
        consume();
        nodePtr->nodeMode = parseExpression();
    }
    else if (is(TokenId::KwdUsing))
    {
        nodePtr->mode     = AstCompilerGlobal::Mode::Using;
        nodePtr->nodeMode = parseUsing();
    }
    else
    {
        raiseError(DiagnosticId::parser_err_unexpected_token, ref());
        skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlagsE::EolBefore);
    }

    expectEndStatement();
    return nodeRef;
}

AstNodeRef Parser::parseCompilerImport()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerImport>();
    consume();

    const auto openRef = ref();

    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->tokModuleName = expectAndConsume(TokenId::StringLine, DiagnosticId::parser_err_expected_token_before);
    nodePtr->tokLocation   = INVALID_REF;
    nodePtr->tokVersion    = INVALID_REF;

    if (consumeIf(TokenId::SymComma) != INVALID_REF)
    {
        auto tokStr = tok().string(*file_);
        if (tokStr == Token::toName(TokenId::KwdLocation))
        {
            consume();
            expectAndConsume(TokenId::SymColon, DiagnosticId::parser_err_expected_token_before);
            nodePtr->tokLocation = expectAndConsume(TokenId::StringLine, DiagnosticId::parser_err_expected_token_before);
            if (consumeIf(TokenId::SymComma) != INVALID_REF)
            {
                tokStr = tok().string(*file_);
                if (tokStr == Token::toName(TokenId::KwdVersion))
                {
                    consume();
                    expectAndConsume(TokenId::SymColon, DiagnosticId::parser_err_expected_token_before);
                    nodePtr->tokVersion = expectAndConsume(TokenId::StringLine, DiagnosticId::parser_err_expected_token_before);
                }
            }
        }
    }

    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);
    expectEndStatement();
    return nodeRef;
}

SWC_END_NAMESPACE()
