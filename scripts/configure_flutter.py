"""Generate missing platform scaffolds with the installed Flutter SDK."""
import json
import plistlib
import shutil
import subprocess
from tempfile import TemporaryDirectory
from pathlib import Path

APP = Path(__file__).resolve().parents[1] / "apps" / "flutter_app"
INTERNET = '<uses-permission android:name="android.permission.INTERNET"/>'


def configure():
    flutter = shutil.which("flutter")
    if flutter is None:
        raise SystemExit("Install the Flutter SDK and make flutter available on PATH.")
    missing = [platform for platform in ("android", "ios", "web") if not (APP / platform).is_dir()]
    if missing:
        with TemporaryDirectory(prefix="boipath-platforms-") as destination:
            template = Path(destination) / "boipath"
            subprocess.run(
                [flutter, "create", "--no-pub", "--empty", "--org", "app.boipath",
                 "--project-name", "boipath", "--platforms", ",".join(missing), str(template)],
                check=True, shell=flutter.lower().endswith(".bat"),
            )
            for platform in missing:
                if not (template / platform).is_dir():
                    raise SystemExit(f"The selected Flutter SDK did not generate {platform}.")
            for platform in missing:
                shutil.copytree(template / platform, APP / platform)
            metadata = APP / ".metadata"
            if not metadata.exists():
                shutil.copy2(template / ".metadata", metadata)
    manifest = APP / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
    android_xml = manifest.read_text(encoding="utf-8")
    if 'android.permission.INTERNET' not in android_xml:
        if "<application" not in android_xml:
            raise SystemExit("Cannot find the generated Android application declaration.")
        android_xml = android_xml.replace("<application", f"{INTERNET}\n    <application", 1)
    manifest.write_text(android_xml.replace('android:label="boipath"', 'android:label="BoiPath"'),
                        encoding="utf-8")
    for variant in ("debug", "profile"):
        debug = APP / "android" / "app" / "src" / variant / "AndroidManifest.xml"
        if not debug.is_file():
            continue
        xml = debug.read_text(encoding="utf-8")
        if "android:usesCleartextTraffic" not in xml and "</manifest>" in xml:
            xml = xml.replace("</manifest>", '    <application android:usesCleartextTraffic="true"/>\n</manifest>')
            debug.write_text(xml, encoding="utf-8")
    details = APP / "web" / "index.html"
    html = details.read_text(encoding="utf-8")
    details.write_text(html.replace("<title>boipath</title>", "<title>BoiPath</title>"), encoding="utf-8")
    manifest_web = APP / "web" / "manifest.json"
    manifest_data = json.loads(manifest_web.read_text(encoding="utf-8"))
    manifest_web.write_text(json.dumps({**manifest_data, "name": "BoiPath", "short_name": "BoiPath"},
                                        indent=2) + "\n", encoding="utf-8")
    ios = APP / "ios" / "Runner" / "Info.plist"
    with ios.open("rb") as stream:
        ios_values = plistlib.load(stream)
    ios_values["CFBundleDisplayName"] = "BoiPath"
    with ios.open("wb") as stream:
        plistlib.dump(ios_values, stream, sort_keys=False)
    print("Platform scaffolds ready. Run 'flutter pub get' in apps/flutter_app.")


if __name__ == "__main__":
    configure()
