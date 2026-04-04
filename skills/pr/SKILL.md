---
name: pr
description: Get PR ready for manual testing and stakeholder review
---


## **Phase 1**: Environment Health Check

Verify your development environment is healthy before running comprehensive checks.

### Check 0: Verify branch naming and PR state

Branch names MUST use the `patients/` prefix. If the current branch does not start with `patients/`, rename it before proceeding:
```bash
BRANCH=$(git branch --show-current)
if [ "$BRANCH" = "main" ]; then
  echo "ERROR: Create a feature branch first: git checkout -b patients/<description>"
  exit 1
fi
if [[ "$BRANCH" != patients/* ]]; then
  git branch -m "patients/$BRANCH"
fi
```

**CRITICAL: Check if PR is already merged.** Never push to a branch whose PR has been merged — this can reopen closed work or create orphan commits. If merged, create a new branch from the current HEAD and continue the `/pr` flow on the new branch.
```bash
PR_STATE=$(gh pr view --json state -q '.state' 2>/dev/null || echo "NONE")
if [ "$PR_STATE" = "MERGED" ]; then
  echo "PR for this branch is already MERGED. Creating a new branch..."
  OLD_BRANCH=$(git branch --show-current)
  # Append -v2, -v3, etc. to create a unique branch name
  SUFFIX=2
  while git show-ref --verify --quiet "refs/heads/${OLD_BRANCH}-v${SUFFIX}" 2>/dev/null; do
    SUFFIX=$((SUFFIX + 1))
  done
  NEW_BRANCH="${OLD_BRANCH}-v${SUFFIX}"
  git checkout -b "$NEW_BRANCH"
  echo "Switched to new branch: $NEW_BRANCH"
fi
```

### Check 1: Verify Correct Instance Running

If the instance is not running, start it first:
```bash
./start.sh
```

To stop it when done:
```bash
./stop.sh
```

Then verify it is up:
```bash
source env.sh && docker ps --format "table {{.Names}}\t{{.Ports}}" | grep patient
```

### Check 2: Check pending migrations

```bash
source env.sh && docker exec $PATIENT_BACKEND rails runner "puts ActiveRecord::Base.connection.migration_context.needs_migration? ? '⚠️  MIGRATIONS PENDING' : '✅ UP TO DATE'"
```

**If pending**: `source env.sh && docker exec $PATIENT_BACKEND rake db:migrate`

### Check 3: Validate schema.rb

Run `/check-schema` to validate schema.rb drift, then check TypeScript type sync as described in `/test-more` Section 8.

---

## **Phase 2**: Code Quality Checks

### Check 1: Run Tests & Frontend Checks (parallel)

Run lint first (it modifies files), then run backend tests and frontend build **simultaneously**:

```bash
source env.sh

# Run lint first — it modifies source files, so it must complete before build reads them
docker exec $PATIENT_FRONTEND npm run lint -- --fix || { echo "❌ Frontend lint failed"; exit 1; }

# Start rspec and build in parallel (safe: build only reads files now that lint is done)
docker exec $PATIENT_BACKEND bundle exec rspec &
RSPEC_PID=$!
docker exec $PATIENT_FRONTEND npm run build &
BUILD_PID=$!

# Wait for both and track failures
FAILED=0
wait $RSPEC_PID   || { echo "❌ RSpec tests failed"; FAILED=1; }
wait $BUILD_PID   || { echo "❌ Frontend build failed (CI=true treats warnings as errors)"; FAILED=1; }
[ $FAILED -eq 0 ] && echo "✅ All checks passed" || echo "⚠️  Some checks failed — fix before proceeding"
exit $FAILED
```

**IMPORTANT**: The `npm run build` step catches lint warnings that CI treats as errors (react-scripts build with `CI=true`). If build fails but lint passes, fix the import order or unused variable warnings shown in the build output.

### Check 2: INSIGHTS.md Pattern Compliance
Review your changes against documented anti-patterns. See INSIGHTS.md for complete list

### Check 3: Architecture Review

Validate adherence to ARCHITECTURE.md

---

## **Phase 2.5**: Plan Completion Gate

**MANDATORY GATE — Do NOT proceed to Phase 3 until this gate passes.**

