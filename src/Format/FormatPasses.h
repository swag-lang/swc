#pragma once

SWC_BEGIN_NAMESPACE();

class FormatModel;

// The formatting passes, in the order run() applies them. Every pass only
// acts when its options ask for a rewrite, so a fully "preserve" configuration
// renders the source byte-for-byte.
namespace FormatPass
{
    void sortUsing(FormatModel& model);   // sort-using-statements, merge-using-statements
    void statements(FormatModel& model);  // remove-condition-parentheses, remove-trailing-commas, one-*-per-line
    void attributes(FormatModel& model);  // attribute-placement, break-after-attribute, sort-attribute-arguments
    void braces(FormatModel& model);      // brace-style, compact-empty-braces, break-before-else
    void shortBlocks(FormatModel& model); // allow-short-*-on-single-line
    void blanks(FormatModel& model);      // blank-line-* structural options
    void spacing(FormatModel& model);     // all space-* options
    void indent(FormatModel& model);      // indent-* structural options
    void wrap(FormatModel& model);        // column-limit and break-* wrapping options

    // Two decisions read the final line layout, so they only become correct once
    // wrapping has fixed it. Taken any earlier they answer for a layout the
    // reader never sees, and the next run of the formatter answers again.
    void caseBlanks(FormatModel& model);          // blank-line-between-cases
    void redundantSemicolons(FormatModel& model); // remove-redundant-semicolons

    void comments(FormatModel& model);    // comment rewriting options
    void align(FormatModel& model);       // align-* options

    void runAll(FormatModel& model);
}

SWC_END_NAMESPACE();
