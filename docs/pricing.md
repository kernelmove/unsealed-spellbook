# Token 计费规则

Unsealed Spellbook 使用静态价格表估算模型调用成本。价格单位均为 **USD / 1,000,000 tokens**；配置文件是 [`model-pricing.json`](../Sources/UnsealedSpellbookCore/Resources/model-pricing.json)。

## 计算公式

```text
costUSD = (
  inputTokens × inputRate
  + (outputTokens + reasoningTokens) × outputRate
  + cacheReadTokens × cacheReadRate
  + cacheWriteTokens × cacheWriteRate
) / 1,000,000
```

Gemini CLI 的 `toolUsePromptTokenCount` 按上游记录的 `totalTokenCount` 归一化：若总量将其单独计入，则合并到输入 Token；若总量已经包含于 Prompt Token，则不重复计算。

各模型成本相加得到所选时间范围的总成本。模型名称必须与配置中的 `model` 忽略大小写地完整匹配；未知模型不应用推测价格，不计入成本，并在界面中标记为“未计价”。金额仅为依据本价格表得到的估算值，不代替供应商账单。

界面中的金额从 `$1,000` 起使用 `K`、`M`、`B`、`T` 紧凑显示；这只是显示格式，底层计算和聚合仍保留完整精度。

## 模型价格

