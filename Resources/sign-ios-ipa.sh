#!/bin/zsh
# Sign one IPA with a .p12 + .mobileprovision and install it on a connected iPhone.
# Only use this with apps you own or are authorized to install.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APPLE_WWDR_G3="$SCRIPT_DIR/ipa-signing/AppleWWDRCAG3.cer"
APPLE_ROOT_G3="$SCRIPT_DIR/ipa-signing/AppleRootCA-G3.cer"
APPLE_ROOT_PEM="$SCRIPT_DIR/ipa-signing/AppleRootCA.pem"

usage() {
  cat <<'USAGE'
Usage:
  ./sign-ios-ipa.sh -i APP.ipa -c CERT.p12 -m PROFILE.mobileprovision -u DEVICE_UDID [options]

Required inputs:
  -i, --ipa PATH              The .ipa file to sign
  -c, --p12 PATH              Certificate with private key (.p12)
  -m, --profile PATH          Provisioning profile (.mobileprovision)
  -u, --udid UDID             iPhone UDID (xcrun devicectl list devices)

Optional:
  -b, --bundle-id ID          Override the app bundle ID
      --identity NAME         Exact codesign identity, if several match
  -o, --export-ipa PATH       Also write a signed .ipa (takes another ~6.8 GB)
      --work-dir PATH         Work folder (default: next to the IPA)
      --no-install            Sign only; do not install
      --cleanup               Delete the work folder after success
      --keep-work             Keep the work folder after success (default)
      --keep-extensions       Keep PlugIns/app extensions (needs separate profiles)
      --allow-low-space       Skip the conservative 2x IPA free-space check
      --memory-limit          Add increased-memory-limit if the profile allows it
  -h, --help                  Show this help

The .p12 password is read from the terminal, or from P12_PASSWORD.
The certificate is imported into a temporary keychain which is deleted on exit.

Examples:
  ./sign-ios-ipa.sh \
    -i "/Users/me/Downloads/ns/tl/OctopathTravelerII.ipa" \
    -c "/Users/me/Downloads/cert.p12" \
    -m "/Users/me/Downloads/profile.mobileprovision" \
    -u "00008120-001A2B3C4D5E6F70"

  # Sign and also export a signed IPA
  ./sign-ios-ipa.sh -i app.ipa -c cert.p12 -m profile.mobileprovision \
    -u UDID -o app-signed.ipa
USAGE
}

die() { print -u2 -- "ERROR: $*"; exit 1; }
step() { print -- "\n==> $*"; }

IPA=""
P12=""
PROFILE=""
UDID=""
BUNDLE_OPT=""
IDENTITY_OPT=""
EXPORT_IPA=""
WORK_DIR=""
DO_INSTALL=1
CLEANUP=0
MEMORY_LIMIT=0
KEEP_EXTENSIONS=0
ALLOW_LOW_SPACE=0

while (( $# )); do
  case "$1" in
    -i|--ipa) IPA="${2:-}"; shift 2 ;;
    -c|--p12) P12="${2:-}"; shift 2 ;;
    -m|--profile) PROFILE="${2:-}"; shift 2 ;;
    -u|--udid) UDID="${2:-}"; shift 2 ;;
    -b|--bundle-id) BUNDLE_OPT="${2:-}"; shift 2 ;;
    --identity) IDENTITY_OPT="${2:-}"; shift 2 ;;
    -o|--export-ipa) EXPORT_IPA="${2:-}"; shift 2 ;;
    --work-dir) WORK_DIR="${2:-}"; shift 2 ;;
    --no-install) DO_INSTALL=0; shift ;;
    --cleanup) CLEANUP=1; shift ;;
    --keep-work) CLEANUP=0; shift ;;
    --memory-limit) MEMORY_LIMIT=1; shift ;;
    --keep-extensions) KEEP_EXTENSIONS=1; shift ;;
    --allow-low-space) ALLOW_LOW_SPACE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

if [[ -z "$IPA" && -t 0 ]]; then
  read -r "?IPA path: " IPA
fi
if [[ -z "$P12" && -t 0 ]]; then
  read -r "?Certificate .p12 path: " P12
fi
if [[ -z "$PROFILE" && -t 0 ]]; then
  read -r "?Provisioning profile path: " PROFILE
