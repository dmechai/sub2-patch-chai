#!/usr/bin/env bash
set -Eeuo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd -- "${script_dir}/.." && pwd)
upstream_ref=${1:-}
image_tag=${2:-sub2api-custom:latest}

if [[ -z "${upstream_ref}" ]]; then
  upstream_ref=$("${script_dir}/latest-release.sh")
fi

build_root=$(mktemp -d /tmp/sub2api-custom-build.XXXXXX)
trap 'rm -rf "${build_root}"' EXIT
source_dir="${build_root}/source"

"${script_dir}/prepare-source.sh" "${upstream_ref}" "${source_dir}"
source_revision=$(git -C "${source_dir}" rev-parse HEAD)
version="${upstream_ref}-dotfix"

docker build \
  --build-arg "VERSION=${version}" \
  --build-arg "COMMIT=${source_revision}" \
  --label "org.opencontainers.image.revision=${source_revision}" \
  --label "org.opencontainers.image.version=${version}" \
  --label "org.opencontainers.image.source=https://github.com/Wei-Shaw/sub2api" \
  --tag "${image_tag}" \
  "${source_dir}"

echo "Built ${image_tag} from ${upstream_ref}; no running container was changed."
