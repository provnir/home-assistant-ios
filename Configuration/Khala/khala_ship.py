"""Khala build identity and release helper (Nir's fork of the Home Assistant iOS app).

Everything that turns this upstream checkout into the "Khala" TestFlight build lives here,
applied at build time to a disposable CI checkout, so no upstream-tracked file has to carry
a fork-only edit (rebases onto upstream stay conflict-free):

  apply        write the git-ignored overrides xcconfig (team + bundle prefix), drop every
               app extension / watch app / mac launcher from the App target's dependencies
               and embed phases, strip applinks associated domains, set the display name,
               install the Khala icon over the upstream one, and keep Siri vocabulary for
               intents the trimmed app no longer supports out of the App bundle. Idempotent.
  verify       assert that `apply` produced exactly that (runs on Linux before any macOS
               minute is spent, and again on macOS before archiving).
  xcconfig     write the per-run signing/version xcconfig passed to `xcodebuild -xcconfig`.
  export-options  write ExportOptions.plist for `xcodebuild -exportArchive`.
  asc          App Store Connect preflight on Linux (needs PyJWT[crypto]); in manual mode it also
               enables the App ID capabilities and creates/refreshes the App Store profile.
  cert         one-time bootstrap: create (or find) the Apple Distribution certificate for a CSR
               whose private key never leaves the VPS, and print the public certificate.
  processing   after the upload, poll App Store Connect until the build is VALID or INVALID.
  verify-ipa   check the exported IPA's Info.plist and embedded profile on Linux, and guard against
               App Store processing rejections the trim could cause (Siri vocabulary/intents,
               extension/watch leftovers, purpose strings) before anything is uploaded.

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


def remove_entry_in_object(text, object_id, entry):
    """Remove one list entry (e.g. a membership exception path) inside one object's block only."""
    block = re.compile(rf"^([ \t]*){object_id}(?: /\*[^\n]*?\*/)? = \{{\n.*?^\1\}};\n", re.M | re.S)
    match = block.search(text)
    require(match is not None, f"pbxproj: object {object_id} not found as a block")
    line = re.compile(rf'^[ \t]*"?{re.escape(entry)}"?,[ \t]*\n', re.M)
    body, hits = line.subn("", match.group(0))
    require(hits == 1, f"pbxproj: expected one entry {entry} in {object_id}, found {hits}")
    return text[:match.start()] + body + text[match.end():]


# --- Siri vocabulary ------------------------------------------------------------------
# App Store processing rejects (ITMS-90626) a bundle whose AppIntentVocabulary.plist has
# phrases for an intent nothing in the app supports. Upstream copies the Intents extension's
# vocabulary (INShareFocusStatusIntent) into the App too; with that extension trimmed, the
# only Siri intents left are the App's own Info.plist INIntentsSupported.

VOCABULARY = "AppIntentVocabulary.plist"


def project_paths(objects, project):
    """Repo-relative path of every group / file reference reachable from the main group."""
    paths, stack = {}, [(objects[project]["mainGroup"], "")]
    while stack:
        node_id, parent = stack.pop()
        node = objects.get(node_id, {})
        tree, path = node.get("sourceTree", "<group>"), node.get("path", "")
        if tree == "<group>":
            here = f"{parent}/{path}".strip("/") if path else parent
        elif tree == "SOURCE_ROOT":
            here = path
        else:
            continue
        paths[node_id] = here
        stack.extend((child, here) for child in node.get("children", []))
    return paths


def vocabulary_files(root, group_dir, entry):
    """Files a synchronized-group entry names; "/Localized/<dir>/<file>" means every <dir>/*.lproj/<file>."""
    if entry.startswith("/Localized/"):
        rel = Path(entry[len("/Localized/"):])
        return sorted((root / group_dir / rel.parent).glob(f"*.lproj/{rel.name}"))
    return [root / group_dir / entry] if (root / group_dir / entry).is_file() else []


