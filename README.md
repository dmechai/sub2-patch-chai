# Sub2API EasyPay 点号补丁

这个仓库从 Sub2API 官方正式版本构建镜像，并在需要时允许 EasyPay 的
`upstreamType` 使用点号，例如 `usdt.trc20`。

补丁只放宽 `upstreamType` 校验。Sub2API 内部使用的自定义支付方式 `type`
仍然只能包含小写字母、数字、下划线和短横线；发给支付上游的
`upstreamType` 不会被转换。

## 当前情况

- Actions 工作流会构建官方 Sub2API 源码并应用补丁；通过预检后自动更新应用容器，不修改数据库或 Redis。
- 官方修复提交为 `c3b3072a6fae7ae6c686e05df78060c74f284a67`，已通过官方 PR `#7012` 合并，并已包含在官方 `v0.2.20` 源码中。
- `prepare-source.sh` 会按文件名顺序处理 `patches/*.patch`：官方未包含补丁时应用，
已包含时自动跳过；两种检查都不通过时停止构建，避免生成未知镜像。

## 只验证，不构建、不重启

```bash
release=$(./scripts/latest-release.sh)
./scripts/prepare-source.sh "$release" /tmp/sub2api-patch-check
cat /tmp/sub2api-patch-check/.sub2api-patch-info
```

当前官方 `v0.2.20` 的 `.sub2api-patch-info` 中，`easypay-upstream-type-dot.patch`
应显示 `already-in-upstream`。

## 本机构建

第一个参数留空时使用官方最新正式版本：

```bash
./scripts/build.sh "" sub2api-custom:latest
```

这只会生成本地 Docker 镜像，不会停止、重启或替换正在运行的容器。

## 上传 GitHub 并跟随官方更新

新建一个空的 GitHub 仓库，把本仓库推送上去并启用 GitHub Actions。工作流每天北京时间 04:00 检查官方最新正式版本；候选镜像不存在时，先应用本地补丁并运行后端、前端测试，再构建镜像。无论候选镜像是本次新构建还是之前已构建，都会进行生产预检；只有线上镜像 ID 不同才切换容器。

```text
ghcr.io/YOUR_GITHUB_NAME/sub2api-custom:latest
ghcr.io/YOUR_GITHUB_NAME/sub2api-custom:vX.Y.Z-dotfix
```

生产预检会验证当前服务健康、候选镜像来源和版本、候选程序可启动；生产镜像不同时保存回滚快照。预检不重启服务。服务器按镜像 ID 判断候选是否已在运行：相同则报告成功但不重启，不同才激活。激活后还会再次检查健康状态，失败时服务器自动恢复先前容器。数据库、Redis 和数据目录不会被重建或删除。

Telegram 会在构建或部署失败、以及新版本部署完成时通知官方版本、Release 摘要、本地补丁状态和最终结果，并提供一个回退按钮。没有新官方版本时不重复构建、部署或发送更新消息。

仅修改说明文档不会重复构建镜像。

以后增加补丁时，把标准 Git patch 文件放入 `patches/`，同时加入覆盖该行为的测试，
再推送到 `main`。构建过程只修改临时下载的官方源码副本，不会覆盖 Wei-Shaw 的官方
仓库或官方镜像；最终发布的是 `dmechai/sub2api-custom` 自有镜像。

## 部署工作流所需配置

在仓库 `Settings -> Secrets and variables -> Actions` 配置以下 Repository secrets。自动部署使用这些仓库级 secrets，不经过要求人工审批的 `production` environment；`deploy.yml` 手动部署工作流仍受该 environment 审批保护，作为备用入口。

```text
DEPLOY_HOST       服务器 IP 或域名
DEPLOY_PORT       SSH 端口，通常是 22
DEPLOY_USER       固定填 sub2api-deployer
DEPLOY_PATH       不再需要；服务器脚本固定使用 /root/sub2api-deploy
DEPLOY_SSH_KEY    GitHub Actions 使用的私钥
DEPLOY_KNOWN_HOSTS 服务器固定的 known_hosts 行
```

自动部署先通过 SSH 做预检：验证当前服务健康、拉取候选镜像、检查版本和官方来源标签、运行二进制 `--version`，并用不暂停容器的方式保存回滚快照。预检不会重启服务。预检通过后工作流自动切换 **Sub2API 容器**，再做健康检查；失败会自动恢复快照。PostgreSQL、Redis 和数据目录不会被重建或删除。手动部署备用入口仍需要 `production` 环境审批。

部署页面默认使用 `ghcr.io/dmechai/sub2api-custom:latest`，它指向最近一次通过自检并
成功上传的候选镜像；也可以手动填写固定标签（例如 `v0.2.20-dotfix`）以便审计和回滚。
回退工作流从服务器保存的最近一次部署快照恢复，Telegram 的“回退 Sub2API”按钮会
直接进入该工作流。

服务器原先运行 `0.2.19-dotfix`，官方最新正式版为 `v0.2.20`。自动工作流会检查已有候选是否已经运行；若已构建但尚未部署，会继续预检并部署，而不是跳过。

## 以后切换生产镜像

只有镜像已构建、发布并测试后才执行。保留当前 Compose 文件，可以叠加示例
override，也可以只修改 `sub2api.image`。使用示例 override 时：

```bash
export SUB2API_IMAGE=ghcr.io/YOUR_GITHUB_NAME/sub2api-custom:vX.Y.Z-dotfix
docker compose -f /root/sub2api-deploy/docker-compose.local.yml \
  -f /root/sub2api-patch/compose.override.example.yml pull sub2api
docker compose -f /root/sub2api-deploy/docker-compose.local.yml \
  -f /root/sub2api-patch/compose.override.example.yml up -d --no-deps sub2api
```

这里只会重建应用容器；PostgreSQL、Redis 和挂载的数据不会改变。通常只有应用容器
重启所需的短暂时间，不是整套服务长时间停机。

使用自定义镜像期间，不要通过 Sub2API 页面里的在线更新按钮安装官方镜像，应通过
Compose 提升测试过的自定义版本。等官方正式版本包含修复后，本仓库会直接构建官方
源码，不再应用本地补丁。

回滚时，把 `SUB2API_IMAGE` 改回之前记录的镜像标签，再运行同样两条 Compose 命令。
普通的 Docker 或服务器重启只会继续使用已经选定的镜像，不会自行拉取新版本。

## 迁移服务器

把本 Git 仓库和镜像仓库保存在服务器之外。迁移时恢复原有 Sub2API 数据和 Compose
部署；如果 GHCR 包是私有的，先登录 GHCR；再指定相同的版本镜像并启动。生产服务器
不需要保留完整源码。
