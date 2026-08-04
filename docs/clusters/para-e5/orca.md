# ORCA

提交时会在当前目录生成并保留完整的 `myorca-tmp`，可执行 `sbatch myorca-tmp` 重提相同作业；再次运行 `myorca.sh` 会覆盖该文件。

1. 脚本名称为 `myorca.sh`
2. 调用时必须提供一个存在的 ORCA 输入文件
3. 固定使用 `v3_64` 分区
4. 支持指定节点数，默认使用 1 个节点；节点数必须是正整数
5. 每个节点固定申请 24 个任务，总任务数等于节点数乘以 24
6. Slurm 作业名称使用输入文件名去掉扩展名后的名称
7. ORCA 并行设置由输入文件中的 `%pal` 控制，提交脚本不检查也不修改 `%pal`
8. 标准输出写入输入目录中同名的 `.log` 文件
9. 标准错误写入输入目录中的 `orca.err`
10. 启动作业前覆盖重建 `PATH` 和 `LD_LIBRARY_PATH`
11. ORCA 安装目录为 `/publicfs01/fs1-9/home/sc32041/soft/orca/6.1.1`
12. OpenMPI 安装目录为 `/publicfs01/fs1-9/home/sc32041/soft/openmpi/4.1.6-gcc14.3`
13. 设置 `XTBEXE=/publicfs01/fs1-9/home/sc32041/soft/xtb-dist/bin/xtb`
14. 使用 ORCA 完整路径直接启动，不额外通过 `mpirun` 启动
15. Slurm 成功接收作业后追加输入目录中的 `Batch.log`

ORCA 的 `%pal nprocs` 不应超过脚本申请的节点总核心数（节点数乘以 24）。

## 调用方式

```text
myorca.sh <input_file> [nodes]
```

示例：

```text
myorca.sh test.inp
myorca.sh test.inp 2
```