def vocabulary_intents(path):
    """Intent names a vocabulary file refers to (phrases and parameter vocabularies)."""
    with open(path, "rb") as source:
        data = plistlib.load(source)
    names = {p.get("IntentName") for p in data.get("IntentPhrases", []) if p.get("IntentName")}
    for vocabulary in data.get("ParameterVocabularies", []):
        names |= {n.split(".", 1)[0] for n in vocabulary.get("ParameterNames", [])}
    return names


def app_intents_supported(root):
    with (root / INFO_PLIST).open("rb") as source:
        return set(plistlib.load(source).get("INIntentsSupported", []))


def vocabulary_routes(objects, root):
    """Every way an AppIntentVocabulary.plist reaches the App target, with the files it brings:
    ("added", exception set, entry, files)  App exception in a synchronized group the App does not own
    ("synced", group, None, files)          a synchronized group the App owns (minus its exclusions)
    ("phase", build file, None, files)      an explicit Copy Bundle Resources entry
    """
    project = next(k for k, v in objects.items() if v.get("isa") == "PBXProject")
    paths, app = project_paths(objects, project), app_target(objects)
    owned = set(objects[app].get("fileSystemSynchronizedGroups", []))
    routes = []
    for group_id, group in objects.items():
        if group.get("isa") != "PBXFileSystemSynchronizedRootGroup" or group_id not in paths:
            continue
        group_dir = paths[group_id]
        app_sets = [e for e in group.get("exceptions", []) if objects[e].get("target") == app]
        listed = [(e, entry) for e in app_sets for entry in objects[e].get("membershipExceptions", [])]
        if group_id in owned:  # exceptions are exclusions
            excluded = {f for _, entry in listed for f in vocabulary_files(root, group_dir, entry)}
            files = [f for f in sorted((root / group_dir).rglob(VOCABULARY)) if f not in excluded]
            if files:
                routes.append(("synced", group_id, None, files))
        else:  # exceptions are additions
            routes += [("added", e, entry, vocabulary_files(root, group_dir, entry))
                       for e, entry in listed if entry.rsplit("/", 1)[-1] == VOCABULARY]
    for phase_id in objects[app]["buildPhases"]:
        if objects[phase_id].get("isa") != "PBXResourcesBuildPhase":
            continue
        for build_file in objects[phase_id].get("files", []):
            ref = objects[build_file].get("fileRef")
            item = objects.get(ref, {})
            refs = item.get("children", []) if item.get("isa") == "PBXVariantGroup" else [ref]
            files = [root / paths[r] for r in refs if r in paths and paths[r].endswith(VOCABULARY)]
            if files:
                routes.append(("phase", build_file, None, files))
    return routes


def unsupported_vocabulary(objects, root):
    supported = app_intents_supported(root)
    rows = []
    for kind, holder, entry, files in vocabulary_routes(objects, root):
        extra = sorted({n for f in files for n in vocabulary_intents(f)} - supported)
        if extra:
            rows.append((kind, holder, entry, files, extra))
    return rows


def strip_vocabulary(path, supported):
    with open(path, "rb") as source:
        data = plistlib.load(source)
    data["IntentPhrases"] = [p for p in data.get("IntentPhrases", []) if p.get("IntentName") in supported]
    data["ParameterVocabularies"] = [v for v in data.get("ParameterVocabularies", [])
                                     if all(n.split(".", 1)[0] in supported for n in v.get("ParameterNames", []))]
    data = {k: v for k, v in data.items() if v != []}
    with open(path, "wb") as out:
        plistlib.dump(data, out, sort_keys=False)


