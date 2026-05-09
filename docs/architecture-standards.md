# ASP.NET Core MVC 架構規範

| 項目 | 內容 |
| --- | --- |
| 文件編號 | MVC-ARCH-001 |
| 版本 | 1.0 |
| 適用範圍 | ASP.NET Core MVC |
| 規範強度 | 強制(採用本規範之專案) |
| 目標讀者 | 後端開發者、前端開發者、AI 代理人 |
| 相依文件 | 《開發規範》(CODE-001) |

---

## §1 總則

### §1.1 目的

本規範界定 ASP.NET Core MVC 後台應用程式之分層架構、命名準則、資料傳遞規則、前端互動模式,以確保專案具備可維護性、可稽核性與一致性。條文採「必須 / 禁止 / 反例 / 正例」格式,供人類開發者與 AI 代理人逐條判定。

### §1.2 規範用語

- **必須 (MUST)**:強制條款,違反即視為不合規
- **禁止 (MUST NOT)**:強制禁止條款
- **應 (SHOULD)**:建議條款,偏離時須具備合理理由
- **得 (MAY)**:允許條款,採用與否由實作者判斷

### §1.3 整體分層

本規範定義後端五個功能層與前端三個結構區:

**後端功能層:**

```
Controllers → Services → Repositories → Database
                ↓
              Core（跨層共用能力）
              Model（EF 實體與視圖）
```

**前端結構區:**

```
Views（主頁面）→ Partials（功能分區）→ Modal（彈窗）
                                    ↓
                               Scripts Partial（頁面邏輯）
```

**請求處理流程:**

```
HTTP 請求 → Middleware → Filter → Controller → Service → Repository → Database
                                     ↓
                                  View / PartialView / Json
```

### §1.4 規範之外

下列主題不屬於本規範範圍:

- 部署與 CI/CD 流程
- 資料庫 Schema 設計
- 身份驗證機制內部實作(屬 Core/AuthService)
- 第三方套件使用細節

---

## §2 後端分層規範

### §2.1 Model 層

#### §2.1.1 定義與分類

Model 層存放所有資料型別定義,分為兩類,**性質完全不同**,禁止混用:

| 類別 | 特性 | 範例 | 是否自動生成 |
| --- | --- | --- | --- |
| **EF 實體** | 對應資料庫實體表,可讀寫 | `permission_management` | 是 |
| **EF 視圖** | 對應資料庫視圖,唯讀,`[Keyless]` | `vw_permission_user` | 是 |

#### §2.1.2 自動生成規則

- 必須:Model 檔案由 `BuildModels` 工具依資料庫 Schema 自動生成
- 必須:檔案頭部保留「嚴重警告」標頭,標示禁止手動修改
- 禁止:手動修改自動生成之 Model 檔案(任何修改在下次生成時會被覆蓋)
- 必須:若需調整 Model,修改資料庫 Schema 後重新執行 `BuildModels`

#### §2.1.3 EF 實體命名

- 表格實體:小寫底線命名法,對應資料庫表名(如 `permission_management`)
- 視圖實體:以 `vw_` 為前綴,對應資料庫視圖(如 `vw_permission_user`)
- 視圖實體必須標記 `[Keyless]`

#### §2.1.4 使用規則

- 必須:Repository 使用 EF 實體進行寫入操作
- 必須:Repository 使用 EF 視圖進行讀取查詢(視圖已含關聯資料)
- 禁止:在 Model 類別內實作業務邏輯或 I/O 操作
- 禁止:Controller 或 Service 直接引用 `DbContext`

---

### §2.2 Repository 層

#### §2.2.1 職責

Repository 為資料存取層,提供乾淨、可預測的資料讀寫介面:

- 查詢資料庫(透過 EF Core)
- 持久化資料(新增、更新、刪除)
- 不包含業務邏輯、不包含資料轉換

#### §2.2.2 結構範本

```csharp
public class ExampleRepository(ExampleDbContext db)
{
    #region 統一的查詢來源
    private IQueryable<example_table> ValidExamples
        => db.example_tables.Where(x => !x.is_deleted).OrderBy(x => x.created_at);

    private IQueryable<vw_example> ValidExampleViews
        => db.vw_examples;
    #endregion

    #region 專用查詢方法
    public List<vw_example> QueryExampleList(string? keyword = null, bool? isActive = null)
        => ValidExampleViews
            .Where(x =>
                (string.IsNullOrEmpty(keyword) || x.name!.Contains(keyword)) &&
                (!isActive.HasValue || x.is_active == isActive))
            .ToList();

    public vw_example? QueryExample(int? id = null, string? name = null)
    {
        if (id.HasValue) return ValidExampleViews.FirstOrDefault(x => x.id == id);
        if (!string.IsNullOrEmpty(name)) return ValidExampleViews.FirstOrDefault(x => x.name == name);
        return null;
    }
    #endregion

    #region 基本 CRUD 操作
    public example_table InsertExample(example_table data)
    {
        var existing = db.example_tables.Find(data.id);
        if (existing == null)
        {
            data.created_at = DateTime.Now;
            db.example_tables.Add(data);
            db.SaveChanges();
            return data;
        }
        existing.name = data.name;
        existing.is_active = data.is_active;
        // 條件性更新（密碼等敏感欄位）
        if (!string.IsNullOrEmpty(data.password_hash))
            existing.password_hash = data.password_hash;
        existing.updated_at = DateTime.Now;
        db.SaveChanges();
        return existing;
    }

    public bool DeleteExample(int id)
    {
        var entity = db.example_tables.Find(id);
        if (entity == null) return false;
        db.example_tables.Remove(entity);
        db.SaveChanges();
        return true;
    }
    #endregion
}
```

#### §2.2.3 命名規則

