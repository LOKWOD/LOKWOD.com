#!/usr/bin/env bash
set -euo pipefail

CAPTURE=/tmp/lokwod-capture
MIRROR="$CAPTURE/mirror"
SITE="$CAPTURE/site"
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126 Safari/537.36'

rm -rf "$CAPTURE"
mkdir -p "$MIRROR" "$SITE/.recovery"

# Capture the live homepage without altering a byte.
curl --fail --location --retry 4 --retry-delay 2 \
  --user-agent "$UA" \
  --dump-header "$CAPTURE/home.headers" \
  --output "$CAPTURE/home.raw.html" \
  https://lokwod.com/

# This job must never mistake the replacement design for the original site.
if grep -Fqi 'Intelligent systems for the parts of your home' "$CAPTURE/home.raw.html"; then
  echo 'ABORT: replacement homepage detected. Refusing to capture it as the original.' >&2
  exit 1
fi
if ! grep -Eqi 'Know your property is protected|Before something fails' "$CAPTURE/home.raw.html"; then
  echo 'ABORT: expected original-homepage wording was not found. Nothing will be committed.' >&2
  sed -n '1,100p' "$CAPTURE/home.raw.html" >&2
  exit 1
fi
sha256sum "$CAPTURE/home.raw.html" | tee "$CAPTURE/home.sha256"

# Mirror all reachable same-domain pages and first-party requisites. The live
# portal intentionally redirects to OpenAI login. Wget reports that external
# 403 as exit code 8 even though all first-party files were downloaded, so code
# 8 is recorded and accepted; every other non-zero exit remains fatal.
cd "$MIRROR"
set +e
wget \
  --mirror \
  --page-requisites \
  --adjust-extension \
  --span-hosts \
  --domains=lokwod.com,www.lokwod.com \
  --execute robots=off \
  --timeout=30 \
  --tries=4 \
  --waitretry=2 \
  --user-agent="$UA" \
  https://lokwod.com/
WGET_STATUS=$?
set -e
printf '%s\n' "$WGET_STATUS" > "$CAPTURE/wget-status.txt"
if [ "$WGET_STATUS" -ne 0 ] && [ "$WGET_STATUS" -ne 8 ]; then
  echo "Mirror failed with unexpected wget exit code $WGET_STATUS" >&2
  exit "$WGET_STATUS"
fi

# Preserve common discovery files whether or not the homepage links to them.
mkdir -p "$MIRROR/lokwod.com"
for path in robots.txt sitemap.xml favicon.ico favicon.svg manifest.webmanifest site.webmanifest; do
  curl --location --silent --show-error --fail \
    --user-agent "$UA" \
    "https://lokwod.com/$path" \
    --output "$MIRROR/lokwod.com/$path" || true
done

# Capture every same-domain URL declared in the sitemap.
if [ -s "$MIRROR/lokwod.com/sitemap.xml" ]; then
  python3 - <<'PY'
from pathlib import Path
import re, subprocess
p = Path('/tmp/lokwod-capture/mirror/lokwod.com/sitemap.xml')
text = p.read_text('utf-8', errors='ignore')
urls = sorted(set(re.findall(r'<loc>\s*(https?://(?:www\.)?lokwod\.com/[^<]*)\s*</loc>', text, re.I)))
for url in urls:
    subprocess.run([
        'wget', '--page-requisites', '--adjust-extension', '--span-hosts',
        '--domains=lokwod.com,www.lokwod.com', '--execute', 'robots=off',
        '--timeout=30', '--tries=4',
        '--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/126 Safari/537.36',
        url,
    ], cwd='/tmp/lokwod-capture/mirror', check=False)
print(f'Sitemap URLs attempted: {len(urls)}')
PY
fi

SOURCE=''
for candidate in "$MIRROR/lokwod.com" "$MIRROR/www.lokwod.com"; do
  if [ -f "$candidate/index.html" ]; then
    SOURCE="$candidate"
    break
  fi