def trim_vocabulary(text, root):
    """Keep Siri vocabulary for intents the trimmed App does not support out of the App bundle."""
    objects = load_objects(text)
    supported = app_intents_supported(root)
    for kind, holder, entry, files, extra in unsupported_vocabulary(objects, root):
        if kind == "added":
            # Preferred: the App simply stops copying it (the files stay untouched).
            text = remove_entry_in_object(text, holder, entry)
            summary(f"- Siri vocabulary: App no longer copies {entry} ({len(files)} localizations; phrases for "
                    f"{', '.join(extra)}, which the trimmed app does not support; INIntentsSupported is "
                    f"{', '.join(sorted(supported)) or 'empty'}).")
        else:
            # Fallback: the file is part of an App-owned folder or a build phase, so it must keep
            # existing; only the phrases for unsupported intents go.
            for path in files:
                strip_vocabulary(path, supported)
            summary(f"- Siri vocabulary: stripped phrases for {', '.join(extra)} from {len(files)} "
                    f"{VOCABULARY} file(s) the App ships ({kind} membership).")
    return text


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
    text = trim_vocabulary(text, root)
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
    stray = [f"{entry or holder}: {extra}" for _, holder, entry, _, extra in unsupported_vocabulary(objects, root)]
    require(not stray, f"App still ships Siri vocabulary for intents it does not support (ITMS-90626): {stray}")

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
            f"App embeds frameworks only ({', '.join(kept)}), no Siri vocabulary for unsupported intents, "
            "no applinks, Khala icon installed.")


# --- per-run xcodebuild inputs --------------------------------------------------------

def write_xcconfig(args):
    require(args.mode in ("cloud", "manual", "unsigned"), "signing mode must be manual, cloud or unsigned")
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
    if args.mode == "unsigned":
        # Compile-only check: nothing is signed, exported or uploaded.
        lines += ["CODE_SIGNING_ALLOWED = NO", "CODE_SIGNING_REQUIRED = NO", "CODE_SIGN_IDENTITY = ",
                  "CODE_SIGN_STYLE = Manual", "PROVISIONING_PROFILE_SPECIFIER = "]
        Path(args.out).write_text("\n".join(lines) + "\n")
        return
    if args.mode == "cloud":
        # Archive with automatic signing (Xcode creates the App ID capabilities, app group,
        # development certificate and profile through the API key); -exportArchive then
        # cloud-signs with the team's cloud-managed Apple Distribution certificate.
        style, identity, profile = "Automatic", "Apple Development", ""
    else:
        require(args.profile, "manual signing needs the App Store profile UUID from prepare")
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
        require(args.profile and args.bundle_id, "manual export needs the bundle id and profile UUID")
        options.update(signingStyle="manual", signingCertificate="Apple Distribution",
                       provisioningProfiles={args.bundle_id: args.profile})
    with open(args.out, "wb") as out:
        plistlib.dump(options, out)


# --- App Store Connect preflight (Linux) ----------------------------------------------

def _apple_error_codes(exc):
    """Apple's error codes/titles only (never the request or the whole body)."""
    try:
        errors = json.loads(exc.read() or b"{}").get("errors", [])
    except (OSError, ValueError):
        return []
    return [f"{e.get('code', '')}: {e.get('title', '')}"[:160] for e in errors[:3]]


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

    def call(self, path, method="GET", body=None, soft=False):
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
            if soft:
                return {"_status": exc.code, "_errors": _apple_error_codes(exc)}
            hint = {401: " (key id, issuer id or .p8 rejected)",
                    403: " (the API key needs the Admin role)"}.get(exc.code, "")
            codes = "; ".join(_apple_error_codes(exc))
            fail(f"App Store Connect {method} {urllib.parse.urlsplit(url).path} -> HTTP {exc.code}{hint}"
                 + (f" [{codes}]" if codes else ""))
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
            "signing=manual needs the APPSTORE_DIST_P12_BASE64 and APPSTORE_DIST_P12_PASSWORD secrets")
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

    if args.mode == "unsigned":
        return
    if args.mode == "cloud":
        devices = apple.call("/v1/devices?filter[platform]=IOS&filter[status]=ENABLED&limit=1")
        total = devices.get("meta", {}).get("paging", {}).get("total", len(devices.get("data", [])))
        # Automatic signing archives with a development profile, and Apple will not issue one
        # for a team that has no registered iOS device.
        require(total > 0, "the team has no enabled iOS device; automatic signing cannot create the development "
                           "profile used for the archive. Register one device (any iPhone UDID) under "
                           "Certificates, Identifiers & Profiles > Devices, or use signing=manual.")
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

    manual_signing(apple, env, bundle, bundles, read_only, now)


# --- manual signing: App ID capabilities, App Store profile, distribution certificate ----

