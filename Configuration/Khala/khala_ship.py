"""Khala build identity and release helper (Nir's fork of the Home Assistant iOS app).

Everything that turns this upstream checkout into the "Khala" TestFlight build lives here,
applied at build time to a disposable CI checkout, so no upstream-tracked file has to carry
a fork-only edit (rebases onto upstream stay conflict-free):

  apply        write the git-ignored overrides xcconfig (team + bundle prefix), drop every
               app extension / watch app / mac launcher from the App target's dependencies
               and embed phases, strip applinks associated domains, set the display name,
               and install the Khala icon over the upstream one. Idempotent.
  verify       assert that `apply` produced exactly that (runs on Linux before any macOS
               minute is spent, and again on macOS before archiving).
  xcconfig     write the per-run signing/version xcconfig passed to `xcodebuild -xcconfig`.
  export-options  write ExportOptions.plist for `xcodebuild -exportArchive`.
  asc          App Store Connect preflight on Linux (needs PyJWT[crypto]).
  verify-ipa   check the exported IPA's Info.plist and embedded profile on Linux.

Apply/verify/xcconfig/export-options/verify-ipa use only the standard library. Credentials
and Apple response bodies are never printed.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import plistlib
import re
import shutil
import struct
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
KHALA = Path(__file__).resolve().parent

DISPLAY_NAME = "Khala"
PBXPROJ = "HomeAssistant.xcodeproj/project.pbxproj"
OVERRIDES = "Configuration/HomeAssistant.overrides.xcconfig"
ENTITLEMENTS = "Configuration/Entitlements/App-ios.entitlements"
INFO_PLIST = "Sources/App/Resources/Info.plist"
APPICONSET = "Sources/App/Resources/Assets.xcassets/AppIcon.appiconset"
ICON_COMPOSER = "Sources/App/Resources/AppIcon.icon"
APP_TARGET = "App"
# Only frameworks stay linked/embedded in the App target. Everything else it depends on
# (Share, Widgets, Intents, Notification Content/Service, Matter, PushProvider app
# extensions, the WatchApp and the Catalyst Launcher) is dropped from the build: each would
# need its own App ID, provisioning and, for several, Apple-approval entitlements.
KEEP_PRODUCT_TYPES = {"com.apple.product-type.framework"}
ASSOCIATED_DOMAINS = "com.apple.developer.associated-domains"


def fail(message):
    raise SystemExit(f"::error::{message}")


def require(condition, message):
    if not condition:
        fail(message)


def summary(message):
    print(message)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(os.environ["GITHUB_STEP_SUMMARY"], "a") as out:
            out.write(message + "\n")


def emit(key, value):
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as out:
            out.write(f"{key}={value}\n")


# --- pbxproj (OpenStep plist) reading -------------------------------------------------

_TOKEN = re.compile(r"[A-Za-z0-9_$/:.\-+]+")


def parse_openstep(text):
    """Minimal parser for Xcode's OpenStep-style project.pbxproj (dicts, arrays, strings)."""
    pos, end = 0, len(text)

    def skip():
        nonlocal pos
        while pos < end:
            if text[pos].isspace():
                pos += 1
            elif text.startswith("/*", pos):
                pos = text.index("*/", pos) + 2
            elif text.startswith("//", pos):
                pos = text.index("\n", pos) + 1
            else:
                return

    def value():
        nonlocal pos
        skip()
        char = text[pos]
        if char == "{":
            pos += 1
            result = {}
            while True:
                skip()
                if text[pos] == "}":
                    pos += 1
                    return result
                key = value()
                skip()
                require(text[pos] == "=", f"pbxproj parse error near offset {pos}")
                pos += 1
                result[key] = value()
                skip()
                require(text[pos] == ";", f"pbxproj parse error near offset {pos}")
                pos += 1
        if char == "(":
            pos += 1
            result = []
            while True:
                skip()
                if text[pos] == ")":
                    pos += 1
                    return result
                result.append(value())
                skip()
                if text[pos] == ",":
                    pos += 1
        if char == '"':
            out, cursor = [], pos + 1
            while text[cursor] != '"':
                if text[cursor] == "\\":
                    out.append(text[cursor:cursor + 2])
                    cursor += 2
                else:
                    out.append(text[cursor])
                    cursor += 1
            pos = cursor + 1
            return "".join(out)
        match = _TOKEN.match(text, pos)
        require(match is not None, f"pbxproj parse error near offset {pos}")
        pos = match.end()
        return match.group(0)

    return value()