Check if this branch has an associated plan file. To find the correct plan:
1. Check if a `--plan-file` argument was passed (e.g., from `/autonomous-execute`)
2. Check if a plan file was created or modified on this branch: `git diff origin/main...HEAD --name-only | grep '^docs/plans/'`
3. If neither produces a result, **skip this gate** — the branch was not created via `/feature-custom-dev`

**Do NOT pick up historical plan files from other features.** Only use a plan file that was created or modified as part of this branch's work.

**Autonomous execution shortcut**: If an autonomous progress log exists at `.claude/logs/autonomous/` matching the plan name, and its Verification Gate section shows `READY FOR PR: yes`, treat all gate conditions as already satisfied. Skip re-running Playwright tests, design review, and QA — they were already completed by `/autonomous-execute`.

If a branch-specific plan file is found, verify that ALL implementation items from the plan are complete:

1. **Read the plan file** and extract every implementation item
2. **Verify each item** is reflected in the codebase (check files exist, code is present)
3. **Verify mandatory quality checks** have been completed:
   - **Playwright E2E tests**: If the feature has frontend changes (`git diff origin/main...HEAD --name-only | grep patient-portal/frontend/src/`), verify that Playwright test files exist in `patient-portal/e2e/tests/smoke/` covering the feature's UI flows. If tests are missing, **write them now** using the `playwright-testing` skill before proceeding.
   - **Design review**: If the feature has frontend changes, check for evidence that `/web-design-reviewer` was run: look for a Design Review section in the autonomous progress log (`.claude/logs/autonomous/`), or PR description screenshots at multiple viewports. If no evidence exists, **run it now** on all affected routes before proceeding.
   - **QA validation**: Check for evidence that `/gstack-qa` was run: look for a QA Validation section in the autonomous progress log, or atomic fix commits with QA-related messages. If no evidence exists, **run it now** before proceeding.

4. **If any items are incomplete**: Stop and complete them. Do NOT proceed to the review cycle with incomplete work — reviews on incomplete code waste cycles.

5. **Log gate status**:
   ```
   Plan Completion Gate:
   - Plan items: X/Y complete
   - Playwright tests: present/missing/N/A
   - Design review: done/missing/N/A
   - QA validation: done/missing
   - GATE: PASS/FAIL
   ```

If no plan file exists (standalone `/pr` invocation without `/feature-custom-dev`), skip this gate.

---

## **Phase 3**: Review Cycle (Local + GitHub Reviews)

**MANDATORY — DO NOT SKIP. You MUST execute `/review-cycle` using the Skill tool.** This is the single review entry point: it pushes to GitHub, creates/finds the PR, runs all local LLM reviews (Claude + Codex + Gemini + Cursor), waits for and harvests GitHub bot reviews (Cursor BugBot, Copilot), then iterates fix-verify cycles until findings converge. Do NOT manually replicate what `/review-cycle` does — invoke it via the Skill tool so it drives each step.

**GATE CHECK**: Before moving to Phase 4, confirm: "I executed `/review-cycle` via the Skill tool and both tracks converged." If you cannot confirm this, go back and run it now.

---

## **Phase 4**: Integration Testing with Playwright

**Use the `playwright-testing` skill** for all Playwright patterns, helpers, and troubleshooting.

### Step 1: Verify effect of changes using UI

Identify affected UI flows and verify changes. Three approaches:

1. **Run existing e2e tests:** `cd patient-portal/e2e && npx playwright test` to catch regressions
2. **Write verification scripts:** For new flows, write a `.spec.ts` in `patient-portal/e2e/tests/verify/` following the `playwright-testing` skill's verification template, execute it, and iterate until passing
3. **Interactive verification:** Use Playwright MCP for quick manual checks following the skill's navigation patterns


### Step 2: Verify Adversarial Test Coverage

**MANDATORY: Execute `/test-more` using the Skill tool** to verify comprehensive test coverage. Do NOT just list what should be tested — actually invoke the skill so it drives the adversarial testing checklist:
- Happy-path flows tested end-to-end with database verification
- Edge cases: form validation errors, boundary values, back-navigation, incomplete flows
- Adversarial: direct navigation to later steps, mid-flow refresh, duplicate submissions, session expiry

### Step 3: Verify Background Jobs Launched
Check that UI interactions triggered expected background jobs:

**Check recent jobs in GoodJob dashboard:**
```bash
source env.sh && open $GOODJOB_URL
```

