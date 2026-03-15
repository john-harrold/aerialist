#!/usr/bin/env python3
"""
pdf2docx_convert.py - PDF to DOCX conversion helper for Spindrift.

Usage:
    python3 pdf2docx_convert.py <input.pdf> <output.docx> [--start N] [--end N] [--pages N,N,N]

Output protocol (stdout, one JSON object per line):
    {"status": "progress", "page": 0, "total_pages": 11, "message": "Parsing pages..."}
    {"status": "complete", "output": "/path/to/output.docx", "pages_converted": 11}
    {"status": "error", "message": "..."}

All diagnostic output goes to stderr. Only the JSON protocol goes to stdout.
"""

import sys
import os
import json
import argparse
import logging
import re
import zipfile
import shutil
import tempfile
import xml.etree.ElementTree as ET


def emit(obj):
    """Write a JSON object to stdout for Swift to parse."""
    print(json.dumps(obj), flush=True)


def _patch_pdf2docx_cmyk():
    """Monkey-patch pdf2docx to handle Indexed/DeviceCMYK images.

    pdf2docx checks 'CMYK' in the PDF colorspace label, but Indexed/DeviceCMYK
    images report as "Indexed". We add a fallback check on the resolved pixmap's
    component count (n>=4 means CMYK).
    """
    import fitz
    from pdf2docx.image.ImagesExtractor import ImagesExtractor
    original = ImagesExtractor._recover_pixmap

    @staticmethod
    def _patched(doc, item):
        pix = original(doc, item)
        if pix.colorspace and pix.colorspace.n >= 4:
            pix = fitz.Pixmap(fitz.csRGB, pix)
        return pix

    ImagesExtractor._recover_pixmap = _patched


# --- DOCX Post-Processing ---

# Well-known font name normalizations
FONT_NORMALIZATIONS = {
    "ArialMT": "Arial",
    "Arial-BoldMT": "Arial",
    "Arial-ItalicMT": "Arial",
    "Arial-BoldItalicMT": "Arial",
    "TimesNewRomanPSMT": "Times New Roman",
    "TimesNewRomanPS-BoldMT": "Times New Roman",
    "TimesNewRomanPS-ItalicMT": "Times New Roman",
    "CourierNewPSMT": "Courier New",
}

# Patterns that indicate a font name is a real, recognizable font
KNOWN_FONT_PATTERNS = [
    "Arial", "Helvetica", "Times", "Courier", "Georgia", "Verdana",
    "Calibri", "Cambria", "Gotham", "Garamond", "Palatino", "Futura",
    "Trebuchet", "Tahoma", "Century", "Bookman", "Lucida", "Menlo",
    "Monaco", "Consolas", "Symbol",
]


def is_known_font(name):
    """Check if a font name is recognizable (not a cryptic embedded name)."""
    for pattern in KNOWN_FONT_PATTERNS:
        if pattern.lower() in name.lower():
            return True
    return False


def extract_pdf_font_info(pdf_path, page_indices=None):
    """Extract font properties, superscript info, and character remaps from a PDF.

    Returns:
        font_props: dict mapping font_name -> {serif, bold, italic, mono}
        superscript_fonts: set of font names that have superscript-flagged spans
        char_remaps: dict mapping font_name -> {old_char: new_char} for broken encodings
    """
    import fitz

    doc = fitz.open(pdf_path)
    font_props = {}
    superscript_fonts = set()

    indices = page_indices if page_indices else range(doc.page_count)
    for page_idx in indices:
        if page_idx >= doc.page_count:
            continue
        page = doc[page_idx]
        blocks = page.get_text('dict')['blocks']
        for block in blocks:
            if 'lines' not in block:
                continue
            for line in block['lines']:
                for span in line['spans']:
                    font = span['font']
                    flags = span['flags']
                    is_super = bool(flags & 1)
                    is_italic = bool(flags & 2)
                    is_serif = bool(flags & 4)
                    is_mono = bool(flags & 8)
                    is_bold = bool(flags & 16)

                    if font not in font_props:
                        font_props[font] = {
                            'serif': is_serif,
                            'bold': is_bold,
                            'italic': is_italic,
                            'mono': is_mono,
                        }

                    if is_super:
                        superscript_fonts.add(font)

    # Build character remaps for AdvP* symbol fonts
    char_remaps = _build_char_remaps(doc, indices)

    # Build list of dropped characters (control chars in AdvP* fonts that
    # pdf2docx will strip, along with surrounding text context for reinsertion)
    dropped_chars = _find_dropped_chars(doc, indices, char_remaps)

    doc.close()
    return font_props, superscript_fonts, char_remaps, dropped_chars


# AdvP math/symbol fonts use WRONG standard glyph names for glyphs that are
# actually different symbols. For example, the glyph named "exclam" visually
# renders as a right arrow, "onequarter" renders as equals, etc.
# We apply these overrides per-font AFTER the encoding-based remap.
_ADVP_MATH_OVERRIDES = {
    # AdvP4C4E74: math/relational symbols with wrong glyph names
    # Encoding: [1 /C6  3 /C14 /C2 /C0 /C24  33 /exclam  188 /onequarter  254 /thorn]
    'AdvP4C4E74': {
        '!': '\u2192',       # exclam (code 33) -> right arrow
        '\u00BC': '=',       # onequarter (code 188) -> equals sign
        '\u00FE': '+',       # thorn (code 254) -> plus sign
    },
}

# Glyph name -> Unicode mapping for common Type 1 glyph names used in AdvP* fonts
_GLYPH_NAME_TO_UNICODE = {
    # Greek letters
    'mu': '\u03BC', 'mu1': '\u03BC', 'alpha': '\u03B1', 'beta': '\u03B2',
    'gamma': '\u03B3', 'delta': '\u03B4', 'epsilon': '\u03B5',
    # Math/relational
    'arrowright': '\u2192', 'arrowleft': '\u2190',
    'equal': '=', 'notequal': '\u2260',
    'lessequal': '\u2264', 'greaterequal': '\u2265',
    'plusminus': '\u00B1', 'minus': '\u2212', 'multiply': '\u00D7',
    'divide': '\u00F7', 'degree': '\u00B0', 'approxequal': '\u2248',
    'similar': '\u223C', 'infinity': '\u221E',
    # Symbols
    'copyright': '\u00A9', 'registered': '\u00AE', 'trademark': '\u2122',
    'bullet': '\u2022', 'ellipsis': '\u2026',
    'dagger': '\u2020', 'daggerdbl': '\u2021',
    # Accents / diacriticals (combining marks repurposed as accented chars)
    'Euro': None,  # Special: combining diaeresis in some fonts, handled separately
    # Standard named glyphs
    'exclam': '!', 'onequarter': '\u00BC', 'thorn': '\u00FE',
    'less': '<', 'greater': '>', 'a': 'a', 'g': 'g', 'm': 'm',
}


