#!/usr/bin/env python3
"""
Crawl Vectric Aspire V12 User Guide TOC and extract ALL form URLs with categories.

The TOC page is rendered as markdown where:
- Section headings appear as [Section Name](anchor_url) on their own line
- Form links appear as |[Form Name](form_url) on their own lines
- A section heading groups all following form links until the next heading

We parse the cached markdown file to get complete coverage.
"""

import csv
import re
import sys
from urllib.parse import unquote

CACHE_FILE = "/Users/zgbot/.hermes/cache/web/docs.vectric.com-8a34241954.md"
OUTPUT = "/Users/zgbot/Desktop/ShopPilot/docs/planning/aspire_form_index.csv"
BASE_URL = "https://docs.vectric.com/docs/V12.0/Aspire/ENU/Help/page/user-guide/"


def parse_toc_markdown(filepath):
    """Parse the markdown TOC and extract (name, category, url) tuples."""
    
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    entries = []
    current_category = "General"  # default before any section heading
    
    for line in lines:
        line = line.rstrip('\n')
        
        # Skip non-content lines (empty, image references, etc.)
        if not line.strip():
            continue
        
        # Section headings: [Section Name](anchor_url) — no leading |
        # These are links to anchors like #interface-overview or just #
        heading_match = re.match(r'^\[([^\]]+)\]\(([^)]+)\)$', line.strip())
        if heading_match and not line.startswith('|'):
            text = heading_match.group(1)
            url = heading_match.group(2)
            
            # Only treat as section headings if they point to anchors (#...) 
            # or are known TOC sections (not content pages like "Tips And Tricks")
            if '#' in url and 'form/' not in url.lower():
                current_category = text.strip()
                continue
        
        # Form links: |[Form Name](form_url) — with leading |
        form_match = re.match(r'^\|\[([^\]]+)\]\(([^)]+)\)$', line.strip())
        if form_match:
            name = unquote(form_match.group(1))
            url = form_match.group(2)
            
            # Only include URLs that contain /form/ (actual forms, not TOC links)
            if '/form/' in url.lower():
                entries.append((name, current_category, url))
    
    return entries


def clean_name(name):
    """Clean up form names for readability."""
    name = name.strip()
    # Remove trailing "Form" if present (but keep important ones like "Job Setup Form")
    if name.endswith(" Form"):
        name = name[:-5].strip()
    return name


def main():
    print(f"Parsing TOC from: {CACHE_FILE}")
    
    entries = parse_toc_markdown(CACHE_FILE)
    
    # Deduplicate by URL (keep first occurrence with best category)
    seen_urls = {}
    for name, category, url in entries:
        if url not in seen_urls:
            seen_urls[url] = (name, category, url)
    
    unique_entries = list(seen_urls.values())
    
    # Sort by category then name
    unique_entries.sort(key=lambda x: (x[1], x[0]))
    
    print(f"\nFound {len(unique_entries)} form entries")
    
    # Print summary by category
    from collections import Counter, OrderedDict
    cat_counts = Counter(e[1] for e in unique_entries)
    print("\n--- Categories ---")
    for cat, count in sorted(cat_counts.items(), key=lambda x: -x[1]):
        print(f"  {cat}: {count}")
    
    # Write CSV
    with open(OUTPUT, 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['name', 'category', 'url'])
        for name, category, url in unique_entries:
            clean_name_val = clean_name(name)
            writer.writerow([clean_name_val, category, url])
    
    print(f"\nWrote {len(unique_entries)} entries to {OUTPUT}")
    
    # Print all entries for verification
    print("\n--- All Entries ---")
    for i, (name, cat, url) in enumerate(unique_entries, 1):
        clean = clean_name(name)
        print(f"{i:3d}. [{cat}] {clean} -> {url}")


if __name__ == '__main__':
    main()