def load_objects(text):
    return parse_openstep(text.split("\n", 1)[1] if text.startswith("// !$*UTF8*$!") else text)["objects"]


def app_target(objects):
    found = [k for k, v in objects.items()
             if v.get("isa") == "PBXNativeTarget" and v.get("name") == APP_TARGET]
    require(len(found) == 1, f"expected exactly one native target named {APP_TARGET}")
    return found[0]


def embedded_products(objects, target_id):
    """(copy phase name, build file id, product path) for every file the App's copy phases embed."""
    rows = []
    for phase_id in objects[target_id]["buildPhases"]:
        phase = objects[phase_id]
        if phase.get("isa") != "PBXCopyFilesBuildPhase":
            continue
        for build_file in phase.get("files", []):
            ref = objects[build_file].get("fileRef") or objects[build_file].get("productRef")
            item = objects.get(ref, {})
            rows.append((phase.get("name", ""), build_file, ref,
                         item.get("path") or item.get("productName") or ""))
    return rows


def trim_plan(objects):
    """Return the App target's dependency ids and embed build-file ids to remove."""
    app = app_target(objects)
    drop_deps, dropped_products, kept = [], set(), []
    for dep in objects[app]["dependencies"]:
        target_id = objects[dep].get("target")
        if target_id is None:  # package product / plugin dependency: keep
            continue
        target = objects[target_id]
        if target.get("productType") in KEEP_PRODUCT_TYPES:
            kept.append(target["name"])
            continue
        drop_deps.append((dep, target["name"]))
        dropped_products.add(target.get("productReference"))
    drop_files = [(bf, path) for _, bf, ref, path in embedded_products(objects, app)
                  if ref in dropped_products]
    return app, drop_deps, drop_files, kept


def remove_list_item(text, object_id):
    pattern = re.compile(rf"^[ \t]*{object_id}(?: /\*[^\n]*?\*/)?,[ \t]*\n", re.M)
    hits = pattern.findall(text)
    require(len(hits) == 1, f"pbxproj: expected one list entry for {object_id}, found {len(hits)}")
    return pattern.sub("", text, count=1)


# --- apply / verify -------------------------------------------------------------------

def png_header(path):
    data = Path(path).read_bytes()[:33]
    require(data[:8] == b"\x89PNG\r\n\x1a\n" and data[12:16] == b"IHDR", f"{path} is not a PNG")
    width, height, _depth, color = struct.unpack(">IIBB", data[16:26])
    return width, height, color  # color 2 = RGB (no alpha), 6 = RGBA


def replace_dir(source, destination):
    if destination.exists():
        shutil.rmtree(destination)
    shutil.copytree(source, destination)


def apply(args):
    root = Path(args.root)
    team, prefix = args.team, args.prefix
    require(re.fullmatch(r"[A-Z0-9]{10}", team or ""), "APPLE_TEAM_ID must be a 10-character team id")
    require(re.fullmatch(r"[a-z0-9]+(\.[a-z0-9-]+)+", prefix or ""), "invalid bundle id prefix")

    (root / OVERRIDES).write_text(
        "// Written by Configuration/Khala/khala_ship.py for a Khala build; git-ignored.\n"
        f"DEVELOPMENT_TEAM = {team}\n"
        f"BUNDLE_ID_PREFIX = {prefix}\n")

    project = root / PBXPROJ
    text = project.read_text()
    _app, drop_deps, drop_files, _kept = trim_plan(load_objects(text))
    for dep, _name in drop_deps:
        text = remove_list_item(text, dep)
    for build_file, _path in drop_files:
        text = remove_list_item(text, build_file)
    project.write_text(text)
    for _dep, name in drop_deps:
        print(f"- App no longer builds/embeds {name}")

    entitlements_path = root / ENTITLEMENTS
    with entitlements_path.open("rb") as source:
        entitlements = plistlib.load(source)
    entitlements.pop(ASSOCIATED_DOMAINS, None)
    with entitlements_path.open("wb") as out:
        plistlib.dump(entitlements, out, sort_keys=False)

    info_path = root / INFO_PLIST
    with info_path.open("rb") as source:
        info = plistlib.load(source)
    info["CFBundleDisplayName"] = DISPLAY_NAME
    info["CFBundleName"] = DISPLAY_NAME
    with info_path.open("wb") as out:
        plistlib.dump(info, out, sort_keys=False)

    replace_dir(KHALA / "AppIcon/AppIcon.appiconset", root / APPICONSET)
    replace_dir(KHALA / "AppIcon/AppIcon.icon", root / ICON_COMPOSER)
    verify(args)


