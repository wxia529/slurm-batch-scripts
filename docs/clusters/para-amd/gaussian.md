# Gaussian

提交时会在当前目录生成并保留 `myg16-tmp`；后续提交可以直接覆盖该文件。

1. 脚本名称为 `myg16.sh`
2. 调用时必须提供一个存在的 Gaussian 输入文件
3. 固定使用 `amd_256` 分区
4. 固定使用单节点 64 核心
5. Slurm 作业名称使用输入文件名去掉扩展名后的名称
6. 标准输出写入输入目录中同名的 `.log` 文件
7. 允许覆盖 `.log`，但文件已存在时必须用中文警告
8. 启动作业前覆盖重建 `PATH` 和 `LD_LIBRARY_PATH`，不在用户原环境后追加
9. `PATH` 固定为：

   ```text
   /opt/slurm/slurm/sbin:/opt/slurm/slurm/bin:/usr/local/bin:/usr/bin:/usr/local/sbin:/usr/sbin:/opt/ibutils/bin
   ```

10. `LD_LIBRARY_PATH` 固定为：

    ```text
    /opt/slurm/slurm/lib:/lib64:/usr/lib64:/usr/local/lib64
    ```

11. Gaussian 安装目录固定为 `/public3/home/sc71468/soft/Gaussian/A03`
12. 使用 `/public3/home/sc71468/soft/Gaussian/A03/g16/bsd/g16.profile` 加载环境，加载失败时立即退出
13. `GAUSS_SCRDIR` 固定为 `/public3/home/sc71468/soft/tmp/${SLURM_JOB_ID}`
14. 固定设置 `PGI_FASTMATH_CPU=sandybridge`
15. 作业正常结束或收到可处理的终止信号时，必须终止 Gaussian 并清理 `GAUSS_SCRDIR`
16. Slurm 成功接收作业后追加输入目录中的 `Batch.log`

## 调用方式

```text
myg16.sh <input.gjf>
```
