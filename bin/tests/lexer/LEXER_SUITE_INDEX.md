# Lexer Suite Index

This index records the refactored lexer test layout, migration mapping, and per-file coverage checklist.

## Directory Tree

```text
bin/tests/lexer
  errors/
    invalid_chars.swg
  identifiers/
    identifier_tokens.swg
  literals/
    numbers.swg
    strings.swg
  operators/
    operators.swg
  trivia/
    comments.swg
```

## Old To New Mapping

| Old | New |
|---|---|
| lexer-comments.swg | trivia/comments.swg |
| lexer-identifiers.swg | identifiers/identifier_tokens.swg |
| lexer-invalid.swg | errors/invalid_chars.swg |
| lexer-numbers.swg | literals/numbers.swg |
| lexer-operators.swg | operators/operators.swg |
| lexer-strings.swg | literals/strings.swg |

## Per-File Coverage Checklist

### trivia/comments.swg

- Covers migrated tests from $old.
- Checklist:
- valid tokenization cases present: partial
- invalid diagnostics present: yes (expected errors=1, expected warnings=0)
- edge cases present: yes
- diagnostic set: none

### identifiers/identifier_tokens.swg

- Covers migrated tests from $old.
- Checklist:
- valid tokenization cases present: yes
- invalid diagnostics present: no (expected errors=0, expected warnings=0)
- edge cases present: partial
- diagnostic set: none

### errors/invalid_chars.swg

- Covers migrated tests from $old.
- Checklist:
- valid tokenization cases present: partial
- invalid diagnostics present: yes (expected errors=1, expected warnings=0)
- edge cases present: yes
- diagnostic set: lex_err_invalid_char

### literals/numbers.swg

- Covers migrated tests from $old.
- Checklist:
- valid tokenization cases present: partial
- invalid diagnostics present: yes (expected errors=69, expected warnings=0)
- edge cases present: yes
- diagnostic set: lex_err_consecutive_num_sep, lex_err_invalid_bin_digit, lex_err_invalid_hex_digit, lex_err_invalid_number_suffix, lex_err_leading_num_sep, lex_err_missing_bin_digit, lex_err_missing_exponent, lex_err_missing_hex_digit, lex_err_trailing_num_sep

### operators/operators.swg

- Covers migrated tests from $old.
- Checklist:
- valid tokenization cases present: yes
- invalid diagnostics present: no (expected errors=0, expected warnings=0)
- edge cases present: partial
- diagnostic set: none

### literals/strings.swg

- Covers migrated tests from $old.
- Checklist:
- valid tokenization cases present: partial
- invalid diagnostics present: yes (expected errors=100, expected warnings=0)
- edge cases present: yes
- diagnostic set: lex_err_empty_hex_escape, lex_err_incomplete_hex_escape, lex_err_invalid_escape, lex_err_invalid_hex_digit, lex_err_too_many_char_char

## Coverage Gaps And Planned Additions

- literals/numbers.swg: add separators and boundary forms (`0x`, `0b`, `0o`) with malformed suffix diagnostics.
- literals/strings.swg: add multiline + unterminated raw-string edge cases and escaped unicode range limits.
- identifiers/identifier_tokens.swg: add unicode identifier acceptance/rejection matrix by category.
- operators/operators.swg: add maximal munch interactions (e.g. `>>=`, `...`, mixed punctuator sequences).
- trivia/comments.swg: add nested/comment-in-string interactions and EOF-after-comment coverage.
- errors/invalid_chars.swg: add invalid UTF-8 byte-sequence diagnostics with exact positions.
