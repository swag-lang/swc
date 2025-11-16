#include "pch.h"
#include "Lexer/SourceFile.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseCompilerFunc()
{
    const auto what = id();

    if (nextIs(TokenId::SymLeftCurly))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerFunc>();
        nodePtr->tokName        = consume();
        nodePtr->nodeBody       = parseFunctionBody();
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

AstNodeRef Parser::parseCompilerMessageFunc()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerMessageFunc>();
    consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->nodeParam = parseExpression();
    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    nodePtr->nodeBody = parseFunctionBody();
    return nodeRef;
}

AstNodeRef Parser::parseCompilerExpr()
{
    if (nextIs(TokenId::SymLeftCurly))
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerEmbeddedFunc>();
        nodePtr->tokName        = consume();
        nodePtr->nodeBody       = parseFunctionBody();
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

template<AstNodeId ID>
AstNodeRef Parser::parseCompilerIfStmt()
{
    if (consumeIf(TokenId::KwdDo).isValid())
    {
        if (is(TokenId::SymLeftCurly))
        {
            raiseError(DiagnosticId::parser_err_unexpected_do_block, ref().offset(-1));
            return parseCompound<ID>(TokenId::SymLeftCurly);
        }

        return parseCompoundValue(ID);
    }

    if (is(TokenId::SymLeftCurly))
        return parseCompound<ID>(TokenId::SymLeftCurly);

    const auto diag = reportError(DiagnosticId::parser_err_expected_do_block, ref().offset(-1));
    diag.report(*ctx_);
    return AstNodeRef::invalid();
}

template AstNodeRef Parser::parseCompilerIf<AstNodeId::AggregateBody>();
template AstNodeRef Parser::parseCompilerIf<AstNodeId::InterfaceBody>();
template AstNodeRef Parser::parseCompilerIf<AstNodeId::EnumBody>();
template AstNodeRef Parser::parseCompilerIf<AstNodeId::TopLevelBlock>();
template AstNodeRef Parser::parseCompilerIf<AstNodeId::EmbeddedBlock>();

template<AstNodeId ID>
AstNodeRef Parser::parseCompilerIf()
{
    SWC_ASSERT(isAny(TokenId::CompilerIf, TokenId::CompilerElseIf));
    const auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerIf>();
    consume();

    // Parse the condition expression
    nodePtr->nodeCondition = parseExpression();
    if (nodePtr->nodeCondition.isInvalid())
        skipTo({TokenId::KwdDo, TokenId::SymLeftCurly});

    nodePtr->nodeIfBlock = parseCompilerIfStmt<ID>();

    // Parse optional 'else' or 'elif' block
    if (is(TokenId::CompilerElseIf))
        nodePtr->nodeElseBlock = parseCompilerIf<ID>();
    else if (consumeIf(TokenId::CompilerElse).isValid())
        nodePtr->nodeElseBlock = parseCompilerIfStmt<ID>();
    else
        nodePtr->nodeElseBlock.setInvalid();

    return nodeRef;
}

AstNodeRef Parser::parseCompilerDependencies()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::Dependencies>();
    consume();
    nodePtr->nodeBody = parseCompound<AstNodeId::TopLevelBlock>(TokenId::SymLeftCurly);
    return nodeRef;
}

AstNodeRef Parser::parseCompilerTypeOf()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerCallUnary>();
    nodePtr->tokName        = consume();

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    if (isAny(TokenId::KwdFunc, TokenId::KwdMtd))
        nodePtr->nodeArg1 = parseType();
    else
        nodePtr->nodeArg1 = parseExpression();

    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseCompilerGlobal()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerGlobal>();
    consume();

    const auto tokStr = tok().string(ast_->lexOut());

    // @temp
    if (tokStr == "testerror" || tokStr == "testerrors" || tokStr == "testwarning" || tokStr == "testwarnings" || tokStr == "testpass")
    {
        skipTo({TokenId::SymSemiColon, TokenId::SymRightCurly}, SkipUntilFlagsE::EolBefore);
        out_->addFlag(ParserOutFlagsE::GlobalSkip);

        return nodeRef;
    }

    if (tokStr == Token::toName(TokenId::KwdSkip))
    {
        nodePtr->mode     = AstCompilerGlobal::Mode::Skip;
        nodePtr->nodeMode = AstNodeRef::invalid();
        out_->addFlag(ParserOutFlagsE::GlobalSkip);
        consume();
    }
    else if (tokStr == Token::toName(TokenId::KwdSkipFmt))
    {
        nodePtr->mode     = AstCompilerGlobal::Mode::SkipFmt;
        nodePtr->nodeMode = AstNodeRef::invalid();
        consume();
    }
    else if (tokStr == Token::toName(TokenId::KwdGenerated))
    {
        nodePtr->mode     = AstCompilerGlobal::Mode::Generated;
        nodePtr->nodeMode = AstNodeRef::invalid();
        consume();
    }
    else if (tokStr == Token::toName(TokenId::KwdExport))
    {
        nodePtr->mode     = AstCompilerGlobal::Mode::Export;
        nodePtr->nodeMode = AstNodeRef::invalid();
        consume();
    }
    else if (is(TokenId::SymAttrStart))
    {
        nodePtr->mode      = AstCompilerGlobal::Mode::AttributeList;
        nodePtr->nodeMode  = parseCompound<AstNodeId::AttributeList>(TokenId::SymAttrStart);
        const auto attrPtr = ast_->node<AstNodeId::AttributeList>(nodePtr->nodeMode);
        attrPtr->nodeBody.setInvalid();
    }
    else if (is(TokenId::KwdPublic))
    {
        nodePtr->mode     = AstCompilerGlobal::Mode::AccessPublic;
        nodePtr->nodeMode = AstNodeRef::invalid();
        consume();
    }
    else if (is(TokenId::KwdInternal))
    {
        nodePtr->mode     = AstCompilerGlobal::Mode::AccessInternal;
        nodePtr->nodeMode = AstNodeRef::invalid();
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

    return nodeRef;
}

