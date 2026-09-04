#include "pch.h"
#include "Format/FormatPassUtil.h"
#include "Format/FormatPasses.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using FormatPassUtil::INVALID_PIECE;

    bool isSymbolOperatorId(const TokenId id)
    {
        return Token::isOpArithmeticOrBitwise(id) || Token::isOpRelational(id) || Token::isOpLogical(id) || id == TokenId::SymPlusPlus;
    }

    bool isAssignRole(const FormatPiece& piece)
    {
        return piece.roles.hasAny({FormatRoleE::AssignOp, FormatRoleE::InitAssign, FormatRoleE::EnumAssign});
    }

    bool isUnarySymbol(const TokenId id)
    {
        switch (id)
        {
            case TokenId::SymMinus:
            case TokenId::SymPlus:
            case TokenId::SymBang:
            case TokenId::SymTilde:
            case TokenId::SymAmpersand:
            case TokenId::SymAsterisk:
                return true;
            default:
                return false;
        }
    }

    bool isClosingId(const TokenId id)
    {
        return id == TokenId::SymRightParen || id == TokenId::SymRightBracket || id == TokenId::SymRightCurly ||
               id == TokenId::SymComma || id == TokenId::SymSemiColon;
    }

    class SpacingPass
    {
    public:
        explicit SpacingPass(FormatModel& model) :
            model_(&model),
            options_(&model.options())
        {
        }

        void run() const
        {
            for (uint32_t i = 0; i < model_->numPieces(); ++i)
            {
                if (model_->piece(i).removed)
                    continue;
                const uint32_t prev = model_->prevPiece(i);
                if (prev == INVALID_PIECE)
                    continue;
                if (!FormatPassUtil::canEditGap(*model_, i) || model_->piece(prev).frozen)
                    continue;
                if (model_->gapHasNewline(i))
                    continue;
                if (model_->piece(i).isComment || model_->piece(prev).isComment)
                    continue;

                const uint32_t                current = model_->gapColumns(i);
                const std::optional<uint32_t> spaces  = desiredSpaces(prev, i);
                if (!spaces)
                {
                    // Alignment is rebuilt by the final alignment pass. In
                    // strict mode any otherwise unclassified horizontal run
                    // is ordinary token separation, never user-owned layout.
                    if (options_->normalizeHorizontalWhitespace.value_or(false) && current > 1)
                        model_->setGapSpaces(i, 1);
                    continue;
                }

                if (options_->normalizeHorizontalWhitespace.value_or(false))
                {
                    if (current != *spaces)
                        model_->setGapSpaces(i, *spaces);
                    continue;
                }

                // Without strict normalization, positive spacing options only
                // insert a missing blank and preserve wider manual alignment.
                if (*spaces == 0 && current != 0)
                    model_->setGapSpaces(i, 0);
                else if (*spaces > 0 && current == 0)
                    model_->setGapSpaces(i, *spaces);
            }
        }

    private:
        static std::optional<uint32_t> fromBool(const std::optional<bool>& option)
        {
            if (!option)
                return std::nullopt;
            return *option ? 1u : 0u;
        }

        // Swag is blank-sensitive before call / declaration parentheses (a
        // space there is a syntax error), so this option can only act on the
        // parenthesized expression that follows a control keyword.
        std::optional<uint32_t> spaceBeforeParen(const uint32_t prevIndex, const uint32_t curIndex) const
        {
            const FormatPiece& prev = model_->piece(prevIndex);
            if (!prev.hasRole(FormatRoleE::ControlKeyword) || !Token::isKeyword(prev.id))
                return std::nullopt;

            const auto nonEmpty = [&]() -> uint32_t {
                const uint32_t next = model_->nextPiece(curIndex);
                if (next == INVALID_PIECE || model_->piece(next).is(TokenId::SymRightParen))
                    return 0;
                return 1;
            };

            switch (options_->spaceBeforeParentheses)
            {
                case FormatSpaceBeforeParens::Never:
                    return 0u;
                case FormatSpaceBeforeParens::Always:
                case FormatSpaceBeforeParens::ControlStatements:
                    return 1u;
                case FormatSpaceBeforeParens::NonEmpty:
                    return nonEmpty();
                case FormatSpaceBeforeParens::Functions:
                case FormatSpaceBeforeParens::Preserve:
                    break;
            }

            return std::nullopt;
        }

        std::optional<uint32_t> desiredSpaces(const uint32_t prevIndex, const uint32_t curIndex) const
        {
            const FormatOptions& opt  = *options_;
            const FormatPiece&   prev = model_->piece(prevIndex);
            const FormatPiece&   cur  = model_->piece(curIndex);

            // Empty bracket pairs.
            if (prev.is(TokenId::SymLeftParen) && cur.is(TokenId::SymRightParen))
                return fromBool(opt.spaceInEmptyParentheses);
            if (prev.is(TokenId::SymLeftCurly) && cur.is(TokenId::SymRightCurly))
                return fromBool(opt.spaceInEmptyBraces);

            // Commas.
            if (cur.is(TokenId::SymComma))
                return fromBool(opt.spaceBeforeComma);
            if (prev.is(TokenId::SymComma) && !isClosingId(cur.id))
            {
                if (prev.hasRole(FormatRoleE::AttrComma) && opt.spaceAfterAttributeComma)
                    return fromBool(opt.spaceAfterAttributeComma);
                return fromBool(opt.spaceAfterComma);
            }

            // Arrows.
            if (cur.hasRole(FormatRoleE::Arrow) || prev.hasRole(FormatRoleE::Arrow))
                return fromBool(opt.spaceAroundArrow);
            if (cur.hasRole(FormatRoleE::FatArrow) || prev.hasRole(FormatRoleE::FatArrow))
                return fromBool(opt.spaceAroundFatArrow);

            // `T?` is one type spelling, never a conditional expression. The classifier
            // gives only nullable-type question marks this role, so ordinary `a ? b : c`
            // still follows the ternary spacing option below.
            if (cur.hasRole(FormatRoleE::NullableTypeSuffix))
                return 0u;

            // Ranges (`..` only; keyword ranges always keep their spaces).
            if ((cur.hasRole(FormatRoleE::RangeOp) && cur.is(TokenId::SymDotDot)) ||
                (prev.hasRole(FormatRoleE::RangeOp) && prev.is(TokenId::SymDotDot)))
                return fromBool(opt.spaceAroundRangeOperator);

            // Assignment operators.
            if (isAssignRole(cur) || isAssignRole(prev))
                return fromBool(opt.spaceAroundAssignmentOperator);

            // Binary / ternary operators (symbols only; word operators such as
            // `and` / `or` can gain a space but never lose it).
            const bool curBinary  = cur.roles.hasAny({FormatRoleE::BinaryOp, FormatRoleE::TernaryOp});
            const bool prevBinary = prev.roles.hasAny({FormatRoleE::BinaryOp, FormatRoleE::TernaryOp});
            if (curBinary || prevBinary)
            {
                const FormatPiece& op = curBinary ? cur : prev;
                if (isSymbolOperatorId(op.id) || op.is(TokenId::SymQuestion) || op.is(TokenId::SymColon))
                    return fromBool(opt.spaceAroundBinaryOperators);
                if (opt.spaceAroundBinaryOperators.value_or(false))
                    return 1u;
                return std::nullopt;
            }

            // Unary operators.
            if (prev.hasRole(FormatRoleE::UnaryOp) && isUnarySymbol(prev.id))
                return fromBool(opt.spaceAfterUnaryOperator);

            // Declaration / base clause colons.
            if (cur.is(TokenId::SymColon) && cur.hasRole(FormatRoleE::DeclColon))
                return fromBool(opt.spaceBeforeColonInDeclarations);
            if (cur.is(TokenId::SymColon) && cur.hasRole(FormatRoleE::BaseClauseColon))
                return fromBool(opt.spaceBeforeColonInBaseClause);
            if (cur.is(TokenId::SymColon) && cur.hasRole(FormatRoleE::NamedArgumentColon))
                return fromBool(opt.spaceBeforeColonInNamedArguments);
            if (prev.is(TokenId::SymColon) && (prev.hasRole(FormatRoleE::DeclColon) || prev.hasRole(FormatRoleE::BaseClauseColon)))
                return fromBool(opt.spaceAfterColonInDeclarations);
            if (prev.is(TokenId::SymColon) && prev.hasRole(FormatRoleE::NamedArgumentColon))
                return fromBool(opt.spaceAfterColonInNamedArguments);

            // After the `)` of a cast.
            if (prev.hasRole(FormatRoleE::CastCloseParen) && !isClosingId(cur.id))
                return fromBool(opt.spaceAfterCast);

            // Attribute bracket on the declaration line.
            if (cur.hasRole(FormatRoleE::AttrOpen))
                return fromBool(opt.spaceBeforeAttributeBracket);

            // Space before parentheses.
            if (cur.is(TokenId::SymLeftParen))
            {
                const std::optional<uint32_t> result = spaceBeforeParen(prevIndex, curIndex);
                if (result)
                    return result;
            }

            // After control keywords (never before punctuation: `default:`).
            if (prev.hasRole(FormatRoleE::ControlKeyword) && Token::isKeyword(prev.id) &&
                !isClosingId(cur.id) && cur.isNot(TokenId::SymColon))
            {
                if (!opt.spaceAfterKeyword)
                    return std::nullopt;
                if (*opt.spaceAfterKeyword)
                    return 1u;
                return cur.is(TokenId::SymLeftParen) ? 0u : 1u;
            }

            // Inside brackets.
            if (prev.is(TokenId::SymLeftParen) || cur.is(TokenId::SymRightParen))
                return fromBool(opt.spaceInsideParentheses);
            if (prev.is(TokenId::SymLeftBracket) || cur.is(TokenId::SymRightBracket))
                return fromBool(opt.spaceInsideBrackets);
            if ((prev.is(TokenId::SymLeftCurly) && prev.hasRole(FormatRoleE::LiteralOpen)) ||
                (cur.is(TokenId::SymRightCurly) && cur.hasRole(FormatRoleE::LiteralClose)))
                return fromBool(opt.spaceInsideBraces);

            return std::nullopt;
        }

        FormatModel*         model_;
        const FormatOptions* options_;
    };
}

namespace FormatPass
{
    void spacing(FormatModel& model)
    {
        SpacingPass(model).run();
    }
}

SWC_END_NAMESPACE();
