# Quantum ESPRESSO

各提交命令会在当前目录生成并保留对应的 `*-tmp` 作业脚本，例如 `mypw-tmp`、`myneb-tmp` 和 `myfd-tmp`；后续同模块提交可以直接覆盖该文件。

1. 使用 QE 7.5，安装目录为 `/home/liqh/soft/QE/qe-7.5`
2. 固定从 `/home/liqh/soft/QE/env.sh` 加载 QE 环境
3. 支持三个分区：`small`、`community`、`highio`，默认使用 `small`
4. 分区支持简写：`s`、`c`、`h`
5. 支持指定节点数，默认使用 1 个节点；节点数必须是正整数
6. 每个节点固定使用 32 个核心，MPI 进程总数等于节点数乘以 32
7. Slurm 作业名称使用输入文件名去掉扩展名后的名称
8. 标准输出写入输入文件同名的 `.log` 文件
9. 错误输出写入模块专用的 `.err` 文件
10. 固定设置 `OMP_NUM_THREADS=1`
11. 普通 QE 模块按照参考脚本使用标准输入重定向：`程序.x < 输入文件`
12. `neb.x` 例外，使用 `neb.x -inp <输入文件>`；QE 源码文档明确说明 NEB 不能使用标准输入重定向
13. Slurm 成功接收作业后追加输入目录中的 `Batch.log`

## 已提供的模块

| 脚本 | 程序 | 调用方式 |
| --- | --- | --- |
| `mypw.sh` | `pw.x` | `mypw.sh <input_file> [queue] [nodes]` |
| `mypp.sh` | `pp.x` | `mypp.sh <input_file> [queue] [nodes]` |
| `mybands.sh` | `bands.x` | `mybands.sh <input_file> [queue] [nodes]` |
| `mydos.sh` | `dos.x` | `mydos.sh <input_file> [queue] [nodes]` |
| `myprojwfc.sh` | `projwfc.x` | `myprojwfc.sh <input_file> [queue] [nodes]` |
| `myph.sh` | `ph.x` | `myph.sh <input_file> [queue] [nodes]` |
| `myq2r.sh` | `q2r.x` | `myq2r.sh <input_file> [queue] [nodes]` |
| `mymatdyn.sh` | `matdyn.x` | `mymatdyn.sh <input_file> [queue] [nodes]` |
| `myneb.sh` | `neb.x` | `myneb.sh <input_file> [queue] [nodes]` |
| `myfd.sh` | 自定义 `fdvib` | `myfd.sh <input_file> [queue] [nodes]` |

`fdvib` 使用现有平台脚本约定的 `fdvib -inp <输入文件>`，并通过同一套 QE 环境加载和资源配置运行。

## 示例

```bash
mypw.sh scf.in
mypw.sh scf.in community
mypw.sh scf.in h 2
myph.sh phonon.in highio 2
myneb.sh neb.in small 4
```
