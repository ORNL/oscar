#!/usr/bin/env node
'use strict';

const { execFileSync } = require('node:child_process');
const fs = require('node:fs');
const https = require('node:https');
const path = require('node:path');

const BOT_LOGINS = new Set([
    'dependabot',
    'dependabot[bot]',
    'github-actions',
    'github-actions[bot]',
    'renovate',
    'renovate[bot]',
]);

const KNOWN_IDENTITY_RULES = [
    {
        login: 'earocorn',
        displayName: 'Alex Almanza',
        match: ({ name, emailLocal }) =>
            name === 'alex almanza' || name === 'earocorn' || emailLocal === 'alexalmanza',
    },
    {
        login: 'kalynstricklin',
        displayName: 'Kalyn Stallings',
        match: ({ name, emailLocal }) =>
            name === 'kalyn stallings' || name === 'kalyn stricklin' || name === 'kalynstricklin' || emailLocal === 'kalynstricklin',
    },
    {
        login: 'kyle-fitzp',
        displayName: 'Kyle Fitzpatrick',
        match: ({ name, emailLocal }) =>
            name === 'kyle fitzpatrick' || name === 'kyle-fitzp' || emailLocal === 'kyle.fitzpatrick',
    },
    {
        login: 'tyronechrisharris',
        displayName: 'Tyrone Harris',
        match: ({ name, emailLocal }) =>
            name === 'tyrone harris' || name === 'tyronechrisharris' || emailLocal === 'tyronechrisharris',
    },
    {
        login: 'drewbotts',
        displayName: 'Drew Botts',
        match: ({ name, emailLocal }) =>
            name === 'drew botts' || name === 'drewbotts' || emailLocal === 'drew.botts',
    },
];

function git(cwd, args, options = {}) {
    return execFileSync('git', args, {
        cwd,
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', options.allowFailure ? 'ignore' : 'pipe'],
    }).trim();
}

function tryGit(cwd, args) {
    try {
        return git(cwd, args, { allowFailure: true });
    } catch {
        return null;
    }
}

function parseSemverTag(tag) {
    const match = tag.match(/^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-([0-9A-Za-z.-]+))?$/);
    if (!match) {
        return null;
    }
    return {
        tag,
        major: Number(match[1]),
        minor: Number(match[2]),
        patch: Number(match[3]),
        prerelease: match[4] ?? null,
    };
}

function compareSemver(left, right) {
    if (left.major !== right.major) return left.major - right.major;
    if (left.minor !== right.minor) return left.minor - right.minor;
    if (left.patch !== right.patch) return left.patch - right.patch;
    if (left.prerelease === right.prerelease) return 0;
    if (left.prerelease === null) return 1;
    if (right.prerelease === null) return -1;
    return left.prerelease.localeCompare(right.prerelease);
}

function discoverPreviousTag(repoRoot, targetRef) {
    const targetCommit = git(repoRoot, ['rev-parse', `${targetRef}^{commit}`]);
    const rawTags = git(repoRoot, ['tag', '-l', 'v*']);
    const tags = rawTags
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter(Boolean)
        .map(parseSemverTag)
        .filter((entry) => entry && entry.prerelease === null);

    const targetSemver = parseSemverTag(targetRef);
    const candidates = tags.filter((entry) => {
        if (entry.tag === targetRef) return false;
        const tagCommit = tryGit(repoRoot, ['rev-parse', `${entry.tag}^{commit}`]);
        if (!tagCommit || tagCommit === targetCommit) return false;
        if (targetSemver && compareSemver(entry, targetSemver) >= 0) return false;
        const ancestorCheck = tryGit(repoRoot, ['merge-base', entry.tag, targetCommit]);
        return Boolean(ancestorCheck);
    });

    candidates.sort((a, b) => compareSemver(b, a));
    if (candidates.length === 0) {
        throw new Error(`Unable to determine previous release tag before ${targetRef}. Pass --previous-tag=<tag>.`);
    }
    return candidates[0].tag;
}

function parseGitHubRepoSlug(remoteUrl) {
    if (!remoteUrl) return null;
    const match = remoteUrl.match(/github\.com[:/]([^/\s]+\/[^/\s]+?)(?:\.git)?$/);
    return match ? match[1] : null;
}

