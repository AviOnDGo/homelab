---
name: "pr"
description: \"Create or update a GitHub Pull Request with compliant structure following AGENTS.md standards\"
type: "prompt"
category: "github"
icon: "🔀"
usage: "Type '/' in OpenCode terminal, search 'pr', select this command"
keywords: ["github", "pull-request", "pr", "review", "AGENTS.md", "openspec"]
---

# OpenCode Pull Request Orchestration

**Purpose**: Orchestrate creation and updating of GitHub Pull Requests per [AGENTS.md § 5️⃣ Pull Request Standards](../../AGENTS.md).

This command is a **lightweight wrapper** — detailed rules are centralized in `AGENTS.md` (the single source of truth). This file focuses on orchestration steps and verification.

**Supports both:**
- ✨ **Creating new PRs** — Create fresh pull request with new branch
- 🔄 **Updating existing PRs** — Update PR body, title, or add commits to existing open PR

---

## 🔄 Workflow

### 0. Detect: New PR or Update Existing?

**Reference**: [AGENTS.md § Git Safety Rules](../../AGENTS.md)

Determine the operation type:

**NEW PR Creation:**
- Current branch is new/unpushed
- No PR exists for this branch
- Operator says: "create PR", "open PR", "new PR"
- → Proceed to NEW PR CREATION PATH (Step 1-6)

**EXISTING PR Update:**
- Current branch already has an open PR
- Operator says: "update PR", "push changes to PR", "update description"
- → Proceed to EXISTING PR UPDATE PATH (Step 1-5 UPDATE)

**How to check:**
```bash
gh pr view --repo <owner>/<repo> 2>/dev/null && echo "UPDATE" || echo "CREATE"
```

---

## ✨ NEW PR CREATION PATH

### 1. Prepare PR Metadata

**Reference**: [AGENTS.md § Pull Request Standards](../../AGENTS.md)

