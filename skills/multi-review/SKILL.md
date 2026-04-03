---
name: multi-review
description: "DEPRECATED — use /review-cycle instead. Redirects to /review-cycle which now includes all multi-LLM review functionality."
argument-hint: Optional focus area (e.g., "security", "performance")
---

# Multi-Review — DEPRECATED

**This skill has been merged into `/review-cycle`.** Use `/review-cycle` instead.

`/review-cycle` now handles everything `/multi-review` used to do:
- Summarize the change
- Push to GitHub and request bot reviews
- Run all CLI LLM reviews in parallel (Claude, Codex, Gemini, Cursor)
- Wait for and harvest GitHub bot reviews (Cursor BugBot, Copilot)
- Analyze cross-tool agreement
- Commit review analytics
- Present consolidated findings

Plus the iterative convergence loop that `/multi-review` lacked.

## Redirect

When this skill is invoked, **execute `/review-cycle` using the Skill tool** with the same arguments:

```
/review-cycle $ARGUMENTS
```
