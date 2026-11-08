#!/usr/bin/env bash
# 离线烟雾测试：用假的 az 验证脚本的关键路径，不访问 Azure。
# 用法：bash tests/smoke.sh
# 退出码：全部通过为 0，否则为 1。

set -u

TESTS_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)
REPO_DIR=$(cd "$TESTS_DIR/.." && pwd -P)
SCRIPT="$REPO_DIR/Azure_Foundry_AI_Automation.sh"
FIXTURES="$TESTS_DIR/fixtures"
TENANT="00000000-0000-0000-0000-000000000000"

WORK=$(mktemp -d)
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$WORK/bin"
cp "$TESTS_DIR/fake_az.sh" "$WORK/bin/az"
chmod +x "$WORK/bin/az"

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); printf '  PASS  %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  FAIL  %s\n' "$1"; }

# 有超时命令时限制单次运行时长，避免失败的重试循环挂起测试。
run_limited() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 40 "$@"
  else
    "$@"
  fi
}

# 用法：run_stage <输出目录> <标准输入> <脚本参数...>
# 环境变量 FAKE_FAIL、FAKE_ACCOUNTS 会传给假 az。
run_stage() {
  local out="$1" input="$2"
  shift 2
  mkdir -p "$out"
  printf '%b' "$input" | PATH="$WORK/bin:$PATH" run_limited bash "$SCRIPT" \
    --tenant-id "$TENANT" --skip-login --output-root "$out" "$@" >"$out/stdout.txt" 2>&1
  return $?
}

# 返回指定前缀的第一个结果文件路径。
result_file() {
  local f
  for f in "$1"/results/"$2"_*.csv; do
    if [[ -f "$f" ]]; then
      printf '%s' "$f"
      return 0
    fi
  done
  return 1
}

expect_rc() {
  local name="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then pass "$name"; else fail "$name（退出码 期望 $expected，实际 $actual）"; fi
}

expect_contains() {
  local name="$1" file="$2" needle="$3"
  if [[ -f "$file" ]] && grep -Fq -- "$needle" "$file"; then pass "$name"; else fail "$name（文件中未找到：$needle）"; fi
}

echo "== 参数与校验 =="

out=$(bash "$SCRIPT" --version 2>&1)
if [[ "$out" == *"Azure Foundry AI Automation v"* ]]; then pass "--version 输出版本"; else fail "--version 输出版本"; fi

bash "$SCRIPT" --stage CreateSubscription --dry-run --output-root "$WORK/t_args" >/dev/null 2>&1
expect_rc "缺少 --tenant-id 时以 2 退出" 2 "$?"

run_stage "$WORK/t_validation" "" --stage DeployModels --dry-run --csv "$FIXTURES/plan_new_subscriptions.csv"
expect_rc "DeployModels 校验失败以 1 退出" 1 "$?"
expect_contains "DeployModels 校验失败提示 SubscriptionId" "$WORK/t_validation/stdout.txt" "需要填写 SubscriptionId"

echo "== 阶段 1：创建订阅 =="

FAKE_ACCOUNTS="$FIXTURES/accounts_empty.json" \
  run_stage "$WORK/t_s1_dry" "EA\n" --stage CreateSubscription --dry-run --csv "$FIXTURES/plan_new_subscriptions.csv"
expect_rc "阶段 1 预演正常结束" 0 "$?"
f=$(result_file "$WORK/t_s1_dry" stage1_subscription_creation) && expect_contains "阶段 1 预演记录 WhatIf" "$f" "WhatIf"

# 错误信息必须从子 shell 正确回传（回归：AZ_REST_ERROR_FILE 作用域问题）。
FAKE_FAIL="alias-put" FAKE_ACCOUNTS="$FIXTURES/accounts_empty.json" \
  run_stage "$WORK/t_s1_fail" "EA\nYES\n" --stage CreateSubscription --csv "$FIXTURES/plan_new_subscriptions.csv"
expect_rc "阶段 1 订阅创建失败以 1 退出" 1 "$?"
f=$(result_file "$WORK/t_s1_fail" stage1_subscription_creation) && expect_contains "阶段 1 失败行保留 Azure 错误信息" "$f" "UserNotAuthorized"

echo "== 阶段 2：创建 Foundry 资源 =="

# 资源组创建失败时，不应记为 Succeeded，也不应继续创建账户。
FAKE_FAIL="group-create" FAKE_ACCOUNTS="$FIXTURES/accounts.json" \
  run_stage "$WORK/t_s2_fail" "YES\n" --stage CreateFoundry --csv "$FIXTURES/plan_existing_subscription.csv"
expect_rc "资源组创建失败以 1 退出" 1 "$?"
f=$(result_file "$WORK/t_s2_fail" stage2_foundry_provisioning) && expect_contains "资源组创建失败记为 Failed" "$f" ",Failed,NotStarted,NotStarted,"

echo "== 阶段 4：扩容 =="

# 读取已有部署失败时，应记录失败行，不能静默视为“没有可扩容的部署”。
FAKE_FAIL="deployments-list" FAKE_ACCOUNTS="$FIXTURES/accounts.json" \
  run_stage "$WORK/t_s4_fail" "" --stage ScaleUpQuota --dry-run --csv "$FIXTURES/plan_existing_subscription.csv"
expect_rc "读取部署列表失败以 1 退出" 1 "$?"
f=$(result_file "$WORK/t_s4_fail" stage4_quota_scale_up) && expect_contains "读取部署列表失败记录 Failed 行" "$f" "Failed"

echo
echo "通过 $PASS 项，失败 $FAIL 项。"
if ((FAIL > 0)); then exit 1; fi
exit 0
