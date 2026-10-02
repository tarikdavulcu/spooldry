#!/usr/bin/env python3
"""Generates localized App Store screenshots (8 concepts x 6 languages x iPhone 6.9" + iPad 13").

The phone/tablet UI is an HTML re-creation of the SwiftUI screens (same layout, colors and strings from the
app's String Catalog). Output: store/screenshots/<locale>/<device>-<n>-<slug>.png  (no alpha channel).
iPhone 6.9": 1320x2868   iPad 13": 2064x2752  (App Store Connect accepted sizes).
"""
import html
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "l10n"))
from aso_data import ASO, LOCALES  # noqa: E402
from strings_app import T  # noqa: E402
from strings_dynamic import D  # noqa: E402

LANG_INDEX = {"de": 0, "fr": 1, "es": 2, "ar": 3, "ja": 4}
FONTS = (ROOT / "design" / "fonts").resolve().as_uri()
OUT = ROOT / "store" / "screenshots"
WORK = ROOT / "design" / "screenshots-html"

DEVICES = {
    "iphone69": {"w": 440, "h": 956, "scale": 3, "frame": "phone"},
    "ipad13": {"w": 1032, "h": 1376, "scale": 2, "frame": "tablet"},
}

SLUGS = ["track", "temp-humidity", "profiles", "ble", "live-activity", "complete", "offline", "lifetime"]

DATES = {
    "en": "Thursday, October 1", "de": "Donnerstag, 1. Oktober", "fr": "jeudi 1 octobre",
    "es": "jueves, 1 de octubre", "ar": "الخميس، 1 أكتوبر", "ja": "10月1日 木曜日",
}
OFFLINE = {"en": "Offline", "de": "Offline", "fr": "Hors ligne", "es": "Sin conexión", "ar": "دون اتصال", "ja": "オフライン"}
END_TIME = {"en": "6:45 PM", "de": "18:45", "fr": "18:45", "es": "18:45", "ar": "6:45 م", "ja": "18:45"}


def tr(lang, key):
    if key in D:
        return D[key][0 if lang == "en" else LANG_INDEX[lang] + 1]
    if key in T:
        return key if lang == "en" else T[key][LANG_INDEX[lang]]
    raise KeyError(key)


def fmt(lang, key, *args):
    s = tr(lang, key)
    import re
    i = iter(args)
    def rep(m):
        if m.group(0) == "%%":
            return "%"
        idx = m.group(1)
        if idx:
            return str(args[int(idx[:-1]) - 1])
        return str(next(i))
    return re.sub(r"%(\d+\$)?(?:lld|@|%)", rep, s)


def num(lang, v, digits=1):
    s = f"{v:.{digits}f}"
    return s.replace(".", ",") if lang in ("de", "fr", "es") else s


def temp(lang, v, digits=1):
    return num(lang, v, digits) + "°C"


def pct(lang, v):
    return f"{int(round(v))} %" if lang in ("de", "fr", "es") else f"{int(round(v))}%"


E = html.escape

