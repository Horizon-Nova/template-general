# template-general

通用專案模板，內含 Horizon-Nova 標準文件與自動同步模板文件的 GitHub Actions 工作流程。

## 內含項目
- `docs/`：標準文件。
- `GitPush.bat`：本機備份、拉取與推送腳本。
- `.github/workflows/sync-template-files.yml`：同步來源模板最新文件。

## 同步機制
- 建立自此模板的新專案後，workflow 會在 `push`、排程與手動觸發時執行。
- workflow 會從 `https://github.com/Horizon-Nova/template-general.git` 拉取最新模板。
- 同步範圍僅包含 `docs/`、`GitPush.bat` 與 workflow 自身，不會覆寫專案業務程式碼。
