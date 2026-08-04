# VASP

提交时会在当前目录生成并保留完整的 `myvasp-tmp`，可执行 `sbatch myvasp-tmp` 重提相同作业；再次运行 `myvasp.sh` 会覆盖该文件。

1. 脚本名称为 `myvasp.sh`
2. 脚本在 VASP 任务目录中运行，并检查 `INCAR` 和 `POTCAR`
3. 普通任务要求顶层存在 `POSCAR`；VTST/NEB 任务允许顶层没有 `POSCAR`，但必须有至少两个纯数字镜像目录（如 `00`、`01`），且每个镜像目录中都存在 `POSCAR`
4. 固定使用 `v3_64` 分区
5. 支持指定节点数，默认使用 1 个节点；节点数必须是正整数
6. 每个节点固定使用 24 个核心
7. MPI 进程总数等于节点数乘以 24
8. VASP 版本固定为 `6.5.1-vtst`
9. 支持 `std`、`gam`、`ncl`，默认使用 `std`
10. Slurm 作业名称使用当前任务目录名称
11. 标准输出追加写入任务目录中的 `log`
12. 标准错误写入任务目录中的 `vasp.err`
13. 启动作业前覆盖重建 `PATH` 和 `LD_LIBRARY_PATH`
14. 加载 `/publicfs01/fs1-9/home/sc32041/soft/toolchain/vasp651.env`
15. 固定设置 `OMP_NUM_THREADS=1`
16. 使用 `mpirun -n <节点数乘以 24> vasp_<运行类型>` 启动作业
17. Slurm 成功接收作业后追加任务目录中的 `Batch.log`；普通任务和 VTST/NEB 任务分别记录实际输入结构

## 调用方式

```text
myvasp.sh [nodes] [type]
```

示例：

```text
myvasp.sh
myvasp.sh 2
myvasp.sh 2 gam
myvasp.sh 1 ncl
```
