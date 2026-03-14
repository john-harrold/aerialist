#!/usr/bin/env python3
"""
table_extract.py - PDF table extraction helper for Aerialist.

Usage:
    python3 table_extract.py <input.pdf> [--pages 0,1,2] [--clip x0,y0,x1,y1] [--clip-page N] [--strategy lines|text]

Output protocol (stdout, one JSON object per line):
    {"status": "progress", "page": 0, "total_pages": 5, "tables_found": 0}
    {"status": "table", "index": 0, "page": 0, "bbox": [x0,y0,x1,y1], "rows": 10, "cols": 4, "cells": [[...], ...]}
    {"status": "complete", "total_tables": 2}
    {"status": "error", "message": "..."}

All diagnostic output goes to stderr. Only the JSON protocol goes to stdout.
"""

import sys
import os
import json
import argparse
import logging


def emit(obj):
    """Write a JSON object to stdout for Swift to parse."""
    print(json.dumps(obj), flush=True)


def detect_table_regions(page):
    """Detect table regions by finding horizontal rules in the page drawings.

    Many academic papers use thin horizontal rules (filled rectangles) to
    delimit tables.  PyMuPDF's find_tables(strategy="lines") misses these
    because they are filled rects, not vector lines.

    Handles both full-width and column-width rules (e.g., tables within a
    single column of a multi-column layout).

    Returns a list of fitz.Rect clip regions, one per detected table.
    """
    import fitz

    pw = page.rect.width
    ph = page.rect.height
    min_rule_width = pw * 0.25  # rule must span at least 25% of page width
    MARGIN = 50  # ignore rules within this distance of page top/bottom edges

    # Collect horizontal rules with their full rect info
    raw_rules = []
    for d in page.get_drawings():
        rect = d.get("rect")
        if rect is None:
            continue
        h = rect.height
        w = rect.width
        if h < 3 and w > min_rule_width:
            y = rect.y0
            if y < MARGIN or y > ph - MARGIN:
                continue
            raw_rules.append((rect.x0, rect.x1, y))

    if len(raw_rules) < 3:
        return []

    # Group rules by their horizontal span (x-range).
    # Rules with similar x0 and x1 belong to the same column group.
    X_TOLERANCE = 15
    groups = []  # list of (x0, x1, [y_positions])
    for x0, x1, y in raw_rules:
        placed = False
        for g in groups:
            if abs(g[0] - x0) < X_TOLERANCE and abs(g[1] - x1) < X_TOLERANCE:
                g[2].append(y)
                placed = True
                break
        if not placed:
            groups.append([x0, x1, [y]])

    HEADER_GAP = 30  # max gap between rules in a header cluster
    regions = []

    for x0, x1, y_list in groups:
        # Sort and deduplicate y-positions
        y_list.sort()
        deduped = [y_list[0]]
        for y in y_list[1:]:
            if y - deduped[-1] > 2:
                deduped.append(y)

        if len(deduped) < 3:
            continue

        # Find table regions within this column group
        i = 0
        while i < len(deduped):
            # Try to form a header cluster (>=2 consecutive close rules)
            j = i
            while j + 1 < len(deduped) and deduped[j + 1] - deduped[j] <= HEADER_GAP:
                j += 1

            if j - i < 1:
                # Single rule, not a table header
                i += 1
                continue

            table_start = deduped[i]

            # Next rule after header cluster is the table bottom
            if j + 1 < len(deduped):
                table_end = deduped[j + 1]
                if table_end - table_start > 40:
                    regions.append(fitz.Rect(x0 - 2, table_start - 2,
                                             x1 + 2, table_end + 2))
                i = j + 2
            else:
                break

    return regions


def filter_false_positives(tables_result, page_height):
    """Remove likely false-positive tables from text strategy results.

    The text strategy often misdetects two-column body text, equations,
    and references as tables. These filters aim to reject those while
    keeping genuine tabular data.
    """
    filtered = []
    for tab in tables_result:
        col_count = tab.col_count
        row_count = tab.row_count
        bbox = tab.bbox  # (x0, y0, x1, y1)
        table_height = bbox[3] - bbox[1]

        # Reject tables spanning most of the page (body text / equations)
        if table_height > page_height * 0.5:
            continue

        # Reject very narrow tables (<=2 cols) — likely body text fragments
        if col_count <= 2:
            continue

        # Reject tables with mostly empty cells
        cells = tab.extract()
        total_cells = row_count * col_count
        if total_cells > 0:
            empty_count = sum(
                1 for row in cells for cell in row
                if cell is None or (isinstance(cell, str) and cell.strip() == "")
            )
            if empty_count / total_cells > 0.7:
                continue

        # Reject tables where most non-empty cells have long text (body text)
        non_empty_cells = [
            cell for row in cells for cell in row
            if cell is not None and isinstance(cell, str) and cell.strip()
        ]
        if non_empty_cells:
            long_count = sum(1 for c in non_empty_cells if len(c.strip()) > 40)
            if long_count / len(non_empty_cells) > 0.5:
                continue

        filtered.append(tab)
    return filtered