| 類別 | 命名格式 | 範例 |
| --- | --- | --- |
| 統一查詢來源 | `Valid{表名}s`(私有屬性) | `ValidUsers` |
| 列表查詢 | `Query{表名}List(...)` | `QueryUserList()` |
| 單一查詢 | `Query{表名}(...)` | `QueryUser(int? id = null)` |
| 新增/更新 | `Insert{表名}(data)` | `InsertUser(user)` |
| 刪除 | `Delete{表名}(int id)` | `DeleteUser(int id)` |

#### §2.2.4 規範

**必須:**
- 查詢來源統一使用 `Valid{表名}s` 私有屬性,確保條件(如軟刪除過濾)不重複
- `Insert*` 方法同時負責新增與更新(以 `id` 判斷):id 為 0 或 null 時新增,否則更新
- 一張表只有一個 `Insert*` 方法,一個 `Delete*` 方法

**禁止:**
- 使用 `Get*` 命名
- 使用 `async/await`
- 使用 `try...catch`(由 `ExceptionLoggingMiddleware` 集中處理)
- 在 Repository 內實作業務規則或資料轉換

---

### §2.3 Service 層

#### §2.3.1 職責

Service 為業務邏輯層,介於 Controller 與 Repository 之間:

- 組合 Repository 呼叫
- 實作業務規則(驗證、計算、流程控制)
- 設定 ViewBag 資料(透過 `ViewBagModel` 方法)
- 回傳結構化結果供 Controller 使用

#### §2.3.2 結構範本

```csharp
public class ExampleService(ExampleRepository repo)
{
    #region 統一的查詢方法
    public List<vw_example> LoadExampleList(string? keyword = null, bool? isActive = null)
        => repo.QueryExampleList(keyword, isActive);

    public vw_example? LoadExample(int id)
        => repo.QueryExample(id: id);
    #endregion

    #region ViewBag 設定方法
    public void ViewBagModel(dynamic viewBag, /* 範圍參數... */)
    {
        viewBag.Examples = repo.QueryExampleList();
        // 依頁面需求設定其他 ViewBag 資料
    }
    #endregion

    #region 基本 CRUD 操作
    public (bool success, string message) CreateExample(example_table data)
    {
        // 業務規則驗證
        var existing = repo.QueryExample(name: data.name);
        if (existing != null)
            return (false, "[失敗] 名稱已存在");

        var result = repo.InsertExample(data);
        return result != null
            ? (true, "[成功] 建立完成")
            : (false, "[失敗] 建立失敗");
    }

    public bool DeleteExample(int id) => repo.DeleteExample(id);
    #endregion
}
```

#### §2.3.3 命名規則

| 類別 | 命名格式 | 範例 |
| --- | --- | --- |
| 列表載入 | `Load{表名}List(...)` | `LoadUserList()` |
| 單一載入 | `Load{表名}(int id)` | `LoadUser(int id)` |
| 新增/更新 | `Create{表名}(data)` | `CreateUser(user)` |
| 刪除 | `Delete{表名}(int id)` | `DeleteUser(int id)` |
| ViewBag 設定 | `ViewBagModel(viewBag, ...)` | `ViewBagModel(ViewBag, scopeIds)` |

#### §2.3.4 `Create*` 回傳格式

**必須:**Create 方法統一回傳 `(bool success, string message)`:

```csharp
// 正確
public (bool success, string message) CreateUser(example_table data) { ... }

// 若需回傳建立後的實體(少數情況)
public (bool success, string? errorMessage, vw_example? result) CreateWithResult(data) { ... }
```

**訊息格式:**訊息必須以 `[成功]` 或 `[失敗]` 開頭,供前端 `resolveToastType` 判斷顯示樣式。

#### §2.3.5 `ViewBagModel` 規則

- 必須:Modal 載入前使用 `ViewBagModel` 統一設定所有靜態選單資料
- 必須:`ViewBagModel` 設定的是**靜態選單與輔助資料**(下拉選單來源),不是動態查詢結果
- 禁止:在 `ViewBagModel` 內設定主要列表資料(主列表由 `Search*` Action 的 `@model` 傳遞)

#### §2.3.6 規範

**必須:**
- 使用 `Load*` 命名查詢方法,不使用 `Get*` 或 `Query*`
- 業務規則在 Service 實作,不下沉至 Repository

**禁止:**
- 使用 `async/await`
- 使用 `try...catch`
- 直接呼叫 `DbContext`

---

### §2.4 Controller 層

#### §2.4.1 職責

Controller 為 HTTP 請求入口:

- 接收請求參數
- 呼叫 Service
- 回傳 View / PartialView / Json

禁止在 Controller 內放置任何業務邏輯。

#### §2.4.2 標準 Action 模式

**主頁面(Index):**
```csharp
public IActionResult Users() => View();
```

**搜尋結果(AJAX 回傳 Partial):**
```csharp
public IActionResult SearchUsers()
{
    var model = sev.LoadUserList();
    return PartialView("Partials/Users/_SearchResults", model);
}
```

**載入 Modal 表單:**
```csharp
public IActionResult LoadUserForm(int? id = null)
{
    sev.ViewBagModel(ViewBag);
    var model = id.HasValue ? sev.LoadUser(id.Value) : null;
    return PartialView("Partials/Users/Modal/_FormData", model);
}
```

**載入 Modal 詳情:**
```csharp
public IActionResult LoadUserDetail(int id)
{
    sev.ViewBagModel(ViewBag);
    var model = sev.LoadUser(id);
    return PartialView("Partials/Users/Modal/_Permissions", model);
}
```

**提交(新增或更新):**
```csharp
[HttpPost]
public IActionResult SubmitUser(example_table form)
{
    var result = sev.CreateUser(form);
    return Json(new { success = result.success, message = result.message });
}
```

**刪除:**
```csharp
[HttpPost]
public IActionResult Delete(int id)
{
    var result = sev.DeleteExample(id);
    return Json(new { success = result, message = result ? "[成功] 刪除完成" : "[失敗] 刪除失敗" });
}
```

