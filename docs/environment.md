# 环境加载

本项目包含两层环境：登录环境中的提交命令，以及计算作业内部的软件运行环境。两者不能混为一谈。

## 加载提交命令

部署后执行：

```bash
source ~/soft/slurm-batchs/env.sh
```

`env.sh` 会扫描 `~/soft/slurm-batchs` 的一级子目录，将包含可执行文件的目录加入 `PATH`。重复加载不会重复添加路径。

加载后可以直接运行：

```bash
myg16.sh
mycp2k.sh
myvasp.sh
myorca.sh
```

若希望每次登录自动加载，可以由用户自行在 `~/.bashrc` 中加入：

```bash
source "$HOME/soft/slurm-batchs/env.sh"
```

部署脚本不会自动修改用户的 Shell 配置。

## 软件运行环境

提交命令不会在登录节点加载 Gaussian、CP2K、VASP 或 ORCA 环境。软件环境只在计算节点执行临时 Slurm 脚本时加载。

作业脚本采用以下策略：

1. 覆盖并重建 `PATH`
2. 覆盖并重建 `LD_LIBRARY_PATH`
3. 按集群配置加载 Toolchain、UCX 或软件 Profile
4. 设置软件所需的其他变量
5. 启动计算程序

这种方式可以降低用户登录环境、Environment Modules 或其他 MPI 配置对计算任务的干扰。它只重建关键路径变量，不使用 `sbatch --export=NIL` 清除全部环境。
