import Foundation

// 脚本目录的写操作：上传、新建目录、改名、移动、复制、删除、版本回滚。
//
// 这些接口都在 `/scripts` 路由组里，面板统一挂了 `RequireRole("operator")`，
// 所以 viewer 账号会拿到 403「权限不足」，入口处先用 `session.canWrite` 挡一层。
extension APIClient {

    /// `POST /scripts/directory {path}` → 201，相对脚本根目录的路径。
    func createScriptDirectory(path: String) async throws {
        _ = try await send(path: "/scripts/directory",
                           method: "POST",
                           json: ["path": path])
    }

    /// `POST /scripts/upload`（multipart，字段名 `file` 可重复，`dir` 是目标目录）。
    /// 同名文件会被**直接覆盖**，面板不会自动改名，调用前得自己问一句。
    func uploadScriptFiles(_ files: [ScriptUploadFile], dir: String) async throws -> ScriptUploadResult {
        let data = try await uploadMultipartFiles(path: "/scripts/upload",
                                                  field: "file",
                                                  files: files.map { ($0.filename, $0.mimeType, $0.data) },
                                                  extraFields: dir.isEmpty ? [:] : ["dir": dir])
        // 201 回执是 `{message, path, paths, uploaded_count}`，没有 data 外壳。
        return (try? Self.decoder.decode(ScriptUploadResult.self, from: data))
            ?? ScriptUploadResult(message: "上传成功", path: nil, paths: nil, uploadedCount: files.count)
    }

    /// `PUT /scripts/rename {old_path, new_name}` → `{message, new_path}`。
    /// `new_name` 只能是叶子名，不能带路径分隔符。
    func renameScript(path: String, newName: String) async throws -> String? {
        let data = try await send(path: "/scripts/rename",
                                  method: "PUT",
                                  json: ["old_path": path, "new_name": newName])
        return (try? Self.decoder.decode(ScriptMutationResult.self, from: data))?.newPath
    }

    /// `PUT /scripts/move {source_path, target_dir}`。`target_dir` 传空串表示移到脚本根目录。
    func moveScript(path: String, targetDir: String) async throws -> String? {
        let data = try await send(path: "/scripts/move",
                                  method: "PUT",
                                  json: ["source_path": path, "target_dir": targetDir])
        return (try? Self.decoder.decode(ScriptMutationResult.self, from: data))?.newPath
    }

    /// `POST /scripts/copy {source_path, target_dir, new_name?}` → 201。
    /// 目标已存在时面板同样直接覆盖。
    func copyScript(path: String, targetDir: String, newName: String?) async throws -> String? {
        var body: [String: Any] = ["source_path": path, "target_dir": targetDir]
        if let newName, !newName.isEmpty { body["new_name"] = newName }
        let data = try await send(path: "/scripts/copy", method: "POST", json: body)
        return (try? Self.decoder.decode(ScriptMutationResult.self, from: data))?.newPath
    }

    /// `DELETE /scripts?path=&type=`。目录要显式传 `type=directory`，否则会当成文件删（回 400）。
    func deleteScript(path: String, isDirectory: Bool) async throws {
        _ = try await send(path: "/scripts",
                           method: "DELETE",
                           query: ["path": path, "type": isDirectory ? "directory" : "file"])
    }

    /// `PUT /scripts/versions/:id/rollback`：把文件写回该版本，并**新增**一个「回滚到 vN」的版本。
    func rollbackScriptVersion(id: Int) async throws -> String? {
        let data = try await send(path: "/scripts/versions/\(id)/rollback", method: "PUT")
        return (try? Self.decoder.decode(ScriptRollbackResult.self, from: data))?.message
    }

    /// `DELETE /scripts/versions?path=`：清空该文件的全部历史版本（不可撤销）。
    func clearScriptVersions(path: String) async throws -> Int? {
        let data = try await send(path: "/scripts/versions", method: "DELETE", query: ["path": path])
        return (try? Self.decoder.decode(ScriptClearVersionsResult.self, from: data))?.clearedCount
    }
}

/// 待上传的脚本文件。`filename` 用原始文件名（面板按扩展名白名单过滤）。
struct ScriptUploadFile {
    let filename: String
    let mimeType: String
    let data: Data
}

struct ScriptUploadResult: Decodable {
    var message: String?
    var path: String?
    var paths: [String]?
    var uploadedCount: Int?
}

private struct ScriptMutationResult: Decodable {
    var message: String?
    var newPath: String?
}

private struct ScriptRollbackResult: Decodable {
    var message: String?
    var version: Int?
}

private struct ScriptClearVersionsResult: Decodable {
    var message: String?
    var clearedCount: Int?
}
