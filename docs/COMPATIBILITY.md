# Compatibility / 兼容性

## Validation baseline / 验证基线

- ChatGPT for macOS: `26.803.61601`
- Codex CLI/App Server: `0.147.0-alpha.6.5`
- Protocol methods: `account/read`, `account/rateLimits/read`
- Validation date: 2026-08-13

The app does not hard-code a plan allowlist. It displays the `planType`, quota buckets, windows, reset timestamps, credits, and reached-limit state returned by Codex App Server.

应用不使用套餐白名单，而是展示 Codex App Server 返回的 `planType`、限额桶、窗口、重置时间、Credits 和限额已用尽状态。

| Plan / 计划 | Parser fixture / 解析测试 | Live account / 真实账户 |
|---|---:|---:|
| Free | Pass / 通过 | Not yet verified / 未验证 |
| Go | Pass / 通过 | Not yet verified / 未验证 |
| Plus | Pass / 通过 | Not yet verified / 未验证 |
| Pro | Pass / 通过 | Pass / 通过 |
| Business | Pass / 通过 | Not yet verified / 未验证 |
| Edu | Pass / 通过 | Not yet verified / 未验证 |
| Enterprise | Pass / 通过 | Not yet verified / 未验证 |

An authenticated account that returns no active quota bucket is shown as a valid account with “No usage window available,” rather than as malformed data. Availability can still depend on plan, region, workspace policy, and the server version.

已认证但未返回活动限额桶的账户会显示“暂无可展示的限额窗口”，不再被误判为数据损坏。实际可用性仍可能受到套餐、地区、工作区策略和服务端版本影响。
