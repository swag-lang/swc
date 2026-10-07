#include "pch.h"
#include "Format/FormatPassUtil.h"
#include "Format/FormatPasses.h"
#include "Format/FormatSiblings.h"

SWC_BEGIN_NAMESPACE();

namespace
{
    using FormatPassUtil::INVALID_PIECE;
    using FormatSiblings::BodyShape;

    // Rewrites the syntax of sibling bodies so they share one form: `do` or
    // braces for the branches of a chain, `{ return e }` or `=> e` for closures
    // and functions. Each rewrite only swaps, drops, or extends existing
    // pieces; the caller parses the result again before laying it out, so the
    // text written here only has to be valid, not well placed.
    class UniformPass
    {
    public:
        explicit UniformPass(FormatModel& model) :
            model_(&model),
            options_(&model.options())
        {
        }

        bool run()
        {
            rewriteBranches();
            rewriteClosures();
            rewriteFunctions();
            return changed_;
        }

    private:
        // `{ stmt }` -> `do stmt`. The statement keeps its own gap; a `do`
        // body never shares the next branch's line.
        bool canUnbrace(const FormatBranch& branch) const
        {
            const uint32_t prev = model_->prevPiece(branch.openPiece);
            return prev != INVALID_PIECE && !model_->piece(prev).isComment;
        }

        void unbrace(const FormatBranch& branch)
        {
            model_->replaceText(branch.openPiece, Utf8("do"));
            model_->setGapSpaces(branch.openPiece, 1);

            const uint32_t next = model_->nextPiece(branch.lastPiece);
            model_->removePiece(branch.lastPiece);
            if (next != INVALID_PIECE && !model_->gapHasNewline(next) && model_->piece(next).roles.hasAny({FormatRoleE::ElseKeyword}))
                model_->setGapBreak(next, 1, model_->lineIndentOf(branch.keyword));
            changed_ = true;
        }

        // Closes a body that gains braces right after its last piece.
        void appendClose(const uint32_t last)
        {
            Utf8 text(model_->piece(last).text);
            text += model_->eol();
            text += "}";
            model_->replaceText(last, std::move(text));

            // A number now carries the brace after it: render it as plain text,
            // the parse that follows reads the number again.
            model_->piece(last).id = TokenId::Identifier;
        }

        // `do stmt` -> `{ stmt }`.
        void brace(const FormatBranch& branch, const BodyShape& shape)
        {
            model_->replaceText(branch.doPiece, Utf8("{"));
            appendClose(shape.last);
            changed_ = true;
        }

        void rewriteBranches()
        {
            const bool chains = options_->uniformBranchBodies.value_or(false);
            for (const auto& group : FormatSiblings::branchGroups(*model_, chains, options_->uniformGuardBodies))
            {
                std::vector<const FormatBranch*> branches;
                std::vector<BodyShape>           shapes;
                bool                             guards = true;
                for (const auto& [chain, index] : group)
                {
                    branches.push_back(&model_->branchChains()[chain].branches[index]);
                    shapes.push_back(FormatSiblings::branchShape(*model_, *branches.back()));
                    guards = guards && model_->branchChains()[chain].branches.size() == 1;
                }

                bool valid      = true;
                bool hasInline  = false;
                bool hasBraced  = false;
                bool unbraceAll = true;
                bool braceAll   = true;
                for (size_t i = 0; i < shapes.size(); ++i)
                {
                    const BodyShape& shape = shapes[i];
                    valid                  = valid && shape.valid;
                    hasInline              = hasInline || !shape.braced;
                    hasBraced              = hasBraced || shape.braced;
                    if (shape.braced)
                        unbraceAll = unbraceAll && shape.unbraceable && canUnbrace(*branches[i]);
                    else
                    {
                        unbraceAll = unbraceAll && shape.compact;
                        braceAll   = braceAll && shape.braceable;
                    }
                }
                if (!valid || !hasInline || !hasBraced)
                    continue;

                // A run of guards only ever shrinks: a guard reads as one line
                // whatever its neighbours hold.
                if (unbraceAll)
                {
                    for (size_t i = 0; i < shapes.size(); ++i)
                    {
                        if (shapes[i].braced)
                            unbrace(*branches[i]);
                    }
                }
                else if (!guards && braceAll)
                {
                    for (size_t i = 0; i < shapes.size(); ++i)
                    {
                        if (!shapes[i].braced)
                            brace(*branches[i], shapes[i]);
                    }
                }
            }
        }

