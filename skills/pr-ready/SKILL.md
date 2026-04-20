---
name: pr-ready
description: Address PR review comments and iterate on solutions
---

## **Phase 0**: Gather PR state (CI + comments + build check in parallel)

### Step 1: Get PR number and branch information
```bash
# Get PR number and branch for workflow queries
PR_NUMBER=$(gh pr view --json number -q .number)
BRANCH_NAME=$(gh pr view --json headRefName -q .headRefName)
```

### Step 2: Check CI status, fetch PR comments, and run frontend build simultaneously

Do ALL of these in parallel — do NOT wait for one to finish before starting others.

**CI check:**
- Use `gh run list --branch $BRANCH_NAME --limit 5 --json status,conclusion,name` to get current CI status
- Note which workflows are passing, failing, or still running

**Fetch PR comments:**
- `mcp__github__pull_request_read` with `method: "get_review_comments"` for line-specific code review comments
- `mcp__github__pull_request_read` with `method: "get_comments"` for general PR discussion comments (includes CI workflow comments)

**Frontend build check (run in background):**
Run `npm run build` in the background to catch CI build failures early. CI sets `CI=true` which makes react-scripts treat lint warnings as errors — this catches those before pushing:
```bash
source env.sh && docker exec $PATIENT_FRONTEND npm run build &
BUILD_PID=$!
```

Check the result after addressing comments:
```bash
wait $BUILD_PID || { echo "❌ Frontend build failed — fix lint warnings (CI=true treats warnings as errors)"; exit 1; }
```

### Step 3: Prioritize and fix immediately

**Fix everything you see immediately** — do NOT gate on CI passing before addressing comments, and do NOT defer CI failures.

- If CI is failing: investigate logs (`gh run view --log-failed`), fix the root cause, push
- If PR comments exist: address them (see Phase 1 below)
- If frontend build failed: fix lint warnings/import order issues shown in build output
- If multiple: fix whichever you encounter first, then the others

After each push, re-request Cursor BugBot & Copilot:
```bash
git push && ./.claude/scripts/request-github-reviews.sh "$PR_NUMBER"
```

---

## **Phase 1**: Address GitHub PR comments

**CRITICAL: Every comment must be addressed as a new task using the review-comment-agent**

### Step 1: Re-request reviews and fetch all PR comments

1. **Always re-request reviews** (even if previously requested, to get fresh reviews on latest changes):
   ```bash
   PR_NUMBER=$(gh pr view --json number -q .number)
   ./.claude/scripts/request-github-reviews.sh "$PR_NUMBER"
   ```

2. **Fetch all PR comments:**

   First, get the PR number for use in later steps:
   ```bash
   # Get PR number and store in variable for later steps
   PR_NUMBER=$(gh pr view --json number -q .number)
   ```

   Then use GitHub MCP tools to retrieve ALL PR comments:
   - `mcp__github__pull_request_read` with `method: "get_review_comments"` for line-specific code review comments
   - `mcp__github__pull_request_read` with `method: "get_comments"` for general PR discussion comments (includes CI workflow comments)

### Step 2: Launch review-comment-agent for each comment

1. **Launch review-comment-agent for every PR comment:**

   For each comment retrieved in Step 1, launch `review-comment-agent` with:
   - Comment body and context
   - File path and line number (if available for review comments)

2. **Threaded reply instructions for review-comment-agent:**

   **CRITICAL: All responses must use threaded replies to maintain comment context**

   When replying to a comment, the agent must:

   a. **Find the comment thread ID:**
      ```bash
      # Extract unique text from the original comment (first 50-100 chars)
      COMMENT_SEARCH=$(echo "[original comment text]" | head -c 100)

      # Find the thread ID
      COMMENT_ID=$(./.claude/scripts/gh-find-comment-thread.sh $PR_NUMBER "$COMMENT_SEARCH")
      ```

   b. **Reply in the same thread:**
      ```bash
      # Get current commit hash
      COMMIT_HASH=$(git rev-parse --short HEAD)

      # Format response with commit hash reference (if we made a new commit)
      RESPONSE_TEXT="Fixed in commit $COMMIT_HASH - [explanation]"

      # If COMMENT_ID found, reply in thread
      if [ -n "$COMMENT_ID" ]; then
        ./.claude/scripts/gh-comment-threaded.sh $PR_NUMBER "$RESPONSE_TEXT" $COMMENT_ID
      else
        # Fallback: Use comment ID directly if available from API response
        ./.claude/scripts/gh-comment-threaded.sh $PR_NUMBER "$RESPONSE_TEXT" "[comment_id_from_api]"
      fi
      ```

## **Phase 1.5**: Gate — Require Copilot + Cursor reviews

**DO NOT PROCEED until both Copilot and Cursor reviews are requested.** No exceptions.

Check who has reviewed:
```bash
PR_NUMBER=$(gh pr view --json number -q .number)
REPO=$(gh repo view --json nameWithOwner -q '.nameWithOwner')
REVIEWERS=$(gh api "repos/$REPO/pulls/$PR_NUMBER/reviews" --jq '[.[].user.login] | unique | join(", ")')
echo "Reviews from: $REVIEWERS"
```

**Both `copilot[bot]` and `cursor[bot]` must appear.** If either is missing:
1. Re-request using `mcp__github__request_copilot_review` (for Copilot) or `gh pr edit --add-reviewer @cursor` (for Cursor)
2. Wait 60 seconds and re-check
3. After 3 attempts, warn the user: "Copilot/Cursor has not responded after 3 requests. Proceed manually or investigate."

---

## **Phase 2**: Harvest review findings into analytics

After addressing all comments, harvest any GitHub review findings into the analytics pipeline:

```bash
PR_NUMBER=$(gh pr view --json number -q .number)
HARVEST_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
./.claude/scripts/harvest-pr-reviews.sh "$PR_NUMBER" "$HARVEST_TIMESTAMP"
# Only run analyze if harvest produced output files
if ls docs/reviews/${HARVEST_TIMESTAMP}-*.txt 1>/dev/null 2>&1; then
  ./.claude/scripts/review-analyze.sh "$HARVEST_TIMESTAMP" --review-type pr-review
  git add review-analytics.json && git commit -m "Update review analytics from PR comments"
fi
```

## **Phase 3**: Merge safety for review-analytics.json

**ALWAYS run this step** — proactively merge with main to prevent conflicts, not just when conflicts exist.

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

## **Phase 4**: Iterate on solution

After addressing all the comments:
1. Update GitHub description with new requirements or correcting details
2. Iterate on the solution starting phase 1

## **Final Step**: Run /schedule-reminder for PR #$PR_NUMBER