#### §2.4.3 命名規則

| Action 類型 | 命名格式 | 回傳 |
| --- | --- | --- |
| 主頁面 | `{功能名}()` | `View()` |
| 搜尋結果 | `Search{功能名}()` | `PartialView(...)` |
| 載入表單 | `Load{功能名}Form(int? id = null)` | `PartialView(...)` |
| 載入詳情 | `Load{功能名}Detail(int id)` | `PartialView(...)` |
| 提交 | `Submit{功能名}(FormType form)` | `Json(...)` |
| 刪除 | `Delete(int id)` | `Json(...)` |

#### §2.4.4 規範

**必須:**
- 主頁面 Action 回傳空 `View()`,資料由前端 AJAX 另行載入
- Modal 載入前呼叫 `ViewBagModel(ViewBag)` 設定選單資料
- 每個 Controller 僅允許一個 `Delete` 方法

**禁止:**
- 使用 `Get*` 命名
- 在 Controller 內撰寫業務判斷或資料處理邏輯
- 使用 `async/await`
- 使用 `try...catch`

---

### §2.5 Core 層

#### §2.5.1 定義

Core 層存放跨層共用之核心能力,包含以下三類:

**類別一:業務範圍解析**

跨功能使用的範圍解析服務,如 `OrganizationScope`:

```csharp
// OrganizationScope 解析當前使用者的組織範圍
public class OrganizationScope(HnbBackofficeDbContext db)
{
    public UserScope ResolveUserScope(ClaimsPrincipal? user = null) { ... }
}

// UserScope 封裝使用者範圍資料
public class UserScope
{
    public vw_permission_user? User { get; set; }
    public int? OrganizationId { get; set; }
    public List<int> ScopeIds { get; set; } = new();
    public List<int> RoleIds { get; set; } = new();
    public List<string> NavigationPermissions { get; set; } = new();
}
```

**類別二:共用擴充方法**

```csharp
// QueryableExtensions 提供條件式查詢擴充
public static IQueryable<T> WhereWhen<T>(
    this IQueryable<T> source,
    bool condition,
    Expression<Func<T, bool>> predicate)
    => condition ? source.Where(predicate) : source;
```

**類別三:基礎控制器**

`BaseController` 為所有功能 Controller 之基類:

```csharp
[Area("Backoffice"), Permission]
public abstract class BaseController : Controller
{
    public override void OnActionExecuting(ActionExecutingContext context)
    {
        LoadSidebarNavigation();  // 每次 Action 前自動載入導覽列資料
        base.OnActionExecuting(context);
    }
}
```

#### §2.5.2 規範

**必須:**
- 所有功能 Controller 繼承 `BaseController`
- `OrganizationScope` 透過建構式注入取得,不直接 `new`
- 呼叫 `organizationScope.ResolveUserScope(User)` 取得範圍,以 `scope.ScopeIds` 過濾資料

**禁止:**
- 在 Core 層放置特定功能業務邏輯(Core 只放跨功能共用能力)
- 將 `BaseController` 的共用邏輯移到個別 Controller 重複撰寫

---

### §2.6 Middleware 層

#### §2.6.1 定義

Middleware 為 HTTP 請求管線層,於 Controller 前後攔截所有請求。

#### §2.6.2 三類 Middleware 說明

**ExceptionLoggingMiddleware — 全域例外捕捉**

```csharp
public class ExceptionLoggingMiddleware(RequestDelegate next)
{
    public async Task Invoke(HttpContext context, ErrorLogService loggerService, ...)
    {
        try { await next(context); }
        catch (Exception ex)
        {
            loggerService.Save(context, ex, "Middleware", 0);
            throw;  // 必須重新拋出,讓框架處理後續錯誤頁面
        }
    }
}
```

本 Middleware 是 Controller/Service/Repository 禁用 `try...catch` 的根本原因——例外由此統一捕捉記錄。

**IpSecurityMiddleware — IP 安全防護**

- 依 IP 封鎖清單攔截惡意請求(回傳 `403 Forbidden`)
- 依頻率限制攔截過多請求(回傳 `429 Too Many Requests`)

**FileUploadFormOptionsMiddleware — 上傳限制注入**

- 僅對特定路由(`/Backoffice/FileManager/SubmitUpload`)生效
- 提前設定 `FormOptions` 解除預設上傳大小限制(最大 5GB)

#### §2.6.3 規範

**必須:**
- Middleware 僅處理管線層關切點(安全、日誌、選項設定)
- 路由特定之 Middleware 必須以 `Path.StartsWithSegments` 判斷再生效

**禁止:**
- 在 Middleware 內實作業務邏輯
- 在 Middleware 內直接回傳業務資料

---

### §2.7 Filters 層

#### §2.7.1 定義

Filter 在 Action 前後執行,用於橫切關注點(Cross-cutting Concerns)。

#### §2.7.2 兩類 Filter 說明

**RequestResponseLoggerFilter — 請求回應記錄**

```csharp
public class RequestResponseLoggerFilter : IAsyncResourceFilter
{
    public async Task OnResourceExecutionAsync(ResourceExecutingContext context, ResourceExecutionDelegate next)
    {
        // 記錄請求 body → 執行 Action → 記錄回應 body → 寫入資料庫
    }
}
```

適用範圍:記錄每個 Action 的請求參數與回應內容到 `access_records` 資料表。

**Permission Filter**

於 `BaseController` 以 `[Permission]` 屬性套用,攔截未授權請求。所有繼承 `BaseController` 之 Controller 自動受此 Filter 保護。

#### §2.7.3 規範

**必須:**
- 跨功能的橫切邏輯以 Filter 實作,不散落在個別 Controller
- `RequestResponseLoggerFilter` 記錄完成後必須將回應 Body 還原(`CopyToAsync`)

