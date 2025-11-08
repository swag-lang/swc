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
            diag.last().addSpan(tknConstVar.toLocation(*ctx_, *file_), DiagnosticId::parser_note_gen_param_type, DiagnosticSeverity::Note);
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

AstNodeRef Parser::parseVarDecl()
{
    SmallVector<TokenRef> tokNames;

    // All names
    TokenRef tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
    if (invalid(tokName))
        return INVALID_REF;
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
        nodeInit = parseInitializationExpression();

    if (tokNames.size() == 1)
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::VarDecl>();
        nodePtr->tokName        = tokNames[0];
        nodePtr->nodeType       = nodeType;
        nodePtr->nodeInit       = nodeInit;
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::MultiVarDecl>();
    nodePtr->tokNames       = ast_->store_.push_span(tokNames.span());
    nodePtr->nodeType       = nodeType;
    nodePtr->nodeInit       = nodeInit;
    return nodeRef;
}

SWC_END_NAMESPACE()
