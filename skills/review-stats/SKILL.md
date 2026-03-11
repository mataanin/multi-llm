---
name: review-stats
description: Show cumulative review analytics across all LLM review tools
---

Generate a review analytics report from `review-analytics.json`. If the file doesn't exist or has no reviews, say so.

Use `jq` to compute and display the following sections. **IMPORTANT**: Derive the tool list dynamically from the data — do NOT hardcode tool names. Use `[.reviews[].findings | keys[]] | unique` to discover all tools.

## 1. Overview
- Total reviews analyzed
- Date range (first to last timestamp)
- Reviewer breakdown (if `reviewer` field present)
- Review type breakdown (code, plan, pr-review, etc.)

## 2. Finding Counts by Tool
For each tool found in the data:
- Total findings across all reviews
- Average findings per review (only counting reviews where the tool ran)
- Reviews where tool found 0 issues
- Tool run rate (how many reviews included this tool)

## 3. Agreement Analysis
From the `matching` field across all reviews:
- Total matched findings (2+ tools agreed)
- Breakdown: how often each pair of tools agrees
- Agreement rate: matched / total unique issues

## 4. Unique Findings
- Per tool: total unique findings (not found by any other tool)
- Which tool most often finds issues others miss

## 5. Action Correlation
From the `acted_upon` field:
- Total findings that were acted upon (file changed in subsequent commit)
- Per tool: how many of their findings were acted upon
- **Action rate per tool**: acted upon / total findings (this measures which tool's findings are most useful)

## 6. Trends (if 3+ reviews)
- Is any tool finding fewer issues over time? (improving code quality or becoming less useful?)
- Is agreement rate increasing? (tools converging on same standards)

Format the output as a clean text report with aligned columns. Keep it concise.