def clean_extracted_rows(cells):
    """Remove completely empty rows from extracted table data."""
    cleaned = []
    for row in cells:
        row_clean = [cell if cell is not None else "" for cell in row]
        # Keep the row if it has any non-empty cell
        if any(c.strip() for c in row_clean):
            cleaned.append(row_clean)
    return cleaned


def extract_grid_positions(tab):
    """Extract column and row boundary positions from a Table's cell rects.

    Returns (col_positions, row_positions) as sorted lists of unique coordinates.
    """
    x_set = set()
    y_set = set()
    if hasattr(tab, 'cells') and tab.cells:
        for cell_rect in tab.cells:
            if cell_rect is None:
                continue
            x0, y0, x1, y1 = cell_rect
            x_set.add(round(x0, 2))
            x_set.add(round(x1, 2))
            y_set.add(round(y0, 2))
            y_set.add(round(y1, 2))
    return sorted(x_set), sorted(y_set)


def extract_with_grid(page, clip, col_positions, row_positions):
    """Extract table data using user-defined grid lines.

    Instead of using find_tables(), this gets all text spans from the region
    and assigns each to a grid cell based on its center position.

    Args:
        page: PyMuPDF page object.
        clip: (x0, y0, x1, y1) clip region.
        col_positions: sorted list of x-positions defining column boundaries.
        row_positions: sorted list of y-positions defining row boundaries.

    Returns a dict with table data, or None if no data found.
    """
    import fitz
    import bisect

    clip_rect = fitz.Rect(clip)

    # Get all text as dict with span-level bounding boxes
    text_data = page.get_text("dict", clip=clip_rect)

    num_cols = len(col_positions) - 1
    num_rows = len(row_positions) - 1
    if num_cols < 1 or num_rows < 1:
        return None

    # Build 2D grid of text lists
    grid = [[[] for _ in range(num_cols)] for _ in range(num_rows)]

    for block in text_data.get("blocks", []):
        if block.get("type") != 0:  # text blocks only
            continue
        for line in block.get("lines", []):
            for span in line.get("spans", []):
                text = span.get("text", "").strip()
                if not text:
                    continue
                bbox = span.get("bbox", [0, 0, 0, 0])
                cx = (bbox[0] + bbox[2]) / 2
                cy = (bbox[1] + bbox[3]) / 2

                # Find which column and row this span belongs to
                col_idx = bisect.bisect_right(col_positions, cx) - 1
                row_idx = bisect.bisect_right(row_positions, cy) - 1

                if 0 <= col_idx < num_cols and 0 <= row_idx < num_rows:
                    grid[row_idx][col_idx].append((cy, cx, text))

    # Sort spans within each cell and join text
    cells = []
    for row in grid:
        cell_row = []
        for cell_spans in row:
            cell_spans.sort()  # sort by y then x
            cell_row.append(" ".join(s[2] for s in cell_spans))
        cells.append(cell_row)

    cleaned = clean_extracted_rows(cells)
    if not cleaned:
        return None

    return {
        "bbox": list(clip),
        "rows": len(cleaned),
        "cols": num_cols,
        "cells": cleaned,
        "col_positions": col_positions,
        "row_positions": row_positions,
    }


def extract_tables_from_page(page, clip=None, strategy=None, force_text=False):
    """Extract tables from a single page using find_tables().

    If no strategy is specified (auto mode):
    1. Try rules-based detection (horizontal rules define table regions)
    2. Fall back to lines strategy
    3. Fall back to text strategy with false-positive filtering

    Returns a list of dicts with table data.
    """
    import fitz

    kwargs = {}
    if clip is not None:
        kwargs["clip"] = fitz.Rect(clip)

    tables_result = []
    page_height = page.rect.height

    def _extract_from_tables(tabs_list):
        """Extract data from Table objects immediately (before they're invalidated)."""
        out = []
        for tab in tabs_list:
            cells = tab.extract()
            cleaned = clean_extracted_rows(cells)
            # Need at least 2 rows (header + data) to be a real table
            if len(cleaned) < 2:
                continue
            col_pos, row_pos = extract_grid_positions(tab)
            out.append({
                "bbox": list(tab.bbox),
                "rows": len(cleaned),
                "cols": tab.col_count,
                "cells": cleaned,
                "col_positions": col_pos,
                "row_positions": row_pos,
            })
        return out

    # Force-text mode: text strategy without false-positive filtering
    if force_text:
        tabs = page.find_tables(strategy="text", **kwargs)
        return _extract_from_tables(list(tabs.tables))

    if strategy:
        # Use the specified strategy
        tabs = page.find_tables(strategy=strategy, **kwargs)
        tables_list = list(tabs.tables)

        # Apply false-positive filtering for text strategy
        if strategy == "text":
            tables_list = filter_false_positives(tables_list, page_height)

        return _extract_from_tables(tables_list)

    # AUTO MODE: try rules-based detection first
    if clip is None:
        regions = detect_table_regions(page)
    else:
        regions = []

    if regions:
        # Extract tables within each rule-defined region.
        # IMPORTANT: extract data immediately from each find_tables call
        # because PyMuPDF Table objects are invalidated by subsequent calls.
        results = []
        for region in regions:
            tabs = page.find_tables(strategy="text", clip=region)
            results.extend(_extract_from_tables(tabs.tables))
        return results

    # Fall back: try lines first
    tabs = page.find_tables(strategy="lines", **kwargs)
    if tabs.tables:
        return _extract_from_tables(tabs.tables)

    # Last resort: text strategy with aggressive filtering
    tabs = page.find_tables(strategy="text", **kwargs)
    filtered = filter_false_positives(list(tabs.tables), page_height)
    return _extract_from_tables(filtered)