def verify(args):
    root = Path(args.root)
    overrides = (root / OVERRIDES).read_text()
    require(f"DEVELOPMENT_TEAM = {args.team}\n" in overrides and f"BUNDLE_ID_PREFIX = {args.prefix}\n" in overrides,
            "overrides xcconfig does not carry the Khala team/prefix")

    objects = load_objects((root / PBXPROJ).read_text())
    app, drop_deps, drop_files, kept = trim_plan(objects)
    require(not drop_deps and not drop_files, "App target still depends on/embeds non-framework targets")
    require("Shared-iOS" in kept, "App target lost its Shared-iOS framework dependency")
    leftovers = [path for _, _, _, path in embedded_products(objects, app)
                 if path.endswith((".appex", ".app"))]
    require(not leftovers, f"App still embeds {leftovers}")

    with (root / ENTITLEMENTS).open("rb") as source:
        entitlements = plistlib.load(source)
    require(ASSOCIATED_DOMAINS not in entitlements, "applinks associated domains are still requested")
    require(entitlements.get("com.apple.security.application-groups"),
            "App entitlements lost their app group (the app's database lives in it)")

    with (root / INFO_PLIST).open("rb") as source:
        info = plistlib.load(source)
    require(info.get("CFBundleDisplayName") == DISPLAY_NAME and info.get("CFBundleName") == DISPLAY_NAME,
            "display name is not Khala")
    require(info.get("ITSAppUsesNonExemptEncryption") is False, "export-compliance key changed upstream")

    iconset = json.loads((root / APPICONSET / "Contents.json").read_text())
    for image in iconset["images"]:
        width, height, color = png_header(root / APPICONSET / image["filename"])
        require((width, height, color) == (1024, 1024, 2), "app icon must be 1024x1024 RGB without alpha")
    icon = json.loads((root / ICON_COMPOSER / "icon.json").read_text())
    for group in icon["groups"]:
        for layer in group["layers"]:
            require((root / ICON_COMPOSER / "Assets" / layer["image-name"]).is_file(),
                    f"AppIcon.icon layer {layer['image-name']} is missing")
    summary(f"- Khala identity verified: team {args.team}, prefix {args.prefix}, display name {DISPLAY_NAME}, "
            f"App embeds frameworks only ({', '.join(kept)}), no applinks, Khala icon installed.")


# --- per-run xcodebuild inputs --------------------------------------------------------

def write_xcconfig(args):
    require(args.mode in ("cloud", "p12"), "signing mode must be cloud or p12")
    require(re.fullmatch(r"[0-9]+(\.[0-9]+){0,2}", args.version), "MARKETING_VERSION must be x[.y[.z]]")
    require(re.fullmatch(r"[1-9][0-9]*(\.[0-9]+){0,2}", args.build), "build number must be x[.y[.z]]")
    lines = [
        "// Per-run Khala signing/version overrides, written by khala_ship.py and passed with",
        "// `xcodebuild -xcconfig`, which outranks project, target and xcconfig-file settings.",
        f"DEVELOPMENT_TEAM = {args.team}",
        f"MARKETING_VERSION = {args.version}",
        f"CURRENT_PROJECT_VERSION = {args.build}",
        # Upstream ships ~20 HA-logo alternate icons; only Khala's primary icon goes in.
        "ASSETCATALOG_COMPILER_INCLUDE_ALL_APPICON_ASSETS = NO",
    ]
    if args.mode == "cloud":
        # Archive with automatic signing (Xcode creates the App ID capabilities, app group,
        # development certificate and profile through the API key); -exportArchive then
        # cloud-signs with the team's cloud-managed Apple Distribution certificate.
        style, identity, profile = "Automatic", "Apple Development", ""
    else:
        require(args.profile, "p12 signing needs the App Store profile name from prepare")
        # Only the App target gets a profile; frameworks and package targets resolve to empty.
        style, identity = "Manual", "Apple Distribution"
        profile = "$(KHALA_PROFILE_$(TARGET_NAME:c99extidentifier))"
        lines.append(f"KHALA_PROFILE_{APP_TARGET} = {args.profile}")
    for key, value in (("CODE_SIGN_STYLE", style), ("CODE_SIGN_IDENTITY", identity),
                       ("PROVISIONING_PROFILE_SPECIFIER", profile)):
        lines += [f"{key} = {value}", f"{key}[sdk=iphoneos*] = {value}"]
    Path(args.out).write_text("\n".join(lines) + "\n")


