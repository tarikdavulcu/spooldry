#!/usr/bin/env python3
"""Static site generator for the SpoolDry website (HTML5 + Bootstrap 5 + vanilla JS).

  python3 website/src/build.py            -> writes website/dist/
Pages: / (English, x-default), /en/ /de/ /fr/ /es/ /ar/ /ja/, /privacy/, /support/
Set SITE_URL to change the canonical domain (default: GitHub Pages).
"""
import html
import json
import os
import pathlib
import re
import shutil
import sys
import zipfile

SRC = pathlib.Path(__file__).resolve().parent
WEB = SRC.parent
ROOT = WEB.parent
DIST = WEB / "dist"
sys.path.insert(0, str(SRC))
from site_copy import C, HREFLANG, LANG_NAMES, LANGS, OG_LOCALE  # noqa: E402
from hardware import BOM, PINOUT  # noqa: E402

SITE_URL = os.environ.get("SITE_URL", "https://tarikdavulcu.github.io/spooldry").rstrip("/")
FW_VERSION = json.loads((ROOT / "protocol" / "spooldry-ble-v1.json").read_text())["firmwareVersion"]
FW_ZIP = f"spooldry-firmware-{FW_VERSION}.zip"
E = html.escape


def t(key, lang):
    return C[key][lang]


# ---------------------------------------------------------------- filament data (parsed from the iOS source of truth)
def filament_rows():
    src = (ROOT / "ios/Packages/SpoolDryKit/Sources/SpoolDryKit/Filament/FilamentDatabase.swift").read_text()
    urls = dict(re.findall(r'private static let (\w+) = "(https://[^"]+)"', src))
    rows = []
    for block in re.split(r"\n        g\(", src)[1:]:
        m = re.match(r'\.(\w+), "([^"]+)", ([\d.]+)\.\.\.([\d.]+), ([\d.]+)\.\.\.([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+)', block)
        if not m:
            continue
        refs = re.findall(r'\.init\("([^"]+)", "([^"]+)", "([^"]+)", (\w+)\)', block.split("]),")[0])
        rows.append({"name": m.group(2), "tmin": m.group(3), "tmax": m.group(4), "hmin": m.group(5), "hmax": m.group(6),
                     "start": m.group(7), "starth": m.group(8), "rh": m.group(9),
                     "refs": [(a, b, c, urls.get(d, "")) for a, b, c, d in refs]})
    return rows


CATEGORY = {"esp32": "ESP32", "sht40": "Temperature/humidity sensor", "ptc": "PTC heater", "fan": "Fan", "mosfet": "MOSFET",
            "relay": "Safety relay", "thermostat": "Thermostat 85 °C", "tco": "Thermal fuse 100 °C", "ntc": "Heater NTC",
            "psu": "Power supply", "jack": "Power connector", "fuse": "Fuse", "buck": "5 V regulator", "parts": "Wires, terminals, passives",
            "enclosure": "Enclosure"}

