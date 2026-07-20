# Gaussian

1. 必须提供一个存在的 Gaussian 输入文件
2. 支持三个分区：`small`、`community`、`highio`
3. 分区支持简写：`s`、`c`、`h`
4. 默认使用 `small` 分区
5. 固定使用单节点 32 核心
6. Slurm 作业名称使用输入文件名去掉扩展名后的名称
7. 使用 `g16` 运行计算
8. 标准输出写入与输入文件同名的 `.log` 文件
9. `.log` 文件放在输入文件所在目录
10. 允许覆盖 `.log`，但文件已存在时必须用中文警告
11. Gaussian 安装目录固定为 `/share/soft/gaussian/G16C01AVX`
12. 使用 `/share/soft/gaussian/G16C01AVX/g16/bsd/g16.profile` 加载运行环境，加载失败时立即退出
13. `GAUSS_SCRDIR` 固定为节点 `/tmp/${USER}/g16_${SLURM_JOB_ID}`
14. 作业正常结束后必须清理 `GAUSS_SCRDIR`
15. 作业收到可处理的强制终止信号时也必须终止 Gaussian 进程并清理 `GAUSS_SCRDIR`
16. Slurm 成功接收作业后，按照集群通用格式追加输入目录中的 `Batch.log`

## 调用方式

```text
myg16.sh <input.gjf> [queue]
```

示例：

```text
myg16.sh test.gjf
myg16.sh test.gjf community
myg16.sh test.gjf h
```
