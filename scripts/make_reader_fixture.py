"""Make a two-page synthetic PDF for local reader testing."""
import sys
from pathlib import Path


def contents(label):
    data = f"BT /F1 28 Tf 64 730 Td ({label}) Tj ET\n".encode("ascii")
    return f"<< /Length {len(data)} >>\nstream\n".encode() + data + b"endstream"


def main():
    output = Path(sys.argv[1] if len(sys.argv) > 1 else "BoiPath_Reader_Test.pdf")
    pages = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
        *[f"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F1 5 0 R >> >> /Contents {i} 0 R >>".encode()
          for i in (6, 7)],
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        contents("BoiPath reader test: page one"),
        contents("BoiPath reader test: page two"),
    ]
    pdf = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for number, body in enumerate(pages, 1):
        offsets.append(len(pdf))
        pdf.extend(f"{number} 0 obj\n".encode() + body + b"\nendobj\n")
    xref = len(pdf)
    pdf.extend(f"xref\n0 {len(offsets)}\n0000000000 65535 f \n".encode())
    for offset in offsets[1:]:
        pdf.extend(f"{offset:010d} 00000 n \n".encode())
    pdf.extend(f"trailer\n<< /Root 1 0 R /Size {len(offsets)} >>\nstartxref\n{xref}\n%%EOF\n".encode())
    output.write_bytes(pdf)
    print(output.resolve())


if __name__ == "__main__":
    main()
