# Quantum ESPRESSO

各提交命令会在当前目录生成并保留包含完整 `#SBATCH` 参数的 `*-tmp` 作业脚本，例如 `mypw-tmp`、`myneb-tmp` 和 `myfd-tmp`。可执行 `sbatch mypw-tmp` 等命令重提相同作业；再次运行对应的 QE 提交命令会覆盖该文件。

1. 使用 QE 7.6，安装目录为 `/data/home/liqh/soft/QE/qe-7.6`
2. 固定加载 `/data/home/liqh/soft/QE/env.sh`
3. 每个节点固定使用 48 个 MPI 进程，支持多节点
4. 当前不固定 Slurm 分区，使用集群默认分区
5. 输入文件转换为绝对路径，作业在输入文件目录中运行
6. 标准输出写入输入文件同名的 `.log`，标准错误写入模块专用的 `.err`
7. 固定设置 `OMP_NUM_THREADS=1`
8. 所有模块使用命名输入参数：`程序 -inp <输入文件>`
9. 作业成功提交后追加输入目录中的 `Batch.log`

## 已提供的模块

| 脚本 | 程序 | 调用方式 |
| --- | --- | --- |
| `mypw.sh` | `pw.x` | `mypw.sh <input_file> [nodes]` |
| `mypp.sh` | `pp.x` | `mypp.sh <input_file> [nodes]` |
| `mybands.sh` | `bands.x` | `mybands.sh <input_file> [nodes]` |
| `mydos.sh` | `dos.x` | `mydos.sh <input_file> [nodes]` |
| `myprojwfc.sh` | `projwfc.x` | `myprojwfc.sh <input_file> [nodes]` |
| `myph.sh` | `ph.x` | `myph.sh <input_file> [nodes]` |
| `myq2r.sh` | `q2r.x` | `myq2r.sh <input_file> [nodes]` |
| `mymatdyn.sh` | `matdyn.x` | `mymatdyn.sh <input_file> [nodes]` |
| `myneb.sh` | `neb.x` | `myneb.sh <input_file> [nodes]` |
| `myfd.sh` | 自定义 `fdvib` | `myfd.sh <input_file> [nodes]` |

`fdvib` 按现有平台约定使用 `fdvib -inp <输入文件>`。作业启动时会检查程序是否已由 QE 安装目录或环境脚本加入 `PATH`。

## 示例

```bash
mypw.sh scf.in
mypw.sh scf.in 2
myph.sh phonon.in 2
myneb.sh neb.in 4
myfd.sh fd.in 2
```
