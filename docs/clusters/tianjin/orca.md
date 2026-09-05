# ORCA

提交时会在当前目录生成并保留完整的 `myorca-tmp`，可执行 `sbatch myorca-tmp` 重提相同作业；再次运行 `myorca.sh` 会覆盖该文件。

1. ORCA 版本为 6.1.1，安装目录为 `/data/home/liqh/soft/orca/6.1.1`
2. OpenMPI 版本为 4.1.8，安装目录为 `/data/home/liqh/soft/openmpi/4.1.8-gcc8.5`
3. 启动作业前覆盖重建 `PATH` 和 `LD_LIBRARY_PATH`，不继承登录环境的软件路径
4. 每个节点申请 48 个任务，支持多节点
5. 当前不固定 Slurm 分区，使用集群默认分区
6. 调用时必须提供一个存在的 ORCA 输入文件，节点数默认为 1
7. Slurm 作业名使用输入文件名去掉扩展名后的名称
8. ORCA 并行规模由输入文件中的 `%pal nprocs` 控制，脚本不修改输入文件
9. `%pal nprocs` 不应超过申请的总任务数，即节点数乘以 48
10. 使用 ORCA 主程序绝对路径直接启动，不额外使用 `mpirun`
11. 标准输出写入输入文件同名的 `.log`，标准错误写入 `orca.err`
12. 作业成功提交后追加输入目录中的 `Batch.log`

## 调用方式

```text
myorca.sh <input_file> [nodes]
```

示例：

```bash
myorca.sh water.inp
myorca.sh water.inp 2
```
