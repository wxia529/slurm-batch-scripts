# Slurm Batch Scripts

本项目为课题组维护不同超算集群上的 Slurm 作业提交脚本，统一解决资源申请、软件环境、作业命名和提交记录问题。

## 支持矩阵

| 集群 | 每节点核心数 | 分区 | Gaussian | CP2K | QE | VASP | ORCA |
| --- | ---: | --- | :---: | :---: | :---: | :---: | :---: |
| `mindu` | 32 | `small`、`community`、`highio` | ✓ | ✓ | — | ✓ | ✓ |
| `para-amd` | 64 | 固定 `amd_256` | ✓ | ✓ | — | ✓ | ✓ |
| `para-e5` | 24 | 固定 `v3_64` | — | ✓ | ✓ | ✓ | ✓ |

## 使用流程

```mermaid
flowchart LR
    A[克隆源码仓库] --> B[选择当前集群]
    B --> C[运行 deploy.sh]
    C --> D[加载 env.sh]
    D --> E[进入计算目录]
    E --> F[调用 my*.sh]
    F --> G[Slurm 接收任务]
    G --> H[追加 Batch.log]
```

## 从这里开始

- [快速开始](getting-started.md)：完成第一次部署和任务提交
- [部署与更新](deployment.md)：了解部署范围和用户文件保护
- [环境加载](environment.md)：加载提交命令并理解作业环境
- [Batch.log](batch-log.md)：查看统一提交历史
- [参与维护](contributing.md)：修改脚本、测试和提交 Pull Request

每个集群和软件的具体参数请从顶部导航中的“集群”进入。