function parseGitmodules(content) {
    const submodules = [];
    let current = null;
    for (const rawLine of content.split(/\r?\n/)) {
        const sectionMatch = rawLine.match(/^\s*\[submodule\s+"([^"]+)"\]\s*$/);
        if (sectionMatch) {
            if (current?.path) submodules.push(current);
            current = { name: sectionMatch[1], path: null, url: null };
            continue;
        }
        if (!current) continue;
        const kvMatch = rawLine.match(/^\s*(path|url)\s*=\s*(.+?)\s*$/);
        if (kvMatch) {
            current[kvMatch[1]] = kvMatch[2];
        }
    }
    if (current?.path) submodules.push(current);
    return submodules;
}

function getSubmoduleCommitAtRef(repoRoot, ref, submodulePath) {
    const line = tryGit(repoRoot, ['ls-tree', ref, '--', submodulePath]);
    if (!line) return null;
    const match = line.match(/^\d+\s+commit\s+([0-9a-f]{40})\t/);
    return match ? match[1] : null;
}

function ensureCommitAvailable(repoDir, sha) {
    if (!sha) return false;
    if (tryGit(repoDir, ['cat-file', '-e', `${sha}^{commit}`]) !== null) {
        const isShallow = tryGit(repoDir, ['rev-parse', '--is-shallow-repository']);
        if (isShallow === 'true') {
            tryGit(repoDir, ['fetch', '--unshallow', '--no-recurse-submodules', 'origin']);
        }
        return true;
    }
    tryGit(repoDir, ['fetch', '--unshallow', '--no-recurse-submodules', 'origin']);
    if (tryGit(repoDir, ['cat-file', '-e', `${sha}^{commit}`]) !== null) {
        return true;
    }
    tryGit(repoDir, ['fetch', '--no-recurse-submodules', 'origin', sha]);
    return tryGit(repoDir, ['cat-file', '-e', `${sha}^{commit}`]) !== null;
}

function collectRawPeopleFromGitRange(repoDir, oldSha, newSha) {
    if (!oldSha || !newSha || oldSha === newSha) {
        return [];
    }
    const format = '%H%x1f%aN%x1f%aE%x1f%B%x1e';
    const raw = git(repoDir, ['log', `${oldSha}..${newSha}`, `--format=${format}`]);
    if (!raw) return [];
    const entries = [];
    for (const record of raw.split('\x1e')) {
        const trimmed = record.trim();
        if (!trimmed) continue;
        const [sha, authorName, authorEmail, body = ''] = trimmed.split('\x1f');
        if (authorName || authorEmail) {
            entries.push({ sha, name: (authorName || '').trim(), email: (authorEmail || '').trim() });
        }
        const coAuthorPattern = /^Co-authored-by:\s*(.+?)\s*<([^>]+)>\s*$/gim;
        for (const match of body.matchAll(coAuthorPattern)) {
            entries.push({ sha, name: match[1].trim(), email: match[2].trim() });
        }
    }
    return entries;
}

