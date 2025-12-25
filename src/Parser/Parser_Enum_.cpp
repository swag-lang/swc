#include "pch.h"
#include "Core/Utf8Helper.h"
#include "Parser/Parser.h"

SWC_BEGIN_NAMESPACE()

AstNodeRef Parser::parseImplEnum()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::ImplEnum>(consume());
    consumeAssert(TokenId::KwdEnum);

    nodePtr->nodeNameRef = parseQualifiedIdentifier();
    if (nodePtr->nodeNameRef.isInvalid())
        skipTo({TokenId::SymLeftCurly});

    nodePtr->spanChildrenRef = parseCompoundContent(AstNodeId::TopLevelBlock, TokenId::SymLeftCurly);
    return nodeRef;
}

AstNodeRef Parser::parseEnumValue()
{
    static constexpr std::initializer_list ENUM_VALUE_SYNC = {TokenId::SymRightCurly, TokenId::SymComma, TokenId::Identifier};

    switch (id())
    {
        case TokenId::CompilerAssert:
            return parseCompilerDiagnostic();
        case TokenId::CompilerError:
            return parseCompilerDiagnostic();
        case TokenId::CompilerWarning:
            return parseCompilerDiagnostic();
        case TokenId::CompilerPrint:
            return parseCompilerDiagnostic();
        case TokenId::CompilerIf:
            return parseCompilerIf<AstNodeId::EnumBody>();

        case TokenId::KwdUsing:
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::UsingEnumDecl>(consume());
            nodePtr->nodeNameRef    = parseQualifiedIdentifier();
            return nodeRef;
        }

        case TokenId::Identifier:
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::EnumValue>(consume());
            if (consumeIf(TokenId::SymEqual).isValid())
            {
                nodePtr->nodeInitRef = parseExpression();
                if (nodePtr->nodeInitRef.isInvalid())
                    skipTo(ENUM_VALUE_SYNC, SkipUntilFlagsE::EolBefore);
            }
            else
                nodePtr->nodeInitRef.setInvalid();
            return nodeRef;
        }

        case TokenId::CompilerAst:
            return parseCompilerFunc();

        case TokenId::SymAttrStart:
            return parseAttributeList<AstNodeId::EnumBody>();

        default:
            raiseError(DiagnosticId::parser_err_unexpected_token, ref());
            return AstNodeRef::invalid();
    }
}

AstNodeRef Parser::parseEnumDecl()
{
    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::EnumDecl>(consume());

    // Name
    nodePtr->tokNameRef = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
    if (nodePtr->tokNameRef.isInvalid())
        skipTo({TokenId::SymLeftCurly, TokenId::SymColon});

    // Type
    if (consumeIf(TokenId::SymColon).isValid())
    {
        if (is(TokenId::SymLeftCurly))
        {
            auto diag = reportError(DiagnosticId::parser_err_expected_token_fam_before, ref());
            diag.addArgument(Diagnostic::ARG_EXPECT_A_TOK_FAM, Utf8Helper::addArticleAAn(Token::toFamily(TokenId::TypeBool)), false);
            diag.report(*ctx_);
        }
        else
        {
            nodePtr->nodeTypeRef = parseType();
            if (nodePtr->nodeTypeRef.isInvalid())
                skipTo({TokenId::SymLeftCurly, TokenId::SymRightCurly});
        }
    }
    else
        nodePtr->nodeTypeRef.setInvalid();

    // Content
    nodePtr->nodeBodyRef = parseCompound<AstNodeId::EnumBody>(TokenId::SymLeftCurly);

    return nodeRef;
}

SWC_END_NAMESPACE()
