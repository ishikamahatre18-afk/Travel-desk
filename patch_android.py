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

# The on-device model engine (LiteRT-LM) needs Android 11 (API 30) and 64-bit ARM.
g = root / "app/build.gradle.kts"
if g.exists():
    t = g.read_text()
    t = re.sub(r"flutter\.minSdkVersion", "30", t)
    if "abiFilters" not in t:
        t = t.replace("defaultConfig {", 'defaultConfig {\n        ndk { abiFilters.add("arm64-v8a") }', 1)
    g.write_text(t)
else:
    sys.exit("build.gradle.kts not found")

# FLAG_SECURE activity
kotlin_dir = root / "app/src/main/kotlin/com/agencyassist/travel_desk"
kotlin_dir.mkdir(parents=True, exist_ok=True)
shutil.copy("android_overlay/MainActivity.kt", kotlin_dir / "MainActivity.kt")


# ---- Stable release signing (so new builds install over old ones) ----------
import os
jks = root / "app/release.jks"
if jks.exists() and os.environ.get("KEYSTORE_PASSWORD"):
    pw = os.environ["KEYSTORE_PASSWORD"]
    (root / "key.properties").write_text(
        f"storePassword={pw}\nkeyPassword={pw}\nkeyAlias=traveldesk\nstoreFile=release.jks\n"
    )
    g = root / "app/build.gradle.kts"
    t = g.read_text()
    if "keystoreProperties" not in t:
        t = ("import java.util.Properties\nimport java.io.FileInputStream\n\n" + t)
        t = t.replace(
            "android {",
            "val keystoreProperties = Properties().apply {\n"
            "    load(FileInputStream(rootProject.file(\"key.properties\")))\n}\n\n"
            "android {\n"
            "    signingConfigs {\n"
            "        create(\"release\") {\n"
            "            keyAlias = keystoreProperties[\"keyAlias\"] as String\n"
            "            keyPassword = keystoreProperties[\"keyPassword\"] as String\n"
            "            storeFile = file(keystoreProperties[\"storeFile\"] as String)\n"
            "            storePassword = keystoreProperties[\"storePassword\"] as String\n"
            "        }\n"
            "    }",
            1,
        )
        t2 = t.replace('signingConfig = signingConfigs.getByName("debug")',
                       'signingConfig = signingConfigs.getByName("release")')
        if t2 == t:
            sys.exit("Could not switch release build to the release signing config")
        g.write_text(t2)
    print("Release signing enabled.")
else:
    print("::warning::No signing key found. Building with a temporary key: this APK will NOT install over an older one.")

print("Android project patched.")
