#!/usr/bin/env python3
# 管理 Swift Package 的版本、SDK 子树快照、来源、审批与 CI 发版。
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
CORE_VERSION_PATTERN = r"(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*)){2}"
DEV_VERSION_PATTERN = rf"{CORE_VERSION_PATTERN}-dev\.(?:0|[1-9][0-9]*)"
REVIEWERS = {"hzh137940556"}


# 保持渠道、SemVer、来源分支和审批环境的一致映射。
@dataclass(frozen=True)
class Release:
    channel: str
    version: str

    # 在 Git、GitHub 或构建操作之前拒绝不合法的渠道和版本。
    def __post_init__(self) -> None:
        if self.channel not in {"dev", "release"}:
            raise ValueError("SDK_CHANNEL 必须为 dev 或 release")
        pattern = DEV_VERSION_PATTERN if self.channel == "dev" else CORE_VERSION_PATTERN
        if not re.fullmatch(pattern, self.version):
            example = "0.1.0-dev.1" if self.channel == "dev" else "0.1.0"
            raise ValueError(f"{self.channel} 版本号必须为 {example} 形式，不接受前导零或其他后缀")

    # 将预发布限制在 develop，稳定发布限制在 main。
    @property
    def branch(self) -> str:
        return "develop" if self.channel == "dev" else "main"

    # 分离测试与正式发布的人工审批环境。
    @property
    def environment(self) -> str:
        return f"ios-sdk-{self.channel}"

    # SwiftPM 直接把严格 SemVer Tag 作为可解析的软件包版本。
    @property
    def tag(self) -> str:
        return self.version


# 在本仓库执行 Git，不通过 shell 拼接输入。
def git(*args: str) -> str:
    return subprocess.check_output(["git", *args], cwd=ROOT, text=True).strip()


# 刷新允许的来源分支和可选 Tag，避免使用陈旧引用判断发布资格。
def fetch_source(release: Release, *, tags: bool = False) -> None:
    command = ["git", "fetch", "origin"]
    if tags:
        command.append("--tags")
    command.append(f"refs/heads/{release.branch}:refs/remotes/origin/{release.branch}")
    subprocess.run(command, cwd=ROOT, check=True)


# 验证待发布提交属于对应远端分支历史。
def check_source(release: Release, sha: str) -> None:
    result = subprocess.run(
        ["git", "merge-base", "--is-ancestor", sha, f"origin/{release.branch}"],
        cwd=ROOT,
        check=False,
    )
    if result.returncode != 0:
        raise ValueError(f"提交 {sha} 不属于 origin/{release.branch}，禁止发布")


