#!/usr/bin/env python3
"""Read a saved web page and print the fields the way the extension sees them.

Offline only. It never opens a browser and never fills anything: it exists so a
real page from the web can be turned into a local test case.

    python3 tools/webtest/extract.py page.html            # human readable
    python3 tools/webtest/extract.py page.html --json      # a FormPayload

It copies content.js where it matters: a label comes from `label[for]`, then a
wrapping <label>, then aria-label, then the nearest preceding text that holds no
field of its own; the section is the nearest heading above.
"""
import json
import re
import sys
from html.parser import HTMLParser

FIELD = {"input", "select", "textarea"}
SKIP_TYPES = {"password", "hidden", "submit", "button", "reset", "image", "file",
              "checkbox", "range", "color"}
HEADINGS = {"h1", "h2", "h3", "h4", "h5", "h6", "legend"}


class Node:
    __slots__ = ("tag", "attrs", "kids", "parent", "text")

    def __init__(self, tag, attrs=None, parent=None):
        self.tag, self.attrs, self.parent = tag, attrs or {}, parent
        self.kids, self.text = [], ""


class Tree(HTMLParser):
    VOID = {"input", "br", "hr", "img", "meta", "link", "source", "area", "base"}

    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.root = Node("#root")
        self.cur = self.root

    def handle_starttag(self, tag, attrs):
        n = Node(tag, dict(attrs), self.cur)
        self.cur.kids.append(n)
        if tag not in self.VOID:
            self.cur = n

    def handle_startendtag(self, tag, attrs):
        self.cur.kids.append(Node(tag, dict(attrs), self.cur))

    def handle_endtag(self, tag):
        n = self.cur
        while n is not self.root and n.tag != tag:
            n = n.parent
        if n is not self.root:
            self.cur = n.parent

    def handle_data(self, data):
        self.cur.text += data


def walk(n):
    yield n
    for k in n.kids:
        yield from walk(k)


def text_of(n, drop_fields=True):
    out = []
    for x in walk(n):
        if drop_fields and x is not n and x.tag in FIELD:
            continue
        if x.text:
            out.append(x.text)
    return re.sub(r"\s+", " ", " ".join(out)).strip()[:80]


def has_field(n):
    return any(x.tag in FIELD for x in walk(n) if x is not n)


def label_for(n, by_for):
    fid = n.attrs.get("id")
    if fid and fid in by_for:
        t = text_of(by_for[fid])
        if t:
            return t
    p = n.parent
    while p is not None and p.tag != "#root":
        if p.tag == "label":
            t = text_of(p)
            if t:
                return t
        p = p.parent
    if n.attrs.get("aria-label"):
        return n.attrs["aria-label"].strip()[:80]
    # nearest preceding sibling that holds no field of its own
    p = n.parent
    for _ in range(3):
        if p is None or p.tag == "#root":
            break
        sibs = p.kids
        if n in sibs:
            for prev in reversed(sibs[: sibs.index(n)]):
                if has_field(prev) or prev.tag in FIELD:
                    break
                t = text_of(prev)
                if t and len(t) < 60:
                    return t
        n, p = p, p.parent
    return ""


def section_for(n):
    node = n
    for _ in range(6):
        p = node.parent
        if p is None:
            break
        sibs = p.kids
        if node in sibs:
            for prev in reversed(sibs[: sibs.index(node)]):
                if prev.tag in HEADINGS:
                    t = text_of(prev)
                    if t:
                        return t
                for x in walk(prev):
                    if x.tag in HEADINGS:
                        t = text_of(x)
                        if t:
                            return t
        node = p
    return ""


def group_for(n, seen):
    box, node = None, n.parent
    while node is not None and node.tag != "#root":
        if node.tag == "fieldset":
            box = node
            break
        c = sum(1 for x in walk(node) if x.tag in FIELD)
        if 4 <= c <= 30:
            box = node
            break
        node = node.parent
    if box is None:
        return ""
    if id(box) not in seen:
        seen[id(box)] = "grp%d" % (len(seen) + 1)
    return seen[id(box)]


def fields(html):
    t = Tree()
    t.feed(html)
    by_for = {}
    for n in walk(t.root):
        if n.tag == "label" and n.attrs.get("for"):
            by_for.setdefault(n.attrs["for"], n)
    seen, out = {}, []
    for n in walk(t.root):
        if n.tag not in FIELD:
            continue
        typ = (n.attrs.get("type") or ("select-one" if n.tag == "select" else "text")).lower()
        if typ in SKIP_TYPES:
            continue
        out.append({
            "label": label_for(n, by_for),
            "name": n.attrs.get("name", ""),
            "id": n.attrs.get("id", ""),
            "placeholder": n.attrs.get("placeholder", ""),
            "autocomplete": n.attrs.get("autocomplete", ""),
            "aria_label": n.attrs.get("aria-label", ""),
            "input_type": typ,
            "section": section_for(n),
            "group": group_for(n, seen),
        })
    return out


if __name__ == "__main__":
    src = open(sys.argv[1], encoding="utf-8", errors="ignore").read()
    fs = fields(src)
    if "--json" in sys.argv:
        print(json.dumps({"fields": fs}, ensure_ascii=False, indent=1))
    else:
        print("%d fields" % len(fs))
        for i, f in enumerate(fs):
            print("  %2d  %-34s %-22s %-12s %s" % (
                i, (f["label"] or "-")[:34], (f["name"] or f["id"] or "-")[:22],
                f["input_type"], f["section"][:24]))