# ---------------------------------------------------------------- setup guide code
SETUP_CODE = [
    "ESP32-C6-DevKitC-1-N8 · USB-C data cable · SHT40 + STEMMA QT cable\n(full dryer: see the Bill of Materials above)",
    "# Arduino IDE 2.x: https://www.arduino.cc/en/software\n# or PlatformIO Core:\npython3 -m pip install -U platformio",
    "# Arduino IDE → Settings → Additional boards manager URLs:\nhttps://espressif.github.io/arduino-esp32/package_esp32_index.json\n# Boards Manager → install \"esp32 by Espressif Systems\" ≥ 3.3.12\n\n# arduino-cli\narduino-cli core update-index --additional-urls https://espressif.github.io/arduino-esp32/package_esp32_index.json\narduino-cli core install esp32:esp32",
    "# Use the USB-C port labelled \"UART\" on the DevKitC-1.\n# Unplug the 24 V supply while flashing from your computer.",
    "# Arduino IDE: Tools → Board → esp32 → \"ESP32C6 Dev Module\"\n#   Flash Size: 8MB · Partition Scheme: Custom (uses SpoolDry/partitions.csv)\n# PlatformIO: board = esp32-c6-devkitc-1 (already in platformio.ini)",
    "# macOS: /dev/cu.usbserial-*  ·  Linux: /dev/ttyUSB0  ·  Windows: COM3\narduino-cli board list",
    "# Library Manager → \"NimBLE-Arduino\" by h2zero ≥ 2.5.1\narduino-cli lib install \"NimBLE-Arduino@2.5.1\"\n# PlatformIO installs it automatically (lib_deps)",
    "cd esp32\npio run\n# or\narduino-cli compile --fqbn esp32:esp32:esp32c6:FlashSize=8M,PartitionScheme=custom SpoolDry",
    "pio run -t upload\n# or\narduino-cli upload -p /dev/ttyUSB0 --fqbn esp32:esp32:esp32c6:FlashSize=8M,PartitionScheme=custom SpoolDry",
    "pio device monitor -b 115200\n# expected:\nSpoolDry firmware 1.0.0 (BLE protocol v1) ready as \"SpoolDry-A1B2\"\nAdvertising SpoolDry service 5D0F0001-2B7E-4C8A-9B1E-53504F4F4C44",
    "# Any BLE scanner (e.g. nRF Connect) must show \"SpoolDry-XXXX\"\n# advertising service 5D0F0001-2B7E-4C8A-9B1E-53504F4F4C44",
    "# SpoolDry → Device → Add Dryer (Bluetooth permission prompt appears)",
    "# Tap \"SpoolDry-XXXX\" → accept the iOS pairing request\n# New phones can pair within 5 min after power-on\n# (or hold BOOT for 10 s to clear bonds and reopen pairing)",
]


# ---------------------------------------------------------------- page parts
CSS_INLINE = (WEB / "src" / "site.css").read_text()
JS_INLINE = (WEB / "src" / "site.js").read_text()


def head(lang, path, title, desc, extra_ld):
    alt = "".join(f'<link rel="alternate" hreflang="{HREFLANG[l]}" href="{SITE_URL}/{l}/">' for l in LANGS)
    alt += f'<link rel="alternate" hreflang="x-default" href="{SITE_URL}/">'
    canonical = f"{SITE_URL}{path}"
    ld = json.dumps(extra_ld, ensure_ascii=False)
    pre = "../" if path != "/" else ""
    return f"""<!doctype html>
<html lang="{lang}" dir="{'rtl' if lang == 'ar' else 'ltr'}" data-bs-theme="dark">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{E(title)}</title>
<meta name="description" content="{E(desc)}">
<meta name="robots" content="index, follow, max-image-preview:large">
<link rel="canonical" href="{canonical}">
{alt}
<meta name="theme-color" content="#0b1014">
<meta property="og:type" content="website">
<meta property="og:site_name" content="SpoolDry">
<meta property="og:title" content="{E(title)}">
<meta property="og:description" content="{E(desc)}">
<meta property="og:url" content="{canonical}">
<meta property="og:locale" content="{OG_LOCALE[lang]}">
<meta property="og:image" content="{SITE_URL}/assets/img/og-image.png">
<meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="{E(title)}">
<meta name="twitter:description" content="{E(desc)}">
<meta name="twitter:image" content="{SITE_URL}/assets/img/og-image.png">
<link rel="icon" href="{pre}favicon.ico" sizes="32x32">
<link rel="icon" href="{pre}assets/img/icon.svg" type="image/svg+xml">
<link rel="apple-touch-icon" href="{pre}assets/img/apple-touch-icon.png">
<link rel="manifest" href="{pre}manifest.webmanifest">
<link rel="preload" href="{pre}assets/fonts/inter-latin-wght-normal.woff2" as="font" type="font/woff2" crossorigin>
<link rel="stylesheet" href="{pre}assets/css/bootstrap.min.css">
<style>{CSS_INLINE.replace("__FONT__", pre + "assets/fonts/inter-latin-wght-normal.woff2")}</style>
<script>(function(){{try{{var t=localStorage.getItem('sd-theme');if(t)document.documentElement.setAttribute('data-bs-theme',t);}}catch(e){{}}}})();</script>
<script type="application/ld+json">{ld}</script>
</head>"""