# 返回已存在 Tag 的提交；Tag 不存在时返回 None。
def existing_tag_sha(release: Release) -> str | None:
    result = subprocess.run(
        ["git", "rev-parse", "--verify", f"refs/tags/{release.tag}^{{commit}}"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        return result.stdout.strip()
    return None


# 返回 source commit 中可发布 SDK 子树的 Git tree。
def sdk_tree_sha(source_sha: str) -> str:
    return git("rev-parse", f"{source_sha}:SDK")


# 校验既有 Tag 是否仍精确对应同一 source commit 和 SDK 子树。
def package_snapshot_matches(release: Release, source_sha: str) -> bool:
    tag_sha = existing_tag_sha(release)
    if tag_sha is None:
        return False
    parent = subprocess.run(
        ["git", "rev-parse", f"{tag_sha}^"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    tree = subprocess.run(
        ["git", "rev-parse", f"{tag_sha}^{{tree}}"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    if parent.returncode != 0 or tree.returncode != 0:
        return False
    return parent.stdout.strip() == source_sha and tree.stdout.strip() == sdk_tree_sha(source_sha)


# 从已验证提交的 SDK 子树创建 Package 根快照；重试只能复用完全相同的 Tag。
def create_package_tag(release: Release, source_sha: str) -> str:
    if git("rev-parse", "HEAD") != source_sha:
        raise ValueError("当前代码与待发布 source SHA 不一致，禁止创建 Package Tag")
    tag_sha = existing_tag_sha(release)
    if tag_sha is not None:
        if not package_snapshot_matches(release, source_sha):
            raise ValueError(f"Tag 已存在但不是当前 SDK snapshot：{release.tag}")
        return tag_sha
    tree_sha = sdk_tree_sha(source_sha)
    message = f"Publish Lingora Swift Package {release.version}\n\nSource-Commit: {source_sha}\n"
    snapshot = subprocess.run(
        ["git", "commit-tree", tree_sha, "-p", source_sha],
        cwd=ROOT,
        check=True,
        capture_output=True,
        input=message,
        text=True,
    ).stdout.strip()
    subprocess.run(
        [
            "git", "tag", "-a", release.tag,
            "-m", f"Publish Lingora Swift Package {release.version}\n\nSource-Commit: {source_sha}",
            snapshot,
        ],
        cwd=ROOT,
        check=True,
    )
    return snapshot


# 仅 develop 上版本文件的实际变更可以提出自动发布请求。
def planned_dev_release(ref_name: str, before_sha: str) -> Release | None:
    if ref_name != "develop":
        return None
    if not re.fullmatch(r"[0-9a-f]{40}", before_sha) or before_sha == "0" * 40:
        raise ValueError("自动发布需要有效的 push before SHA")
    changed = git("diff", "--name-only", before_sha, "HEAD", "--", "sdk-dev.version")
    if not changed:
        return None
    return Release("dev", (ROOT / "sdk-dev.version").read_text(encoding="utf-8").strip())


# 校验发布请求的分支、SHA 与版本唯一性，审批后仍锁定同一 SDK 快照。
def verify_request(
    release: Release,
    ref_type: str,
    ref_name: str,
    expected_sha: str,
    *,
    allow_existing_tag: bool = False,
) -> str:
    if ref_type != "branch" or ref_name != release.branch:
        raise ValueError(f"{release.channel} 渠道只能从 {release.branch} 分支发起")
    sha = git("rev-parse", "HEAD")
    if sha != expected_sha:
        raise ValueError("当前代码与发布事件记录的 commit SHA 不一致，禁止发布")
    fetch_source(release, tags=True)
    check_source(release, sha)
    tag_sha = existing_tag_sha(release)
    if tag_sha is not None and (
        not allow_existing_tag or not package_snapshot_matches(release, sha)
    ):
        raise ValueError(f"Tag 已存在或指向其他 SDK snapshot，必须使用新版本：{release.tag}")
    return sha


# 限定 GitHub 仓库标识，避免凭据被发送到外部地址。
def check_repository(repository: str) -> None:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("repository 必须为 owner/repository")


# 读取 GitHub 审批配置；权限、网络或响应异常都不能当作配置已通过。
def github_json(repository: str, path: str) -> dict:
    check_repository(repository)
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if not token:
        raise ValueError("读取审批配置需要 GH_TOKEN 或 GITHUB_TOKEN")
    request = Request(
        f"https://api.github.com/repos/{repository}/{path}",
        headers={"Accept": "application/vnd.github+json", "Authorization": f"Bearer {token}"},
    )
    try:
        with urlopen(request, timeout=30) as response:
            data = json.load(response)
    except HTTPError as exc:
        raise ValueError(f"无法读取发布审批配置：HTTP {exc.code}，请由仓库所有者完成设置") from exc
    except URLError as exc:
        raise ValueError("无法连接 GitHub 验证审批配置，发布已停止") from exc
    if not isinstance(data, dict):
        raise ValueError("GitHub 审批配置响应格式错误")
    return data


# 校验当前渠道的唯一审批人、自审、管理员保护和唯一来源分支。
def validate_environment(release: Release, environment: dict, policies: dict) -> None:
    rules = environment.get("protection_rules", [])
    reviewers_rule = next((rule for rule in rules if rule.get("type") == "required_reviewers"), {})
    reviewers = {
        item.get("reviewer", {}).get("login")
        for item in reviewers_rule.get("reviewers", [])
        if item.get("type") == "User"
    }
    if reviewers != REVIEWERS or reviewers_rule.get("prevent_self_review") is not False:
        raise ValueError(f"发布环境 {release.environment} 必须仅配置 hzh137940556 为审批人，并允许自己批准")
    if environment.get("can_admins_bypass") is not False:
        raise ValueError(f"发布环境 {release.environment} 必须关闭管理员跳过审批")
    policy = environment.get("deployment_branch_policy") or {}
    branches = policies.get("branch_policies", [])
    if (
        policy.get("custom_branch_policies") is not True
        or policy.get("protected_branches") is not False
        or len(branches) != 1
        or branches[0].get("type") != "branch"
        or branches[0].get("name") != release.branch
    ):
        raise ValueError(f"发布环境 {release.environment} 必须只允许 Branch {release.branch}")


# 审批前后读取当前渠道的真实门禁，环境缺失时停止发布。
def check_environment(release: Release, repository: str) -> None:
    path = f"environments/{release.environment}"
    validate_environment(
        release,
        github_json(repository, path),
        github_json(repository, f"{path}/deployment-branch-policies"),
    )


# 从干净且已同步的本地分支完成验证，然后请求 GitHub Actions 发版。
def publish(release: Release) -> None:
    if git("branch", "--show-current") != release.branch:
        raise ValueError(f"{release.channel} 渠道只能从 {release.branch} 发布")
    if git("status", "--porcelain"):
        raise ValueError("工作区存在未提交修改，请先提交")
    fetch_source(release, tags=True)
    sha = git("rev-parse", "HEAD")
    if sha != git("rev-parse", f"origin/{release.branch}"):
        raise ValueError(f"本地 {release.branch} 与 origin/{release.branch} 不一致，请先同步")
    if existing_tag_sha(release) is not None:
        raise ValueError(f"Tag 已存在，必须使用新版本：{release.tag}")
    subprocess.run(["make", "verify"], cwd=ROOT, check=True)
    if git("rev-parse", "HEAD") != sha or git("status", "--porcelain"):
        raise ValueError("测试期间代码发生变化，请重新发布")
    subprocess.run(
        [
            "gh", "workflow", "run", "ci.yml", "--ref", release.branch,
            "-f", f"channel={release.channel}", "-f", f"version={release.version}",
        ],
        cwd=ROOT,
        check=True,
    )
    print(f"已请求 {release.channel} 发布 {release.tag}；Tag 将在 CI 验证和环境审批后创建")


# 向 CI 输出已验证的版本、渠道、来源和审批环境。
def report(release: Release, sha: str = "", output: Path | None = None) -> None:
    fields = {
        "version": release.version,
        "channel": release.channel,
        "branch": release.branch,
        "tag": release.tag,
        "sha": sha,
        "environment": release.environment,
    }
    print(json.dumps(fields, ensure_ascii=False))
    if output:
        with output.open("a", encoding="utf-8") as stream:
            stream.writelines(f"{key}={value}\n" for key, value in fields.items())
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with Path(summary).open("a", encoding="utf-8") as stream:
            stream.write(f"\n### Swift Package 发布信息 [{release.channel}] — {release.version}\n\n")
            stream.writelines(f"- {key}: `{value}`\n" for key, value in fields.items())


# 提供 Makefile 与 GitHub Actions 共用的版本检查和发版入口。
def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Lingora iOS Swift Package 发布校验与发版工具")
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("info", "publish"):
        command = commands.add_parser(name)
        command.add_argument("--channel", choices=("dev", "release"), required=True)
        command.add_argument("--version", required=True)
    create = commands.add_parser("create-package-tag")
    create.add_argument("--channel", choices=("dev", "release"), required=True)
    create.add_argument("--version", required=True)
    create.add_argument("--source-sha", required=True)
    verify = commands.add_parser("verify-request")
    verify.add_argument("--channel", choices=("dev", "release"), required=True)
    verify.add_argument("--version", required=True)
    verify.add_argument("--ref-type", required=True)
    verify.add_argument("--ref-name", required=True)
    verify.add_argument("--expected-sha", required=True)
    verify.add_argument("--repository", required=True)
    verify.add_argument("--github-output", type=Path)
    verify.add_argument("--allow-existing-tag", action="store_true")
    plan = commands.add_parser("plan-dev")
    plan.add_argument("--ref-name", required=True)
    plan.add_argument("--before-sha", required=True)
    plan.add_argument("--github-output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "plan-dev":
            planned = planned_dev_release(args.ref_name, args.before_sha)
            if planned is not None:
                report(planned, output=args.github_output)
            return 0
        release = Release(args.channel, args.version)
        if args.command == "verify-request":
            sha = verify_request(
                release,
                args.ref_type,
                args.ref_name,
                args.expected_sha,
                allow_existing_tag=args.allow_existing_tag,
            )
            check_environment(release, args.repository)
            report(release, sha, args.github_output)
        elif args.command == "create-package-tag":
            snapshot = create_package_tag(release, args.source_sha)
            print(json.dumps({"tag": release.tag, "package_sha": snapshot}, ensure_ascii=False))
        elif args.command == "publish":
            publish(release)
        else:
            report(release)
        return 0
    except (ValueError, OSError, subprocess.CalledProcessError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
