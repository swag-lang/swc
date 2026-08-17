---
title: Complete Markdown viewer fixture
author: sFileScope tests
tags: [markdown, rendering, streaming]
---

# Heading level one

## Heading level two

### Heading level three

#### Heading level four

##### Heading level five

###### Heading level six

Ordinary text includes **bold**, *italic*, ***bold italic***, ~~strikethrough~~,
==highlight==, `inline code`, H~2~O, x^2^, an escaped \*asterisk\*, an em dash —,
and UTF-8 such as café, 日本語, and 🙂.

[An inline link](https://example.com "Example title"), <https://example.org>, and a
[reference link][reference] exercise all supported link forms.

[reference]: https://example.net "Reference title"

> A block quote can contain **emphasis**, `code`, and a second line.
>
> - Nested quoted item

- Unordered item
  - Nested unordered item
    1. Nested ordered item
- [x] Completed task
- [ ] Pending task

1. First ordered item
2. Second ordered item
3. Third ordered item

> [!NOTE]
> Notes provide useful context.

> [!TIP]
> Tips suggest a better path.

> [!IMPORTANT]
> Important information deserves attention.

> [!WARNING]
> Warnings describe a likely problem.

> [!CAUTION]
> Cautions describe a dangerous outcome.

| Alignment | Syntax | Result |
|:----------|:------:|-------:|
| Left      | center | right  |
| **Bold**  | `code` | 42     |

```swag
// A fenced code block with a language identifier.
func fibonacci(value: u32)->u32
{
    if value < 2 do
        return value
    return fibonacci(value - 1) + fibonacci(value - 2)
}
```

    An indented code block remains monospaced.

---

Inline mathematics: $E = mc^2$, $x_i^{n+1}$, and
$\left(\frac{a+b}{c-d}\right)^2$.

$$
\frac{1}{n}\sum_{i=0}^{n} x_i^2 = \sqrt{\alpha + \beta}
$$

\[
A = \begin{bmatrix} a & b \\ c & d \end{bmatrix},\qquad
f(x) = \begin{cases}x^2 & x \ge 0 \\ -x & x < 0\end{cases}
\]

$$
\begin{aligned}
(a+b)^2 &= a^2 + 2ab + b^2 \\
\int_0^1 x^2\,dx &= \frac{1}{3}
\end{aligned}
$$

## Search target

The distant markdown verification marker is visible inside a complete paragraph.

Term one
: Definition one

Term two
: Definition two with a footnote.[^rendering]

[^rendering]: Footnotes remain readable at the end of the document.

[TOC]