def nav(lang, pre):
    langs = "".join(f'<li><a class="dropdown-item{" active" if l == lang else ""}" href="{pre}{l}/" hreflang="{l}" lang="{l}">{LANG_NAMES[l]}</a></li>' for l in LANGS)
    links = [("#features", "nav_features"), ("#build", "nav_build"), ("#setup", "nav_setup"), ("#filament", "nav_filament"),
             ("#safety", "nav_safety"), ("#pricing", "nav_pricing"), ("#faq", "nav_faq")]
    items = "".join(f'<li class="nav-item"><a class="nav-link" href="{h}">{E(t(k, lang))}</a></li>' for h, k in links)
    return f"""<a class="visually-hidden-focusable skip" href="#main">{E(t('skip', lang))}</a>
<nav class="navbar navbar-expand-lg sticky-top glass-nav" aria-label="Main">
 <div class="container">
  <a class="navbar-brand d-flex align-items-center gap-2 fw-bold" href="{pre}{lang}/"><img src="{pre}assets/img/icon-64.png" width="32" height="32" alt="" class="rounded-3">SpoolDry</a>
  <button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#nav" aria-controls="nav" aria-expanded="false" aria-label="Menu"><span class="navbar-toggler-icon"></span></button>
  <div class="collapse navbar-collapse" id="nav">
   <ul class="navbar-nav ms-auto me-lg-3">{items}</ul>
   <div class="d-flex gap-2 align-items-center">
    <div class="dropdown"><button class="btn btn-sm btn-outline-light dropdown-toggle" data-bs-toggle="dropdown" aria-expanded="false" aria-label="Language">{LANG_NAMES[lang]}</button><ul class="dropdown-menu dropdown-menu-end">{langs}</ul></div>
    <button class="btn btn-sm btn-outline-light theme-toggle" type="button" aria-label="{E(t('theme', lang))}" title="{E(t('theme', lang))}"><svg aria-hidden="true" width="16" height="16" viewBox="0 0 16 16"><circle cx="8" cy="8" r="6.5" fill="none" stroke="currentColor" stroke-width="1.5"/><path d="M8 1.5a6.5 6.5 0 0 1 0 13z" fill="currentColor"/></svg></button>
   </div>
  </div>
 </div>
</nav>"""


def bento(lang):
    cards = [("b_ble", "ᛒ", "span-2"), ("b_poly", "⬡", ""), ("b_live", "◷", "row-2"), ("b_cloud", "⊘", ""),
             ("b_th", "°", ""), ("b_prof", "≣", ""), ("b_hist", "↺", ""), ("b_safe", "⛨", ""), ("b_multi", "⧉", ""), ("b_life", "∞", "span-2")]
    out = []
    for key, ic, cls in cards:
        extra = ""
        if key == "b_live":
            extra = '<img src="../assets/img/shot-live.webp" alt="" loading="lazy" decoding="async" width="440" height="956" class="bento-shot">'
        out.append(f'<article class="bento-card glass {cls}"><div class="bento-ic" aria-hidden="true">{ic}</div>'
                   f'<h3>{E(t(key + "_h", lang))}</h3><p>{E(t(key + "_p", lang))}</p>{extra}</article>')
    return "".join(out)