**禁止:**
- 在 Filter 內實作特定功能業務邏輯
- 在 Filter 內直接修改回應內容(除日誌外)

---

## §3 資料傳遞規範

### §3.1 ViewBag vs Model 決策

資料傳遞至 View 前,必須依下列規則判定使用 `@model` 或 `ViewBag`:

**使用 `@model` 的情況:**
- 列表資料(需 `@foreach` 處理)
- 需要迴圈處理的資料
- 需條件判斷的複雜資料(分區塊顯示)

**使用 `ViewBag` 的情況:**
- 單一數值或文字(計數、標題、ID)
- 唯一的動態識別資料
- Modal 動態載入時的輔助選單資料(特殊情況,見 §3.2)

**決策流程:**

```
資料需要傳遞到 View
        ↓
    是列表嗎？
    ├─ 是 → @model
    └─ 否 ↓
    需要 @foreach 嗎？
    ├─ 是 → @model
    └─ 否 ↓
    需要條件判斷（分區塊）嗎？
    ├─ 是 → @model
    └─ 否 ↓
    是單一值嗎？
    ├─ 是 → ViewBag
    └─ 否 ↓
    是 Modal 特殊情況嗎？
    ├─ 是 → ViewBag（允許含列表）
    └─ 否 → @model
```

### §3.2 Modal 資料傳遞(特殊情況)

Modal 透過 AJAX 動態載入時,Partial View 可能同時需要:

- 當前實體(如正在編輯的使用者)
- 下拉選單資料(如組織列表)
- 多選資料(如角色列表、導航權限)

此情況允許使用 `ViewBag` 傳遞多種類型資料:

```csharp
// Controller
public IActionResult LoadUserForm(int? id = null)
{
    sev.ViewBagModel(ViewBag);              // 設定 ViewBag 選單資料
    var model = id.HasValue ? sev.LoadUser(id.Value) : null;
    return PartialView("Partials/Users/Modal/_FormData", model);
}
```

```cshtml
@* Modal Partial — model 為主要實體,ViewBag 為輔助選單 *@
@model vw_permission_user?
@{
    var organizations = (IEnumerable<dynamic>)(ViewBag.Organizations ?? Enumerable.Empty<dynamic>());
}

<input type="text" value="@(Model?.full_name ?? "")" />

<select>
    @foreach (var org in organizations)
    {
        <option value="@org.id">@org.organization_name</option>
    }
</select>
```

**注意:**Modal Partial 同時使用 `@model`(主實體)與 `ViewBag`(輔助選單)並非矛盾,是明確允許的模式。

### §3.3 空值處理(Razor)

**必須:**
- 所有可能為 null 的字串使用 `?? ""`:如 `@(Model?.name ?? "")`
- 集合在使用前正規化:`var items = ViewBag.Items as List<ItemDto> ?? new();`
- 日期顯示:`@(Model?.created_at?.ToString("yyyy/MM/dd HH:mm") ?? "-")`
- 數值顯示:`@(Model?.count ?? 0)`

**禁止:**
- 為空值切換整段 DOM 結構(如以 `@if (!list.Any())` 替換整個表格為提示卡片)
- 為空值改變元件樣式(保持骨架一致,空時顯示空字串或預設值)
- 在 Controller 因參數缺漏而改回傳提示畫面

**反例:**
```cshtml
@* 錯誤:空值改變介面結構 *@
@if (Model?.name != null)
{
    <span>@Model.name</span>
}
else
{
    <span class="text-muted">（未填寫）</span>
}
```

**正例:**
```cshtml
@* 正確:固定元件結構,空值顯示空字串 *@
<span>@(Model?.name ?? "")</span>
```

---

## §4 View 結構規範

### §4.1 頁面組合骨架(通用)

每一個主頁面(.cshtml)均採**組合骨架**設計:主頁面本身是空殼,所有畫面內容、樣式、腳本均拆分為 Partial,由主頁面組合引用。

**通用骨架:**

```cshtml
@{
    ViewData["Title"] = "功能名稱 - 系統名稱";
    ViewData["PageTitle"] = "功能名稱";
    ViewData["PageDescription"] = "功能說明";
    ViewData["PageIcon"] = "lucide-icon-name";
    ViewData["HelpModalId"] = "featureHelpModal";
    Layout = "~/Areas/Backoffice/Views/Shared/_Layout.cshtml";
}

@await Html.PartialAsync("Partials/{Feature}/_Styles")

<section class="mb-3 mb-lg-4">
    @* 畫面內容 Partial,依功能需求引用 *@
    @await Html.PartialAsync("Partials/{Feature}/_ContentA")
    @await Html.PartialAsync("Partials/{Feature}/_ContentB")
</section>

@* Modal Partial,依功能需求引用 *@
@await Html.PartialAsync("Partials/{Feature}/Modal/_Help")

@section Scripts {
    @await Html.PartialAsync("Partials/{Feature}/_Scripts")
}
```

**骨架組成規則:**

| 位置 | Partial | 必要性 | 說明 |
| --- | --- | --- | --- |
| 最上方(section 之前) | `_Styles` | **必須** | 頁面專屬樣式,即使無內容也必須建立 |
| section 內 | 畫面內容 Partial | 依需求 | 可有一至多個,依頁面功能決定 |
| section 之後 | Modal Partial | 依需求 | 所有 Modal 預先於此引用 |
| `@section Scripts` | `_Scripts` | **必須** | 頁面腳本,即使無內容也必須建立 |

**核心規範:**
- 必須:`_Styles` 與 `_Scripts` 兩份 Partial **每個頁面都必須存在**,即使內容為空
- 必須:主頁面不含任何業務邏輯、資料讀取、內嵌 CSS、內嵌 JS
- 必須:所有 Modal 於主頁面預先引用,不以空容器等待 AJAX 注入
- 必須:`_Scripts` 透過 `@section Scripts` 注入,確保在 Layout 的 Script 區塊執行
- `_Styles` 與 `_Scripts` 在主頁面的引用順序不作強制規定,依頁面需求決定

