'use strict';

const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const {
    collectReleaseContributors,
    discoverPreviousTag,
    ensureContributorsInReleaseNotes,
    renderContributorsMarkdown,
} = require('./collect-release-contributors.js');

function git(cwd, args, env = {}) {
    return execFileSync('git', ['-c', 'commit.gpgSign=false', '-c', 'tag.gpgSign=false', ...args], {
        cwd,
        encoding: 'utf8',
        env: { ...process.env, ...env },
        stdio: ['ignore', 'pipe', 'pipe'],
    }).trim();
}

function commitAs(cwd, { name, email, message, file = 'README.md', content }) {
    fs.writeFileSync(path.join(cwd, file), content, 'utf8');
    git(cwd, ['add', file]);
    git(
        cwd,
        ['commit', '-m', message],
        {
            GIT_AUTHOR_NAME: name,
            GIT_AUTHOR_EMAIL: email,
            GIT_COMMITTER_NAME: name,
            GIT_COMMITTER_EMAIL: email,
        },
    );
    return git(cwd, ['rev-parse', 'HEAD']);
}

test('collectReleaseContributors aggregates top-level and submodule contributors since previous tag', async () => {
    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'oscar-contrib-test-'));
    try {
        const subDir = path.join(tempDir, 'sub-module-remote');
        const mainDir = path.join(tempDir, 'main-repo');
        fs.mkdirSync(subDir);
        fs.mkdirSync(mainDir);

        git(subDir, ['init', '-b', 'main']);
        commitAs(subDir, {
            name: 'Initial Author',
            email: '100+inituser@users.noreply.github.com',
            message: 'init submodule',
            content: 'v1\n',
        });

        git(mainDir, ['init', '-b', 'main']);
        git(mainDir, ['remote', 'add', 'origin', 'https://github.com/ORNL/oscar.git']);
        git(mainDir, ['-c', 'protocol.file.allow=always', 'submodule', 'add', subDir, 'include/osh-oakridge-modules']);
        // Normalize URL in .gitmodules to canonical GitHub slug for compare URL rendering
        fs.writeFileSync(
            path.join(mainDir, '.gitmodules'),
            [
                '[submodule "include/osh-oakridge-modules"]',
                '\tpath = include/osh-oakridge-modules',
                '\turl = https://github.com/ORNL/osh-oakridge-modules.git',
                '',
            ].join('\n'),
            'utf8',
        );
        git(mainDir, ['add', '.gitmodules']);
        commitAs(mainDir, {
            name: 'Initial Author',
            email: '100+inituser@users.noreply.github.com',
            message: 'release v3.10.0',
            content: 'base\n',
        });
        git(mainDir, ['tag', 'v3.10.0']);

        // Submodule commits by two distinct contributors + a bot + a Co-authored-by trailer
        const checkoutSubDir = path.join(mainDir, 'include/osh-oakridge-modules');
        commitAs(checkoutSubDir, {
            name: 'kyle-fitzp',
            email: 'kyle.fitzpatrick@botts-inc.com',
            message: 'Fix first neutron counts\n\nCo-authored-by: Kalyn Stallings <134666642+kalynstricklin@users.noreply.github.com>',
            content: 'v2\n',
        });
        commitAs(checkoutSubDir, {
            name: 'dependabot[bot]',
            email: '49699333+dependabot[bot]@users.noreply.github.com',
            message: 'chore(deps): bump dependency',
            content: 'v3\n',
        });

        git(mainDir, ['add', 'include/osh-oakridge-modules']);
        commitAs(mainDir, {
            name: 'Alex Almanza',
            email: 'alexalmanza@local.machine',
            message: 'Advance submodule and release 3.11.0',
            content: 'next\n',
        });
        git(mainDir, ['tag', 'v3.11.0']);

        assert.equal(discoverPreviousTag(mainDir, 'v3.11.0'), 'v3.10.0');

        const summary = await collectReleaseContributors({
            repoRoot: mainDir,
            targetRef: 'v3.11.0',
            enableNetworkLookup: false,
        });

        assert.equal(summary.previousTag, 'v3.10.0');
        assert.deepEqual(
            summary.contributors.map((entry) => ({
                login: entry.login,
                displayName: entry.displayName,
                repos: entry.repos,
            })),
            [
                {
                    login: 'earocorn',
                    displayName: 'Alex Almanza',
                    repos: ['ORNL/oscar'],
                },
                {
                    login: 'kalynstricklin',
                    displayName: 'Kalyn Stallings',
                    repos: ['ORNL/osh-oakridge-modules'],
                },
                {
                    login: 'kyle-fitzp',
                    displayName: 'Kyle Fitzpatrick',
                    repos: ['ORNL/osh-oakridge-modules'],
                },
            ],
        );

        const rendered = renderContributorsMarkdown(summary);
        assert.match(rendered, /\*\*Alex Almanza\*\* \(@earocorn\) — `ORNL\/oscar`/);
        assert.match(rendered, /\*\*Kalyn Stallings\*\* \(@kalynstricklin\) — `ORNL\/osh-oakridge-modules`/);
        assert.match(rendered, /\*\*Kyle Fitzpatrick\*\* \(@kyle-fitzp\) — `ORNL\/osh-oakridge-modules`/);
        assert.doesNotMatch(rendered, /dependabot/i);
        assert.doesNotMatch(rendered, /inituser/i);

        // Idempotence and missing-handle supplementation in ensureContributorsInReleaseNotes
        const baseNotes = '### Release overview\nExample release notes.\n';
        const appended = ensureContributorsInReleaseNotes(baseNotes, summary);
        assert.match(appended, /### Contributors/);
        assert.equal(ensureContributorsInReleaseNotes(appended, summary), appended);

        const partialNotes = '### Release overview\nNotes.\n\n### Contributors\n- **Alex Almanza** (@earocorn) — `ORNL/oscar`\n';
        const supplemented = ensureContributorsInReleaseNotes(partialNotes, summary);
        assert.match(supplemented, /@kalynstricklin/);
        assert.match(supplemented, /@kyle-fitzp/);
    } finally {
        fs.rmSync(tempDir, { recursive: true, force: true });
    }
});