def build_section(lang):
    cards = []
    for b in BOM:
        links = " · ".join(f'<a href="{E(u)}" rel="noopener nofollow" target="_blank">{E(n)}</a>' for n, u in b["links"])
        cards.append(f"""<div class="col-md-6 col-xl-4"><article class="glass h-100 p-4 comp">
<h3 class="h5">{E(b['name'])}</h3>
<dl><dt>{E(t('col_purpose', lang))}</dt><dd>{E(b['purpose'][lang])}</dd>
<dt>{E(t('col_spec', lang))}</dt><dd class="small">{E(b['spec'])}</dd>
<dt>{E(t('col_why', lang))}</dt><dd>{E(b['why'][lang])}</dd>
<dt>{E(t('col_links', lang))}</dt><dd class="small">{links}</dd></dl></article></div>""")
    rows = "".join(f"<tr><td>{E(CATEGORY[b['id']])}</td><td>{E(b['name'])}</td><td>{E(b['purpose'][lang])}</td><td>{b['qty']}</td>"
                   f"<td>{' · '.join(f'<a href=\"{E(u)}\" rel=\"noopener nofollow\" target=\"_blank\">{E(n)}</a>' for n, u in b['links'][:2])}</td></tr>" for b in BOM)
    pins = "".join(f"<tr><td><code>{E(g)}</code></td><td>{E(f)}</td><td>{E(c)}</td><td>{E(d)}</td><td class='small'>{E(n)}</td></tr>" for g, f, c, d, n in PINOUT)
    return f"""<section id="build" class="section"><div class="container">
<h2 class="display-6 fw-bold">{E(t('build_h', lang))}</h2><p class="lead text-body-secondary col-lg-9">{E(t('build_p', lang))}</p>
<div class="row g-4 mt-2">{''.join(cards)}</div>
<h3 class="h3 mt-5" id="bom">{E(t('bom_h', lang))}</h3>
<div class="table-responsive glass p-2"><table class="table table-sm align-middle mb-0"><thead><tr><th>{E(t('col_component', lang))}</th><th>{E(t('col_part', lang))}</th><th>{E(t('col_purpose', lang))}</th><th>{E(t('col_qty', lang))}</th><th>{E(t('col_links', lang))}</th></tr></thead><tbody>{rows}</tbody></table></div>
<p class="small text-body-secondary mt-2">{E(t('bom_note', lang))}</p>
<h3 class="h3 mt-5" id="wiring">{E(t('wiring_h', lang))}</h3>
<figure class="glass p-2"><img src="../assets/img/wiring.svg" alt="{E(t('wiring_h', lang))}" class="img-fluid w-100" loading="lazy" width="1200" height="860"></figure>
<h3 class="h3 mt-5" id="pinout">{E(t('pinout_h', lang))}</h3>
<div class="table-responsive glass p-2"><table class="table table-sm mb-0"><thead><tr><th>GPIO</th><th>Function</th><th>Component</th><th>Dir</th><th>Notes</th></tr></thead><tbody>{pins}</tbody></table></div>
</div></section>"""


def setup_section(lang):
    steps = t("setup_steps", lang)
    lis = "".join(f'<li class="glass p-3 mb-3"><h3 class="h6 fw-bold mb-2">{i + 1}. {E(s)}</h3><pre class="code"><code>{E(SETUP_CODE[i])}</code></pre></li>' for i, s in enumerate(steps))
    return f"""<section id="setup" class="section"><div class="container">
<h2 class="display-6 fw-bold">{E(t('setup_h', lang))}</h2>
<ol class="list-unstyled setup mt-4" dir="ltr">{lis}</ol>
<div class="glass p-4 mt-4" id="firmware"><h3 class="h4">{E(t('fw_h', lang))}</h3>
<div class="row g-3 small" dir="ltr"><div class="col-md-6"><ul class="mb-0">
<li><b>Version:</b> {FW_VERSION} · BLE Protocol v1</li><li><b>Board:</b> Espressif ESP32-C6-DevKitC-1-N8 (8 MB)</li>
<li><b>Framework:</b> Arduino-ESP32 3.3.x (PlatformIO: pioarduino)</li><li><b>Dependencies:</b> NimBLE-Arduino 2.5.x (h2zero)</li></ul></div>
<div class="col-md-6"><ul class="mb-0"><li><b>Configuration:</b> <code>SpoolDry/src/core/Config.h</code> (pins, limits)</li>
<li><b>Partitions:</b> <code>SpoolDry/partitions.csv</code> (2× 3 MB OTA slots)</li><li><b>Tests:</b> <code>make -C test/host test</code> (33 safety &amp; protocol tests)</li>
<li><b>Service UUID:</b> <code>5D0F0001-2B7E-4C8A-9B1E-53504F4F4C44</code></li></ul></div></div>
<a class="btn btn-accent mt-3" href="../assets/downloads/{FW_ZIP}" download>{E(t('fw_btn', lang))}</a></div>
</div></section>"""


