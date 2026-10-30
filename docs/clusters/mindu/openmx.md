# OpenMX

本页所有提交命令均支持将 `-h` 或 `--help` 作为第一个参数查看用法、参数及默认设置；查看帮助不会提交作业或生成文件。

```bash
myopenmx.sh input.dat
myopenmx.sh input.dat c 2
```

- 调用方式：`myopenmx.sh <input_file> [queue] [nodes]`。
- 默认 `small`、1 节点；支持 `s/small`、`c/community`、`h/highio`。
- 每节点 32 个 MPI 进程，每进程申请 1 核，`OMP_NUM_THREADS=1`。
- 重建基础 `PATH` 和 `LD_LIBRARY_PATH` 后，加载 `/home/liqh/soft/openmx/env.sh`。该文件须提供兼容的 `openmx` 和 `mpirun`；加载或命令检查失败立即退出。
- 脚本不设置 `MKL_NUM_THREADS`，不重新编译 OpenMX。
- 进入输入文件所在目录，运行 `mpirun -n <节点数×32> openmx <input_file>`。
- 标准输出覆盖同名 `.stdout`，标准错误覆盖同名 `.stderr`；OpenMX 自身的结果文件由输入设置决定。输入中的相对路径以输入目录为基准。
- 作业名为输入文件名去掉扩展名，Slurm 输出为提交目录的 `slurm-<jobid>.out`。
- 当前提交目录保留 `myopenmx-tmp`，再次调用会覆盖。可直接 `sbatch myopenmx-tmp` 重提，但不会追加 `Batch.log`。并发提交须使用不同提交目录。
- 成功提交后以文件锁追加输入目录的 `Batch.log`；失败不记录。作业返回 OpenMX/MPI 启动器的退出码。

部署更新后重新加载 `~/soft/slurm-batchs/env.sh`。本地模拟测试不验证目标集群 MPI 通信、OpenMX 安装或环境脚本内容。
