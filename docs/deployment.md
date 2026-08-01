# 部署与更新

## 源码与部署目录

源码仓库保存所有集群的脚本和文档；部署目录只保存当前集群实际使用的文件：

```text
源码仓库：slurm-batch-scripts/
部署目录：~/soft/slurm-batchs/
```

部署时，`deploy.sh` 根据参数从对应集群目录（如 `mindu/`、`para-amd/` 或 `para-e5/`）选择脚本，并从 `docs/clusters/` 选择说明文件。

例如：

```text
docs/clusters/mindu/gaussian.md
→ ~/soft/slurm-batchs/gaussian/README.md

mindu/gaussian/myg16.sh
→ ~/soft/slurm-batchs/gaussian/myg16.sh
```

## 安全边界

部署脚本不会：

- 删除任何文件或目录
- 清空部署目录
- 修改 `Batch.log`
- 修改计算输入和输出文件
- 修改 `.bashrc`、`.bash_profile` 等用户配置
- 修改用户放入目录中的其他不同名文件
- 创建或覆盖 `~/bin` 中的命令

部署脚本使用：

```text
~/soft/slurm-batchs/.slurm-batchs-managed
```

记录当前集群和自己管理的路径。如果目标目录已经部署另一套集群，部署会在写入任何文件前停止，避免残留命令使用错误的分区或软件环境。如果目标位置存在同名但未登记的文件，部署同样会停止，避免覆盖用户内容。

所有项目文件都会先复制到部署目录内的临时暂存目录。只有完整暂存成功后，脚本才会记录管理清单并开始安装；首次部署即使中断，下次也可以继续执行。

## 部署内容

所有集群都会部署：

- 集群级 `README.md`
- `env.sh`
- 软件提交脚本
- 软件目录中的 `README.md`

部署脚本会自动发现所选集群目录中的软件及其 Shell 脚本，因此各集群的软件集合可以不同。以后新增软件目录时，不需要在部署逻辑中登记特定软件名称。同一部署目录不允许直接切换集群，部署过程也不会删除目标目录中的其他文件。

旧版管理清单没有集群记录，部署脚本不会根据某个软件名称猜测集群。确认目标目录所属集群后，可显式接管一次：

```bash
./deploy.sh --adopt-legacy mindu
```

接管成功后，后续恢复为普通部署命令。

## 更新部署

进入源码仓库并获取最新版本：

```bash
cd slurm-batch-scripts
git pull --ff-only
```

随后重新部署当前集群：

```bash
./deploy.sh mindu
# 或
./deploy.sh para-amd
# 或
./deploy.sh para-e5
```

重复部署只更新项目管理的文件。

## 发布源码包

项目使用日期 tag 发布完整源码包，格式为：

```text
release-YYYY-MM-DD
```

例如：

```text
release-2026-08-02
```

推送该 tag 后，GitHub Actions 会执行语法检查、三个集群的隔离部署测试和严格文档构建，然后生成：

```text
slurm-batchs-2026-08-02.tar.gz
```

压缩包会上传为 Actions Artifact，并附加到同名 GitHub Release。同一天需要重复发布时，可使用 `release-YYYY-MM-DD-N`，例如 `release-2026-08-02-2`。