AstNodeRef Parser::parseCompilerImport()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerImport>();
    consume();

    const auto openRef = ref();

    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);
    nodePtr->tokModuleName = expectAndConsume(TokenId::StringLine, DiagnosticId::parser_err_expected_token_before);
    nodePtr->tokLocation   = TokenRef::invalid();
    nodePtr->tokVersion    = TokenRef::invalid();

    if (consumeIf(TokenId::SymComma).isValid())
    {
        auto tokStr = tok().string(ast_->lexOut());
        if (tokStr == Token::toName(TokenId::KwdLocation))
        {
            consume();
            expectAndConsume(TokenId::SymColon, DiagnosticId::parser_err_expected_token_before);
            nodePtr->tokLocation = expectAndConsume(TokenId::StringLine, DiagnosticId::parser_err_expected_token_before);
            if (consumeIf(TokenId::SymComma).isValid())
            {
                tokStr = tok().string(ast_->lexOut());
                if (tokStr == Token::toName(TokenId::KwdVersion))
                {
                    consume();
                    expectAndConsume(TokenId::SymColon, DiagnosticId::parser_err_expected_token_before);
                    nodePtr->tokVersion = expectAndConsume(TokenId::StringLine, DiagnosticId::parser_err_expected_token_before);
                }
            }
        }
    }

    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseCompilerScope()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerScope>();
    consume();

    const auto openRef = ref();
    if (consumeIf(TokenId::SymLeftParen).isValid())
    {
        nodePtr->tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_before);
        expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    }

    nodePtr->nodeBody = parseEmbeddedStmt();
    return nodeRef;
}

AstNodeRef Parser::parseCompilerMacro()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerMacro>();
    consumeAssert(TokenId::CompilerMacro);
    nodePtr->nodeBody = parseCompound<AstNodeId::EmbeddedBlock>(TokenId::SymLeftCurly);
    return nodeRef;
}

AstNodeRef Parser::parseCompilerInject()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::CompilerInject>();
    consumeAssert(TokenId::CompilerInject);

    const auto openRef = ref();
    expectAndConsume(TokenId::SymLeftParen, DiagnosticId::parser_err_expected_token_before);

    nodePtr->nodeExpr = parseExpression();
    nodePtr->nodeReplaceBreak.setInvalid();
    nodePtr->nodeReplaceContinue.setInvalid();

    while (consumeIf(TokenId::SymComma).isValid())
    {
        // Replacement for 'break'
        if (consumeIf(TokenId::KwdBreak).isValid())
        {
            if (nodePtr->nodeReplaceBreak.isValid())
            {
                raiseError(DiagnosticId::parser_err_inject_instruction_done, ref());
                skipTo({TokenId::SymRightParen, TokenId::SymLeftParen});
                continue;
            }

            expectAndConsume(TokenId::SymEqual, DiagnosticId::parser_err_expected_token_before);
            nodePtr->nodeReplaceBreak = parseEmbeddedStmt();
            continue;
        }

        // Replacement for 'continue'
        if (consumeIf(TokenId::KwdContinue).isValid())
        {
            if (nodePtr->nodeReplaceContinue.isValid())
            {
                raiseError(DiagnosticId::parser_err_inject_instruction_done, ref());
                skipTo({TokenId::SymRightParen, TokenId::SymLeftParen});
                continue;
            }

            expectAndConsume(TokenId::SymEqual, DiagnosticId::parser_err_expected_token_before);
            nodePtr->nodeReplaceContinue = parseEmbeddedStmt();
            continue;
        }

        raiseError(DiagnosticId::parser_err_inject_invalid_instruction, ref());
        skipTo({TokenId::SymRightParen});
        break;
    }

    expectAndConsumeClosing(TokenId::SymRightParen, openRef);

    return nodeRef;
}

AstNodeRef Parser::parseCompilerUp()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::AncestorIdentifier>();
    consumeAssert(TokenId::CompilerUp);

    const auto openRef = ref();
    if (consumeIf(TokenId::SymLeftParen).isValid())
    {
        nodePtr->nodeValue = parseExpression();
        expectAndConsumeClosing(TokenId::SymRightParen, openRef);
    }
    else
        nodePtr->nodeValue.setInvalid();

    nodePtr->nodeIdent = parseQualifiedIdentifier();
    return nodeRef;
}

SWC_END_NAMESPACE()