ICONS = {
    "thermo": '<svg viewBox="0 0 24 24"><path d="M10 4a2 2 0 1 1 4 0v9.3a4 4 0 1 1-4 0z" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="12" cy="17" r="2" fill="currentColor"/></svg>',
    "drop": '<svg viewBox="0 0 24 24"><path d="M12 3c3 4 6 7.3 6 11a6 6 0 0 1-12 0c0-3.7 3-7 6-11z" fill="none" stroke="currentColor" stroke-width="2"/></svg>',
    "scope": '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="8" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="12" cy="12" r="3" fill="currentColor"/></svg>',
    "spool": '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="12" cy="12" r="3.5" fill="none" stroke="currentColor" stroke-width="2"/></svg>',
    "check": '<svg viewBox="0 0 24 24"><path d="M5 12.5l4.5 4.5L19 7.5" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    "flame": '<svg viewBox="0 0 24 24"><path d="M12 3c1 4 5 5 5 10a5 5 0 0 1-10 0c0-3 2-4 2-7 2 1 3 3 3 5 1-2 0-5 0-8z" fill="currentColor"/></svg>',
    "cpu": '<svg viewBox="0 0 24 24"><rect x="6" y="6" width="12" height="12" rx="2" fill="none" stroke="currentColor" stroke-width="2"/><path d="M9 2v3M15 2v3M9 19v3M15 19v3M2 9h3M2 15h3M19 9h3M19 15h3" stroke="currentColor" stroke-width="2"/></svg>',
    "clock": '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 7v5l3 2" stroke="currentColor" stroke-width="2" fill="none" stroke-linecap="round"/></svg>',
    "list": '<svg viewBox="0 0 24 24"><path d="M8 6h12M8 12h12M8 18h12" stroke="currentColor" stroke-width="2" stroke-linecap="round"/><circle cx="4" cy="6" r="1.4" fill="currentColor"/><circle cx="4" cy="12" r="1.4" fill="currentColor"/><circle cx="4" cy="18" r="1.4" fill="currentColor"/></svg>',
    "gear": '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="3.2" fill="none" stroke="currentColor" stroke-width="2"/><path d="M12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
    "wave": '<svg viewBox="0 0 24 24"><path d="M3 9c3-3 6 3 9 0s6 3 9 0M3 15c3-3 6 3 9 0s6 3 9 0" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>',
    "bt": '<svg viewBox="0 0 24 24"><path d="M7 7l10 10-5 4V3l5 4L7 17" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round"/></svg>',
    "plane": '<svg viewBox="0 0 24 24"><path d="M21 15v-2l-8-5V3.5a1.5 1.5 0 0 0-3 0V8l-8 5v2l8-2.5V18l-2 1.5V21l3.5-1 3.5 1v-1.5L13 18v-5.5z" fill="currentColor"/></svg>',
    "seal": '<svg viewBox="0 0 24 24"><path d="M12 2l2.4 2 3.1-.3.9 3 2.7 1.6-1 2.9 1 2.9-2.7 1.6-.9 3-3.1-.3L12 22l-2.4-2-3.1.3-.9-3L2.9 15.7l1-2.9-1-2.9 2.7-1.6.9-3 3.1.3z" fill="currentColor"/><path d="M8 12.3l2.7 2.7L16 9.7" fill="none" stroke="#0b1418" stroke-width="2.2" stroke-linecap="round"/></svg>',
    "stop": '<svg viewBox="0 0 24 24"><rect x="6" y="6" width="12" height="12" rx="2" fill="currentColor"/></svg>',
    "inf": '<svg viewBox="0 0 24 24"><path d="M7 8.5c-2 0-3.5 1.5-3.5 3.5S5 15.5 7 15.5c3.5 0 6.5-7 10-7 2 0 3.5 1.5 3.5 3.5S19 15.5 17 15.5c-3.5 0-6.5-7-10-7z" fill="none" stroke="currentColor" stroke-width="2"/></svg>',
}


def icon(name, cls=""):
    return f'<span class="ic {cls}">{ICONS[name]}</span>'


