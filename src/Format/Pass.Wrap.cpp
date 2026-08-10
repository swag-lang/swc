// The wrapping contract.
//
// This pass decides locally, one construct and one break at a time. There is no
// penalty function over the whole unwrapped line the way clang-format has, and
// no Wadler document searched for the best fit the way prettier has. That is a
// deliberate choice, not a missing feature, and it rests on what the canonical
// Swag style is: `column-limit` is 0, so the formatter adds and removes no
// statement break at all. The author owns the line breaks; the formatter owns
// the columns. Everything a solver would decide — which of six equally legal
// shapes a dense expression takes — is therefore already decided by the source,
// and a solver would have nothing left to search.
//
// The exception is the interior of a bracket, where continuation lines keep
// their distance to the statement instead of taking the canonical indent. That
// is what carries a hand-packed data table: its rows are aligned in columns the
// formatter cannot see, and forcing the canonical indent on them was measured to
// destroy that alignment (`bin/examples/modules/opengl3`, where rows starting
// with `1,` carry a leading blank so the numbers line up under `-1,`).
//
// A `column-limit` above 0 turns the greedy breaker below on. It stays greedy:
// it picks the break highest in the expression tree that still fits, one break
// at a time. Revisit this choice — and only then reach for a solver — when a
// wrapping shape has to be added that cannot be stated as one such local rule.
#include "pch.h"
#include "Compiler/Lexer/Token.h"
#include "Format/FormatPassUtil.h"
#include "Format/FormatPasses.h"
#include "Support/Report/Assert.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using FormatPassUtil::INVALID_PIECE;
    using FormatPassUtil::PieceColumn;

    enum class ListLineMode : uint8_t
    {
        Unchanged,
        SingleLine,
        MultiLine,
    };

    struct ListPolicy
    {
        std::optional<bool> forceSingleLine;
        std::optional<bool> sourceSelectsLayout;
        std::optional<bool> hugTrailingBlock;
        FormatListLayout    layout  = FormatListLayout::Preserve;
        FormatBinPackStyle  binPack = FormatBinPackStyle::Preserve;

        bool active() const
        {
            return forceSingleLine.value_or(false) || sourceSelectsLayout.has_value() || hugTrailingBlock.value_or(false) ||
                   layout != FormatListLayout::Preserve || binPack != FormatBinPackStyle::Preserve;
        }
    };

    struct ListState
    {
        uint32_t              openPiece  = INVALID_PIECE;
        uint32_t              closePiece = INVALID_PIECE;
        std::vector<uint32_t> items;
        std::optional<bool>   forceSingleLine;
        std::optional<bool>   sourceSelectsLayout;
        std::optional<bool>   hugTrailingBlock;
        FormatListLayout      layout     = FormatListLayout::Preserve;
        FormatBinPackStyle    binPack    = FormatBinPackStyle::Preserve;
        ListLineMode          lineMode   = ListLineMode::Unchanged;
        bool                  editable   = false;
        bool                  hasComment = false;
        bool                  canJoin    = false;
        bool                  literal    = false;
        bool                  hug        = false;
    };

    struct LogicalPolicy
    {
        std::optional<bool>     forceSingleLine;
        std::optional<bool>     sourceSelectsLayout;
        FormatLogicalLayout     layout        = FormatLogicalLayout::Preserve;
        FormatOperatorWrapStyle breakPosition = FormatOperatorWrapStyle::Preserve;
        FormatLogicalPacking    packing       = FormatLogicalPacking::Preserve;

        bool active() const
        {
            return forceSingleLine.value_or(false) || sourceSelectsLayout.has_value() ||
                   layout != FormatLogicalLayout::Preserve || breakPosition != FormatOperatorWrapStyle::Preserve ||
                   packing != FormatLogicalPacking::Preserve;
        }
    };

    struct LogicalState
    {
        uint32_t                firstPiece        = INVALID_PIECE;
        uint32_t                lastPiece         = INVALID_PIECE;
        uint32_t                rootOperatorPiece = INVALID_PIECE;
        std::vector<uint32_t>   operators;
        std::vector<uint32_t>   operands;
        std::optional<bool>     forceSingleLine;
        std::optional<bool>     sourceSelectsLayout;
        FormatLogicalLayout     layout        = FormatLogicalLayout::Preserve;
        FormatOperatorWrapStyle breakPosition = FormatOperatorWrapStyle::Preserve;
        FormatLogicalPacking    packing       = FormatLogicalPacking::Preserve;
        ListLineMode            lineMode      = ListLineMode::Unchanged;
        bool                    editable      = false;
        bool                    hasComment    = false;
        bool                    canJoin       = false;
    };

    enum class LayoutTargetKind : uint8_t
    {
        List,
        Logical,
    };

    struct LayoutTarget
    {
        uint32_t         firstPiece = INVALID_PIECE;
        uint32_t         lastPiece  = INVALID_PIECE;
        uint32_t         index      = INVALID_PIECE;
        LayoutTargetKind kind       = LayoutTargetKind::List;
    };

    bool textHasNewline(const std::string_view text)
    {
        return text.find_first_of("\r\n") != std::string_view::npos;
    }

    class WrapPass
    {
    public:
        explicit WrapPass(FormatModel& model) :
            model_(&model),
            options_(&model.options())
        {
        }

        void run()
        {
            collectLists();
            collectLogicalExpressions();
            chooseLineModes();
            prepareLists();
            prepareLogicalExpressions();
            wrapLongLines();
            finishLists();
            finishLogicalExpressions();

            // The repair replays the records in source order, so the ones this
            // pass appended have to be merged back into the indent pass's.
            std::ranges::stable_sort(model_->hangingLines(), {}, &FormatHangingLine::lineStart);
        }

    private:
        ListPolicy policyFor(const FormatPiece& piece) const
        {
            if (piece.hasRole(FormatRoleE::CallOpenParen))
            {
                return {
                    .forceSingleLine     = options_->forceSingleLineArgumentLists,
                    .sourceSelectsLayout = options_->sourceSelectsArgumentLayout,
                    .hugTrailingBlock    = options_->hugTrailingBlockArgument,
                    .layout              = options_->argumentListLayout,
                    .binPack             = options_->binPackArguments,
                };
            }

            if (piece.hasRole(FormatRoleE::LiteralOpen))
            {
                return {
                    .forceSingleLine     = options_->forceSingleLineLiteralLists,
                    .sourceSelectsLayout = options_->sourceSelectsLiteralLayout,
                    .hugTrailingBlock    = options_->hugTrailingBlockItem,
                    .layout              = options_->literalListLayout,
                    .binPack             = options_->binPackLiteralItems,
                };
            }

            SWC_ASSERT(piece.hasRole(FormatRoleE::DeclOpenParen));
            return {
                .forceSingleLine     = options_->forceSingleLineParameterLists,
                .sourceSelectsLayout = options_->sourceSelectsParameterLayout,
                .layout              = options_->parameterListLayout,
                .binPack             = options_->binPackParameters,
            };
        }

        void collectLists()
        {
            for (uint32_t i = 0; i < model_->numPieces(); ++i)
            {
                const FormatPiece& open = model_->piece(i);
                if (open.removed || open.match == INVALID_PIECE ||
                    !open.roles.hasAny({FormatRoleE::CallOpenParen, FormatRoleE::DeclOpenParen, FormatRoleE::LiteralOpen}) ||
                    model_->piece(open.match).hasRole(FormatRoleE::DestructuringClose))
                    continue;

                const ListPolicy policy = policyFor(open);
                if (!policy.active())
                    continue;

                ListState state;
                state.openPiece           = i;
                state.closePiece          = open.match;
                state.forceSingleLine     = policy.forceSingleLine;
                state.sourceSelectsLayout = policy.sourceSelectsLayout;
                state.hugTrailingBlock    = policy.hugTrailingBlock;
                state.layout              = policy.layout;
                state.binPack             = policy.binPack;
                state.literal             = open.hasRole(FormatRoleE::LiteralOpen);
                collectItems(state);
                lists_.push_back(std::move(state));
            }
        }

        LogicalPolicy logicalPolicy() const
        {
            return {
                .forceSingleLine     = options_->forceSingleLineLogicalExpressions,
                .sourceSelectsLayout = options_->sourceSelectsLogicalExpressionLayout,
                .layout              = options_->logicalExpressionLayout,
                .breakPosition       = options_->logicalOperatorBreakPosition,
                .packing             = options_->logicalOperandPacking,
            };
        }

        uint32_t nextCodePiece(const uint32_t pieceIndex) const
        {
            for (uint32_t next = model_->nextPiece(pieceIndex); next != INVALID_PIECE; next = model_->nextPiece(next))
            {
                if (!model_->piece(next).isComment)
                    return next;
            }
            return INVALID_PIECE;
        }

        void collectLogicalExpressions()
        {
            const LogicalPolicy policy = logicalPolicy();
            if (!policy.active())
                return;

            for (const FormatLogicalExpression& expr : model_->logicalExpressions())
            {
                SWC_ASSERT(expr.rootOperatorPiece != INVALID_PIECE);
                const uint32_t rootDepth = model_->piece(expr.rootOperatorPiece).depth;

                LogicalState state;
                state.firstPiece          = expr.firstPiece;
                state.lastPiece           = expr.lastPiece;
                state.rootOperatorPiece   = expr.rootOperatorPiece;
                state.forceSingleLine     = policy.forceSingleLine;
                state.sourceSelectsLayout = policy.sourceSelectsLayout;
                state.layout              = policy.layout;
                state.breakPosition       = policy.breakPosition;
                state.packing             = policy.packing;
                state.operands.push_back(expr.firstPiece);

                for (uint32_t i = expr.firstPiece; i <= expr.lastPiece; ++i)
                {
                    const FormatPiece& piece = model_->piece(i);
                    if (!piece.hasRole(FormatRoleE::LogicalOp) || piece.depth != rootDepth)
                        continue;
                    const uint32_t operand = nextCodePiece(i);
                    if (operand == INVALID_PIECE || operand > expr.lastPiece)
                        continue;
                    state.operators.push_back(i);
                    state.operands.push_back(operand);
                }

                if (!state.operators.empty())
                    logicalExpressions_.push_back(std::move(state));
            }
        }

        void chooseLineModes()
        {
            std::vector<LayoutTarget> targets;
            targets.reserve(lists_.size() + logicalExpressions_.size());
            for (uint32_t i = 0; i < lists_.size(); ++i)
                targets.push_back({lists_[i].openPiece, lists_[i].closePiece, i, LayoutTargetKind::List});
            for (uint32_t i = 0; i < logicalExpressions_.size(); ++i)
                targets.push_back({logicalExpressions_[i].firstPiece, logicalExpressions_[i].lastPiece, i, LayoutTargetKind::Logical});

            std::ranges::sort(targets, [](const LayoutTarget& lhs, const LayoutTarget& rhs) {
                const uint32_t lhsSize = lhs.lastPiece - lhs.firstPiece;
                const uint32_t rhsSize = rhs.lastPiece - rhs.firstPiece;
                if (lhsSize != rhsSize)
                    return lhsSize < rhsSize;
                return lhs.firstPiece > rhs.firstPiece;
            });

            // Normalize nested constructs first so an outer expression can
            // join after all of its joinable children have joined.
            for (const LayoutTarget& target : targets)
            {
                if (target.kind == LayoutTargetKind::List)
                {
                    ListState& state = lists_[target.index];
                    inspectList(state);
                    chooseLineMode(state);
                }
                else
                {
                    LogicalState& state = logicalExpressions_[target.index];
                    inspectLogicalExpression(state);
                    chooseLogicalLineMode(state);
                }
            }
        }

        void collectItems(ListState& state) const
        {
            const FormatPiece& open = model_->piece(state.openPiece);
            uint32_t           item = model_->nextPiece(state.openPiece);
            if (item == INVALID_PIECE || item == state.closePiece)
                return;
            state.items.push_back(item);

            const uint32_t innerDepth = open.depth + 1;
            for (uint32_t i = item; i != INVALID_PIECE && i < state.closePiece; i = model_->nextPiece(i))
            {
                const FormatPiece& piece = model_->piece(i);
                if (piece.isNot(TokenId::SymComma) || piece.depth != innerDepth || piece.hasRole(FormatRoleE::ClosureCaptureComma))
                    continue;

                const uint32_t next = model_->nextPiece(i);
                if (next != INVALID_PIECE && next < state.closePiece)
                    state.items.push_back(next);
            }
        }

        bool isItemStart(const ListState& state, const uint32_t pieceIndex) const
        {
            return std::ranges::find(state.items, pieceIndex) != state.items.end();
        }

        void inspectList(ListState& state) const
        {
            state.editable = FormatPassUtil::canEditPiece(*model_, state.openPiece) &&
                             FormatPassUtil::canEditPiece(*model_, state.closePiece);
            state.canJoin = state.editable;

            for (uint32_t i = state.openPiece + 1; i <= state.closePiece; ++i)
            {
                const FormatPiece& piece = model_->piece(i);
                if (piece.removed)
                    continue;
                if (piece.isComment)
                {
                    state.hasComment = true;
                    state.canJoin    = false;
                }
                if (piece.frozen || model_->gapBefore(i).frozen)
                {
                    state.editable = false;
                    state.canJoin  = false;
                }

                if (model_->gapHasNewline(i) && i != state.closePiece && !isItemStart(state, i))
                    state.canJoin = false;
            }
        }

        // A call whose last argument is the only multiline one reads as a header
        // followed by a block: `f(a, b, [` then the rows, then `])`. Splitting the
        // scalar arguments one per line only to reach that block hides the header
        // and pushes the block far to the right, so detect the shape here and let
        // the list keep its opening line.
        bool wantsHug(const ListState& state) const
        {
            if (!state.hugTrailingBlock.value_or(false) || state.hasComment || state.items.size() < 2)
                return false;

            const uint32_t last = state.items.back();
            if (!isMultilineLiteralItem(last))
                return false;

            for (uint32_t i = state.openPiece + 1; i < last; ++i)
            {
                if (model_->piece(i).removed)
                    continue;
                if (isItemStart(state, i))
                {
                    if (!FormatPassUtil::canEditGap(*model_, i))
                        return false;
                    continue;
                }
                // An earlier argument that spans lines has its own block to place.
                if (model_->gapHasNewline(i))
                    return false;
            }

            if (!FormatPassUtil::canEditGap(*model_, last))
                return false;

            for (uint32_t i = last + 1; i <= state.closePiece; ++i)
            {
                if (!model_->piece(i).removed && model_->gapHasNewline(i))
                    return true;
            }
            return false;
        }

        void hugItems(const ListState& state) const
        {
            for (size_t i = 0; i < state.items.size(); ++i)
            {
                const uint32_t item = state.items[i];
                if (model_->gapHasNewline(item))
                    model_->setGapSpaces(item, i == 0 ? spacesAfterOpen(state) : spacesAfterComma());
            }
        }

        bool firstItemsShareSourceLine(const ListState& state) const
        {
            if (state.items.size() < 2)
                return true;

            // Literal rows often intentionally pack many scalar values per
            // source line. Unlike argument lists, seeing only the first two
            // items together is not enough evidence that a previously
            // multiline data table should become one enormous line.
            if (state.literal)
            {
                for (uint32_t i = state.openPiece + 1; i <= state.closePiece; ++i)
                {
                    if (textHasNewline(model_->gapBefore(i).origText))
                        return false;
                }
            }

            for (uint32_t i = state.items[0] + 1; i <= state.items[1]; ++i)
            {
                if (textHasNewline(model_->gapBefore(i).origText))
                    return false;
            }
            return true;
        }

        std::vector<FormatGap> snapshotGaps(const ListState& state) const
        {
            std::vector<FormatGap> result;
            result.reserve(state.closePiece - state.openPiece);
            for (uint32_t i = state.openPiece + 1; i <= state.closePiece; ++i)
                result.push_back(model_->gapBefore(i));
            return result;
        }

        void restoreGaps(const ListState& state, const std::vector<FormatGap>& gaps) const
        {
            SWC_ASSERT(gaps.size() == state.closePiece - state.openPiece);
            for (uint32_t i = state.openPiece + 1; i <= state.closePiece; ++i)
                model_->gapBefore(i) = gaps[i - state.openPiece - 1];
        }

        uint32_t spacesAfterOpen(const ListState& state) const
        {
            const FormatPiece& open = model_->piece(state.openPiece);
            if (open.is(TokenId::SymLeftBracket))
                return options_->spaceInsideBrackets.value_or(false) ? 1 : 0;
            if (open.is(TokenId::SymLeftCurly))
                return options_->spaceInsideBraces.value_or(false) ? 1 : 0;
            return options_->spaceInsideParentheses.value_or(false) ? 1 : 0;
        }

        uint32_t spacesAfterComma() const
        {
            return options_->spaceAfterComma.value_or(true) ? 1 : 0;
        }

        uint32_t spacesBeforeClose(const ListState& state) const
        {
            const FormatPiece& close = model_->piece(state.closePiece);
            if (state.items.empty())
            {
                if (close.is(TokenId::SymRightCurly))
                    return options_->spaceInEmptyBraces.value_or(false) ? 1 : 0;
                if (close.is(TokenId::SymRightBracket))
                    return options_->spaceInsideBrackets.value_or(false) ? 1 : 0;
                return options_->spaceInEmptyParentheses.value_or(false) ? 1 : 0;
            }
            if (close.is(TokenId::SymRightBracket))
                return options_->spaceInsideBrackets.value_or(false) ? 1 : 0;
            if (close.is(TokenId::SymRightCurly))
                return options_->spaceInsideBraces.value_or(false) ? 1 : 0;
            return options_->spaceInsideParentheses.value_or(false) ? 1 : 0;
        }

        bool joinList(const ListState& state) const
        {
            if (!state.canJoin)
                return false;

            for (size_t i = 0; i < state.items.size(); ++i)
            {
                const uint32_t item = state.items[i];
                if (!model_->gapHasNewline(item))
                    continue;
                model_->setGapSpaces(item, i == 0 ? spacesAfterOpen(state) : spacesAfterComma());
            }

            if (model_->gapHasNewline(state.closePiece))
                model_->setGapSpaces(state.closePiece, spacesBeforeClose(state));
            return true;
        }

        bool joinedListFits(const ListState& state) const
        {
            if (options_->columnLimit == 0)
                return true;
            const uint32_t lineStart = model_->lineStartOf(state.openPiece);
            return FormatPassUtil::lineWidth(*model_, lineStart) <= options_->columnLimit;
        }

        void chooseLineMode(ListState& state)
        {
            if (!state.editable)
                return;

            state.hug = wantsHug(state);
            if (state.hug)
            {
                state.lineMode = ListLineMode::MultiLine;
                return;
            }

            if (state.forceSingleLine.value_or(false))
            {
                if (joinList(state))
                    state.lineMode = ListLineMode::SingleLine;
                return;
            }

            if (!state.sourceSelectsLayout.has_value())
                return;

            if (*state.sourceSelectsLayout)
            {
                if (firstItemsShareSourceLine(state) && joinList(state))
                    state.lineMode = ListLineMode::SingleLine;
                else
                    state.lineMode = ListLineMode::MultiLine;
                return;
            }

            if (!state.canJoin)
            {
                state.lineMode = ListLineMode::MultiLine;
                return;
            }

            const std::vector<FormatGap> originalGaps = snapshotGaps(state);
            const bool                   joined       = joinList(state);
            SWC_ASSERT(joined);
            if (joinedListFits(state))
            {
                state.lineMode = ListLineMode::SingleLine;
                return;
            }

            restoreGaps(state, originalGaps);
            state.lineMode = ListLineMode::MultiLine;
        }

        bool isLogicalBoundaryGap(const LogicalState& state, const uint32_t pieceIndex) const
        {
            if (std::ranges::find(state.operators, pieceIndex) != state.operators.end())
                return true;
            return std::ranges::find(state.operands.begin() + 1, state.operands.end(), pieceIndex) != state.operands.end();
        }

        void inspectLogicalExpression(LogicalState& state) const
        {
            state.editable = FormatPassUtil::canEditPiece(*model_, state.firstPiece) &&
                             FormatPassUtil::canEditPiece(*model_, state.lastPiece);
            state.canJoin = state.editable;

            for (uint32_t i = state.firstPiece + 1; i <= state.lastPiece; ++i)
            {
                const FormatPiece& piece = model_->piece(i);
                if (piece.removed)
                    continue;
                if (piece.isComment)
                {
                    state.hasComment = true;
                    state.canJoin    = false;
                }
                if (piece.frozen || model_->gapBefore(i).frozen)
                {
                    state.editable = false;
                    state.canJoin  = false;
                }
                if (model_->gapHasNewline(i) && !isLogicalBoundaryGap(state, i))
                    state.canJoin = false;
            }
        }

        bool firstLogicalOperandsShareSourceLine(const LogicalState& state) const
        {
            SWC_ASSERT(state.operands.size() >= 2);
            for (uint32_t i = state.operands[0] + 1; i <= state.operands[1]; ++i)
            {
                if (textHasNewline(model_->gapBefore(i).origText))
                    return false;
            }
            return true;
        }

        std::vector<FormatGap> snapshotLogicalGaps(const LogicalState& state) const
        {
            std::vector<FormatGap> result;
            result.reserve(state.lastPiece - state.firstPiece);
            for (uint32_t i = state.firstPiece + 1; i <= state.lastPiece; ++i)
                result.push_back(model_->gapBefore(i));
            return result;
        }

        void restoreLogicalGaps(const LogicalState& state, const std::vector<FormatGap>& gaps) const
        {
            SWC_ASSERT(gaps.size() == state.lastPiece - state.firstPiece);
            for (uint32_t i = state.firstPiece + 1; i <= state.lastPiece; ++i)
                model_->gapBefore(i) = gaps[i - state.firstPiece - 1];
        }

        void joinLogicalBoundaries(const LogicalState& state) const
        {
            for (size_t i = 0; i < state.operators.size(); ++i)
            {
                const uint32_t op      = state.operators[i];
                const uint32_t operand = state.operands[i + 1];
                if (model_->gapHasNewline(op))
                    model_->setGapSpaces(op, 1);
                if (model_->gapHasNewline(operand))
                    model_->setGapSpaces(operand, 1);
            }
        }

        bool joinLogicalExpression(const LogicalState& state) const
        {
            if (!state.canJoin)
                return false;
            joinLogicalBoundaries(state);
            return true;
        }

        bool joinedLogicalExpressionFits(const LogicalState& state) const
        {
            if (options_->columnLimit == 0)
                return true;
            const uint32_t lineStart = model_->lineStartOf(state.firstPiece);
            return FormatPassUtil::lineWidth(*model_, lineStart) <= options_->columnLimit;
        }

        void chooseLogicalLineMode(LogicalState& state)
        {
            if (!state.editable)
                return;

            if (state.forceSingleLine.value_or(false))
            {
                if (joinLogicalExpression(state))
                    state.lineMode = ListLineMode::SingleLine;
                return;
            }

            if (!state.sourceSelectsLayout.has_value())
                return;

            if (*state.sourceSelectsLayout)
            {
                if (firstLogicalOperandsShareSourceLine(state) && joinLogicalExpression(state))
                    state.lineMode = ListLineMode::SingleLine;
                else
                    state.lineMode = ListLineMode::MultiLine;
                return;
            }

            if (!state.canJoin)
            {
                state.lineMode = ListLineMode::MultiLine;
                return;
            }

            const std::vector<FormatGap> originalGaps = snapshotLogicalGaps(state);
            const bool                   joined       = joinLogicalExpression(state);
            SWC_ASSERT(joined);
            if (joinedLogicalExpressionFits(state))
            {
                state.lineMode = ListLineMode::SingleLine;
                return;
            }

            restoreLogicalGaps(state, originalGaps);
            state.lineMode = ListLineMode::MultiLine;
        }

        bool listIsMultiline(const ListState& state) const
        {
            for (uint32_t i = state.openPiece + 1; i <= state.closePiece; ++i)
            {
                if (!model_->piece(i).removed && model_->gapHasNewline(i))
                    return true;
            }
            return false;
        }

        Utf8 fixedContinuationIndent(const ListState& state) const
        {
            const uint32_t tabWidth = std::max(options_->tabWidth, 1u);
            const uint32_t baseCols = FormatModel::textColumns(model_->lineIndentOf(state.openPiece), tabWidth);
            return FormatPassUtil::indentForColumns(*model_, baseCols + std::max(options_->continuationIndentWidth, 1u));
        }

        uint32_t openColumn(const ListState& state) const
        {
            std::vector<PieceColumn> columns;
            FormatPassUtil::computeLineColumns(*model_, model_->lineStartOf(state.openPiece), &columns);
            for (const PieceColumn& column : columns)
            {
                if (column.piece == state.openPiece)
                    return column.column;
            }
            return UINT32_MAX;
        }

        bool literalStartsOnNextSourceLine(const ListState& state) const
        {
            return state.literal && !state.items.empty() && textHasNewline(model_->gapBefore(state.items.front()).origText);
        }

        // Where the first item actually starts on the bracket's line. That is
        // one past the bracket in every list the spacing pass tightens, but a
        // type-level brace keeps its inner blank, and hanging alignment has to
        // line up with the item rather than with the bracket.
        uint32_t firstItemColumn(const ListState& state) const
        {
            std::vector<PieceColumn> columns;
            FormatPassUtil::computeLineColumns(*model_, model_->lineStartOf(state.openPiece), &columns);
            for (size_t c = 0; c + 1 < columns.size(); ++c)
            {
                if (columns[c].piece == state.openPiece)
                    return columns[c + 1].column;
            }
            return UINT32_MAX;
        }

        Utf8 listItemIndent(const ListState& state) const
        {
            if (state.layout == FormatListLayout::HangingAlign && !literalStartsOnNextSourceLine(state))
            {
                const uint32_t item = firstItemColumn(state);
                if (item != UINT32_MAX)
                    return FormatPassUtil::indentForColumns(*model_, item);

                const uint32_t column = openColumn(state);
                if (column != UINT32_MAX)
                    return FormatPassUtil::indentForColumns(*model_, column + 1);
            }

            if (state.layout == FormatListLayout::Preserve)
            {
                for (const uint32_t item : state.items)
                {
                    if (model_->gapHasNewline(item))
                        return Utf8(model_->lineIndentOf(item));
                }
            }

            return fixedContinuationIndent(state);
        }

        void attachFirstItem(const ListState& state) const
        {
            if (state.items.empty() || state.hasComment)
                return;
            const uint32_t first = state.items.front();
            if (model_->gapHasNewline(first) && FormatPassUtil::canEditGap(*model_, first))
                model_->setGapSpaces(first, spacesAfterOpen(state));
        }

        void breakFirstItem(const ListState& state) const
        {
            if (state.items.empty() || state.hasComment)
                return;
            const uint32_t first = state.items.front();
            if (FormatPassUtil::canEditGap(*model_, first))
                model_->setGapBreak(first, 1, fixedContinuationIndent(state).view());
        }

        void applyListShape(const ListState& state) const
        {
            if (state.hug)
            {
                hugItems(state);
                return;
            }

            switch (state.layout)
            {
                case FormatListLayout::HangingIndent:
                case FormatListLayout::HangingAlign:
                    if (literalStartsOnNextSourceLine(state))
                        breakFirstItem(state);
                    else
                        attachFirstItem(state);
                    break;
                case FormatListLayout::Vertical:
                case FormatListLayout::Block:
                    breakFirstItem(state);
                    break;
                case FormatListLayout::Preserve:
                    break;
            }
        }

        uint32_t requiredPackedBreak(const ListState& state) const
        {
            if (state.items.empty())
                return INVALID_PIECE;
            if (state.layout == FormatListLayout::Vertical || state.layout == FormatListLayout::Block)
                return state.items.front();
            if ((state.layout == FormatListLayout::HangingIndent || state.layout == FormatListLayout::HangingAlign) && state.items.size() > 1)
                return state.items[1];

            for (const uint32_t item : state.items)
            {
                if (model_->gapHasNewline(item))
                    return item;
            }
            return INVALID_PIECE;
        }

        void packExistingLines(const ListState& state) const
        {
            if (state.hug || state.binPack != FormatBinPackStyle::Pack || state.hasComment || !listIsMultiline(state))
                return;

            const uint32_t requiredBreak = requiredPackedBreak(state);
            for (size_t i = 0; i < state.items.size(); ++i)
            {
                const uint32_t item = state.items[i];
                if (item == requiredBreak || !model_->gapHasNewline(item) || !FormatPassUtil::canEditGap(*model_, item))
                    continue;
                model_->setGapSpaces(item, i == 0 ? spacesAfterOpen(state) : spacesAfterComma());
            }
        }

        void prepareLists()
        {
            for (const ListState& state : lists_)
            {
                if (state.lineMode == ListLineMode::SingleLine)
                    continue;
                if (state.lineMode == ListLineMode::MultiLine || listIsMultiline(state))
                    applyListShape(state);
                packExistingLines(state);
            }
        }

        bool logicalExpressionIsMultiline(const LogicalState& state) const
        {
            for (uint32_t i = state.firstPiece + 1; i <= state.lastPiece; ++i)
            {
                if (!model_->piece(i).removed && model_->gapHasNewline(i))
                    return true;
            }
            return false;
        }

        bool logicalBoundaryIsBroken(const LogicalState& state, const size_t index) const
        {
            return model_->gapHasNewline(state.operators[index]) || model_->gapHasNewline(state.operands[index + 1]);
        }

        FormatOperatorWrapStyle logicalBoundaryPosition(const LogicalState& state, const size_t index) const
        {
            if (state.breakPosition == FormatOperatorWrapStyle::Before || state.breakPosition == FormatOperatorWrapStyle::After)
                return state.breakPosition;
            if (model_->gapHasNewline(state.operators[index]))
                return FormatOperatorWrapStyle::Before;
            if (model_->gapHasNewline(state.operands[index + 1]))
                return FormatOperatorWrapStyle::After;
            if (options_->breakBeforeBinaryOperators == FormatOperatorWrapStyle::Before ||
                options_->breakBeforeBinaryOperators == FormatOperatorWrapStyle::After)
                return options_->breakBeforeBinaryOperators;
            return FormatOperatorWrapStyle::After;
        }

        Utf8 fixedLogicalIndent(const LogicalState& state) const
        {
            const uint32_t tabWidth = std::max(options_->tabWidth, 1u);
            const uint32_t baseCols = FormatModel::textColumns(model_->lineIndentOf(state.firstPiece), tabWidth);
            return FormatPassUtil::indentForColumns(*model_, baseCols + std::max(options_->continuationIndentWidth, 1u));
        }

        uint32_t logicalFirstOperandColumn(const LogicalState& state) const
        {
            std::vector<PieceColumn> columns;
            FormatPassUtil::computeLineColumns(*model_, model_->lineStartOf(state.firstPiece), &columns);
            for (const PieceColumn& column : columns)
            {
                if (column.piece == state.firstPiece)
                    return column.column;
            }
            return UINT32_MAX;
        }

        Utf8 logicalIndent(const LogicalState& state) const
        {
            if (state.layout == FormatLogicalLayout::HangingAlign)
            {
                const uint32_t column = logicalFirstOperandColumn(state);
                if (column != UINT32_MAX)
                    return FormatPassUtil::indentForColumns(*model_, column);
            }

            if (state.layout == FormatLogicalLayout::Preserve)
            {
                for (size_t i = 0; i < state.operators.size(); ++i)
                {
                    if (model_->gapHasNewline(state.operators[i]))
                        return Utf8(model_->lineIndentOf(state.operators[i]));
                    if (model_->gapHasNewline(state.operands[i + 1]))
                        return Utf8(model_->lineIndentOf(state.operands[i + 1]));
                }
            }

            return fixedLogicalIndent(state);
        }

        uint32_t firstBrokenLogicalOperator(const LogicalState& state) const
        {
            for (size_t i = 0; i < state.operators.size(); ++i)
            {
                if (logicalBoundaryIsBroken(state, i))
                    return static_cast<uint32_t>(i);
            }
            return INVALID_PIECE;
        }

        void setLogicalBoundaryBreak(const LogicalState& state, const size_t index, const Utf8& indent) const
        {
            const uint32_t                op       = state.operators[index];
            const uint32_t                operand  = state.operands[index + 1];
            const FormatOperatorWrapStyle position = logicalBoundaryPosition(state, index);
            if (position == FormatOperatorWrapStyle::Before)
            {
                if (model_->gapHasNewline(operand))
                    model_->setGapSpaces(operand, 1);
                model_->setGapBreak(op, 1, indent.view());
            }
            else
            {
                if (model_->gapHasNewline(op))
                    model_->setGapSpaces(op, 1);
                model_->setGapBreak(operand, 1, indent.view());
            }
        }

        void normalizeLogicalBoundaries(const LogicalState& state, const Utf8& indent) const
        {
            for (size_t i = 0; i < state.operators.size(); ++i)
            {
                if (logicalBoundaryIsBroken(state, i))
                    setLogicalBoundaryBreak(state, i, indent);
            }
        }

        void applyLogicalPacking(const LogicalState& state, const Utf8& indent) const
        {
            if (state.packing == FormatLogicalPacking::Preserve || state.hasComment || !state.editable)
                return;

            uint32_t requiredBreak = firstBrokenLogicalOperator(state);
            if (requiredBreak == INVALID_PIECE && state.lineMode == ListLineMode::MultiLine)
                requiredBreak = 0;

            joinLogicalBoundaries(state);
            switch (state.packing)
            {
                case FormatLogicalPacking::Pack:
                    if (requiredBreak != INVALID_PIECE)
                        setLogicalBoundaryBreak(state, requiredBreak, indent);
                    break;
                case FormatLogicalPacking::ByPrecedence:
                {
                    if (requiredBreak != INVALID_PIECE)
                        setLogicalBoundaryBreak(state, requiredBreak, indent);
                    for (size_t i = 0; i < state.operators.size(); ++i)
                    {
                        if (model_->piece(state.operators[i]).isNot(TokenId::KwdOr))
                            continue;
                        setLogicalBoundaryBreak(state, i, indent);
                    }
                    break;
                }
                case FormatLogicalPacking::OnePerLine:
                    for (size_t i = 0; i < state.operators.size(); ++i)
                        setLogicalBoundaryBreak(state, i, indent);
                    break;
                case FormatLogicalPacking::Preserve:
                    break;
            }
        }

        void prepareLogicalExpressions() const
        {
            for (const LogicalState& state : logicalExpressions_)
            {
                if (state.lineMode == ListLineMode::SingleLine)
                    continue;
                if (state.lineMode != ListLineMode::MultiLine && !logicalExpressionIsMultiline(state))
                    continue;

                const Utf8 indent = logicalIndent(state);
                applyLogicalPacking(state, indent);
                normalizeLogicalBoundaries(state, indent);
            }
        }

        bool lineEditable(const uint32_t lineStart) const
        {
            uint32_t piece = lineStart;
            for (;;)
            {
                if (model_->piece(piece).frozen || model_->gapBefore(piece).frozen)
                    return false;
                const uint32_t next = model_->nextPiece(piece);
                if (next == INVALID_PIECE || model_->gapHasNewline(next))
                    return true;
                piece = next;
            }
        }

        bool commaBelongsToSingleLineList(const uint32_t commaPiece) const
        {
            for (auto it = lists_.rbegin(); it != lists_.rend(); ++it)
            {
                const ListState& state = *it;
                if (state.lineMode != ListLineMode::SingleLine || commaPiece <= state.openPiece || commaPiece >= state.closePiece)
                    continue;
                if (model_->piece(commaPiece).depth == model_->piece(state.openPiece).depth + 1)
                    return true;
            }
            return false;
        }

        bool isWrappableComma(const uint32_t commaPiece) const
        {
            const FormatPiece& piece = model_->piece(commaPiece);
            return piece.is(TokenId::SymComma) && !piece.hasRole(FormatRoleE::ClosureCaptureComma) &&
                   !commaBelongsToSingleLineList(commaPiece);
        }

        const LogicalState* logicalExpressionForBoundary(const uint32_t pieceIndex) const
        {
            const LogicalState* result     = nullptr;
            uint32_t            resultSize = UINT32_MAX;
            for (const LogicalState& state : logicalExpressions_)
            {
                if (pieceIndex < state.firstPiece || pieceIndex > state.lastPiece || !isLogicalBoundaryGap(state, pieceIndex))
                    continue;
                const uint32_t size = state.lastPiece - state.firstPiece;
                if (size < resultSize)
                {
                    result     = &state;
                    resultSize = size;
                }
            }
            return result;
        }

        FormatOperatorWrapStyle operatorWrapStyle(const uint32_t operatorPiece) const
        {
            if (!model_->piece(operatorPiece).hasRole(FormatRoleE::LogicalOp))
                return options_->breakBeforeBinaryOperators;

            const LogicalState* state = logicalExpressionForBoundary(operatorPiece);
            if (!state)
                return options_->breakBeforeBinaryOperators;
            if (state->lineMode == ListLineMode::SingleLine)
                return FormatOperatorWrapStyle::None;
            if (state->breakPosition == FormatOperatorWrapStyle::Before || state->breakPosition == FormatOperatorWrapStyle::After)
                return state->breakPosition;
            return options_->breakBeforeBinaryOperators;
        }

        const ListState* listContaining(const uint32_t pieceIndex) const
        {
            for (auto it = lists_.rbegin(); it != lists_.rend(); ++it)
            {
                if (pieceIndex > it->openPiece && pieceIndex < it->closePiece)
                    return &*it;
            }
            return nullptr;
        }

        // One statement, one continuation indent. A line that a break produced is
        // queued with the indent that break used, because measuring again from
        // the new line would step one level further right at every break.
        struct PendingWrap
        {
            uint32_t lineStart = INVALID_PIECE;
            Utf8     indent;
            bool     continuation = false;
        };

        void wrapLongLines()
        {
            if (options_->columnLimit == 0)
                return;

            std::vector<uint32_t> lineStarts;
            model_->collectLineStarts(lineStarts);

            std::deque<PendingWrap> queue;
            for (const uint32_t lineStart : lineStarts)
                queue.push_back({lineStart, {}, false});

            uint32_t guard = 0;
            while (!queue.empty() && guard < 100000)
            {
                guard++;
                const PendingWrap pending = queue.front();
                queue.pop_front();

                PendingWrap produced;
                produced.lineStart = wrapLine(pending, produced.indent);
                if (produced.lineStart != INVALID_PIECE)
                {
                    produced.continuation = true;
                    queue.push_front(produced);
                }
            }
        }

        uint32_t wrapLine(const PendingWrap& pending, Utf8& outIndent) const
        {
            std::vector<PieceColumn> columns;
            const uint32_t           width = FormatPassUtil::computeLineColumns(*model_, pending.lineStart, &columns);
            if (width <= options_->columnLimit || columns.size() < 2 || !lineEditable(pending.lineStart))
                return INVALID_PIECE;

            const uint32_t breakPiece = chooseBreak(columns);
            if (breakPiece == INVALID_PIECE)
                return INVALID_PIECE;

            outIndent = pending.continuation ? pending.indent : continuationIndent(pending.lineStart, columns, breakPiece);
            model_->setGapBreak(breakPiece, 1, outIndent.view());
            return breakPiece;
        }

        // The piece a break before `columns[c]` would put on the next line, or
        // INVALID_PIECE when that position is not a break the options allow.
        uint32_t breakCandidateAt(const std::vector<PieceColumn>& columns, const size_t c) const
        {
            const uint32_t     pieceIndex = columns[c].piece;
            const FormatPiece& piece      = model_->piece(pieceIndex);
            const uint32_t     next       = c + 1 < columns.size() ? columns[c + 1].piece : INVALID_PIECE;

            uint32_t candidate = INVALID_PIECE;
            if (isWrappableComma(pieceIndex))
                candidate = next;
            else if (piece.hasRole(FormatRoleE::BinaryOp))
            {
                const FormatOperatorWrapStyle opStyle = operatorWrapStyle(pieceIndex);
                if (opStyle == FormatOperatorWrapStyle::Before)
                    candidate = pieceIndex;
                else if (opStyle == FormatOperatorWrapStyle::After)
                    candidate = next;
            }
            else if (piece.hasRole(FormatRoleE::TernaryOp) && options_->breakBeforeTernaryOperators.value_or(false))
                candidate = pieceIndex;
            else if (piece.hasRole(FormatRoleE::Arrow) && options_->breakAfterReturnType.value_or(false))
                candidate = pieceIndex;
            else if (piece.hasRole(FormatRoleE::TrailingDo) && options_->breakBeforeDo.value_or(false))
                candidate = pieceIndex;

            if (candidate == INVALID_PIECE || candidate == columns.front().piece || model_->piece(candidate).isComment)
                return INVALID_PIECE;
            return candidate;
        }

        // How much of the expression a break at this token preserves: a list
        // separator cuts between whole items, and below it the operators rank by
        // precedence, so `and` is cut before `<` and `<` before `*`.
        static uint32_t breakRank(const FormatPiece& piece)
        {
            if (piece.is(TokenId::SymComma))
                return 0;
            if (Token::isOpLogical(piece.id))
                return 1;
            if (Token::isOpRelational(piece.id))
                return 2;
            if (Token::isOpArithmeticOrBitwise(piece.id))
                return 3;
            return 4;
        }

        // One break at a time, chosen locally — see the pass header. The break
        // that keeps the most structure is the one highest in the expression
        // tree: first the shallowest bracket depth, so a top-level `+` beats a
        // comma nested inside one of its operands however much earlier that
        // comma sits, then the loosest-binding token at that depth. Among the
        // remaining candidates the last one that still fits wins, which fills
        // the line.
        uint32_t chooseBreak(const std::vector<PieceColumn>& columns) const
        {
            const uint32_t limit = options_->columnLimit;

            uint32_t bestDepth = UINT32_MAX;
            uint32_t bestRank  = UINT32_MAX;
            for (size_t c = 0; c < columns.size(); ++c)
            {
                if (breakCandidateAt(columns, c) == INVALID_PIECE)
                    continue;
                const FormatPiece& piece = model_->piece(columns[c].piece);
                if (piece.depth < bestDepth)
                {
                    bestDepth = piece.depth;
                    bestRank  = UINT32_MAX;
                }
                if (piece.depth == bestDepth)
                    bestRank = std::min(bestRank, breakRank(piece));
            }
            if (bestDepth == UINT32_MAX)
                return INVALID_PIECE;

            const uint32_t tabWidth = std::max(options_->tabWidth, 1u);
            uint32_t       best     = INVALID_PIECE;
            uint32_t       firstAny = INVALID_PIECE;
            for (size_t c = 0; c < columns.size(); ++c)
            {
                const uint32_t     candidate = breakCandidateAt(columns, c);
                const FormatPiece& piece     = model_->piece(columns[c].piece);
                if (candidate == INVALID_PIECE || piece.depth != bestDepth || breakRank(piece) != bestRank)
                    continue;
                if (firstAny == INVALID_PIECE)
                    firstAny = candidate;

                // What has to fit is the line the break leaves behind. Breaking
                // *after* a token puts that token on it, so its end column is
                // what the limit applies to, not where it starts.
                const uint32_t end = candidate == columns[c].piece
                                               ? columns[c].column
                                               : columns[c].column + FormatModel::textColumns(piece.text, tabWidth, columns[c].column);
                if (end <= limit)
                    best = candidate;
            }

            return best != INVALID_PIECE ? best : firstAny;
        }

        Utf8 continuationIndent(const uint32_t lineStart, const std::vector<PieceColumn>& columns, const uint32_t breakPiece) const
        {
            const LogicalState* logical = logicalExpressionForBoundary(breakPiece);
            if (logical && logical->lineMode != ListLineMode::SingleLine && logical->layout != FormatLogicalLayout::Preserve)
                return logicalIndent(*logical);

            const ListState* list = listContaining(breakPiece);
            if (list && list->lineMode != ListLineMode::SingleLine && list->layout != FormatListLayout::Preserve)
                return listItemIndent(*list);

            if (options_->alignAfterOpenBracket.value_or(false))
            {
                uint32_t              openBracketColumn = UINT32_MAX;
                std::vector<uint32_t> stack;
                for (const auto& [pieceIndex, column] : columns)
                {
                    if (pieceIndex == breakPiece)
                        break;
                    const FormatPiece& piece = model_->piece(pieceIndex);
                    if (piece.is(TokenId::SymLeftParen) || piece.is(TokenId::SymLeftBracket))
                        stack.push_back(column);
                    else if (piece.is(TokenId::SymRightParen) || piece.is(TokenId::SymRightBracket))
                    {
                        if (!stack.empty())
                            stack.pop_back();
                    }
                }
                if (!stack.empty())
                    openBracketColumn = stack.back();
                if (openBracketColumn != UINT32_MAX)
                    return FormatPassUtil::indentForColumns(*model_, openBracketColumn + 1);
            }

            const uint32_t tabWidth = std::max(options_->tabWidth, 1u);
            const uint32_t baseCols = FormatModel::textColumns(model_->lineIndentOf(lineStart), tabWidth);
            return FormatPassUtil::indentForColumns(*model_, baseCols + std::max(options_->continuationIndentWidth, 1u));
        }

        void applyOnePerLine(const ListState& state, const Utf8& indent) const
        {
            if (state.hug || state.binPack != FormatBinPackStyle::OnePerLine || state.items.size() < 2 || state.hasComment)
                return;

            for (size_t i = 1; i < state.items.size(); ++i)
            {
                const uint32_t item = state.items[i];
                if (FormatPassUtil::canEditGap(*model_, item))
                    model_->setGapBreak(item, 1, indent.view());
            }
        }

        void alignBrokenItems(const ListState& state, const Utf8& indent) const
        {
            if (state.hug || state.layout == FormatListLayout::Preserve || state.hasComment)
                return;

            for (const uint32_t item : state.items)
            {
                if (model_->gapHasNewline(item) && FormatPassUtil::canEditGap(*model_, item))
                    model_->setGapBreak(item, 1, indent.view());
            }
        }

        void placeClose(const ListState& state) const
        {
            if (state.hasComment || !FormatPassUtil::canEditGap(*model_, state.closePiece))
                return;

            if (state.layout == FormatListLayout::Block)
            {
                model_->setGapBreak(state.closePiece, 1, model_->lineIndentOf(state.openPiece));
                return;
            }

            if (state.layout != FormatListLayout::Preserve && model_->gapHasNewline(state.closePiece))
                model_->setGapSpaces(state.closePiece, spacesBeforeClose(state));
        }

        bool isMultilineLiteralItem(const uint32_t item) const
        {
            const FormatPiece& piece = model_->piece(item);
            return piece.is(TokenId::SymLeftBracket) || piece.is(TokenId::SymLeftCurly) || piece.is(TokenId::KwdFunc) ||
                   piece.is(TokenId::CompilerCode);
        }

        bool isStructuralItemLine(const FormatPiece& piece, const bool bracketItem, const uint32_t itemDepth) const
        {
            if (bracketItem && piece.depth == itemDepth + 1)
                return true;
            if (piece.is(TokenId::SymRightParen) || piece.is(TokenId::SymRightBracket) || piece.is(TokenId::SymRightCurly))
                return true;
            return piece.roles.hasAny({FormatRoleE::StmtStart, FormatRoleE::CaseLabel, FormatRoleE::AttrOpen,
                                       FormatRoleE::ElseKeyword, FormatRoleE::EnumValueStart, FormatRoleE::FieldDeclStart,
                                       FormatRoleE::BlockOpen, FormatRoleE::BlockClose, FormatRoleE::LiteralOpen,
                                       FormatRoleE::LiteralClose, FormatRoleE::DestructuringClose, FormatRoleE::WhereKeyword});
        }

        uint32_t inlineBodyDepthAt(const uint32_t pieceIndex) const
        {
            uint32_t result = 0;
            for (const FormatInlineBody& body : model_->inlineBodies())
            {
                if (pieceIndex > body.doPiece && pieceIndex <= body.lastPiece)
                    result++;
            }
            return result;
        }

        void alignMultilineItemContents(const ListState& state, const size_t itemIndex) const
        {
            const uint32_t item = state.items[itemIndex];
            if (!isMultilineLiteralItem(item))
                return;

            // A hugged block keeps its opening token on the call line, so its own
            // gap carries no newline; its content still has to follow that line.
            const bool hugged = state.hug && itemIndex + 1 == state.items.size();
            if (!hugged && !model_->gapHasNewline(item))
                return;

            const uint32_t rangeEnd = itemIndex + 1 < state.items.size() ? model_->prevPiece(state.items[itemIndex + 1])
                                                                         : model_->prevPiece(state.closePiece);
            if (rangeEnd == INVALID_PIECE || rangeEnd <= item)
                return;

            const uint32_t tabWidth        = std::max(options_->tabWidth, 1u);
            const uint32_t itemCols        = FormatModel::textColumns(model_->lineIndentOf(item), tabWidth);
            const uint32_t itemDepth       = model_->piece(item).depth;
            const uint32_t itemInlineDepth = inlineBodyDepthAt(item);
            const bool     bracketItem     = model_->piece(item).is(TokenId::SymLeftBracket) || model_->piece(item).is(TokenId::SymLeftCurly);
            int32_t        lastDelta       = 0;

            for (uint32_t lineStart = model_->nextPiece(item); lineStart != INVALID_PIECE && lineStart <= rangeEnd; lineStart = model_->nextPiece(lineStart))
            {
                if (!model_->gapHasNewline(lineStart))
                    continue;
                if (!FormatPassUtil::canEditGap(*model_, lineStart))
                    continue;

                const FormatPiece& piece      = model_->piece(lineStart);
                const uint32_t     current    = FormatModel::textColumns(model_->lineIndentOf(lineStart), tabWidth);
                uint32_t           targetCols = current;
                if (isStructuralItemLine(piece, bracketItem, itemDepth))
                {
                    uint32_t structuralDepth = piece.depth;
                    if (piece.match != INVALID_PIECE &&
                        (piece.is(TokenId::SymRightParen) || piece.is(TokenId::SymRightBracket) || piece.is(TokenId::SymRightCurly)))
                        structuralDepth = model_->piece(piece.match).depth;
                    const uint32_t bracketDepth     = structuralDepth > itemDepth ? structuralDepth - itemDepth : 0;
                    const uint32_t pieceInlineDepth = inlineBodyDepthAt(lineStart);
                    const uint32_t inlineDepth      = pieceInlineDepth > itemInlineDepth ? pieceInlineDepth - itemInlineDepth : 0;
                    const uint32_t relativeDepth    = bracketDepth + inlineDepth;
                    targetCols                      = itemCols + relativeDepth * std::max(options_->indentWidth, 1u);
                    lastDelta                       = static_cast<int32_t>(targetCols) - static_cast<int32_t>(current);
                }
                else
                {
                    const int32_t shifted = static_cast<int32_t>(current) + lastDelta;
                    targetCols            = shifted > 0 ? static_cast<uint32_t>(shifted) : 0;
                }

                if (targetCols != current)
                    model_->setGapBreak(lineStart, model_->gapNewlineCount(lineStart), FormatPassUtil::indentForColumns(*model_, targetCols).view());
            }
        }

        void finishLists() const
        {
            for (const ListState& state : lists_)
            {
                if (state.lineMode == ListLineMode::SingleLine || !listIsMultiline(state))
                    continue;

                applyListShape(state);
                const Utf8 indent = listItemIndent(state);
                applyOnePerLine(state, indent);
                alignBrokenItems(state, indent);
                placeClose(state);
                for (size_t i = 0; i < state.items.size(); ++i)
                    alignMultilineItemContents(state, i);
                recordHangingItems(state);
            }
        }

        // A continuation line placed under its bracket has to move with that
        // bracket when the alignment pass later shifts the line the bracket sits
        // on. The indent pass records the lines it placed so alignment can
        // replay them; a line this pass creates needs the same record, or it
        // only reaches its column on the next run of the formatter.
        void recordHangingItems(const ListState& state) const
        {
            if (state.hug || state.layout != FormatListLayout::HangingAlign || literalStartsOnNextSourceLine(state))
                return;

            const uint32_t open = openColumn(state);
            if (open == UINT32_MAX)
                return;
            const uint32_t item   = firstItemColumn(state);
            const uint32_t offset = item != UINT32_MAX && item > open ? item - open : 1;

            for (const uint32_t piece : state.items)
            {
                if (model_->gapHasNewline(piece) && FormatPassUtil::canEditGap(*model_, piece))
                    model_->hangingLines().push_back({piece, state.openPiece, offset});
            }
        }

        void addRequiredLogicalBreaks(const LogicalState& state, const Utf8& indent) const
        {
            if (state.packing == FormatLogicalPacking::OnePerLine)
            {
                for (size_t i = 0; i < state.operators.size(); ++i)
                    setLogicalBoundaryBreak(state, i, indent);
                return;
            }

            if (state.packing != FormatLogicalPacking::ByPrecedence)
                return;

            if (state.lineMode == ListLineMode::MultiLine)
                setLogicalBoundaryBreak(state, 0, indent);
            for (size_t i = 0; i < state.operators.size(); ++i)
            {
                if (model_->piece(state.operators[i]).isNot(TokenId::KwdOr))
                    continue;
                setLogicalBoundaryBreak(state, i, indent);
            }
        }

        void finishLogicalExpressions() const
        {
            for (const LogicalState& state : logicalExpressions_)
            {
                if (state.lineMode == ListLineMode::SingleLine || !logicalExpressionIsMultiline(state))
                    continue;
                const Utf8 indent = logicalIndent(state);
                addRequiredLogicalBreaks(state, indent);
                normalizeLogicalBoundaries(state, indent);
                recordHangingOperands(state);
            }
        }

        // Same rule as `recordHangingItems`: an operand line placed under the
        // expression's first operand has to follow that operand when alignment
        // shifts the line it sits on.
        void recordHangingOperands(const LogicalState& state) const
        {
            if (state.layout != FormatLogicalLayout::HangingAlign || logicalFirstOperandColumn(state) == UINT32_MAX)
                return;

            for (size_t i = 0; i < state.operators.size(); ++i)
            {
                for (const uint32_t boundary : {state.operators[i], state.operands[i + 1]})
                {
                    if (model_->gapHasNewline(boundary) && FormatPassUtil::canEditGap(*model_, boundary))
                        model_->hangingLines().push_back({boundary, state.firstPiece, 0});
                }
            }
        }

        FormatModel*              model_;
        const FormatOptions*      options_;
        std::vector<ListState>    lists_;
        std::vector<LogicalState> logicalExpressions_;
    };
}

namespace FormatPass
{
    void wrap(FormatModel& model)
    {
        WrapPass(model).run();
    }
}

SWC_END_NAMESPACE();
