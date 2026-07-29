#!/usr/bin/env python3
"""
Crawl Vectric Aspire V12 User Guide TOC and extract ALL form URLs with categories.

The cached markdown has lines like:
  [Section Name](https://.../page/user-guide/#anchor)   <- section heading (has #, no /form/)
  [Form Name](https://.../Help/form/something/index.html)  <- form link (has /form/)

A section heading groups all following form links until the next heading.
"""

import csv
import re
from urllib.parse import unquote

CACHE_FILE = "/Users/zgbot/.hermes/cache/web/docs.vectric.com-8a34241954.md"
OUTPUT = "/Users/zgbot/Desktop/ShopPilot/docs/planning/aspire_form_index.csv"


def parse_toc_markdown(filepath):
    """Parse the markdown TOC and extract (name, category, url) tuples."""
    
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    entries = []
    current_category = "General"  # default before any section heading
    
    for line in lines:
        line = line.rstrip('\n').strip()
        
        # Skip empty lines and non-link content
        if not line or not line.startswith('['):
            continue
        
        # Match [text](url) pattern
        link_match = re.match(r'^\[([^\]]+)\]\(([^)]+)\)$', line)
        if not link_match:
            continue
        
        text = link_match.group(1).strip()
        url = link_match.group(2).strip()
        
        # Skip image links (start with !)
        if text.startswith('!'):
            continue
        
        # Determine if this is a section heading or form link
        if '/form/' in url.lower():
            # This is a form link — add it under current category
            entries.append((text, current_category, url))
        elif '#' in url and 'form/' not in url.lower():
            # This is a section heading (anchor link)
            # Skip known non-category headings
            skip_headings = [
                "Tips And Tricks",
                "User Guide",
                "What's New",
                "Keyboard Shortcuts",
                "Single Page",
                "Vectric Documentation",
            ]
            if text not in skip_headings:
                current_category = text
    
    return entries


def clean_name(name):
    """Clean up form names for readability."""
    name = name.strip()
    # Remove trailing "Form" but keep important ones like "Job Setup Form"
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
    from collections import Counter
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
