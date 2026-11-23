#!/usr/bin/env python3
"""Generate deterministic cached OOXML pie-chart fixtures."""

from __future__ import annotations

import hashlib
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

ROOT = Path(__file__).resolve().parent.parent
STAMP = (2020, 1, 2, 3, 4, 6)
PERMISSIONS = 0o100644 << 16
PPT_REL_TYPE = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide"
CATEGORIES = ["Fieldwork", "Samples", "Travel", "Equipment"]


def xml(value: str) -> bytes:
    return value.encode("utf-8")


def series(title: str, values: list[int]) -> str:
    title_cache = f'<c:tx><c:strRef><c:strCache><c:ptCount val="1"/><c:pt idx="0"><c:v>{title}</c:v></c:pt></c:strCache></c:strRef></c:tx>'
    category_cache = f'<c:cat><c:strRef><c:strCache><c:ptCount val="{len(CATEGORIES)}"/>'
    category_cache += "".join(f'<c:pt idx="{index}"><c:v>{category}</c:v></c:pt>' for index, category in enumerate(CATEGORIES))
    category_cache += "</c:strCache></c:strRef></c:cat>"
    values_cache = f'<c:val><c:numRef><c:numCache><c:ptCount val="{len(values)}"/>'
    values_cache += "".join(f'<c:pt idx="{index}"><c:v>{value}</c:v></c:pt>' for index, value in enumerate(values))
    values_cache += "</c:numCache></c:numRef></c:val>"
    return f"<c:ser>{title_cache}{category_cache}{values_cache}</c:ser>"


def slide() -> str:
    return (
        '<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><p:cSld><p:spTree><p:nvGrpSpPr/><p:grpSpPr/><p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="457200" y="274320"/><a:ext cx="10972800" cy="914400"/></a:xfrm></p:spPr><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>Budget shares</a:t></a:r></a:p></p:txBody></p:sp><p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="3" name="Budget share pie chart"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x="457200" y="1371600"/><a:ext cx="10972800" cy="5029200"/></p:xfrm><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart r:id="rIdChart1"/></a:graphicData></a:graphic></p:graphicFrame></p:spTree></p:cSld></p:sld>'
    )


def package(path: Path, chart_xml: str) -> None:
    members = [
        (
            "[Content_Types].xml",
            xml('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slides/slide1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/><Override PartName="/ppt/charts/chart1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawingml.chart+xml"/></Types>'),
        ),
        (
            "_rels/.rels",
            xml('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/></Relationships>'),
        ),
        (
            "ppt/presentation.xml",
            xml('<p:presentation xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst><p:sldSz cx="12192000" cy="6858000"/></p:presentation>'),
        ),
        (
            "ppt/_rels/presentation.xml.rels",
            xml(f'<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="{PPT_REL_TYPE}" Target="slides/slide1.xml"/></Relationships>'),
        ),
        ("ppt/slides/slide1.xml", xml(slide())),
        (
            "ppt/slides/_rels/slide1.xml.rels",
            xml('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdChart1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" Target="../charts/chart1.xml"/></Relationships>'),
        ),
        ("ppt/charts/chart1.xml", xml(chart_xml)),
    ]
    with ZipFile(path, "w") as archive:
        for name, payload in members:
            item = ZipInfo(name, STAMP)
            item.compress_type = ZIP_DEFLATED
            item.create_system = 3
            item.external_attr = PERMISSIONS
            archive.writestr(item, payload, compress_type=ZIP_DEFLATED, compresslevel=9)


def chart(*series_xml: str) -> str:
    return '<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart"><c:chart><c:plotArea><c:pieChart>' + "".join(series_xml) + "</c:pieChart></c:plotArea></c:chart></c:chartSpace>"


def main() -> None:
    fixtures = {
        "viewer.pie-chart.pptx": chart(series("Share", [40, 30, 20, 10])),
        "viewer.pie-multiple-chart.pptx": chart(series("Planned", [40, 30, 20, 10]), series("Actual", [35, 30, 25, 10])),
        "viewer.pie-negative-chart.pptx": chart(series("Share", [40, -30, 20, 10])),
        "viewer.pie-combo-chart.pptx": chart(series("Share", [40, 30, 20, 10])).replace(
            "</c:plotArea>", '<c:barChart><c:barDir val="col"/>' + series("Other", [40, 30, 20, 10]) + "</c:barChart></c:plotArea>"
        ),
    }
    for name, source in fixtures.items():
        path = ROOT / name
        package(path, source)
        print(f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {name}")


if __name__ == "__main__":
    main()
