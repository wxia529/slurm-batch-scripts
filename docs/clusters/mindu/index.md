# mindu 集群

## 硬件与分区

1. 每个节点都是 32 核心
2. 支持三个分区：`community`、`small`、`highio`
3. 所有脚本默认使用 `small` 分区

## 通用提交记录

1. 所有作业提交脚本统一使用 `Batch.log` 记录提交历史
2. `Batch.log` 放在任务目录，并且是普通可见文件；对于 Gaussian、CP2K、QE、ORCA，任务目录就是输入文件所在目录
3. Slurm 成功接收作业后，在 `Batch.log` 中追加一行，不覆盖已有记录
4. 提交失败时不写入记录
5. 每条记录包含：
   - 提交时间
   - 软件名称
   - Slurm Job ID
   - 作业名称
   - 分区
   - 节点数
   - 核心数或 MPI 进程数
   - 任务目录
   - 输入文件
   - 输出文件
6. 多个任务同时提交时，必须保证每条记录完整，不能互相覆盖
7. 任务目录必须使用绝对路径，例如：

```text
2026-07-20 18:30:12 | Gaussian | job_id=123456 | job=water | partition=small | nodes=1 | cores=32 | directory=/data/project/water | input=water.gjf | output=water.log
```
