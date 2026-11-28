---
title: Markdown rendering parity
---

# Typographic Markdown

A quiet reading column with ***clear hierarchy***, `inline code`, ==highlighting==,
H~2~O, x^2^, a [reference link][guide], and inline math $x^2 + y^2 = z^2$.

> [!NOTE]
> A themed alert keeps its own rhythm and remains easy to scan.

## Lists and tasks

- A regular item
- [x] A completed task
- [ ] An open task
  1. A nested ordered item

## Table

| Feature | Syntax | Status |
|:---|:---:|---:|
| Emphasis | `***text***` | Complete |
| Mathematics | `$x^2$` | Pixel |

## Display mathematics

\[
\frac{1}{n} \sum_{i=0}^{n} x_i^2
\]

***

The rule above must not be confused with bold-italic delimiters.[^quality]

[guide]: https://support.typora.io/Markdown-Reference/
[^quality]: The renderer comparison uses the same document, viewport, and a dark reading theme.
