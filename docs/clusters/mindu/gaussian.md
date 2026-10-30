# Gaussian

本页所有提交命令均支持将 `-h` 或 `--help` 作为第一个参数查看用法、参数及默认设置；查看帮助不会提交作业或生成文件。

提交时会在当前目录生成并保留完整的 `myg16-tmp`，可执行 `sbatch myg16-tmp` 重提相同作业；再次运行 `myg16.sh` 会覆盖该文件。

1. 必须提供一个存在的 Gaussian 输入文件
2. 支持三个分区：`small`、`community`、`highio`
3. 分区支持简写：`s`、`c`、`h`
4. 默认使用 `small` 分区
5. 固定使用单节点 32 核心
6. Slurm 作业名称使用输入文件名去掉扩展名后的名称
7. 使用 `g16` 运行计算
8. 标准输出写入与输入文件同名的 `.log` 文件
9. `.log` 文件放在输入文件所在目录
10. 允许覆盖 `.log`，但文件已存在时必须用中文警告
11. Gaussian 安装目录固定为 `/share/soft/gaussian/G16C01AVX`
12. 使用 `/share/soft/gaussian/G16C01AVX/g16/bsd/g16.profile` 加载运行环境，加载失败时立即退出
13. `highio` 分区（含简写 `h`）的 `GAUSS_SCRDIR` 为 `${HOME}/tmp/g16_${SLURM_JOB_ID}`，即 `~/tmp/` 下的作业独立目录；`small` 和 `community` 分区仍使用节点 `/tmp/${USER}/g16_${SLURM_JOB_ID}`。目录不存在时自动创建，使用 `highio` 前请确认主目录所在文件系统的可用空间和配额充足
14. 作业正常结束后必须清理 `GAUSS_SCRDIR`
15. 作业收到可处理的强制终止信号时也必须终止 Gaussian 进程并清理 `GAUSS_SCRDIR`
16. Slurm 成功接收作业后，按照集群通用格式追加输入目录中的 `Batch.log`

## 调用方式

```text
myg16.sh <input.gjf> [queue]
```

示例：

```text
myg16.sh test.gjf
myg16.sh test.gjf community
myg16.sh test.gjf h
```
