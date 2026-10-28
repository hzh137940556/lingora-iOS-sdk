"""使用真实固定版本 CLI 和本机协议 fixture 验证 ICU 上传及 apple-sdk 下载，不访问真实项目。"""
from email import policy
from email.parser import BytesParser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import zipfile

DEMO = Path(__file__).resolve().parents[1]
EXPECTED = {"legacy_count": "%lld files", "catalog_hello": "Catalog %@", "catalog_items": {"variations": {"plural": {"one": "%lld catalog item", "other": "%lld catalog items"}}}, "welcome_name": "Hello, %@!", "items_count": {"variations": {"plural": {"one": "%lld item", "other": "%lld items"}}}}


# 协议 fixture 校验 CLI 的真实 multipart 请求，导出响应使用已核对的服务端格式。
class Handler(BaseHTTPRequestHandler):
    imported = False
    errors = []

    # 测试不输出请求头，避免继承环境中的信息进入日志。
    def log_message(self, *args):
        pass

    # 返回 CLI 使用的统一 API envelope。
    def respond(self, data):
        body = json.dumps({"code": 200, "data": data}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(body)

    # 分支查询仅接受隔离测试项目的请求。
    def do_GET(self):
        if self.path.endswith("/branches"):
            self.respond([{"id": "00000000-0000-0000-0000-000000000002", "name": "develop"}])
        else:
            self.send_error(404)

    # 验证上传策略及 ICU 正文，下载通过标准 ZIP 协议交付。
    def do_POST(self):
        body = self.rfile.read(int(self.headers["Content-Length"]))
        try:
            if self.path.endswith("/imports/single-step"):
                message = BytesParser(policy=policy.default).parsebytes(
                    f"Content-Type: {self.headers['Content-Type']}\r\nMIME-Version: 1.0\r\n\r\n".encode() + body)
                parts = list(message.iter_parts())
                params = json.loads(next(p.get_payload(decode=True) for p in parts if p.get_param("name", header="content-disposition") == "params"))
                assert params["forceMode"] == "KEEP" and not params["removeOtherKeys"]
                assert not params["convertPlaceholdersToIcu"]
                mapping = params["fileMappings"][0]
                assert mapping["namespace"] == "app" and mapping["languageTag"] == "en-US"
                values = json.loads(next(p.get_payload(decode=True) for p in parts if p.get_filename()))
                assert values["legacy_count"] == "{arg1, number} files"
                assert values["catalog_hello"] == "Catalog {arg1}"
                assert values["catalog_items"] == {"one": "# catalog item", "other": "# catalog items"}
                assert values["welcome_name"] == "Hello, {arg1}!"
                assert values["items_count"] == {"one": "# item", "other": "# items"}
                Handler.imported = True
                self.respond({"affected": 0, "deleted": 0})
            elif self.path.endswith("/exports"):
                assert Handler.imported
                payload = json.loads(body)
                assert payload["format"] in ("apple-sdk", "APPLE_SDK")
                archive = io.BytesIO()
                with zipfile.ZipFile(archive, "w") as output:
                    output.writestr("Lingora/app/ja.json", json.dumps(EXPECTED))
                self.send_response(200)
                self.send_header("Content-Type", "application/zip")
                self.end_headers()
                self.wfile.write(archive.getvalue())
            else:
                self.send_error(404)
        except Exception as error:
            Handler.errors.append(repr(error))
            self.send_error(400)


# 在临时目录跑固定 CLI 的 push/pull/validate，使用合成凭据且清理所有产物。
def main():
    version = (DEMO / "lingora-cli.version").read_text().strip()
    cli = ["uvx", "--from", f"lingora-cli=={version}", "lingora"]
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix="lingora-cli-smoke-") as temporary:
            root = Path(temporary)
            config = json.loads((DEMO / "ci/lingora.dev.json").read_text())
            config["apiUrl"] = f"http://127.0.0.1:{server.server_port}"
            config["projectId"] = "00000000-0000-0000-0000-000000000001"
            config["push"]["files"] = [dict(item, path=str((DEMO / "ci" / item["path"]).resolve())) for item in config["push"]["files"] if item["namespace"] == "app"]
            legacy = root / "Legacy.strings"
            legacy.write_text('"legacy_count" = "%d files";')
            catalog = root / "Localizable.xcstrings"
            catalog.write_text(json.dumps({"version": "1.0", "sourceLanguage": "en-US", "strings": {
                "catalog_hello": {"localizations": {"en-US": {"stringUnit": {"value": "Catalog %@"}}}},
                "catalog_items": {"localizations": {"en-US": {"variations": {"plural": {
                    "one": {"stringUnit": {"value": "%d catalog item"}},
                    "other": {"stringUnit": {"value": "%d catalog items"}}
                }}}}}
            }}))
            config["push"]["files"] += [{"path": str(source), "namespace": "app", "language": "en-US"}
                                         for source in (legacy, catalog)]
            config["pull"].update(path=str(root / "output"), languages=["ja"], namespaces=["app"])
            path = root / "config.json"
            path.write_text(json.dumps(config))
            environment = {**os.environ, "LINGORA_API_KEY": "local-protocol-fixture", "NO_PROXY": "127.0.0.1,localhost", "no_proxy": "127.0.0.1,localhost"}
            subprocess.run([sys.executable, str(DEMO / "scripts/push_icu.py"), "--config", str(path), "--version", version], env=environment, check=True)
            for command in ("pull", "validate"):
                subprocess.run([*cli, "--config", str(path), command], env=environment, check=True)
            assert json.loads((root / "output/Lingora/app/ja.json").read_text()) == EXPECTED
            assert not Handler.errors, Handler.errors
            print("Pinned CLI ICU upload/download protocol smoke passed (localhost only)")
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


if __name__ == "__main__":
    main()
