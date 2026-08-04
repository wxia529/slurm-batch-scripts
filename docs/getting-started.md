# 快速开始

## 准备条件

部署和使用提交脚本前，请确认：

- 当前登录节点可以使用 `sbatch`
- 系统提供 Bash、`flock`、`mktemp` 和 `readlink`
- 当前账户能够读取对应软件安装目录
- 源码仓库与部署目录是两个不同概念

源码仓库可以克隆到任意位置，部署目录固定为：

```text
~/soft/slurm-batchs
```

## 获取源码

在 GitHub 项目页面点击 **Code**，复制仓库的 HTTPS 或 SSH 地址，然后执行：

```bash
git clone <复制的仓库地址>
cd slurm-batch-scripts
```

尖括号中的内容需要替换为 GitHub 页面提供的真实地址。

## 选择集群并部署

在 `mindu` 上执行：

```bash
./deploy.sh mindu
```

在 `para-amd` 上执行：

```bash
./deploy.sh para-amd
```

在 `para-e5` 上执行：

```bash
./deploy.sh para-e5
```

部署完成后加载提交命令：

```bash
source ~/soft/slurm-batchs/env.sh
```

## 提交示例

每次提交都会在运行命令的当前目录保留对应的 `*-tmp` Slurm 作业脚本。该文件包含完整的 `#SBATCH` 资源参数、软件环境和运行命令，可以直接执行 `sbatch <脚本名>-tmp` 重提相同的计算作业；再次运行原提交命令时会覆盖它。

Gaussian：

```bash
myg16.sh water.gjf
```

CP2K：

```bash
mycp2k.sh water.inp
```

VASP 需要先进入包含输入文件的任务目录：

```bash
cd calculations/water
myvasp.sh
```

ORCA：

```bash
myorca.sh water.inp
```

QE：

```bash
mypw.sh water.in
```

命令参数因集群而异，提交前请阅读对应的软件页面。