**Or query database directly:**
```bash
source env.sh && docker exec $PATIENT_BACKEND rails runner "
  recent_jobs = GoodJob::Job.where('created_at > ?', 5.minutes.ago)
  puts \"Recent jobs: #{recent_jobs.count}\"
  recent_jobs.each { |j| puts \"  - #{j.serialized_params['job_class']}: #{j.finished_at ? 'COMPLETED' : 'PENDING'}\" }
"
```

**Expected job types**:
- `PostPurchaseJob` (after purchase)
- `FileSyncJob` (after file upload)
- `Monday::CreateReferralJob` (after referral form submission)
- Email delivery jobs (ActionMailer)

### Step 4: Verify Emails Sent
Check Letter Opener for emails triggered by your flow:

```bash
# Open Letter Opener in browser
source env.sh && open $LETTER_OPENER_URL
```

---

## **Phase 4.5**: Capture Screenshots for Release Notes

Capture screenshots of affected UI screens for the daily release notes system. These screenshots are committed to `pr-screenshots/` and embedded in the PR description for automated Slack posting.

### Pre-flight Checks

Verify the local dev instance is running before attempting screenshots. If it is not running, start it with `./start.sh` first. To stop it when done, run `./stop.sh`.

```bash
source env.sh
curl -sf $FRONTEND_URL > /dev/null && echo "Frontend OK" || echo "Frontend NOT RUNNING"
curl -sf $BACKEND_URL/health > /dev/null && echo "Backend OK" || echo "Backend NOT RUNNING"
```

If either service is not running, run `./start.sh` and retry. If it still fails, **warn the developer** and offer to skip screenshots entirely. Never fail the `/pr` flow due to screenshot issues.

### Step 1: Detect Affected Routes

Analyze changed frontend files:
```bash
git diff origin/main...HEAD --name-only | grep -E 'patient-portal/frontend/src/'
```

Map changed files to potentially affected routes using:
- `patient-portal/frontend/src/types/Paths.ts` — route path constants
- `patient-portal/frontend/src/AppRoutes.tsx` — full-page route components
- `patient-portal/frontend/src/DialogRoutes.tsx` — dialog/modal route components

### Step 2: Developer Route Selection

**If running in autonomous mode** (invoked from `/autonomous-execute`): auto-select ALL detected routes. Do NOT use `AskUserQuestion`. Skip directly to Step 3.

**Otherwise**, present a multi-select choice to the developer using `AskUserQuestion`:

> I detected frontend changes that may affect these routes:
> - `/patient/feed` (PatientFeed component changed)
> - `/provider/admin/patients/:id` (AdminPatientDetails changed)
>
> Which routes should I screenshot for release notes?

Options:
- Each detected route as a selectable option
- "Skip screenshots" option
- Developer can also specify custom routes via "Other"

If the developer selects "Skip screenshots", proceed directly to Phase 5.

### Step 3: Capture Screenshots via Playwright MCP

For each selected route:

1. **Navigate and authenticate:**
   - Patient routes (`/patient/*`): Log in as your patient test account
   - Admin routes (`/provider/*`): Log in as your admin/provider test account
   - Use `mcp__playwright__browser_navigate` to reach the route
   - Use `mcp__playwright__browser_wait_for` for network idle

2. **Take screenshot** via `mcp__playwright__browser_take_screenshot` in **JPEG format**

3. **Save to** `pr-screenshots/YYYY-MM-DD-{screen-name}.jpg`
   - Use today's date and a slugified screen name (e.g., `2026-03-03-patient-feed.jpg`)

**Error handling:** If navigation or screenshot fails for any route, log a warning and continue with remaining routes. Never fail the entire flow.

### Step 4: Commit Screenshots

```bash
git add pr-screenshots/
git commit -m "Add PR screenshots for release notes"
```

### Step 5: Upload Screenshots & Embed in PR Description

**Relative paths do NOT render in private repo PR descriptions.** Upload to GitHub's CDN via a draft release:

```bash
# Create release (once) and upload screenshots
gh release view screenshots-assets 2>/dev/null || \
  gh release create screenshots-assets --title "PR Screenshot Assets" --notes "" --draft
gh release upload screenshots-assets pr-screenshots/*.jpg --clobber

# Get URLs for PR description
gh release view screenshots-assets --json assets --jq '.assets[] | "\(.name): \(.url)"'
```