def _build_char_remaps(doc, page_indices):
    """Build character-level remapping tables for AdvP* symbol fonts.

    Examines PDF font encoding tables (Differences arrays and glyph names)
    to determine correct Unicode mappings for fonts with broken ToUnicode CMaps.

    Returns:
        dict mapping font_name -> {old_char: new_char_or_action}
    """
    import fitz

    char_remaps = {}
    seen_xrefs = {}  # xref -> font_name (from PDF internal name to display name)

    # First, find all AdvP* fonts across target pages and get their xrefs
    advp_fonts = {}  # display_name -> (xref, pdf_internal_name)
    for page_idx in page_indices:
        if page_idx >= doc.page_count:
            continue
        page = doc[page_idx]
        fonts = page.get_fonts(full=True)
        for font_info in fonts:
            xref = font_info[0]
            basefont = font_info[3] if len(font_info) > 3 else ''
            # Extract display name from basefont (e.g., "GEAAFP+AdvP4C4E74" -> "AdvP4C4E74")
            display_name = basefont.split('+')[-1] if '+' in basefont else basefont
            if display_name.startswith('AdvP') and xref not in seen_xrefs:
                seen_xrefs[xref] = display_name
                advp_fonts[display_name] = xref

    if not advp_fonts:
        return char_remaps

    # For each AdvP font, parse the encoding Differences array to get glyph names
    for display_name, xref in advp_fonts.items():
        try:
            remap = _parse_font_encoding(doc, xref, display_name)
            if remap is None:
                remap = {}

            # For Greek/symbol fonts, add ASCII-to-Greek mappings.
            # These fonts use standard ASCII glyph names (a, g, m) but the
            # visual glyphs are Greek letters. The ToUnicode CMap maps them
            # correctly to ASCII, but the intent is Greek.
            _add_greek_remaps_if_symbol_font(doc, xref, display_name, remap)

            # For single-glyph AdvP fonts with standard encoding,
            # detect Greek letters by checking if it's a very sparse font
            # with just one ASCII letter glyph (e.g., AdvP7DED has only 'm'=μ)
            _add_single_glyph_greek_remap(doc, xref, display_name, remap)

            # Apply math/symbol overrides for fonts with wrong glyph names
            # (e.g., AdvP4C4E74 where "exclam" is actually a right arrow)
            for pattern, overrides in _ADVP_MATH_OVERRIDES.items():
                if pattern in display_name:
                    remap.update(overrides)

            if remap:
                char_remaps[display_name] = remap
                # Also add the basefont name variant (with prefix)
                for page_idx in page_indices:
                    if page_idx >= doc.page_count:
                        continue
                    page = doc[page_idx]
                    for font_info in page.get_fonts(full=True):
                        if font_info[0] == xref:
                            basefont = font_info[3] if len(font_info) > 3 else ''
                            if basefont and basefont != display_name:
                                char_remaps[basefont] = remap
                    break
        except Exception as e:
            logging.warning(f"Failed to parse encoding for {display_name}: {e}")

    return char_remaps


def _add_greek_remaps_if_symbol_font(doc, xref, font_name, remap):
    """Detect if an AdvP font is a Greek/symbol font and add ASCII-to-Greek remaps.

    Some AdvP fonts use ASCII glyph names (a, g, m) but render as Greek letters
    (α, γ, μ). We detect this by counting actual glyphs in the Differences array
    (not FirstChar/LastChar range, which can be misleading for sparse fonts).
    """
    font_obj_str = doc.xref_object(xref, compressed=False)

    # Parse encoding to get the glyph names at each code
    enc_match = re.search(r'/Encoding\s+(\d+)\s+0\s+R', font_obj_str)
    if not enc_match:
        return

    enc_xref = int(enc_match.group(1))
    enc_obj_str = doc.xref_object(enc_xref, compressed=False)
    diff_match = re.search(r'/Differences\s*\[(.*?)\]', enc_obj_str, re.DOTALL)
    if not diff_match:
        return

    # Parse Differences to find ASCII letter glyph names
    diff_str = diff_match.group(1)
    code_to_glyph = {}
    current_code = 0
    for token in diff_str.split():
        token = token.strip()
        if not token:
            continue
        if token.startswith('/'):
            code_to_glyph[current_code] = token[1:]
            current_code += 1
        else:
            try:
                current_code = int(token)
            except ValueError:
                continue

    # Count actual glyphs (number of entries in Differences, not code range)
    actual_glyph_count = len(code_to_glyph)
    if actual_glyph_count > 15:
        return  # Too many glyphs, likely a regular text font

    # Check for ASCII letters that should be Greek in symbol fonts
    GREEK_ASCII_MAP = {
        'a': '\u03B1',   # alpha
        'b': '\u03B2',   # beta
        'g': '\u03B3',   # gamma
        'd': '\u03B4',   # delta
        'e': '\u03B5',   # epsilon
        'm': '\u03BC',   # mu
    }

    has_greek_letters = False
    for code, glyph_name in code_to_glyph.items():
        if glyph_name in GREEK_ASCII_MAP and 97 <= code <= 122:
            has_greek_letters = True
            break

    if has_greek_letters:
        for code, glyph_name in code_to_glyph.items():
            if glyph_name in GREEK_ASCII_MAP and 97 <= code <= 122:
                ascii_char = chr(code)
                remap[ascii_char] = GREEK_ASCII_MAP[glyph_name]


def _add_single_glyph_greek_remap(doc, xref, font_name, remap):
    """Handle single-glyph AdvP fonts that use standard encoding (WinAnsiEncoding).

    Some AdvP fonts have just one glyph at an ASCII letter position
    (e.g., AdvP7DED has only 'm' at code 109). These are Greek letter fonts
    where the single glyph is a Greek letter, not the ASCII letter.
    """
    font_obj_str = doc.xref_object(xref, compressed=False)

    # Only handle standard encoding (no custom Differences-based encoding)
    if '/Encoding' in font_obj_str and '/WinAnsiEncoding' not in font_obj_str:
        return  # Has custom encoding, handled by _parse_font_encoding

    first_match = re.search(r'/FirstChar\s+(\d+)', font_obj_str)
    last_match = re.search(r'/LastChar\s+(\d+)', font_obj_str)
    if not first_match or not last_match:
        return

    first_char = int(first_match.group(1))
    last_char = int(last_match.group(1))

    # Only handle single-glyph or very sparse fonts
    if last_char - first_char > 2:
        return

    GREEK_ASCII_MAP = {
        'a': '\u03B1', 'b': '\u03B2', 'g': '\u03B3',
        'd': '\u03B4', 'e': '\u03B5', 'm': '\u03BC',
    }

    for code in range(first_char, last_char + 1):
        if 97 <= code <= 122:  # ASCII lowercase letter
            ascii_char = chr(code)
            if ascii_char in GREEK_ASCII_MAP:
                remap[ascii_char] = GREEK_ASCII_MAP[ascii_char]


