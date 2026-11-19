#!/usr/bin/env bash
set -Eeuo pipefail

script_path=${BASH_SOURCE[0]}
case $script_path in */*) script_parent=${script_path%/*} ;; *) script_parent=. ;; esac
repo_root=$(CDPATH= cd -- "$script_parent/.." && pwd -P)

version=${1:-}
if [[ -z $version ]]; then
    version=$(sed -n 's/^[[:space:]]*version = "\([^"]*\)"/\1/p' "$repo_root/build.gradle" | head -n1)
fi
[[ -n $version ]] || { printf 'ERROR: Could not determine OSCAR version.\n' >&2; exit 1; }

release_zip=${2:-"$repo_root/build/distributions/oscar-${version}.zip"}
[[ -f $release_zip ]] || { printf 'ERROR: Packaged release ZIP not found: %s\n' "$release_zip" >&2; exit 1; }

suite_repo_url=${OSCAR_REGRESSION_SUITE_REPO:-https://github.com/ORNL/oscar-regression.git}
suite_ref=${OSCAR_REGRESSION_SUITE_REF:-main}
work_base=/opt/oscar-ci-regression
deploy_dir="$work_base/oscar-${version}"
backup_dir="$work_base/backups"
suite_dir="${RUNNER_TEMP:-/tmp}/oscar-regression-$$"
admin_password="OscarCiTest!${RANDOM:-4821}97531Aa"

cleanup() {
    local exit_code=$?
    if ((exit_code != 0)) && [[ -f "$deploy_dir/oscar.sh" ]]; then
        printf '\n=== Live deployment regression failed (exit=%s); collecting container status and logs ===\n' "$exit_code" >&2
        sudo bash "$deploy_dir/oscar.sh" status >&2 || true
        sudo bash "$deploy_dir/oscar.sh" logs --tail 150 >&2 || true
    fi
    if [[ -f "$deploy_dir/oscar.sh" ]]; then
        sudo bash "$deploy_dir/oscar.sh" stop >/dev/null 2>&1 || true
    fi
    sudo docker compose --project-name oscar down --remove-orphans >/dev/null 2>&1 || true
    sudo docker volume rm oscar_oscar_state oscar_postgres_data >/dev/null 2>&1 || true
    sudo rm -rf "$work_base" "$suite_dir" >/dev/null 2>&1 || true
}
trap cleanup EXIT

printf '== Step 1: Validate ORNL/oscar-regression oracles and 50-lane fixture ==\n'
rm -rf "$suite_dir"
git clone --depth 1 --branch "$suite_ref" "$suite_repo_url" "$suite_dir"
(
    cd "$suite_dir"
    npm ci
    npx playwright install chromium
    if ! node -e 'import("playwright").then(async ({chromium}) => { const b = await chromium.launch({headless: true}); await b.close(); })' >/dev/null 2>&1; then
        npx playwright install-deps chromium
    fi
    npm run check
    npm test
    npm run build
    npm audit --audit-level=high
)

printf '== Step 2: Initialize packaged OSCAR %s Docker Compose deployment ==\n' "$version"
sudo systemctl stop apache2 nginx >/dev/null 2>&1 || true
sudo docker compose --project-name oscar down --remove-orphans >/dev/null 2>&1 || true
sudo docker volume rm oscar_oscar_state oscar_postgres_data >/dev/null 2>&1 || true
sudo rm -rf "$work_base"
sudo mkdir -p "$work_base/extract" "$backup_dir"
sudo unzip -q "$release_zip" -d "$work_base/extract"
if [[ -d "$work_base/extract/oscar-${version}" ]]; then
    sudo mv "$work_base/extract/oscar-${version}" "$deploy_dir"
else
    extracted_first=$(sudo find "$work_base/extract" -mindepth 1 -maxdepth 1 -type d | head -n1)
    [[ -n $extracted_first ]] || { printf 'ERROR: Release ZIP did not unpack a root directory.\n' >&2; exit 1; }
    sudo mv "$extracted_first" "$deploy_dir"
fi
sudo rm -rf "$work_base/extract"

sudo env OSCAR_SETUP_ADMIN_PASSWORD="$admin_password" \
    bash "$deploy_dir/oscar.sh" init \
    --non-interactive \
    --hostname oscar.local \
    --port 443 \
    --timezone UTC \
    --tls-san 127.0.0.1 \
    --tls-san localhost \
    --backup-mode single \
    --backup-dir "$backup_dir" \
    --add-hosts-entry

sudo bash "$deploy_dir/oscar.sh" status

cert_copy="$suite_dir/oscar-ci-server.crt"
sudo cp "$deploy_dir/tls/server.crt" "$cert_copy"
sudo chmod 644 "$cert_copy"

printf '== Step 3: Run headless Playwright UI, gateway, ConSys API, and 50-lane fixture regression checks ==\n'
(
    cd "$suite_dir"
    NODE_EXTRA_CA_CERTS="$cert_copy" \
    OSCAR_CI_ADMIN_PASSWORD="$admin_password" \
    node --input-type=module <<'NODE'
import assert from 'node:assert/strict';
import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import { chromium } from 'playwright';

const password = process.env.OSCAR_CI_ADMIN_PASSWORD;
assert.ok(password && password.length >= 14, 'Missing CI admin password');
const basicAuth = 'Basic ' + Buffer.from(`admin:${password}`).toString('base64');

function requestOnce(urlString, headers = {}) {
    const url = new URL(urlString);
    const transport = url.protocol === 'https:' ? https : http;
    return new Promise((resolve, reject) => {
        const req = transport.request(url, { method: 'GET', headers }, (res) => {
            const chunks = [];
            res.on('data', (chunk) => chunks.push(chunk));
            res.on('end', () => resolve({
                status: res.statusCode ?? 0,
                headers: res.headers,
                body: Buffer.concat(chunks).toString('utf8'),
            }));
        });
        req.on('error', reject);
        req.end();
    });
}

// 1. Port 80 HTTP -> HTTPS 308 redirect
const httpRedirect = await requestOnce('http://oscar.local/healthz');
assert.equal(httpRedirect.status, 308, `Expected HTTP 308 redirect, got ${httpRedirect.status}`);
assert.equal(httpRedirect.headers.location, 'https://oscar.local/healthz');

// 2. Trusted TLS gateway /healthz and security headers
const healthz = await requestOnce('https://oscar.local/healthz');
assert.equal(healthz.status, 200);
assert.equal(healthz.body.trim(), 'ok');
assert.equal(healthz.headers['x-content-type-options'], 'nosniff');
assert.equal(healthz.headers['x-frame-options'], 'SAMEORIGIN');
assert.equal(healthz.headers['referrer-policy'], 'no-referrer');

// 3. Operational view gateway canonicalization & fail-closed malformed paths
const validView = await requestOnce('https://oscar.local/view/east-gate');
assert.equal(validView.status, 302);
assert.equal(validView.headers.location, '/?view=east-gate');

const malformedView = await requestOnce('https://oscar.local/view/');
assert.equal(malformedView.status, 302);
assert.equal(malformedView.headers.location, '/?view=');

// 4. Unauthenticated ConSys API fails closed without immutable browser caching
const unauthApi = await requestOnce('https://oscar.local/sensorhub/api/systems');
assert.equal(unauthApi.status, 401, `Expected 401 on anonymous ConSys API, got ${unauthApi.status}`);
assert.ok(
    !String(unauthApi.headers['cache-control'] ?? '').includes('immutable'),
    'Anonymous 401 must not carry immutable Cache-Control',
);

// 5. Authenticated ConSys API returns OSCAR system & datastreams
let systemsJson = null;
for (let attempt = 1; attempt <= 25; attempt += 1) {
    const res = await requestOnce('https://oscar.local/sensorhub/api/systems?limit=100', {
        Authorization: basicAuth,
        Accept: 'application/geo+json, application/json',
    });
    if (res.status === 200) {
        const parsed = JSON.parse(res.body);
        const items = parsed.items ?? parsed.features ?? [];
        if (Array.isArray(items) && items.some((item) => JSON.stringify(item).includes('urn:ornl:oscar:system:'))) {
            systemsJson = items;
            break;
        }
    }
    await new Promise((r) => setTimeout(r, 1500));
}
assert.ok(systemsJson, 'Authenticated ConSys /sensorhub/api/systems did not expose urn:ornl:oscar:system:*');

const dsRes = await requestOnce('https://oscar.local/sensorhub/api/datastreams?limit=100', {
    Authorization: basicAuth,
    Accept: 'application/json',
});
assert.equal(dsRes.status, 200, `Expected 200 from /sensorhub/api/datastreams, got ${dsRes.status}`);

// 6. Verify 50-lane CSV fixture invariants
const csvLines = fs.readFileSync('fixtures/oscar-50-lane-config.csv', 'utf8').trim().split(/\r?\n/);
assert.equal(csvLines.length, 51, `Expected header + 50 lanes in oscar-50-lane-config.csv, got ${csvLines.length}`);

// 7. Headless Chromium E2E navigation across OSCAR Viewer routes & SensorHub Admin
const viewerRoutes = [
    ['/', 'Lane Status'],
    ['/event-log', 'Events'],
    ['/health', 'Status of Health'],
    ['/report', 'Report Generator'],
    ['/alarm-transfer', 'Alarm Transfer'],
    ['/map', 'Map'],
    ['/national-view', 'National'],
    ['/users', 'Users, Passkeys & Access Control'],
    ['/usb-backups', 'Continual & Occasional USB NVMe Backups'],
    ['/extensions', 'Pluggable Runtime Extensions & Regional Packs'],
    ['/servers', 'Nodes'],
];
const browser = await chromium.launch({ headless: true });
try {
    const context = await browser.newContext({
        ignoreHTTPSErrors: true,
        httpCredentials: { username: 'admin', password },
        viewport: { width: 1600, height: 1000 },
        locale: 'en-US',
    });
    let sawImmutableNextBundle = false;
    const page = await context.newPage();
    page.on('response', (res) => {
        if (res.url().includes('/_next/static/')) {
            const cc = res.headers()['cache-control'] ?? '';
            if (cc.includes('private') && cc.includes('immutable')) {
                sawImmutableNextBundle = true;
            }
        }
    });

    await page.goto('https://oscar.local/', { waitUntil: 'domcontentloaded', timeout: 30000 });
    const usernameInput = page.getByLabel('Username');
    if (await usernameInput.isVisible({ timeout: 5000 }).catch(() => false)) {
        await usernameInput.fill('admin');
        await page.getByLabel('Password').fill(password);
        await Promise.all([
            page.waitForURL((url) => !url.pathname.startsWith('/login'), { timeout: 20000 }),
            page.getByRole('button', { name: 'Sign in', exact: true }).click(),
        ]);
    }
    const sessionRes = await context.request.get('https://oscar.local/session');
    assert.ok(sessionRes.ok(), `Expected /session 200 after login, got ${sessionRes.status()}`);
    const sessionJson = await sessionRes.json();
    assert.equal(sessionJson.username, 'admin', `Expected authenticated session user admin, got ${sessionJson.username}`);

    for (const [route, marker] of viewerRoutes) {
        const response = await page.goto(`https://oscar.local${route}`, { waitUntil: 'domcontentloaded', timeout: 30000 });
        assert.ok(response && response.status() >= 200 && response.status() < 400, `Viewer route ${route} returned HTTP ${response?.status()}`);
        await page.getByRole('heading', { name: marker, exact: true }).first().waitFor({ timeout: 15000 });
        const bodyText = await page.locator('body').innerText();
        assert.ok(!/application error|internal server error/i.test(bodyText), `Viewer route ${route} rendered an application error`);
    }
    const scopedRes = await page.goto('https://oscar.local/view/east-gate', { waitUntil: 'domcontentloaded', timeout: 30000 });
    assert.ok(scopedRes && scopedRes.status() >= 200 && scopedRes.status() < 400, `Workstation view redirect failed with HTTP ${scopedRes?.status()}`);
    assert.ok(page.url().includes('?view=east-gate'), `Expected workstation URL to canonicalize to ?view=east-gate, got ${page.url()}`);
    assert.ok(sawImmutableNextBundle, 'Expected /_next/static/ assets to serve private immutable Cache-Control');

    const adminRes = await page.goto('https://oscar.local/sensorhub/admin', { waitUntil: 'domcontentloaded', timeout: 30000 });
    assert.ok(adminRes && adminRes.status() >= 200 && adminRes.status() < 400, `SensorHub Admin returned HTTP ${adminRes?.status()}`);
    await page.waitForTimeout(2000);
    const adminBody = await page.locator('body').innerText();
    assert.ok(/sensorhub|admin|module|sensor|system/i.test(adminBody) && adminBody.trim().length > 100, 'SensorHub Admin UI did not render module controls');

    // 8. Pluggable Runtime Extensions & Regional Packs E2E round-trip (shipped defaults -> custom upload -> HTTP 206 -> 1-click reset)
    const unauthExt = await requestOnce('https://oscar.local/sensorhub/oscar/extensions/status');
    assert.equal(unauthExt.status, 401, `Expected 401 on anonymous /extensions/status, got ${unauthExt.status}`);

    const extHeaders = { 'X-Requested-With': 'OSCAR-Viewer' };
    try {
        const initExtRes = await context.request.get('https://oscar.local/sensorhub/oscar/extensions/status');
        assert.equal(initExtRes.status(), 200, `Expected 200 from /extensions/status, got ${initExtRes.status()}`);
        const initExt = await initExtRes.json();
        assert.equal(initExt.ocr?.customActive, false, 'Fresh install must start with shipped default OCR');
        assert.equal(initExt.maps?.customActive, false, 'Fresh install must start with shipped default maps');
        assert.equal(initExt.spectroscopy?.customActive, false, 'Fresh install must start with shipped default spectroscopy');
        assert.equal(initExt.trustedCerts?.customActive, false, 'Fresh install must start with shipped default CA trust');
        assert.equal(initExt.policyPacks?.customActive, false, 'Fresh install must start with shipped default policy pack');

        // Starter template download check
        const tplRes = await context.request.get('https://oscar.local/sensorhub/oscar/extensions/templates/ocr-pack.zip');
        assert.equal(tplRes.status(), 200);
        assert.ok((await tplRes.body()).length > 100, 'Expected non-empty OCR starter template ZIP');

        // 8a. OCR regional plate-rules upload & reset
        const ocrRules = JSON.stringify({
            ruleSetId: 'ci-numeric-plates-v1',
            description: 'CI Numeric & Alphanumeric Plate Filter',
            minLength: 3,
            maxLength: 10,
            asciiOnly: false,
            requireLetter: false,
            requireDigit: true,
        });
        const ocrUp = await context.request.post(
            'https://oscar.local/sensorhub/oscar/extensions/ocr/upload?filename=ci-plate-rules.json',
            { headers: { ...extHeaders, 'Content-Type': 'application/octet-stream' }, data: Buffer.from(ocrRules, 'utf8') },
        );
        assert.equal(ocrUp.status(), 200, `OCR rules upload failed: ${ocrUp.status()}`);
        const ocrAfter = await ocrUp.json();
        assert.equal(ocrAfter.ocr?.customActive, true);
        assert.equal(ocrAfter.ocr?.plateRuleSetId, 'ci-numeric-plates-v1');

        // 8b. Offline PMTiles v3 upload, HTTP 206 Range verification, & /map render
        const pmBuf = Buffer.alloc(256, 0);
        pmBuf.write('PMTiles', 0, 'ascii');
        pmBuf[7] = 3;
        pmBuf.writeBigUInt64LE(127n, 8);
        pmBuf.writeBigUInt64LE(1n, 16);
        pmBuf.writeBigUInt64LE(128n, 24);
        pmBuf.writeBigUInt64LE(2n, 32);
        pmBuf.writeBigUInt64LE(130n, 40);
        pmBuf.writeBigUInt64LE(130n, 56);
        pmBuf[96] = 1; pmBuf[97] = 1; pmBuf[98] = 1; pmBuf[99] = 1;
        pmBuf[100] = 0; pmBuf[101] = 14;
        pmBuf.writeInt32LE(-844000000, 102);
        pmBuf.writeInt32LE(359000000, 106);
        pmBuf.writeInt32LE(-842000000, 110);
        pmBuf.writeInt32LE(360500000, 114);
        pmBuf[118] = 10;
        pmBuf.writeInt32LE(-843000000, 119);
        pmBuf.writeInt32LE(359750000, 123);
        pmBuf.write('{}', 128, 'utf8');

        const mapUp = await context.request.post(
            'https://oscar.local/sensorhub/oscar/extensions/maps/upload?filename=ci-region.pmtiles&displayName=CI%20Offline%20Region&defaultBasemap=true',
            { headers: { ...extHeaders, 'Content-Type': 'application/octet-stream' }, data: pmBuf },
        );
        assert.equal(mapUp.status(), 200, `PMTiles upload failed: ${mapUp.status()}`);
        assert.equal((await mapUp.json()).maps?.customActive, true);

        const rangeRes = await context.request.get(
            'https://oscar.local/sensorhub/oscar/extensions/maps/tiles/ci-region.pmtiles',
            { headers: { Range: 'bytes=0-126' } },
        );
        assert.equal(rangeRes.status(), 206, `Expected HTTP 206 Partial Content for PMTiles range, got ${rangeRes.status()}`);
        assert.equal((await rangeRes.body()).length, 127);

        // 8c. Spectroscopy isotope library upload & mode toggle
        const specLib = JSON.stringify({
            schemaVersion: 1,
            libraryId: 'ci-riid-v1',
            version: '1.0.0',
            isotopes: [{ name: 'Cs-137', category: 'Industrial', energiesKeV: [661.7], windowKeV: 20.0, minSnr: 3.5 }],
        });
        const specUp = await context.request.post(
            'https://oscar.local/sensorhub/oscar/extensions/spectroscopy/upload?filename=ci-isotopes.json&executionMode=override',
            { headers: { ...extHeaders, 'Content-Type': 'application/octet-stream' }, data: Buffer.from(specLib, 'utf8') },
        );
        assert.equal(specUp.status(), 200);
        const specJson = await specUp.json();
        assert.equal(specJson.spectroscopy?.customActive, true);
        assert.equal(specJson.spectroscopy?.executionMode, 'override');

        // 8d. Private key rejection (HTTP 400) + valid public CA X.509 upload
        const fakeKey = ['-----BEGIN ' + 'PRIVATE KEY-----', 'dGVzdA==', '-----END ' + 'PRIVATE KEY-----'].join('\n');
        const badCert = await context.request.post(
            'https://oscar.local/sensorhub/oscar/extensions/trusted-certs/upload?filename=bad-key.pem',
            { headers: { ...extHeaders, 'Content-Type': 'application/octet-stream' }, data: Buffer.from(fakeKey, 'utf8') },
        );
        assert.equal(badCert.status(), 400, `Expected 400 when private key material is uploaded, got ${badCert.status()}`);

        const testCaCert = [
            '-----BEGIN ' + 'CERTIFICATE-----',
            'MIIB6DCCAY2gAwIBAgIUDu7BhMC7VJ2L5aY7wnQlr9cjy3owCgYIKoZIzj0EAwIw',
            'STErMCkGA1UEAwwiT1NDQVIgUmVncmVzc2lvbiBFcGhlbWVyYWwgVGVzdCBDQTEa',
            'MBgGA1UECgwRT1JOTCBUZXN0IEZpeHR1cmUwHhcNMjYxMTE5MTkyNTA0WhcNMzYx',
            'MTE2MTkyNTA0WjBJMSswKQYDVQQDDCJPU0NBUiBSZWdyZXNzaW9uIEVwaGVtZXJh',
            'bCBUZXN0IENBMRowGAYDVQQKDBFPUk5MIFRlc3QgRml4dHVyZTBZMBMGByqGSM49',
            'AgEGCCqGSM49AwEHA0IABI+/9JGj86a2MjXJt6OfpMJzak0ImBKt6HJhINquNy1O',
            'yNbV+mBrHnim/6w/BfG1CjpkGTTfIsVGhKQsA4iZoGyjUzBRMB0GA1UdDgQWBBQ8',
            '5g23KIfKnsay6z9P8mcLuv68ejAfBgNVHSMEGDAWgBQ85g23KIfKnsay6z9P8mcL',
            'uv68ejAPBgNVHRMBAf8EBTADAQH/MAoGCCqGSM49BAMCA0kAMEYCIQDsKKITGSgj',
            'RM6/swph2ag5mO/yv8qvWLLgEmMwfvWeEgIhAICvvV/YhZ7Pq3z3fPqtXOSkPY5G',
            'yVbiYD94Kvx47zvG',
            '-----END ' + 'CERTIFICATE-----',
        ].join('\n');
        const goodCert = await context.request.post(
            'https://oscar.local/sensorhub/oscar/extensions/trusted-certs/upload?filename=ci-test-ca.pem',
            { headers: { ...extHeaders, 'Content-Type': 'application/octet-stream' }, data: Buffer.from(testCaCert, 'utf8') },
        );
        assert.equal(goodCert.status(), 200, `Expected 200 uploading public X.509 CA cert, got ${goodCert.status()}`);
        assert.equal((await goodCert.json()).trustedCerts?.customActive, true);

        // 8e. Agency Adjudication Policy Pack upload & export
        const policyDoc = JSON.stringify({
            schemaVersion: 1,
            packId: 'ci-policy-v1',
            version: '1.0.0',
            agencyName: 'CI Port Test',
            codes: [{ code: 741, label: 'CI Cleared Medical Permit' }],
        });
        const polUp = await context.request.post(
            'https://oscar.local/sensorhub/oscar/extensions/policy-packs/upload?filename=ci-policy.json',
            { headers: { ...extHeaders, 'Content-Type': 'application/octet-stream' }, data: Buffer.from(policyDoc, 'utf8') },
        );
        assert.equal(polUp.status(), 200);
        assert.equal((await polUp.json()).policyPacks?.customActive, true);

        const polExp = await context.request.get('https://oscar.local/sensorhub/oscar/extensions/policy-packs/export');
        assert.equal(polExp.status(), 200);
        assert.ok((await polExp.text()).includes('CI Cleared Medical Permit'));
    } finally {
        // Restore all domains cleanly to shipped defaults
        await context.request.post('https://oscar.local/sensorhub/oscar/extensions/ocr/action', {
            headers: { ...extHeaders, 'Content-Type': 'application/json' }, data: { action: 'reset' },
        }).catch(() => {});
        await context.request.post('https://oscar.local/sensorhub/oscar/extensions/maps/action', {
            headers: { ...extHeaders, 'Content-Type': 'application/json' }, data: { action: 'delete-pack', fileName: 'ci-region.pmtiles' },
        }).catch(() => {});
        await context.request.post('https://oscar.local/sensorhub/oscar/extensions/maps/action', {
            headers: { ...extHeaders, 'Content-Type': 'application/json' }, data: { action: 'reset' },
        }).catch(() => {});
        await context.request.post('https://oscar.local/sensorhub/oscar/extensions/spectroscopy/action', {
            headers: { ...extHeaders, 'Content-Type': 'application/json' }, data: { action: 'reset' },
        }).catch(() => {});
        await context.request.post('https://oscar.local/sensorhub/oscar/extensions/trusted-certs/action', {
            headers: { ...extHeaders, 'Content-Type': 'application/json' }, data: { action: 'reset' },
        }).catch(() => {});
        await context.request.post('https://oscar.local/sensorhub/oscar/extensions/policy-packs/action', {
            headers: { ...extHeaders, 'Content-Type': 'application/json' }, data: { action: 'reset' },
        }).catch(() => {});
    }
    const postResetRes = await context.request.get('https://oscar.local/sensorhub/oscar/extensions/status');
    assert.equal(postResetRes.status(), 200);
    const postReset = await postResetRes.json();
    assert.equal(postReset.ocr?.customActive, false, 'Expected OCR reset to shipped default');
    assert.equal(postReset.maps?.customActive, false, 'Expected Maps reset to shipped default');
    assert.equal(postReset.spectroscopy?.customActive, false, 'Expected Spectroscopy reset to shipped default');
    assert.equal(postReset.trustedCerts?.customActive, false, 'Expected Trusted CAs reset to shipped default');
    assert.equal(postReset.policyPacks?.customActive, false, 'Expected Policy Packs reset to shipped default');
} finally {
    await browser.close();
}
console.log('Playwright UI, TLS gateway, ConSys API, and 50-lane fixture checks passed.');
NODE
)

printf '== Step 4: Verify live archive CLI and coordinated online single-snapshot backup ==\n'
sudo bash "$deploy_dir/oscar.sh" archive status
sudo bash "$deploy_dir/oscar.sh" archive verify
sudo bash "$deploy_dir/oscar.sh" backup

backup_id=$(sudo find "$backup_dir" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%f\n' | sort | tail -n1)
[[ -n $backup_id ]] || { printf 'ERROR: oscar.sh backup did not produce a snapshot directory in %s\n' "$backup_dir" >&2; exit 1; }
sudo bash "$deploy_dir/oscar.sh" backup-verify "$backup_id"

printf 'Live OSCAR %s deployment, Playwright UI, ConSys API, and backup verification succeeded (snapshot %s).\n' "$version" "$backup_id"