        // `{ return e }` -> `=> e`.
        bool canUnbraceFunction(const FormatFunctionBody& body, const BodyShape& shape) const
        {
            if (!shape.braced || !shape.unbraceable)
                return false;
            const uint32_t prev = model_->prevPiece(body.openPiece);
            return prev != INVALID_PIECE && !model_->piece(prev).isComment;
        }

        void unbraceFunction(const FormatFunctionBody& body, const BodyShape& shape)
        {
            model_->replaceText(body.openPiece, Utf8("=>"));
            model_->setGapSpaces(body.openPiece, 1);
            model_->removePiece(shape.first);
            model_->removePiece(body.lastPiece);
            changed_ = true;
        }

        // A group of closures that cannot all stand on one line is expanded:
        // `=> e` gains a body. One that can is compacted: `{ return e }`
        // becomes `=> e`. The layout pass then splits or joins the bodies.
        void rewriteClosures()
        {
            const auto& bodies = model_->functionBodies();
            for (const auto& group : FormatSiblings::closureGroups(*model_, options_->uniformClosureBodies))
            {
                bool                   oneLine  = false;
                bool                   expanded = false;
                bool                   compact  = true;
                std::vector<BodyShape> shapes;
                for (const uint32_t i : group)
                {
                    shapes.push_back(FormatSiblings::functionShape(*model_, bodies[i]));
                    const BodyShape& shape = shapes.back();
                    oneLine                = oneLine || shape.oneLine;
                    expanded               = expanded || !shape.oneLine;
                    compact                = compact && shape.compact;
                }
                if (!oneLine || !expanded)
                    continue;

                for (size_t i = 0; i < group.size(); ++i)
                {
                    const FormatFunctionBody& body  = bodies[group[i]];
                    const BodyShape&          shape = shapes[i];
                    if (compact)
                    {
                        if (shape.valid && canUnbraceFunction(body, shape))
                            unbraceFunction(body, shape);
                        continue;
                    }

                    if (shape.braced || !shape.valid || !shape.braceable)
                        continue;

                    Utf8 open("{");
                    open += model_->eol();
                    open += "return";
                    model_->replaceText(body.arrowPiece, std::move(open));
                    appendClose(shape.last);
                    changed_ = true;
                }
            }
        }

        // Single-statement functions declared side by side, some already on
        // one line: `{ return e }` becomes `=> e`. The layout pass joins the
        // bodies that return nothing.
        void rewriteFunctions()
        {
            const auto& bodies = model_->functionBodies();
            for (const auto& group : FormatSiblings::functionGroups(*model_, options_->uniformFunctionBodies))
            {
                bool                   oneLine  = false;
                bool                   expanded = false;
                bool                   compact  = true;
                std::vector<BodyShape> shapes;
                for (const uint32_t i : group)
                {
                    shapes.push_back(FormatSiblings::functionShape(*model_, bodies[i]));
                    const BodyShape& shape = shapes.back();
                    oneLine                = oneLine || shape.oneLine;
                    expanded               = expanded || !shape.oneLine;
                    compact                = compact && shape.compact && shape.valid;
                }
                if (!oneLine || !expanded || !compact)
                    continue;

                for (size_t i = 0; i < group.size(); ++i)
                {
                    if (canUnbraceFunction(bodies[group[i]], shapes[i]))
                        unbraceFunction(bodies[group[i]], shapes[i]);
                }
            }
        }

        FormatModel*         model_;
        const FormatOptions* options_;
        bool                 changed_ = false;
    };
}

namespace FormatPass
{
    bool uniformSiblings(FormatModel& model)
    {
        return UniformPass(model).run();
    }
}

SWC_END_NAMESPACE();