def _find_dropped_chars(doc, page_indices, char_remaps):
    """Find characters that pdf2docx will strip (control chars < U+0020).

    For each dropped character, record the correct replacement and surrounding
    text context so we can reinsert it into the DOCX.

    Returns:
        list of {
            'replacement': str,   # correct Unicode character
            'before': str,        # ~10 chars of text before the dropped char
            'after': str,         # ~10 chars of text after the dropped char
        }
    """
    dropped = []

    for page_idx in page_indices:
        if page_idx >= doc.page_count:
            continue
        page = doc[page_idx]
        blocks = page.get_text('dict')['blocks']

        # Collect all spans in reading order with their text
        all_spans = []
        for block in blocks:
            if 'lines' not in block:
                continue
            for line in block['lines']:
                for span in line['spans']:
                    all_spans.append(span)

        # Build a flat text with span boundaries
        for si, span in enumerate(all_spans):
            font = span['font']
            text = span['text']

            # Check if this font has remaps for control chars
            remap = char_remaps.get(font, {})
            if not remap:
                continue

            for ci, ch in enumerate(text):
                if ord(ch) < 0x20:
                    # This is a control char that pdf2docx will strip
                    replacement = remap.get(ch)
                    if replacement is None:
                        continue  # No known replacement

                    # Build before/after context from surrounding text
                    # Before: chars before this one in the same span, plus prev spans
                    before_parts = []
                    before_parts.append(text[:ci])
                    for prev_si in range(si - 1, max(-1, si - 5), -1):
                        before_parts.insert(0, all_spans[prev_si]['text'])
                    before_text = ''.join(before_parts)[-15:]
                    # Strip control chars from context (they'll also be dropped)
                    before_text = ''.join(c for c in before_text if ord(c) >= 0x20)

                    # After: chars after this one in the same span, plus next spans
                    after_parts = []
                    after_parts.append(text[ci + 1:])
                    for next_si in range(si + 1, min(len(all_spans), si + 5)):
                        after_parts.append(all_spans[next_si]['text'])
                    after_text = ''.join(after_parts)[:15:]
                    after_text = ''.join(c for c in after_text if ord(c) >= 0x20)

                    if before_text or after_text:
                        dropped.append({
                            'replacement': replacement,
                            'before': _normalize_ligatures(before_text[-10:]),
                            'after': _normalize_ligatures(after_text[:10]),
                        })

    return dropped


def _normalize_ligatures(text):
    """Normalize common typographic ligatures to ASCII equivalents."""
    ligatures = {
        '\uFB01': 'fi',   # ﬁ
        '\uFB02': 'fl',   # ﬂ
        '\uFB00': 'ff',   # ﬀ
        '\uFB03': 'ffi',  # ﬃ
        '\uFB04': 'ffl',  # ﬄ
    }
    for lig, replacement in ligatures.items():
        text = text.replace(lig, replacement)
    return text


def _reinsert_dropped_chars(tree, dropped_chars):
    """Reinsert characters that were stripped by pdf2docx.

    For each dropped character, find the location in the DOCX text by matching
    the before/after context, then insert the replacement character.
    Handles cases where spaces adjacent to the dropped char were also stripped.
    """
    if not dropped_chars:
        return

    root = tree.getroot()

    # Build a flat list of text elements
    text_elements = []
    for t in root.iter(f'{W}t'):
        if t.text:
            text_elements.append(t)

    # Build concatenated text with element boundaries
    full_text = ''
    boundaries = []  # [(start_offset, text_element), ...]
    for te in text_elements:
        boundaries.append((len(full_text), te))
        full_text += te.text

    used_positions = set()  # Track where we've already inserted

    for dropped in dropped_chars:
        before_raw = dropped['before']
        after_raw = dropped['after']
        replacement = dropped['replacement']

        if not before_raw or not after_raw:
            continue  # Require both contexts to avoid false positives

        before = _normalize_ligatures(before_raw)
        after = _normalize_ligatures(after_raw)

        # Try multiple search strategies:
        # 1. Direct junction: before + after
        # 2. With missing space: before.rstrip() + after.lstrip()
        # 3. With space added: before + " " + after (if DOCX kept space)
        search_variants = []
        search_variants.append((before, after))  # Direct
        b_stripped = before.rstrip()
        a_stripped = after.lstrip()
        if b_stripped != before or a_stripped != after:
            search_variants.append((b_stripped, a_stripped))  # Spaces stripped

        found = False
        for b_ctx, a_ctx in search_variants:
            if found:
                break
            # Use progressively shorter context, minimum 4 chars each side
            min_ctx = min(4, len(b_ctx), len(a_ctx))
            for ctx_len in range(min(len(b_ctx), len(a_ctx), 8), min_ctx - 1, -1):
                search_before = b_ctx[-ctx_len:]
                search_after = a_ctx[:ctx_len]
                search_pattern = search_before + search_after

                # Find ALL occurrences and pick the one not already used
                start = 0
                while start < len(full_text):
                    idx = full_text.find(search_pattern, start)
                    if idx < 0:
                        break

                    insert_pos = idx + len(search_before)
                    # Skip if we already inserted at or near this position
                    if any(abs(insert_pos - p) < 3 for p in used_positions):
                        start = idx + 1
                        continue

                    # Skip if the replacement char already exists at this position
                    if insert_pos < len(full_text) and full_text[insert_pos] == replacement:
                        start = idx + 1
                        continue
                    if insert_pos > 0 and full_text[insert_pos - 1] == replacement:
                        start = idx + 1
                        continue

                    # Insert the character
                    _insert_char_at_position(insert_pos, replacement, boundaries)
                    full_text = full_text[:insert_pos] + replacement + full_text[insert_pos:]
                    # Update boundaries
                    for i in range(len(boundaries)):
                        if boundaries[i][0] > insert_pos:
                            boundaries[i] = (boundaries[i][0] + len(replacement), boundaries[i][1])
                    used_positions.add(insert_pos)
                    found = True
                    break

                if found:
                    break


def _insert_char_at_position(pos, char, boundaries):
    """Insert a character at a given position in the text, modifying the
    appropriate text element."""
    for bi in range(len(boundaries) - 1, -1, -1):
        start = boundaries[bi][0]
        te = boundaries[bi][1]
        if start <= pos:
            local_pos = pos - start
            old_text = te.text
            te.text = old_text[:local_pos] + char + old_text[local_pos:]
            te.set(f'{W}space', 'preserve')
            break


