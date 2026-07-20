# VASP

## 基本要求

1. 脚本名称为 `myvasp.sh`
2. 脚本在 VASP 任务目录中运行，并检查 `INCAR`、`POSCAR`、`POTCAR`，不强制检查 `KPOINTS`
3. 支持三个分区：`small`、`community`、`highio`
4. 分区支持简写：`s`、`c`、`h`
5. 默认使用 `small` 分区
6. 支持指定节点数，默认使用 1 个节点；节点数必须是正整数
7. 每个节点固定使用 32 个核心
8. MPI 进程总数等于节点数乘以 32
9. Slurm 作业名称使用当前任务目录名称

## VASP 版本和运行类型

VASP 版本固定为 `6.5.1-vtst`。第三个参数只用于选择运行类型，默认值为 `std`。

| 参数 | 运行程序 |
| --- | --- |
| 空、`std` | `vasp_std` |
| `gam` | `vasp_gam` |
| `ncl` | `vasp_ncl` |

不在表中的运行类型必须拒绝提交。

## 运行环境

1. VASP 程序目录固定为 `/home/liqh/soft/vasp/6.5.1-vtst/bin`
2. 启动作业前必须覆盖原有的 `PATH` 和 `LD_LIBRARY_PATH`，不能在原环境后追加
3. `PATH` 固定重建为：

   ```text
   /slurm/bin:/slurm/sbin:/bin:/usr/bin:/usr/local/bin:/sbin:/usr/sbin:/usr/local/sbin:/home/liqh/soft/vaspkit.1.5.1/bin:/home/liqh/soft/vasp/6.5.1-vtst/bin
   ```

4. `LD_LIBRARY_PATH` 固定重建为：

   ```text
   /slurm/lib:/lib64:/usr/lib64:/usr/local/lib64
   ```

5. 完成上述环境重建后，再加载固定的 Toolchain 环境文件 `/home/liqh/soft/toolchain/vasp651.env`
6. 固定设置 `I_MPI_ADJUST_REDUCE=3`
7. 使用 `mpirun -n <MPI 进程总数> <运行程序>` 启动作业

## 输出和提交记录

1. 标准输出追加写入任务目录中的 `log`，不覆盖已有内容
2. 标准错误写入任务目录中的 `vasp.err`
3. Slurm 成功接收作业后，按照集群通用格式追加任务目录中的 `Batch.log`
4. `Batch.log` 中的任务目录使用当前 VASP 任务目录的绝对路径
5. VASP 提交记录使用 `input=INCAR,POSCAR,POTCAR` 和 `output=log`

## 调用方式

```text
myvasp.sh [queue] [nodes] [type]
```

示例：

```text
myvasp.sh
myvasp.sh community
myvasp.sh h 2
myvasp.sh small 2 gam
myvasp.sh highio 4 ncl
```