PROFILE_NAME = "Khala App Store CI"
# Entitlement the App target asks for -> App ID capability that puts it in the profile.
# keychain-access-groups needs none (every profile carries <team>.*).
CAPABILITY_FOR = {
    "aps-environment": "PUSH_NOTIFICATIONS",
    "com.apple.developer.healthkit": "HEALTHKIT",
    "com.apple.developer.healthkit.background-delivery": "HEALTHKIT",
    "com.apple.developer.networking.wifi-info": "ACCESS_WIFI_INFORMATION",
    "com.apple.developer.nfc.readersession.formats": "NFC_TAG_READING",
    "com.apple.developer.siri": "SIRIKIT",
    "com.apple.developer.usernotifications.communication": "USERNOTIFICATIONS_COMMUNICATION",
    "com.apple.developer.usernotifications.time-sensitive": "USERNOTIFICATIONS_TIMESENSITIVE",
    "com.apple.security.application-groups": "APP_GROUPS",
    "keychain-access-groups": None,
}


def requested_entitlements(prefix):
    """The App target's entitlements as `apply` left them, with the app group resolved."""
    with (ROOT / ENTITLEMENTS).open("rb") as source:
        entitlements = plistlib.load(source)
    unknown = sorted(set(entitlements) - set(CAPABILITY_FOR))
    require(not unknown, f"App entitlements gained {unknown}: map them in khala_ship.py CAPABILITY_FOR")
    groups = [g.replace("$(BUNDLE_ID_PREFIX)", prefix).replace("$(BUNDLE_ID_SUFFIX)", "")
              for g in entitlements.get("com.apple.security.application-groups", [])]
    return entitlements, groups


def profile_entitlements(profile_b64):
    match = re.search(rb"<\?xml.*?</plist>", base64.b64decode(profile_b64), re.S)
    require(match is not None, "the App Store profile carries no readable plist")
    return plistlib.loads(match.group(0))


def profile_gaps(provision, entitlements, groups):
    granted = provision.get("Entitlements", {})
    missing = [key for key, capability in CAPABILITY_FOR.items()
               if capability and key in entitlements and key not in granted]
    missing_groups = [g for g in groups if g not in granted.get("com.apple.security.application-groups", [])]
    return missing, missing_groups