def _parse_font_encoding(doc, xref, font_name):
    """Parse a font's encoding Differences array to build a character remap table.

    Returns:
        dict mapping wrong_unicode_char -> correct_unicode_char
    """
    font_obj_str = doc.xref_object(xref, compressed=False)

    # Extract Encoding reference
    enc_match = re.search(r'/Encoding\s+(\d+)\s+0\s+R', font_obj_str)
    if not enc_match:
        # Check for WinAnsiEncoding or other named encoding
        if '/WinAnsiEncoding' in font_obj_str:
            return None  # Standard encoding, no remap needed
        return None

    enc_xref = int(enc_match.group(1))
    enc_obj_str = doc.xref_object(enc_xref, compressed=False)

    # Parse Differences array: [code1 /name1 /name2 code2 /name3 ...]
    diff_match = re.search(r'/Differences\s*\[(.*?)\]', enc_obj_str, re.DOTALL)
    if not diff_match:
        return None

    diff_str = diff_match.group(1)
    # Parse the Differences array into (code, glyph_name) pairs
    code_to_glyph = {}
    current_code = 0
    for token in diff_str.split():
        token = token.strip()
        if not token:
            continue
        if token.startswith('/'):
            glyph_name = token[1:]
            code_to_glyph[current_code] = glyph_name
            current_code += 1
        else:
            try:
                current_code = int(token)
            except ValueError:
                continue

    # Also get the ToUnicode CMap to see what PyMuPDF returns for each code
    tounicode_map = {}
    tounicode_match = re.search(r'/ToUnicode\s+(\d+)\s+0\s+R', font_obj_str)
    if tounicode_match:
        tounicode_xref = int(tounicode_match.group(1))
        try:
            cmap_stream = doc.xref_stream(tounicode_xref)
            if cmap_stream:
                cmap_text = cmap_stream.decode('latin-1', errors='replace')
                tounicode_map = _parse_tounicode_cmap(cmap_text)
        except Exception:
            pass

    # Now build the remap: for each code, determine what PyMuPDF outputs vs
    # what the glyph name says it should be
    remap = {}
    for code, glyph_name in code_to_glyph.items():
        # What does PyMuPDF output for this code?
        if code in tounicode_map:
            wrong_char = tounicode_map[code]
        elif code < 128:
            wrong_char = chr(code)  # ASCII fallback
        else:
            wrong_char = chr(code)  # Direct mapping

        # What should this glyph actually be?
        correct_char = _glyph_name_to_char(glyph_name, font_name)

        if correct_char is None:
            # This is a combining mark or unknown glyph. If the wrong_char
            # is a control character (U+0001-U+001F), add a deletion entry
            # so it gets cleaned up even if the combining handler misses it.
            if ord(wrong_char) < 0x20:
                remap[wrong_char] = None  # Will be deleted by _apply_char_remaps
            continue

        if wrong_char != correct_char:
            remap[wrong_char] = correct_char

    return remap if remap else None


def _parse_tounicode_cmap(cmap_text):
    """Parse a ToUnicode CMap to get code -> Unicode character mappings."""
    result = {}
    # Match bfchar entries: <XX> <XXXX>
    for match in re.finditer(r'<([0-9a-fA-F]+)>\s*<([0-9a-fA-F]+)>', cmap_text):
        code_hex = match.group(1)
        uni_hex = match.group(2)
        try:
            code = int(code_hex, 16)
            uni_val = int(uni_hex, 16)
            result[code] = chr(uni_val)
        except (ValueError, OverflowError):
            continue
    return result


def _glyph_name_to_char(glyph_name, font_name):
    """Convert a Type 1 glyph name to the correct Unicode character.

    Returns None for combining marks and unknown glyphs (they should be
    removed or merged with adjacent characters).
    """
    # Check our mapping table first
    if glyph_name in _GLYPH_NAME_TO_UNICODE:
        return _GLYPH_NAME_TO_UNICODE[glyph_name]

    # Glyph names starting with 'C' followed by digits are custom glyphs
    # in AdvP* fonts. These are typically combining marks or symbols.
    if re.match(r'^C\d+$', glyph_name):
        # These are combining diacritical marks or special symbols.
        # Map known patterns based on font context:
        return _map_custom_glyph(glyph_name, font_name)

    # Try Adobe Glyph List standard names
    return _AGL_FALLBACK.get(glyph_name)


# Common Adobe Glyph List names not in our main table
_AGL_FALLBACK = {
    'space': ' ', 'period': '.', 'comma': ',', 'colon': ':',
    'semicolon': ';', 'hyphen': '-', 'endash': '\u2013', 'emdash': '\u2014',
    'quoteleft': '\u2018', 'quoteright': '\u2019',
    'quotedblleft': '\u201C', 'quotedblright': '\u201D',
    'fi': 'fi', 'fl': 'fl',
    'summation': '\u2211', 'product': '\u220F', 'radical': '\u221A',
    'integral': '\u222B', 'partialdiff': '\u2202',
}


# Known custom glyph mappings for AdvP* fonts, keyed by font name pattern
_CUSTOM_GLYPH_MAP = {
    # AdvP4C4E74: mathematical/relational symbols
    # Encoding: [1 /C6  3 /C14 /C2 /C0 /C24  33 /exclam  188 /onequarter  254 /thorn]
    # C6 at code 1 = plus-minus, C14 at code 3 = degree, C2 at code 4 = multiplication,
    # C0 at code 5 = minus, C24 at code 6 = approximately
    'AdvP4C4E74': {
        'C6': '\u00B1',    # plus-minus (code 1, PyMuPDF -> U+0001)
        'C14': '\u00B0',   # degree (code 3, PyMuPDF -> U+0003)
        'C2': '\u00D7',    # multiplication (code 4, PyMuPDF -> U+0004)
        'C0': '\u2212',    # minus (code 5, PyMuPDF -> U+0005)
        'C24': '\u223C',   # approximately (code 6, PyMuPDF -> U+0006)
    },
    # AdvP697C: Greek letters
    # Encoding: [2 /C211 /C210  60 /less  62 /greater  97 /a  103 /g  109 /m]
    # C211 at code 2 = copyright, C210 at code 3 = registered
    'AdvP697C': {
        'C211': '\u00A9',  # copyright (code 2, PyMuPDF -> U+0002)
        'C210': '\u00AE',  # registered (code 3, PyMuPDF -> U+0003)
    },
    # AdvP4C4E59: diacritical marks (combining)
    # Encoding: [2 /C16 /C19  128 /Euro]
    # C16 at code 2 = dotless-i base (combining, remove)
    # C19 at code 3 = combining acute accent (remove, merge with next char)
    # Euro at code 128 = combining diaeresis (handled specially)
    'AdvP4C4E59': {
        'C16': None,   # combining mark, will be removed
        'C19': None,   # combining acute, will be removed
    },
}


def _map_custom_glyph(glyph_name, font_name):
    """Map a custom glyph name (C0, C6, C14, etc.) to the correct Unicode character."""
    for font_pattern, glyph_map in _CUSTOM_GLYPH_MAP.items():
        if font_pattern in font_name:
            if glyph_name in glyph_map:
                return glyph_map[glyph_name]
    return None


