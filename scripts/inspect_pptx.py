#!/usr/bin/env python3
"""Inventory PPTX source objects locally; do not classify clinical content."""

import argparse
import hashlib
import json
import posixpath
from pathlib import Path
from xml.etree import ElementTree as ET
from zipfile import BadZipFile, ZipFile


NS = {
    "a": "http://schemas.openxmlformats.org/drawingml/2006/main",
    "p": "http://schemas.openxmlformats.org/presentationml/2006/main",
    "r": "http://schemas.openxmlformats.org/officeDocument/2006/relationships",
}
RID = "{" + NS["r"] + "}"


def resolve_part(part, target):
    if target.startswith("/"):
        return posixpath.normpath(target.lstrip("/"))
    return posixpath.normpath(posixpath.join(posixpath.dirname(part), target))


def relationships(archive, part):
    directory, filename = posixpath.split(part)
    rel_path = posixpath.join(directory, "_rels", filename + ".rels")
    if rel_path not in archive.namelist():
        return {}
    result = {}
    for element in ET.fromstring(archive.read(rel_path)):
        item = dict(element.attrib)
        if item.get("TargetMode") != "External":
            item["part"] = resolve_part(part, item["Target"])
        result[item["Id"]] = item
    return result


def paragraph_text(paragraph):
    pieces = []
    for element in paragraph.iter():
        if element.tag == "{" + NS["a"] + "}t":
            pieces.append(element.text or "")
        elif element.tag == "{" + NS["a"] + "}br":
            pieces.append("\n")
    return "".join(pieces)


def paragraphs(element):
    return [
        text for paragraph in element.findall(".//a:p", NS)
        if (text := paragraph_text(paragraph)).strip()
    ]


def inspect_slide(archive, part, page):
    tree = ET.fromstring(archive.read(part))
    rels = relationships(archive, part)
    record = {
        "page": page,
        "part": part,
        "hidden": tree.get("show", "1") in ("0", "false"),
        "paragraphs": paragraphs(tree),
        "tables": [],
        "pictures": [],
        "notes": [],
        "object_counts": {
            tag: len(tree.findall(".//p:" + tag, NS))
            for tag in ("sp", "pic", "graphicFrame", "grpSp", "cxnSp", "contentPart")
        },
        "image_relationship_count": sum(
            rel.get("Type", "").endswith("/image") for rel in rels.values()
        ),
    }
    for table in tree.findall(".//a:tbl", NS):
        record["tables"].append([
            ["\n".join(paragraphs(cell)) for cell in row.findall("a:tc", NS)]
            for row in table.findall("a:tr", NS)
        ])
    for picture in tree.findall(".//p:pic", NS):
        properties = picture.find("p:nvPicPr/p:cNvPr", NS)
        item = {
            "object_id": properties.get("id") if properties is not None else None,
            "name": properties.get("name") if properties is not None else None,
        }
        blip = picture.find(".//a:blip", NS)
        if blip is not None:
            for attribute in ("embed", "link"):
                rel_id = blip.get(RID + attribute)
                if not rel_id:
                    continue
                rel = rels.get(rel_id, {})
                media = rel.get("part")
                item["relationship"] = rel_id
                item["target"] = media or rel.get("Target")
                item["external"] = rel.get("TargetMode") == "External"
                if media and media in archive.namelist():
                    data = archive.read(media)
                    item["bytes"] = len(data)
                    item["sha256"] = hashlib.sha256(data).hexdigest()
                elif not item["external"]:
                    item["missing_part"] = True
        transform = picture.find("p:spPr/a:xfrm", NS)
        if transform is not None:
            item["transform"] = {
                "attributes": dict(transform.attrib),
                "offset": dict(transform.find("a:off", NS).attrib)
                if transform.find("a:off", NS) is not None else None,
                "extent": dict(transform.find("a:ext", NS).attrib)
                if transform.find("a:ext", NS) is not None else None,
            }
        crop = picture.find("p:blipFill/a:srcRect", NS)
        if crop is not None:
            item["crop"] = dict(crop.attrib)
        record["pictures"].append(item)
    for rel in rels.values():
        note_part = rel.get("part")
        if rel.get("Type", "").endswith("/notesSlide") and note_part:
            if note_part in archive.namelist():
                record["notes"].extend(paragraphs(ET.fromstring(archive.read(note_part))))
    record["has_source_content"] = bool(
        record["paragraphs"] or record["tables"] or record["pictures"] or record["notes"]
        or any(record["object_counts"].values()) or record["image_relationship_count"]
    )
    return record


def inspect_pptx(path):
    with ZipFile(path) as archive:
        part = "ppt/presentation.xml"
        tree = ET.fromstring(archive.read(part))
        rels = relationships(archive, part)
        slides = []
        for page, slide in enumerate(tree.findall("p:sldIdLst/p:sldId", NS), 1):
            slide_part = rels[slide.attrib[RID + "id"]]["part"]
            slides.append(inspect_slide(archive, slide_part, page))
        size = tree.find("p:sldSz", NS)
        return {
            "source": str(path.resolve()),
            "source_sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "slide_size": dict(size.attrib) if size is not None else None,
            "slide_count": len(slides),
            "scope": (
                "Source object inventory, not rendered visibility or clinical interpretation. "
                "Inspect text, image contents, charts/OLE/other objects and rendered pages separately. "
                "A negative has_source_content value does not establish a blank page: "
                "master/layout/background content is not inventoried."
            ),
            "slides": slides,
        }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="A local PPTX or locally converted PPTX")
    parser.add_argument("--output", type=Path, help="Optional JSON file in a working directory")
    args = parser.parse_args()
    try:
        inventory = inspect_pptx(args.source)
    except (OSError, BadZipFile, KeyError, ET.ParseError) as error:
        parser.exit(1, f"Cannot inventory {args.source}: {error}\n")
    content = json.dumps(inventory, ensure_ascii=False, indent=2) + "\n"
    if args.output:
        target = args.output.resolve()
        if target == args.source.resolve():
            parser.error("The output must not overwrite the source.")
        try:
            with target.open("x", encoding="utf-8") as handle:
                handle.write(content)
        except OSError as error:
            parser.exit(1, f"Cannot create inventory {target}: {error}\n")
        print(target)
    else:
        print(content, end="")


if __name__ == "__main__":
    main()
