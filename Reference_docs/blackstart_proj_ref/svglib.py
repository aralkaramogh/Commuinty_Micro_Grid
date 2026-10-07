"""Tiny SVG helper library for the black-start project diagrams."""
from xml.sax.saxutils import escape

FONT = "Segoe UI, Helvetica, Arial, sans-serif"
C = dict(
    power="#c0392b", sense="#1f6fb2", gate="#1e8449", data="#6c3483", drv="#d35400",
    ink="#1f2933", sub="#52606d", line="#9aa5b1", gnd="#52606d",
    band_a="#eef4fb", band_a_s="#c9d9ee", band_b="#eef8f1", band_b_s="#c3e3cd",
    band_c="#fdf2ee", band_c_s="#f0cfc4", box="#ffffff", panel="#f7f9fb", panel_s="#d9e2ec",
    note="#fff8e1", note_s="#f2d58a",
)


class SVG:
    def __init__(self, w, h, title):
        self.w, self.h = w, h
        self.parts = []
        self.title = title

    def add(self, s):
        self.parts.append(s)

    # ---------- primitives
    def rect(self, x, y, w, h, fill="#fff", stroke=None, sw=1.2, rx=8, dash=None, opacity=None):
        st = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ''
        da = f' stroke-dasharray="{dash}"' if dash else ''
        op = f' fill-opacity="{opacity}"' if opacity is not None else ''
        self.add(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" fill="{fill}"{op}{st}{da}/>')

    def text(self, x, y, s, size=13, color=None, weight="normal", anchor="start", italic=False):
        color = color or C["ink"]
        it = ' font-style="italic"' if italic else ''
        self.add(f'<text x="{x}" y="{y}" font-family="{FONT}" font-size="{size}" fill="{color}" '
                 f'font-weight="{weight}" text-anchor="{anchor}"{it}>{escape(s)}</text>')

    def lines(self, x, y, items, size=13, lh=None, color=None, anchor="start", weight="normal"):
        lh = lh or size * 1.35
        for i, s in enumerate(items):
            self.text(x, y + i * lh, s, size=size, color=color, anchor=anchor, weight=weight)

    def line(self, pts, color=None, sw=1.6, dash=None, arrow=False, arrow_start=False):
        color = color or C["line"]
        d = " ".join(f"{x},{y}" for x, y in pts)
        da = f' stroke-dasharray="{dash}"' if dash else ''
        me = f' marker-end="url(#arr_{color[1:]})"' if arrow else ''
        ms = f' marker-start="url(#arrs_{color[1:]})"' if arrow_start else ''
        self.add(f'<polyline points="{d}" fill="none" stroke="{color}" stroke-width="{sw}" '
                 f'stroke-linejoin="round" stroke-linecap="round"{da}{me}{ms}/>')

    def dot(self, x, y, color=None, r=3.5):
        self.add(f'<circle cx="{x}" cy="{y}" r="{r}" fill="{color or C["ink"]}"/>')

    def box(self, x, y, w, h, title, sub=(), stroke=None, fill=None, tsize=14, ssize=12, center=True, title_color=None):
        self.rect(x, y, w, h, fill=fill or C["box"], stroke=stroke or C["line"], sw=1.4)
        n = 1 + len(sub)
        lh_t, lh_s = tsize * 1.25, ssize * 1.3
        total = lh_t + lh_s * len(sub)
        y0 = y + h / 2 - total / 2 + tsize * 0.95
        cx = x + w / 2 if center else x + 10
        anc = "middle" if center else "start"
        self.text(cx, y0, title, size=tsize, weight="bold", anchor=anc, color=title_color)
        for i, s in enumerate(sub):
            self.text(cx, y0 + lh_t + i * lh_s - 2, s, size=ssize, color=C["sub"], anchor=anc)

    def tag(self, x, y, s, color, size=11.5, h=19):
        w = 8 + len(s) * size * 0.58
        self.rect(x, y, w, h, fill=color, rx=9)
        self.text(x + w / 2, y + h / 2 + size * 0.36, s, size=size, color="#fff", weight="bold", anchor="middle")
        return w

    def gnd(self, x, y, color=None):
        c = color or C["gnd"]
        self.line([(x, y - 8), (x, y)], color=c, sw=1.6)
        for i, half in enumerate((11, 7, 3)):
            yy = y + i * 4
            self.line([(x - half, yy), (x + half, yy)], color=c, sw=1.6)

    def resistor_v(self, x, y1, y2, label=None, color=None, label_left=True):
        c = color or C["ink"]
        mid = (y1 + y2) / 2
        self.line([(x, y1), (x, mid - 14)], color=c)
        self.rect(x - 6, mid - 14, 12, 28, fill="#fff", stroke=c, sw=1.5, rx=2)
        self.line([(x, mid + 14), (x, y2)], color=c)
        if label:
            if label_left:
                self.text(x - 11, mid + 4, label, size=12, anchor="end")
            else:
                self.text(x + 11, mid + 4, label, size=12)

    def resistor_h(self, x1, x2, y, label=None, color=None):
        c = color or C["ink"]
        mid = (x1 + x2) / 2
        self.line([(x1, y), (mid - 14, y)], color=c)
        self.rect(mid - 14, y - 6, 28, 12, fill="#fff", stroke=c, sw=1.5, rx=2)
        self.line([(mid + 14, y), (x2, y)], color=c)
        if label:
            self.text(mid, y - 11, label, size=12, anchor="middle")

    def diode_v(self, x, y1, y2, color=None, label=None):
        """Diode pointing DOWN (current flows y1 -> y2)."""
        c = color or C["ink"]
        mid = (y1 + y2) / 2
        self.line([(x, y1), (x, mid - 8)], color=c)
        self.add(f'<polygon points="{x-9},{mid-8} {x+9},{mid-8} {x},{mid+7}" fill="{c}"/>')
        self.line([(x - 9, mid + 8), (x + 9, mid + 8)], color=c, sw=2)
        self.line([(x, mid + 8), (x, y2)], color=c)
        if label:
            self.text(x + 14, mid + 4, label, size=12)

    def diode_h(self, x1, x2, y, color=None, label=None):
        """Diode pointing RIGHT."""
        c = color or C["ink"]
        mid = (x1 + x2) / 2
        self.line([(x1, y), (mid - 8, y)], color=c)
        self.add(f'<polygon points="{mid-8},{y-9} {mid-8},{y+9} {mid+7},{y}" fill="{c}"/>')
        self.line([(mid + 8, y - 9), (mid + 8, y + 9)], color=c, sw=2)
        self.line([(mid + 8, y), (x2, y)], color=c)
        if label:
            self.text(mid, y - 14, label, size=12, anchor="middle")

    def buffer(self, x, y, w=36, h=30, color=None):
        """Gate-driver triangle pointing right, left tip at x, centered on y."""
        c = color or C["gate"]
        self.add(f'<polygon points="{x},{y-h/2} {x},{y+h/2} {x+w},{y}" fill="#fff" stroke="{c}" stroke-width="1.8"/>')

    def mosfet(self, cx, cy, kind="N", color=None, scale=1.0, labels=True):
        """Schematic MOSFET. N: D on top, S at bottom. P: S on top, D at bottom.
        Returns dict of terminal coordinates: top, bottom, gate."""
        c = color or C["ink"]
        s = scale
        gx = cx - 40 * s
        plate = cx - 12 * s
        ch = cx - 5 * s
        lead = cx + 12 * s
        top = (lead, cy - 40 * s)
        bot = (lead, cy + 40 * s)
        # gate lead + plate
        self.line([(gx, cy), (plate, cy)], color=c, sw=1.8)
        self.line([(plate, cy - 18 * s), (plate, cy + 18 * s)], color=c, sw=2.2)
        # channel (3 segments)
        for a, b in ((-22, -10), (-6, 6), (10, 22)):
            self.line([(ch, cy + a * s), (ch, cy + b * s)], color=c, sw=2.4)
        # drain/source leads
        self.line([(ch, cy - 16 * s), (lead, cy - 16 * s), (lead, cy - 40 * s)], color=c, sw=1.8)
        self.line([(ch, cy + 16 * s), (lead, cy + 16 * s), (lead, cy + 40 * s)], color=c, sw=1.8)
        # body tied to source (N: source at bottom, P: source on top)
        if kind == "N":
            self.line([(ch, cy), (lead, cy), (lead, cy + 16 * s)], color=c, sw=1.8)
            self.add(f'<polygon points="{ch+1},{cy} {ch+11*s},{cy-5*s} {ch+11*s},{cy+5*s}" fill="{c}"/>')
        else:
            self.line([(ch, cy), (lead, cy), (lead, cy - 16 * s)], color=c, sw=1.8)
            self.add(f'<polygon points="{lead-1},{cy} {lead-11*s},{cy-5*s} {lead-11*s},{cy+5*s}" fill="{c}"/>')
        if labels:
            tl, bl = ("D", "S") if kind == "N" else ("S", "D")
            self.text(lead + 7, cy - 26 * s, tl, size=12, weight="bold", color=C["sub"])
            self.text(lead + 7, cy + 32 * s, bl, size=12, weight="bold", color=C["sub"])
            self.text(gx - 2, cy - 7, "G", size=12, weight="bold", color=C["sub"], anchor="end")
        return dict(top=top, bottom=bot, gate=(gx, cy))

    def cap_v(self, x, y1, y2, label=None, color=None):
        c = color or C["ink"]
        mid = (y1 + y2) / 2
        self.line([(x, y1), (x, mid - 4)], color=c)
        self.line([(x - 12, mid - 4), (x + 12, mid - 4)], color=c, sw=2.4)
        self.line([(x - 12, mid + 4), (x + 12, mid + 4)], color=c, sw=2.4)
        self.line([(x, mid + 4), (x, y2)], color=c)
        if label:
            self.text(x + 18, mid + 4, label, size=12)

    # ---------- output
    def render(self):
        cols = {C[k] for k in ("power", "sense", "gate", "data", "drv", "line", "ink", "gnd")}
        defs = []
        for col in cols:
            cid = col[1:]
            defs.append(f'<marker id="arr_{cid}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" '
                        f'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{col}"/></marker>')
            defs.append(f'<marker id="arrs_{cid}" viewBox="0 0 10 10" refX="1" refY="5" markerWidth="7" markerHeight="7" '
                        f'orient="auto-start-reverse"><path d="M0,0 L10,5 L0,10 z" fill="{col}"/></marker>')
        head = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{self.w}" height="{self.h}" '
                f'viewBox="0 0 {self.w} {self.h}" role="img" aria-label="{escape(self.title)}">'
                f'<title>{escape(self.title)}</title><defs>{"".join(defs)}</defs>'
                f'<rect width="{self.w}" height="{self.h}" fill="#ffffff"/>')
        return head + "".join(self.parts) + "</svg>"

    def save(self, path):
        with open(path, "w", encoding="utf-8") as f:
            f.write(self.render())
