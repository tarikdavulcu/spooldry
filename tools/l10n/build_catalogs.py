#!/usr/bin/env python3
"""Builds the iOS String Catalogs (.xcstrings) for en, de, fr, es, ar, ja and validates them.

  python3 tools/l10n/build_catalogs.py          # write catalogs
  python3 tools/l10n/build_catalogs.py --check  # validate only (CI)

Validation: every key used in Swift exists, every language is translated, and format specifiers
(%@, %lld, %%) match the English source in count and type.
"""
import json
import pathlib
import re
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))
from strings_app import T  # noqa: E402
from strings_dynamic import D  # noqa: E402

LANGS = ["de", "fr", "es", "ar", "ja"]
SPEC = re.compile(r"%(?:\d+\$)?(lld|@|lf|d|%)")

INFO_PLIST = {
    "CFBundleDisplayName": ("SpoolDry",) * 6,
    "NSBluetoothAlwaysUsageDescription": (
        "SpoolDry uses Bluetooth to connect directly to your SpoolDry filament dryer to read temperature and humidity and to start or stop drying. No data leaves your iPhone.",
        "SpoolDry nutzt Bluetooth, um sich direkt mit deinem SpoolDry-Filamenttrockner zu verbinden, Temperatur und Feuchte zu lesen und Trocknungen zu starten oder zu stoppen. Keine Daten verlassen dein iPhone.",
        "SpoolDry utilise le Bluetooth pour se connecter directement à votre sécheur de filament SpoolDry, lire la température et l'humidité, et démarrer ou arrêter le séchage. Aucune donnée ne quitte votre iPhone.",
        "SpoolDry usa Bluetooth para conectarse directamente a tu secador de filamento SpoolDry, leer la temperatura y la humedad e iniciar o detener el secado. Ningún dato sale de tu iPhone.",
        "يستخدم SpoolDry البلوتوث للاتصال مباشرة بمجفف الخيوط SpoolDry لقراءة الحرارة والرطوبة وبدء التجفيف أو إيقافه. لا تغادر أي بيانات جهاز iPhone.",
        "SpoolDryはBluetoothでSpoolDryフィラメントドライヤーに直接接続し、温度と湿度の読み取りや乾燥の開始・停止を行います。データがiPhoneの外に送信されることはありません。"),
}

SHORTCUTS = {
    "Show my filament dryer in ${applicationName}": (
        "Zeig meinen Filamenttrockner in ${applicationName}",
        "Affiche mon sécheur de filament dans ${applicationName}",
        "Muestra mi secador de filamento en ${applicationName}",
        "اعرض مجفف الخيوط في ${applicationName}",
        "${applicationName}でフィラメントドライヤーを表示"),
    "Check filament drying in ${applicationName}": (
        "Prüfe die Filamenttrocknung in ${applicationName}",
        "Vérifie le séchage du filament dans ${applicationName}",
        "Comprueba el secado del filamento en ${applicationName}",
        "تحقق من تجفيف الخيوط في ${applicationName}",
        "${applicationName}でフィラメントの乾燥を確認"),
    "Dryer Status": ("Trocknerstatus", "État du sécheur", "Estado del secador", "حالة المجفف", "ドライヤーの状態"),
}

WIDGET_EXTRA = ["Temperature", "Humidity", "Target", "Filament", "Current", "SpoolDry", "Done", "Preheating", "Remaining"]


def specs(s):
    return sorted(m.group(1) for m in SPEC.finditer(s))


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def catalog(entries):
    """entries: {key: (en, de, fr, es, ar, ja)}"""
    strings = {}
    for key in sorted(entries):
        vals = entries[key]
        loc = {"en": unit(vals[0])}
        for lang, v in zip(LANGS, vals[1:]):
            loc[lang] = unit(v)
        strings[key] = {"extractionState": "manual", "localizations": loc}
    return {"sourceLanguage": "en", "strings": strings, "version": "1.0"}


def validate(entries, label):
    errors = []
    for key, vals in entries.items():
        if len(vals) != 6:
            errors.append(f"[{label}] {key!r}: expected 6 values, got {len(vals)}")
            continue
        src = specs(vals[0])
        for lang, v in zip(["en"] + LANGS, vals):
            if not v.strip():
                errors.append(f"[{label}] {key!r}: empty {lang}")
            if specs(v) != src:
                errors.append(f"[{label}] {key!r}: {lang} format specifiers {specs(v)} != {src}")
    return errors


def main():
    check = "--check" in sys.argv
    used = json.loads(subprocess.check_output([sys.executable, str(ROOT / "tools" / "l10n_extract.py")]))
    app_entries = {k: (k,) + v for k, v in T.items()}
    app_entries.update({k: v for k, v in D.items()})
    errors = []
    missing = [k for k in used["app"] if k not in app_entries]
    missing += [k for k in used["widget"] + WIDGET_EXTRA if k not in app_entries]
    errors += [f"missing translation for key {k!r}" for k in missing]
    errors += validate(app_entries, "app")

    widget_keys = set(used["widget"]) | set(WIDGET_EXTRA) | {k for k in D if k.startswith("state.")}
    widget_entries = {k: app_entries[k] for k in widget_keys if k in app_entries}

    info_entries = {k: v for k, v in INFO_PLIST.items()}
    errors += validate(info_entries, "InfoPlist")
    sc_entries = {k: (k,) + v for k, v in SHORTCUTS.items()}

    if errors:
        print("\n".join(errors))
        print(f"\n{len(errors)} localization problem(s)")
        return 1
    print(f"OK: {len(app_entries)} app keys, {len(widget_entries)} widget keys, 6 languages, specifiers consistent")
    if check:
        return 0
    out = {
        ROOT / "ios/SpoolDry/Resources/Localizable.xcstrings": catalog(app_entries),
        ROOT / "ios/SpoolDryWidgets/Localizable.xcstrings": catalog(widget_entries),
        ROOT / "ios/SpoolDry/Resources/InfoPlist.xcstrings": catalog(info_entries),
        ROOT / "ios/SpoolDry/Resources/AppShortcuts.xcstrings": catalog(sc_entries),
    }
    for path, data in out.items():
        path.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=False) + "\n")
        print("wrote", path.relative_to(ROOT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
