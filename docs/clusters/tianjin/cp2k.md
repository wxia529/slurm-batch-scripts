# CP2K

提交时会在当前目录生成并保留完整的 `mycp2k-tmp`，可执行 `sbatch mycp2k-tmp` 重提相同作业；再次运行 `mycp2k.sh` 会覆盖该文件。

1. CP2K 版本为 2026.2，安装目录为 `/data/home/liqh/soft/cp2k/2026.2`
2. 将 `/data/home/liqh/soft/cp2k/2026.2/install/bin` 写入 `PATH`，运行时使用命令名 `cp2k.psmp`
3. 固定加载 `/data/home/liqh/soft/cp2k/2026.2/install/cp2k_env`
4. 随后加载 `/data/home/liqh/soft/ucx/1.22-gcc8.5/env.sh`
5. 加载环境前覆盖重建 `PATH` 和 `LD_LIBRARY_PATH`
6. 每个节点使用 48 个 MPI 进程，支持多节点
7. 固定使用 `p1` 分区
8. 固定设置 `OMPI_MCA_pml=ucx`、`OMPI_MCA_btl=^openib` 和 `OMP_NUM_THREADS=1`
9. 输入文件转换为绝对路径，作业在输入文件目录中运行
10. Slurm 作业名使用输入文件名去掉扩展名后的名称
11. 标准输出写入输入文件同名的 `.out`，标准错误写入 `cp2k.err`
12. 作业成功提交后追加输入目录中的 `Batch.log`

## 调用方式

```text
mycp2k.sh <input_file> [nodes]
```

示例：

```bash
mycp2k.sh water.inp
mycp2k.sh water.inp 2
```