function extractOshJsLockCommit(viewerDir, commitSha) {
    const lockContent = tryGit(viewerDir, ['show', `${commitSha}:package-lock.json`]);
    if (!lockContent) return null;
    const match = lockContent.match(/github\.com[:/][^/"\s]+\/osh-js(?:\.git)?(?:#|\/tar\.gz\/)([0-9a-f]{40})/);
    return match ? match[1] : null;
}

function fetchGitHubJson(apiPath, token) {
    const headers = {
        Accept: 'application/vnd.github+json',
        'User-Agent': 'ornl-oscar-release-contributors',
    };
    if (token) {
        headers.Authorization = `Bearer ${token}`;
    }
    return new Promise((resolve) => {
        const request = https.get(
            {
                hostname: 'api.github.com',
                path: apiPath,
                headers,
                timeout: 8000,
            },
            (response) => {
                let data = '';
                response.setEncoding('utf8');
                response.on('data', (chunk) => {
                    data += chunk;
                });
                response.on('end', () => {
                    if (response.statusCode && response.statusCode >= 200 && response.statusCode < 300) {
                        try {
                            resolve(JSON.parse(data));
                            return;
                        } catch {
                            resolve(null);
                            return;
                        }
                    }
                    resolve(null);
                });
            },
        );
        request.on('error', () => resolve(null));
        request.on('timeout', () => {
            request.destroy();
            resolve(null);
        });
    });
}

function isBotIdentity(name, email, login) {
    const lowerName = (name || '').toLowerCase();
    const lowerEmail = (email || '').toLowerCase();
    const lowerLogin = (login || '').toLowerCase();
    if (BOT_LOGINS.has(lowerLogin) || BOT_LOGINS.has(lowerName)) return true;
    if (lowerLogin.endsWith('[bot]') || lowerName.endsWith('[bot]')) return true;
    if (lowerEmail === 'noreply@github.com' && lowerName === 'github') return true;
    return false;
}

function resolveStaticIdentity(name, email) {
    const trimmedName = (name || '').trim();
    const lowerName = trimmedName.toLowerCase();
    const lowerEmail = (email || '').trim().toLowerCase();
    const emailLocal = lowerEmail.split('@')[0] || '';

    const noreplyMatch = lowerEmail.match(/^(?:\d+\+)?([a-z0-9-]+)@users\.noreply\.github\.com$/i);
    const loginFromEmail = noreplyMatch ? noreplyMatch[1] : null;

    for (const rule of KNOWN_IDENTITY_RULES) {
        if (
            (loginFromEmail && loginFromEmail.toLowerCase() === rule.login.toLowerCase()) ||
            rule.match({ name: lowerName, emailLocal })
        ) {
            return { login: rule.login, displayName: rule.displayName };
        }
    }

    if (loginFromEmail) {
        const displayName =
            trimmedName && trimmedName.toLowerCase() !== loginFromEmail.toLowerCase()
                ? trimmedName
                : loginFromEmail;
        return { login: loginFromEmail, displayName };
    }

    return null;
}

async function collectReleaseContributors({
    repoRoot,
    targetRef = 'HEAD',
    previousTag = null,
    githubToken = process.env.GITHUB_TOKEN || process.env.GH_TOKEN || '',
    enableNetworkLookup = true,
}) {
    const resolvedRoot = path.resolve(repoRoot);
    const resolvedPreviousTag = previousTag || discoverPreviousTag(resolvedRoot, targetRef);
    const topRemoteSlug =
        parseGitHubRepoSlug(tryGit(resolvedRoot, ['remote', 'get-url', 'origin'])) || 'ORNL/oscar';

    const componentRanges = [];
    const rawContributions = [];

    const topOldSha = git(resolvedRoot, ['rev-parse', `${resolvedPreviousTag}^{commit}`]);
    const topNewSha = git(resolvedRoot, ['rev-parse', `${targetRef}^{commit}`]);
    componentRanges.push({
        repo: topRemoteSlug,
        oldRef: resolvedPreviousTag,
        newRef: targetRef === 'HEAD' ? topNewSha.slice(0, 8) : targetRef,
        compareUrl: `https://github.com/${topRemoteSlug}/compare/${resolvedPreviousTag}...${
            targetRef === 'HEAD' ? topNewSha : targetRef
        }`,
    });
    for (const person of collectRawPeopleFromGitRange(resolvedRoot, topOldSha, topNewSha)) {
        rawContributions.push({ ...person, repo: topRemoteSlug });
    }

    const gitmodulesContent = tryGit(resolvedRoot, ['show', `${targetRef}:.gitmodules`]) || '';
    const submodules = parseGitmodules(gitmodulesContent);

    for (const submodule of submodules) {
        const oldSha = getSubmoduleCommitAtRef(resolvedRoot, resolvedPreviousTag, submodule.path);
        const newSha = getSubmoduleCommitAtRef(resolvedRoot, targetRef, submodule.path);
        if (!oldSha || !newSha || oldSha === newSha) continue;

        const repoSlug = parseGitHubRepoSlug(submodule.url) || submodule.path;
        const submoduleDir = path.join(resolvedRoot, submodule.path);
        if (fs.existsSync(submoduleDir)) {
            ensureCommitAvailable(submoduleDir, oldSha);
            ensureCommitAvailable(submoduleDir, newSha);
            for (const person of collectRawPeopleFromGitRange(submoduleDir, oldSha, newSha)) {
                rawContributions.push({ ...person, repo: repoSlug });
            }

            if (submodule.path === 'web/oscar-viewer') {
                const oldOshJsSha = extractOshJsLockCommit(submoduleDir, oldSha);
                const newOshJsSha = extractOshJsLockCommit(submoduleDir, newSha);
                if (oldOshJsSha && newOshJsSha && oldOshJsSha !== newOshJsSha) {
                    const oshJsSlug = `${topRemoteSlug.split('/')[0]}/osh-js`;
                    componentRanges.push({
                        repo: oshJsSlug,
                        oldRef: oldOshJsSha.slice(0, 8),
                        newRef: newOshJsSha.slice(0, 8),
                        compareUrl: `https://github.com/${oshJsSlug}/compare/${oldOshJsSha}...${newOshJsSha}`,
                    });
                    if (enableNetworkLookup) {
                        const compareData = await fetchGitHubJson(
                            `/repos/${oshJsSlug}/compare/${oldOshJsSha}...${newOshJsSha}`,
                            githubToken,
                        );
                        for (const commitEntry of compareData?.commits ?? []) {
                            const gitAuthor = commitEntry?.commit?.author ?? {};
                            const ghLogin = commitEntry?.author?.login ?? null;
                            rawContributions.push({
                                sha: commitEntry.sha,
                                name: gitAuthor.name || ghLogin || '',
                                email: gitAuthor.email || '',
                                preResolvedLogin: ghLogin,
                                repo: oshJsSlug,
                            });
                        }
                    }
                }
            }
        }

        componentRanges.push({
            repo: repoSlug,
            oldRef: oldSha.slice(0, 8),
            newRef: newSha.slice(0, 8),
            compareUrl: `https://github.com/${repoSlug}/compare/${oldSha}...${newSha}`,
        });
    }

    const apiCacheByEmail = new Map();
    const contributorsByKey = new Map();

    for (const item of rawContributions) {
        if (isBotIdentity(item.name, item.email, item.preResolvedLogin)) {
            continue;
        }
        let identity = resolveStaticIdentity(item.name, item.email);
        if (!identity && item.preResolvedLogin) {
            const matchedKnown = KNOWN_IDENTITY_RULES.find(
                (rule) => rule.login.toLowerCase() === item.preResolvedLogin.toLowerCase(),
            );
            identity = {
                login: item.preResolvedLogin,
                displayName: matchedKnown?.displayName || item.name || item.preResolvedLogin,
            };
        }
        if (!identity && enableNetworkLookup && item.sha && item.repo.includes('/')) {
            const cacheKey = `${item.repo}:${item.email.toLowerCase()}`;
            if (!apiCacheByEmail.has(cacheKey)) {
                const commitInfo = await fetchGitHubJson(`/repos/${item.repo}/commits/${item.sha}`, githubToken);
                apiCacheByEmail.set(cacheKey, commitInfo?.author?.login ?? null);
            }
            const apiLogin = apiCacheByEmail.get(cacheKey);
            if (apiLogin) {
                if (isBotIdentity(item.name, item.email, apiLogin)) {
                    continue;
                }
                const matchedKnown = KNOWN_IDENTITY_RULES.find(
                    (rule) => rule.login.toLowerCase() === apiLogin.toLowerCase(),
                );
                identity = {
                    login: apiLogin,
                    displayName: matchedKnown?.displayName || item.name || apiLogin,
                };
            }
        }

        const key = identity?.login ? `gh:${identity.login.toLowerCase()}` : `name:${item.name.toLowerCase()}`;
        const existing = contributorsByKey.get(key) || {
            login: identity?.login ?? null,
            displayName: identity?.displayName || item.name || item.email,
            repos: new Set(),
        };
        if (!existing.login && identity?.login) {
            existing.login = identity.login;
        }
        if (identity?.displayName) {
            existing.displayName = identity.displayName;
        }
        existing.repos.add(item.repo);
        contributorsByKey.set(key, existing);
    }

    const orderedRanges = [
        componentRanges[0],
        ...componentRanges.slice(1).sort((a, b) => a.repo.localeCompare(b.repo)),
    ];
    const repoOrder = orderedRanges.map((entry) => entry.repo);
    const contributors = [...contributorsByKey.values()]
        .map((entry) => ({
            login: entry.login,
            displayName: entry.displayName,
            repos: [...entry.repos].sort((a, b) => {
                const ia = repoOrder.indexOf(a);
                const ib = repoOrder.indexOf(b);
                if (ia !== -1 && ib !== -1) return ia - ib;
                if (ia !== -1) return -1;
                if (ib !== -1) return 1;
                return a.localeCompare(b);
            }),
        }))
        .sort((a, b) => a.displayName.localeCompare(b.displayName, 'en', { sensitivity: 'base' }));

    return {
        previousTag: resolvedPreviousTag,
        targetRef,
        contributors,
        componentRanges: orderedRanges,
    };
}

function renderContributorsMarkdown(summary) {
    const lines = [
        '### Contributors',
        `Thanks to everyone who contributed across \`ORNL/oscar\` and its submodules since \`${summary.previousTag}\`:`,
    ];
    for (const contributor of summary.contributors) {
        const handleText = contributor.login ? ` (@${contributor.login})` : '';
        const repoList = contributor.repos.map((repo) => `\`${repo}\``).join(', ');
        lines.push(`- **${contributor.displayName}**${handleText} — ${repoList}`);
    }
    lines.push('');
    lines.push('### Full changelog across repository and submodules');
    for (const range of summary.componentRanges) {
        lines.push(`- **\`${range.repo}\`**: [\`${range.oldRef}...${range.newRef}\`](${range.compareUrl})`);
    }
    return `${lines.join('\n')}\n`;
}

function ensureContributorsInReleaseNotes(existingMarkdown, summary) {
    const trimmed = existingMarkdown.replace(/\s+$/, '');
    const hasHeading = /^#{2,3}\s+Contributors\b/im.test(trimmed);
    if (!hasHeading) {
        return `${trimmed}\n\n${renderContributorsMarkdown(summary)}`;
    }
    const missingHandles = summary.contributors.filter(
        (contributor) =>
            contributor.login &&
            !new RegExp(`(^|[^A-Za-z0-9_])@${contributor.login}\\b`, 'i').test(trimmed),
    );
    if (missingHandles.length === 0) {
        return `${trimmed}\n`;
    }
    const additionalLines = missingHandles.map((contributor) => {
        const repoList = contributor.repos.map((repo) => `\`${repo}\``).join(', ');
        return `- **${contributor.displayName}** (@${contributor.login}) — ${repoList}`;
    });
    return `${trimmed}\n${additionalLines.join('\n')}\n`;
}

async function main() {
    const args = process.argv.slice(2);
    let repoRoot = path.resolve(__dirname, '..');
    let targetRef = 'HEAD';
    let previousTag = null;
    let ensureInFile = null;
    let outputJson = false;
    let enableNetworkLookup = true;

    for (const arg of args) {
        if (arg.startsWith('--repo-root=')) {
            repoRoot = arg.slice('--repo-root='.length);
        } else if (arg.startsWith('--tag=')) {
            targetRef = arg.slice('--tag='.length);
        } else if (arg.startsWith('--previous-tag=')) {
            previousTag = arg.slice('--previous-tag='.length);
        } else if (arg.startsWith('--ensure-in=')) {
            ensureInFile = arg.slice('--ensure-in='.length);
        } else if (arg === '--json') {
            outputJson = true;
        } else if (arg === '--no-network') {
            enableNetworkLookup = false;
        } else {
            process.stderr.write(
                'Usage: node tools/collect-release-contributors.js [--repo-root=DIR] [--tag=REF] [--previous-tag=TAG] [--ensure-in=FILE] [--json] [--no-network]\n',
            );
            process.exit(2);
        }
    }

    const summary = await collectReleaseContributors({
        repoRoot,
        targetRef,
        previousTag,
        enableNetworkLookup,
    });

    if (ensureInFile) {
        const existing = fs.readFileSync(ensureInFile, 'utf8');
        const updated = ensureContributorsInReleaseNotes(existing, summary);
        fs.writeFileSync(ensureInFile, updated, 'utf8');
    }

    if (outputJson) {
        process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
    } else if (!ensureInFile) {
        process.stdout.write(renderContributorsMarkdown(summary));
    }
}

if (require.main === module) {
    main().catch((error) => {
        process.stderr.write(`${error.stack || error.message}\n`);
        process.exit(1);
    });
}

module.exports = {
    collectReleaseContributors,
    discoverPreviousTag,
    ensureContributorsInReleaseNotes,
    parseGitmodules,
    renderContributorsMarkdown,
    resolveStaticIdentity,
};