def build_font_map(font_props):
    """Build a mapping from cryptic font names to real system fonts.

    Returns:
        dict mapping old_name -> {"name": new_name, "bold": bool, "italic": bool}
    """
    font_map = {}

    for font_name, props in font_props.items():
        # Check if the font name contains a known font
        if is_known_font(font_name):
            # Normalize known font names
            base_name = font_name
            # Strip prefix before + (e.g., "BCDGEE+Calibri-Bold" -> "Calibri-Bold")
            if '+' in base_name:
                base_name = base_name.split('+', 1)[1]

            # Check for explicit normalizations
            if base_name in FONT_NORMALIZATIONS:
                new_name = FONT_NORMALIZATIONS[base_name]
            else:
                # Strip style suffix (e.g., "Gotham-Bold" -> "Gotham")
                new_name = base_name.split('-')[0]

            # Detect bold/italic from font name
            lower_name = font_name.lower()
            is_bold = props['bold'] or 'bold' in lower_name
            is_italic = props['italic'] or 'italic' in lower_name or font_name.endswith('.I')

            mapping = {
                'name': new_name,
                'bold': is_bold,
                'italic': is_italic,
            }
            font_map[font_name] = mapping
            # pdf2docx normalizes "Gotham-Bold" -> "Gotham", so also map the base name
            if '-' in font_name:
                base = font_name.split('-')[0]
                if base and base not in font_map:
                    font_map[base] = mapping
            continue

        # Cryptic font name (Adv*, etc.) - map based on properties
        is_italic = props['italic'] or font_name.endswith('.I')
        is_bold = props['bold']

        if props['mono']:
            new_name = "Courier New"
        elif props['serif']:
            new_name = "Times New Roman"
        else:
            new_name = "Helvetica Neue"

        mapping = {
            'name': new_name,
            'bold': is_bold,
            'italic': is_italic,
        }
        font_map[font_name] = mapping

        # pdf2docx normalizes font names: "GEAAEK+AdvOT1ef757c0" -> "AdvOT1ef757c0"
        # and sometimes "AdvOT1ef757c0+fb" -> "fb" (taking the part after +).
        # Add mappings for these derived names too.
        if '+' in font_name:
            # "AdvOT1ef757c0+fb" -> also map "fb"
            suffix = font_name.split('+')[-1]
            if suffix and suffix not in font_map:
                font_map[suffix] = mapping
            # Also map the base: "AdvOT1ef757c0+fb" -> "AdvOT1ef757c0"
            base = font_name.split('+')[0]
            # Strip any prefix before + in the base (e.g., "GEAAEK+AdvOT...")
            if base and base not in font_map:
                font_map[base] = mapping

    return font_map


# OOXML namespace
W_NS = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
W = '{' + W_NS + '}'


def get_paragraph_dominant_size(para):
    """Get the most common font size in a paragraph (in half-points)."""
    sizes = {}
    for run in para.findall(f'.//{W}r'):
        rpr = run.find(f'{W}rPr')
        if rpr is None:
            continue
        sz = rpr.find(f'{W}sz')
        if sz is not None:
            val = sz.get(f'{W}val')
            if val:
                sizes[val] = sizes.get(val, 0) + 1
    if not sizes:
        return None
    return max(sizes, key=sizes.get)


def _apply_char_remaps(text, font_name, char_remaps):
    """Apply character-level remapping to text from a specific font.

    Handles three cases:
    1. Simple 1:1 character replacement (e.g., '!' -> '→' in AdvP4C4E74)
    2. Character deletion (remap value is None, e.g., combining marks)
    3. Combining diacritical marks (e.g., € in AdvP4C4E59 = diaeresis on previous vowel)
    """
    if not text or font_name not in char_remaps:
        return text

    remap = char_remaps[font_name]
    result = list(text)
    i = 0
    while i < len(result):
        ch = result[i]
        if ch in remap:
            replacement = remap[ch]
            if replacement is None:
                # Delete this character (combining mark artifact)
                result.pop(i)
                continue
            else:
                result[i] = replacement
        i += 1

    return ''.join(result)


def _apply_combining_diacriticals(paragraphs):
    """Fix combining diacritical marks that span across adjacent DOCX runs.

    In AdvP4C4E59-type fonts, a diaeresis (€/U+20AC) or acute accent (U+0003)
    is a separate run that should combine with the adjacent base character.

    The combining mark glyph overlaps with the base character in the PDF,
    meaning:
    - € (diaeresis): combine with the PRECEDING vowel
    - U+0003 (acute): combine with the FOLLOWING character

    This function merges these across run boundaries in the DOCX XML.
    """
    # Unicode combining map: base_vowel + diacritic_type -> precomposed char
    DIAERESIS_MAP = {
        'a': '\u00E4', 'e': '\u00EB', 'i': '\u00EF', 'o': '\u00F6',
        'u': '\u00FC', 'y': '\u00FF',
        'A': '\u00C4', 'E': '\u00CB', 'I': '\u00CF', 'O': '\u00D6',
        'U': '\u00DC', 'Y': '\u0178',
    }
    ACUTE_MAP = {
        'a': '\u00E1', 'e': '\u00E9', 'i': '\u00ED', 'o': '\u00F3',
        'u': '\u00FA', 'y': '\u00FD',
        'A': '\u00C1', 'E': '\u00C9', 'I': '\u00CD', 'O': '\u00D3',
        'U': '\u00DA', 'Y': '\u00DD',
    }

    DIAERESIS_CHAR = '\u20AC'  # Euro sign = combining diaeresis in AdvP4C4E59
    ACUTE_CHAR = '\u0003'      # ETX control = combining acute in AdvP4C4E59
    DOTLESS_I_CHAR = '\u0002'  # STX control = dotless-i base in AdvP4C4E59

    for para in paragraphs:
        runs = para.findall(f'.//{W}r')
        runs_to_remove = []

        for idx, run in enumerate(runs):
            text_el = run.find(f'{W}t')
            if text_el is None or not text_el.text:
                continue
            text = text_el.text

            # Case 1: Run contains diaeresis mark (€)
            if DIAERESIS_CHAR in text:
                # Check if this run also has a dotless-i (€ + \x02 = ï)
                if DOTLESS_I_CHAR in text:
                    # This is "ï" - the dotless-i + diaeresis pair.
                    # Insert ï into the previous run's last vowel position
                    # or replace this run's content with ï
                    if idx > 0:
                        prev_text_el = runs[idx - 1].find(f'{W}t')
                        if prev_text_el is not None and prev_text_el.text:
                            # Append ï to previous run (e.g., "na" + ï = "naï")
                            prev_text_el.text = prev_text_el.text + '\u00EF'
                            prev_text_el.set(f'{W}space', 'preserve')
                            runs_to_remove.append(run)
                            continue

                    # Fallback: replace in-place
                    text_el.text = text.replace(DIAERESIS_CHAR, '').replace(DOTLESS_I_CHAR, '\u00EF')
                    continue

                # Pure diaeresis mark - apply to FIRST char of NEXT run if it's a vowel.
                # If next char isn't a vowel, the base char was a dotless-i that got
                # stripped — default to ï.
                new_text = text.replace(DIAERESIS_CHAR, '')
                if not new_text:
                    # Entire run is the diaeresis
                    merged = False
                    if idx + 1 < len(runs):
                        next_text_el = runs[idx + 1].find(f'{W}t')
                        if next_text_el is not None and next_text_el.text:
                            next_text = next_text_el.text
                            if next_text and next_text[0] in DIAERESIS_MAP:
                                next_text_el.text = DIAERESIS_MAP[next_text[0]] + next_text[1:]
                                next_text_el.set(f'{W}space', 'preserve')
                                runs_to_remove.append(run)
                                merged = True
                    if not merged:
                        # Fallback: the dotless-i base was stripped, produce ï
                        if idx > 0:
                            prev_text_el = runs[idx - 1].find(f'{W}t')
                            if prev_text_el is not None and prev_text_el.text:
                                prev_text_el.text = prev_text_el.text + '\u00EF'
                                prev_text_el.set(f'{W}space', 'preserve')
                                runs_to_remove.append(run)
                else:
                    text_el.text = new_text

            # Case 2: Run contains acute accent mark (U+0003 from AdvP4C4E59)
            # Only handle if this looks like a combining mark (run is very short)
            if ACUTE_CHAR in text and len(text.replace(ACUTE_CHAR, '')) == 0:
                # Entire run is acute mark(s) - merge with next run
                if idx + 1 < len(runs):
                    next_text_el = runs[idx + 1].find(f'{W}t')
                    if next_text_el is not None and next_text_el.text:
                        next_text = next_text_el.text
                        if next_text and next_text[0] in ACUTE_MAP:
                            next_text_el.text = ACUTE_MAP[next_text[0]] + next_text[1:]
                            next_text_el.set(f'{W}space', 'preserve')
                            runs_to_remove.append(run)

        # Remove merged runs
        for run in runs_to_remove:
            parent = para
            # The run might be inside a hyperlink or other wrapper
            for possible_parent in para.iter():
                if run in list(possible_parent):
                    parent = possible_parent
                    break
            try:
                parent.remove(run)
            except ValueError:
                pass


