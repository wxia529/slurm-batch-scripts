# Slurm Batch Scripts

面向课题组的 Slurm 作业提交脚本集合，为不同超算集群提供统一的命令、资源配置和提交记录。

| 集群 | 每节点核心数 | 分区 | 软件 |
| --- | ---: | --- | --- |
| `mindu` | 32 | `small`、`community`、`highio` | Gaussian、CP2K、VASP |
| `para-amd` | 64 | `amd_256` | Gaussian、CP2K、VASP、ORCA |
| `para-e5` | 24 | `v3_64` | CP2K、QE、VASP、ORCA |

## 快速开始

在源码仓库根目录选择当前集群进行部署：

```bash
./deploy.sh mindu
# 或
./deploy.sh para-amd
# 或
./deploy.sh para-e5
```

加载提交命令：

```bash
source ~/soft/slurm-batchs/env.sh
```

完整的部署、使用和维护说明位于 [`docs/`](docs/index.md)，并通过 Material for MkDocs 构建为文档站点。

源码包通过日期 tag 发布，例如 `release-2026-08-02`。发布流程和下载位置见 [`docs/deployment.md`](docs/deployment.md)。

## 文档维护

`docs/` 是本项目唯一的文档来源。部署目录中的 `README.md` 也由 `docs/` 中对应页面生成，禁止直接维护重复副本。

本地预览：

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements-docs.txt
mkdocs serve
```
