#!/usr/bin/env python3
"""Clean up the Aspire form index CSV: deduplicate, resolve relative URLs, normalize categories."""

import csv
import re
import sys
from collections import OrderedDict

INPUT = "/Users/zgbot/Desktop/ShopPilot/docs/planning/aspire_form_index.csv"
OUTPUT = "/Users/zgbot/Desktop/ShopPilot/docs/planning/aspire_form_index_cleaned.csv"
BASE_URL = "https://docs.vectric.com/docs/V12.0/Aspire/ENU/Help/page/user-guide/"

def resolve_url(url):
    """Convert relative URLs to absolute."""
    url = url.strip()
    if url.startswith("http"):
        return url
    # Relative URL like ../../form/...
    return BASE_URL + url.lstrip("./")


def normalize_category(cat, name):
    """Clean up category names for better readability."""
    cat = cat.strip()
    
    # Chapter pages have escaped dots in the TOC — clean them up
    if re.match(r'^\d+\\\.', name):
        m = re.match(r'^(\d+)\\\.\s*(.*)', name)
        if m:
            num = int(m.group(1))
            return f"Chapter {num}"
    
    # "Single Page" entries — these are navigation forms
    if cat == "Single Page":
        return "Interface Navigation"
    
    return cat


def normalize_name(name):
    """Clean up form names."""
    name = name.strip()
    name = re.sub(r'\\\.', '.', name)
    return name


# Read the CSV — handle \r\n line endings explicitly
rows = []
with open(INPUT, "r", newline="", encoding="utf-8-sig") as f:
    # Read raw lines to debug
    raw_lines = f.readlines()

print(f"Read {len(raw_lines)} raw lines from input", file=sys.stderr)
if raw_lines:
    print(f"First line repr: {repr(raw_lines[0][:120])}", file=sys.stderr)

# Use csv reader with proper handling
with open(INPUT, "r", newline="", encoding="utf-8-sig") as f:
    content = f.read()

# Replace \r\n with \n for consistent parsing
content = content.replace('\r\n', '\n').replace('\r', '\n')

reader = csv.DictReader(content.splitlines())
fieldnames = reader.fieldnames
print(f"CSV fieldnames: {fieldnames}", file=sys.stderr)

for row in reader:
    rows.append(row)

print(f"Parsed {len(rows)} data rows", file=sys.stderr)

# Deduplicate by resolved URL — keep the entry with the better name/category
url_map = OrderedDict()  # url -> best row
dup_count = 0
for row in rows:
    raw_url = row.get("url", "").strip()
    if not raw_url:
        continue
    url = resolve_url(raw_url)
    
    clean_name = normalize_name(row.get("name", ""))
    clean_cat = normalize_category(row.get("category", ""), row.get("name", ""))
    
    if url not in url_map:
        url_map[url] = {"name": clean_name, "category": clean_cat, "url": url}
    else:
        existing = url_map[url]
        # If current is a numbered chapter and existing isn't, keep existing
        if re.match(r'^\d+\\\.', row.get("name", "")) and not re.match(r'^\d+\\\.', existing["name"]):
            dup_count += 1
            continue
        # Prefer non-TOC category over TOC
        elif clean_cat != "TOC" and existing["category"] == "TOC":
            url_map[url] = {"name": clean_name, "category": clean_cat, "url": url}
            dup_count += 1

print(f"After dedup: {len(url_map)} unique URLs (removed {dup_count} duplicates)", file=sys.stderr)

# Sort by category then name
sorted_rows = sorted(url_map.values(), key=lambda r: (r["category"], r["name"]))

# Write cleaned CSV
with open(OUTPUT, "w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["name", "category", "url"])
    writer.writeheader()
    for row in sorted_rows:
        writer.writerow(row)

print(f"Wrote {len(sorted_rows)} rows to {OUTPUT}", file=sys.stderr)

# Summary by category
from collections import Counter
cats = Counter(r["category"] for r in sorted_rows)
print("\nForms by category:", file=sys.stderr)
for cat, count in cats.most_common():
    print(f"  {cat}: {count}", file=sys.stderr)
