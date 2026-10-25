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

AstNodeRef Parser::parseDestructuringPattern(bool declaration, SmallVector<TokenRef>* bindings)
{
    const bool     named             = is(TokenId::SymLeftCurly);
    const TokenId  closeId           = named ? TokenId::SymRightCurly : TokenId::SymRightParen;
    const TokenRef openRef           = consume();
    const auto [patternRef, pattern] = ast_->makeNode<AstNodeId::AssignList>(openRef);
    pattern->addFlag(AstAssignListFlagsE::Destructuring);
    if (named)
        pattern->addFlag(AstAssignListFlagsE::NamedDestructuring);
    if (declaration)
        pattern->addFlag(AstAssignListFlagsE::DeclarationPattern);

    SmallVector<AstNodeRef> children;
    SmallVector<TokenRef>   fieldNames;
    bool                    comma = false;
    while (!is(closeId) && !atEnd())
    {
        parseDestructuringFieldName(fieldNames, named);
        if (isAny(TokenId::SymLeftParen, TokenId::SymLeftCurly))
            children.push_back(parseDestructuringPattern(declaration, bindings));
        else if (is(TokenId::KwdUnnamed))
        {
            const auto [ignoreRef, ignore] = ast_->makeNode<AstNodeId::AssignIgnore>(consume());
            SWC_UNUSED(ignore);
            children.push_back(ignoreRef);
            if (bindings)
                bindings->push_back(TokenRef::invalid());
        }
        else if (declaration)
        {
            const TokenRef nameRef = expectAndConsume(TokenId::Identifier, DiagnosticId::parser_err_expected_token_fam);
            if (bindings)
                bindings->push_back(nameRef);
            const auto [bindingRef, binding] = ast_->makeNode<AstNodeId::Identifier>(nameRef);
            SWC_UNUSED(binding);
            children.push_back(bindingRef);
        }
        else
            children.push_back(parseExpression());
        if (consumeIf(TokenId::SymComma).isInvalid())
            break;
        comma = true;
    }
    if (!named && children.size() == 1 && !comma && is(closeId))
    {
        const Diagnostic diag = reportError(DiagnosticId::parser_err_tuple_pattern_comma, ref());
        diag.report(*ctx_);
    }
    expectAndConsumeClosing(closeId, openRef, {TokenId::SymEqual});
    pattern->spanChildrenRef   = ast_->pushSpan(children.span());
    pattern->spanFieldNamesRef = ast_->pushSpan(fieldNames.span());
    return patternRef;
}

AstNodeRef Parser::parseVarDeclDecomposition()
{
    const TokenRef declarationRef = ref();
    EnumFlags      flags          = AstVarDeclFlagsE::Zero;
    if (consumeIf(TokenId::KwdConst).isValid())
        flags.add(AstVarDeclFlagsE::Const);
    else if (consumeIf(TokenId::KwdVar).isValid())
        flags.add(AstVarDeclFlagsE::Var);
    else
    {
        consumeAssert(TokenId::KwdLet);
        flags.add(AstVarDeclFlagsE::Let);
    }

    SmallVector<TokenRef> names;
    const AstNodeRef      patternRef = parseDestructuringPattern(true, &names);
    const TokenRef        assignRef  = expectAndConsume(TokenId::SymEqual, DiagnosticId::parser_err_expected_token_before);
    const auto [nodeRef, node]       = ast_->makeNode<AstNodeId::VarDeclDestructuring>(declarationRef);
    node->flags()                    = flags;
    node->spanNamesRef               = ast_->pushSpan(names.span());
    node->nodePatternRef             = patternRef;
    node->nodeInitRef                = parseInitializerExpression(assignRef);
    return nodeRef;
}

AstNodeRef Parser::parseVarDecl()
{
    EnumFlags<AstVarDeclFlagsE>    flags        = AstVarDeclFlagsE::Zero;
    const TokenRef                 tokStart     = ref();
    EnumFlags<AstVarStorageFlagsE> storageFlags = parseStorageModifiers();

    if (consumeIf(TokenId::KwdConst).isValid())
        flags.add(AstVarDeclFlagsE::Const);
    else if (consumeIf(TokenId::KwdVar).isValid())
        flags.add(AstVarDeclFlagsE::Var);
    else if (consumeIf(TokenId::KwdLet).isValid())
        flags.add(AstVarDeclFlagsE::Let);

    if (hasContextFlag(ParserContextFlagsE::InUsingMemberDecl))
        flags.add(AstVarDeclFlagsE::Using);

    storageFlags.add(topLevelStorageFlags_);
    storageFlags.add(aggregateStorageFlags_);

    SmallVector<AstNodeRef> vars;
    while (true)
    {
        // All names
        SmallVector<TokenRef> tokNames;
        while (true)
        {
            // A parameter named '_' is one the body leaves unnamed.
            TokenRef tokName = TokenRef::invalid();
            if (Token::isCompilerUniq(id()) || (hasContextFlag(ParserContextFlagsE::InFunctionParam) && is(TokenId::KwdUnnamed)))
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

        // What a single and a multiple declaration share, everything but their names.
        const auto setDeclCommon = [&](auto* nodePtr) {
            nodePtr->flags()      = flags;
            nodePtr->storageFlags = storageFlags;
            if (hasContextFlag(ParserContextFlagsE::InFunctionParam))
                nodePtr->addFlag(AstVarDeclFlagsE::Parameter);
            if (fwdCopyParam)
                nodePtr->addFlag(AstVarDeclFlagsE::FwdCopy);

            nodePtr->nodeTypeRef = nodeType;
            nodePtr->nodeInitRef = nodeInit;
        };

        if (tokNames.size() == 1)
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::SingleVarDecl>(tokStart);
            setDeclCommon(nodePtr);
            nodePtr->tokNameRef = tokNames[0];
            vars.push_back(nodeRef);
        }
        else
        {
            auto [nodeRef, nodePtr] = ast_->makeNode<AstNodeId::MultiVarDecl>(tokStart);
            setDeclCommon(nodePtr);
            nodePtr->spanNamesRef = ast_->pushSpan(tokNames.span());
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
