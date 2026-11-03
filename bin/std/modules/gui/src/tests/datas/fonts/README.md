# HTML golden fallback fonts

These small, renamed SIL Open Font License subsets are test inputs for
`htmlview.document`. The fixture uses them explicitly with system fallback disabled,
so its Japanese text and emoji have the same outlines and advances on every host.
They do not change application font selection.

- `html-cjk.otf`: U+65E5, U+672C and U+8A9E from the Japanese face (index 0) of
  Noto Sans CJK Regular 2.004. Copyright 2014–2021 Adobe (http://www.adobe.com/).
  Source: https://github.com/notofonts/noto-cjk/tree/Sans2.004
  Input `NotoSansCJK-Regular.ttc` SHA-256:
  `b76b0433203017ca80401b2ee0dd69350349871c4b19d504c34dbdd80541690a`.
  License: `notosanscjk-OFL.txt`.
- `html-emoji.ttf`: U+1F642 from Noto Emoji 3.002, instantiated at weight 400.
  Copyright 2013 Google LLC.
  Source: https://github.com/google/fonts/tree/main/ofl/notoemoji
  Input `NotoEmoji[wght].ttf` SHA-256:
  `de6c18832938afc99caf132b39d6a30a19bac7f2e812e28db2535b4608d27551`.
  License: `notoemoji-OFL.txt`.

Generation uses fontTools: load the CJK collection with `fontNumber=0`, instantiate
Emoji with `instantiateVariableFont(font, {"wght": 400})`, and subset the listed
Unicode scalars with `Subsetter`. Preserve all name IDs/languages, legacy names and
the original timestamps. Rename name IDs 1, 3, 4, 6 and 16 to `SwagTestHtmlCjk` or
`SwagTestHtmlEmoji`, and IDs 2 and 17 to `Regular`; also rename the CFF font name,
FamilyName and FullName for the CJK subset. Original copyright and license metadata
remain embedded. The fixture uses outline fonts; bitmap-only color emoji is not an
input to this golden.