| 模型 | Input | Output | Cache Read | Cache Write |
| --- | ---: | ---: | ---: | ---: |
| `gpt-5.6-sol` | 5 | 30 | 0.5 | 6.25 |
| `gpt-5.6-terra` | 2.5 | 15 | 0.25 | 3.125 |
| `gpt-5.6-luna` | 1 | 6 | 0.1 | 1.25 |
| `gpt-5.5` | 5 | 30 | 0.5 | 0 |
| `gpt-5.5-pro` | 30 | 180 | 0 | 0 |
| `gpt-5.4` | 2.5 | 15 | 0.25 | 0 |
| `gpt-5.4-pro` | 30 | 180 | 0 | 0 |
| `gpt-5.4-mini` | 0.75 | 4.5 | 0.075 | 0 |
| `gpt-5.4-nano` | 0.2 | 1.25 | 0.02 | 0 |
| `gpt-5.3-codex` | 1.75 | 14 | 0.175 | 0 |
| `gpt-5-mini` | 0.25 | 2 | 0.025 | 0 |
| `gpt-5-nano` | 0.05 | 0.4 | 0.005 | 0 |
| `gpt-4o-mini` | 0.15 | 0.6 | 0.075 | 0 |
| `claude-fable-5` | 10 | 50 | 1 | 12.5 |
| `claude-sonnet-5` | 3 | 15 | 0.3 | 3.75 |
| `claude-mythos-5` | 10 | 50 | 1 | 12.5 |
| `claude-opus-4-8` | 5 | 25 | 0.5 | 6.25 |
| `claude-opus-4-7` | 5 | 25 | 0.5 | 6.25 |
| `claude-opus-4-6` | 5 | 25 | 0.5 | 6.25 |
| `claude-opus-4-6-fast` | 30 | 150 | 3 | 37.5 |
| `claude-opus-4-6-1m` | 5 | 25 | 0.5 | 6.25 |
| `claude-opus-4-6-1m-fast` | 30 | 150 | 3 | 37.5 |
| `claude-sonnet-4-6` | 3 | 15 | 0.3 | 3.75 |
| `claude-sonnet-4-6-1m` | 3 | 15 | 0.3 | 3.75 |
| `claude-haiku-4-5-20251001` | 1 | 5 | 0.1 | 1.25 |
| `gemini-3.1-pro-preview` | 2 | 12 | 0.2 | 0 |
| `gemini-3.5-flash` | 1.5 | 9 | 0.15 | 0 |
| `gemini-3.1-flash-lite` | 0.25 | 1.5 | 0.025 | 0 |
| `gemini-3-flash-preview` | 0.5 | 3 | 0.05 | 0 |
| `deepseek-v4-flash` | 0.14 | 0.28 | 0.0028 | 0 |
| `deepseek-v4-pro` | 0.435 | 0.87 | 0.003625 | 0 |
| `deepseek-chat` | 0.14 | 0.28 | 0.0028 | 0 |
| `deepseek-reasoner` | 0.14 | 0.28 | 0.0028 | 0 |
| `deepseek-v3` | 0 | 0.28 | 0.014 | 0.14 |
| `deepseek-r1` | 0 | 2.19 | 0.14 | 0.55 |
| `qwen3.7-max` | 1.65 | 4.951 | 0.33 | 0 |
| `qwen3.7-plus` | 0.276 | 1.101 | 0.0552 | 0 |
| `qwen3.6-plus` | 0.276 | 1.651 | 0.0552 | 0 |
| `qwen3.5-plus` | 0.115 | 0.688 | 0 | 0 |
| `qwen3.6-flash` | 0.165 | 0.99 | 0 | 0 |
| `qwen3.5-flash` | 0.029 | 0.287 | 0 | 0 |
| `qwen-flash` | 0.022 | 0.216 | 0.0044 | 0 |
| `qwen3-coder-next` | 0.3 | 1.5 | 0 | 0 |
| `qwen3-coder-flash` | 0.144 | 0.574 | 0.0288 | 0 |
| `qwen3-coder-30b-a3b-instruct` | 0.216 | 0.861 | 0 | 0 |
| `qwen3.6-35b-a3b` | 0.248 | 1.485 | 0 | 0 |
| `qwen3.6-27b` | 0.6 | 3.6 | 0 | 0 |
| `qwen3.5-397b-a17b` | 0.172 | 1.032 | 0 | 0 |
| `qwen3.5-122b-a10b` | 0.115 | 0.917 | 0 | 0 |
| `qwen3.5-27b` | 0.086 | 0.688 | 0 | 0 |
| `qwen3.5-35b-a3b` | 0.057 | 0.459 | 0 | 0 |
| `qwen3-coder-plus` | 1 | 5 | 0 | 0 |
| `qwen3-coder-480b-a35b-instruct` | 1.5 | 7.5 | 0 | 0 |
| `qwen3-235b-a22b` | 2 | 8 | 8 | 2 |
| `qwen3-32b` | 2 | 8 | 8 | 2 |
| `qwen3-30b-a3b` | 0.75 | 3 | 3 | 0.75 |
| `qwen3-14b` | 1 | 4 | 4 | 1 |
| `qwen3-8b` | 0.5 | 2 | 2 | 0.5 |
| `qwen3-4b` | 0.3 | 1.2 | 1.2 | 0.3 |
| `qwen3-1.7b` | 0.3 | 1.2 | 1.2 | 0.3 |
| `qwen3-0.6b` | 0.3 | 1.2 | 1.2 | 0.3 |
| `qwen2.5-coder-32b-instruct` | 0.002 | 0.006 | 0.006 | 0.002 |
| `qwen2.5-coder-14b-instruct` | 0.002 | 0.006 | 0.006 | 0.002 |
| `qwen2.5-coder-7b-instruct` | 0.001 | 0.002 | 0.002 | 0.001 |
| `qwen2.5-coder-3b-instruct` | 0 | 0 | 0 | 0 |
| `qwen2.5-coder-1.5b-instruct` | 0 | 0 | 0 | 0 |
| `qwen2.5-coder-0.5b-instruct` | 0 | 0 | 0 | 0 |
| `qwen-coder-plus-latest` | 3.5 | 7 | 7 | 3.5 |
| `qwen-plus-latest` | 0.8 | 2 | 2 | 0.8 |
| `qwen-turbo-latest` | 0.3 | 0.6 | 0.6 | 0.3 |
| `qwen-max-latest` | 2.4 | 9.6 | 9.6 | 2.4 |
| `qwq-plus-latest` | 0 | 0 | 0 | 0 |
| `qwq-plus` | 0 | 0 | 0 | 0 |
| `qwen-coder-plus` | 3.5 | 7 | 7 | 3.5 |
| `qwen-plus` | 0.8 | 2 | 0.2 | 0.8 |
| `qwen-turbo` | 0.3 | 0.6 | 0.6 | 0.3 |
| `qwen-max` | 2.4 | 9.6 | 9.6 | 2.4 |
| `qwen-vl-max` | 3 | 9 | 9 | 3 |
| `qwen-vl-max-latest` | 3 | 9 | 9 | 3 |
| `qwen-vl-plus` | 1.5 | 4.5 | 4.5 | 1.5 |
| `qwen-vl-plus-latest` | 1.5 | 4.5 | 4.5 | 1.5 |
| `kimi-k2.7-code` | 0.95 | 4 | 0.19 | 0 |
| `kimi-k2.7-code-highspeed` | 1.9 | 8 | 0.38 | 0 |
| `kimi-k2.6` | 0.95 | 4 | 0.16 | 0 |
| `kimi-k2.5` | 0.6 | 3 | 0.1 | 0 |
| `kimi-k2-0905-preview` | 0.6 | 2.5 | 0.15 | 0 |
| `kimi-k2-0711-preview` | 0.6 | 2.5 | 0.15 | 0 |
| `kimi-k2-turbo-preview` | 2.4 | 10 | 0.6 | 0 |
| `kimi-k2-thinking` | 0.6 | 2.5 | 0.15 | 0 |
| `kimi-k2-thinking-turbo` | 1.15 | 8 | 0.15 | 0 |
| `MiniMax-M3` | 0.6 | 2.4 | 0.12 | 0.6 |
| `MiniMax-M2.7` | 0.3 | 1.2 | 0.06 | 0.375 |
| `MiniMax-M2.7-highspeed` | 0.6 | 2.4 | 0.06 | 0.375 |
| `MiniMax-M2.5` | 0.3 | 1.2 | 0.03 | 0.375 |
| `MiniMax-M2.5-highspeed` | 0.6 | 2.4 | 0.03 | 0.375 |
| `MiniMax-M2.1` | 0.3 | 1.2 | 0.03 | 0.375 |
| `MiniMax-M2.1-lightning` | 0.6 | 2.4 | 0.03 | 0.375 |
| `MiniMax-M2` | 0.3 | 1.2 | 0 | 0 |