def filament_section(lang):
    rows = []
    for r in filament_rows():
        srcs = "<br>".join(f'<a href="{E(u)}" rel="noopener nofollow" target="_blank">{E(m)}</a>: {E(s)}' for m, p, s, u in r["refs"])
        hot = float(r["tmin"]) > 70
        rows.append(f"<tr><th scope='row'>{E(r['name'])}{' <span class=\"badge text-bg-warning\">110–150 °C</span>' if hot else ''}</th>"
                    f"<td>{r['tmin']}–{r['tmax']} °C</td><td>{r['hmin']}–{r['hmax']} h</td><td>{r['start']} °C · {r['starth']} h · &lt;{r['rh']}% RH</td><td class='small'>{srcs}</td></tr>")
    return f"""<section id="filament" class="section"><div class="container">
<h2 class="display-6 fw-bold">{E(t('fil_h', lang))}</h2><p class="text-body-secondary col-lg-9">{E(t('fil_note', lang))}</p>
<div class="table-responsive glass p-2"><table class="table table-sm align-middle mb-0"><thead><tr><th>{E(t('col_material', lang))}</th><th>{E(t('col_temp', lang))}</th><th>{E(t('col_time', lang))}</th><th>{E(t('col_start', lang))}</th><th>{E(t('col_sources', lang))}</th></tr></thead>
<tbody>{''.join(rows)}</tbody></table></div></div></section>"""


def safety_section(lang):
    items = "".join(f"<li>{E(s)}</li>" for s in t("safety_items", lang))
    layers = ["Firmware: 80 °C absolute, target +8 °C/30 s, sensor CRC & plausibility, fan tach, heater-NTC derating, runaway & stuck-heater detection, 5 s watchdog",
              "Heater defaults OFF: 10 kΩ gate pull-downs, outputs driven LOW first at boot, sessions never resume after reset",
              "Two independent switches in the heater path: MOSFET Q1 + relay K1",
              "85 °C bimetal thermostat opens the relay coil without software",
              "100 °C one-shot thermal cutoff in the heater current",
              "Self-limiting PTC element (power collapses without airflow)",
              "7.5 A fuse · certified, enclosed 24 V supply (no user mains wiring)"]
    li2 = "".join(f"<li>{E(s)}</li>" for s in layers)
    return f"""<section id="safety" class="section"><div class="container"><div class="row g-4">
<div class="col-lg-6"><h2 class="display-6 fw-bold">{E(t('safety_h', lang))}</h2>
<div class="alert alert-warning glass-warn" role="note">{E(t('safety_intro', lang))}</div><ul class="safety-list">{items}</ul></div>
<div class="col-lg-6"><div class="glass p-4 h-100" dir="ltr"><h3 class="h5">{E(t('layers_h', lang))}</h3><ol class="small mb-0">{li2}</ol></div></div>
</div></div></section>"""


def pricing_section(lang):
    return f"""<section id="pricing" class="section"><div class="container"><h2 class="display-6 fw-bold text-center">{E(t('pricing_h', lang))}</h2>
<div class="row g-4 justify-content-center mt-2">
<div class="col-md-5"><div class="glass p-4 h-100"><h3 class="h4">{E(t('free_h', lang))}</h3><p class="display-6 fw-bold">0</p><p>{E(t('free_p', lang))}</p></div></div>
<div class="col-md-5"><div class="glass p-4 h-100 featured"><h3 class="h4">{E(t('life_h', lang))}</h3><p class="display-6 fw-bold accent">$19.99</p><p>{E(t('life_p', lang))}</p><p class="small fw-semibold">{E(t('no_sub', lang))}</p></div></div>
</div></div></section>"""