def fix_document_xml(tree, font_map, superscript_fonts, char_remaps=None):
    """Fix fonts, bold/italic, superscript, and character encoding in document.xml."""
    root = tree.getroot()
    char_remaps = char_remaps or {}

    # Build a secondary remap lookup that also checks normalized font names
    # (pdf2docx may normalize "AdvP4C4E74" differently)
    remap_lookup = dict(char_remaps)

    # Also build AdvP697C-style Greek letter remaps where ASCII letters
    # map to Greek (m->μ, g->γ, a->α). These are font-specific:
    # only remap when the DOCX font matches the AdvP font name.
    greek_remap_fonts = set()
    for fname in char_remaps:
        if 'AdvP697C' in fname or 'AdvP7DED' in fname:
            greek_remap_fonts.add(fname)

    for para in root.iter(f'{W}p'):
        dominant_size = get_paragraph_dominant_size(para)

        for run in para.findall(f'.//{W}r'):
            rpr = run.find(f'{W}rPr')
            if rpr is None:
                continue

            text_el = run.find(f'{W}t')
            run_text = text_el.text if text_el is not None else ''

            # --- Font replacement ---
            rfonts = rpr.find(f'{W}rFonts')
            old_font = None
            if rfonts is not None:
                old_font = rfonts.get(f'{W}ascii') or rfonts.get(f'{W}hAnsi')

            # --- Character remapping ---
            if old_font and run_text and text_el is not None:
                # Apply character remaps for this font
                new_text = _apply_char_remaps(run_text, old_font, remap_lookup)
                if new_text != run_text:
                    text_el.text = new_text
                    if new_text:
                        text_el.set(f'{W}space', 'preserve')
                    run_text = new_text

            if old_font and old_font in font_map:
                mapping = font_map[old_font]
                new_name = mapping['name']
                # Update all font attributes
                for attr in ['ascii', 'hAnsi', 'eastAsia', 'cs']:
                    if rfonts.get(f'{W}{attr}') is not None:
                        rfonts.set(f'{W}{attr}', new_name)

                # --- Bold fix ---
                bold_el = rpr.find(f'{W}b')
                if mapping['bold']:
                    # Font should be bold
                    if bold_el is not None:
                        # Remove val="0" if present
                        if f'{W}val' in bold_el.attrib:
                            del bold_el.attrib[f'{W}val']
                    else:
                        bold_el = ET.SubElement(rpr, f'{W}b')
                else:
                    # Font should not be bold - remove the element entirely
                    # (let it inherit from style, which is normal weight)
                    if bold_el is not None:
                        rpr.remove(bold_el)

                # --- Italic fix ---
                italic_el = rpr.find(f'{W}i')
                if mapping['italic']:
                    if italic_el is not None:
                        if f'{W}val' in italic_el.attrib:
                            del italic_el.attrib[f'{W}val']
                    else:
                        italic_el = ET.SubElement(rpr, f'{W}i')
                else:
                    if italic_el is not None:
                        rpr.remove(italic_el)

            # --- Superscript fix ---
            # Check if this run should be superscript:
            # 1. Font had superscript flags in the PDF
            # 2. Run's font size is significantly smaller than the paragraph's dominant size
            if old_font and old_font in superscript_fonts and dominant_size:
                sz_el = rpr.find(f'{W}sz')
                if sz_el is not None:
                    run_size = sz_el.get(f'{W}val')
                    if run_size and dominant_size:
                        try:
                            ratio = int(run_size) / int(dominant_size)
                            if ratio <= 0.80:
                                # This is a superscript run
                                vert = rpr.find(f'{W}vertAlign')
                                if vert is None:
                                    vert = ET.SubElement(rpr, f'{W}vertAlign')
                                vert.set(f'{W}val', 'superscript')
                        except (ValueError, ZeroDivisionError):
                            pass

    # Fix combining diacritical marks that span across runs
    _apply_combining_diacriticals(list(root.iter(f'{W}p')))


def remove_blank_pages(tree):
    """Remove blank pages caused by pdf2docx's column-switching section breaks.

    pdf2docx generates a complex multi-section structure for two-column layouts:
        continuous(cols=2) → nextColumn(cols=2) → continuous(cols=1) → nextPage(cols=2)
    for each page. The continuous(cols=1) "bridge" sections contain header/footer
    remnants ("Pham et al.", journal name, page numbers) and cause Word to insert
    visual blank pages due to the column-count transition (cols=2 → cols=1 → cols=2).

    This function removes these bridge sections and any empty nextPage sections.
    """
    root = tree.getroot()
    body = root.find(f'{W}body')
    if body is None:
        return

    children = list(body)
    WP_NS = 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing'

    # Build section groups: contiguous paragraphs ending with a sectPr
    sections = []
    current_paras = []

    for child in children:
        # Check for section break in paragraph properties
        sect_pr = None
        ppr = child.find(f'{W}pPr') if child.tag == f'{W}p' else None
        if ppr is not None:
            sect_pr = ppr.find(f'{W}sectPr')

        current_paras.append(child)

        if sect_pr is not None:
            sect_type_el = sect_pr.find(f'{W}type')
            sect_type = sect_type_el.get(f'{W}val', 'nextPage') if sect_type_el is not None else 'nextPage'

            cols_el = sect_pr.find(f'{W}cols')
            num_cols = 1
            if cols_el is not None:
                try:
                    num_cols = int(cols_el.get(f'{W}num', '1'))
                except (ValueError, TypeError):
                    pass

            text_len = 0
            has_image = False
            for para in current_paras:
                for t in para.iter(f'{W}t'):
                    if t.text:
                        text_len += len(t.text.strip())
                if para.find(f'.//{{{WP_NS}}}inline') is not None or \
                   para.find(f'.//{{{WP_NS}}}anchor') is not None:
                    has_image = True

            sections.append({
                'paragraphs': list(current_paras),
                'type': sect_type,
                'cols': num_cols,
                'text_len': text_len,
                'has_image': has_image,
            })
            current_paras = []
        elif child.tag == f'{W}sectPr':
            # Final body-level section
            sections.append({
                'paragraphs': list(current_paras),
                'type': 'final',
                'cols': -1,
                'text_len': 0,
                'has_image': False,
            })
            current_paras = []

    # Remaining paragraphs (edge case)
    if current_paras:
        sections.append({
            'paragraphs': current_paras,
            'type': 'trailing',
            'cols': 1,
            'text_len': 0,
            'has_image': False,
        })

    # Identify bridge sections to remove:
    # 1. continuous(cols=1) sections with very little text, between multi-column sections
    # 2. Empty nextPage sections (0 text, no images)
    to_remove = set()

    for i, sect in enumerate(sections):
        if sect['type'] in ('final', 'trailing'):
            continue

        # Target: continuous sections with single column and sparse text
        # These are the column-switching bridges that cause blank pages
        if sect['type'] == 'continuous' and sect['cols'] <= 1 and \
           sect['text_len'] < 150 and not sect['has_image']:
            # Verify this is between multi-column sections (bridge pattern)
            prev_cols = sections[i - 1]['cols'] if i > 0 else 1
            next_cols = sections[i + 1]['cols'] if i + 1 < len(sections) else 1
            if prev_cols >= 2 or next_cols >= 2:
                to_remove.add(i)

        # Also remove empty nextPage sections (no content at all)
        if sect['type'] == 'nextPage' and sect['text_len'] == 0 and not sect['has_image']:
            to_remove.add(i)

    # Remove sections (elements) from body
    removed_count = 0
    for i in sorted(to_remove, reverse=True):
        sect = sections[i]
        for para in sect['paragraphs']:
            try:
                body.remove(para)
                removed_count += 1
            except ValueError:
                pass

    if removed_count:
        logging.info(f"Removed {removed_count} elements from {len(to_remove)} blank/bridge sections")


