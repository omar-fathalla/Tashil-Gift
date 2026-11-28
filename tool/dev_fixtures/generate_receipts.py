#!/usr/bin/env python3
"""Generates the SYNTHETIC receipt images used by tool/seed_dev.js (TAG-14).

Every image is drawn from scratch: fake chain names, fake branch codes, fake
barcodes (999...), no customer data. Never copy real receipts from the
production Storage bucket into this folder.

  python3 tool/dev_fixtures/generate_receipts.py   # needs Pillow with raqm
Font: any Arabic TTF; set RECEIPT_FONT=/path/to/NotoSansArabic.ttf.

Scenarios (expected result in docs/DEV_ENVIRONMENT.md):
  01 valid receipt, branch 101 of the campaign (target spend 249.50 >= 150)
  02 the same receipt photographed again (duplicate)
  03 receipt from branch 201, which is not in the campaign
  04 receipt below the campaign minimum spend
  05 blurry, unreadable receipt
  06 not a receipt at all
"""
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "receipts")
FONT = os.environ.get(
    "RECEIPT_FONT",
    "/usr/share/fonts/truetype/sand-box/google/Noto Sans Arabic/NotoSansArabic-VariableFont_wdth,wght.ttf",
)
W = 560

def font(size):
    return ImageFont.truetype(FONT, size)

def receipt(chain, branch, branch_code, number, date, lines, footer_note=""):
    h = 420 + 46 * len(lines)
    img = Image.new("RGB", (W, h), (252, 251, 247))
    d = ImageDraw.Draw(img)
    y = 20
    def rtl(text, size=24, x_right=W - 24, fill=(20, 20, 20)):
        f = font(size)
        width = d.textlength(text, font=f, direction="rtl", language="ar")
        d.text((x_right - width, y), text, font=f, fill=fill, direction="rtl", language="ar")
    def center(text, size=24, fill=(20, 20, 20)):
        f = font(size)
        width = d.textlength(text, font=f, direction="rtl", language="ar")
        d.text(((W - width) / 2, y), text, font=f, fill=fill, direction="rtl", language="ar")
    center("فاتورة تجريبية - بيئة التطوير فقط", 20, (190, 40, 20)); y += 34
    center("SAMPLE / DEV ONLY - NOT A REAL RECEIPT", 16, (190, 40, 20)); y += 34
    center(chain, 32); y += 50
    center(f"{branch} - كود الفرع {branch_code}", 22); y += 40
    rtl(f"رقم الفاتورة: {number}", 22); y += 34
    rtl(f"التاريخ: {date}", 22); y += 40
    d.line((24, y, W - 24, y), fill=(60, 60, 60), width=2); y += 14
    total = 0.0
    for name, barcode, qty, price in lines:
        rtl(name, 22)
        d.text((24, y + 2), f"{qty} x {price:.2f}", font=font(20), fill=(20, 20, 20))
        y += 26
        d.text((W - 24 - d.textlength(barcode, font=font(16)), y), barcode, font=font(16), fill=(90, 90, 90))
        y += 20
        total += qty * price
    d.line((24, y + 6, W - 24, y + 6), fill=(60, 60, 60), width=2); y += 22
    rtl(f"الإجمالي: {total:.2f} جنيه", 28); y += 50
    if footer_note:
        center(footer_note, 18, (90, 90, 90)); y += 30
    center("شكرا لزيارتكم - رقم ضريبي تجريبي 000-000-000", 16, (90, 90, 90))
    return img, total

CHOCO = [
    ("شوكولاتة تجربة بالبندق 100 جم", "9990000000011", 2, 45.00),
    ("بسكويت تجربة بالشوكولاتة", "9990000000028", 3, 22.50),
    ("أرز ماركة أخرى 1 كجم", "9990000009991", 1, 38.00),
]

def main():
    os.makedirs(OUT, exist_ok=True)
    valid, t = receipt("سلسلة تجربة أ", "فرع الاختبار الأول", "101", "101/1/7001/251126", "25/11/2026", CHOCO + [
        ("شوكولاتة تجربة كبيرة 200 جم", "9990000000035", 1, 92.00),
    ])
    valid.save(os.path.join(OUT, "01_valid_chain_a_branch_101.png"), optimize=True)
    valid.rotate(2.5, expand=True, fillcolor=(235, 235, 235)).save(os.path.join(OUT, "02_duplicate_of_01.png"), optimize=True)
    other, _ = receipt("سلسلة تجربة ب", "فرع خارج الحملة", "201", "201/2/7002/251126", "25/11/2026", CHOCO)
    other.save(os.path.join(OUT, "03_other_branch_chain_b_201.png"), optimize=True)
    low, _ = receipt("سلسلة تجربة أ", "فرع الاختبار الأول", "101", "101/1/7003/251126", "25/11/2026", [
        ("بسكويت تجربة بالشوكولاتة", "9990000000028", 1, 22.50),
        ("أرز ماركة أخرى 1 كجم", "9990000009991", 1, 38.00),
    ], "أقل من الحد الأدنى للحملة")
    low.save(os.path.join(OUT, "04_below_min_spend.png"), optimize=True)
    blurry, _ = receipt("سلسلة تجربة أ", "فرع الاختبار الثاني", "102", "102/1/7004/251126", "25/11/2026", CHOCO)
    blurry.filter(ImageFilter.GaussianBlur(5)).save(os.path.join(OUT, "05_blurry_unreadable.png"), optimize=True)
    img = Image.new("RGB", (560, 420), (120, 180, 220))
    d = ImageDraw.Draw(img)
    d.ellipse((380, 40, 480, 140), fill=(250, 210, 60))
    d.polygon([(0, 420), (180, 200), (360, 420)], fill=(70, 120, 70))
    d.polygon([(200, 420), (400, 160), (560, 420)], fill=(50, 100, 60))
    d.text((20, 20), "NOT A RECEIPT - DEV TEST IMAGE", font=font(20), fill=(255, 255, 255))
    img.save(os.path.join(OUT, "06_not_a_receipt.png"), optimize=True)
    print(f"wrote 6 images to {OUT} (valid receipt total {t:.2f})")

if __name__ == "__main__":
    main()