done
if [ -z "$SOURCE" ]; then
  echo 'No mirrored index.html was produced.' >&2
  find "$MIRROR" -maxdepth 5 -type f -print >&2
  exit 1
fi

cp -a "$SOURCE"/. "$SITE/"
# Use the byte-for-byte live homepage, not wget's processed copy.
cp "$CAPTURE/home.raw.html" "$SITE/index.html"
cp "$CAPTURE/home.raw.html" "$SITE/.recovery/home.raw.html"
cp "$CAPTURE/home.headers" "$SITE/.recovery/home.headers"
cp "$CAPTURE/home.sha256" "$SITE/.recovery/home.sha256"
cp "$CAPTURE/wget-status.txt" "$SITE/.recovery/wget-status.txt"
printf 'lokwod.com\n' > "$SITE/CNAME"
: > "$SITE/.nojekyll"

# GitHub Pages needs directory index files to preserve the live site's clean
# routes (/products, /platform, /support/request, etc.). Keep the captured
# .html files as evidence and add equivalent route/index.html copies.
python3 - <<'PY'
from pathlib import Path
root = Path('/tmp/lokwod-capture/site')
for p in sorted(root.rglob('*.html')):
    rel = p.relative_to(root)
    if rel.as_posix() == 'index.html' or rel.parts[0] == '.recovery':
        continue
    # Query-string captures all map to their queryless live route. The main
    # route page is already captured separately, so do not turn query variants
    # into invalid directory names.
    if '?' in p.name:
        continue
    route_dir = p.with_suffix('')
    route_dir.mkdir(parents=True, exist_ok=True)
    target = route_dir / 'index.html'
    if not target.exists():
        target.write_bytes(p.read_bytes())
PY

python3 - <<'PY'
from pathlib import Path
import hashlib, json, mimetypes, re
root = Path('/tmp/lokwod-capture/site')
files = []
for p in sorted(root.rglob('*')):
    if p.is_file():
        rel = p.relative_to(root).as_posix()
        data = p.read_bytes()
        files.append({
            'path': rel,
            'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest(),
            'content_type': mimetypes.guess_type(rel)[0],
        })
html = (root / 'index.html').read_text('utf-8', errors='ignore')
first_party_paths = sorted(set(re.findall(r'''(?:href|src)=["'](/[^"'#?]*)''', html, flags=re.I)))
manifest = {
    'source': 'https://lokwod.com/',
    'purpose': 'Recovery capture of the live pre-migration LOKWOD.com site',
    'homepage_is_byte_for_byte_live_response': True,
    'homepage_sha256': hashlib.sha256((root / 'index.html').read_bytes()).hexdigest(),
    'first_party_homepage_paths': first_party_paths,
    'file_count': len(files),
    'files': files,
}
(root / '.recovery' / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(f'Captured {len(files)} files')
PY

# Final guard before publishing the isolated branch.
if grep -Fqi 'Intelligent systems for the parts of your home' "$SITE/index.html"; then
  echo 'ABORT: replacement homepage appeared in assembled capture.' >&2
  exit 1
fi
grep -Eqi 'Know your property is protected|Before something fails' "$SITE/index.html"

git config user.name 'LOKWOD Site Recovery'
git config user.email 'actions@users.noreply.github.com'
git checkout --orphan recovery-capture-worktree
git rm -rf . >/dev/null 2>&1 || true
cp -a "$SITE"/. .
git add -A
git commit -m 'Capture exact live LOKWOD.com site before DNS migration'
git push --force origin HEAD:recovery/live-site-exact

{
  echo '## Live-site capture complete'
  echo
  echo '- Recovery branch: `recovery/live-site-exact`'
  echo '- Source: `https://lokwod.com/`'
  echo '- Guard: original wording found; replacement wording absent'
  echo "- Files: $(find "$SITE" -type f | wc -l)"
  echo "- Homepage SHA-256: $(cut -d' ' -f1 "$CAPTURE/home.sha256")"
  echo "- Wget status: $WGET_STATUS (8 is expected when OpenAI rejects anonymous crawler login)"
} >> "$GITHUB_STEP_SUMMARY"