Use the release asset URLs (not relative paths) in the PR description between marker comments:

```markdown
## Screenshots
<!-- release-notes-screenshots -->
![screen-name](https://github.com/{OWNER}/{REPO}/releases/download/screenshots-assets/YYYY-MM-DD-screen-name.jpg)
<!-- /release-notes-screenshots -->
```

The `<!-- release-notes-screenshots -->` markers are parsed by the release notes GitHub Action. Omit the section entirely if no screenshots were captured.

---

## **Phase 5**: Create PR & PR description

Reuse the change summary from CHANGE_SUMMARY environment variable to update the PR description. Create a new summary using instructions from Phase 3 if the variable is missing.

If screenshots were captured in Phase 4.5, they should already be included in the description between `<!-- release-notes-screenshots -->` markers.

**Asana ticket**: If the plan file has an `**Asana Ticket:**` line, include it in the PR description under a `## Asana` section:
```markdown
## Asana
[Task name](https://app.asana.com/0/<project_gid>/<task_gid>)
```
If no plan file or no ticket line, omit the section.

Add the `ci-maintain` label to the PR so the CI maintenance workflow will keep it up to date with main.

Request reviews using the dedicated script:
```bash
PR_NUMBER=$(gh pr view --json number -q .number)
./.claude/scripts/request-github-reviews.sh "$PR_NUMBER"
```

### Step: Save conversation transcript

**Skip this step if `DEVELOPER_ENGINEER=1` is set.**

```bash
if [ "${DEVELOPER_ENGINEER:-0}" != "1" ]; then
  echo "Saving conversation transcript..."
else
  echo "DEVELOPER_ENGINEER=1 — skipping transcript save"
fi
```

If not suppressed, **execute `/save-thread-git` using the Skill tool** to export the conversation, commit it, and link it in the PR description.

---

## **Phase 6**: Fix Remaining CI Failures

**Note**: `/review-cycle` (Phase 3) already handles local CI verification, GitHub comment replies, and iterative fixes. This phase is a safety net for any CI failures that appear after the review cycle completes.

```bash
# Check CI status
gh run list --limit 3

# If any run failed, get the run ID and view logs
FAILED_RUN=$(gh run list --limit 3 --json databaseId,conclusion -q '.[] | select(.conclusion=="failure") | .databaseId' | head -1)
if [ -n "$FAILED_RUN" ]; then
  gh run view "$FAILED_RUN" --log-failed
fi
```

After fixing CI issues, push and re-request reviews:
```bash
git push && ./.claude/scripts/request-github-reviews.sh "$PR_NUMBER"
```

---

## **Phase 6.5**: Merge safety for review-analytics.json

**Fallback step** — `/review-cycle` (Phase 3) already merges review-analytics.json internally. This step catches any analytics changes from Phase 4/5/6 pushes that occurred after the review cycle completed.

**`review-analytics.json` is append-only.** Never discard entries from either side.

```bash
git fetch origin main
jq -s '{ reviews: ([.[].reviews[]] | unique_by(.timestamp) | sort_by(.timestamp)) }' \
  <(git show origin/main:review-analytics.json) review-analytics.json > /tmp/ra-merged.json \
  && mv /tmp/ra-merged.json review-analytics.json
if ! git diff --quiet review-analytics.json; then
  git add review-analytics.json && git commit -m "Merge review-analytics.json with main to prevent conflicts

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>"
  git push
fi
```

## **Final Step**: Workflow Retrospective

Before wrapping up, collect quick feedback on how the `/pr` workflow and tooling performed.

### Step 1: Solicit Feedback

Ask the user using `AskUserQuestion`:

> **Quick retro on this /pr run:**
>
> 1. How did the workflow go? (0-10)
> 2. What worked well?
> 3. What was slow, frustrating, or broken in the tooling?
>
> (Brief is fine — even just a number and a few words.)

### Step 2: Capture Workflow & Tooling Improvements

If the user provides feedback, save to `tool-improvements/pr-workflow.md` (append if exists):

```markdown
## YYYY-MM-DD — PR #<number>
**Rating:** <0-10>

### What worked
- <from feedback>

### Tooling / workflow improvements
- [ ] <actionable item>
```

### Step 3: Schedule reminder

Run /schedule-reminder for PR #$PR_NUMBER
