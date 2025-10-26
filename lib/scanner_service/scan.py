import sys, json, re
from PIL import Image, ImageOps, ImageFilter
try:
    import pytesseract
    from pytesseract import Output
except Exception as e:
    print(json.dumps({"error": f"pytesseract not available: {e}", "student_number":"", "surname":"", "analyzed":""}))
    sys.exit(1)

try:
    import cv2
    import numpy as np
except Exception:
    cv2 = None
    np = None

def preprocess(path: str) -> Image.Image:
    img = Image.open(path)
    # upscale small images a bit, cap size
    if img.width < 900:
        scale = min(1200 / max(1, img.width), 2.0)
        new_w = int(img.width * scale)
        new_h = int(img.height * scale)
        img = img.resize((new_w, new_h), Image.LANCZOS)
    img = Image.open(path).convert('L')     # grayscale
    img = ImageOps.autocontrast(img)        # improve contrast
    img = img.filter(ImageFilter.SHARPEN)
    if cv2 and np:
        arr = np.array(img)
        # Otsu binarization
        _, bin_img = cv2.threshold(arr, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        img = Image.fromarray(bin_img)
    return img

def find_student_number(text: str) -> str:
    # Prefer exact pattern: 4 digits - 5+ digits - MN - 0
    patterns = [
        r'\b\d{4}-\d{5,}-MN-0\b',
        r'\b\d{4}-\d{5,}-MN-\d\b',
        r'\b\d{4}[-\s]\d{5,}[-\s]MN[-\s]\d\b',
    ]
    for pat in patterns:
        m = re.search(pat, text)
        if m:
            return m.group(0)
    # Fallback: generic ID containing MN with digit groups around it
    m2 = re.search(r'\b\d{3,}[-/ ]\d{4,}[-/ ]MN[-/ ]\d\b', text)
    return m2.group(0) if m2 else ''

def find_surname(img: Image.Image, text: str) -> str:
    # Use layout pick line with largest median word height, then take last alphe token there
    try:
        data = pytesseract.image_to_data(img, output_type=Output.DICT, config='--psm 6')
        n = len(data.get('text', []))
        
        if n == 0:
            raise ValueError('no data')

        rows = []
        for i in range(n):
            t = (data['text'][i] or '').strip()
            conf = int(data.get('conf', ['-1'])[i]) if str(data.get('conf', ['-1'])[i]).isdigit() else -1
            if not t or conf < 0:
                continue
            line_key = (data.get('block_num', [0])[i],
                        data.get('par_num', [0])[i],
                        data.get('line_num', [0])[i])
            rows.append({
                'line_key': line_key,
                'text': t,
                'height': int(data.get('height', [0])[i] or 0),
                'conf': conf
            })

        if not rows:
            raise ValueError('no words')

        # group by line
        from collections import defaultdict
        lines = defaultdict(list)

        for r in rows:
            lines[r['line_key']].append(r)

        # score lines by median height
        def median(nums):
            s = sorted(nums)
            if not s: return 0
            m = len(s)/2
            return (s[m] if len(s)%2==1 else (s[m-1]+s[m])/2)
        
        best_line = max(lines.values(), key=lambda ws: median([w['height'] for w in ws]))
        # collect alpha tokens
        tokens = [w['text'] for w in best_line if re.fullmatch(r'[A-Za-z]+', w['text'])]

        if tokens:
            return tokens[-1]

        # fallback: tallest single alpha word
        alpha_rows = [r for r in rows if re.fullmatch(r'[A-Za-z]+', r['text'])]
        
        if alpha_rows:
            tallest = max(alpha_rows, key=lambda r: r['height'])
            return tallest['text']
    except Exception:
        pass

    words = re.findall(r'[A-Za-z]{3,}', text)
    return max(words, key=len) if words else '' 

def parse(text: str, img: Image.Image) -> tuple[str,str]:
    sid = find_student_number(text)
    surname = find_surname(img, text)
    return sid.strip(), surname.strip()
    

def main():
    if len(sys.argv) < 2:
        print(json.dumps({"student_number":"", "surname":"", "analyzed": ""}))
        return
    path = sys.argv[1]

    try:
        img = preprocess(path)
        text = pytesseract.image_to_string(img) or ""
        sid, sname = parse(text, img)
        print(json.dumps({"student_number": sid, "surname": sname, "analyzed": text}))
    except Exception as e:
        print(json.dumps({"error": str(e), "student_number":"", "surname":"", "analyzed": ""}))

if __name__ == "__main__":
    main()