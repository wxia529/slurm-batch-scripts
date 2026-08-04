# Quantum ESPRESSO

各提交命令会在当前目录生成并保留包含完整 `#SBATCH` 参数的 `*-tmp` 作业脚本，例如 `mypw-tmp`、`myneb-tmp` 和 `myfd-tmp`。可执行 `sbatch mypw-tmp` 等命令重提相同作业；再次运行对应的 QE 提交命令会覆盖该文件。

1. 使用 QE 7.5，安装目录为 `/publicfs01/fs1-9/home/sc32041/soft/QE/qe-7.5`
2. 固定使用 `v3_64` 分区
3. 支持指定节点数，默认使用 1 个节点；节点数必须是正整数
4. 每个节点固定使用 24 个核心，MPI 进程总数等于节点数乘以 24
5. 作业启动前覆盖重建 `PATH` 和 `LD_LIBRARY_PATH`
6. 加载 `/publicfs01/fs1-9/home/sc32041/soft/toolchain/qe.env`
7. 固定设置 `OMP_NUM_THREADS=1`
8. 输入文件转换为绝对路径，作业在输入文件目录中运行
9. 标准输出写入输入文件同名的 `.log` 文件，错误输出写入模块专用的 `.err` 文件
10. Slurm 成功接收作业后追加输入目录中的 `Batch.log`

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

上述 QE 7.5 程序都通过 `-i`、`-in`、`-inp` 或 `-input` 读取命名输入文件，因此脚本统一使用 `-inp`。`neb.x` 的源码文档明确说明不能使用标准输入重定向（例如 `neb.x < neb.in`）；`myneb.sh` 会使用 `neb.x -inp <输入文件>`，并在输入目录中生成其需要的 `neb.dat` 和 `pw_*.in` 文件。

`fdvib` 不是 QE 7.5 上游源码中的程序；`myfd.sh` 按现有平台脚本约定调用 `fdvib -inp <输入文件>`，默认假定它已经位于 `qe.env` 加载后的 `PATH` 中。

## 调用方式

```text
mypw.sh <input_file> [nodes]
```

示例：

```text
mypw.sh scf.in
mypw.sh scf.in 2

mypp.sh pp.in
myph.sh ph.in 2
myneb.sh neb.in 4
myfd.sh fd.in 2
```