def manual_signing(apple, env, bundle, bundles, read_only, now):
    prefix = env.get("BUNDLE_ID_PREFIX") or bundle.rsplit(".", 1)[0]
    entitlements, groups = requested_entitlements(prefix)
    der = p12_certificate_der(env)
    certs = apple.all("/v1/certificates?limit=200&filter[certificateType]=DISTRIBUTION,IOS_DISTRIBUTION"
                      "&fields[certificates]=certificateContent,expirationDate,certificateType")["data"]
    cert = next((c for c in certs if base64.b64decode(c["attributes"].get("certificateContent", "")) == der
                 and datetime.fromisoformat(c["attributes"]["expirationDate"].replace("Z", "+00:00")) > now), None)
    require(cert is not None, "the P12 distribution certificate is not active in this Apple team "
                              "(bootstrap it: dispatch with bootstrap_csr, see SHIP.md)")
    summary(f"- Distribution certificate {cert['id']} ({cert['attributes']['certificateType']}) matches the P12.")

    if not bundles:  # registered moments ago by asc()
        query = urllib.parse.urlencode({"filter[identifier]": bundle, "fields[bundleIds]": "identifier"})
        bundles = [b for b in apple.call(f"/v1/bundleIds?{query}")["data"] if b["attributes"]["identifier"] == bundle]
    bundle_id = bundles[0]["id"]
    app_id = apple.call(f"/v1/bundleIds/{bundle_id}?include=bundleIdCapabilities")
    have = {c["attributes"].get("capabilityType") for c in app_id.get("included", [])
            if c.get("type") == "bundleIdCapabilities"}
    summary(f"- App ID capabilities on: {', '.join(sorted(have)) or 'none'}.")
    wanted = sorted({CAPABILITY_FOR[k] for k in entitlements if CAPABILITY_FOR.get(k)})
    for capability in [c for c in wanted if c not in have]:
        if read_only:
            summary(f"- App ID capability {capability} is off (a build run enables it).")
            continue
        result = apple.call("/v1/bundleIdCapabilities", "POST", {"data": {
            "type": "bundleIdCapabilities", "attributes": {"capabilityType": capability},
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_id}}}}}, soft=True)
        if "_status" in result:
            summary(f"- Could not enable {capability} on the App ID (HTTP {result['_status']}: "
                    f"{'; '.join(result['_errors'])}).")
        else:
            summary(f"- Enabled App ID capability {capability}.")

    # Our own CI profile only (by name); a person's profiles are never touched.
    profiles = apple.all("/v1/profiles?limit=200&filter[profileType]=IOS_APP_STORE"
                         f"&filter[name]={urllib.parse.quote(PROFILE_NAME)}&include=bundleId,certificates"
                         "&fields[profiles]=name,profileState,expirationDate,bundleId,certificates,profileContent,uuid"
                         "&fields[bundleIds]=identifier&fields[certificates]=name")
    ours = [p for p in profiles["data"] if p["attributes"]["name"] == PROFILE_NAME]
    profile = next(iter(usable_profiles({**profiles, "data": ours}, bundle, cert["id"], now)), None)
    if profile is not None:
        missing, missing_groups = profile_gaps(profile_entitlements(profile["attributes"]["profileContent"]),
                                               entitlements, groups)
        if missing or missing_groups:
            summary(f"- Profile \"{PROFILE_NAME}\" lacks {missing + missing_groups}; recreating it.")
            profile = None
    if profile is None:
        require(not read_only, f"no current \"{PROFILE_NAME}\" profile; a build run (not preflight_only) creates it")
        for stale in ours:
            apple.call(f"/v1/profiles/{stale['id']}", "DELETE")
        profile = apple.call("/v1/profiles", "POST", {"data": {
            "type": "profiles", "attributes": {"name": PROFILE_NAME, "profileType": "IOS_APP_STORE"},
            "relationships": {"bundleId": {"data": {"type": "bundleIds", "id": bundle_id}},
                              "certificates": {"data": [{"type": "certificates", "id": cert["id"]}]}}}})["data"]
        summary(f"- Created App Store profile \"{PROFILE_NAME}\" ({profile['attributes']['uuid']}).")
    content = profile["attributes"]["profileContent"]
    missing, missing_groups = profile_gaps(profile_entitlements(content), entitlements, groups)
    steps = []
    if missing_groups:
        steps.append(f"the app group {', '.join(missing_groups)} (the App Store Connect API cannot create or assign "
                     "app groups): Identifiers > + > App Groups > register it; then Identifiers > "
                     f"{bundle} > App Groups > Configure > tick it > Save")
    if missing:
        steps.append(f"entitlements {missing}: on Identifiers > {bundle}, tick the matching capabilities "
                     f"({', '.join(sorted({CAPABILITY_FOR[k] for k in missing}))}) > Save")
    require(not steps, "the App Store profile lacks " + "; and ".join(steps) + ". Once, in Certificates, "
            "Identifiers & Profiles; then dispatch again (the profile is recreated automatically).")
    emit("profile_uuid", profile["attributes"]["uuid"])
    emit("profile_b64", content)
    summary(f"- App Store profile \"{PROFILE_NAME}\" ({profile['attributes']['uuid']}) covers every App "
            f"entitlement, app group {', '.join(groups)} included.")


