#include "pch.h"
#include "Lexer/SourceFile.h"
#include "Parser/AstNode.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseGenericParam()
{
    bool        isConstant  = false;
    bool        isType      = false;
    const auto& tknConstVar = tok();

    if (consumeIf(TokenId::KwdConst))
        isConstant = true;
    else if (consumeIf(TokenId::KwdVar))
        isType = true;

    const auto tknName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);

    AstNodeRef nodeType = INVALID_REF;
    if (consumeIf(TokenId::SymColon))
    {
        if (isType)
        {
            auto diag = reportError(DiagnosticId::parser_err_gen_param_type, ref() - 1);
            diag.last().addSpan(tknConstVar.location(*ctx_, *file_), DiagnosticId::parser_note_gen_param_type, DiagnosticSeverity::Note);
            diag.addElement(DiagnosticId::parser_help_gen_param_type);
            diag.report(*ctx_);
        }

        isConstant = true;
        nodeType   = parseType();
    }

    AstNodeRef nodeAssign = INVALID_REF;
    if (consumeIf(TokenId::SymEqual))
    {
        if (isConstant)
            nodeAssign = parseExpression();
        else
            nodeAssign = parseType();
    }

    if (isConstant)
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::GenericValueParam>();
        nodePtr->tokName        = tknName;
        nodePtr->nodeAssign     = nodeAssign;
        nodePtr->nodeType       = nodeType;
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::GenericTypeParam>();
    nodePtr->tokName        = tknName;
    nodePtr->nodeAssign     = nodeAssign;
    return nodeRef;
}

AstNodeRef Parser::parseDecompositionDecl(AstVarDecl::Flags flags)
{
    const auto openRef = consume(TokenId::SymLeftParen);

    TokenRef tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
    if (invalid(tokName))
        return INVALID_REF;

    // All names
    SmallVector<TokenRef> tokNames;
    tokNames.push_back(tokName);
    while (consumeIf(TokenId::SymComma))
    {
        tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
        if (invalid(tokName))
            return INVALID_REF;
        tokNames.push_back(tokName);
    }

    expectAndConsumeClosingFor(TokenId::SymLeftParen, openRef);
    expectAndConsume(TokenId::SymEqual, DiagnosticId::parser_err_expected_token_fam);

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::DecompositionDecl>();
    nodePtr->addFlag(flags);
    nodePtr->nodeInit  = parseInitializerExpression();
    nodePtr->spanNames = ast_->store_.push_span(tokNames.span());
    return nodeRef;
}

AstNodeRef Parser::parseVarDecl()
{
    AstVarDecl::Flags flags = AstVarDecl::FlagsE::Zero;
    if (consumeIf(TokenId::KwdConst))
        flags.add(AstVarDecl::FlagsE::Const);
    else if (consumeIf(TokenId::KwdVar))
        flags.add(AstVarDecl::FlagsE::Var);
    else if (consumeIf(TokenId::KwdLet))
        flags.add(AstVarDecl::FlagsE::Let);

    if (is(TokenId::SymLeftParen))
        return parseDecompositionDecl(flags);

    // All names
    TokenRef tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
    if (invalid(tokName))
        return INVALID_REF;

    SmallVector<TokenRef> tokNames;
    tokNames.push_back(tokName);

    while (consumeIf(TokenId::SymComma))
    {
        tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
        if (invalid(tokName))
            return INVALID_REF;
        tokNames.push_back(tokName);
    }

    AstNodeRef nodeType = INVALID_REF;
    AstNodeRef nodeInit = INVALID_REF;

    if (consumeIf(TokenId::SymColon))
        nodeType = parseType();
    if (consumeIf(TokenId::SymEqual))
        nodeInit = parseInitializerExpression();

    if (tokNames.size() == 1)
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::VarDecl>();
        nodePtr->addFlag(flags);
        nodePtr->tokName  = tokNames[0];
        nodePtr->nodeType = nodeType;
        nodePtr->nodeInit = nodeInit;
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::VarMultiDecl>();
    nodePtr->addFlag(flags);
    nodePtr->tokNames = ast_->store_.push_span(tokNames.span());
    nodePtr->nodeType = nodeType;
    nodePtr->nodeInit = nodeInit;
    return nodeRef;
}

SWC_END_NAMESPACE()
