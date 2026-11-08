#!/usr/bin/env bash
# 离线测试用的假 az，仅供 tests/smoke.sh 复制为 az 后使用，不访问 Azure。
# FAKE_FAIL：空格分隔的场景名，命中时返回失败。
# FAKE_ACCOUNTS：`az account list` 返回的 JSON 文件路径。
# FAKE_TENANT：`az account show` 返回的租户 ID。

args="$*"

should_fail() {
  case " ${FAKE_FAIL:-} " in
    *" $1 "*) return 0 ;;
  esac
  return 1
}

case "$args" in
  "account show"*)
    echo "${FAKE_TENANT:-00000000-0000-0000-0000-000000000000}" ;;
  "account list-locations"*)
    echo '[{"name":"eastus2"}]' ;;
  "account list"*)
    cat "${FAKE_ACCOUNTS:-/dev/null}" ;;
  "account set"*)
    exit 0 ;;
  "provider show"*)
    echo '{"registrationState":"Registered"}' ;;
  "provider register"*)
    exit 0 ;;
  "group show"*)
    echo "ResourceGroupNotFound: simulated" >&2
    exit 3 ;;
  "group create"*)
    if should_fail group-create; then
      echo "AuthorizationFailed: simulated group create failure" >&2
      exit 1
    fi
    echo '{}' ;;
  "cognitiveservices account show"*)
    echo "eastus2" ;;
  "cognitiveservices usage list"*)
    echo '[]' ;;
  "cognitiveservices account deployment list"*)
    if should_fail deployments-list; then
      echo "simulated deployment list failure" >&2
      exit 1
    fi
    echo '[]' ;;
  "rest --method PUT"*"/aliases/"*)
    if should_fail alias-put; then
      echo "ERROR: (UserNotAuthorized) simulated alias failure" >&2
      exit 1
    fi
    echo '{"properties":{"provisioningState":"Succeeded","subscriptionId":"22222222-2222-2222-2222-222222222222"}}' ;;
  "rest --method GET"*)
    echo "ResourceNotFound: simulated" >&2
    exit 3 ;;
  *)
    echo '[]' ;;
esac