---

### §4.2 Partial 職責分類

#### §4.2.1 `_Styles`(必要,即使空白)

存放頁面專屬的 CSS 定義。全域共用樣式放 `Themes/`,僅該頁面使用的樣式放此。

```cshtml
@{
    Layout = null;
}

<style>
    .hover-lift {
        transition: transform 0.2s ease-in-out, box-shadow 0.2s ease-in-out;
    }
    .hover-lift:hover {
        transform: translateY(-2px);
    }
</style>
```

若無專屬樣式,仍須建立空檔:

```cshtml
@{
    Layout = null;
}

@* 本頁面無專屬樣式 *@
```

#### §4.2.2 `_Scripts`(必要,即使空白)

存放頁面級 JavaScript,包含外部套件引用、初始化、主要函式(`Search`、`Submit`、`Delete`)。

```cshtml
@{
    Layout = null;
}

@* 外部套件(若需要) *@
<script src="https://cdn.example.com/lib.js"></script>

<script>
    $(document).ready(() => {
        window.lucide?.createIcons?.();
        Search();
    });

    function Search() { ... }
    function Submit() { ... }
    function Delete(id) { ... }
    function resolveToastType(message) { ... }
</script>
```

若無 JS 需求,仍須建立空檔:

```cshtml
@{
    Layout = null;
}

@* 本頁面無專屬腳本 *@
```

#### §4.2.3 畫面內容 Partial

承載各功能區塊的 HTML。每個 Partial 只負責自己區塊的內容。

**命名慣例:**

| Partial 名稱 | 適用情境 | 說明 |
| --- | --- | --- |
| `_Control` | 功能頁 | 搜尋列、篩選器、新增按鈕 |
| `_SearchResults` | 功能頁 | 資料表格,強型別 `@model List<T>` |
| `_Welcome` | 組合頁 | 歡迎區、使用者資訊 |
| `_QuickActions` | 組合頁 | 快速連結卡片 |
| `_SystemStatus` | 組合頁 | 圖表、狀態監控 |
| `_{功能區塊名}` | 任意 | 依頁面語意自訂名稱 |

**允許 Partial 自帶 `<script>`:** 當 JS 邏輯與該 Partial 的 HTML 緊密耦合(如圖表初始化),允許在 Partial 內直接內嵌 `<script>`。此 Partial 本身即為其 JS 的責任範圍,不需移至 `_Scripts`。

```cshtml
@* _SystemStatus.cshtml — 圖表 Partial 自帶初始化腳本 *@
@{
    Layout = null;
}

<canvas id="cpuChart"></canvas>

<script>
    $(document).ready(function () {
        const cpuUsage = @(ViewBag.CpuUsage ?? 0);
        new Chart(document.getElementById('cpuChart'), { ... });
    });
</script>
```

#### §4.2.4 Modal Partial

承載彈窗 HTML,路徑固定在 `Modal/` 子目錄下。

| Partial 名稱 | 說明 |
| --- | --- |
| `Modal/_FormData` | 新增/編輯表單,強型別 `@model T?` |
| `Modal/_Detail` 或 `_Permissions` | 唯讀詳情,強型別 `@model T?` |
| `Modal/_Help` | 操作說明,無 `@model` |

---

### §4.3 兩種頁面類型的完整結構

#### §4.3.1 功能頁(有 CRUD、有搜尋)

適用:Users、Roles、Organizations 等有增刪改查的頁面。

```
{Feature}.cshtml
├── Partials/{Feature}/_Styles.cshtml          頁面樣式(必須)
├── Partials/{Feature}/_Control.cshtml         搜尋列 + 篩選 + 新增按鈕
├── Partials/{Feature}/_SearchResults.cshtml   資料表格(@model List<T>)
├── Partials/{Feature}/Modal/_FormData.cshtml  新增/編輯表單(@model T?)
├── Partials/{Feature}/Modal/_Help.cshtml      操作說明
├── Partials/{Feature}/Modal/_Detail.cshtml    詳情/權限(@model T?)
└── Partials/{Feature}/_Scripts.cshtml         Search/Submit/Delete 等(必須)
```

主頁面範本:

```cshtml
@{
    ViewData["Title"] = "角色管理 - 系統名稱";
    ViewData["PageTitle"] = "角色管理";
    ViewData["PageDescription"] = "管理系統角色與權限設定";
    ViewData["PageIcon"] = "shield";
    ViewData["HelpModalId"] = "roleHelpModal";
    Layout = "~/Areas/Backoffice/Views/Shared/_Layout.cshtml";
}

@await Html.PartialAsync("Partials/Roles/_Styles")

<section class="mb-3 mb-lg-4">
    @await Html.PartialAsync("Partials/Roles/_Control")
    @await Html.PartialAsync("Partials/Roles/_SearchResults")
</section>

@await Html.PartialAsync("Partials/Roles/Modal/_FormData")
@await Html.PartialAsync("Partials/Roles/Modal/_Help")
@await Html.PartialAsync("Partials/Roles/Modal/_Permissions")

@section Scripts {
    @await Html.PartialAsync("Partials/Roles/_Scripts")
}
```

#### §4.3.2 組合頁(儀表板、統計、唯讀展示)

適用:Dashboard、報表、總覽等無 CRUD 的組合式頁面。Partial 無固定名稱,依頁面語意自訂。