def export_options(args):
    options = {"method": "app-store-connect", "destination": "export", "teamID": args.team,
               "uploadSymbols": True, "stripSwiftSymbols": True,
               "manageAppVersionAndBuildNumber": False}
    if args.mode == "cloud":
        options["signingStyle"] = "automatic"
    else:
        require(args.profile and args.bundle_id, "p12 export needs the bundle id and profile name")
        options.update(signingStyle="manual", signingCertificate="Apple Distribution",
                       provisioningProfiles={args.bundle_id: args.profile})
    with open(args.out, "wb") as out:
        plistlib.dump(options, out)


# --- App Store Connect preflight (Linux) ----------------------------------------------

class AppStoreConnect:
    BASE = "https://api.appstoreconnect.apple.com"

    def __init__(self, env):
        import jwt  # PyJWT[crypto], installed by the prepare job only

        names = ("APP_STORE_CONNECT_KEY_ID", "APP_STORE_CONNECT_ISSUER_ID", "APP_STORE_CONNECT_PRIVATE_KEY")
        missing = [n for n in names if not env.get(n)]
        require(not missing, "missing App Store Connect configuration: " + ", ".join(missing))
        now = int(time.time())
        try:
            self.token = jwt.encode({"iss": env["APP_STORE_CONNECT_ISSUER_ID"], "iat": now,
                                     "exp": now + 19 * 60, "aud": "appstoreconnect-v1"},
                                    env["APP_STORE_CONNECT_PRIVATE_KEY"], algorithm="ES256",
                                    headers={"kid": env["APP_STORE_CONNECT_KEY_ID"], "typ": "JWT"})
        except Exception as exc:
            fail(f"could not sign an App Store Connect token ({type(exc).__name__}); check the .p8 secret")

    def call(self, path, method="GET", body=None):
        url = path if path.startswith("https://") else self.BASE + path
        require(urllib.parse.urlsplit(url).netloc == "api.appstoreconnect.apple.com", "unexpected Apple host")
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(url, data=data, method=method, headers={
            "Authorization": f"Bearer {self.token}", "Accept": "application/json",
            **({"Content-Type": "application/json"} if data else {})})
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                raw = response.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            hint = {401: " (key id, issuer id or .p8 rejected)",
                    403: " (the API key needs the Admin role)"}.get(exc.code, "")
            fail(f"App Store Connect {method} {urllib.parse.urlsplit(url).path} -> HTTP {exc.code}{hint}")
        except (OSError, ValueError) as exc:
            fail(f"App Store Connect request failed ({type(exc).__name__})")

    def all(self, path):
        result = {"data": [], "included": []}
        while path:
            page = self.call(path)
            for key in result:
                result[key].extend(page.get(key, []))
            path = page.get("links", {}).get("next")
        return result


def usable_profiles(response, bundle, cert_id, now):
    included = {(x["type"], x["id"]): x for x in response.get("included", [])}
    found = []
    for profile in response.get("data", []):
        attrs, rel = profile["attributes"], profile.get("relationships", {})
        bid = rel.get("bundleId", {}).get("data") or {}
        identifier = included.get(("bundleIds", bid.get("id")), {}).get("attributes", {}).get("identifier")
        certs = {x["id"] for x in rel.get("certificates", {}).get("data", [])}
        expiry = datetime.fromisoformat(attrs["expirationDate"].replace("Z", "+00:00"))
        if identifier == bundle and attrs["profileState"] == "ACTIVE" and expiry > now and cert_id in certs:
            found.append(profile)
    return sorted(found, key=lambda p: p["attributes"]["expirationDate"], reverse=True)


