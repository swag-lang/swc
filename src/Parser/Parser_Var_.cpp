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

    if (consumeIf(TokenId::KwdConst) != INVALID_REF)
        isConstant = true;
    else if (consumeIf(TokenId::KwdVar) != INVALID_REF)
        isType = true;

    const auto tknName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);

    AstNodeRef nodeType = INVALID_REF;
    if (consumeIf(TokenId::SymColon) != INVALID_REF)
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
    if (consumeIf(TokenId::SymEqual) != INVALID_REF)
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

    // All names
    SmallVector<TokenRef> tokNames;
    while (!is(TokenId::SymRightParen))
    {
        TokenRef tokName = consumeIf(TokenId::SymQuestion);
        if (tokName == INVALID_REF)
        {
            tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
            if (invalid(tokName))
                return INVALID_REF;
        }

        tokNames.push_back(tokName);
        if (consumeIf(TokenId::SymComma) == INVALID_REF)
            break;
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
    if (consumeIf(TokenId::KwdConst) != INVALID_REF)
        flags.add(AstVarDecl::FlagsE::Const);
    else if (consumeIf(TokenId::KwdVar) != INVALID_REF)
        flags.add(AstVarDecl::FlagsE::Var);
    else if (consumeIf(TokenId::KwdLet) != INVALID_REF)
        flags.add(AstVarDecl::FlagsE::Let);

    if (is(TokenId::SymLeftParen))
        return parseDecompositionDecl(flags);

    SmallVector<AstNodeRef> vars;
    while (true)
    {
        // All names
        SmallVector<TokenRef> tokNames;
        while (true)
        {
            TokenRef tokName = INVALID_REF;
            if (Token::isCompilerAlias(id()) || Token::isCompilerUniq(id()))
                tokName = consume();
            else
                tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
            if (invalid(tokName))
                return INVALID_REF;
            tokNames.push_back(tokName);

            if (consumeIf(TokenId::SymComma) == INVALID_REF)
                break;
        }

        AstNodeRef nodeType = INVALID_REF;
        AstNodeRef nodeInit = INVALID_REF;

        if (consumeIf(TokenId::SymColon) != INVALID_REF)
            nodeType = parseType();
        if (consumeIf(TokenId::SymEqual) != INVALID_REF)
            nodeInit = parseInitializerExpression();

        if (tokNames.size() == 1)
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::VarDecl>();
            nodePtr->addFlag(flags);
            nodePtr->tokName  = tokNames[0];
            nodePtr->nodeType = nodeType;
            nodePtr->nodeInit = nodeInit;
            vars.push_back(nodeRef);
        }
        else
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::VarMultiNameDecl>();
            nodePtr->addFlag(flags);
            nodePtr->tokNames = ast_->store_.push_span(tokNames.span());
            nodePtr->nodeType = nodeType;
            nodePtr->nodeInit = nodeInit;
            vars.push_back(nodeRef);
        }

        if (!is(TokenId::SymComma))
            break;
        consume();
    }

    if (vars.size() == 1)
        return vars[0];

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::VarMultiDecl>();
    nodePtr->spanChildren   = ast_->store_.push_span(vars.span());
    return nodeRef;
}

SWC_END_NAMESPACE()
