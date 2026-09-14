# Sub2API EasyPay 点号补丁

这个仓库从 Sub2API 官方正式版本构建镜像，并在需要时允许 EasyPay 的
`upstreamType` 使用点号，例如 `usdt.trc20`。

补丁只放宽 `upstreamType` 校验。Sub2API 内部使用的自定义支付方式 `type`
仍然只能包含小写字母、数字、下划线和短横线；发给支付上游的
`upstreamType` 不会被转换。

## 当前情况

- 此仓库不会管理或修改正在运行的服务。
- 官方修复提交为 `c3b3072a6fae7ae6c686e05df78060c74f284a67`，已通过官方
  PR `#7012` 合并。
- 修复已经在官方 `main`，但尚未进入最新正式版本 `v0.2.4`。
- `prepare-source.sh` 会按文件名顺序处理 `patches/*.patch`。旧版本能应用时才应用；
  官方已经包含同一补丁时会自动跳过；两种检查都不通过时停止构建，避免生成未知镜像。

## 只验证，不构建、不重启

```bash
release=$(./scripts/latest-release.sh)
./scripts/prepare-source.sh "$release" /tmp/sub2api-patch-check
cat /tmp/sub2api-patch-check/.sub2api-patch-info
```

`v0.2.4` 应显示 `easypay-upstream-type-dot.patch:applied`，当前官方 `main` 应显示
`easypay-upstream-type-dot.patch:already-in-upstream`。

## 本机构建

第一个参数留空时使用官方最新正式版本：

```bash
./scripts/build.sh "" sub2api-custom:latest
```

这只会生成本地 Docker 镜像，不会停止、重启或替换正在运行的容器。

## 上传 GitHub 并跟随官方更新

新建一个空的 GitHub 仓库，把本仓库推送上去并启用 GitHub Actions。工作流每天
检查官方最新正式版本，构建后发布到 GitHub Container Registry：

```text
ghcr.io/YOUR_GITHUB_NAME/sub2api-custom:latest
ghcr.io/YOUR_GITHUB_NAME/sub2api-custom:vX.Y.Z-dotfix
```

生产环境应使用明确的版本标签，测试通过后再主动切换。定时构建不会操作服务器，
所以官方发布新版本不会让生产服务被静默重启。

在仓库的 Actions secrets 中配置 `TELEGRAM_BOT_TOKEN` 和
`TELEGRAM_CHAT_ID` 后，每次构建都会通知成功或失败。成功通知仅表示候选镜像已经
通过后端校验、支付参数透传和前端表单测试，并已推送到 GHCR；通知本身不会部署。
成功通知还会提供一个“打开部署页面”按钮。部署入口是单独的手动工作流，任何定时
任务都不能调用它；页面还会要求 `production` 环境审批。

修改 `patches/`、`scripts/` 或构建工作流并推送到 `main` 时也会触发自检。仅修改
说明文档不会重复构建镜像。

以后增加补丁时，把标准 Git patch 文件放入 `patches/`，同时加入覆盖该行为的测试，
再推送到 `main`。构建过程只修改临时下载的官方源码副本，不会覆盖 Wei-Shaw 的官方
仓库或官方镜像；最终发布的是 `dmechai/sub2api-custom` 自有镜像。

## 部署工作流所需配置

在仓库 `Settings -> Environments` 新建 `production` 环境，添加你自己的审批人，
并在该环境的 **Environment secrets** 中配置：

```text
DEPLOY_HOST       服务器 IP 或域名
DEPLOY_PORT       SSH 端口，通常是 22
DEPLOY_USER       SSH 用户，需能执行 Docker
DEPLOY_PATH       /root/sub2api-deploy
DEPLOY_SSH_KEY    GitHub Actions 使用的私钥
DEPLOY_KNOWN_HOSTS 服务器固定的 known_hosts 行
GHCR_USERNAME     能拉取 GHCR 镜像的 GitHub 用户名
GHCR_TOKEN        只读 GHCR Token；公开镜像可留空
```

部署工作流会先等待 `production` 审批，随后通过 SSH 在服务器上临时生成 Compose
override，创建当前容器的回滚镜像，拉取候选镜像并重建 **仅 Sub2API 容器**。健康检查
失败会恢复刚才保存的容器镜像并使工作流失败。PostgreSQL、Redis 和数据目录不会被
重建或删除。

当前服务器实际运行官方 `v0.2.4`。Docker 镜像标签仍记录初始版本 `v0.1.179`，
但页面在线更新已经把容器内程序升级到了 `v0.2.4`。首次构建应手动运行一次工作流，
把 `upstream_ref` 填为 `v0.2.4`，测试 `v0.2.4-dotfix` 后再让生产使用该版本。
定时任务可以继续构建新版本，但不会自动部署。

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
