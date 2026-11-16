# Headless host fallback fonts

`Gui.Testing.HeadlessHost` compiles these two small SIL Open Font License subsets in and gives
them to its font cache as the only fallback faces, with the installed fonts switched off. A
character the interface faces lack then has the same outline and advance on every machine, or
the same missing-glyph box when neither subset carries it.

They are byte-for-byte copies of the `htmlview.document` golden inputs in
`../../tests/datas/fonts`, whose `README.md` records their sources, input hashes and generation:

- `fallback-cjk.otf` is `html-cjk.otf`: U+65E5, U+672C and U+8A9E from Noto Sans CJK
  Regular 2.004. Copyright 2014–2021 Adobe (http://www.adobe.com/). License:
  `notosanscjk-OFL.txt`.
- `fallback-emoji.ttf` is `html-emoji.ttf`: U+1F642 from Noto Emoji 3.002 at weight 400.
  Copyright 2013 Google LLC. License: `notoemoji-OFL.txt`.

They do not change application font selection: only a headless test host uses them.
