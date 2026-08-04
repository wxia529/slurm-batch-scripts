# ORCA

提交时会在当前目录生成并保留完整的 `myorca-tmp`，可执行 `sbatch myorca-tmp` 重提相同作业；再次运行 `myorca.sh` 会覆盖该文件。

1. 脚本名称为 `myorca.sh`
2. 调用时必须提供一个存在的 ORCA 输入文件
3. 固定使用 `amd_256` 分区
4. 支持指定节点数，默认使用 1 个节点；节点数必须是正整数
5. 每个节点固定申请 64 个任务，总任务数等于节点数乘以 64
6. Slurm 作业名称使用输入文件名去掉扩展名后的名称
7. ORCA 并行设置由输入文件控制，提交脚本不检查也不修改 `%pal`
8. 标准输出写入输入目录中同名的 `.log` 文件
9. 标准错误写入输入目录中的 `orca.err`
10. 启动作业前覆盖重建 `PATH` 和 `LD_LIBRARY_PATH`，不在用户原环境后追加
11. `PATH` 固定为：

    ```text
    /opt/slurm/slurm/sbin:/opt/slurm/slurm/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/opt/ibutils/bin:/public3/home/sc71468/soft/orca/orca_6_1_1_linux_x86-64_shared_openmpi418_nodmrg:/public3/home/sc71468/soft/openmpi/4.1.6/bin
    ```

12. `LD_LIBRARY_PATH` 固定为：

    ```text
    /opt/slurm/slurm/lib:/lib64:/usr/lib64:/usr/local/lib64:/public3/home/sc71468/soft/orca/orca_6_1_1_linux_x86-64_shared_openmpi418_nodmrg:/public3/home/sc71468/soft/openmpi/4.1.6/lib
    ```

13. 固定设置 `XTBEXE=/public3/home/sc71468/soft/xtb-dist/bin/xtb`
14. 使用 ORCA 完整路径直接启动，不通过 `mpirun`
15. Slurm 成功接收作业后追加输入目录中的 `Batch.log`

## 调用方式

```text
myorca.sh <input_file> [nodes]
```

示例：

```text
myorca.sh test.inp
myorca.sh test.inp 2
```
