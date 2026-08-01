# 参与维护

## 基本原则

1. `docs/` 是唯一文档来源
2. 集群公共配置写在 `docs/clusters/<集群>/index.md`
3. 软件配置写在同一集群目录下的软件页面
4. 脚本行为必须与文档一致
5. 新增软件时必须同时更新 MkDocs 导航和部署清单
6. 部署脚本不得删除或修改用户文件
7. Commit 标题和正文必须使用英文，并采用 Conventional Commits 格式

## GitHub 协作流程

```mermaid
flowchart LR
    A[同步主分支] --> B[创建功能分支]
    B --> C[修改脚本和 docs]
    C --> D[执行检查]
    D --> E[提交并推送]
    E --> F[创建 Pull Request]
    F --> G[组内审核]
    G --> H[合并 main]
    H --> I[重新部署]
```

创建分支：

```bash
git switch main
git pull --ff-only
git switch -c feature/update-cp2k
```

执行基础检查：

```bash
bash -n deploy.sh env.sh
bash -n mindu/cp2k/mycp2k.sh
bash -n para-amd/cp2k/mycp2k.sh
bash -n para-e5/vasp/myvasp.sh
bash -n para-e5/cp2k/mycp2k.sh
bash -n para-e5/orca/myorca.sh
bash -n para-e5/qe/mypw.sh
find para-e5/qe -type f -name '*.sh' -print0 | xargs -0 -r bash -n
mkdocs build --strict
git diff --check
```

提交修改：

```bash
git add .
git commit -m "feat: update CP2K submission script"
git push -u origin feature/update-cp2k
```

Pull Request 应说明：

- 修改了哪个集群和软件
- 修改原因和行为变化
- 是否改变参数或默认值
- 已执行的测试
- 用户是否需要重新部署
