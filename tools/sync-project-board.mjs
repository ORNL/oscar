#!/usr/bin/env node
/**
 * Idempotently creates and synchronizes the ORNL GitHub Projects v2 Kanban board
 * ("OSCAR Platform Roadmap & Release Tracker") with Incorporated (v3.10-v3.11.15),
 * In Review / Draft PR (v3.12.0), and Planned (v3.12.0) items across ORNL/*.
 *
 * Prerequisite (one-time token scope grant):
 *   gh auth refresh -h github.com -s project,read:project
 *
 * Usage:
 *   node tools/sync-project-board.mjs [--dry-run]
 */

import { execFileSync } from 'node:child_process';

const ORG_LOGIN = 'ORNL';
const PROJECT_TITLE = 'OSCAR Platform Roadmap & Release Tracker';
const DRY_RUN = process.argv.includes('--dry-run');

const BOARD_ITEMS = [
    // Incorporated (v3.10.0 - v3.11.15)
    { repo: 'ORNL/oscar', kind: 'issue', number: 78, targetColumn: 'Done' },
    { repo: 'ORNL/oscar', kind: 'issue', number: 79, targetColumn: 'Done' },
    { repo: 'ORNL/oscar', kind: 'issue', number: 73, targetColumn: 'Done' },
    { repo: 'ORNL/oscar', kind: 'issue', number: 49, targetColumn: 'Done' },
    { repo: 'ORNL/osh-core', kind: 'pr', number: 10, targetColumn: 'Done' },
    { repo: 'ORNL/osh-addons', kind: 'pr', number: 20, targetColumn: 'Done' },
    { repo: 'ORNL/osh-oakridge-modules', kind: 'pr', number: 58, targetColumn: 'Done' },
    { repo: 'ORNL/osh-oakridge-modules', kind: 'pr', number: 60, targetColumn: 'Done' },
    { repo: 'ORNL/osh-oakridge-modules', kind: 'pr', number: 61, targetColumn: 'Done' },
    { repo: 'ORNL/oscar-viewer', kind: 'pr', number: 51, targetColumn: 'Done' },
    { repo: 'ORNL/oscar-viewer', kind: 'pr', number: 52, targetColumn: 'Done' },
    { repo: 'ORNL/oscar-regression', kind: 'pr', number: 33, targetColumn: 'Done' },
    { repo: 'ORNL/oscar-video-guides', kind: 'pr', number: 11, targetColumn: 'Done' },
    { repo: 'ORNL/oscar', kind: 'pr', number: 83, targetColumn: 'Done' },

    // Incorporated (v3.12.0 — Option A Split-at-Export, 10-Year Scale, Mobile Detectors, Custom Dashboards & Field Cutover)
    { repo: 'ORNL/osh-core', kind: 'pr', number: 11, targetColumn: 'Done' },
    { repo: 'ORNL/osh-addons', kind: 'pr', number: 22, targetColumn: 'Done' },
    { repo: 'ORNL/osh-oakridge-modules', kind: 'pr', number: 64, targetColumn: 'Done' },
    { repo: 'ORNL/oscar-viewer', kind: 'pr', number: 53, targetColumn: 'Done' },
    { repo: 'ORNL/oscar-viewer', kind: 'pr', number: 54, targetColumn: 'Done' },
    { repo: 'ORNL/oscar-video-guides', kind: 'pr', number: 12, targetColumn: 'Done' },
    { repo: 'ORNL/oscar-regression', kind: 'pr', number: 34, targetColumn: 'Done' },
    { repo: 'ORNL/oscar', kind: 'pr', number: 88, targetColumn: 'Done' },
    { repo: 'ORNL/oscar', kind: 'issue', number: 80, targetColumn: 'Done' },
    { repo: 'ORNL/oscar', kind: 'issue', number: 81, targetColumn: 'Done' },
    { repo: 'ORNL/osh-oakridge-modules', kind: 'pr', number: 57, targetColumn: 'Done' },
    { repo: 'ORNL/oscar-viewer', kind: 'pr', number: 49, targetColumn: 'Done' },
    { repo: 'ORNL/oscar', kind: 'pr', number: 76, targetColumn: 'Done' },
    { repo: 'ORNL/oscar-viewer', kind: 'pr', number: 50, targetColumn: 'Done' },
    { repo: 'ORNL/oscar', kind: 'issue', number: 84, targetColumn: 'Done' },
    { repo: 'ORNL/osh-addons', kind: 'issue', number: 19, targetColumn: 'Done' },
    { repo: 'ORNL/osh-addons', kind: 'issue', number: 21, targetColumn: 'Done' },
    { repo: 'ORNL/osh-oakridge-modules', kind: 'issue', number: 63, targetColumn: 'Done' },
    { repo: 'ORNL/oscar', kind: 'issue', number: 77, targetColumn: 'Done' },
    { repo: 'ORNL/oscar', kind: 'issue', number: 75, targetColumn: 'Done' },
    { repo: 'ORNL/oscar', kind: 'issue', number: 74, targetColumn: 'Done' },
    { repo: 'ORNL/osh-oakridge-modules', kind: 'issue', number: 52, targetColumn: 'Done' },
    { repo: 'ORNL/oscar-viewer', kind: 'issue', number: 46, targetColumn: 'Done' },
    { repo: 'ORNL/osh-oakridge-modules', kind: 'issue', number: 49, targetColumn: 'Done' },
    { repo: 'ORNL/osh-oakridge-modules', kind: 'issue', number: 41, targetColumn: 'Done' },
    { repo: 'ORNL/oscar-viewer', kind: 'issue', number: 44, targetColumn: 'Done' },
    { repo: 'ORNL/oscar', kind: 'issue', number: 87, targetColumn: 'Done' },

    // Incorporated (v3.12.1 — Staging CI Workflow, Sandbox TTL Auto-Shutdown & Printable Technician Handover One-Sheet PDF)
    { repo: 'ORNL/oscar', kind: 'pr', number: 89, targetColumn: 'Done' },
    { repo: 'ORNL/oscar', kind: 'pr', number: 90, targetColumn: 'Done' },
    { repo: 'ORNL/oscar', kind: 'pr', number: 91, targetColumn: 'Done' },
    { repo: 'ORNL/oscar', kind: 'pr', number: 92, targetColumn: 'Done' },
    { repo: 'ORNL/oscar-viewer', kind: 'pr', number: 55, targetColumn: 'Done' },
    { repo: 'ORNL/osh-oakridge-modules', kind: 'pr', number: 65, targetColumn: 'Done' },
    { repo: 'ORNL/oscar-regression', kind: 'pr', number: 35, targetColumn: 'Done' },
];

