# Baymax

![Baymax Gif](https://media.giphy.com/media/v1.Y2lkPTc5MGI3NjExaGdnZzkxOGY5eHJ6ZDIwa2VmaXc5NjRqam43ZnliNDIzcm90cGk4dCZlcD12MV9naWZzX3NlYXJjaCZjdD1n/52AimBOEZ5mgw/giphy.gif)
> *"I am Baymax, your personal healthcare companion."*

Named after the inflatable healthcare robot from **Big Hero 6** — because just like the original, this Baymax detects when something is wrong, diagnoses the problem, and helps fix it. Except instead of scraped knees, it's production errors.

Production alert triage agent for Rails applications. Receives error alerts from AppSignal and Rollbar, triages them with an LLM, creates GitHub issues with structured diagnoses, and dispatches AI agents for auto-fixes.

## How It Works

```
AppSignal/Rollbar → Cloudflare Worker (webhook proxy) → GitHub repository_dispatch
→ Baymax triage workflow → LLM diagnosis → GitHub issue → AI agent fix → PR verification
```

1. Your error monitoring service sends a webhook to a Cloudflare Worker proxy
2. The proxy validates the signature and dispatches the event to your GitHub repo
3. The **triage workflow** runs `baymax triage`, which filters, analyzes, and diagnoses the error
4. Baymax creates a GitHub issue with the diagnosis and, if confident enough, dispatches an AI agent to fix it
5. When the agent opens a PR labeled `baymax-fix`, the **verify workflow** checks the fix

## Prerequisites

- Rails 7.0+
- Ruby 3.1+
- A [Cloudflare Workers](https://workers.cloudflare.com/) account (for the webhook proxy)
- [AppSignal](https://www.appsignal.com/) and/or [Rollbar](https://rollbar.com/) for error monitoring
- An [Anthropic API key](https://console.anthropic.com/) for LLM triage

## Installation

Add to your Gemfile:

```ruby
gem "baymax"
```

Run the install generator:

```bash
bundle install
rails generate baymax:install
```

This creates:

| File | Purpose |
|------|---------|
| `config/baymax_settings.yml` | Triage thresholds, LLM config, filter rules |
| `.github/workflows/baymax_triage.yml` | Workflow triggered by webhook dispatch |
| `.github/workflows/baymax_verify.yml` | Workflow triggered by PRs labeled `baymax-fix` |
| `.github/prompts/baymax_triage.md` | LLM system prompt for error diagnosis |
| `.github/prompts/baymax_diagnosis.md` | Issue body template documentation |
| `.github/prompts/baymax_fix_instructions.md` | Instructions for the AI agent fixing the error |

## Setup

### 1. Deploy the webhook proxy

Deploy [telos-webhook-proxy](https://github.com/TelosLabs/telos-webhook-proxy) to Cloudflare Workers. This receives webhooks from your error monitoring service and forwards them as `repository_dispatch` events to GitHub.

Add these secrets to your Cloudflare Worker:

| Secret | Description |
|--------|-------------|
| `GITHUB_TOKEN` | Fine-grained PAT (see step 3a below) |
| `APPSIGNAL_WEBHOOK_SECRET` | From your AppSignal webhook configuration |
| `ROLLBAR_WEBHOOK_SECRET` | From your Rollbar webhook configuration (if using Rollbar) |

### 2. Configure your error monitoring webhooks

Point your error monitoring service to the proxy URL:

```
https://your-proxy.workers.dev/?repo=YourOrg/YourRepo
```

- **AppSignal**: Settings > Notifications & Integrations > Webhooks
- **Rollbar**: Project Settings > Notifications > Webhook

### 3. Create GitHub fine-grained personal access tokens

You need two tokens with **fine-grained** permissions scoped to your target repository.

**a) Webhook proxy token** (used by the Cloudflare Worker):

| Permission | Access |
|------------|--------|
| Contents | Read and write |

This token needs `Contents: Read and write` to trigger `repository_dispatch` events.

**b) Agent dispatch token** (used by the triage workflow to assign AI agents):

| Permission | Access |
|------------|--------|
| Contents | Read and write |
| Issues | Read and write |
| Pull requests | Read and write |

Create both tokens at [github.com/settings/tokens](https://github.com/settings/tokens?type=beta).

### 4. Add GitHub Actions secrets

Go to your repo's **Settings > Secrets and variables > Actions** and add:

| Secret | Required | Description |
|--------|----------|-------------|
| `ANTHROPIC_API_KEY` | Yes | Anthropic API key for LLM triage |
| `AGENT_ASSIGN_TOKEN` | Yes | Fine-grained PAT from step 3b |
| `APPSIGNAL_API_KEY` | If using AppSignal | Fetches full error details from the AppSignal API |
| `ROLLBAR_API_TOKEN` | If using Rollbar | Fetches full error details from the Rollbar API |

> **Note:** `GITHUB_TOKEN` is provided automatically by GitHub Actions — you do not need to add it as a secret.

### 5. Update your config

Open `config/baymax_settings.yml` and set your repository:

```yaml
github:
  repo: YourOrg/YourRepo
```

Review the defaults and adjust as needed:

```yaml
filter:
  min_severity: warning        # Ignore info/debug alerts
  min_occurrences: 3           # Require 3+ occurrences before triaging

decision:
  confidence_threshold: 0.8    # Only auto-fix when LLM confidence > 80%

triage:
  max_triage_per_hour: 10      # Rate limit to avoid runaway costs
```

### 6. Test locally

Verify everything is wired up correctly:

```bash
# Dry run with a fixture payload (no API calls, no LLM)
bundle exec baymax triage --fixture appsignal --dry-run --skip-llm

# Dry run with LLM triage (requires ANTHROPIC_API_KEY)
bundle exec baymax triage --fixture appsignal --dry-run

# Test with a Rollbar payload
bundle exec baymax triage --fixture rollbar --dry-run --skip-llm
```

A successful run prints a JSON summary with the triage result.

## CLI Reference

```
Usage: baymax <mode> [options]
Modes: triage, verify
```

### Triage mode

```bash
baymax triage [options]
```

| Option | Description |
|--------|-------------|
| `--config PATH` | Path to settings YAML (default: `config/baymax_settings.yml`) |
| `--prompt PATH` | Path to custom triage prompt |
| `--dry-run` | Run pipeline without GitHub API calls |
| `--skip-llm` | Skip LLM triage, use filter-only data |
| `--fixture NAME` | Use a built-in fixture (`appsignal` or `rollbar`) |
| `--event PATH` | Load event from a JSON file |

### Verify mode

```bash
baymax verify --pr NUMBER [options]
```

| Option | Description |
|--------|-------------|
| `--pr NUMBER` | PR number to verify (required) |
| `--config PATH` | Path to settings YAML |
| `--dry-run` | Run without posting comments |

## Decision Outcomes

After triage, Baymax decides on one of these actions:

| Outcome | When | What happens |
|---------|------|--------------|
| **skip** | Duplicate alert (existing issue found) | Nothing — silently deduplicates |
| **queued** | Rate limit reached | Issue created with `baymax-queued` label |
| **diagnosis_only** | Low confidence, data-related, or security tier 3 | Issue created, no agent dispatched |
| **fix_with_review** | Security tier 2 | Issue + agent dispatched, PR labeled `review-required` |
| **fix** | Tier 1, high confidence, fixable | Issue + agent dispatched for auto-fix |

## Customization

### Triage prompt

Edit `.github/prompts/baymax_triage.md` to adjust how the LLM diagnoses errors. The prompt controls the JSON output format, confidence calibration, and security tier classification.

### Fix instructions

Edit `.github/prompts/baymax_fix_instructions.md` to change the constraints given to the AI agent when it creates fix PRs.

### Filter rules

In `config/baymax_settings.yml`, you can ignore specific error classes, set minimum severity and occurrence thresholds, and control the triage rate limit.

## License

Available as open source under the [MIT License](LICENSE.txt).
