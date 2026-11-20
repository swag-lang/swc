#!/usr/bin/env python3
"""Create small original EPUB, OOXML and RTF reader fixtures.

All prose and XML are authored below for Swag Scope. Packages are assembled with
Python's standard library only, with fixed ZIP metadata and ordering. No external
corpus, office suite, image, or system font is read.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZIP_STORED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parent.parent
STAMP = (2020, 1, 2, 3, 4, 6)
PERMISSIONS = 0o100644 << 16


def xml(value: str) -> bytes:
    return value.encode("utf-8")


def package(path: Path, members: list[tuple[str, bytes, int]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(path, "w") as archive:
        for name, payload, method in members:
            item = ZipInfo(name, STAMP)
            item.compress_type = method
            item.create_system = 3
            item.external_attr = PERMISSIONS
            archive.writestr(item, payload, compress_type=method, compresslevel=9 if method == ZIP_DEFLATED else None)


def epub(name: str, entries: list[tuple[str, str]], rootfile: str, package_xml: str, mime_first: bool = True) -> None:
    members = [
        ("mimetype", b"application/epub+zip", ZIP_STORED),
        ("META-INF/container.xml", xml(f'<?xml version="1.0"?><container><rootfiles><rootfile full-path="{rootfile}" media-type="application/oebps-package+xml"/></rootfiles></container>'), ZIP_DEFLATED),
        (rootfile, xml(package_xml), ZIP_DEFLATED),
    ]
    members.extend((path, xml(body), ZIP_DEFLATED) for path, body in entries)
    package(ROOT / name, members)


def generate(output: Path) -> None:
    global ROOT
    ROOT = output
    ROOT.mkdir(parents=True, exist_ok=True)
    # The manifest is deliberately in reverse order from the spine: the reader must
    # use spine order and resolve each reference by id.
    epub(
        "viewer.epub",
        [
            ("OEBPS/one.xhtml", "<html><body><h1>First chapter</h1><p>A readable EPUB page.</p></body></html>"),
            ("OEBPS/two.xhtml", "<html><body><h1>Second chapter</h1></body></html>"),
        ],
        "OEBPS/content.opf",
        '<?xml version="1.0"?><package><manifest><item id="second" href="two.xhtml" media-type="application/xhtml+xml"/><item id="first" href="one.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="first"/><itemref idref="second"/></spine></package>',
    )
    epub(
        "viewer.nested.epub",
        [("OPS/chapters/part.xhtml", "<html><body><h1>North Basin, Station 14B</h1><p>Mira Chen follows a nested trail from the reed bed to the lower weir. The field sheet records a checked water level of 1.42 metres and three sealed sample jars.</p></body></html>")],
        "OPS/book.opf",
        '<package><manifest><item id="part" href="chapters/part.xhtml" media-type="application/xhtml+xml"/></manifest><spine><itemref idref="part"/></spine></package>',
    )
    # The rootfile intentionally escapes the package; the EPUB reader must reject it.
    package(ROOT / "viewer.damaged.epub", [
        ("mimetype", b"application/epub+zip", ZIP_STORED),
        ("META-INF/container.xml", xml('<container><rootfiles><rootfile full-path="../outside.opf"/></rootfiles></container>'), ZIP_DEFLATED),
    ])

    CT_DOCX = '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>'
    ROOT_RELS = '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>'
    W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

    def docx(name: str, body: str, *, rels: bool = False, content_types: str = CT_DOCX) -> None:
        members = [("[Content_Types].xml", xml(content_types), ZIP_DEFLATED)]
        if rels:
            members.append(("_rels/.rels", xml(ROOT_RELS), ZIP_DEFLATED))
        members.append(("word/document.xml", xml(f'<w:document xmlns:w="{W}"><w:body>{body}</w:body></w:document>'), ZIP_DEFLATED))
        package(ROOT / name, members)


    docx("viewer.docx", '<w:p><w:r><w:t>Hello &amp; welcome</w:t></w:r></w:p><w:tbl><w:tr><w:tc><w:p><w:r><w:t>One</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Two</w:t></w:r></w:p></w:tc></w:tr></w:tbl><w:p><w:r><w:drawing/></w:r></w:p>', rels=True)
    docx("viewer.formatted.docx", '<w:p><w:pPr><w:pStyle w:val="Heading1"/><w:jc w:val="center"/></w:pPr><w:r><w:rPr><w:b/></w:rPr><w:t>Styled title</w:t></w:r></w:p><w:p><w:r><w:t>Plain &amp; </w:t></w:r><w:r><w:rPr><w:i/></w:rPr><w:t>italic</w:t></w:r><w:r><w:t> and </w:t></w:r><w:r><w:rPr><w:u w:val="single"/><w:strike/></w:rPr><w:t>marked</w:t></w:r><w:r><w:rPr><w:b w:val="0"/></w:rPr><w:t> text.</w:t></w:r></w:p><w:p><w:pPr><w:outlineLvl w:val="1"/><w:jc w:val="right"/></w:pPr><w:r><w:t>Second heading</w:t></w:r></w:p>', rels=True, content_types='<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>')
    docx("viewer.runs.docx", '<w:p><w:r><w:t>First </w:t></w:r><w:r><w:t>run &amp; second</w:t></w:r><w:r><w:tab/><w:t>tab</w:t><w:br/><w:t>line</w:t></w:r></w:p><w:p><w:r><w:t>&lt;escaped&gt;</w:t></w:r></w:p>', content_types='<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>')
    docx("viewer.pagebreak.docx", '<w:p><w:r><w:t>First </w:t></w:r><w:r><w:t>run &amp; second</w:t></w:r><w:r><w:tab/><w:t>tab</w:t><w:br/><w:t>line</w:t><w:br w:type="page"/><w:t>Page two</w:t></w:r></w:p><w:p><w:r><w:t>&lt;escaped&gt;</w:t></w:r></w:p>', content_types='<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>')
    package(ROOT / "viewer.damaged.docx", [("[Content_Types].xml", xml("<Types/>"), ZIP_DEFLATED)])

    # RTF source strings remain plain, reviewable source; escaped bytes and broken
    # grouping are intentional format cases.
    RTF = {
        "viewer.rtf": r'''{\rtf1\ansi\ansicpg1252\deff0
    {\fonttbl{\f0 Arial;}}
    {\colortbl;\red32\green90\blue144;}
    \pard\qc\b Rich text reading\b0\par
    \pard This is \i formatted\i0  and \ul searchable\ulnone  text.\par
    \pard First\tab second\line next line.\par
    }
    ''',
        "viewer.unicode.rtf": r'''{\rtf1\ansi\ansicpg1252\uc1
    \pard Caf\'e9, \u8364\'80 and \u-10179?\u-8704? survive.\par
    }
    ''',
        "viewer.table.rtf": r'''{\rtf1\ansi\ansicpg1252
    \trowd\intbl One\cell Two\cell\row
    \pard After the table.\par
    }
    ''',
        "viewer.destinations.rtf": r'''{\rtf1\ansi\ansicpg1252
    {\*\unknown Hidden destination}
    {\pict\bin4 {}xx}
    \pard Visible body.\par
    }
    ''',
        "viewer.damaged.rtf": r'''{\rtf1\ansi\ansicpg1252\pard Missing closing group.\par
    ''',
    }
    for name, source in RTF.items():
        # The source block is indented for Python; strip that indentation while
        # retaining the original RTF line breaks and whitespace inside groups.
        source = source.replace("\n    ", "\n")
        (ROOT / name).write_bytes(source.encode("ascii"))

    # Shared-string workbook with two related sheets. Worksheet member order and
    # relationship ids intentionally differ from visible sheet order.
    XLSX_CT = '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>'
    XLSX_RELS = '<Relationships><Relationship Id="r1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="r2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/></Relationships>'
    package(ROOT / "viewer.xlsx", [
        ("[Content_Types].xml", xml(XLSX_CT), ZIP_DEFLATED),
        ("xl/workbook.xml", xml('<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Summary &amp; totals" r:id="r2"/><sheet name="Data" r:id="r1"/></sheets></workbook>'), ZIP_DEFLATED),
        ("xl/_rels/workbook.xml.rels", xml(XLSX_RELS), ZIP_DEFLATED),
        ("xl/sharedStrings.xml", xml('<sst><si><t>Expense &amp; income</t></si><si><r><t>Hello</t></r><r><t> world</t></r></si></sst>'), ZIP_DEFLATED),
        ("xl/worksheets/sheet1.xml", xml('<worksheet><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Second sheet</t></is></c><c r="C1"><v>42</v></c></row></sheetData></worksheet>'), ZIP_DEFLATED),
        ("xl/worksheets/sheet2.xml", xml('<worksheet><sheetData><row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1"><f>2+2</f><v>4</v></c><c r="C1" t="b"><v>1</v></c></row><row r="2"><c r="A2" t="s"><v>1</v></c></row></sheetData></worksheet>'), ZIP_DEFLATED),
    ])
    package(ROOT / "viewer.inline.xlsx", [
        ("xl/workbook.xml", xml('<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Inline" r:id="r1"/></sheets></workbook>'), ZIP_DEFLATED),
        ("xl/_rels/workbook.xml.rels", xml('<Relationships><Relationship Id="r1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="/xl/worksheets/sheet.xml"/></Relationships>'), ZIP_DEFLATED),
        ("xl/worksheets/sheet.xml", xml('<worksheet><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Safe &amp; sound</t></is></c><c r="C1" t="n"><v>12.5</v></c></row></sheetData></worksheet>'), ZIP_DEFLATED),
    ])
    INLINE_BOOK = '<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Inline" r:id="r1"/></sheets></workbook>'
    INLINE_RELS = '<Relationships><Relationship Id="r1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="/xl/worksheets/sheet.xml"/></Relationships>'
    def one_sheet_workbook(name: str, worksheet: str) -> None:
        package(ROOT / name, [
            ("xl/workbook.xml", xml(INLINE_BOOK), ZIP_DEFLATED),
            ("xl/_rels/workbook.xml.rels", xml(INLINE_RELS), ZIP_DEFLATED),
            ("xl/worksheets/sheet.xml", xml(worksheet), ZIP_DEFLATED),
        ])

    one_sheet_workbook("viewer.empty-cells.xlsx", '<worksheet><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Safe &amp; sound</t></is></c><c r="C1" t="n"><v>12.5</v></c></row><row r="3"><c r="B3"/></row><row r="4"/></sheetData></worksheet>')
    one_sheet_workbook("viewer.formulas.xlsx", '<worksheet><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Safe &amp; sound</t></is></c><c r="C1" t="n"><f>SUM(2,3)</f></c><c r="D1" t="n"><f t="shared" si="1"/></c><c r="E1" t="n"><f>2+2</f><v>4</v></c></row></sheetData></worksheet>')
    one_sheet_workbook("viewer.sparse-rows.xlsx", '<worksheet><sheetData><row r="7"><c r="A7" t="inlineStr"><is><t>Safe &amp; sound</t></is></c><c r="C7" t="n"><v>12.5</v></c></row></sheetData></worksheet>')
    one_sheet_workbook("viewer.wide-column.xlsx", '<worksheet><sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>Safe &amp; sound</t></is></c><c r="XFD1" t="n"><v>12.5</v></c></row></sheetData></worksheet>')
    package(ROOT / "viewer.damaged.xlsx", [("xl/workbook.xml", xml("<workbook/>"), ZIP_DEFLATED)])

    PPT_CT = '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>'
    PPT_REL_TYPE = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide"
    def slide(text: str) -> bytes:
        return xml(f'<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>{text}</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>')

    def presentation(ids: str) -> bytes:
        return xml(f'<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><p:sldIdLst>{ids}</p:sldIdLst></p:presentation>')

    package(ROOT / "viewer.pptx", [
        ("[Content_Types].xml", xml(PPT_CT), ZIP_DEFLATED),
        ("ppt/presentation.xml", presentation('<p:sldId r:id="rslide1"/>'), ZIP_DEFLATED),
        ("ppt/_rels/presentation.xml.rels", xml(f'<Relationships><Relationship Id="rslide1" Type="{PPT_REL_TYPE}" Target="slides/slide1.xml"/><Relationship Id="rslide2" Type="{PPT_REL_TYPE}" Target="slides/slide2.xml"/></Relationships>'), ZIP_DEFLATED),
        ("ppt/slides/slide1.xml", slide("First &amp; final"), ZIP_DEFLATED),
    ])
    formatted_slide1 = xml('<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><p:cSld><p:spTree><p:sp><p:txBody><a:p><a:pPr algn="r"/><a:r><a:t>First &amp; final</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>')
    formatted_slide2 = xml('<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><p:cSld><p:spTree><p:sp><p:txBody><a:p><a:pPr algn="ctr"/><a:r><a:rPr b="1"/><a:t>Opens first</a:t></a:r><a:r><a:rPr i="1"/><a:t> styled</a:t></a:r></a:p></p:txBody></p:sp></p:spTree></p:cSld></p:sld>')
    slide1_with_picture = xml('<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><p:cSld><p:spTree><p:sp><p:txBody><a:p><a:r><a:t>Opens first</a:t></a:r></a:p></p:txBody></p:sp><p:pic/></p:spTree></p:cSld></p:sld>')
    # The first presentation deliberately lists relation rslide2 first.
    for name, first, second in [("viewer.formatted.pptx", formatted_slide1, formatted_slide2), ("viewer.slides.pptx", slide("First &amp; final"), slide("Opens first"))]:
        members = [
            ("[Content_Types].xml", xml(PPT_CT), ZIP_DEFLATED),
            ("ppt/presentation.xml", presentation('<p:sldId r:id="rslide2"/><p:sldId r:id="rslide1"/>'), ZIP_DEFLATED),
            ("ppt/_rels/presentation.xml.rels", xml(f'<Relationships><Relationship Id="rslide1" Type="{PPT_REL_TYPE}" Target="slides/slide1.xml"/><Relationship Id="rslide2" Type="{PPT_REL_TYPE}" Target="/ppt/slides/slide2.xml"/></Relationships>'), ZIP_DEFLATED),
            ("ppt/slides/slide1.xml", first, ZIP_DEFLATED),
            ("ppt/slides/slide2.xml", second if name.endswith("formatted.pptx") else slide1_with_picture, ZIP_DEFLATED),
        ]
        package(ROOT / name, members)
    package(ROOT / "viewer.damaged.pptx", [("ppt/presentation.xml", xml("<p:presentation/>"), ZIP_DEFLATED)])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=ROOT)
    args = parser.parse_args()
    generate(args.output_dir)
    names = [
        "viewer.epub", "viewer.nested.epub", "viewer.damaged.epub",
        "viewer.docx", "viewer.formatted.docx", "viewer.runs.docx", "viewer.pagebreak.docx", "viewer.damaged.docx",
        "viewer.rtf", "viewer.unicode.rtf", "viewer.table.rtf", "viewer.destinations.rtf", "viewer.damaged.rtf",
        "viewer.xlsx", "viewer.inline.xlsx", "viewer.damaged.xlsx",
        "viewer.empty-cells.xlsx", "viewer.formulas.xlsx", "viewer.sparse-rows.xlsx", "viewer.wide-column.xlsx",
        "viewer.pptx", "viewer.formatted.pptx", "viewer.slides.pptx", "viewer.damaged.pptx",
    ]
    for name in names:
        path = args.output_dir / name
        print(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {name}")

if __name__ == "__main__":
    main()
