#include "pch.h"
#include "Compiler/Parser/Parser/Parser.h"

SWC_BEGIN_NAMESPACE();

AstNodeRef Parser::parseGenericParam()
{
    bool         isConstant  = false;
    bool         isType      = false;
    const Token& tknConstVar = tok();

    if (consumeIf(TokenId::KwdConst).isValid())
        isConstant = true;
    else if (consumeIf(TokenId::KwdVar).isValid())
        isType = true;

    const TokenRef tknName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);

    AstNodeRef nodeType = AstNodeRef::invalid();
    if (consumeIf(TokenId::SymColon).isValid())
    {
        if (isType)
        {
            Diagnostic diag = reportError(DiagnosticId::parser_err_gen_param_type, ref().offset(-1));
            diag.last().addSpan(tknConstVar.codeRange(*ctx_, ast_->srcView()), DiagnosticId::parser_note_gen_param_type, DiagnosticSeverity::Note);
            diag.addElement(DiagnosticId::parser_help_gen_param_type);
            diag.report(*ctx_);
        }

        isConstant = true;
        nodeType   = parseType();
    }

    AstNodeRef nodeAssign = AstNodeRef::invalid();
    if (consumeIf(TokenId::SymEqual).isValid())
    {
        if (isConstant)
            nodeAssign = parseExpression();
        else
            nodeAssign = parseType();
    }

    if (isConstant)
    {
        auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::GenericParamValue>(tknName);
        nodePtr->nodeAssignRef  = nodeAssign;
        nodePtr->nodeTypeRef    = nodeType;
        return nodeRef;
    }

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::GenericParamType>(tknName);
    nodePtr->nodeAssignRef  = nodeAssign;
    return nodeRef;
}

AstNodeRef Parser::parseVarDeclDecomposition()
{
    EnumFlags flags = AstVarDeclFlagsE::Zero;
    if (consumeIf(TokenId::KwdConst).isValid())
        flags.add(AstVarDeclFlagsE::Const);
    else if (consumeIf(TokenId::KwdVar).isValid())
        flags.add(AstVarDeclFlagsE::Var);
    else
    {
        consumeAssert(TokenId::KwdLet);
        flags.add(AstVarDeclFlagsE::Let);
    }

    const TokenRef openRef = consumeAssert(TokenId::SymLeftCurly);

    SmallVector<TokenRef> tokNames;
    SmallVector<TokenRef> fieldNames;
    bool                  hasNamed      = false;
    bool                  hasPositional = false;
    bool                  reportedMixed = false;
    while (!is(TokenId::SymRightCurly) && !atEnd())
    {
        const TokenRef itemRef      = ref();
        TokenRef       fieldNameRef = TokenRef::invalid();
        const bool     isNamed      = is(TokenId::Identifier) && nextIs(TokenId::SymColon) && !tok().flags.has(TokenFlagsE::BlankAfter);
        if (isNamed)
        {
            hasNamed     = true;
            fieldNameRef = consume();
            consumeAssert(TokenId::SymColon);
        }
        else
            hasPositional = true;

        fieldNames.push_back(fieldNameRef);
        if (consumeIf(TokenId::SymQuestion).isValid())
            tokNames.push_back(TokenRef::invalid());
        else
        {
            const TokenRef tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
            if (tokName.isInvalid())
                skipTo({TokenId::SymRightCurly, TokenId::SymComma});
            tokNames.push_back(tokName);
        }

        if (hasNamed && hasPositional && !reportedMixed)
        {
            const Diagnostic diag = reportError(DiagnosticId::parser_err_mixed_destructuring, itemRef);
            diag.report(*ctx_);
            reportedMixed = true;
        }

        if (consumeIf(TokenId::SymComma).isInvalid())
            break;

        if (is(TokenId::SymRightCurly))
        {
            Diagnostic diag = reportError(DiagnosticId::parser_err_expected_token_fam_before, ref());
            setReportExpected(diag, TokenId::Identifier);
            diag.report(*ctx_);
        }
    }

    expectAndConsumeClosing(TokenId::SymRightCurly, openRef, {TokenId::SymEqual});
    const TokenRef tokAssign = expectAndConsume(TokenId::SymEqual, DiagnosticId::parser_err_expected_token_before);

    auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::VarDeclDestructuring>(ref());
    nodePtr->flags()        = flags;
    if (hasNamed && !hasPositional)
        nodePtr->addFlag(AstVarDeclFlagsE::NamedDestructuring);
    nodePtr->nodeInitRef       = parseInitializerExpression(tokAssign);
    nodePtr->spanNamesRef      = ast_->pushSpan(tokNames.span());
    nodePtr->spanFieldNamesRef = ast_->pushSpan(fieldNames.span());

    return nodeRef;
}