```
Index.cshtml
├── Partials/_Styles.cshtml              頁面樣式(必須)
├── Partials/_Welcome.cshtml             歡迎區(讀 User Claims)
├── Partials/_QuickActions.cshtml        快速操作卡片
├── Partials/_SystemStatus.cshtml        系統圖表(可自帶 <script>)
├── Partials/_RecentActivities.cshtml    活動或說明區塊
├── Partials/Modal/_Help.cshtml          操作說明 Modal
└── Partials/_Scripts.cshtml             初始化與共用腳本(必須)
```

主頁面範本:

```cshtml
@{
    ViewData["Title"] = "儀表板";
    ViewData["PageTitle"] = "儀表板";
    ViewData["PageDescription"] = "系統總覽";
    ViewData["PageIcon"] = "home";
    ViewData["HelpModalId"] = "dashboardHelpModal";
    Layout = "~/Areas/Backoffice/Views/Shared/_Layout.cshtml";
}

@await Html.PartialAsync("Partials/_Styles")

<section class="mb-3 mb-lg-4">
    @await Html.PartialAsync("Partials/_Welcome")
    @await Html.PartialAsync("Partials/_QuickActions")
    @await Html.PartialAsync("Partials/_SystemStatus")
    @await Html.PartialAsync("Partials/_RecentActivities")
</section>

@await Html.PartialAsync("Partials/Modal/_Help")

@section Scripts {
    @await Html.PartialAsync("Partials/_Scripts")
}
```

**路徑差異說明:**功能頁 Partial 位於 `Partials/{Feature}/` 子目錄,組合頁 Partial 直接位於 `Partials/` 根目錄(因無功能分類概念)。

---

### §4.4 全域 Partial 規範

所有 Partial 必須遵守:

- 必須:頭部設定 `Layout = null;`
- 必須:強型別 `_SearchResults` 使用 `@model List<T>`
- 必須:強型別 Modal Partial 使用 `@model T?`(null 對應新增情境)
- 允許:畫面內容 Partial 直接讀取 `User.FindFirst(...)` 取得 Claims 資料
- 允許:與 HTML 緊密耦合的 JS(如圖表初始化)在 Partial 內直接內嵌 `<script>`
- 禁止:在 Partial 內嵌的 `<script>` 中呼叫跨 Partial 的業務函式(如 `Search()`、`Submit()`)

---

### §4.5 Modal 使用規範

**必須:**
- Modal 以標準 Bootstrap 結構定義於 `Modal/` 子目錄的 Partial
- 使用 `showModal()` / `closeModal()` 開關 Modal
- 動態載入時傳入 `url`、`method`、`data`、`container` 參數

```javascript
// 正確:按鈕 onclick 觸發
showModal('featureFormModal', {
    url: '@Url.Action("LoadFeatureForm", "Feature")',
    method: 'GET',
    data: { id: null },
    container: 'featureFormModalContent'
})
```

**禁止:**
- 以空容器(`<div id="modalContainer"></div>`)等待 AJAX 注入 HTML
- 以 JS 組裝 Modal HTML
- 使用 Bootstrap 原生 `.modal('show')` 直接操作(統一用 `showModal`)

**Modal 尺寸規則:**

| 類型 | 尺寸 class |
| --- | --- |
| 表單 Modal | `modal-lg` |
| 說明 Modal | `modal-xl` |
| 詳情 Modal | 預設(無額外 class) |

---

## §5 前端規範

### §5.1 AJAX 規範

**必須:**
- 統一使用 jQuery `$.ajax()`
- POST 請求攜帶 Anti-Forgery Token
- 回傳 JSON 格式統一: `{ success: boolean, message?: string, data?: any }`

```javascript
function Submit() {
    const $form = $('#FormDataExample');
    const formElement = $form[0];

    if (!formElement.checkValidity()) {
        formElement.reportValidity();
        return;
    }

    $.ajax({
        url: '@Url.Action("SubmitExample", "Example")',
        type: 'POST',
        data: $form.serialize(),
        success: (res) => {
            const message = res?.message ?? '[成功] 操作完成';
            showToast(message, resolveToastType(message));
            closeModal('exampleFormModal');
            Search();
        },
        error: () => showToast('[失敗] 系統發生錯誤', 'error')
    });
}

// Toast 類型解析(依訊息前綴判斷)
function resolveToastType(message) {
    return (message ?? '').includes('[失敗]') ? 'error' : 'success';
}
```

**Controller 回傳格式:**

```csharp
// 成功
return Json(new { success = true, message = "[成功] 操作完成" });
// 失敗
return Json(new { success = false, message = "[失敗] 原因說明" });
```

**禁止:**
- 在 JS 手動驗證必填欄位(使用 HTML5 `required`)
- 混用 `fetch` 與 `$.ajax`
- 省略錯誤處理(`error` callback)
- 在 JS 組裝任何 HTML

### §5.2 事件綁定規範

**預設:按鈕 `onclick` 直接觸發**

```html
<button type="button" onclick="submitForm()">送出</button>
```

**例外:動態內容使用委派事件**

當元素由 AJAX 動態產生,或同一頁面多次載入 Partial 時:

```javascript
$(document)
    .off('click.feature', '.js-submit-example')
    .on('click.feature', '.js-submit-example', submitForm);
```

**規則:**
- 必須:委派事件使用命名空間(`click.feature`)
- 必須:綁定前先 `.off()` 再 `.on()`,避免重複綁定
- 必須:動態篩選事件使用命名空間區隔(如 `.rolesPage`、`.usersPage`)

### §5.3 表單設計規範

**佈局原則:**
- 標題與輸入框並行,節省垂直空間
- 欄位採 `form-control-sm` 尺寸
- Modal 表單一律 `modal-lg`
- 按鈕採 `btn-sm`,群組用 `d-flex justify-content-end gap-2`

```html
<div class="row g-2 align-items-center">
    <div class="col-auto" style="width: 90px;">
        <label class="col-form-label col-form-label-sm">
            欄位名<span class="text-danger">*</span>
        </label>
    </div>
    <div class="col">
        <input type="text" class="form-control form-control-sm" required>
    </div>
</div>
```