function ghGraphql(query, variables = {}) {
    const args = ['api', 'graphql', '-f', `query=${query}`];
    for (const [key, value] of Object.entries(variables)) {
        if (typeof value === 'number') {
            args.push('-F', `${key}=${value}`);
        } else {
            args.push('-f', `${key}=${value}`);
        }
    }
    const raw = execFileSync('gh', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
    return JSON.parse(raw);
}

function resolveContentNodeId(repoFullName, kind, number) {
    const [owner, name] = repoFullName.split('/');
    const field = kind === 'pr' ? 'pullRequest' : 'issue';
    const data = ghGraphql(
        `query($owner: String!, $name: String!, $number: Int!) {
            repository(owner: $owner, name: $name) {
                ${field}(number: $number) { id title url state }
            }
        }`,
        { owner, name, number },
    );
    return data?.data?.repository?.[field] ?? null;
}

function main() {
    if (DRY_RUN) {
        console.log(`[dry-run] Validating ${BOARD_ITEMS.length} roadmap items across ${ORG_LOGIN}/*...`);
        for (const item of BOARD_ITEMS) {
            const node = resolveContentNodeId(item.repo, item.kind, item.number);
            if (!node) {
                throw new Error(`Could not resolve ${item.repo}#${item.number}`);
            }
            console.log(`  [${item.targetColumn}] ${item.repo}#${item.number} (${node.state}) — ${node.title}`);
        }
        console.log(`[dry-run] All ${BOARD_ITEMS.length} items resolved cleanly.`);
        return;
    }

    let orgData;
    try {
        orgData = ghGraphql(
            `query($login: String!) {
                organization(login: $login) {
                    id
                    projectsV2(first: 50) {
                        nodes { id number title url }
                    }
                }
            }`,
            { login: ORG_LOGIN },
        );
    } catch (error) {
        const stderr = String(error?.stderr || error?.message || error);
        if (stderr.includes('read:project') || stderr.includes('INSUFFICIENT_SCOPES')) {
            console.error(
                'GitHub CLI token is missing Projects v2 scopes.\n' +
                'Run once:\n' +
                '  gh auth refresh -h github.com -s project,read:project\n' +
                'Then re-run:\n' +
                '  node tools/sync-project-board.mjs',
            );
            process.exit(2);
        }
        throw error;
    }

    const org = orgData.data.organization;
    let project = org.projectsV2.nodes.find((candidate) => candidate.title === PROJECT_TITLE);
    if (!project) {
        const created = ghGraphql(
            `mutation($ownerId: ID!, $title: String!) {
                createProjectV2(input: { ownerId: $ownerId, title: $title }) {
                    projectV2 { id number title url }
                }
            }`,
            { ownerId: org.id, title: PROJECT_TITLE },
        );
        project = created.data.createProjectV2.projectV2;
        console.log(`Created GitHub Project v2 #${project.number}: ${project.url}`);
    } else {
        console.log(`Updating GitHub Project v2 #${project.number}: ${project.url}`);
    }

    // Link primary repositories to the Project v2 board for discoverability on each repo's Projects tab
    for (const repoName of ['oscar', 'osh-oakridge-modules', 'oscar-viewer', 'osh-core', 'osh-addons', 'oscar-regression']) {
        try {
            const repoInfo = ghGraphql(
                `query($owner: String!, $name: String!) { repository(owner: $owner, name: $name) { id } }`,
                { owner: ORG_LOGIN, name: repoName },
            );
            const repoId = repoInfo?.data?.repository?.id;
            if (repoId) {
                ghGraphql(
                    `mutation($projectId: ID!, $repositoryId: ID!) {
                        linkProjectV2ToRepository(input: { projectId: $projectId, repositoryId: $repositoryId }) {
                            repository { nameWithOwner }
                        }
                    }`,
                    { projectId: project.id, repositoryId: repoId },
                );
            }
        } catch {
            // Already linked or non-fatal
        }
    }

    const fieldsData = ghGraphql(
        `query($projectId: ID!) {
            node(id: $projectId) {
                ... on ProjectV2 {
                    fields(first: 30) {
                        nodes {
                            ... on ProjectV2SingleSelectField {
                                id
                                name
                                options { id name }
                            }
                        }
                    }
                }
            }
        }`,
        { projectId: project.id },
    );
    const statusField = fieldsData.data.node.fields.nodes.find((field) => field?.name === 'Status');

    for (const item of BOARD_ITEMS) {
        const content = resolveContentNodeId(item.repo, item.kind, item.number);
        if (!content) {
            console.warn(`Skipping unresolved ${item.repo}#${item.number}`);
            continue;
        }
        const added = ghGraphql(
            `mutation($projectId: ID!, $contentId: ID!) {
                addProjectV2ItemById(input: { projectId: $projectId, contentId: $contentId }) {
                    item { id }
                }
            }`,
            { projectId: project.id, contentId: content.id },
        );
        const itemId = added.data.addProjectV2ItemById.item.id;
        if (statusField) {
            const matchedOption = statusField.options.find((opt) =>
                opt.name.toLowerCase() === item.targetColumn.toLowerCase() ||
                (item.targetColumn === 'Done' && /done|incorporated|complete/i.test(opt.name)) ||
                (item.targetColumn === 'In Progress' && /progress|review|active/i.test(opt.name)) ||
                (item.targetColumn === 'Todo' && /todo|planned|backlog/i.test(opt.name)),
            );
            if (matchedOption) {
                ghGraphql(
                    `mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $optionId: String!) {
                        updateProjectV2ItemFieldValue(input: {
                            projectId: $projectId,
                            itemId: $itemId,
                            fieldId: $fieldId,
                            value: { singleSelectOptionId: $optionId }
                        }) {
                            projectV2Item { id }
                        }
                    }`,
                    {
                        projectId: project.id,
                        itemId,
                        fieldId: statusField.id,
                        optionId: matchedOption.id,
                    },
                );
            }
        }
        console.log(`Synced [${item.targetColumn}] ${item.repo}#${item.number}: ${content.title}`);
    }

    console.log(`\nProject board synchronized: ${project.url}`);
}

main();
