# RASPA3

本页所有提交命令均支持将 `-h` 或 `--help` 作为第一个参数查看用法、参数及默认设置；查看帮助不会提交作业或生成文件。

提交时会在当前目录生成并保留完整的 `myraspa3-tmp`，可执行 `sbatch myraspa3-tmp` 重提相同作业；再次运行 `myraspa3.sh` 会覆盖该文件。直接重提不会追加 `Batch.log`。

1. RASPA3 版本为 3.0.30，安装前缀为 `/data/home/liqh/soft/raspa3`
2. 作业启动前覆盖重建 `PATH` 和 `LD_LIBRARY_PATH`，然后固定加载 `/data/home/liqh/soft/raspa3/env.sh`
3. `env.sh` 设置 `RASPA3_ROOT` 和 `RASPA_DIR`（`/data/home/liqh/soft/raspa3/usr/share/raspa3`），并把 `/data/home/liqh/soft/raspa3/usr/bin` 加入 `PATH`
4. 运行命令名为 `raspa3`，对应 `usr/bin/raspa3`。`env.sh` 提供的库路径包括安装自带的 libomp、`/data/app/lapack/3.12.1/lib64` 和 `/data/app/cuda/cuda-11.8/lib64`
5. 固定使用 `p1` 分区。该分区按整节点计费。脚本申请 1 个节点、1 个任务、每任务 48 个 CPU，不使用 `mpirun`
6. 脚本不显式申请 Slurm 内存，使用分区默认值。节点报告内存为 382000 MB
7. 不设置 `OMP_NUM_THREADS`、`MKL_*`、`OPENBLAS_*` 或 `KMP_*`。线程数由 `simulation.json` 的 `NumberOfThreads`（默认 1）和 `ThreadingType`（默认 Serial）决定；`NumberOfThreads` 不应超过 48。脚本不修改输入文件
8. 必须在包含 `simulation.json` 的任务目录中运行。程序固定读取当前目录的 `simulation.json`，不接受其他输入文件名
9. Slurm 作业名使用任务目录名称
10. 标准输出写入 `raspa3.out`，标准错误写入 `raspa3.err`。已有 `raspa3.out` 会中文警告后覆盖。程序还会在任务目录的 `output/` 中写入各体系的结果文件
11. 计算节点不能访问互联网。作业只使用已安装的 RASPA3 和任务目录中的文件
12. 作业成功提交后追加任务目录中的 `Batch.log`

## 调用方式

```text
myraspa3.sh
```

示例：

```bash
cd calculations/methane
myraspa3.sh
```
