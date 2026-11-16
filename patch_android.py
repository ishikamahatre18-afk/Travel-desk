#!/usr/bin/env python3
"""Hardens the generated Android project. Run from the repo root after copying android/."""
import pathlib
import re
import shutil
import sys

root = pathlib.Path("android")
manifest = root / "app/src/main/AndroidManifest.xml"
if not manifest.exists():
    sys.exit("AndroidManifest.xml not found")

m = manifest.read_text()

if "android.permission.INTERNET" not in m:
    m = m.replace("<application", '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)

# Security flags on <application>
def add_attr(text, attr, value):
    if f"{attr}=" in text:
        return re.sub(rf'{attr}="[^"]*"', f'{attr}="{value}"', text, count=1)
    return text.replace("<application", f'<application {attr}="{value}"', 1)

m = add_attr(m, "android:allowBackup", "false")
m = add_attr(m, "android:usesCleartextTraffic", "false")
m = add_attr(m, "android:label", "Travel Desk")

# Backup rules must not re-enable backups on Android 12+.
m = add_attr(m, "android:fullBackupContent", "false")
m = add_attr(m, "android:dataExtractionRules", "@xml/data_extraction_rules")

if "<queries>" not in m:
    m = m.replace(
        "</manifest>",
        '    <queries>\n        <intent>\n            <action android:name="android.intent.action.VIEW"/>\n'
        '            <data android:scheme="https"/>\n        </intent>\n    </queries>\n</manifest>',
    )
manifest.write_text(m)

xml_dir = root / "app/src/main/res/xml"
xml_dir.mkdir(parents=True, exist_ok=True)
(xml_dir / "data_extraction_rules.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n<data-extraction-rules>\n'
    "    <cloud-backup><exclude domain=\"root\"/><exclude domain=\"file\"/>"
    "<exclude domain=\"database\"/><exclude domain=\"sharedpref\"/></cloud-backup>\n"
    "    <device-transfer><exclude domain=\"root\"/><exclude domain=\"file\"/>"
    "<exclude domain=\"database\"/><exclude domain=\"sharedpref\"/></device-transfer>\n"
    "</data-extraction-rules>\n"
)

# flutter_secure_storage needs minSdk 23.
for name in ("build.gradle.kts", "build.gradle"):
    g = root / "app" / name
    if g.exists():
        t = g.read_text()
        t = re.sub(r"flutter\.minSdkVersion", "23", t)
        g.write_text(t)

# FLAG_SECURE activity
kotlin_dir = root / "app/src/main/kotlin/com/agencyassist/travel_desk"
kotlin_dir.mkdir(parents=True, exist_ok=True)
shutil.copy("android_overlay/MainActivity.kt", kotlin_dir / "MainActivity.kt")

print("Android project patched.")
