# CP2K

1. 脚本名称为 `mycp2k.sh`
2. 调用时必须提供一个存在的 CP2K 输入文件
3. 固定使用 `v3_64` 分区
4. 支持指定节点数，默认使用 1 个节点；节点数必须是正整数
5. 每个节点固定使用 24 个核心
6. MPI 进程总数等于节点数乘以 24
7. Slurm 作业名称使用输入文件名去掉扩展名后的名称
8. 标准输出写入输入目录中同名的 `.out` 文件
9. 标准错误写入输入目录中的 `cp2k.err`
10. 启动作业前覆盖重建 `PATH` 和 `LD_LIBRARY_PATH`
11. 加载 `/publicfs01/fs1-9/home/sc32041/soft/cp2k/latest/install/cp2k_env`
12. 随后加载 `/publicfs01/fs1-9/home/sc32041/soft/ucx/1.21-gcc-14.3/env.sh`
13. 固定设置 `OMP_NUM_THREADS=1`
14. 使用 `mpirun -n <节点数乘以 24> cp2k.psmp <输入文件>` 启动作业
15. Slurm 成功接收作业后追加输入目录中的 `Batch.log`

## 调用方式

```text
mycp2k.sh <input_file> [nodes]
```

示例：

```text
mycp2k.sh test.inp
mycp2k.sh test.inp 2
```