def bootstrap_certificate(args):
    """Create or find the Apple Distribution certificate for a CSR made on the VPS (public data only)."""
    from cryptography import x509
    from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

    csr_b64 = re.sub(r"-----[A-Z ]+-----|\s", "", os.environ.get("KHALA_CSR", ""))
    try:
        csr = x509.load_der_x509_csr(base64.b64decode(csr_b64, validate=True))
    except Exception as exc:
        fail(f"bootstrap_csr is not a base64 DER/PEM certificate signing request ({type(exc).__name__})")
    require(csr.is_signature_valid, "the CSR signature is invalid")
    spki = csr.public_key().public_bytes(Encoding.DER, PublicFormat.SubjectPublicKeyInfo)
    apple = AppStoreConnect(os.environ)
    now = datetime.now(timezone.utc)
    certs = apple.all("/v1/certificates?limit=200&filter[certificateType]=DISTRIBUTION,IOS_DISTRIBUTION"
                      "&fields[certificates]=name,certificateContent,expirationDate,certificateType")["data"]
    mine = None
    for item in certs:
        cert = x509.load_der_x509_certificate(base64.b64decode(item["attributes"]["certificateContent"]))
        if cert.public_key().public_bytes(Encoding.DER, PublicFormat.SubjectPublicKeyInfo) == spki and \
                datetime.fromisoformat(item["attributes"]["expirationDate"].replace("Z", "+00:00")) > now:
            mine = item
    if mine is not None:
        summary(f"- Reusing distribution certificate {mine['id']} already issued for this key.")
    else:
        result = apple.call("/v1/certificates", "POST", {"data": {"type": "certificates", "attributes": {
            "certificateType": "DISTRIBUTION", "csrContent": csr_b64}}}, soft=True)
        require("_status" not in result,
                f"Apple refused a new distribution certificate (HTTP {result.get('_status')}: "
                f"{'; '.join(result.get('_errors', []))}); the team has {len(certs)} distribution certificate(s), "
                "Apple allows only a few. Nothing was revoked; free a slot by hand if this is the limit.")
        mine = result["data"]
        summary(f"- Created Apple Distribution certificate {mine['id']}.")
    attrs = mine["attributes"]
    summary(f"- Expires {attrs['expirationDate']}. Public certificate (DER, base64) for the VPS p12 step:")
    summary(f"KHALA_DIST_CERT_B64={attrs['certificateContent']}")


# --- exported IPA check (Linux) -------------------------------------------------------

# Usage-description keys App Store processing (ITMS-90683) asks for when a binary links the
# framework. Only frameworks whose APIs need exactly these keys; "any of" where one suffices.
PURPOSE_KEYS = {
    "HealthKit": ("NSHealthShareUsageDescription", "NSHealthUpdateUsageDescription"),
    "CoreMotion": ("NSMotionUsageDescription",),
    "Speech": ("NSSpeechRecognitionUsageDescription",),
    "CoreBluetooth": ("NSBluetoothAlwaysUsageDescription",),
    "CoreNFC": ("NFCReaderUsageDescription",),
    "CoreLocation": ("NSLocationWhenInUseUsageDescription",),
    "HomeKit": ("NSHomeKitUsageDescription",),
    "AppTrackingTransparency": ("NSUserTrackingUsageDescription",),
}  # Contacts is linked by Shared without a purpose string and Apple accepts it: not checked.
PURPOSE_ANY = {
    "EventKit": ("NSRemindersUsageDescription", "NSRemindersFullAccessUsageDescription",
                 "NSCalendarsUsageDescription", "NSCalendarsFullAccessUsageDescription"),
    "Photos": ("NSPhotoLibraryUsageDescription", "NSPhotoLibraryAddUsageDescription"),
}
WATCH_KEYS = ("WKCompanionAppBundleIdentifier", "WKWatchKitApp", "WKApplication", "WKAppBundleIdentifier",
              "WKRunsIndependentlyOfCompanionApp", "WKWatchOnly")
LOAD_DYLIB_COMMANDS = {0xC, 0x80000018, 0x8000001F, 0x20, 0x80000023}


def linked_frameworks(binary):
    """System framework names a Mach-O (thin or universal) loads."""
    slices = [0]
    if binary[:4] in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):  # fat, big-endian header
        count, wide = struct.unpack(">I", binary[4:8])[0], binary[3] == 0xBF
        step = 32 if wide else 20
        slices = [struct.unpack(">Q" if wide else ">I",
                                binary[8 + i * step + 8: 8 + i * step + (16 if wide else 12)])[0]
                  for i in range(count)]
    names = set()
    for base in slices:
        if binary[base:base + 4] != b"\xcf\xfa\xed\xfe":  # MH_MAGIC_64, little-endian
            continue
        ncmds = struct.unpack_from("<I", binary, base + 16)[0]
        cursor = base + 32
        for _ in range(ncmds):
            cmd, size = struct.unpack_from("<II", binary, cursor)
            if cmd in LOAD_DYLIB_COMMANDS:
                offset = struct.unpack_from("<I", binary, cursor + 8)[0]
                raw = binary[cursor + offset: cursor + size].split(b"\0", 1)[0].decode(errors="replace")
                match = re.search(r"/System/Library/(?:Private)?Frameworks/([^/]+)\.framework/", raw)
                if match:
                    names.add(match.group(1))
            cursor += size
    return names


