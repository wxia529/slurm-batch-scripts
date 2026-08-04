# CP2K

提交时会在当前目录生成并保留 `mycp2k-tmp`；后续提交可以直接覆盖该文件。

1. 必须提供一个存在的 CP2K 输入文件
2. 支持三个分区：`small`、`community`、`highio`
3. 分区支持简写：`s`、`c`、`h`
4. 默认使用 `small` 分区
5. 支持指定节点数，默认使用 1 个节点；节点数必须是正整数
6. 每个节点固定使用 32 个核心
7. MPI 进程总数等于节点数乘以 32
8. 固定设置 `OMP_NUM_THREADS=1`
9. Slurm 作业名称使用输入文件名去掉扩展名后的名称
10. 使用 `cp2k.psmp` 运行计算
11. 标准输出写入与输入文件同名的 `.out` 文件
12. 标准错误写入 `cp2k.err`
13. 加载 CP2K 环境前必须覆盖原有的 `PATH` 和 `LD_LIBRARY_PATH`，不能在用户原环境后追加
14. `PATH` 固定重建为：

    ```text
    /slurm/bin:/slurm/sbin:/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin:/home/liqh/soft/cp2k/latest/exe/bin
    ```

15. `LD_LIBRARY_PATH` 固定重建为：

    ```text
    /slurm/lib:/lib64:/usr/lib64:/usr/local/lib64:/home/liqh/soft/cp2k/latest/exe/lib64
    ```

16. 完成上述环境重建后，按照以下顺序加载环境文件：
    1. CP2K：`/home/liqh/soft/cp2k/latest/install/cp2k_env`
    2. UCX：`/home/liqh/soft/ucx/1.20.1-gcc13.4/env.sh`
17. 固定设置 `OMPI_MCA_btl="^openib"`
18. 使用 `mpirun -n <MPI 进程总数> cp2k.psmp <输入文件>` 启动作业
19. Slurm 成功接收作业后，按照集群通用格式追加输入目录中的 `Batch.log`

## 调用方式

```text
mycp2k.sh <input_file> [queue] [nodes]
```

示例：

```text
mycp2k.sh test.inp
mycp2k.sh test.inp community
mycp2k.sh test.inp h 2
```
