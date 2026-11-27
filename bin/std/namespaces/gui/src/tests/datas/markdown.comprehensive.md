---
title: Markdown fixture
---

# Markdown viewer fixture

[TOC]

This paragraph has **bold**, *italic*, ***both***, `inline code`, a
[local link](html.local-target.html#local-target), and a [reference][guide].

> [!WARNING]
> Streaming must preserve the visible block and the scroll position.

## Lists

- First item
  - Nested item
- Second item with H~2~O and x^2^.

1. Ordered item
2. Another ordered item

| Feature | Expected result |
| --- | --- |
| Frames | Independent scrolling |
| Links | Local navigation |

```swag
func answer()->u32 => 42
```

Inline mathematics $\frac{x}{2}$ and a display expression:

\[
\int_0^1 x^2\,dx
\]

[^note]: A fixture footnote.

The note is referenced here[^note].

[guide]: https://example.com/guide
