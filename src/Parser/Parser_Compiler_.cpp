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
        nodePtr->nodeBody       = parseCompound(AstNodeId::FuncBody, TokenId::SymLeftCurly);
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
        nodePtr->nodeBody       = parseCompound(AstNodeId::FuncBody, TokenId::SymLeftCurly);
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

    if (tokStr == "skip")
    {
        nodePtr->mode = AstCompilerGlobal::Mode::Skip;
        file_->addFlag(FileFlagsE::LexOnly);
        consume();
    }
    else if (tokStr == "generated")
    {
        nodePtr->mode = AstCompilerGlobal::Mode::Generated;
        consume();
    }
    else if (tokStr == "export")
    {
        nodePtr->mode = AstCompilerGlobal::Mode::Export;
        consume();
    }
    else
    {
        // @skip
        skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlagsE::EolBefore);
    }

    expectEndStatement();
    return nodeRef;
}

SWC_END_NAMESPACE()