def main():
    parser = argparse.ArgumentParser(description="Extract tables from PDF")
    parser.add_argument("input", help="Input PDF file path")
    parser.add_argument("--pages", type=str, default=None,
                        help="Comma-separated 0-indexed page numbers")
    parser.add_argument("--clip", type=str, default=None,
                        help="Clip region as x0,y0,x1,y1")
    parser.add_argument("--clip-page", type=int, default=None,
                        help="Page index for the clip region (0-indexed)")
    parser.add_argument("--strategy", type=str, default=None,
                        choices=["lines", "text"],
                        help="Table detection strategy (default: try lines then text)")
    parser.add_argument("--force-text", action="store_true",
                        help="Use text strategy without false-positive filtering")
    parser.add_argument("--col-positions", type=str, default=None,
                        help="Comma-separated column boundary x-positions for grid extraction")
    parser.add_argument("--row-positions", type=str, default=None,
                        help="Comma-separated row boundary y-positions for grid extraction")
    args = parser.parse_args()

    # Redirect all library logging to stderr
    logging.basicConfig(stream=sys.stderr, level=logging.WARNING)

    if not os.path.isfile(args.input):
        emit({"status": "error", "message": f"Input file not found: {args.input}"})
        sys.exit(1)

    try:
        import fitz
    except ImportError:
        emit({"status": "error", "message": "PyMuPDF (fitz) not installed"})
        sys.exit(1)

    try:
        doc = fitz.open(args.input)
        total_pages = doc.page_count
    except Exception as e:
        emit({"status": "error", "message": f"Failed to open PDF: {e}"})
        sys.exit(1)

    # Determine which pages to process
    if args.pages:
        page_indices = [int(p.strip()) for p in args.pages.split(",")]
    else:
        page_indices = list(range(total_pages))

    # Parse clip region
    clip = None
    if args.clip:
        parts = [float(x.strip()) for x in args.clip.split(",")]
        if len(parts) != 4:
            emit({"status": "error", "message": "Clip must be x0,y0,x1,y1"})
            sys.exit(1)
        clip = tuple(parts)

    # Parse custom grid positions
    col_positions = None
    if args.col_positions:
        col_positions = [float(x.strip()) for x in args.col_positions.split(",")]
    row_positions = None
    if args.row_positions:
        row_positions = [float(x.strip()) for x in args.row_positions.split(",")]

    table_index = 0
    num_pages = len(page_indices)

    try:
        for i, page_idx in enumerate(page_indices):
            if page_idx < 0 or page_idx >= total_pages:
                continue

            page = doc[page_idx]

            # Only apply clip to the specified clip-page (or all pages if no clip-page)
            page_clip = None
            if clip is not None:
                if args.clip_page is None or args.clip_page == page_idx:
                    page_clip = clip

            # Grid extraction mode: use user-defined grid lines
            if col_positions and row_positions and page_clip:
                tab_data = extract_with_grid(page, page_clip, col_positions, row_positions)
                tables = [tab_data] if tab_data else []
            else:
                tables = extract_tables_from_page(
                    page, clip=page_clip, strategy=args.strategy,
                    force_text=args.force_text
                )

            emit({
                "status": "progress",
                "page": page_idx,
                "total_pages": num_pages,
                "tables_found": len(tables),
            })

            for tab_data in tables:
                table_msg = {
                    "status": "table",
                    "index": table_index,
                    "page": page_idx,
                    "page_height": page.rect.height,
                    "bbox": tab_data["bbox"],
                    "rows": tab_data["rows"],
                    "cols": tab_data["cols"],
                    "cells": tab_data["cells"],
                }
                if "col_positions" in tab_data:
                    table_msg["col_positions"] = tab_data["col_positions"]
                if "row_positions" in tab_data:
                    table_msg["row_positions"] = tab_data["row_positions"]
                emit(table_msg)
                table_index += 1

        doc.close()
        emit({"status": "complete", "total_tables": table_index})

    except Exception as e:
        emit({"status": "error", "message": str(e)})
        sys.exit(1)


if __name__ == "__main__":
    main()