CSS = """
@font-face { font-family: Inter; src: url('{FONTS}/inter-latin-wght-normal.woff2') format('woff2'); font-weight: 100 900; }
@font-face { font-family: NotoArabic; src: url('{FONTS}/noto-sans-arabic-arabic-400-normal.woff2') format('woff2'); font-weight: 400; }
@font-face { font-family: NotoArabic; src: url('{FONTS}/noto-sans-arabic-arabic-600-normal.woff2') format('woff2'); font-weight: 600; }
@font-face { font-family: NotoArabic; src: url('{FONTS}/noto-sans-arabic-arabic-700-normal.woff2') format('woff2'); font-weight: 700; }
@font-face { font-family: NotoArabic; src: url('{FONTS}/noto-sans-arabic-arabic-800-normal.woff2') format('woff2'); font-weight: 800; }
* { box-sizing: border-box; margin: 0; padding: 0; }
:root { --accent: #2EC4B6; --heat: #FF9933; --moist: #4FA8F2; --ok: #33C778; --bad: #F24D45; --card: rgba(255,255,255,0.07); --line: rgba(255,255,255,0.08); --sub: rgba(235,240,245,0.62); }
html, body { width: {W}px; height: {H}px; overflow: hidden; }
body { font-family: Inter, 'Noto Sans CJK JP', NotoArabic, sans-serif; color: #F2F5F7; -webkit-font-smoothing: antialiased;
  background: radial-gradient(120% 70% at 15% 0%, #165a60 0%, #0b2730 42%, #060c11 100%); }
body.ar { font-family: NotoArabic, Inter, sans-serif; }
body.ja { font-family: 'Noto Sans CJK JP', Inter, sans-serif; }
.head { position: absolute; left: 0; right: 0; top: {HEAD_TOP}px; padding: 0 {PADX}px; text-align: center; }
.head h1 { font-size: {H1}px; line-height: 1.08; font-weight: 800; letter-spacing: -0.02em; }
.ja .head h1, .ar .head h1 { letter-spacing: 0; line-height: 1.25; }
.head p { margin-top: 12px; font-size: {HP}px; color: var(--sub); line-height: 1.35; font-weight: 500; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
.head h1.long { font-size: calc({H1}px * 0.84); }
.head .tag { display: inline-flex; align-items: center; gap: 6px; padding: 5px 12px; border-radius: 99px; background: rgba(46,196,182,.16); color: var(--accent); font-size: {TAG}px; font-weight: 700; margin-bottom: 14px; }
.device { position: absolute; left: 50%; transform: translateX(-50%); top: {DEV_TOP}px; width: {DEV_W}px; height: {DEV_H}px; border-radius: {DEV_R}px; background: #0a0d10; padding: {BEZEL}px; box-shadow: 0 30px 80px rgba(0,0,0,.55), 0 0 0 2px #2a3136, inset 0 0 0 2px #1a1f23; }
.screen { position: relative; width: 100%; height: 100%; border-radius: {SCR_R}px; overflow: hidden; background: radial-gradient(100% 60% at 0% 0%, rgba(46,196,182,.20), transparent 60%), #121417; }
.status { height: 44px; display: flex; justify-content: space-between; align-items: center; padding: 0 26px; font-size: 15px; font-weight: 600; }
.island { position: absolute; top: 10px; left: 50%; transform: translateX(-50%); width: 112px; height: 32px; background: #000; border-radius: 20px; z-index: 5; }
.app { padding: 4px 16px 0; }
.title { font-size: 31px; font-weight: 800; margin: 6px 0 12px; }
.row { display: flex; align-items: center; gap: 10px; }
.between { justify-content: space-between; }
.card { background: var(--card); border: 1px solid var(--line); border-radius: 18px; padding: 14px; }
.badge { display: inline-flex; align-items: center; gap: 6px; padding: 6px 11px; border-radius: 99px; font-size: 13px; font-weight: 700; }
.ic { display: inline-flex; width: 1em; height: 1em; } .ic svg { width: 100%; height: 100%; }
.hero { border-radius: 26px; padding: 18px; background: linear-gradient(135deg, #17545b, #0f1a29); display: flex; gap: 16px; align-items: center; }
.ring { position: relative; width: 132px; height: 132px; flex: none; }
.ring > svg { position: absolute; inset: 0; transform: rotate(-90deg); }
[dir=rtl] .ring > svg { transform: rotate(-90deg) scaleY(-1); }
.ring .c { position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; text-align: center; }
.big { font-size: 23px; font-weight: 800; font-variant-numeric: tabular-nums; }
.grid { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-top: 12px; }
.tile .lbl { font-size: 12.5px; font-weight: 600; color: var(--sub); display: flex; align-items: center; gap: 5px; }
.tile .val { font-size: 27px; font-weight: 800; margin-top: 4px; font-variant-numeric: tabular-nums; white-space: nowrap; }
.tile .foot { font-size: 11.5px; color: var(--sub); margin-top: 2px; }
.btn { margin-top: 12px; height: 50px; border-radius: 15px; display: flex; align-items: center; justify-content: center; gap: 8px; font-weight: 700; font-size: 17px; color: #000; background: var(--accent); }
.btn.red { background: var(--bad); }
.note { text-align: center; font-size: 12px; color: var(--sub); margin-top: 7px; }
.tabbar { position: absolute; left: 0; right: 0; bottom: 0; height: 82px; background: rgba(20,22,25,.92); border-top: 1px solid var(--line); display: flex; justify-content: space-around; padding-top: 9px; }
.tab { display: flex; flex-direction: column; align-items: center; gap: 3px; font-size: 10.5px; color: rgba(235,240,245,.45); font-weight: 600; width: 20%; text-align: center; }
.tab .ic { font-size: 24px; } .tab.on { color: var(--accent); }
.list { border-radius: 14px; background: var(--card); border: 1px solid var(--line); overflow: hidden; }
.li { display: flex; align-items: center; gap: 12px; padding: 11px 14px; border-bottom: 1px solid var(--line); }
.li:last-child { border-bottom: 0; }
.mat { width: 40px; height: 40px; border-radius: 50%; background: rgba(46,196,182,.15); display: flex; align-items: center; justify-content: center; font-size: 10.5px; font-weight: 800; flex: none; }
.li .t { font-weight: 700; font-size: 16px; } .li .s { font-size: 13px; color: var(--sub); font-variant-numeric: tabular-nums; }
.sect { font-size: 12.5px; font-weight: 600; color: var(--sub); text-transform: uppercase; margin: 14px 4px 6px; letter-spacing: .02em; }
.ar .sect, .ja .sect { text-transform: none; }
.step { display: flex; align-items: center; gap: 12px; padding: 11px 14px; border-bottom: 1px solid var(--line); font-size: 15px; }
.dot { width: 28px; height: 28px; border-radius: 50%; background: rgba(51,199,120,.2); color: var(--ok); display: flex; align-items: center; justify-content: center; font-size: 16px; flex: none; }
.kv { display: flex; justify-content: space-between; padding: 11px 14px; border-bottom: 1px solid var(--line); font-size: 15px; }
.kv span:last-child { color: var(--sub); font-variant-numeric: tabular-nums; }
.lock { position: absolute; inset: 0; background: radial-gradient(90% 60% at 50% 20%, #1d5e66, #0b1d26 60%, #05090c); }
.lock .date { text-align: center; margin-top: 70px; font-size: 18px; font-weight: 600; color: rgba(255,255,255,.85); }
.lock .time { text-align: center; font-size: 92px; font-weight: 700; letter-spacing: -2px; line-height: 1; margin-top: 4px; }
.la { margin: 0 12px; border-radius: 24px; background: rgba(18,22,26,.88); padding: 15px; backdrop-filter: blur(20px); }
.di { position: absolute; top: 9px; left: 50%; transform: translateX(-50%); height: 36px; padding: 0 16px; background: #000; border-radius: 22px; display: flex; align-items: center; gap: 46px; font-size: 13.5px; font-weight: 700; z-index: 6; white-space: nowrap; }
.metric { text-align: center; } .metric .v { font-size: 15px; font-weight: 700; font-variant-numeric: tabular-nums; white-space: nowrap; } .metric .l { font-size: 11px; color: var(--sub); }
.bar { height: 6px; border-radius: 6px; background: rgba(255,255,255,.12); overflow: hidden; margin-top: 10px; } .bar i { display: block; height: 100%; background: var(--accent); }
[dir=rtl] .bar i { margin-left: auto; }
.banner { position: absolute; top: 52px; left: 10px; right: 10px; z-index: 7; border-radius: 22px; padding: 12px 14px; background: rgba(42,46,52,.96); box-shadow: 0 12px 30px rgba(0,0,0,.5); display: flex; gap: 11px; }
.banner img { width: 38px; height: 38px; border-radius: 9px; flex: none; }
.banner .t { font-weight: 700; font-size: 15px; } .banner .s { font-size: 13.5px; color: rgba(255,255,255,.8); line-height: 1.3; }
.pill { display: inline-flex; gap: 6px; align-items: center; padding: 6px 12px; border-radius: 99px; background: rgba(255,255,255,.08); font-size: 13px; font-weight: 600; }
.paywall { text-align: center; padding: 30px 22px; }
.paywall img { width: 104px; height: 104px; border-radius: 24px; box-shadow: 0 14px 40px rgba(0,0,0,.5); }
.paywall h2 { font-size: 29px; font-weight: 800; margin-top: 14px; }
.price { font-size: 46px; font-weight: 900; color: var(--accent); margin-top: 4px; }
.otp { font-weight: 800; letter-spacing: .12em; font-size: 14px; margin-top: 2px; }
.ar .otp, .ja .otp { letter-spacing: 0; }
.ben { text-align: start; margin-top: 18px; }
.ben .li { padding: 10px 14px; font-size: 15px; font-weight: 600; } .ben .ic { color: var(--accent); font-size: 20px; }
/* tablet layout */
.tablet .screen { zoom: 1.45; }
.tablet .app { padding: 10px 22px 0; }
.tablet .title { font-size: 40px; }
.tablet .grid { grid-template-columns: repeat(4, 1fr); }
.tablet .cols { display: grid; grid-template-columns: 1.15fr 1fr; gap: 16px; }
"""


