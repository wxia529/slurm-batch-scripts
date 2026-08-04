# CP2K

提交时会在当前目录生成并保留 `mycp2k-tmp`；后续提交可以直接覆盖该文件。

1. 脚本名称为 `mycp2k.sh`
2. 调用时必须提供一个存在的 CP2K 输入文件
3. 固定使用 `amd_256` 分区
4. 支持指定节点数，默认使用 1 个节点；节点数必须是正整数
5. 每个节点固定使用 64 个核心
6. MPI 进程总数等于节点数乘以 64
7. Slurm 作业名称使用输入文件名去掉扩展名后的名称
8. 标准输出写入输入目录中同名的 `.out` 文件
9. 标准错误写入输入目录中的 `cp2k.err`
10. 启动作业前覆盖重建 `PATH` 和 `LD_LIBRARY_PATH`，不在用户原环境后追加
11. `PATH` 固定为：

    ```text
    /opt/slurm/slurm/sbin:/opt/slurm/slurm/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/opt/ibutils/bin:/public3/home/sc71468/soft/cp2k/latest/exe/bin:/public3/home/sc71468/soft/Multiwfn:/public3/home/sc71468/soft/shs/cp2k
    ```

12. `LD_LIBRARY_PATH` 固定为：

    ```text
    /opt/slurm/slurm/lib:/lib64:/usr/lib64:/usr/local/lib64:/public3/home/sc71468/soft/cp2k/latest/exe/lib64
    ```

13. 完成路径重建后依次加载：
    1. `/public3/home/sc71468/soft/cp2k/latest/install/cp2k_env`
    2. `/public3/home/sc71468/soft/ucx/1.21-gcc-13.2/env.sh`
14. 固定设置 `OMP_NUM_THREADS=1`
15. 使用 `mpirun -n <节点数乘以 64> cp2k.psmp <输入文件>` 启动作业
16. Slurm 成功接收作业后追加输入目录中的 `Batch.log`

## 调用方式

```text
mycp2k.sh <input_file> [nodes]
```

示例：

```text
mycp2k.sh test.inp
mycp2k.sh test.inp 2
```
