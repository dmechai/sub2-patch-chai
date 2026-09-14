#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "${script_dir}/.." && pwd)
upstream_repo=${UPSTREAM_REPO:-https://github.com/Wei-Shaw/sub2api.git}
upstream_ref=${UPSTREAM_REF:-${1:-main}}
output_dir=${2:-${repo_dir}/upstream-src}
patch_file="${repo_dir}/patches/easypay-upstream-type-dot.patch"

if [[ -e "${output_dir}" ]]; then
  echo "Refusing to overwrite existing path: ${output_dir}" >&2
  exit 1
fi

git clone --filter=blob:none --no-checkout "${upstream_repo}" "${output_dir}"
git -C "${output_dir}" checkout --detach "${upstream_ref}"

backend_file="${output_dir}/backend/internal/service/payment_config_providers.go"
frontend_file="${output_dir}/frontend/src/components/payment/PaymentProviderDialog.vue"

if grep -Fq 'easyPayUpstreamMethodCodePattern' "${backend_file}" \
  && grep -Fq '/^[a-z0-9_.-]+$/.test(method.upstreamType)' "${frontend_file}"; then
  patch_status=already-in-upstream
elif git -C "${output_dir}" apply --check "${patch_file}"; then
  git -C "${output_dir}" apply "${patch_file}"
  patch_status=applied
else
  echo "The upstream source is neither already fixed nor compatible with the patch." >&2
  echo "Review the upstream EasyPay validation changes before building this version." >&2
  exit 2
fi

source_revision=$(git -C "${output_dir}" rev-parse HEAD)
printf 'UPSTREAM_REF=%s\nUPSTREAM_REVISION=%s\nPATCH_STATUS=%s\n' \
  "${upstream_ref}" "${source_revision}" "${patch_status}" \
  > "${output_dir}/.sub2api-patch-info"

echo "Prepared ${upstream_ref} (${source_revision}) with patch status: ${patch_status}"
