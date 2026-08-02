# Changelog

## [1.0.0] - 2026-08-02

### Added
- `health` command — check all provider endpoints in one call
- `cost-report` command — usage summary by provider, tier, and day
- `benchmark` command — latency test across active providers
- `init` command — create default config in `~/.config/model-router/`
- `--help` and `--version` flags
- Request logging to `~/.model-router/usage.log`
- Fallback chain with stderr notification when a provider is unavailable
- Comprehensive test suite (25+ assertions)
- GitHub Actions CI with shellcheck linting
- Example scripts for CI pipelines, cron jobs, and multi-provider failover

### Changed
- Improved error messages with actionable guidance
- `info` command now shows cost limits and version
- `recommend` command now shows cost and effort details

## [0.1.0] - 2026-08-02

### Added
- Initial release
- Tier-based routing (heavy, standard, light, local, local-fast, gemini, mistral)
- Agent and job name resolution
- Provider fallback when primary is disabled
- Eval-safe output with injection prevention
- Safe defaults when config is missing or corrupt
- 5-provider support (Anthropic, Google, Mistral, OpenAI, Ollama)