def fix_font_table_xml(tree, font_map):
    """Update font declarations in fontTable.xml."""
    root = tree.getroot()

    # Track which new fonts we need
    existing_fonts = set()
    for font_el in root.findall(f'{W}font'):
        name = font_el.get(f'{W}name')
        if name:
            existing_fonts.add(name)

    # Replace font names in existing entries and track remapped names
    remapped = {}
    for font_el in root.findall(f'{W}font'):
        name = font_el.get(f'{W}name')
        if name and name in font_map:
            new_name = font_map[name]['name']
            font_el.set(f'{W}name', new_name)
            remapped[name] = new_name


def postprocess_docx(pdf_path, docx_path, page_indices=None):
    """Post-process a DOCX file to fix fonts, bold/italic, superscript,
    character encoding, and blank pages based on PDF metadata."""

    # 1. Extract font info, character remaps, and dropped chars from PDF
    font_props, superscript_fonts, char_remaps, dropped_chars = extract_pdf_font_info(pdf_path, page_indices)

    # 2. Build font mapping
    font_map = build_font_map(font_props)

    # Skip if nothing to fix
    if not font_map and not char_remaps and not dropped_chars:
        return

    # 3. Open DOCX as ZIP and modify XML files
    temp_dir = tempfile.mkdtemp(prefix="spindrift_postprocess_")
    try:
        # Extract DOCX
        with zipfile.ZipFile(docx_path, 'r') as zin:
            zin.extractall(temp_dir)

        # Register OOXML namespaces to preserve them on output
        _register_ooxml_namespaces()

        # Fix document.xml
        doc_xml_path = os.path.join(temp_dir, 'word', 'document.xml')
        if os.path.exists(doc_xml_path):
            doc_original_ns = _capture_root_namespaces(doc_xml_path)
            tree = ET.parse(doc_xml_path)
            fix_document_xml(tree, font_map, superscript_fonts, char_remaps)
            _reinsert_dropped_chars(tree, dropped_chars)
            remove_blank_pages(tree)
            _write_xml_preserving_namespaces(tree, doc_xml_path, doc_original_ns)

        # Fix fontTable.xml
        font_xml_path = os.path.join(temp_dir, 'word', 'fontTable.xml')
        if os.path.exists(font_xml_path):
            ft_original_ns = _capture_root_namespaces(font_xml_path)
            tree = ET.parse(font_xml_path)
            fix_font_table_xml(tree, font_map)
            _write_xml_preserving_namespaces(tree, font_xml_path, ft_original_ns)

        # 4. Rewrite DOCX from modified files
        # Collect all files from the extracted directory
        with zipfile.ZipFile(docx_path, 'w', zipfile.ZIP_DEFLATED) as zout:
            for dirpath, dirnames, filenames in os.walk(temp_dir):
                for filename in filenames:
                    file_path = os.path.join(dirpath, filename)
                    arcname = os.path.relpath(file_path, temp_dir)
                    zout.write(file_path, arcname)

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def _register_ooxml_namespaces():
    """Register OOXML namespaces so ElementTree preserves them on output."""
    namespaces = {
        'wpc': 'http://schemas.microsoft.com/office/word/2010/wordprocessingCanvas',
        'mo': 'http://schemas.microsoft.com/office/mac/office/2008/main',
        'mc': 'http://schemas.openxmlformats.org/markup-compatibility/2006',
        'mv': 'urn:schemas-microsoft-com:mac:vml',
        'o': 'urn:schemas-microsoft-com:office:office',
        'r': 'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
        'm': 'http://schemas.openxmlformats.org/officeDocument/2006/math',
        'v': 'urn:schemas-microsoft-com:vml',
        'wp14': 'http://schemas.microsoft.com/office/word/2010/wordprocessingDrawing',
        'wp': 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing',
        'w10': 'urn:schemas-microsoft-com:office:word',
        'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
        'w14': 'http://schemas.microsoft.com/office/word/2010/wordml',
        'wpg': 'http://schemas.microsoft.com/office/word/2010/wordprocessingGroup',
        'wpi': 'http://schemas.microsoft.com/office/word/2010/wordprocessingInk',
        'wne': 'http://schemas.microsoft.com/office/word/2006/wordml',
        'wps': 'http://schemas.microsoft.com/office/word/2010/wordprocessingShape',
        'a': 'http://schemas.openxmlformats.org/drawingml/2006/main',
        'pic': 'http://schemas.openxmlformats.org/drawingml/2006/picture',
    }
    for prefix, uri in namespaces.items():
        ET.register_namespace(prefix, uri)


def _capture_root_namespaces(xml_path):
    """Read the root element's namespace declarations from an XML file.

    Returns a dict mapping prefix -> URI for all xmlns declarations found
    on the root element. The default namespace uses '' as its key.
    """
    with open(xml_path, 'rb') as f:
        raw = f.read(8192)  # Root element is always within first 8K
    text = raw.decode('utf-8', errors='replace')

    ns_decls = {}
    # Find the root element's opening tag (after XML declaration)
    decl_end = text.find('?>')
    tag_start = text.find('<', (decl_end + 2) if decl_end >= 0 else 0)
    if tag_start < 0:
        return ns_decls
    tag_end = text.find('>', tag_start)
    if tag_end < 0:
        return ns_decls
    root_tag = text[tag_start:tag_end + 1]

    for m in re.finditer(r'xmlns(?::(\w+))?="([^"]+)"', root_tag):
        prefix = m.group(1) or ''
        uri = m.group(2)
        ns_decls[prefix] = uri

    return ns_decls