def tabbar(lang, active):
    items = [("thermo", "Dryer"), ("list", "Profiles"), ("clock", "History"), ("cpu", "Device"), ("gear", "Settings")]
    return '<div class="tabbar">' + "".join(
        f'<div class="tab {"on" if i == active else ""}">{icon(ic)}<span>{E(tr(lang, k))}</span></div>' for i, (ic, k) in enumerate(items)) + "</div>"


def status_bar(time="9:41"):
    return f'<div class="status"><span>{time}</span><span style="display:flex;gap:6px;align-items:center">●●●● ▮</span></div><div class="island"></div>'


def ring(progress, color, inner):
    r = 56
    c = 2 * 3.14159 * r
    arc = "" if progress is None else f'<circle cx="66" cy="66" r="{r}" fill="none" stroke="{color}" stroke-width="13" stroke-linecap="round" stroke-dasharray="{c*progress:.1f} {c:.1f}"/>'
    return f'''<div class="ring"><svg viewBox="0 0 132 132"><circle cx="66" cy="66" r="{r}" fill="none" stroke="{color}" stroke-opacity=".18" stroke-width="13"/>{arc}</svg><div class="c">{inner}</div></div>'''


def tiles(lang, t="67.2", h=18.4, target=70, fil="PA-CF"):
    return f'''<div class="grid">
<div class="card tile"><div class="lbl">{icon("thermo")}{E(tr(lang,"Temperature"))}</div><div class="val" style="color:var(--heat)">{temp(lang,float(t))}</div></div>
<div class="card tile"><div class="lbl">{icon("drop")}{E(tr(lang,"Humidity"))}</div><div class="val" style="color:var(--moist)">{pct(lang,h)}</div><div class="foot">{E(tr(lang,"Relative humidity"))}</div></div>
<div class="card tile"><div class="lbl">{icon("scope")}{E(tr(lang,"Target"))}</div><div class="val">{temp(lang,target,0)}</div></div>
<div class="card tile"><div class="lbl">{icon("spool")}{E(tr(lang,"Filament"))}</div><div class="val">{fil}</div></div></div>'''