def faq_section(lang):
    items = "".join(f"""<div class="accordion-item glass"><h3 class="accordion-header"><button class="accordion-button collapsed" type="button" data-bs-toggle="collapse" data-bs-target="#faq{i}" aria-expanded="false" aria-controls="faq{i}">{E(q)}</button></h3>
<div id="faq{i}" class="accordion-collapse collapse" data-bs-parent="#faqacc"><div class="accordion-body">{E(a)}</div></div></div>""" for i, (q, a) in enumerate(t("faq", lang)))
    return f'<section id="faq" class="section"><div class="container col-lg-9"><h2 class="display-6 fw-bold">{E(t("faq_h", lang))}</h2><div class="accordion mt-3" id="faqacc">{items}</div></div></section>'


def footer(lang, pre):
    langs = " · ".join(f'<a href="{pre}{l}/" hreflang="{l}" lang="{l}">{LANG_NAMES[l]}</a>' for l in LANGS)
    return f"""<footer class="py-5 border-top border-secondary-subtle"><div class="container small text-body-secondary d-flex flex-column flex-md-row justify-content-between gap-3">
<div>© 2026 SpoolDry · {E(t('footer_note', lang))}</div>
<div><a href="{pre}privacy/">{E(t('footer_privacy', lang))}</a> · <a href="{pre}support/">{E(t('footer_support', lang))}</a> · {langs}</div></div></footer>
<script src="{pre}assets/js/bootstrap.bundle.min.js" defer></script><script>{JS_INLINE}</script>"""


def ld_for(lang, path):
    faq = [{"@type": "Question", "name": q, "acceptedAnswer": {"@type": "Answer", "text": a}} for q, a in t("faq", lang)]
    return {"@context": "https://schema.org", "@graph": [
        {"@type": "WebSite", "@id": f"{SITE_URL}/#website", "url": f"{SITE_URL}/", "name": "SpoolDry", "inLanguage": lang},
        {"@type": "SoftwareApplication", "name": "SpoolDry", "applicationCategory": "UtilitiesApplication", "operatingSystem": "iOS 17 or later",
         "description": t("description", lang), "url": f"{SITE_URL}{path}", "inLanguage": lang,
         "offers": [{"@type": "Offer", "price": "0", "priceCurrency": "USD", "description": "3 free drying sessions"},
                    {"@type": "Offer", "price": "19.99", "priceCurrency": "USD", "description": "SpoolDry Lifetime (one-time purchase)"}],
         "author": {"@type": "Person", "name": "Tarık Davulcu"}},
        {"@type": "FAQPage", "mainEntity": faq}]}


def landing(lang, path):
    pre = "../" if path != "/" else ""
    how = "".join(f'<div class="col-md-4"><div class="glass p-4 h-100"><div class="step-n">{i + 1}</div><p class="mb-0">{E(s)}</p></div></div>' for i, s in enumerate(t("how", lang)))
    body = f"""<body class="lang-{lang}">
{nav(lang, pre)}
<main id="main">
<header class="hero section"><div class="container"><div class="row align-items-center g-4 g-lg-5">
<div class="col-lg-6"><p class="kicker">{E(t('hero_kicker', lang))}</p><h1 class="hero-title">{t('hero_h1', lang)}</h1>
<p class="lead text-body-secondary">{E(t('hero_p', lang))}</p>
<div class="d-flex flex-wrap gap-3 mt-4"><a class="btn btn-accent btn-lg" href="#pricing">{E(t('cta_free', lang))}</a><a class="btn btn-outline-light btn-lg" href="#pricing">{E(t('cta_life', lang))}</a></div>
<p class="small text-body-secondary mt-3">{E(t('no_sub', lang))} · {E(t('appstore', lang))}</p></div>
<div class="col-lg-6 text-center"><picture><source type="image/webp" srcset="{pre}assets/img/hero-480.webp 480w, {pre}assets/img/hero-880.webp 880w" sizes="(min-width: 992px) 44vw, 90vw">
<img src="{pre}assets/img/hero-880.png" alt="SpoolDry app dashboard showing PA-CF drying at 67.2 °C and 18 % humidity" width="880" height="1100" class="img-fluid hero-img" fetchpriority="high"></picture></div>
</div></div></header>
<section id="features" class="section"><div class="container"><h2 class="display-6 fw-bold">{E(t('features_h', lang))}</h2><div class="bento mt-4">{bento(lang).replace('../', pre)}</div></div></section>
<section class="section"><div class="container"><h2 class="h2 fw-bold">{E(t('how_h', lang))}</h2><div class="row g-4 mt-1">{how}</div></div></section>
{build_section(lang).replace('../', pre)}
{setup_section(lang).replace('../', pre)}
{filament_section(lang)}
{safety_section(lang)}
{pricing_section(lang)}
{faq_section(lang)}
</main>
{footer(lang, pre)}
</body></html>"""
    return head(lang, path, t("title", lang), t("description", lang), ld_for(lang, path)) + body


