# Batch.log 提交记录

所有提交脚本统一在任务目录维护：

```text
Batch.log
```

## 写入时机

脚本使用 `sbatch --parsable` 获取 Slurm Job ID。只有 Slurm 成功接收任务后才会追加记录；提交失败不会写入。

示例：

```text
2026-07-20 18:30:12 | Gaussian | job_id=123456 | job=water | partition=small | nodes=1 | cores=32 | directory=/data/project/water | input=water.gjf | output=water.log
```

## 记录字段

- 提交时间
- 软件名称
- Slurm Job ID
- 作业名称
- 分区
- 节点数
- 核心数或 MPI 进程数
- 任务目录绝对路径
- 输入文件
- 输出文件

多个任务同时提交时，脚本通过 `flock` 锁定记录文件，确保每一行完整。

!!! warning "Batch.log 不是运行结果"
    `Batch.log` 只说明 Slurm 已经接收任务，不代表任务开始运行或成功完成。请使用 `squeue`、`sacct` 和软件输出文件检查状态。