def store_checks(ipa, app, names, info):
    """App Store processing rejections our target trim could cause, checked from the IPA alone.
    Returns (problems, what was checked)."""
    problems = []
    # Extensions/watch: none may remain, and the App must not claim to be one.
    leftovers = sorted({n[len(app):].split("/", 1)[0] for n in names if n.startswith(app) and
                        n[len(app):].split("/", 1)[0] in ("PlugIns", "Extensions", "Watch", "AppClips")})
    if leftovers:
        problems.append(f"bundle still contains {leftovers}")
    stray = sorted(k for k in info if k.startswith("NSExtension") or k in WATCH_KEYS)
    if stray:
        problems.append(f"app Info.plist carries extension/watch keys {stray}")

    # Siri (ITMS-90626): every intent named in vocabulary or restrictions must be supported, and
    # with no extensions left only the App's own INIntentsSupported counts.
    supported = set(info.get("INIntentsSupported", []))
    for key in ("INIntentsRestrictedWhileLocked", "INIntentsRestrictedWhileProtectedDataUnavailable"):
        extra = sorted(set(info.get(key, [])) - supported)
        if extra:
            problems.append(f"{key} names unsupported intents {extra}")
    vocabularies = [n for n in names if n.startswith(app) and n.rsplit("/", 1)[-1] == VOCABULARY]
    bad_vocabulary = {}
    for name in vocabularies:
        data = plistlib.loads(ipa.read(name))
        used = {p.get("IntentName") for p in data.get("IntentPhrases", []) if p.get("IntentName")}
        for vocabulary in data.get("ParameterVocabularies", []):
            used |= {n.split(".", 1)[0] for n in vocabulary.get("ParameterNames", [])}
        extra = tuple(sorted(used - supported))
        if extra:
            bad_vocabulary.setdefault(extra, []).append(name[len(app):])
    for extra, files in bad_vocabulary.items():
        problems.append(f"{len(files)} {VOCABULARY} file(s) ({', '.join(sorted(files)[:3])}...) have phrases for "
                        f"intents the app does not support {list(extra)} (ITMS-90626)")

    # Intents the App claims must have something to handle them in the binaries.
    executable = info.get("CFBundleExecutable", "")
    binaries = [app + executable] + sorted(
        n for n in names if re.fullmatch(re.escape(app) + r"Frameworks/([^/]+)\.framework/\1", n))
    blobs = {n: ipa.read(n) for n in binaries if n in names}
    if app + executable not in blobs:
        problems.append(f"main executable {executable!r} missing")
    if supported:
        code = b"".join(blobs.values())
        for intent in sorted(supported):
            system = re.fullmatch(r"IN[A-Z][A-Za-z]+Intent", intent) is not None
            needle = b"handlerForIntent" if system else intent.encode()
            if needle not in code:
                problems.append(f"INIntentsSupported names {intent} but no binary "
                                f"{'implements application:handlerForIntent:' if system else 'defines it'}")

    # Purpose strings (ITMS-90683): present and non-empty for every linked framework that needs one.
    linked = set()
    for blob in blobs.values():
        linked |= linked_frameworks(blob)
    empty = sorted(k for k, v in info.items() if k.endswith("UsageDescription") and not (isinstance(v, str) and v.strip()))
    if empty:
        problems.append(f"empty purpose strings {empty}")
    for framework in sorted(linked & set(PURPOSE_KEYS)):
        missing = [k for k in PURPOSE_KEYS[framework] if not info.get(k)]
        if missing:
            problems.append(f"links {framework} but Info.plist lacks {missing} (ITMS-90683)")
    for framework in sorted(linked & set(PURPOSE_ANY)):
        if not any(info.get(k) for k in PURPOSE_ANY[framework]):
            problems.append(f"links {framework} but Info.plist has none of {list(PURPOSE_ANY[framework])} (ITMS-90683)")

    checked = (f"{len(vocabularies)} Siri vocabulary file(s), INIntentsSupported {sorted(supported)}, "
               f"{len(blobs)} binaries linking {len(linked & (set(PURPOSE_KEYS) | set(PURPOSE_ANY)))} "
               "purpose-string frameworks, no extension/watch keys")
    if any(n.startswith(app + "gallery.ckcomplication/") for n in names):
        checked += "; note: watch complication gallery (gallery.ckcomplication) still ships, harmless without a watch app"
    return problems, checked


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
        problems, checked = store_checks(ipa, app, names, info)
    require(not problems, "packaged app would be rejected by App Store processing:\n  "
            + "\n  ".join(problems))
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
    summary(f"- App Store processing guards passed: {checked}.")


