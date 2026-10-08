# Gaussian

## 调用方式

```bash
myg16.sh water.gjf
myg16.sh water.gjf 16
```

- 使用 Gaussian 16 A03，安装根目录为 `/data/app/gaussian/G16-A03`。
- 固定 `p1` 分区、单节点、一个 task，默认申请 40 核；第二个参数可指定 1–40 核。
- 输入文件必须显式设置 `%NProcShared`，数值不能超过申请核心数；所有 Link1 段中出现的设置都会检查。较少的输入核心数允许提交，但可能闲置申请的 CPU。
- 不支持 `%CPU`、`%NProc`、`%LindaWorkers` 和 `%NProcLinda`，使用 `%NProcShared` 配置单节点并行。
- 不修改输入文件；`%Mem` 由用户设置。脚本不显式申请 Slurm 内存，使用分区默认值，请确保 `%Mem` 适合实际分配的内存。
- 从 `${g16root}/g16/bsd/g16.profile` 加载环境，检查环境文件和可执行文件，失败时退出。
- 在输入文件所在目录直接运行安装目录中的 `g16`，不使用 MPI 启动器；作业名为输入文件名去掉扩展名。
- 输出写入同名 `.log`，已有日志会中文警告后覆盖；checkpoint 等文件按输入设置生成。Slurm 输出为提交目录中的 `slurm-<jobid>.out`。
- 临时文件使用计算节点 `/tmp/${USER}/g16_${SLURM_JOB_ID}.XXXXXX`，通过 `mktemp` 创建独立目录。请先确认计算节点本地磁盘空间充足。
- 正常退出、计算失败及可处理的 TERM/INT/HUP 信号都会清理本次 scratch；SIGKILL 或节点故障无法保证清理。
- 当前目录保留完整 `myg16-tmp`，再次调用会覆盖它；可用 `sbatch myg16-tmp` 重提，但直接重提不会追加 `Batch.log`。并发调用请使用不同提交目录，避免争用此文件。
- 成功提交后，用文件锁向输入目录的 `Batch.log` 追加 Job ID 和资源记录；提交失败不记录。

输入头部示例：

```text
%chk=water.chk
%NProcShared=16
%Mem=8GB
```

两边现场需确认环境文件权限、分区资源及计算节点 `/tmp` 容量；本地模拟测试不验证集群实际运行环境。
