// ============================================================================
// Lexer Operators Ok
// ============================================================================

// swc-option lex-only

// Operator & punctuation lexing coverage

// --- Single-character operators & delimiters ---
( ) [ ] { } ; , @ ? ~ = < > + - * / & | ^ % . : '\\' '\''

// --- Paired/multi-character operators ---
== != >= <= && || :: ->
+= -= *= /= &= |= ^= %=
<< >> <<= >>=
.. ...

// --- Mixed sequences to test longest-match behavior ---
= == ===
< <= << <<<
> >= >> >>>
: ::
. .. ... ....
- -> -- -=>   // note: '-=>' should be tokenized as '-' then '=>', if supported

// --- Around identifiers and numbers ---
a+b
x<<y
value>=42
flag&&enabled||disabled
ptr->field
ns::Type
v+=1
1..10
...spread
