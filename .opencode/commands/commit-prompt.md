---
name: "commit"
description: "Group and commit staged changes with proper messages following AGENTS.md rules"
type: "prompt"
category: "git"
icon: "📝"
usage: "Type '/' in OpenCode terminal, search 'commit', select this command"
keywords: ["git", "commit", "grouping", "message", "AGENTS.md"]
---

# OpenCode Commit Orchestration

**Purpose**: Orchestrate intelligent grouping and committing of staged changes per [AGENTS.md § 🔒 Agent Git Behavior (Mandatory)](../../AGENTS.md).

This command is a **lightweight wrapper** — detailed rules are centralized in `AGENTS.md` (the single source of truth). This file focuses on orchestration steps and references.

---

## 🔄 Workflow

### 1. Pre-Commit Secret Scan

Before grouping, scan staged files for hardcoded secrets:

**Reference**: [AGENTS.md § Pre-Commit Secret Scan Gate](../../AGENTS.md)

- ❌ If secrets found → **ABORT**, report matches, wait for operator confirmation
- ✅ If clean → Proceed to Step 2

### 2. Analyze & Group Files

Examine staged files and categorize by concern:

**Reference**: [AGENTS.md § Commit Grouping Strategy (Mandatory)](../../AGENTS.md)

Five categories (apply in order):
1. **Security** — credential removal + `.env.example`
2. **Spec** — `openspec/specs/` rewrites + deleted specs
3. **Structural** — Dockerfile/compose changes (non-security)
4. **Documentation** — SERVICE_DOCUMENTATION.md, RESTORE_GUIDE.md, etc.
5. **Repository-wide** — AGENTS.md, root scripts, `.github/` files

**Decision rule**: "Would a reviewer expect these files to change together?" → same commit

### 3. Create Compliant Commit Messages

For each group, create one commit:

**Reference**: [AGENTS.md § Commit message format per group](../../AGENTS.md)

Format:
```
<type>(<scope>): <subject (max 72 chars)>

<body: explain what & why>
```

Common type/scope: `fix(security)`, `spec(mediaServices)`, `chore(docs)`, `chore(repo)`, `ci(workflow)`

### 4. Pre-Push Secret Scan

Before pushing, scan all commits:

**Reference**: [AGENTS.md § Pre-Push Secret Scan Gate](../../AGENTS.md)

- ❌ If secrets found → **ABORT**, report hash/file/line
- ✅ If clean → Safe to push

---

## 🚫 Critical Rules

| Rule | Source |
|------|--------|
| Never commit without operator saying "commit" | AGENTS.md § Git Safety Rules |
| Never push without operator saying "push" | AGENTS.md § Git Safety Rules |
| Never override secret scan gates | AGENTS.md § Pre-Commit/Pre-Push Secret Scan |
| Never lump unrelated files into single commit | AGENTS.md § Commit Grouping Strategy |
| Explain **what** changed AND **why** | AGENTS.md § Commit message format |
| All `.env` values go in `.env` + `.env.example` | AGENTS.md § Environment & Secrets |

---

## 📖 Full Reference

All detailed rules, examples, and guidance live in [`AGENTS.md`](../../AGENTS.md):

- **§ 🔒 Agent Git Behavior (Mandatory)** — Root rules & safety gates
- **§ Commit Grouping Strategy (Mandatory)** — All 5 categories + decision heuristic
- **§ Commit message format per group** — Type/scope/subject/body rules + examples
- **§ Pre-Commit Secret Scan Gate** — What to scan, how to interpret results
- **§ Pre-Push Secret Scan Gate** — Same scan, applied to full commits
- **§ 4.3 General Guidelines** — File encoding, naming, line length
- **§ 9️⃣ Project Conventions** — Docker/Terraform/cron patterns

---

## 📝 How to Use This Command

**In OpenCode terminal:**

1. Type `/` — command palette appears
2. Search `"commit"` — this command shows in list
3. Select → command loads
4. Type your request:
   ```
   Group and commit changes
   ```

**OpenCode will then:**
1. ✅ Scan for secrets in staged files (Step 1)
2. ✅ Analyze & group files by category (Step 2)
3. ✅ Create one commit per group with proper message (Step 3)
4. ✅ Show each commit message before executing
5. ✅ Wait for your confirmation or `"push"` command

**After commits are made:**

- Say `"Push these changes"` → OpenCode runs pre-push scan, then pushes

---

*Command location: `.opencode/commands/commit-prompt.md` | Source of truth: `AGENTS.md` | Updated: 2026-06-27*