def _write_xml_preserving_namespaces(tree, xml_path, original_ns):
    """Write an XML tree preserving all original namespace declarations.

    Python's ElementTree drops xmlns declarations for prefixes not used in
    any element tag name. OOXML requires these declarations because they are
    referenced in mc:Ignorable attributes (e.g., w14, wp14). This function
    writes the XML via ET, then injects any missing namespace declarations
    back into the root element.

    Also adds standalone='yes' to the XML declaration as required by OOXML.
    """
    tree.write(xml_path, xml_declaration=True, encoding='UTF-8')

    with open(xml_path, 'r', encoding='utf-8') as f:
        xml_text = f.read()

    # Find current namespace declarations in the written output's root element
    current_ns = {}
    decl_end = xml_text.find('?>')
    tag_start = xml_text.find('<', (decl_end + 2) if decl_end >= 0 else 0)
    tag_end = xml_text.find('>', tag_start) if tag_start >= 0 else -1
    if tag_start >= 0 and tag_end >= 0:
        root_tag = xml_text[tag_start:tag_end + 1]
        for m in re.finditer(r'xmlns(?::(\w+))?="([^"]+)"', root_tag):
            prefix = m.group(1) or ''
            uri = m.group(2)
            current_ns[prefix] = uri

    # Build list of missing namespace declarations
    missing = []
    for prefix, uri in original_ns.items():
        if prefix not in current_ns:
            if prefix:
                missing.append(f'xmlns:{prefix}="{uri}"')
            else:
                missing.append(f'xmlns="{uri}"')

    if missing and tag_end >= 0:
        # Insert missing declarations before the closing > of the root element
        xml_text = xml_text[:tag_end] + ' ' + ' '.join(missing) + xml_text[tag_end:]

    # Add standalone='yes' to XML declaration (required by OOXML)
    xml_text = xml_text.replace(
        "<?xml version='1.0' encoding='UTF-8'?>",
        "<?xml version='1.0' encoding='UTF-8' standalone='yes'?>"
    )

    with open(xml_path, 'w', encoding='utf-8') as f:
        f.write(xml_text)


# --- Main conversion logic ---

def main():
    parser = argparse.ArgumentParser(description="Convert PDF to DOCX")
    parser.add_argument("input", help="Input PDF file path")
    parser.add_argument("output", help="Output DOCX file path")
    parser.add_argument("--start", type=int, default=0, help="Start page (0-indexed)")
    parser.add_argument("--end", type=int, default=None, help="End page (exclusive, omit for all)")
    parser.add_argument("--pages", type=str, default=None,
                        help="Comma-separated page indices (overrides --start/--end)")
    args = parser.parse_args()

    # Redirect all library logging to stderr so stdout stays clean for JSON protocol
    logging.basicConfig(stream=sys.stderr, level=logging.WARNING)
    for name in ["pdf2docx", "fonttools", "PIL", "fitz"]:
        logging.getLogger(name).setLevel(logging.WARNING)

    # Validate input
    if not os.path.isfile(args.input):
        emit({"status": "error", "message": f"Input file not found: {args.input}"})
        sys.exit(1)

    try:
        import fitz  # PyMuPDF
    except ImportError:
        emit({"status": "error", "message": "PyMuPDF (fitz) not installed"})
        sys.exit(1)

    try:
        from pdf2docx import Converter
    except ImportError:
        emit({"status": "error", "message": "pdf2docx not installed"})
        sys.exit(1)

    _patch_pdf2docx_cmyk()

    # Open PDF, get page count, and check if pages have extractable text
    try:
        doc = fitz.open(args.input)
        total_pages = doc.page_count
    except Exception as e:
        emit({"status": "error", "message": f"Failed to open PDF: {e}"})
        sys.exit(1)

    # Determine which pages to convert
    pages_param = None
    if args.pages:
        pages_param = [int(p.strip()) for p in args.pages.split(",")]
        effective_count = len(pages_param)
        check_indices = pages_param
    else:
        effective_count = (args.end if args.end else total_pages) - args.start
        check_indices = list(range(args.start, args.end if args.end else total_pages))

    emit({"status": "progress", "page": 0, "total_pages": effective_count,
          "message": "Opening document..."})

    # Check if the PDF has extractable text on the target pages
    has_text = False
    for idx in check_indices:
        if idx < doc.page_count:
            text = doc[idx].get_text().strip()
            if len(text) > 10:  # More than trivial whitespace/artifacts
                has_text = True
                break
    doc.close()

    try:
        if has_text:
            # Use pdf2docx for text-based PDFs
            cv = Converter(args.input)

            emit({"status": "progress", "page": 0, "total_pages": effective_count,
                  "message": "Analyzing document..."})

            cv.convert(
                args.output,
                start=args.start,
                end=args.end,
                pages=pages_param,
            )

            cv.close()

            # Post-process: fix fonts, bold/italic, and superscript
            emit({"status": "progress", "page": effective_count, "total_pages": effective_count,
                  "message": "Fixing formatting..."})
            postprocess_docx(args.input, args.output, check_indices)

            pages_converted = effective_count
        else:
            # Scanned/image PDF — embed pages as images
            pages_converted = convert_scanned_pdf(
                args.input, args.output, args.start, args.end, pages_param
            )

        emit({
            "status": "complete",
            "output": args.output,
            "pages_converted": pages_converted
        })

    except Exception as e:
        emit({"status": "error", "message": str(e)})
        sys.exit(1)


def convert_scanned_pdf(input_path, output_path, start, end, pages_param):
    """Fallback for scanned PDFs: embed each page as an image in the DOCX."""
    import fitz
    from docx import Document
    from docx.shared import Inches
    import tempfile

    doc = fitz.open(input_path)
    word_doc = Document()

    if pages_param:
        page_indices = pages_param
    else:
        page_indices = list(range(start, end if end else doc.page_count))

    emit({"status": "progress", "page": 0, "total_pages": len(page_indices),
          "message": "Converting scanned pages as images..."})

    temp_dir = tempfile.mkdtemp(prefix="spindrift_scan_")
    pages_done = 0

    for i, page_idx in enumerate(page_indices):
        if page_idx >= doc.page_count:
            continue

        page = doc[page_idx]
        # Render at 200 DPI for good quality
        mat = fitz.Matrix(200 / 72, 200 / 72)
        pix = page.get_pixmap(matrix=mat)
        img_path = os.path.join(temp_dir, f"page_{page_idx}.png")
        pix.save(img_path)

        # Add to Word document
        if i > 0:
            word_doc.add_page_break()

        # Calculate width to fit page (6.5 inches usable width)
        aspect = pix.height / pix.width
        width = 6.5
        word_doc.add_picture(img_path, width=Inches(width))

        pages_done += 1
        emit({"status": "progress", "page": pages_done, "total_pages": len(page_indices),
              "message": f"Rendering page {page_idx + 1}..."})

        # Clean up temp image
        os.remove(img_path)

    word_doc.save(output_path)
    doc.close()

    # Clean up temp directory
    try:
        os.rmdir(temp_dir)
    except OSError:
        pass

    return pages_done


if __name__ == "__main__":
    main()