AstNodeRef Parser::parseVarDecl()
{
    EnumFlags      flags    = AstVarDeclFlagsE::Zero;
    const TokenRef tokStart = ref();
    if (consumeIf(TokenId::KwdConst).isValid())
        flags.add(AstVarDeclFlagsE::Const);
    else if (consumeIf(TokenId::KwdVar).isValid())
        flags.add(AstVarDeclFlagsE::Var);
    else if (consumeIf(TokenId::KwdLet).isValid())
        flags.add(AstVarDeclFlagsE::Let);

    if (hasContextFlag(ParserContextFlagsE::InUsingMemberDecl))
        flags.add(AstVarDeclFlagsE::Using);

    SmallVector<AstNodeRef> vars;
    while (true)
    {
        // All names
        SmallVector<TokenRef> tokNames;
        while (true)
        {
            TokenRef tokName = TokenRef::invalid();
            if (Token::isCompilerUniq(id()))
                tokName = consume();
            else
                tokName = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam_before);
            if (tokName.isInvalid())
                skipTo({TokenId::SymComma, TokenId::SymColon, TokenId::SymEqual});
            tokNames.push_back(tokName);

            if (consumeIf(TokenId::SymComma).isInvalid())
                break;
        }

        if (isNot(TokenId::SymColon) && isNot(TokenId::SymEqual))
            raiseError(DiagnosticId::parser_err_empty_var_decl, ref().offset(-1));

        // Type
        AstNodeRef nodeType     = AstNodeRef::invalid();
        bool       fwdCopyParam = false;
        if (consumeIf(TokenId::SymColon).isValid())
        {
            const PushContextFlags scopedContext{this, ParserContextFlagsE::InVarDeclType};
            const bool             prevFwdSeen = fwdSeenParam_;
            nodeType                           = parseType();
            fwdCopyParam                       = fwdSeenParam_ && !prevFwdSeen && fwdPassMode_ == FwdParseMode::Copy;
        }

        // Initialization
        AstNodeRef     nodeInit  = AstNodeRef::invalid();
        const TokenRef tokAssign = consumeIf(TokenId::SymEqual);
        if (tokAssign.isValid())
            nodeInit = parseInitializerExpression(tokAssign);
        else if (nodeType.isValid() && is(TokenId::SymLeftCurly) && !tok().hasFlag(TokenFlagsE::BlankBefore))
        {
            // 'name: Type{...}' used to be a second spelling of an initialized declaration. It
            // was the only declaration form that initialized without '=', and it only parsed as
            // an initializer when no blank separated the type from '{'. The literal is still
            // consumed so the rest of the statement reports its own errors normally.
            raiseError(DiagnosticId::parser_err_var_decl_brace_init, ref());
            nodeInit = parseLiteralStruct();
        }

        if (tokNames.size() == 1)
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::SingleVarDecl>(tokStart);
            nodePtr->flags()        = flags;
            if (hasContextFlag(ParserContextFlagsE::InFunctionParam))
                nodePtr->addFlag(AstVarDeclFlagsE::Parameter);
            if (fwdCopyParam)
                nodePtr->addFlag(AstVarDeclFlagsE::FwdCopy);
            nodePtr->tokNameRef  = tokNames[0];
            nodePtr->nodeTypeRef = nodeType;
            nodePtr->nodeInitRef = nodeInit;
            vars.push_back(nodeRef);
        }
        else
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::MultiVarDecl>(tokStart);
            nodePtr->flags()        = flags;
            if (hasContextFlag(ParserContextFlagsE::InFunctionParam))
                nodePtr->addFlag(AstVarDeclFlagsE::Parameter);
            if (fwdCopyParam)
                nodePtr->addFlag(AstVarDeclFlagsE::FwdCopy);
            nodePtr->spanNamesRef = ast_->pushSpan(tokNames.span());
            nodePtr->nodeTypeRef  = nodeType;
            nodePtr->nodeInitRef  = nodeInit;
            vars.push_back(nodeRef);
        }

        if (!is(TokenId::SymComma))
            break;
        consume();
    }

    // One single variable
    if (vars.size() == 1)
        return vars.front();

    // Multiple variables
    auto [nodeRef, nodePtr]  = ast_->makeNode<AstNodeId::VarDeclList>(ref());
    nodePtr->spanChildrenRef = ast_->pushSpan(vars.span());
    return nodeRef;
}

SWC_END_NAMESPACE();
