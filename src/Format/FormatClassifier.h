#pragma once

SWC_BEGIN_NAMESPACE();

class Ast;
class FormatModel;

// Walks the AST and annotates the pieces of a FormatModel with semantic roles
// (call paren vs declaration paren, declaration colon, binary operator, block
// braces, ...) so the formatting passes never have to query the AST themselves.
class FormatClassifier
{
public:
    static void classify(FormatModel& model, const Ast& ast);
};

SWC_END_NAMESPACE();