# --- App Store Connect build processing (Linux) -------------------------------------------

def processing(args):
    """Poll one uploaded build until Apple's processing is VALID or INVALID (the upload action only
    waits for VALID, so a rejected build would just time out there). Apple's API gives the state,
    not the ITMS reason: that arrives by email."""
    apple = AppStoreConnect(os.environ)
    apps = apple.call("/v1/apps?" + urllib.parse.urlencode({"filter[bundleId]": args.bundle_id, "fields[apps]": "bundleId"}))
    apps = [a for a in apps.get("data", []) if a["attributes"]["bundleId"] == args.bundle_id]
    require(apps, f"no App Store Connect app record for {args.bundle_id}")
    query = urllib.parse.urlencode({
        "filter[app]": apps[0]["id"], "filter[version]": args.build, "filter[preReleaseVersion.version]": args.version,
        "filter[preReleaseVersion.platform]": "IOS", "fields[builds]": "version,processingState,uploadedDate",
        "limit": 1})
    deadline, state, last = time.time() + args.minutes * 60, None, None
    while True:
        apple = AppStoreConnect(os.environ)  # tokens live 19 minutes; one per poll is cheap
        builds = apple.call(f"/v1/builds?{query}").get("data", [])
        state = builds[0]["attributes"].get("processingState") if builds else "NOT_LISTED_YET"
        if state != last:
            print(f"{datetime.now(timezone.utc):%H:%M:%S}Z build {args.version} ({args.build}): {state}", flush=True)
            last = state
        if state in ("VALID", "INVALID", "FAILED") or time.time() > deadline:
            break
        time.sleep(30)
    emit("processing_state", state)
    if state == "VALID":
        summary(f"- App Store Connect processing: **VALID**, Khala {args.version} ({args.build}) is ready in TestFlight.")
    elif state in ("INVALID", "FAILED"):
        summary(f"- App Store Connect processing: **{state}** for {args.version} ({args.build}). Apple's email names "
                "the ITMS reason (the API does not expose it).")
        fail(f"App Store Connect processing ended {state}")
    else:
        summary(f"- App Store Connect processing still {state} after {args.minutes} min; not failing the run. "
                "Apple emails the result.")


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
    command.add_argument("--mode", choices=("cloud", "manual", "unsigned"), required=True)
    command.add_argument("--bundle-id", required=True)
    command.add_argument("--read-only", action="store_true")
    commands.add_parser("cert")
    command = commands.add_parser("processing")
    for flag in ("--bundle-id", "--version", "--build"):
        command.add_argument(flag, required=True)
    command.add_argument("--minutes", type=int, default=25)
    command = commands.add_parser("verify-ipa")
    for flag in ("--ipa", "--team", "--bundle-id", "--version", "--build"):
        command.add_argument(flag, required=True)
    args = parser.parse_args()
    {"apply": apply, "verify": verify, "xcconfig": write_xcconfig, "export-options": export_options,
     "asc": asc, "cert": bootstrap_certificate, "verify-ipa": verify_ipa, "processing": processing}[args.command](args)


if __name__ == "__main__":
    main()