def p12_certificate_der(env):
    from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat, pkcs12

    require(env.get("APPSTORE_DIST_P12_BASE64") and env.get("APPSTORE_DIST_P12_PASSWORD"),
            "signing=p12 needs the APPSTORE_DIST_P12_BASE64 and APPSTORE_DIST_P12_PASSWORD secrets")
    try:
        key, cert, _ = pkcs12.load_key_and_certificates(
            base64.b64decode(env["APPSTORE_DIST_P12_BASE64"]), env["APPSTORE_DIST_P12_PASSWORD"].encode())
    except Exception as exc:
        fail(f"could not open the distribution P12 ({type(exc).__name__})")
    require(key is not None and cert is not None, "the P12 must contain the certificate and its private key")
    require(key.public_key().public_bytes(Encoding.DER, PublicFormat.SubjectPublicKeyInfo) ==
            cert.public_key().public_bytes(Encoding.DER, PublicFormat.SubjectPublicKeyInfo),
            "the P12 certificate does not match its private key")
    return cert.public_bytes(Encoding.DER)


def asc(args):
    env = os.environ
    apple = AppStoreConnect(env)
    bundle, read_only = args.bundle_id, args.read_only
    now = datetime.now(timezone.utc)

    query = urllib.parse.urlencode({"filter[identifier]": bundle, "limit": 200,
                                    "fields[bundleIds]": "identifier,name,platform"})
    bundles = [b for b in apple.all(f"/v1/bundleIds?{query}")["data"] if b["attributes"]["identifier"] == bundle]
    if bundles:
        summary(f"- Bundle ID {bundle} is registered.")
    else:
        # Registering it here (idempotent, harmless) lets Nir create the App Store Connect
        # record before the first macOS minute is spent.
        apple.call("/v1/bundleIds", "POST", {"data": {"type": "bundleIds", "attributes": {
            "identifier": bundle, "name": DISPLAY_NAME, "platform": "IOS"}}})
        summary(f"- Registered bundle ID {bundle} (name {DISPLAY_NAME}).")

    apps = apple.call("/v1/apps?" + urllib.parse.urlencode({"filter[bundleId]": bundle, "fields[apps]": "name,bundleId"}))
    apps = [a for a in apps.get("data", []) if a["attributes"]["bundleId"] == bundle]
    require(apps, f"no App Store Connect app record for {bundle}. Create it once: App Store Connect > Apps > + > "
                  f"New App, platform iOS, a unique name (e.g. Khala), bundle ID {bundle}, any SKU (e.g. khala). "
                  "Then dispatch again.")
    summary(f"- App Store Connect record: {apps[0]['attributes']['name']} ({apps[0]['id']}).")

    if args.mode == "cloud":
        devices = apple.call("/v1/devices?filter[platform]=IOS&filter[status]=ENABLED&limit=1")
        total = devices.get("meta", {}).get("paging", {}).get("total", len(devices.get("data", [])))
        # Automatic signing archives with a development profile, and Apple will not issue one
        # for a team that has no registered iOS device.
        require(total > 0, "the team has no enabled iOS device; automatic signing cannot create the development "
                           "profile used for the archive. Register one device (any iPhone UDID) under "
                           "Certificates, Identifiers & Profiles > Devices, or use signing=p12.")
        summary(f"- {total} enabled iOS device(s) registered.")
        certs = apple.all("/v1/certificates?filter[certificateType]=DEVELOPMENT,IOS_DEVELOPMENT&limit=200"
                          "&fields[certificates]=name,displayName,certificateType,expirationDate")["data"]
        # Each CI archive makes Xcode create an "Created via API" development certificate whose
        # private key dies with the runner; the next run then refuses to create another
        # ("already has an Apple Development signing certificate for this machine"). Only these
        # key-less CI certificates are revoked, never a person's own certificates.
        stale = [c for c in certs if "Created via API" in
                 f"{c['attributes'].get('name', '')} {c['attributes'].get('displayName', '')}"]
        if read_only:
            summary(f"- {len(stale)} stale CI development certificate(s) would be revoked by a build run.")
        else:
            for cert in stale:
                apple.call(f"/v1/certificates/{cert['id']}", "DELETE")
            summary(f"- Revoked {len(stale)} stale CI development certificate(s) (\"Created via API\").")
        return

    der = p12_certificate_der(env)
    certs = apple.all("/v1/certificates?limit=200&filter[certificateType]=DISTRIBUTION,IOS_DISTRIBUTION"
                      "&fields[certificates]=certificateContent,expirationDate")["data"]
    cert = next((c for c in certs if base64.b64decode(c["attributes"].get("certificateContent", "")) == der
                 and datetime.fromisoformat(c["attributes"]["expirationDate"].replace("Z", "+00:00")) > now), None)
    require(cert is not None, "the P12 distribution certificate is not active in this Apple team")
    profiles = apple.all("/v1/profiles?limit=200&filter[profileType]=IOS_APP_STORE&include=bundleId,certificates"
                         "&fields[profiles]=name,profileState,expirationDate,bundleId,certificates"
                         "&fields[bundleIds]=identifier&fields[certificates]=name")
    usable = usable_profiles(profiles, bundle, cert["id"], now)
    require(usable, f"no ACTIVE App Store profile for {bundle} containing the P12 certificate; create one in "
                    "Certificates, Identifiers & Profiles > Profiles (App Store Connect distribution)")
    name = usable[0]["attributes"]["name"]
    emit("profile_name", name)
    summary(f"- P12 certificate active; App Store profile \"{name}\" selected.")


