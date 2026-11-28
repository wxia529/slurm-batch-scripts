# ABINIT

本页提交命令支持将 `-h` 或 `--help` 作为第一个参数查看用法、参数及默认设置；查看帮助不会提交作业或生成文件。

提交时会在当前目录生成并保留完整的 `myabinit-tmp`，可执行 `sbatch myabinit-tmp` 重提相同作业；再次运行 `myabinit.sh` 会覆盖该文件。

1. 使用 ABINIT 10.8.3，安装目录为 `/home/liqh/soft/ABINIT/abinit-10.8.3-oneapi2022-avx512`
2. 使用 Intel oneAPI 2022 classic 工具链构建，并启用 AVX-512 优化
3. 固定从 `/home/liqh/soft/ABINIT/env-10.8.3-oneapi2022-avx512.sh` 加载 ABINIT、Intel MPI 和依赖库环境
4. 必须提供一个存在的 ABINIT 输入文件；建议使用 `.abi` 扩展名
5. 输入文件基本名只能包含英文字母、数字、点、下划线和连字符
6. 支持三个分区：`small`、`community`、`highio`
7. 分区支持简写：`s`、`c`、`h`；默认使用 `small`
8. 支持指定节点数，默认使用 1 个节点；节点数必须是正整数
9. 每个节点固定使用 32 个 MPI 进程，进程总数等于节点数乘以 32
10. 固定设置 `OMP_NUM_THREADS=1`
11. Slurm 作业名称使用输入文件名去掉扩展名后的名称
12. 使用 `mpirun -n <MPI 进程总数> abinit <输入文件>` 启动作业
13. ABINIT 标准输出写入与输入文件同名的 `.log` 文件，标准错误写入 `abinit.err`
14. ABINIT 自身生成的 `.abo`、NetCDF 和波函数等结果文件写入输入文件所在目录
15. Slurm 成功接收作业后，按照集群通用格式追加输入目录中的 `Batch.log`

## 调用方式

```text
myabinit.sh <input_file> [queue] [nodes]
```

示例：

```text
myabinit.sh silicon.abi
myabinit.sh silicon.abi community
myabinit.sh silicon.abi h 2
```