Gather required information:
- **Title**: Short, descriptive (max ~60 chars)
- **Base branch**: Usually `main` (confirm with operator)
- **Head branch**: Your feature/fix branch (confirm it's pushed)
- **Target repo**: Confirm owner/repo if non-standard

### 2. Load & Populate PR Template (NEW)

**Reference**: [AGENTS.md § PR Description Template](../../AGENTS.md)

Template is at `.github/pull_request_template.md`

Populate ALL 9 sections with substantive content (not placeholder text). See AGENTS.md § PR Description Template for the complete list and detailed guidance on each section.

### 3. OpenSpec Integration (NEW, if applicable)

**Reference**: [AGENTS.md § OpenSpec Integration](../../AGENTS.md)

If this PR implements an OpenSpec change, follow the guidance in AGENTS.md § OpenSpec Integration to link artifacts and cross-reference requirements.

### 4. Validation Checklist (NEW)

Before creating PR, verify:

**Reference**: [AGENTS.md § Agent Responsibilities](../../AGENTS.md)

- ✅ All 9 sections populated with substantive content (no placeholders)
- ✅ Technical decisions explain "why" not just "what"
- ✅ Security considerations addressed (or explicitly "N/A" with reason)
- ✅ Testing recommendations are specific & actionable
- ✅ All links are correct and tested
- ✅ If OpenSpec: all artifacts linked correctly
- ✅ Branch is pushed, base branch exists, title is descriptive

### 5. Create PR (NEW)

Execute PR creation:

```bash
gh pr create \
  --title "<title>" \
  --body "<populated template>" \
  --base <base-branch> \
  --head <head-branch> \
  --repo <owner>/<repo>
```

OpenCode will confirm before executing.

### 6. Post-Creation (NEW)

After PR is created:
- ✅ Report PR number and URL
- ✅ Output any relevant metadata (CI workflows, reviewers, etc.)
- ✅ If OpenSpec-related, confirm artifacts are linked in PR description

---

## 🔄 EXISTING PR UPDATE PATH

### 1. Detect PR Number

**Reference**: [AGENTS.md § Pull Request Standards](../../AGENTS.md)

Get PR number for current branch:

```bash
PR_NUM=$(gh pr view --json number --jq '.number' 2>/dev/null)
echo "Found PR #$PR_NUM"
```

- ✅ If PR found → Continue to Step 2
- ❌ If no PR found → Confirm with operator this is correct branch

### 2. Fetch Current PR Details (UPDATE)

Retrieve current PR state:

```bash
gh pr view $PR_NUM --json title,body,state,reviews
```

Capture:
- Current title (for reference)
- Current body (for reference)
- PR state (confirm it's open, not merged/closed)
- Current review state

### 3. Determine Update Type (UPDATE)

What is being updated?

**Option A: Update PR Description Only**
- Modify problem statement, solution, technical details, testing recommendations
- Do NOT re-execute commits
- Useful for clarifying intent or fixing typos
- → Proceed to Step 4A (Update Body Only)

**Option B: Add New Commits**
- Changes have been made to branch
- New commits should be pushed
- PR description may also need updates
- → Proceed to Step 4B (Push & Update)

**Option C: Update Title Only**
- Renaming/clarifying the PR title
- Body stays the same
- → Proceed to Step 4C (Update Title Only)

### 4A. Update PR Body Only (UPDATE)

If only description changed:

1. Load current PR body
2. Guide through updating specific sections (problem, solution, testing, etc.)
3. Validate all 9 sections still populated with substantive content
4. Execute body update:

```bash
gh pr edit $PR_NUM --body "<updated template>"
```

5. Report: "PR #$PR_NUM description updated"

### 4B. Push Commits & Update PR (UPDATE)

If new commits added:

1. Confirm new commits are ready
2. Ask: "Should PR description also be updated?"
   - If **yes** → Load & update description sections (similar to 4A)
   - If **no** → Skip to push
3. Execute commit push:

```bash
git push origin HEAD:refs/heads/<branch-name>
```

4. If body was updated, execute body update:

```bash
gh pr edit $PR_NUM --body "<updated template>"
```

5. Report: "PR #$PR_NUM updated with new commits" (+ body changes if applicable)

### 4C. Update PR Title Only (UPDATE)

If only title changed:

```bash
gh pr edit $PR_NUM --title "<new title>"
```

Report: "PR #$PR_NUM title updated to: <new title>"

### 5. Post-Update (UPDATE)

After PR is updated:
- ✅ Report PR number and URL
- ✅ Show what was changed (title / body / commits / all three)
- ✅ Output current PR state (still open, no conflicts, etc.)
- ✅ If OpenSpec-related, confirm artifacts are still linked

---

## 🚫 Critical Rules (Both Paths)

| Rule | Source |
|------|--------|
| Never create/update PR without explicit operator request | AGENTS.md § Git Safety Rules |
| Always populate ALL 9 sections of template (new PRs) | AGENTS.md § PR Description Template |
| When updating, ensure ALL 9 sections remain substantive | AGENTS.md § Agent Responsibilities |
| Explain technical decisions, not just "what" but "why" | AGENTS.md § Agent Responsibilities |
| Include security considerations when applicable | AGENTS.md § Agent Responsibilities |
| Provide testable, specific recommendations | AGENTS.md § Agent Responsibilities |
| Link to related OpenSpec changes when applicable | AGENTS.md § OpenSpec Integration |
| Verify links are correct before creating/updating PR | AGENTS.md § Agent Responsibilities |
| Never leave placeholder text in any section | AGENTS.md § Agent Responsibilities |
| For updates: confirm PR still has all required sections | AGENTS.md § Agent Responsibilities |

---

## 📖 Full Reference

All detailed rules, template structure, and examples live in [`AGENTS.md`](../../AGENTS.md):

- **§ 5️⃣ Pull Request Standards** — Root standard for all PRs
- **§ PR Description Template** — All 9 required sections
- **§ Template Location** — `.github/pull_request_template.md`
- **§ OpenSpec Integration** — Linking artifacts & requirements
- **§ Example: Detailed PR Structure** — Concrete example showing all sections
- **§ Agent Responsibilities** — What agents MUST do when creating/updating PRs

Also reference:
- **§ 📐 Spec Format Standard** — For understanding spec requirements being implemented
- **§ 🔒 Agent Git Behavior** — Safety rules applying to all git operations

---

## 📝 How to Use This Command

**In OpenCode terminal:**

1. Type `/` — command palette appears
2. Search `"pr"` — this command shows in list (🔀 icon)
3. Select → command loads
4. Type your request for either scenario:

**CREATE new PR:**
```
Create a pull request for this change
```
or
```
Open a new PR
```

**UPDATE existing PR:**
```
Update my pull request description
```
or
```
Push changes to my PR
```

**OpenCode will then:**

**For NEW PR Creation:**
1. ✅ Detect that this is a new PR (no existing PR found)
2. ✅ Confirm PR metadata (title, base, head, repo)
3. ✅ Load template from `.github/pull_request_template.md`
4. ✅ Guide you through populating all 9 sections
5. ✅ Check if OpenSpec-related and link artifacts
6. ✅ Validate all sections have substantive content
7. ✅ Show final PR body before creating
8. ✅ Create PR with `gh pr create`
9. ✅ Report PR number and URL

**For EXISTING PR Update:**
1. ✅ Detect that PR exists for this branch
2. ✅ Fetch current PR number and state
3. ✅ Ask: what's being updated? (description / new commits / title)
4. ✅ If description → guide through updating specific sections
5. ✅ If commits → push new commits, optionally update description
6. ✅ If title → update title only
7. ✅ Execute update(s) via `gh pr edit`
8. ✅ Report what changed and confirm PR state

**Expected interactions:**

NEW PR flow:
```
OpenCode: "Creating new PR for branch feature/xyz. Title?"
You: "Add firefly backup automation"

OpenCode: "Confirm base branch?"
You: "main"

OpenCode: [Shows template sections one by one]
...

OpenCode: "PR body ready. Create it?"
You: "Create"

OpenCode: [Creates PR, reports #123]
```

UPDATE PR flow:
```
OpenCode: "Found PR #456 for your branch. What to update?"
You: "Update the description"

OpenCode: "Current body: [shows excerpt]"
OpenCode: "Which section? Problem / Solution / Testing?"
You: "Testing"

OpenCode: [Shows current testing section]
You: [Provide new testing section]

OpenCode: "Description updated. PR #456 refreshed."
```

---

## 🎯 OpenSpec PR Integration (Both New & Update)

**Reference**: [AGENTS.md § OpenSpec Integration](../../AGENTS.md)

When PRs relate to OpenSpec changes:
- OpenCode detects OpenSpec files and asks: "Is this OpenSpec-related?"
- For **new PRs**: helps populate Related Changes with proposal/design/spec/tasks links
- For **updates**: validates artifacts remain linked correctly and requirements sections stay accurate
- Ensures requirement IDs (REQ-001, etc.) are cross-referenced in PR description

---

*Command location: `.opencode/commands/pr-prompt.md` | Source of truth: `AGENTS.md § 5️⃣` | Template: `.github/pull_request_template.md` | Updated: 2026-06-27*
