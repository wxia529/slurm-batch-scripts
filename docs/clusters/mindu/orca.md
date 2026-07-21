# ORCA

## 基本要求

1. 脚本名称为 `myorca.sh`
2. 调用时必须提供一个存在的 ORCA 输入文件
3. 支持三个分区：`small`、`community`、`highio`
4. 分区支持简写：`s`、`c`、`h`，默认使用 `small`
5. 支持指定节点数，默认使用 1 个节点；节点数必须是正整数
6. 每个节点固定申请 32 个任务，总任务数等于节点数乘以 32
7. Slurm 作业名称使用输入文件名去掉扩展名后的名称
8. ORCA 并行设置由输入文件控制，提交脚本不检查也不修改 `%pal`

## 软件与运行环境

1. ORCA 版本固定为 `6.1.1`
2. ORCA 安装目录固定为：

    ```text
    /home/liqh/soft/orca/orca_6_1_1_linux_x86-64_shared_openmpi418_nodmrg
    ```

3. OpenMPI 环境固定为：

    ```text
    /home/liqh/soft/openmpi/4.1.6-gcc13.4/env.sh
    ```

4. 加载软件环境前必须覆盖原有的 `PATH` 和 `LD_LIBRARY_PATH`，不能在用户原环境后追加
5. `PATH` 固定重建为：

    ```text
    /slurm/bin:/slurm/sbin:/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin:/home/liqh/soft/orca/orca_6_1_1_linux_x86-64_shared_openmpi418_nodmrg
    ```

6. `LD_LIBRARY_PATH` 固定重建为：

    ```text
    /slurm/lib:/lib64:/usr/lib64:/usr/local/lib64:/home/liqh/soft/orca/orca_6_1_1_linux_x86-64_shared_openmpi418_nodmrg
    ```

7. 完成路径重建后加载 `/home/liqh/soft/openmpi/4.1.6-gcc13.4/env.sh`，加载失败时立即退出
8. 使用 ORCA 完整路径直接启动，不通过 `mpirun`

## 输出和提交记录

1. 标准输出写入输入目录中与输入文件同名的 `.log` 文件
2. 标准错误写入输入目录中的 `orca.err`
3. Slurm 成功接收作业后，按照集群通用格式追加输入目录中的 `Batch.log`
4. 提交失败时不得写入 `Batch.log`
5. 多个任务同时提交时，必须通过文件锁保证每条记录完整

## 调用方式

```text
myorca.sh <input_file> [queue] [nodes]
```

示例：

```text
myorca.sh test.inp
myorca.sh test.inp community
myorca.sh test.inp h 2
```
