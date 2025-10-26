#!/usr/bin/env python3
import sys, json, re
from PIL import Image, ImageOps, ImageFilter

try:
    import pytesseract
    from pytesseract import Output
except Exception as e:
    print(json.dumps({"error": f"pytesseract not available: {e}", "student_number":"", "surname":"", "analyzed": ""}))
    sys.exit(0)

try:
    import cv2
    import numpy as np
except Exception:
    cv2 = None
    np = None

BLACKLIST = {
    'university','college','philippines','republic','diploma','bachelor',
    'technology','camera','report','student','department','institute','school','polytechnic','information'
}
BLACKLIST_PAT = re.compile(r'philipp|philip|phillip', re.I)
TRIPLE_REPEAT = re.compile(r'(.)\1\1', re.I)

def preprocess(path: str) -> Image.Image:
    img = Image.open(path)
    if img.width < 900:
        scale = min(1200 / max(1, img.width), 2.0)
        img = img.resize((int(img.width*scale), int(img.height*scale)), Image.LANCZOS)
    img = img.convert('L')
    img = ImageOps.autocontrast(img)
    img = img.filter(ImageFilter.SHARPEN)
    if cv2 and np:
        arr = np.array(img)
        _, bin_img = cv2.threshold(arr, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        img = Image.fromarray(bin_img)
    return img

def find_student_number(text: str) -> str:
    pats = [
        r'\b\d{4}[-–—]\d{5,}[-–—]MN[-–—]0\b',
        r'\b\d{4}[-\s]\d{5,}[-\s]MN[-\s]\d\b',
    ]
    for pat in pats:
        m = re.search(pat, text)
        if m:
            return m.group(0).replace('—','-').replace('–','-')
    m2 = re.search(r'\b\d{3,}[-/ ]\d{4,}[-/ ]MN[-/ ]\d\b', text)
    return m2.group(0) if m2 else ''

def _median(vals):
    s = sorted(vals)
    n = len(s)
    if n == 0: return 0
    return s[n//2] if n%2==1 else (s[n//2-1] + s[n//2]) / 2

def find_surname(img: Image.Image, full_text: str) -> str:
    try:
        data = pytesseract.image_to_data(img, output_type=Output.DICT, config='--psm 6')
        n = len(data.get('text', []))
        if n == 0:
            raise ValueError('no words')
        words = []
        for i in range(n):
            t = (data['text'][i] or '').strip()
            if not t:
                continue
            try:
                conf = float(str(data.get('conf', ['-1'])[i]))
            except:
                conf = -1.0
            if conf < 55:  # discard low confidence tokens
                continue
            w = {
                't': t,
                'top': int(data.get('top', [0])[i] or 0),
                'h': int(data.get('height', [0])[i] or 0),
                'line': (data.get('block_num', [0])[i],
                         data.get('par_num', [0])[i],
                         data.get('line_num', [0])[i]),
            }
            words.append(w)
        if not words:
            raise ValueError('no reliable words')

        # Estimate y-band of the ID line using tokens containing digits and 'MN'
        id_like = [w for w in words if (('MN' in w['t']) or re.search(r'\d', w['t'])) and re.search(r'[-–—/]', w['t'])]
        if id_like:
            id_band_top = _median([w['top'] for w in id_like])
        else:
            id_band_top = _median([w['top'] for w in words])

        # Prefer uppercase alphabetic tokens near the ID band, exclude blacklist and weird repeats
        height = img.height
        band_tol = max(160, int(0.08 * height))
        candidates = [
            w for w in words
            if re.fullmatch(r'[A-Za-z]+', w['t'])
            and (w['t'].isupper() or (len(w['t']) >= 3 and w['t'][0].isupper()))
            and abs(w['top'] - id_band_top) <= band_tol
            and w['t'].lower() not in BLACKLIST
            and not BLACKLIST_PAT.search(w['t'])
            and not TRIPLE_REPEAT.search(w['t'])
            and 3 <= len(w['t']) <= 14
        ]
        if candidates:
            # pick tallest near-band token as surname
            surname = max(candidates, key=lambda x: x['h'])['t']
            return surname[:1].upper() + surname[1:].lower()

        # Fallback: tallest alphabetic word excluding blacklist
        alpha = [
            w for w in words
            if re.fullmatch(r'[A-Za-z]+', w['t'])
            and w['t'].lower() not in BLACKLIST
            and not BLACKLIST_PAT.search(w['t'])
            and not TRIPLE_REPEAT.search(w['t'])
        ]
        if alpha:
            surname = max(alpha, key=lambda x: x['h'])['t']
            return surname[:1].upper() + surname[1:].lower()

    except Exception:
        pass

    # Text-only fallback
    tokens = [w for w in re.findall(r'[A-Za-z]{3,}', full_text)
              if w.lower() not in BLACKLIST and not BLACKLIST_PAT.search(w) and not TRIPLE_REPEAT.search(w)]
    return max(tokens, key=len) if tokens else ''

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"student_number":"", "surname":"", "analyzed": ""}))
        return
    path = sys.argv[1]
    try:
        img = preprocess(path)
        text = pytesseract.image_to_string(img) or ""
        sid = find_student_number(text)
        sname = find_surname(img, text)
        print(json.dumps({"student_number": sid.strip(), "surname": sname.strip(), "analyzed": text}))
    except Exception as e:
        print(json.dumps({"error": str(e), "student_number":"", "surname":"", "analyzed": ""}))

if __name__ == "__main__":
    main()