fi
if [[ -z "$UDID" && -t 0 ]]; then
  read -r "?iPhone UDID: " UDID
fi

[[ -n "$IPA" && -n "$P12" && -n "$PROFILE" && -n "$UDID" ]] || {
  usage
  die "missing required input"
}

IPA="${IPA/#\~/$HOME}"
P12="${P12/#\~/$HOME}"
PROFILE="${PROFILE/#\~/$HOME}"
EXPORT_IPA="${EXPORT_IPA/#\~/$HOME}"
WORK_DIR="${WORK_DIR/#\~/$HOME}"

[[ -f "$IPA" ]] || die "IPA not found: $IPA"
[[ -f "$P12" ]] || die "p12 not found: $P12"
[[ -f "$PROFILE" ]] || die "profile not found: $PROFILE"

for tool in /usr/bin/security /usr/bin/codesign /usr/bin/plutil /usr/bin/python3 /usr/bin/xcrun; do
  [[ -x "$tool" ]] || die "missing tool: $tool"
done
[[ -x /usr/bin/zip ]] || die "missing /usr/bin/zip"

if [[ -z "$WORK_DIR" ]]; then
  # Keep work outside iCloud/FileProvider directories: FinderInfo/fileprovider
  # xattrs reappear there and codesign refuses to sign.
  WORK_DIR="${TMPDIR:-/tmp}/sign-ipa-$(date +%Y%m%d-%H%M%S)"
fi
mkdir -p "$WORK_DIR"
WORK_DIR="$(cd "$WORK_DIR" && pwd)"
[[ -d "$WORK_DIR" ]] || die "cannot create work folder: $WORK_DIR"

if [[ -n "$EXPORT_IPA" ]]; then
  [[ -e "$EXPORT_IPA" ]] && die "refusing to overwrite existing export: $EXPORT_IPA"
  EXPORT_DIR=$(dirname "$EXPORT_IPA")
  [[ -d "$EXPORT_DIR" ]] || die "export directory does not exist: $EXPORT_DIR"
  EXPORT_DIR="$(cd "$EXPORT_DIR" && pwd)"
  EXPORT_IPA="$EXPORT_DIR/$(basename "$EXPORT_IPA")"
fi

IPA_BYTES=$(/usr/bin/stat -f%z "$IPA")
AVAIL_BYTES=$(/bin/df -k "$WORK_DIR" | /usr/bin/awk 'NR==2 {print $4 * 1024}')
if [[ -n "$EXPORT_IPA" ]]; then
  NEED_BYTES=$(( IPA_BYTES * 3 + 1024 * 1024 * 1024 ))
else
  NEED_BYTES=$(( IPA_BYTES * 2 + 1024 * 1024 * 1024 ))
fi
if (( ! ALLOW_LOW_SPACE )) && (( AVAIL_BYTES < NEED_BYTES )); then
  die "not enough free space in $WORK_DIR (need about $(( NEED_BYTES / 1024 / 1024 / 1024 )) GB, have $(( AVAIL_BYTES / 1024 / 1024 / 1024 )) GB)"
fi
if (( ALLOW_LOW_SPACE )); then
  print -- "WARNING: low-space check skipped; free $(( AVAIL_BYTES / 1024 / 1024 / 1024 )) GB, IPA $(( IPA_BYTES / 1024 / 1024 / 1024 )) GB"
fi

print -- "IPA:      $IPA ($(( IPA_BYTES / 1024 / 1024 / 1024 )) GB)"
print -- "Work:     $WORK_DIR"
print -- "Profile:  $PROFILE"
print -- "Device:   $UDID"

ORIGINAL_KEYCHAINS=()
while IFS= read -r line; do
  line="${line#"${line%%[![:space:]]*}"}"
  line="${line#\"}"
  line="${line%\"}"
  [[ -n "$line" ]] && ORIGINAL_KEYCHAINS+=("$line")
done < <(/usr/bin/security list-keychains -d user 2>/dev/null || true)

TMP_KEYCHAIN_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/ipa-sign.XXXXXX")"
TMP_KEYCHAIN="$TMP_KEYCHAIN_DIR/signing.keychain-db"
TMP_KEYCHAIN_PASS="$(/usr/bin/uuidgen)"

