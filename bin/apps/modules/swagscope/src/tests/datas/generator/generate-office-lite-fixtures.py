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
    merge_start = '<w:tr><w:tc><w:tcPr><w:vMerge w:val="restart"/></w:tcPr><w:p><w:r><w:t>First vertical merge</w:t></w:r></w:p></w:tc><w:tc><w:tcPr><w:vMerge w:val="restart"/></w:tcPr><w:p><w:r><w:t>Second vertical merge</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Outer cell</w:t></w:r></w:p></w:tc></w:tr>'
    merge_continue = '<w:tr><w:tc><w:tcPr><w:vMerge/></w:tcPr><w:p/></w:tc><w:tc><w:tcPr><w:vMerge/></w:tcPr><w:p/></w:tc><w:tc><w:p><w:r><w:t>Next row cell</w:t></w:r></w:p></w:tc></w:tr>'
    docx("viewer.table-merge.docx", f'<w:tbl>{merge_start}{merge_continue * 9}</w:tbl>', rels=True)
    docx("viewer.table-merge-span.docx", '<w:tbl><w:tr><w:tc><w:tcPr><w:gridSpan w:val="2"/><w:vMerge w:val="restart"/></w:tcPr><w:p><w:r><w:t>Vertical merge across columns</w:t></w:r></w:p></w:tc><w:tc><w:p><w:r><w:t>Outer cell</w:t></w:r></w:p></w:tc></w:tr><w:tr><w:tc><w:tcPr><w:gridSpan w:val="2"/><w:vMerge/></w:tcPr><w:p/></w:tc><w:tc><w:p><w:r><w:t>Next row cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl>', rels=True)
    docx("viewer.bad-table-merge.docx", '<w:tbl><w:tr><w:tc><w:tcPr><w:vMerge/></w:tcPr><w:p><w:r><w:t>Unmatched merge</w:t></w:r></w:p></w:tc></w:tr></w:tbl>', rels=True)
    docx("viewer.nested-table.docx", '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Outer cell</w:t></w:r></w:p><w:tbl><w:tr><w:tc><w:p><w:r><w:t>Nested cell</w:t></w:r></w:p></w:tc></w:tr></w:tbl></w:tc></w:tr></w:tbl>', rels=True)
    package(ROOT / "viewer.endnotes.docx", [
        ("[Content_Types].xml", xml(CT_DOCX), ZIP_DEFLATED),
        ("word/document.xml", xml(f'<w:document xmlns:w="{W}"><w:body><w:p><w:r><w:t>Opening </w:t><w:endnoteReference w:id="2"/><w:t> middle </w:t><w:endnoteReference w:id="1"/><w:t> ending </w:t><w:endnoteReference w:id="2"/><w:t> missing </w:t><w:endnoteReference w:id="9"/><w:t>.</w:t></w:r></w:p></w:body></w:document>'), ZIP_DEFLATED),
        ("word/_rels/document.xml.rels", xml('<Relationships><Relationship Id="rEndnotes" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/endnotes" Target="endnotes.xml"/></Relationships>'), ZIP_DEFLATED),
        ("word/endnotes.xml", xml(f'<w:endnotes xmlns:w="{W}"><w:endnote w:id="1"><w:p><w:r><w:t>First &amp; safely &lt;escaped&gt; endnote.</w:t></w:r></w:p></w:endnote><w:endnote w:id="2"><w:p><w:r><w:t>Second endnote appears first.</w:t></w:r></w:p></w:endnote></w:endnotes>'), ZIP_DEFLATED),
    ])
    package(ROOT / "viewer.external-links.docx", [
        ("[Content_Types].xml", xml(CT_DOCX), ZIP_DEFLATED),
        ("word/document.xml", xml(f'<w:document xmlns:w="{W}" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><w:body><w:p><w:hyperlink r:id="rWeb"><w:r><w:t>Web &amp; source</w:t></w:r></w:hyperlink><w:r><w:t> · </w:t></w:r><w:hyperlink r:id="rMail"><w:r><w:t>Email source</w:t></w:r></w:hyperlink><w:r><w:t> · </w:t></w:r><w:hyperlink r:id="rScript"><w:r><w:t>Unsafe source</w:t></w:r></w:hyperlink><w:r><w:t> · </w:t></w:r><w:hyperlink r:id="rMissing"><w:r><w:t>Missing source</w:t></w:r></w:hyperlink></w:p></w:body></w:document>'), ZIP_DEFLATED),
        ("word/_rels/document.xml.rels", xml('<Relationships><Relationship Id="rWeb" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="https://example.invalid/source?q=one&amp;r=two" TargetMode="External"/><Relationship Id="rMail" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="mailto:field-office@example.invalid" TargetMode="External"/><Relationship Id="rScript" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="javascript:alert(1)" TargetMode="External"/></Relationships>'), ZIP_DEFLATED),
    ])
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

    chart_categories = ["North", "West", "South"]
    def chart_series(title: str, values: list[int]) -> str:
        title_cache = f'<c:tx><c:strRef><c:strCache><c:ptCount val="1"/><c:pt idx="0"><c:v>{title}</c:v></c:pt></c:strCache></c:strRef></c:tx>'
        category_cache = '<c:cat><c:strRef><c:strCache><c:ptCount val="3"/>'
        category_cache += "".join(f'<c:pt idx="{index}"><c:v>{category}</c:v></c:pt>' for index, category in enumerate(chart_categories))
        category_cache += "</c:strCache></c:strRef></c:cat>"
        values_cache = '<c:val><c:numRef><c:numCache><c:ptCount val="3"/>'
        values_cache += "".join(f'<c:pt idx="{index}"><c:v>{value}</c:v></c:pt>' for index, value in enumerate(values))
        values_cache += "</c:numCache></c:numRef></c:val>"
        return f"<c:ser>{title_cache}{category_cache}{values_cache}</c:ser>"

    chart_xml = xml(
        '<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart><c:plotArea><c:barChart><c:barDir val="bar"/>'
        + chart_series("Units sold", [42, 27, 35])
        + chart_series("Revenue", [80, 50, 72])
        + "</c:barChart></c:plotArea></c:chart></c:chartSpace>"
    )
    chart_slide = xml(
        '<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><p:cSld><p:spTree><p:nvGrpSpPr/><p:grpSpPr/><p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="457200" y="274320"/><a:ext cx="10972800" cy="914400"/></a:xfrm></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>Regional sales</a:t></a:r></a:p></p:txBody></p:sp><p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="3" name="Sales chart"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x="457200" y="1371600"/><a:ext cx="10972800" cy="5029200"/></p:xfrm><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart r:id="rIdChart1"/></a:graphicData></a:graphic></p:graphicFrame></p:spTree></p:cSld></p:sld>'
    )
    package(ROOT / "viewer.chart.pptx", [
        ("[Content_Types].xml", xml('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/><Override PartName="/ppt/charts/chart1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/></Types>'), ZIP_DEFLATED),
        ("_rels/.rels", xml('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/></Relationships>'), ZIP_DEFLATED),
        ("ppt/presentation.xml", xml('<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst><p:sldSz cx="12192000" cy="6858000"/></p:presentation>'), ZIP_DEFLATED),
        ("ppt/_rels/presentation.xml.rels", xml(f'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="{PPT_REL_TYPE}" Target="slides/slide1.xml"/></Relationships>'), ZIP_DEFLATED),
        ("ppt/slides/slide1.xml", chart_slide, ZIP_DEFLATED),
        ("ppt/slides/_rels/slide1.xml.rels", xml('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdChart1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart1.xml"/></Relationships>'), ZIP_DEFLATED),
        ("ppt/charts/chart1.xml", chart_xml, ZIP_DEFLATED),
    ])
    column_chart_xml = chart_xml.replace(b'<c:barDir val="bar"/>', b'<c:barDir val="col"/>').replace(b'<c:v>50</c:v>', b'<c:v>-50</c:v>')
    package(ROOT / "viewer.column-chart.pptx", [
        ("[Content_Types].xml", xml('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/><Override PartName="/ppt/charts/chart1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/></Types>'), ZIP_DEFLATED),
        ("_rels/.rels", xml('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/></Relationships>'), ZIP_DEFLATED),
        ("ppt/presentation.xml", xml('<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst><p:sldSz cx="12192000" cy="6858000"/></p:presentation>'), ZIP_DEFLATED),
        ("ppt/_rels/presentation.xml.rels", xml(f'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="{PPT_REL_TYPE}" Target="slides/slide1.xml"/></Relationships>'), ZIP_DEFLATED),
        ("ppt/slides/slide1.xml", chart_slide, ZIP_DEFLATED),
        ("ppt/slides/_rels/slide1.xml.rels", xml('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdChart1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart1.xml"/></Relationships>'), ZIP_DEFLATED),
        ("ppt/charts/chart1.xml", column_chart_xml, ZIP_DEFLATED),
    ])
    combo_chart_xml = chart_xml.replace(
        b"</c:barChart>",
        b"</c:barChart><c:lineChart>" + chart_series("Trend", [10, 20, 15]).encode("utf-8") + b"</c:lineChart>",
    )
    package(ROOT / "viewer.combo-chart.pptx", [
        ("[Content_Types].xml", xml('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/><Override PartName="/ppt/charts/chart1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/></Types>'), ZIP_DEFLATED),
        ("_rels/.rels", xml('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/></Relationships>'), ZIP_DEFLATED),
        ("ppt/presentation.xml", xml('<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst><p:sldSz cx="12192000" cy="6858000"/></p:presentation>'), ZIP_DEFLATED),
        ("ppt/_rels/presentation.xml.rels", xml(f'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="{PPT_REL_TYPE}" Target="slides/slide1.xml"/></Relationships>'), ZIP_DEFLATED),
        ("ppt/slides/slide1.xml", chart_slide, ZIP_DEFLATED),
        ("ppt/slides/_rels/slide1.xml.rels", xml('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdChart1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart1.xml"/></Relationships>'), ZIP_DEFLATED),
        ("ppt/charts/chart1.xml", combo_chart_xml, ZIP_DEFLATED),
    ])

    table_rows = [
        ["Quarter", "Plan", "Actual"],
        ["Q1", "120", "116"],
        ["Q2", "135", "142"],
    ]
    table_cells = ""
    for row_index, row in enumerate(table_rows):
        table_cells += '<a:tr h="457200">'
        for value in row:
            fill = '<a:solidFill><a:srgbClr val="DDEBF7"/></a:solidFill>' if row_index == 0 else ""
            table_cells += f"<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>{value}</a:t></a:r></a:p></a:txBody><a:tcPr>{fill}</a:tcPr></a:tc>"
        table_cells += "</a:tr>"
    table_slide = xml(
        '<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"><p:cSld><p:spTree><p:nvGrpSpPr/><p:grpSpPr/><p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="457200" y="274320"/><a:ext cx="10972800" cy="914400"/></a:xfrm></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>Quarterly forecast</a:t></a:r></a:p></p:txBody></p:sp><p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="3" name="Forecast table"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x="914400" y="1371600"/><a:ext cx="10058400" cy="3657600"/></p:xfrm><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table"><a:tbl><a:tblPr firstRow="1" bandRow="1"><a:tableStyleId>{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}</a:tableStyleId></a:tblPr><a:tblGrid><a:gridCol w="5486400"/><a:gridCol w="2286000"/><a:gridCol w="2286000"/></a:tblGrid>'
        + table_cells
        + "</a:tbl></a:graphicData></a:graphic></p:graphicFrame></p:spTree></p:cSld></p:sld>"
    )
    package(ROOT / "viewer.table.pptx", [
        ("[Content_Types].xml", xml('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/></Types>'), ZIP_DEFLATED),
        ("_rels/.rels", xml('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/></Relationships>'), ZIP_DEFLATED),
        ("ppt/presentation.xml", xml('<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst><p:sldSz cx="12192000" cy="6858000"/></p:presentation>'), ZIP_DEFLATED),
        ("ppt/_rels/presentation.xml.rels", xml(f'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="{PPT_REL_TYPE}" Target="slides/slide1.xml"/></Relationships>'), ZIP_DEFLATED),
        ("ppt/slides/slide1.xml", table_slide, ZIP_DEFLATED),
    ])


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=ROOT)
    args = parser.parse_args()
    generate(args.output_dir)
    names = [
        "viewer.epub", "viewer.nested.epub", "viewer.damaged.epub",
        "viewer.docx", "viewer.formatted.docx", "viewer.runs.docx", "viewer.pagebreak.docx", "viewer.endnotes.docx", "viewer.external-links.docx", "viewer.table-merge.docx", "viewer.table-merge-span.docx", "viewer.bad-table-merge.docx", "viewer.nested-table.docx", "viewer.damaged.docx",
        "viewer.rtf", "viewer.unicode.rtf", "viewer.table.rtf", "viewer.destinations.rtf", "viewer.damaged.rtf",
        "viewer.xlsx", "viewer.inline.xlsx", "viewer.damaged.xlsx",
        "viewer.empty-cells.xlsx", "viewer.formulas.xlsx", "viewer.sparse-rows.xlsx", "viewer.wide-column.xlsx",
        "viewer.pptx", "viewer.formatted.pptx", "viewer.slides.pptx", "viewer.damaged.pptx", "viewer.chart.pptx", "viewer.column-chart.pptx", "viewer.combo-chart.pptx", "viewer.table.pptx",
    ]
    for name in names:
        path = args.output_dir / name
        print(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {name}")

if __name__ == "__main__":
    main()