# --- exported IPA check (Linux) -------------------------------------------------------

def verify_ipa(args):
    with zipfile.ZipFile(args.ipa) as ipa:
        names = ipa.namelist()
        apps = sorted({n.split("/")[1] for n in names if n.startswith("Payload/") and n.count("/") >= 2
                       and n.split("/")[1].endswith(".app")})
        require(len(apps) == 1, f"expected one app in the IPA, found {apps}")
        app = f"Payload/{apps[0]}/"
        info = plistlib.loads(ipa.read(app + "Info.plist"))
        nested = [n for n in names if n.startswith(app) and (n.startswith(app + "PlugIns/") or n.startswith(app + "Watch/"))]
        profile = ipa.read(app + "embedded.mobileprovision")
    expected = {"CFBundleIdentifier": args.bundle_id, "CFBundleShortVersionString": args.version,
                "CFBundleVersion": args.build, "CFBundleDisplayName": DISPLAY_NAME}
    for key, value in expected.items():
        require(info.get(key) == value, f"packaged app: {key} is {info.get(key)!r}, expected {value!r}")
    require(not nested, "packaged app still contains extensions or a watch app")
    match = re.search(rb"<\?xml.*?</plist>", profile, re.S)
    require(match is not None, "embedded.mobileprovision carries no readable plist")
    provision = plistlib.loads(match.group(0))
    entitlements = provision.get("Entitlements", {})
    require(entitlements.get("application-identifier") == f"{args.team}.{args.bundle_id}",
            "embedded profile is for a different app or team")
    require(not provision.get("ProvisionedDevices") and entitlements.get("get-task-allow") is not True,
            "embedded profile is not an App Store distribution profile")
    summary(f"- Packaged IPA verified: {args.bundle_id} {args.version} ({args.build}), display name "
            f"{DISPLAY_NAME}, no extensions, App Store profile \"{provision.get('Name')}\".")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("apply", "verify"):
        command = commands.add_parser(name)
        command.add_argument("--team", required=True)
        command.add_argument("--prefix", required=True)
        command.add_argument("--root", default=str(ROOT))
    command = commands.add_parser("xcconfig")
    for flag in ("--mode", "--team", "--version", "--build", "--out"):
        command.add_argument(flag, required=True)
    command.add_argument("--profile", default="")
    command = commands.add_parser("export-options")
    for flag in ("--mode", "--team", "--out"):
        command.add_argument(flag, required=True)
    command.add_argument("--bundle-id", default="")
    command.add_argument("--profile", default="")
    command = commands.add_parser("asc")
    command.add_argument("--mode", choices=("cloud", "p12"), required=True)
    command.add_argument("--bundle-id", required=True)
    command.add_argument("--read-only", action="store_true")
    command = commands.add_parser("verify-ipa")
    for flag in ("--ipa", "--team", "--bundle-id", "--version", "--build"):
        command.add_argument(flag, required=True)
    args = parser.parse_args()
    {"apply": apply, "verify": verify, "xcconfig": write_xcconfig, "export-options": export_options,
     "asc": asc, "verify-ipa": verify_ipa}[args.command](args)


if __name__ == "__main__":
    main()
