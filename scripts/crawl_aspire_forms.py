#!/usr/bin/env python3
"""Crawl Vectric Aspire V12 User Guide TOC and all chapter pages for form URLs."""

import csv
import re
import sys
import urllib.request
import ssl
from collections import Counter
from html.parser import HTMLParser

CACHE_FILE = "/Users/zgbot/.hermes/cache/web/docs.vectric.com-8a34241954.md"
OUTPUT = "/Users/zgbot/Desktop/ShopPilot/docs/planning/aspire_form_index.csv"
BASE_URL = "https://docs.vectric.com/docs/V12.0/Aspire/ENU/Help/page/user-guide/"

ssl_context = ssl.create_default_context()
ssl_context.check_hostname = False
ssl_context.verify_mode = ssl.CERT_NONE


def read_full_file(path):
    """Read entire file using read_file API via subprocess."""
    import subprocess
    result = subprocess.run(
        ["python3", "-c", f'''
with open("{path}", "r") as f:
    content = f.read()
print(content, end="")
'''],
        capture_output=True, text=True, timeout=10
    )
    return result.stdout


def extract_links_from_text(text):
    """Extract [text](url) markdown links from content."""
    # Markdown-style: [name](url)
    md_pattern = r'\[([^\]]+)\]\(([^)]+)\)'
    for match in re.finditer(md_pattern, text):
        yield match.group(1).strip(), match.group(2).strip()


def extract_links_from_html(html_text):
    """Extract <a href="url">text</a> from HTML."""
    pattern = r'<a\s+[^>]*href=["\']([^"\']*?)["\'][^>]*>(.*?)</a>'
    for match in re.finditer(pattern, html_text, re.DOTALL):
        url = match.group(1).strip()
        inner = re.sub(r'<[^>]+>', '', match.group(2)).strip()
        if inner:
            yield inner, url


def is_form_url(url):
    """Check if URL points to a form page."""
    return "/form/" in url.lower()


def is_chapter_url(url):
    """Check if URL is a chapter/index page (not a form)."""
    return "page/" in url and "/index.html" in url and "/form/" not in url


def is_user_guide_page(url):
    """Check if URL belongs to the user-guide section."""
    return "user-guide" in url.lower() or "help/page/" in url.lower()


# ============================================================
# PHASE 1: Read cached TOC page content (full file)
# ============================================================
print("Phase 1: Reading full TOC cache...", file=sys.stderr)

with open(CACHE_FILE, "r") as f:
    toc_content = f.read()

print(f"TOC cache size: {len(toc_content)} chars", file=sys.stderr)

all_forms = {}  # url -> (name, category)
seen_urls = set()

# Extract ALL links from the TOC page
for name, url in extract_links_from_text(toc_content):
    if is_form_url(url):
        all_forms[url] = (name, "TOC")
        seen_urls.add(url)
    elif is_chapter_url(url) and is_user_guide_page(url):
        pass  # We'll crawl these

# Also extract from HTML links in the cached content
for name, url in extract_links_from_html(toc_content):
    if is_form_url(url) and url not in seen_urls:
        all_forms[url] = (name, "TOC")
        seen_urls.add(url)

print(f"Forms found directly on TOC page: {len(all_forms)}", file=sys.stderr)

# ============================================================
# PHASE 2: Identify chapter pages to crawl
# ============================================================
chapters_to_crawl = []
for name, url in extract_links_from_text(toc_content):
    if is_chapter_url(url) and is_user_guide_page(url) and url not in seen_urls:
        chapters_to_crawl.append((name, url))

print(f"Chapter pages to crawl: {len(chapters_to_crawl)}", file=sys.stderr)

# ============================================================
# PHASE 3: Crawl each chapter page for additional form links
# ============================================================
def fetch_page(url):
    """Fetch a page and return its text content."""
    try:
        req = urllib.request.Request(url, headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36",
            "Accept": "text/html,application/xhtml+xml"
        })
        with urllib.request.urlopen(req, timeout=20, context=ssl_context) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except Exception as e:
        print(f"  Error fetching {url}: {e}", file=sys.stderr)
        return None

for ch_name, ch_url in chapters_to_crawl:
    print(f"  Crawling chapter: {ch_name} -> {ch_url}", file=sys.stderr)
    
    # First try markdown-style extraction from the TOC content itself (it may already have sub-links)
    for name, url in extract_links_from_text(toc_content):
        if is_form_url(url) and url not in seen_urls:
            all_forms[url] = (name, ch_name)
            seen_urls.add(url)
    
    # Now fetch the actual chapter page
    html = fetch_page(ch_url)
    if html:
        for name, url in extract_links_from_text(html):
            if is_form_url(url) and url not in seen_urls:
                all_forms[url] = (name, ch_name)
                seen_urls.add(url)
        
        # Also check HTML links on the chapter page
        for name, url in extract_links_from_html(html):
            if is_form_url(url) and url not in seen_urls:
                all_forms[url] = (name, ch_name)
                seen_urls.add(url)
    else:
        print(f"  Could not fetch {ch_url}", file=sys.stderr)

# ============================================================
# PHASE 4: Also look for sub-chapter pages within chapter content
# ============================================================
print("Phase 4: Looking for sub-pages in TOC content...", file=sys.stderr)

# The TOC page may have nested links - extract all non-form, non-index pages too
sub_pages = []
for name, url in extract_links_from_text(toc_content):
    if "page/" in url and "/index.html" not in url and is_user_guide_page(url):
        sub_pages.append((name, url))

print(f"Found {len(sub_pages)} potential sub-pages", file=sys.stderr)

for sp_name, sp_url in sub_pages[:30]:  # Limit to avoid too many requests
    if sp_url not in seen_urls:
        print(f"  Checking sub-page: {sp_name} -> {sp_url}", file=sys.stderr)
        html = fetch_page(sp_url)
        if html:
            for name, url in extract_links_from_text(html):
                if is_form_url(url) and url not in seen_urls:
                    all_forms[url] = (name, sp_name)
                    seen_urls.add(url)

# ============================================================
# PHASE 5: Write CSV output
# ============================================================
print(f"\nTotal unique form URLs found: {len(all_forms)}", file=sys.stderr)

# Sort by category then name for readable output
sorted_forms = sorted(all_forms.items(), key=lambda x: (x[1][1], x[1][0]))

with open(OUTPUT, "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["name", "category", "url"])
    for url, (name, category) in sorted_forms:
        writer.writerow([name, category, url])

print(f"Wrote {len(sorted_forms)} form entries to {OUTPUT}", file=sys.stderr)

# Summary by category
cats = Counter(name for name, cat in all_forms.values())
print("\nForms by category:", file=sys.stderr)
for cat, count in cats.most_common():
    print(f"  {cat}: {count}", file=sys.stderr)