PRIVACY = """<h1>Privacy Policy</h1><p class="text-body-secondary">Last updated: October 2, 2026</p>
<p>SpoolDry ("the app") is designed to work without collecting personal data.</p>
<h2 class="h4 mt-4">What the app does not do</h2><ul><li>No account, no sign-in.</li><li>No analytics, advertising or tracking SDKs. No data is sold or shared.</li><li>No server or cloud database. The app does not send your data over the internet.</li></ul>
<h2 class="h4 mt-4">Bluetooth</h2><p>The app uses Bluetooth Low Energy only to communicate directly with your SpoolDry dryer (ESP32) to read temperature, humidity and device status and to start or stop drying. iOS asks for Bluetooth permission the first time you set up a dryer.</p>
<h2 class="h4 mt-4">Data stored on your device</h2><ul><li>Saved dryers (name, Bluetooth identifier, firmware version).</li><li>Drying history (dates, filament, target, duration, start/end humidity, a 5-minute chart series which is removed after the retention period you choose).</li><li>Your custom filament profiles and settings.</li><li>A counter of used free drying sessions, stored in the iOS Keychain on this device.</li><li>The latest dryer status in an App Group so widgets and Live Activities can display it.</li></ul>
<p>Deleting the app deletes this data (except the Keychain counter, which iOS may keep). Data may be included in your own encrypted iPhone backups.</p>
<h2 class="h4 mt-4">Purchases</h2><p>The one-time "SpoolDry Lifetime" purchase is processed by Apple through the App Store. The developer does not receive your payment details.</p>
<h2 class="h4 mt-4">Website</h2><p>This website uses no cookies and no third-party trackers. Fonts and scripts are served from this site. Your light/dark choice is stored in your browser's local storage.</p>
<h2 class="h4 mt-4">Contact</h2><p>Questions: open an issue at <a href="https://github.com/tarikdavulcu/spooldry/issues">github.com/tarikdavulcu/spooldry/issues</a>.</p>"""

SUPPORT = """<h1>SpoolDry Support</h1><p class="lead text-body-secondary">Help for the iOS app, the ESP32 firmware and the hardware build.</p>
<h2 class="h4 mt-4">Contact</h2><p>Report a problem or ask a question: <a href="https://github.com/tarikdavulcu/spooldry/issues">github.com/tarikdavulcu/spooldry/issues</a>. Please include your iOS version, app version, firmware version (Device tab) and what the dryer's status LED shows.</p>
<h2 class="h4 mt-4">Common fixes</h2><ul>
<li><b>Dryer not found:</b> make sure it advertises "SpoolDry-XXXX" (check the serial monitor) and Bluetooth permission is enabled in Settings › SpoolDry.</li>
<li><b>Pairing fails:</b> new phones can pair within 5 minutes after power-on. Hold the BOOT button for 10 seconds to clear stored bonds and reopen pairing. In iOS Settings › Bluetooth, "Forget" the old SpoolDry entry.</li>
<li><b>Start rejected (sensor fault):</b> check the SHT40 STEMMA QT cable and the heater NTC.</li>
<li><b>Fan failure / over-temperature:</b> the heater was switched off for safety. Inspect the fan and airflow, let the dryer cool below 50 °C, then use Reset Fault.</li>
<li><b>Restore purchase:</b> Settings › Restore Purchases, signed in with the same Apple Account.</li></ul>
<h2 class="h4 mt-4">Documentation</h2><p>Build guide, BOM, wiring diagram, pin map, BLE protocol and safety notes: see the <a href="../en/#build">website</a> and the docs folder of the project.</p>"""