**驗證原則:**
- 必須:使用 HTML5 原生驗證(`required`、`type="email"`、`pattern` 等)
- 禁止:在 JS 手動重寫驗證邏輯
- 伺服端錯誤使用 `invalid-feedback` 顯示

### §5.4 命名規範

**JavaScript 函式:**
- 動詞開頭,大駝峰(頁面功能): `Search()`、`Submit()`、`Delete(id)`
- 動詞開頭,小駝峰(輔助函式): `resolveToastType()`、`bindFilters()`、`applyFilters()`
- 事件處理器: `onSearchInput`、`onStatusChange`

**HTML ID:**
- kebab-case:`user-form-modal`、`role-results-container`

**CSS class(JS 操作專用):**
- `js-` 前綴:`js-submit-form`、`js-open-detail`

**Partial 內 JS 主要函式命名對應表:**

| 功能 | 函式名稱 |
| --- | --- |
| 載入/搜尋列表 | `Search()` |
| 提交表單 | `Submit()` |
| 刪除資料 | `Delete(id)` |
| 套用篩選 | `applyFilters()` (或 `applyXxxFilters()`) |
| 綁定篩選事件 | `bindFilters()` (或 `bindXxxFilters()`) |
| 解析 Toast 類型 | `resolveToastType(message)` |

---

## §6 Scripts Partial 結構規範

`_Scripts.cshtml` 為每個功能頁面的 JavaScript 集中位置,結構如下:

```javascript
<script>
    // 1. 頁面層級變數(DataTable 實例等)
    let featureTable;

    // 2. 初始化
    $(document).ready(() => {
        window.lucide?.createIcons?.();
        Search();
    });

    // 3. 主要操作函式
    function Search() {
        const $container = $('#featureResultsContainer');
        $.ajax({
            url: '@Url.Action("SearchFeature", "Feature")',
            type: 'GET',
            success: (html) => {
                $container.html(html);
                window.lucide?.createIcons?.();
                HNBDataTable.autoInit($container);
                featureTable = $('#featureTable').DataTable();
                bindFilters();
                applyFilters();
            },
            error: () => showToast('[失敗] 無法載入資料，請稍後再試', 'error')
        });
    }

    function bindFilters() {
        $('#searchInput')
            .off('input.featurePage')
            .on('input.featurePage', function () {
                featureTable?.search(this.value).draw();
            });

        $('#statusFilter')
            .off('change.featurePage')
            .on('change.featurePage', () => applyFilters());
    }

    function applyFilters() {
        const statusFilter = $('#statusFilter').val();
        $.fn.dataTable.ext.search = [];
        $.fn.dataTable.ext.search.push((settings, data) => {
            if (settings.nTable?.id !== 'featureTable') return true;
            const status = data[2] ?? '';
            return !statusFilter
                || (statusFilter === 'true' && status.includes('啟用'))
                || (statusFilter === 'false' && status.includes('停用'));
        });
        featureTable?.draw();
    }

    function Submit() {
        const $form = $('#FormDataFeature');
        if (!$form[0].checkValidity()) { $form[0].reportValidity(); return; }
        $.ajax({
            url: '@Url.Action("SubmitFeature", "Feature")',
            type: 'POST',
            data: $form.serialize(),
            success: (res) => {
                const message = res?.message ?? '[成功] 已儲存';
                showToast(message, resolveToastType(message));
                closeModal('featureFormModal');
                Search();
            },
            error: () => showToast('[失敗] 提交失敗，請聯絡系統管理員', 'error')
        });
    }

    function Delete(id) {
        if (!confirm('確定要刪除？')) return;
        $.ajax({
            url: '@Url.Action("Delete", "Feature")',
            type: 'POST',
            data: { id },
            success: (res) => {
                const message = res?.message ?? '[成功] 已刪除';
                showToast(message, resolveToastType(message));
                Search();
            },
            error: () => showToast('[失敗] 無法刪除，請稍後再試', 'error')
        });
    }

    function resolveToastType(message) {
        return (message ?? '').includes('[失敗]') ? 'error' : 'success';
    }
</script>
```

**規範:**
- 必須:`_Scripts.cshtml` 頭部設定 `Layout = null;`
- 必須:頁面 DataTable 實例宣告於 Script 頂層,供篩選函式存取
- 必須:Lucide 圖示在 AJAX 回傳後重新初始化(`window.lucide?.createIcons?.()`)
- 必須:DataTable 在 AJAX 回傳後重新初始化(`HNBDataTable.autoInit($container)`)
- 禁止:在 Scripts Partial 以 JS 組裝任何 HTML 字串

---

## §7 合規判定

出現下列任一情況即視為偏離本規範,必須修正:

| 編號 | 偏離情況 | 違反條款 |
| --- | --- | --- |
| V-01 | Repository 使用 `Get*` 命名 | §2.2.3 |
| V-02 | Repository 內有業務規則或資料轉換 | §2.2.4 |
| V-03 | Repository/Service/Controller 使用 `async/await` | §2.2.4、§2.3.6、§2.4.4 |
| V-04 | Repository/Service/Controller 使用 `try...catch` | §2.2.4、§2.3.6、§2.4.4 |
| V-05 | Service 使用 `Query*` 或 `Get*` 命名 | §2.3.3 |
| V-06 | Service `Create*` 回傳非 `(bool, string)` 格式 | §2.3.4 |
| V-07 | Service 回傳訊息未以 `[成功]`/`[失敗]` 開頭 | §2.3.4 |
| V-08 | Controller 內有業務邏輯 | §2.4.1 |
| V-09 | Controller Action 使用 `Get*` 命名 | §2.4.3 |
| V-10 | Controller 有多於一個 `Delete` 方法 | §2.4.4 |
| V-11 | Model 檔案被手動修改 | §2.1.2 |
| V-12 | 列表資料以 `ViewBag` 傳遞(非 Modal 情況) | §3.1 |
| V-13 | 單一值以 `@model` 傳遞 | §3.1 |
| V-14 | 空值改變 DOM 結構或元件樣式 | §3.3 |
| V-15 | 主頁面含有業務資料讀取、內嵌 CSS 或內嵌 JS | §4.1 |
| V-16 | `_Styles` 或 `_Scripts` Partial 缺少(即使內容為空也必須建立) | §4.1、§4.2.1、§4.2.2 |
| V-17 | Modal 未於主頁面預先引用,以空容器等待注入 | §4.1、§4.5 |
| V-17a | Partial 未設定 `Layout = null;` | §4.4 |
| V-17b | Partial 內嵌 `<script>` 中呼叫跨 Partial 的業務函式(如 `Search()`) | §4.4 |
| V-18 | JS 手動驗證必填欄位 | §5.1 |
| V-19 | JS 組裝任何 HTML 字串 | §5.1 |
| V-20 | 委派事件未使用命名空間或未先 `.off()` | §5.2 |

---

## 附錄 A 完整功能開發清單

開發新功能時,依下列順序完成所有項目:

### A.1 後端

- [ ] 確認或建立 Repository 查詢來源(`Valid*`)
- [ ] 新增 Repository 查詢方法(`Query*List`、`Query*`)
- [ ] 新增 Repository 寫入方法(`Insert*`、`Delete*`)
- [ ] 新增 Service 載入方法(`Load*List`、`Load*`)
- [ ] 新增或更新 `ViewBagModel` 設定
- [ ] 新增 Service 業務方法(`Create*`、`Delete*`)
- [ ] 新增 Controller Actions(主頁面、Search*、Load*Form、Load*Detail、Submit*、Delete)
- [ ] 確認 Controller 繼承 `BaseController`

### A.2 前端

- [ ] 建立主頁面 `{Feature}.cshtml`,設定 ViewData,引用所有 Partial 與 Modal
- [ ] 建立 `Partials/{Feature}/_Styles.cshtml`(必須,無內容時放空白佔位註解)
- [ ] 建立 `Partials/{Feature}/_Control.cshtml`
- [ ] 建立 `Partials/{Feature}/_SearchResults.cshtml`(強型別 `@model List<T>`)
- [ ] 建立 `Partials/{Feature}/Modal/_FormData.cshtml`(強型別 `@model T?`)
- [ ] 建立 `Partials/{Feature}/Modal/_Help.cshtml`
- [ ] 建立 `Partials/{Feature}/Modal/_Detail.cshtml`(或 `_Permissions.cshtml`)
- [ ] 建立 `Partials/{Feature}/_Scripts.cshtml`(必須,無內容時放空白佔位註解),實作 `Search()`、`Submit()`、`Delete(id)` 等主要函式

---

## 附錄 B 命名速查

### B.1 後端命名

| 層次 | 類型 | 格式 | 範例 |
| --- | --- | --- | --- |
| Repository | 查詢來源 | `Valid{表名}s` | `ValidUsers` |
| Repository | 列表查詢 | `Query{表名}List` | `QueryUserList()` |
| Repository | 單一查詢 | `Query{表名}` | `QueryUser(int? id)` |
| Repository | 新增/更新 | `Insert{表名}` | `InsertUser(data)` |
| Repository | 刪除 | `Delete{表名}` | `DeleteUser(int id)` |
| Service | 列表載入 | `Load{表名}List` | `LoadUserList()` |
| Service | 單一載入 | `Load{表名}` | `LoadUser(int id)` |
| Service | 新增/更新 | `Create{表名}` | `CreateUser(data)` |
| Service | 刪除 | `Delete{表名}` | `DeleteUser(int id)` |
| Service | ViewBag 設定 | `ViewBagModel` | `ViewBagModel(viewBag)` |
| Controller | 主頁面 | `{功能名}()` | `Users()` |
| Controller | 搜尋 | `Search{功能名}()` | `SearchUsers()` |
| Controller | 載入表單 | `Load{功能名}Form` | `LoadUserForm(int? id)` |
| Controller | 載入詳情 | `Load{功能名}Detail` | `LoadUserDetail(int id)` |
| Controller | 提交 | `Submit{功能名}` | `SubmitUser(form)` |
| Controller | 刪除 | `Delete` | `Delete(int id)` |

### B.2 前端命名

| 類型 | 格式 | 範例 |
| --- | --- | --- |
| 主要功能函式 | 大駝峰 | `Search()`、`Submit()`、`Delete(id)` |
| 輔助函式 | 小駝峰 | `bindFilters()`、`resolveToastType()` |
| 事件處理器 | `on` 前綴,小駝峰 | `onSearchInput`、`onStatusChange` |
| HTML ID | kebab-case | `user-form-modal`、`role-table` |
| JS 專用 class | `js-` 前綴 | `js-submit-form`、`js-open-detail` |
| 事件命名空間 | `{功能}Page` | `.usersPage`、`.rolesPage` |

---

## 附錄 C 訊息格式規範

### C.1 回傳訊息前綴

所有 Service 業務方法的回傳訊息必須以下列前綴開頭:

| 前綴 | 用途 | 範例 |
| --- | --- | --- |
| `[成功]` | 操作成功 | `[成功] 使用者已建立` |
| `[失敗]` | 操作失敗 | `[失敗] 名稱已存在` |
| `[提醒]` | 警告或提示(限 Razor) | `[提醒] 尚無資料` |

### C.2 前端 Toast 判定

`resolveToastType(message)` 依訊息前綴自動判斷 Toast 類型:

```javascript
function resolveToastType(message) {
    return (message ?? '').includes('[失敗]') ? 'error' : 'success';
}
```

---

**文件終**