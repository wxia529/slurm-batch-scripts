# para-amd 集群

## 硬件与分区

1. 每个节点都是 64 核心
2. 所有作业固定使用 `amd_256` 分区
3. 提交脚本不提供分区参数

## 通用提交记录

1. 所有作业提交脚本统一使用任务目录中的可见文件 `Batch.log` 记录提交历史
2. Slurm 成功接收作业后追加一行，不覆盖已有记录
3. 提交失败时不写入记录
4. 每条记录包含提交时间、软件名称、Slurm Job ID、作业名称、分区、节点数、核心数或 MPI 进程数、任务目录、输入文件和输出文件
5. 任务目录必须使用绝对路径
6. 多个任务同时提交时，必须使用文件锁保证每条记录完整

记录示例：

```text
2026-07-20 18:30:12 | Gaussian | job_id=123456 | job=water | partition=amd_256 | nodes=1 | cores=64 | directory=/data/project/water | input=water.gjf | output=water.log
```