def dashboard(lang, state="drying"):
    if state == "drying":
        color, prog = "#FABF40", 0.66
        inner = f'<div style="font-size:20px;color:{color}">{icon("drop")}</div><div class="big">2:41:00</div>'
        st_key, detail = "state.drying", fmt(lang, "Ends at %@", END_TIME[lang])
        badge_bg, badge_c = "rgba(250,191,64,.18)", color
    else:
        color, prog = "#33C778", 1.0
        inner = f'<div style="font-size:26px;color:{color}">{icon("seal")}</div><div style="font-weight:700;font-size:12px;max-width:96px;overflow-wrap:anywhere">{E(tr(lang,"state.completed"))}</div>'
        st_key, detail = "state.completed", tr(lang, "Your filament is dry. Store it sealed with desiccant.")
        badge_bg, badge_c = "rgba(51,199,120,.18)", color
    hum = 18.4 if state == "drying" else 11.6
    tc = "67.2" if state == "drying" else "44.1"
    btn = (f'<div class="btn red">{icon("stop")}{E(tr(lang,"Stop Drying"))}</div>' if state == "drying"
           else f'<div class="btn">▶ {E(tr(lang,"Start Drying"))}</div>')
    return f'''<div class="app"><div class="title">SpoolDry</div>
<div class="row between"><div><div style="font-weight:700;font-size:19px">SpoolDry #1</div><div style="font-size:12.5px;color:var(--sub)">{E(fmt(lang,"Firmware %@","1.0.0"))}</div></div>
<span class="badge" style="background:{badge_bg};color:{badge_c}">{icon("drop" if state=="drying" else "seal")}{E(tr(lang,st_key))}</span></div>
<div class="hero" style="margin-top:12px">{ring(prog, color, inner)}<div><div style="font-size:12px;font-weight:600;opacity:.7">{E(tr(lang,"Drying status"))}</div>
<div style="font-size:22px;font-weight:800;margin:4px 0;overflow-wrap:anywhere;hyphens:auto">{E(tr(lang,st_key))}</div><div style="font-size:13px;opacity:.82;line-height:1.35">{E(detail)}</div></div></div>
{tiles(lang, tc, hum)}{btn}</div>'''