def simple_page(slug, title, inner):
    path = f"/{slug}/"
    ld = {"@context": "https://schema.org", "@type": "WebPage", "name": title, "url": f"{SITE_URL}{path}"}
    return head("en", path, f"{title} – SpoolDry", f"{title} for the SpoolDry iOS app and ESP32 filament dryer.", ld) + \
        f'<body class="lang-en">{nav("en", "../")}<main id="main" class="section"><div class="container col-lg-8 prose">{inner}</div></main>{footer("en", "../")}</body></html>'


def make_firmware_zip():
    out = DIST / "assets" / "downloads" / FW_ZIP
    out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        base = ROOT / "esp32"
        for p in sorted(base.rglob("*")):
            if p.is_file() and not any(x in p.parts for x in (".pio", "build")) and p.suffix not in (".o",) and p.name not in ("spooldry_tests", "golden_vectors"):
                z.write(p, f"spooldry-firmware-{FW_VERSION}/{p.relative_to(base)}")
        for extra in ("protocol/spooldry-ble-v1.json", "protocol/golden-vectors-v1.json", "docs/BLE_PROTOCOL.md", "docs/SAFETY.md", "docs/ESP32_SETUP.md", "docs/HARDWARE.md"):
            p = ROOT / extra
            if p.exists():
                z.write(p, f"spooldry-firmware-{FW_VERSION}/{extra}")
    return out


def main():
    if DIST.exists():
        shutil.rmtree(DIST)
    shutil.copytree(WEB / "assets", DIST / "assets")
    (DIST / "assets" / "img").mkdir(parents=True, exist_ok=True)
    pages = {"index.html": landing("en", "/")}
    for lang in LANGS:
        pages[f"{lang}/index.html"] = landing(lang, f"/{lang}/")
    pages["privacy/index.html"] = simple_page("privacy", "Privacy Policy", PRIVACY)
    pages["support/index.html"] = simple_page("support", "Support", SUPPORT)
    for rel, content in pages.items():
        p = DIST / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content)
    # robots, sitemap, manifest
    (DIST / "robots.txt").write_text(f"User-agent: *\nAllow: /\n\nSitemap: {SITE_URL}/sitemap.xml\n")
    urls = ["/"] + [f"/{l}/" for l in LANGS] + ["/privacy/", "/support/"]
    alts = "".join(f'<xhtml:link rel="alternate" hreflang="{l}" href="{SITE_URL}/{l}/"/>' for l in LANGS) + f'<xhtml:link rel="alternate" hreflang="x-default" href="{SITE_URL}/"/>'
    entries = "".join(f"<url><loc>{SITE_URL}{u}</loc><lastmod>2026-10-02</lastmod>{alts if u == '/' or u.strip('/') in LANGS else ''}</url>" for u in urls)
    (DIST / "sitemap.xml").write_text(f'<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">{entries}</urlset>\n')
    manifest = {"name": "SpoolDry", "short_name": "SpoolDry", "start_url": "./", "display": "standalone", "background_color": "#0b1014",
                "theme_color": "#0b1014", "icons": [{"src": "assets/img/icon-192.png", "sizes": "192x192", "type": "image/png"},
                                                   {"src": "assets/img/icon-512.png", "sizes": "512x512", "type": "image/png"}]}
    (DIST / "manifest.webmanifest").write_text(json.dumps(manifest, indent=2))
    (DIST / ".nojekyll").write_text("")
    shutil.copy(DIST / "assets" / "img" / "favicon.ico", DIST / "favicon.ico")
    z = make_firmware_zip()
    print(f"built {len(pages)} pages into {DIST} (firmware zip {z.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
