# VASP

提交时会在当前目录生成并保留完整的 `myvasp-tmp`，可执行 `sbatch myvasp-tmp` 重提相同作业；再次运行 `myvasp.sh` 会覆盖该文件。

1. VASP 版本为 6.5.1 VTST，程序目录为 `/data/home/liqh/soft/vasp/vasp.6.5.1/bin`
2. 固定加载 `/data/home/liqh/soft/vasp/env.sh`
3. 每个节点固定使用 48 个核心，支持多节点 MPI
4. 固定使用 `p1` 分区
5. 支持 `std`、`gam` 和 `ncl`，默认使用 `std`
6. MPI 进程总数等于节点数乘以 48，固定设置 `OMP_NUM_THREADS=1`
7. 脚本在当前 VASP 任务目录运行，并检查 `INCAR` 和 `POTCAR`
8. 普通任务要求顶层存在 `POSCAR`；VTST/NEB 任务可以改用至少两个纯数字镜像目录，并要求每个目录存在 `POSCAR`
9. Slurm 作业名使用任务目录名称
10. 标准输出追加到 `log`，标准错误写入 `vasp.err`
11. 作业成功提交后追加任务目录中的 `Batch.log`

## 调用方式

```text
myvasp.sh [nodes] [type]
```

示例：

```bash
myvasp.sh
myvasp.sh 2
myvasp.sh 2 gam
myvasp.sh 1 ncl
```