def chart_svg(w=340, h=170):
    import math
    pts_t, pts_h = [], []
    for i in range(61):
        x = i / 60
        tt = 23 + 47 * (1 - math.exp(-x * 6)) + (0.6 * math.sin(i) if x > .4 else 0)
        hh = 46 * math.exp(-x * 2.6) + 10
        pts_t.append((x * w, h - (tt - 15) / 65 * h))
        pts_h.append((x * w, h - hh / 60 * h))
    pt = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts_t)
    ph = " ".join(f"{x:.1f},{y:.1f}" for x, y in pts_h)
    grid = "".join(f'<line x1="0" x2="{w}" y1="{y}" y2="{y}" stroke="rgba(255,255,255,.08)"/>' for y in range(0, h + 1, h // 4))
    return f'''<svg viewBox="0 0 {w} {h}" width="100%" height="{h}">{grid}<polyline points="{pt}" fill="none" stroke="#FF9933" stroke-width="3"/>
<polyline points="{ph}" fill="none" stroke="#4FA8F2" stroke-width="3" stroke-dasharray="7 5"/></svg>'''


def screen_temp_humidity(lang):
    return f'''<div class="app"><div class="title">SpoolDry</div>
<div class="card"><div style="font-weight:700;font-size:17px;margin-bottom:8px">{E(tr(lang,"Last 3 hours"))}</div>{chart_svg()}
<div class="row" style="gap:16px;font-size:12px;margin-top:8px"><span style="color:var(--heat)">━ {E(fmt(lang,"Temperature (%@)","°C"))}</span><span style="color:var(--moist)">╍ {E(tr(lang,"Humidity (%%)").replace("%%","%"))}</span></div></div>
{tiles(lang)}<div class="card" style="margin-top:12px"><div class="row between"><span style="font-weight:600">{E(tr(lang,"Humidity target"))}</span><span style="color:var(--ok);font-weight:700">{E(fmt(lang,"< %lld%% RH",20))} ✓</span></div></div></div>'''


def screen_profiles(lang):
    rows = [("PLA", "PLA", 50, 6, False), ("PETG", "PETG", 65, 6, False), ("ABS", "ABS", 70, 6, False), ("ASA", "ASA", 70, 6, False),
            ("TPU", "TPU", 60, 6, False), ("PA", "PA (Nylon)", 70, 12, False), ("PC", "PC", 70, 8, False), ("PA-C", "PA-CF", 70, 12, False),
            ("PA-G", "PA-GF", 70, 12, False), ("PEEK", "PEEK", 70, 6, True), ("PEI", "PEI / ULTEM", 70, 6, True)]
    h = {"en": "h", "de": "Std.", "fr": "h", "es": "h", "ar": "ساعة", "ja": "時間"}[lang]
    lis = "".join(f'''<div class="li"><div class="mat">{a}</div><div style="flex:1"><div class="t">{n}</div><div class="s">{temp(lang,t,0)} · {hrs} {h}</div></div>{'<span style="color:#FFA040;font-size:20px">'+ICONS["flame"]+'</span>' if hot else '<span style="color:var(--sub)">›</span>'}</div>'''
                  for a, n, t, hrs, hot in rows)
    return f'''<div class="app"><div class="title">{E(tr(lang,"Filament Profiles"))}</div>
<div style="font-size:12.5px;color:var(--sub);line-height:1.35;margin-bottom:6px">{E(tr(lang,"Typical starting guidance, not a manufacturer requirement. Always check your filament's data sheet."))}</div>
<div class="sect">{E(tr(lang,"Engineering polymers"))}</div><div class="list">{lis}</div></div>'''


def screen_ble(lang):
    steps = ["Switch on your SpoolDry dryer", "Bluetooth is on", "Searching for dryers nearby", "Connect and read device information"]
    st = "".join(f'<div class="step"><div class="dot">{icon("check")}</div>{E(tr(lang,s))}</div>' for s in steps)
    kv = [("Name", "SpoolDry-A1B2"), ("Firmware", "1.0.0"), ("BLE protocol", "v1"), ("Maximum temperature", "70 °C")]
    kvs = "".join(f'<div class="kv"><span>{E(tr(lang,k))}</span><span>{v}</span></div>' for k, v in kv)
    return f'''<div class="app"><div style="text-align:center;font-weight:700;font-size:17px;margin:8px 0 14px">{E(tr(lang,"Set Up Dryer"))}</div>
<div class="list">{st}</div><div class="sect">{E(tr(lang,"Connected"))}</div><div class="list">{kvs}</div>
<div class="btn">{icon("bt")}{E(tr(lang,"Save and Open Dashboard"))}</div>
<div class="card" style="margin-top:14px;display:flex;gap:12px;align-items:center"><span style="font-size:30px;color:var(--accent)">{ICONS["cpu"]}</span>
<div style="font-size:13px;color:var(--sub);line-height:1.35">ESP32-C6 · SHT40 · PTC 24 V · BLE 5</div></div></div>'''


def screen_live_activity(lang):
    return f'''<div class="lock"><div class="di"><span>PA-CF</span><span style="color:#FABF40">2:41:00</span></div>
<div class="date">{E(DATES[lang])}</div><div class="time">9:41</div>
<div class="la" style="margin-top:250px"><div class="row between"><div><div style="font-weight:800;font-size:17px">PA-CF</div><div style="font-size:12px;color:var(--sub)">SpoolDry #1</div></div>
<span class="badge" style="color:#FABF40;background:rgba(250,191,64,.16)">{icon("drop")}{E(tr(lang,"state.drying"))}</span></div>
<div class="row between" style="margin-top:10px;align-items:flex-end"><div><div style="font-size:34px;font-weight:800;font-variant-numeric:tabular-nums">2:41:00</div><div style="font-size:11px;color:var(--sub)">{E(tr(lang,"Remaining"))}</div></div>
<div class="row" style="gap:14px"><div class="metric"><div class="v">{temp(lang,70,0)}</div><div class="l">{E(tr(lang,"Target"))}</div></div>
<div class="metric"><div class="v">{temp(lang,67.2)}</div><div class="l">{E(tr(lang,"Current"))}</div></div><div class="metric"><div class="v">{pct(lang,18)}</div><div class="l">{E(tr(lang,"Humidity"))}</div></div></div></div>
<div class="bar"><i style="width:66%"></i></div></div></div>'''


def screen_complete(lang, icon_uri):
    banner = f'''<div class="banner"><img src="{icon_uri}"><div><div class="t">{E(tr(lang,"Drying complete"))}</div><div class="s">{E(fmt(lang,"%@ is dry. %@ is cooling down or finished.","PA-CF","SpoolDry #1"))}</div></div></div>'''
    return banner + dashboard(lang, "completed")


def screen_offline(lang):
    rows = [("PA-CF", "outcome.completed", "#33C778", "38 % → 11 %"), ("PETG", "outcome.completed", "#33C778", "41 % → 17 %"),
            ("PC", "outcome.stopped", "rgba(235,240,245,.6)", "36 % → 22 %"), ("TPU", "outcome.completed", "#33C778", "44 % → 14 %")]
    if lang not in ("de", "fr", "es"):
        rows = [(a, b, c, d.replace(" %", "%")) for a, b, c, d in rows]
    lis = "".join(f'<div class="li"><div style="flex:1"><div class="t">{n}</div><div class="s">{h}</div></div><span style="color:{c};font-weight:700;font-size:13px">{E(tr(lang,o))}</span></div>' for n, o, c, h in rows)
    stats = f'''<div class="grid"><div class="card tile"><div class="lbl">{E(tr(lang,"Drying sessions"))}</div><div class="val">27</div></div>
<div class="card tile"><div class="lbl">{E(tr(lang,"Drying hours"))}</div><div class="val">{num(lang,184.5)}</div></div></div>'''
    return f'''<div class="app"><div class="title">{E(tr(lang,"History"))}</div>
<div class="row" style="gap:8px;flex-wrap:wrap;margin-bottom:10px"><span class="pill">{icon("plane")} {E(OFFLINE[lang])}</span><span class="pill">{icon("bt")} Bluetooth LE</span></div>
<div class="list">{lis}</div>{stats}
<div class="card" style="margin-top:12px;font-size:13px;color:var(--sub);line-height:1.4">{E(tr(lang,"All data stays on this iPhone: dryers, drying history, profiles and settings. No account, no cloud, no tracking. Session summaries are kept; detailed chart samples are removed after the selected period."))}</div></div>'''


def screen_paywall(lang, icon_uri):
    bens = ["Unlimited drying sessions", "Live Activity & Dynamic Island on every bake", "Custom filament profiles", "Full history & statistics", "Multiple dryers", "All future improvements"]
    ics = ["inf", "wave", "list", "clock", "cpu", "seal"]
    lis = "".join(f'<div class="li">{icon(i)}<span>{E(tr(lang,b))}</span></div>' for b, i in zip(bens, ics))
    price = '<div class="price">$19.99</div>' if lang == "en" else ""
    return f'''<div class="paywall"><img src="{icon_uri}"><h2>{E(tr(lang,"SpoolDry Lifetime"))}</h2>{price}
<div class="otp">{E(tr(lang,"ONE-TIME PURCHASE"))}</div><div style="color:var(--sub);margin-top:4px">{E(tr(lang,"No subscription."))}</div>
<div class="list ben">{lis}</div><div class="btn" style="margin-top:18px">{E(tr(lang,"Unlock Lifetime"))}</div>
<div style="margin-top:10px;font-size:14px;color:var(--accent)">{E(tr(lang,"Restore Purchases"))}</div></div>'''


def page(lang, device, idx, icon_uri):
    d = DEVICES[device]
    w, h = d["w"], d["h"]
    tablet = d["frame"] == "tablet"
    if tablet:
        geo = dict(HEAD_TOP=64, PADX=80, H1=58, HP=23, TAG=17, DEV_TOP=330, DEV_W=860, DEV_H=1180, DEV_R=40, BEZEL=16, SCR_R=26)
    else:
        geo = dict(HEAD_TOP=54, PADX=24, H1=40, HP=16, TAG=13, DEV_TOP=270, DEV_W=372, DEV_H=800, DEV_R=56, BEZEL=11, SCR_R=46)
    css = CSS.replace("{FONTS}", FONTS).replace("{W}", str(w)).replace("{H}", str(h))
    for k, v in geo.items():
        css = css.replace("{" + k + "}", str(v))
    headline = ASO[lang]["headlines"][idx]
    sub_keys = ["Live chamber temperature and relative humidity, with a full history of every bake.",
                "Live chamber temperature and relative humidity, with a full history of every bake.",
                "Values are typical starting guidance compiled from manufacturer recommendations, not universal requirements. Your filament's data sheet always wins.",
                "Your iPhone talks directly to the dryer over Bluetooth. No account, no cloud, works offline.",
                "Live Activities and the Dynamic Island show the real dryer state and remaining time.",
                "Your filament is dry. Store it sealed with desiccant.",
                "Your iPhone talks directly to the dryer over Bluetooth. No account, no cloud, works offline.",
                "Payment is charged to your Apple Account. One purchase unlocks SpoolDry on this Apple Account; there are no recurring charges."]
    sub = tr(lang, sub_keys[idx])
    if idx == 2:
        sub = tr(lang, "SpoolDry tracks drying sessions for PLA through PA-CF, with typical guidance for engineering polymers.")
    if idx == 7:
        sub = tr(lang, "No subscription.") + " " + fmt(lang, "You've used %lld of %lld free drying sessions.", 3, 3).split(".")[0].strip()
        sub = tr(lang, "No subscription.")
    body = [dashboard(lang), screen_temp_humidity(lang), screen_profiles(lang), screen_ble(lang),
            screen_live_activity(lang), screen_complete(lang, icon_uri), screen_offline(lang), screen_paywall(lang, icon_uri)][idx]
    tabs = {0: 0, 1: 0, 2: 1, 5: 0, 6: 2}
    bar = tabbar(lang, tabs[idx]) if idx in tabs else ""
    top = "" if idx == 4 else status_bar()
    rtl = ' dir="rtl"' if lang == "ar" else ""
    cls = f'{lang} {"tablet" if tablet else "phone"}'
    return f'''<!doctype html><html lang="{lang}"{rtl}><head><meta charset="utf-8"><style>{css}</style></head>
<body class="{cls}"><div class="head"><div class="tag">SpoolDry</div><h1 class="{"long" if len(headline) + sum(1 for ch in headline if ord(ch) > 0x2E80) > 24 else ""}">{E(headline)}</h1><p>{E(sub)}</p></div>
<div class="device"><div class="screen">{top}{body}{bar}</div></div></body></html>'''


def main():
    from render import render_many
    icon_uri = (ROOT / "design" / "icon" / "sizes" / "icon-180.png").resolve().as_uri()
    jobs = []
    for lang in ASO:
        for device, d in DEVICES.items():
            for idx, slug in enumerate(SLUGS):
                html_path = WORK / lang / f"{device}-{idx+1}-{slug}.html"
                html_path.parent.mkdir(parents=True, exist_ok=True)
                html_path.write_text(page(lang, device, idx, icon_uri))
                out = OUT / LOCALES[lang] / f"{device}-{idx+1}-{slug}.png"
                jobs.append((html_path, out, d["w"], d["h"], d["scale"]))
    only = sys.argv[1] if len(sys.argv) > 1 else None
    if only:
        jobs = [j for j in jobs if only in str(j[1])]
    by_scale = {}
    for j in jobs:
        by_scale.setdefault(j[4], []).append(j[:4])
    for scale, js in by_scale.items():
        render_many(js, scale)
    # Flatten to RGB (App Store rejects alpha) and verify size.
    from PIL import Image
    for _, out, w, h, scale in jobs:
        im = Image.open(out).convert("RGB")
        assert im.size == (w * scale, h * scale), (out, im.size)
        im.save(out, optimize=True)
    print(f"rendered {len(jobs)} screenshots")


if __name__ == "__main__":
    main()