cleanup() {
  /usr/bin/security delete-keychain "$TMP_KEYCHAIN" >/dev/null 2>&1 || true
  rm -rf "$TMP_KEYCHAIN_DIR" 2>/dev/null || true
  if (( ${#ORIGINAL_KEYCHAINS[@]} )); then
    /usr/bin/security list-keychains -d user -s "${ORIGINAL_KEYCHAINS[@]}" >/dev/null 2>&1 || true
  else
    /usr/bin/security list-keychains -d user -s "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT INT TERM

step "Creating temporary keychain"
/usr/bin/security create-keychain -p "$TMP_KEYCHAIN_PASS" "$TMP_KEYCHAIN" >/dev/null
/usr/bin/security set-keychain-settings -lut 21600 "$TMP_KEYCHAIN"
/usr/bin/security unlock-keychain -p "$TMP_KEYCHAIN_PASS" "$TMP_KEYCHAIN" >/dev/null

if [[ -z "${P12_PASSWORD:-}" ]]; then
  if [[ -t 0 ]]; then
    read -r -s "?p12 password: " P12_PASSWORD
    print
  else
    die "p12 password required: set P12_PASSWORD or run from a terminal"
  fi
fi

step "Importing certificate"
/usr/bin/security import "$P12" -k "$TMP_KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security -f pkcs12 >/dev/null || {
  die "could not import p12 (wrong password, missing private key, or damaged file)"
}
/usr/bin/security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$TMP_KEYCHAIN_PASS" "$TMP_KEYCHAIN" >/dev/null

# New Apple Distribution certs chain to WWDR G3; add the public intermediate locally.
for apple_cert in "$APPLE_WWDR_G3" "$APPLE_ROOT_G3" "$APPLE_ROOT_PEM"; do
  [[ -f "$apple_cert" ]] || continue
  /usr/bin/security add-certificates -k "$TMP_KEYCHAIN" "$apple_cert" >/dev/null 2>&1 || \
    /usr/bin/security import "$apple_cert" -k "$TMP_KEYCHAIN" -T /usr/bin/codesign >/dev/null 2>&1 || true
done

/usr/bin/security list-keychains -d user -s "$TMP_KEYCHAIN" "${ORIGINAL_KEYCHAINS[@]}" >/dev/null

step "Reading provisioning profile"
PROFILE_PLIST="$WORK_DIR/profile.plist"
PROFILE_JSON="$WORK_DIR/profile.json"
PROFILE_ENTITLEMENTS="$WORK_DIR/profile-entitlements.plist"
/usr/bin/security cms -D -i "$PROFILE" > "$PROFILE_PLIST" 2>/dev/null || die "cannot decode profile"
/usr/bin/python3 - "$PROFILE_PLIST" "$PROFILE_JSON" "$PROFILE_ENTITLEMENTS" <<'PY'
import datetime
import json
import plistlib
import sys

src, out_json, out_ent = sys.argv[1:4]
with open(src, "rb") as f:
    p = plistlib.load(f)
team_ids = p.get("TeamIdentifier") or []
team = team_ids[0] if team_ids else ""
ent = p.get("Entitlements") or {}
app_id = ent.get("application-identifier") or ""
if not team and app_id:
    team = app_id.split(".", 1)[0]
devices = p.get("ProvisionedDevices") or []
expires = p.get("ExpirationDate")
expires_s = expires.isoformat() if isinstance(expires, datetime.datetime) else str(expires or "")
data = {
    "name": p.get("Name") or "",
    "uuid": p.get("UUID") or "",
    "team": team,
    "app_id": app_id,
    "expires": expires_s,
    "devices": devices,
    "all_devices": bool(p.get("ProvisionsAllDevices")),
}
with open(out_json, "w") as f:
    json.dump(data, f, indent=2)
with open(out_ent, "wb") as f:
    plistlib.dump(ent, f)
print(f"profile: {data['name']}")
print(f"team:    {team}")
print(f"app id:  {app_id or '(none)'}")
print(f"expires: {expires_s}")
PY

/usr/bin/python3 - "$PROFILE_JSON" "$UDID" <<'PY'
import datetime
import json
import sys

data = json.load(open(sys.argv[1]))
udid = sys.argv[2].replace("-", "").upper()
devices = {str(x).replace("-", "").upper() for x in data.get("devices", [])}
if data.get("all_devices"):
    sys.exit(0)
if udid not in devices:
    print(f"ERROR: this profile does not include UDID {sys.argv[2]}", file=sys.stderr)
    print(f"       profile has {len(devices)} registered device(s)", file=sys.stderr)
    print("       create a new Development/Ad Hoc profile with this iPhone registered", file=sys.stderr)
    sys.exit(1)
expires = data.get("expires")
if expires:
    try:
        dt = datetime.datetime.fromisoformat(expires)
        if dt.tzinfo is not None:
            dt = dt.astimezone(datetime.timezone.utc).replace(tzinfo=None)
        if dt < datetime.datetime.utcnow():
            print(f"ERROR: provisioning profile expired at {expires}", file=sys.stderr)
            sys.exit(1)
    except ValueError:
        pass
PY

TEAM=$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("team",""))' "$PROFILE_JSON")
PROFILE_APP_ID=$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("app_id",""))' "$PROFILE_JSON")
[[ -n "$TEAM" ]] || die "profile has no TeamIdentifier"

step "Extracting IPA"
/usr/bin/unzip -qo "$IPA" -d "$WORK_DIR" || die "unzip failed"
APP=$(/usr/bin/find "$WORK_DIR/Payload" -maxdepth 1 -type d -name '*.app' -print -quit 2>/dev/null)
[[ -n "$APP" && -d "$APP" ]] || die "no Payload/*.app found in IPA"

APP_BUNDLE=$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$APP/Info.plist")
[[ -n "$APP_BUNDLE" ]] || die "app has no CFBundleIdentifier"

BUNDLE="${BUNDLE_OPT:-$APP_BUNDLE}"
if [[ "$BUNDLE" != "$APP_BUNDLE" ]]; then
  print -- "Changing bundle ID from $APP_BUNDLE to $BUNDLE (side-by-side copy)"
  /usr/bin/plutil -replace CFBundleIdentifier -string "$BUNDLE" "$APP/Info.plist"
else
  print -- "Keeping bundle ID: $BUNDLE"
fi

step "Preparing entitlements"
ENTITLEMENTS="$WORK_DIR/entitlements.plist"
/usr/bin/python3 - "$PROFILE_ENTITLEMENTS" "$ENTITLEMENTS" "$TEAM" "$BUNDLE" "$MEMORY_LIMIT" "$PROFILE_APP_ID" <<'PY'
import plistlib
import sys

src, dst, team, bundle, memory, profile_app_id = sys.argv[1:7]
with open(src, "rb") as f:
    ent = plistlib.load(f)

# This signing service's explicit App ID profile is accepted by iOS even when
# the app's CFBundleIdentifier differs from application-identifier. Keep the
# profile entitlement unchanged so every IPA can retain its own bundle ID.
if profile_app_id.endswith(".*"):
    ent["application-identifier"] = f"{team}.{bundle}"
    ent["com.apple.developer.team-identifier"] = team
    if "keychain-access-groups" in ent:
        ent["keychain-access-groups"] = [f"{team}.{bundle}"]

mem_key = "com.apple.developer.kernel.increased-memory-limit"
if memory == "1":
    if ent.get(mem_key) is True:
        print("increased-memory-limit: profile allows it")
    else:
        print("increased-memory-limit: profile does NOT allow it; leaving it out", file=sys.stderr)
elif ent.get(mem_key) is True:
    print("increased-memory-limit: kept from profile")

with open(dst, "wb") as f:
    plistlib.dump(ent, f)
PY

# Remove resource forks / Finder metadata that make codesign fail.
/usr/bin/xattr -cr "$APP" 2>/dev/null || true

step "Preparing nested code"
if (( ! KEEP_EXTENSIONS )); then
  for extdir in PlugIns Watch AppClips Extensions; do
    if [[ -d "$APP/$extdir" ]]; then
      print -- "Removing $extdir (app extensions need separate provisioning profiles)"
      rm -rf "$APP/$extdir"
    fi
  done
fi
cp "$PROFILE" "$APP/embedded.mobileprovision"

if [[ -n "$IDENTITY_OPT" ]]; then
  IDENTITY="$IDENTITY_OPT"
else
  IDENTITIES=$(/usr/bin/security find-identity -v -p codesigning "$TMP_KEYCHAIN" | /usr/bin/sed -n 's/.*"\(Apple [^"]*\)".*/\1/p; s/.*"\(iPhone [^"]*\)".*/\1/p' | /usr/bin/sort -u || true)
  if [[ -z "$IDENTITIES" ]]; then
    print -u2 -- "WARNING: no 'valid' identity (often an OCSP/network issue); trying matching identities."
    IDENTITIES=$(/usr/bin/security find-identity -p codesigning "$TMP_KEYCHAIN" | /usr/bin/sed -n 's/.*"\(Apple [^"]*\)".*/\1/p; s/.*"\(iPhone [^"]*\)".*/\1/p' | /usr/bin/sort -u || true)
  fi
  [[ -n "$IDENTITIES" ]] || die "no codesigning identity found; check the p12 and Keychain"
  IDENTITY=$(print -r -- "$IDENTITIES" | /usr/bin/grep -F "($TEAM)" | /usr/bin/head -1 || true)
  if [[ -z "$IDENTITY" ]]; then
    print -u2 -- "Available identities:"
    print -u2 -- "$IDENTITIES"
    die "no codesigning identity for team ($TEAM); the certificate and profile must belong to the same team"
  fi
fi
print -- "Identity: $IDENTITY"

# Sign nested code inside-out. Do not use --deep with the main entitlements:
# extensions/frameworks must not inherit the app's application-identifier.
if [[ -d "$APP" ]]; then
  while IFS= read -r -d '' lib; do
    /usr/bin/codesign --force --sign "$IDENTITY" --timestamp=none "$lib"
  done < <(/usr/bin/find "$APP" -type f \( -name '*.dylib' -o -name '*.so' \) -print0)
fi

if [[ -d "$APP/Frameworks" ]]; then
  while IFS= read -r -d '' fw; do
    /usr/bin/codesign --force --sign "$IDENTITY" --timestamp=none "$fw"
  done < <(/usr/bin/find "$APP/Frameworks" -depth -type d -name '*.framework' -print0)
fi

/usr/bin/codesign --force \
  --sign "$IDENTITY" \
  --entitlements "$ENTITLEMENTS" \
  --generate-entitlement-der \
  --timestamp=none \
  "$APP"

step "Verifying signature"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
/usr/bin/codesign -d --entitlements :- "$APP" >/dev/null

if [[ -n "$EXPORT_IPA" ]]; then
  step "Writing signed IPA"
  ( cd "$WORK_DIR" && /usr/bin/zip -qry "$EXPORT_IPA" Payload )
  print -- "Signed IPA: $EXPORT_IPA"
fi

if (( DO_INSTALL )); then
  step "Installing on iPhone"
  DEVICES=$(/usr/bin/xcrun devicectl list devices 2>&1 || true)

  # Check the device's actual state, not just whether its UDID shows up in the
  # list: devicectl keeps paired-but-offline devices around as "unavailable".
  DEVICE_JSON="$(mktemp "${TMPDIR:-/tmp}/ipa-dispatch-devices.XXXXXX")"
  /usr/bin/xcrun devicectl list devices --json-output "$DEVICE_JSON" >/dev/null 2>&1 || true
  DEVICE_STATUS="$(/usr/bin/python3 - "$DEVICE_JSON" "$UDID" <<'PY'
import json, sys
path, want = sys.argv[1], sys.argv[2].upper().replace("-", "")
try:
    with open(path) as fh:
        data = json.load(fh)
except Exception:
    print("unknown")
    raise SystemExit
for dev in data.get("result", {}).get("devices", []):
    props = dev.get("properties") or {}
    hw = props.get("hardware") or dev.get("hardwareProperties") or {}
    conn = props.get("connection") or dev.get("connectionProperties") or {}
    udid = str(hw.get("udid", "")).upper().replace("-", "")
    if udid != want or str(hw.get("reality", "")).lower() != "physical":
        continue
    state = str(conn.get("state") or conn.get("tunnelState") or "disconnected").lower()
    print("connected" if state.startswith(("available", "connected")) else state)
    raise SystemExit
print("missing")
PY
)" || DEVICE_STATUS="unknown"
  rm -f "$DEVICE_JSON"

  # Fall back to the table's State column when --json-output is unavailable.
  if [[ "$DEVICE_STATUS" == "unknown" ]]; then
    DEVICE_LINE=$(print -r -- "$DEVICES" | /usr/bin/grep -i -F "$UDID" | /usr/bin/head -1 || true)
    DEVICE_STATUS=$(print -r -- "$DEVICE_LINE" \
      | /usr/bin/sed -E 's/[[:space:]]{2,}/|/g' \
      | /usr/bin/awk -F'|' '{print tolower($3)}' || true)
    [[ -n "$DEVICE_STATUS" ]] || DEVICE_STATUS="missing"
  fi

  case "$DEVICE_STATUS" in
    connected|available*) ;;
    missing)
      print -u2 -- "$DEVICES"
      die "device $UDID was not found by devicectl. Connect by USB, unlock it, trust this Mac, and enable Developer Mode."
      ;;
    *)
      print -u2 -- "$DEVICES"
      die "device $UDID is $DEVICE_STATUS (not connected). Connect by USB, unlock it, trust this Mac, and enable Developer Mode."
      ;;
  esac

  bundle_installed() {
    local b="$1" esc
    esc=$(print -r -- "$b" | /usr/bin/sed 's/[.]/\\./g')
    /usr/bin/xcrun devicectl device info apps --device "$UDID" --timeout 60 2>/dev/null \
      | /usr/bin/grep -Eq "[[:space:]]${esc}([[:space:]]|$)"
  }

  resign_main_for_bundle() {
    local new_bundle="$1"
    /usr/bin/plutil -replace CFBundleIdentifier -string "$new_bundle" "$APP/Info.plist"
    if [[ "$PROFILE_APP_ID" == *".*" ]]; then
      /usr/bin/python3 - "$ENTITLEMENTS" "$TEAM" "$new_bundle" <<'PY'
import plistlib, sys
path, team, bundle = sys.argv[1:4]
with open(path, "rb") as f:
    ent = plistlib.load(f)
ent["application-identifier"] = f"{team}.{bundle}"
ent["com.apple.developer.team-identifier"] = team
if "keychain-access-groups" in ent:
    ent["keychain-access-groups"] = [f"{team}.{bundle}"]
with open(path, "wb") as f:
    plistlib.dump(ent, f)
PY
    fi
    /usr/bin/xattr -cr "$APP" 2>/dev/null || true
    /usr/bin/codesign --force \
      --sign "$IDENTITY" \
      --entitlements "$ENTITLEMENTS" \
      --generate-entitlement-der \
      --timestamp=none \
      "$APP"
    /usr/bin/codesign --verify --deep --strict "$APP"
  }

  install_current() {
    /usr/bin/xcrun devicectl device install app \
      --device "$UDID" \
      --timeout 1800 \
      "$APP" 2>&1
  }

  if INSTALL_OUT=$(install_current); then
    print -r -- "$INSTALL_OUT"
  else
    print -u2 -- "$INSTALL_OUT"
    if print -r -- "$INSTALL_OUT" | /usr/bin/grep -qE 'MismatchedApplicationIdentifierEntitlement|does not match installed application'; then
      print -- ""
      print -- "Bundle ID conflict; installing a side-by-side copy instead."
      INSTALLED_COPY=0
      for n in 1 2 3 4 5; do
        CAND="${BUNDLE}.sideload${n}"
        if bundle_installed "$CAND"; then
          continue
        fi
        print -- "Trying bundle ID: $CAND"
        resign_main_for_bundle "$CAND"
        if INSTALL_OUT=$(install_current); then
          print -r -- "$INSTALL_OUT"
          BUNDLE="$CAND"
          INSTALLED_COPY=1
          break
        fi
        print -u2 -- "$INSTALL_OUT"
        if ! print -r -- "$INSTALL_OUT" | /usr/bin/grep -qE 'MismatchedApplicationIdentifierEntitlement|does not match installed application|already exists|already installed'; then
          break
        fi
      done
      if (( ! INSTALLED_COPY )); then
        die "could not install a side-by-side copy"
      fi
    else
      exit 1
    fi
  fi
  print -- "Installed bundle ID: $BUNDLE"
fi

step "Done"
print -- "Signed app: $APP"
print -- "Work dir:   $WORK_DIR"
print -- "On iPhone:  Settings > General > VPN & Device Management > Developer App > Trust"
if (( CLEANUP )); then
  cleanup
  trap - EXIT INT TERM
  rm -rf "$WORK_DIR"
  print -- "Removed work dir."
fi
