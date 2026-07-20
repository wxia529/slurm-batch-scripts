# VASP

1. 脚本名称为 `myvasp.sh`
2. 脚本在 VASP 任务目录中运行，并检查 `INCAR` 和 `POTCAR`，不强制检查 `KPOINTS`
3. 普通任务要求顶层存在 `POSCAR`；VTST/NEB 任务允许顶层没有 `POSCAR`，但必须有至少两个纯数字镜像目录（如 `00`、`01`），且每个镜像目录中都存在 `POSCAR`
4. 固定使用 `amd_256` 分区
5. 支持指定节点数，默认使用 1 个节点；节点数必须是正整数
6. 每个节点固定使用 64 个核心
7. MPI 进程总数等于节点数乘以 64
8. VASP 版本固定为 `6.5.1-vtst`
9. 支持 `std`、`gam`、`ncl`，默认使用 `std`
10. Slurm 作业名称使用当前任务目录名称
11. 标准输出追加写入任务目录中的 `log`
12. 标准错误写入任务目录中的 `vasp.err`
13. 启动作业前覆盖重建 `PATH` 和 `LD_LIBRARY_PATH`，不在用户原环境后追加
14. `PATH` 固定为：

    ```text
    /public3/home/sc71468/soft/vasp/6.5.1-vtst/bin:/opt/slurm/slurm/sbin:/opt/slurm/slurm/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/opt/ibutils/bin
    ```

15. `LD_LIBRARY_PATH` 固定为：

    ```text
    /opt/slurm/slurm/lib:/lib64:/usr/lib64:/usr/local/lib64
    ```

16. 路径重建后加载 `/public3/home/sc71468/soft/toolchain/vasp651.env`
17. 固定设置 `OMP_NUM_THREADS=1`
18. 使用 `mpirun -n <节点数乘以 64> vasp_<运行类型>` 启动作业
19. Slurm 成功接收作业后追加任务目录中的 `Batch.log`；普通任务和 VTST/NEB 任务分别记录实际输入结构

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
