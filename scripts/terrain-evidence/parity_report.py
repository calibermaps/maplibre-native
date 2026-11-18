#!/usr/bin/env python3
"""Turn the render-test runner's HTML report into a markdown table plus PNGs.

    parity_report.py <runner html> <out dir> <ported list> [title]

Writes <out dir>/<test>/{actual,expected,diff}.png and prints the markdown table.
<ported list> names the test ids that came from GL JS (one per line).
"""
import base64
import html
import json
import os
import re
import sys

page, out_dir, ported_list = sys.argv[1:4]
ported = {line.strip() for line in open(ported_list) if line.strip()}
text = open(page, encoding="utf-8", errors="replace").read()

rows = []
for block in re.findall(r'<div class="test ([^"]*)">(.*?)</div>', text, re.S):
    classes, body = block
    m = re.search(r'</span> (\S+)</h2>', body)
    if not m:
        continue
    test_id = m.group(1)
    status = re.search(r'<span class="label"[^>]*>([^<]*)</span>', body).group(1)
    name = re.sub(r"^(render-tests/)?(terrain/)?", "", test_id)
    folder = os.path.join(out_dir, name.replace("/", "__"))
    images = re.findall(r'src="data:image/png;base64,([^"]*)"(?: data-alt-src="data:image/png;base64,([^"]*)")?', body)
    saved = []
    if images:
        os.makedirs(folder, exist_ok=True)
        actual, expected = images[0]
        pairs = [("actual", actual), ("expected", expected)]
        if len(images) > 1:
            pairs.append(("diff", images[1][0]))
        for label, data in pairs:
            if data:
                with open(os.path.join(folder, label + ".png"), "wb") as f:
                    data = "".join(data.split()); f.write(base64.b64decode(data + "=" * (-len(data) % 4)))
                saved.append(label)
    diff = re.search(r'<strong>Diff:</strong> ([0-9.eE+-]+)', body)
    error = re.search(r'<strong>Error:</strong> (.*?)</p>', body, re.S)
    rows.append({
        "id": name,
        "status": status,
        "result": "pass" if status.endswith("passed") else ("error" if status == "errored" else "fail"),
        "difference": float(diff.group(1)) if diff else 0.0,
        "origin": "GL JS port" if name.split("/")[0] in ported else "native",
        "images": saved,
        "error": html.unescape(re.sub(r"<[^>]+>", " ", error.group(1))).strip()[:160] if error else "",
    })

rows.sort(key=lambda r: (r["origin"] != "GL JS port", r["result"] == "pass", r["id"]))
with open(os.path.join(out_dir, "results.json"), "w") as f:
    json.dump(rows, f, indent=1)

rel = os.path.basename(os.path.normpath(out_dir))
print("| Test | From | Result | Difference | Images | Note |")
print("|---|---|---|---|---|---|")
for r in rows:
    folder = r["id"].replace("/", "__")
    links = " ".join(f"[{label}]({rel}/{folder}/{label}.png)" for label in r["images"])
    print(f"| {r['id']} | {r['origin']} | {r['result']} | {r['difference']:.4f} | {links} | {r['error'] or r['status']} |")
