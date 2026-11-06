import { useEffect, useState } from "react";

type Screen =
  | "flow"
  | "onboarding"
  | "home"
  | "meetings"
  | "models"
  | "settings"
  | "menubar"
  | "translate"
  | "captions"
  | "errors"
  | "components";

type IconName =
  | "grid"
  | "home"
  | "meeting"
  | "model"
  | "settings"
  | "menu"
  | "translate"
  | "caption"
  | "alert"
  | "chevron"
  | "search"
  | "copy"
  | "pin"
  | "close"
  | "play"
  | "stop"
  | "download"
  | "folder"
  | "check"
  | "pause"
  | "more"
  | "arrow"
  | "external"
  | "edit";

const iconPaths: Record<IconName, React.ReactNode> = {
  grid: (
    <>
      <rect x="3" y="3" width="7" height="7" rx="1" />
      <rect x="14" y="3" width="7" height="7" rx="1" />
      <rect x="3" y="14" width="7" height="7" rx="1" />
      <rect x="14" y="14" width="7" height="7" rx="1" />
    </>
  ),
  home: (
    <>
      <path d="m3 11 9-8 9 8" />
      <path d="M5 10v10h14V10M9 20v-6h6v6" />
    </>
  ),
  meeting: (
    <>
      <rect x="3" y="5" width="18" height="16" rx="2" />
      <path d="M16 3v4M8 3v4M3 10h18M8 14h3M8 17h7" />
    </>
  ),
  model: (
    <>
      <rect x="5" y="5" width="14" height="14" rx="3" />
      <path d="M9 9h6v6H9zM9 1v4M15 1v4M9 19v4M15 19v4M1 9h4M19 9h4M1 15h4M19 15h4" />
    </>
  ),
  settings: (
    <>
      <circle cx="12" cy="12" r="3" />
      <path d="M19.4 15a1.7 1.7 0 0 0 .34 1.88l.06.06-2.83 2.83-.06-.06a1.7 1.7 0 0 0-1.88-.34 1.7 1.7 0 0 0-1.03 1.56V21h-4v-.08A1.7 1.7 0 0 0 9 19.37a1.7 1.7 0 0 0-1.88.34l-.06.06-2.83-2.83.06-.06A1.7 1.7 0 0 0 4.63 15 1.7 1.7 0 0 0 3.08 14H3v-4h.08A1.7 1.7 0 0 0 4.63 9a1.7 1.7 0 0 0-.34-1.88l-.06-.06 2.83-2.83.06.06A1.7 1.7 0 0 0 9 4.63h.01A1.7 1.7 0 0 0 10 3.08V3h4v.08A1.7 1.7 0 0 0 15 4.63a1.7 1.7 0 0 0 1.88-.34l.06-.06 2.83 2.83-.06.06A1.7 1.7 0 0 0 19.37 9v.01A1.7 1.7 0 0 0 20.92 10H21v4h-.08A1.7 1.7 0 0 0 19.4 15Z" />
    </>
  ),
  menu: (
    <>
      <path d="M4 6h16M4 12h16M4 18h16" />
    </>
  ),
  translate: (
    <>
      <path d="M4 5h10M9 3v2M6 9c1.5 3 3.5 5 7 7M13 7c-1 4-4 7-9 9M14 20l4-10 4 10M15.5 17h5" />
    </>
  ),
  caption: (
    <>
      <rect x="2" y="4" width="20" height="16" rx="2" />
      <path d="M6 9h6M6 13h10M6 17h8" />
    </>
  ),
  alert: (
    <>
      <path d="M12 3 2.5 20h19L12 3Z" />
      <path d="M12 9v5M12 17.5v.5" />
    </>
  ),
  chevron: <path d="m9 18 6-6-6-6" />,
  search: (
    <>
      <circle cx="11" cy="11" r="7" />
      <path d="m20 20-4-4" />
    </>
  ),
  copy: (
    <>
      <rect x="8" y="8" width="12" height="12" rx="2" />
      <path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3" />
    </>
  ),
  pin: (
    <>
      <path d="m14 4 6 6-3 1-4 4-1 5-2-2-4 4-1-1 4-4-2-2 5-1 4-4 1-3Z" />
    </>
  ),
  close: <path d="M6 6l12 12M18 6 6 18" />,
  play: <path d="m8 5 11 7-11 7V5Z" />,
  stop: <rect x="6" y="6" width="12" height="12" rx="1" />,
  download: (
    <>
      <path d="M12 3v12m0 0 5-5m-5 5-5-5M4 20h16" />
    </>
  ),
  folder: <path d="M3 6h7l2 2h9v11H3V6Z" />,
  check: <path d="m5 12 4 4L19 6" />,
  pause: <path d="M9 5v14M15 5v14" />,
  more: (
    <>
      <circle cx="5" cy="12" r="1" />
      <circle cx="12" cy="12" r="1" />
      <circle cx="19" cy="12" r="1" />
    </>
  ),
  arrow: <path d="M5 12h14m-5-5 5 5-5 5" />,
  external: (
    <>
      <path d="M14 4h6v6M20 4l-9 9" />
      <path d="M18 13v7H4V6h7" />
    </>
  ),
  edit: (
    <>
      <path d="m4 20 4-1 11-11-3-3L5 16l-1 4Z" />
      <path d="m14 7 3 3" />
    </>
  ),
};

function Icon({ name, size = 18 }: { name: IconName; size?: number }) {
  return (
    <svg
      className="icon"
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      {iconPaths[name]}
    </svg>
  );
}

function Button({
  children,
  onClick,
  primary = false,
  danger = false,
  disabled = false,
  icon,
}: {
  children: React.ReactNode;
  onClick?: () => void;
  primary?: boolean;
  danger?: boolean;
  disabled?: boolean;
  icon?: IconName;
}) {
  return (
    <button
      disabled={disabled}
      onClick={onClick}
      className={`btn ${primary ? "primary" : ""} ${danger ? "danger" : ""}`}
    >
      {icon && <Icon name={icon} size={16} />}
      <span>{children}</span>
    </button>
  );
}

function Toggle({ on = true, onChange }: { on?: boolean; onChange?: () => void }) {
  return (
    <button aria-label="切换" onClick={onChange} className={`toggle ${on ? "on" : ""}`}>
      <span />
    </button>
  );
}

const nav: { id: Screen; label: string; icon: IconName }[] = [
  { id: "flow", label: "流程总览", icon: "grid" },
  { id: "onboarding", label: "首次启动", icon: "play" },
  { id: "menubar", label: "菜单栏", icon: "menu" },
  { id: "home", label: "主窗口", icon: "home" },
  { id: "translate", label: "划词翻译", icon: "translate" },
  { id: "captions", label: "实时字幕", icon: "caption" },
  { id: "errors", label: "全局错误", icon: "alert" },
  { id: "components", label: "组件库", icon: "grid" },
];

export default function App() {
  const [screen, setScreen] = useState<Screen>("flow");
  const [notice, setNotice] = useState("");
  const [modelReady, setModelReady] = useState(false);
  const [sessionSaved, setSessionSaved] = useState(false);
  const [theme, setTheme] = useState<"light" | "dark">("light");

  const go = (next: Screen) => {
    setScreen(next);
    setNotice("");
  };

  return (
    <div className="prototype-shell" data-theme={theme}>
      <header className="prototype-header">
        <div className="brand-block">
          <div className="brand-mark">L</div>
          <div>
            <strong>LingoLens</strong>
            <span>macOS 高保真交互原型</span>
          </div>
        </div>
        <nav className="frame-nav" aria-label="原型帧">
          {nav.map((item) => (
            <button
              key={item.id}
              className={screen === item.id ? "active" : ""}
              onClick={() => go(item.id)}
            >
              <Icon name={item.icon} size={16} />
              {item.label}
            </button>
          ))}
        </nav>
        <div className="prototype-meta">
          <button
            className="theme-toggle"
            onClick={() => setTheme(theme === "light" ? "dark" : "light")}
          >
            <span>{theme === "light" ? "☼" : "☾"}</span>
            {theme === "light" ? "浅色" : "深色"}
          </button>
        </div>
      </header>
      <main className="canvas">
        <div className="canvas-label">
          <span>原型画布</span>
          <span>{screen === "flow" ? "点击节点开始体验" : "所有按钮均可点击探索"}</span>
        </div>
        {screen === "flow" && <FlowMap go={go} />}
        {screen === "onboarding" && <Onboarding onDone={() => go("home")} />}
        {screen === "menubar" && (
          <MenuBar
            go={go}
            onSaved={() => {
              setSessionSaved(true);
              setNotice("会议已保存");
            }}
          />
        )}
        {screen === "home" && (
          <MainWindow page="home" go={go} modelReady={modelReady} sessionSaved={sessionSaved} />
        )}
        {screen === "meetings" && (
          <MainWindow page="meetings" go={go} modelReady={modelReady} sessionSaved />
        )}
        {screen === "models" && (
          <MainWindow page="models" go={go} modelReady={modelReady} setModelReady={setModelReady} />
        )}
        {screen === "settings" && <MainWindow page="settings" go={go} modelReady={modelReady} />}
        {screen === "translate" && <TranslateWindow />}
        {screen === "captions" && (
          <CaptionWindow
            onStop={() => {
              setSessionSaved(true);
              setNotice("会议已保存");
            }}
          />
        )}
        {screen === "errors" && <ErrorGallery />}
        {screen === "components" && <ComponentLibrary />}
        {notice && (
          <div className="toast">
            <Icon name="check" size={18} />
            <div>
              <strong>{notice}</strong>
              <span>转写已保存在“会议”中</span>
            </div>
            <button onClick={() => go("meetings")}>查看会议</button>
            <button aria-label="关闭" onClick={() => setNotice("")}>
              <Icon name="close" size={15} />
            </button>
          </div>
        )}
      </main>
    </div>
  );
}

function FlowMap({ go }: { go: (s: Screen) => void }) {
  const flows = [
    {
      n: "01",
      title: "首次启动",
      desc: "完成本地环境、模型与权限准备",
      steps: [
        ["欢迎", "onboarding"],
        ["环境准备", "onboarding"],
        ["权限授权", "onboarding"],
        ["首页", "home"],
      ],
    },
    {
      n: "02",
      title: "划词翻译",
      desc: "从任意应用唤起轻量翻译浮窗",
      steps: [
        ["选中文字", "translate"],
        ["按下 ⌥D", "translate"],
        ["翻译浮窗", "translate"],
        ["复制 / 固定", "translate"],
      ],
    },
    {
      n: "03",
      title: "会议助手",
      desc: "字幕、转写、纪要一条链路完成",
      steps: [
        ["菜单栏", "menubar"],
        ["音频会话", "captions"],
        ["会议详情", "meetings"],
        ["生成并导出", "meetings"],
      ],
    },
    {
      n: "04",
      title: "模型管理",
      desc: "下载模型并切换为常驻模型",
      steps: [
        ["模型页", "models"],
        ["下载模型", "models"],
        ["设为常驻", "models"],
        ["首页就绪", "home"],
      ],
    },
  ];
  return (
    <section className="flow-board">
      <div className="board-intro">
        <div>
          <span className="eyebrow">产品架构 / 关键流程</span>
          <h1>所有能力，本机完成。</h1>
          <p>不连接云端。翻译、转写和纪要生成均由 Apple Silicon 本地运行。</p>
        </div>
        <div className="legend">
          <span>
            <i className="dot filled" />
            可点击节点
          </span>
          <span>
            <i className="dot" />
            系统状态
          </span>
          <span>⌘ 快捷键</span>
        </div>
      </div>
      <div className="flows">
        {flows.map((flow) => (
          <div className="flow-row" key={flow.n}>
            <div className="flow-info">
              <span>{flow.n}</span>
              <div>
                <strong>{flow.title}</strong>
                <small>{flow.desc}</small>
              </div>
            </div>
            <div className="flow-steps">
              {flow.steps.map(([label, target], i) => (
                <div className="step-wrap" key={label}>
                  <button onClick={() => go(target as Screen)}>
                    <b>{i + 1}</b>
                    <span>{label}</span>
                  </button>
                  {i < flow.steps.length - 1 && (
                    <div className="connector">
                      <span />
                      <Icon name="chevron" size={14} />
                    </div>
                  )}
                </div>
              ))}
            </div>
            <button className="enter-flow" onClick={() => go(flow.steps[0][1] as Screen)}>
              进入流程 <Icon name="arrow" size={16} />
            </button>
          </div>
        ))}
      </div>
      <div className="frame-index">
        <span>界面帧</span>
        {["A 菜单栏", "B 首次启动", "C 主窗口", "D 翻译浮窗", "E 字幕浮窗", "F 错误状态"].map(
          (x) => (
            <div key={x}>{x}</div>
          ),
        )}
      </div>
    </section>
  );
}

function WindowChrome({
  title,
  children,
  wide = false,
}: {
  title: string;
  children: React.ReactNode;
  wide?: boolean;
}) {
  return (
    <div className={`mac-window ${wide ? "wide" : ""}`}>
      <div className="titlebar">
        <div className="traffic">
          <i />
          <i />
          <i />
        </div>
        <span>{title}</span>
        <div />
      </div>
      {children}
    </div>
  );
}

function Onboarding({ onDone }: { onDone: () => void }) {
  const [step, setStep] = useState(0);
  const [progress, setProgress] = useState(0);
  useEffect(() => {
    if (step !== 1 || progress >= 100) return;
    const timer = window.setInterval(() => setProgress((p) => Math.min(100, p + 5)), 90);
    return () => window.clearInterval(timer);
  }, [step, progress]);
  const data = [
    {
      label: "欢迎",
      title: "欢迎使用 LingoLens",
      desc: "在你的 Mac 上完成翻译、实时字幕和会议纪要。数据不会离开设备。",
    },
    {
      label: "运行环境",
      title: "准备本地运行环境",
      desc: "正在检查 Apple Silicon 与安装 MLX 运行时。",
    },
    {
      label: "选择模型",
      title: "下载一个本地模型",
      desc: "可随时在“模型”中导入或更换。推荐模型适合大多数 Mac。",
    },
    {
      label: "授予权限",
      title: "允许 LingoLens 工作",
      desc: "这些权限仅用于读取选中文字和本地音频。",
    },
    { label: "试一试", title: "一切准备就绪", desc: "在任意应用中选中一段文字，然后按下快捷键。" },
  ];
  return (
    <WindowChrome title="LingoLens 设置">
      <div className="onboarding">
        <aside className="onboard-steps">
          {data.map((x, i) => (
            <div
              key={x.label}
              className={`${i === step ? "current" : ""} ${i < step ? "done" : ""}`}
            >
              <i>{i < step ? "✓" : i + 1}</i>
              <span>{x.label}</span>
            </div>
          ))}
        </aside>
        <section className="onboard-content">
          <div className="onboard-graphic">
            {step === 0 ? (
              <div className="wire-logo">LL</div>
            ) : step === 4 ? (
              <div className="key-demo">
                <kbd>⌥</kbd>
                <kbd>D</kbd>
              </div>
            ) : (
              <Icon name={step === 1 ? "settings" : step === 2 ? "model" : "check"} size={54} />
            )}
          </div>
          <span className="step-count">
            第 {step + 1} 步，共 {data.length} 步
          </span>
          <h1>{data[step].title}</h1>
          <p>{data[step].desc}</p>
          {step === 1 && (
            <div className="setup-block">
              <div>
                <span>安装 MLX 运行时…</span>
                <b>{progress}%</b>
              </div>
              <div className="progress">
                <i style={{ width: `${progress}%` }} />
              </div>
              <small>
                {progress < 40 ? "检查系统环境" : progress < 80 ? "安装本地组件" : "正在完成设置"}
              </small>
            </div>
          )}
          {step === 2 && (
            <div className="model-choice">
              <label className="selected">
                <input type="radio" defaultChecked />
                <div>
                  <strong>Qwen3 4B · 推荐</strong>
                  <span>4 位量化 · 约 2.7 GB · 8 GB 内存可用</span>
                </div>
                <b>下载</b>
              </label>
              <label>
                <input type="radio" />
                <div>
                  <strong>选择本地模型文件夹</strong>
                  <span>扫描已有 MLX 模型</span>
                </div>
                <Icon name="folder" size={18} />
              </label>
            </div>
          )}
          {step === 3 && (
            <div className="permission-list">
              {["辅助功能", "麦克风", "系统音频录制"].map((p, i) => (
                <div key={p}>
                  <Icon name={i === 0 ? "translate" : i === 1 ? "caption" : "meeting"} size={19} />
                  <span>
                    <strong>{p}</strong>
                    <small>
                      {i === 0
                        ? "读取其他应用中选中的文字"
                        : i === 1
                          ? "转写你的发言"
                          : "转写会议中对方的发言"}
                    </small>
                  </span>
                  <b className={i < 2 ? "granted" : ""}>{i < 2 ? "已允许" : "去授权"}</b>
                </div>
              ))}
            </div>
          )}
          {step === 4 && (
            <div className="try-box">
              <span>快捷键</span>
              <kbd>⌥ D</kbd>
              <small>选中文字后按下</small>
            </div>
          )}
          <div className="onboard-actions">
            {step > 0 && <Button onClick={() => setStep(step - 1)}>返回</Button>}
            <span />
            <Button
              primary
              disabled={step === 1 && progress < 100}
              onClick={() => (step === data.length - 1 ? onDone() : setStep(step + 1))}
            >
              {step === data.length - 1 ? "进入 LingoLens" : step === 2 ? "下载并继续" : "继续"}
            </Button>
          </div>
        </section>
      </div>
    </WindowChrome>
  );
}

function MenuBar({ go, onSaved }: { go: (s: Screen) => void; onSaved: () => void }) {
  const [running, setRunning] = useState(false);
  const [seconds, setSeconds] = useState(0);
  const [source, setSource] = useState("两者");
  const [captions, setCaptions] = useState(true);
  const [record, setRecord] = useState(true);
  const [otherLanguage, setOtherLanguage] = useState("英语");
  const [myLanguage, setMyLanguage] = useState("中文（普通话）");
  useEffect(() => {
    if (!running) return;
    const timer = window.setInterval(() => setSeconds((x) => x + 1), 1000);
    return () => window.clearInterval(timer);
  }, [running]);
  const stop = () => {
    setRunning(false);
    if (record) onSaved();
  };
  const time = `00:${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
  return (
    <div className="desktop-stage">
      <div className="fake-menubar">
        <strong>⌘</strong>
        <span>文件</span>
        <span>编辑</span>
        <div />
        <span>中</span>
        <span>⌁</span>
        <button className="menu-app-icon">LL</button>
        <span>10:41</span>
      </div>
      <div className="menu-popover">
        <div className="popover-arrow" />
        <div className="model-status">
          <div className="model-cube">
            <Icon name="model" size={19} />
          </div>
          <div>
            <strong>Qwen3 4B MLX</strong>
            <span>
              <i className={running ? "pulse" : ""} /> {running ? "正在转写" : "已就绪 · 本地运行"}
            </span>
          </div>
          <button aria-label="模型设置" onClick={() => go("models")}>
            <Icon name="chevron" size={16} />
          </button>
        </div>
        <button
          className={`session-button ${running ? "running" : ""}`}
          onClick={() => (running ? stop() : setRunning(true))}
        >
          <Icon name={running ? "stop" : "caption"} size={21} />
          <span>
            {running ? time : "开始音频会话"}
            <small>{running ? "点击停止并保存" : "实时字幕与会议记录"}</small>
          </span>
        </button>
        {running && (
          <div className="audio-levels">
            <div>
              <span>
                <i className="record-dot" /> 对方
              </span>
              <div className="level-bars">
                {[3, 7, 11, 16, 9, 5, 13, 8].map((h, i) => (
                  <i key={i} style={{ height: h }} />
                ))}
              </div>
            </div>
            <div>
              <span>我</span>
              <div className="level-bars me-level">
                {[5, 12, 8, 15, 18, 10, 6, 4].map((h, i) => (
                  <i key={i} style={{ height: h }} />
                ))}
              </div>
            </div>
          </div>
        )}
        {running && captions && (
          <button className="floating-preview" onClick={() => go("captions")}>
            <span>字幕浮窗正在显示</span>
            <b>
              查看浮窗 <Icon name="external" size={13} />
            </b>
          </button>
        )}
        <div className="menu-section">
          <label>音频源</label>
          <div className="segmented">
            {["系统音频", "麦克风", "两者"].map((x) => (
              <button onClick={() => setSource(x)} className={source === x ? "active" : ""} key={x}>
                {x}
              </button>
            ))}
          </div>
          <div className="select-row">
            <span>对方语言</span>
            <button onClick={() => setOtherLanguage(otherLanguage === "英语" ? "日语" : "英语")}>
              {otherLanguage} <span>⌄</span>
            </button>
          </div>
          <div className="select-row">
            <span>我的语言</span>
            <button
              onClick={() =>
                setMyLanguage(myLanguage === "中文（普通话）" ? "英语" : "中文（普通话）")
              }
            >
              {myLanguage} <span>⌄</span>
            </button>
          </div>
          <div className="toggle-row">
            <span>显示字幕</span>
            <Toggle on={captions} onChange={() => setCaptions(!captions)} />
          </div>
          <div className="toggle-row">
            <span>记录会议</span>
            <Toggle on={record} onChange={() => setRecord(!record)} />
          </div>
        </div>
        <div className="menu-links">
          <button onClick={() => go("translate")}>
            <Icon name="translate" size={17} />
            <span>划词翻译</span>
            <kbd>⌥ D</kbd>
          </button>
          <button onClick={() => go("home")}>
            <Icon name="external" size={17} />
            <span>打开主窗口</span>
          </button>
          <button>
            <Icon name="close" size={17} />
            <span>退出 LingoLens</span>
            <kbd>⌘ Q</kbd>
          </button>
        </div>
      </div>
      <div className="stage-note">
        <b>A · 菜单栏下拉面板</b>
        <span>点击“开始音频会话”体验运行状态</span>
      </div>
    </div>
  );
}

const sideNav: { id: Screen; label: string; icon: IconName }[] = [
  { id: "home", label: "首页", icon: "home" },
  { id: "meetings", label: "会议", icon: "meeting" },
  { id: "models", label: "模型", icon: "model" },
  { id: "settings", label: "设置", icon: "settings" },
];

function MainWindow({
  page,
  go,
  modelReady = false,
  setModelReady,
  sessionSaved = false,
}: {
  page: Screen;
  go: (s: Screen) => void;
  modelReady?: boolean;
  setModelReady?: (v: boolean) => void;
  sessionSaved?: boolean;
}) {
  return (
    <WindowChrome title="LingoLens" wide>
      <div className="main-layout">
        <aside className="sidebar">
          <div className="sidebar-brand">
            <div className="brand-mark small">L</div>
            <strong>LingoLens</strong>
          </div>
          <nav>
            {sideNav.map((x) => (
              <button key={x.id} className={page === x.id ? "active" : ""} onClick={() => go(x.id)}>
                <Icon name={x.icon} size={18} />
                <span>{x.label}</span>
                {x.id === "meetings" && sessionSaved && <i />}
              </button>
            ))}
          </nav>
          <div className="sidebar-bottom">
            <span>
              <i className={modelReady ? "" : "loading"} />
              {modelReady ? "模型已就绪" : "模型未加载"}
            </span>
            <small>完全本地运行</small>
          </div>
        </aside>
        <section className="main-content">
          {page === "home" && (
            <HomePage go={go} modelReady={modelReady} sessionSaved={sessionSaved} />
          )}
          {page === "meetings" && <MeetingsPage />}
          {page === "models" && <ModelsPage onReady={() => setModelReady?.(true)} go={go} />}
          {page === "settings" && <SettingsPage />}
        </section>
      </div>
    </WindowChrome>
  );
}

function PageHeader({
  title,
  subtitle,
  children,
}: {
  title: string;
  subtitle: string;
  children?: React.ReactNode;
}) {
  return (
    <header className="page-header">
      <div>
        <h1>{title}</h1>
        <p>{subtitle}</p>
      </div>
      {children}
    </header>
  );
}

function HomePage({
  go,
  modelReady,
  sessionSaved,
}: {
  go: (s: Screen) => void;
  modelReady: boolean;
  sessionSaved: boolean;
}) {
  return (
    <div className="page-scroll">
      <PageHeader title="上午好" subtitle="所有服务均在本机运行，数据不会离开这台 Mac。">
        <Button onClick={() => go("menubar")} primary icon="caption">
          开始音频会话
        </Button>
      </PageHeader>
      {!modelReady && (
        <div className="alert-strip">
          <Icon name="alert" size={20} />
          <div>
            <strong>辅助功能权限需要重新授权</strong>
            <span>划词翻译目前无法读取其他应用中选中的文字。</span>
          </div>
          <Button>去授权</Button>
        </div>
      )}
      <div className="status-grid">
        <div className="status-card">
          <div className="card-heading">
            <span>常驻模型</span>
            <i className={modelReady ? "ready" : ""}>{modelReady ? "已就绪" : "未加载"}</i>
          </div>
          <h2>{modelReady ? "Qwen3 8B MLX" : "Qwen3 4B MLX"}</h2>
          <p>{modelReady ? "8B · 4 位量化 · 4.9 GB" : "4B · 4 位量化 · 2.7 GB"}</p>
          <div className="meter-line">
            <span>统一内存</span>
            <b>{modelReady ? "6.8 / 16 GB" : "3.1 / 16 GB"}</b>
          </div>
          <div className="meter">
            <i style={{ width: modelReady ? "43%" : "20%" }} />
          </div>
          <button onClick={() => go("models")}>
            管理模型 <Icon name="chevron" size={14} />
          </button>
        </div>
        <div className="status-card">
          <div className="card-heading">
            <span>本地运行时</span>
            <i className="ready">运行正常</i>
          </div>
          <div className="runtime-row">
            <div>
              <Icon name="model" size={21} />
            </div>
            <span>
              <strong>MLX 0.27.1</strong>
              <small>Apple Silicon · GPU 可用</small>
            </span>
            <Icon name="check" size={18} />
          </div>
          <div className="runtime-row">
            <div>
              <Icon name="caption" size={21} />
            </div>
            <span>
              <strong>系统语音识别</strong>
              <small>中文、英语已安装</small>
            </span>
            <Icon name="check" size={18} />
          </div>
          <button onClick={() => go("errors")}>
            状态与诊断 <Icon name="chevron" size={14} />
          </button>
        </div>
      </div>
      <section className="home-section">
        <div className="section-title">
          <h2>快捷操作</h2>
        </div>
        <div className="quick-grid">
          <button onClick={() => go("translate")}>
            <Icon name="copy" size={23} />
            <strong>翻译剪贴板</strong>
            <span>立即翻译已复制的内容</span>
          </button>
          <button onClick={() => go("translate")}>
            <Icon name="translate" size={23} />
            <strong>空白翻译窗</strong>
            <span>输入或粘贴任意文本</span>
          </button>
          <button onClick={() => go("menubar")}>
            <Icon name="caption" size={23} />
            <strong>开始会话</strong>
            <span>实时字幕并记录会议</span>
          </button>
        </div>
      </section>
      <section className="home-section">
        <div className="section-title">
          <h2>最近会议</h2>
          <button onClick={() => go("meetings")}>查看全部</button>
        </div>
        <div className="recent-list">
          <button onClick={() => go("meetings")}>
            <div className="date-tile">
              <b>{sessionSaved ? "18" : "17"}</b>
              <span>六月</span>
            </div>
            <span>
              <strong>{sessionSaved ? "产品同步会" : "海外市场周会"}</strong>
              <small>{sessionSaved ? "刚刚 · 32 分钟" : "昨天 14:30 · 48 分钟"}</small>
            </span>
            <i>已有纪要</i>
            <Icon name="chevron" size={17} />
          </button>
          <button onClick={() => go("meetings")}>
            <div className="date-tile">
              <b>16</b>
              <span>六月</span>
            </div>
            <span>
              <strong>客户需求访谈</strong>
              <small>周一 10:00 · 1 小时 12 分</small>
            </span>
            <i className="muted">仅转写</i>
            <Icon name="chevron" size={17} />
          </button>
        </div>
      </section>
    </div>
  );
}

function MeetingsPage() {
  const [generated, setGenerated] = useState(false);
  const [generating, setGenerating] = useState(false);
  const [query, setQuery] = useState("");
  const [split, setSplit] = useState(53);
  const [highlight, setHighlight] = useState("");
  const [editing, setEditing] = useState("");
  const [phase, setPhase] = useState(0);
  const generate = () => {
    setGenerating(true);
    setPhase(1);
    window.setTimeout(() => setPhase(2), 450);
    window.setTimeout(() => setPhase(3), 850);
    window.setTimeout(() => {
      setGenerating(false);
      setGenerated(true);
    }, 1100);
  };
  return (
    <div className="meeting-page">
      <aside className="meeting-list">
        <PageHeader title="会议" subtitle="共 12 条记录" />
        <div className="search">
          <Icon name="search" size={15} />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="搜索会议与转写"
          />
        </div>
        {["产品同步会", "海外市场周会", "客户需求访谈", "设计评审"].filter((x) => x.includes(query))
          .length === 0 && (
          <div className="list-empty">
            <div>
              <Icon name="search" size={21} />
            </div>
            <strong>没有匹配的会议</strong>
            <p>尝试使用其他关键词搜索转写内容。</p>
            <Button onClick={() => setQuery("")}>清除搜索</Button>
          </div>
        )}
        {["产品同步会", "海外市场周会", "客户需求访谈", "设计评审"]
          .filter((x) => x.includes(query))
          .map((x, i) => (
            <button className={i === 0 ? "active" : ""} key={x}>
              <div>
                <strong>{x}</strong>
                {i < 2 && <i>纪要</i>}
              </div>
              <span>{i === 0 ? "今天 10:08" : `${17 - i} 六月 · ${i + 1}:02:14`}</span>
              <p>{i === 0 ? "讨论了新版本上线时间与市场…" : "会议转写内容预览…"}</p>
            </button>
          ))}
      </aside>
      <section className="meeting-detail">
        <header>
          <div>
            <h2>产品同步会</h2>
            <p>今天 10:08 · 32 分钟 · 中文 / 英语</p>
          </div>
          <Button icon="more">更多</Button>
        </header>
        <div className="detail-tabs">
          <button className="active">转写与纪要</button>
          <button>会议信息</button>
        </div>
        <div className="detail-columns" style={{ gridTemplateColumns: `${split}% 6px 1fr` }}>
          <section className="transcript">
            <div className="pane-toolbar">
              <strong>转写</strong>
              <button>
                <Icon name="search" size={15} /> 搜索
              </button>
            </div>
            {[
              [
                "00:18",
                "对方",
                "Before we launch, I want to confirm the timeline.",
                "正式上线前，我想确认一下时间安排。",
              ],
              [
                "00:25",
                "我",
                "第一阶段计划在下周三完成。",
                "The first phase is planned for next Wednesday.",
              ],
              [
                "00:41",
                "对方",
                "That works. Who will own the final review?",
                "没问题。最终审核由谁负责？",
              ],
              [
                "00:48",
                "我",
                "我会和设计团队一起完成。",
                "I will work with the design team on it.",
              ],
            ].map((r, i) => (
              <article
                key={r[0]}
                id={`transcript-${r[0]}`}
                className={highlight === r[0] ? "highlighted" : ""}
              >
                <time>{r[0]}</time>
                <div>
                  <span className={i % 2 ? "me" : ""}>{r[1]}</span>
                  <p
                    contentEditable={editing === r[0]}
                    suppressContentEditableWarning
                    className={editing === r[0] ? "editing" : ""}
                    onKeyDown={(e) => {
                      if (e.key === "Enter" || e.key === "Escape") {
                        e.preventDefault();
                        setEditing("");
                      }
                    }}
                  >
                    {r[2]}
                  </p>
                  <small>{r[3]}</small>
                </div>
                <button title="编辑" onClick={() => setEditing(r[0])}>
                  <Icon name="edit" size={14} />
                </button>
              </article>
            ))}
          </section>
          <button
            className="split-handle"
            aria-label="调整分栏宽度"
            onPointerDown={(e) => {
              const startX = e.clientX;
              const start = split;
              const move = (event: PointerEvent) =>
                setSplit(Math.max(38, Math.min(68, start + (event.clientX - startX) / 8)));
              const up = () => {
                window.removeEventListener("pointermove", move);
                window.removeEventListener("pointerup", up);
              };
              window.addEventListener("pointermove", move);
              window.addEventListener("pointerup", up);
            }}
          >
            <i />
          </button>
          <section className="minutes">
            <div className="pane-toolbar">
              <strong>会议纪要</strong>
              {generated && (
                <button>
                  <Icon name="copy" size={15} /> 复制
                </button>
              )}
            </div>
            <div className="minute-options">
              <label>
                模板
                <select>
                  <option>标准会议纪要</option>
                  <option>项目复盘</option>
                  <option>客户访谈</option>
                </select>
              </label>
              <label>
                输出语言
                <select>
                  <option>简体中文</option>
                  <option>英语</option>
                </select>
              </label>
            </div>
            {!generated && !generating && (
              <div className="empty-minutes">
                <div>
                  <Icon name="meeting" size={28} />
                </div>
                <strong>还没有会议纪要</strong>
                <p>将使用完整转写在本机生成结构化纪要。</p>
                <Button primary onClick={generate}>
                  生成纪要
                </Button>
              </div>
            )}
            {generating && (
              <div className="generating">
                <div className="generation-ring">
                  <b>{phase}/3</b>
                </div>
                <strong>{phase < 3 ? `分段提炼 ${phase}/3` : "正在合并纪要"}</strong>
                <p>{phase < 3 ? "按时间段分析讨论、决策与行动项" : "去重并组织结构化内容"}</p>
                <div className="phase-track">
                  <i style={{ width: `${phase * 33}%` }} />
                </div>
                <Button onClick={() => setGenerating(false)} icon="stop">
                  停止
                </Button>
              </div>
            )}
            {generated && (
              <div className="markdown">
                <h1>产品同步会</h1>
                <h2>摘要</h2>
                <p>团队确认了第一阶段上线时间，并明确最终审核责任。</p>
                <h2>关键讨论</h2>
                <ul>
                  <li>第一阶段计划于下周三完成</li>
                  <li>最终审核由产品与设计团队共同负责</li>
                </ul>
                <h2>决策</h2>
                <ul>
                  <li>按原定计划推进，无需调整范围</li>
                </ul>
                <h2>行动项</h2>
                <button
                  className="action-item"
                  onClick={() => {
                    setHighlight("00:48");
                    document
                      .getElementById("transcript-00:48")
                      ?.scrollIntoView({ behavior: "smooth", block: "center" });
                    window.setTimeout(() => setHighlight(""), 1800);
                  }}
                >
                  <input type="checkbox" />
                  <span>
                    <b>完成最终设计审核</b>
                    <small>负责人：我 · 截止：下周二</small>
                  </span>
                  <time>定位 00:48</time>
                </button>
                <h2>待定问题</h2>
                <p>后续版本的本地化范围尚待确认。</p>
              </div>
            )}
            <div className="minute-footer">
              {generated ? (
                <>
                  <Button onClick={generate}>重新生成</Button>
                  <Button primary icon="download">
                    导出 .md
                  </Button>
                </>
              ) : (
                <span>模型：Qwen3 4B · 完全本地生成</span>
              )}
            </div>
          </section>
        </div>
      </section>
    </div>
  );
}

function ModelsPage({ onReady, go }: { onReady: () => void; go: (s: Screen) => void }) {
  const [downloading, setDownloading] = useState(false);
  const [downloaded, setDownloaded] = useState(false);
  const [progress, setProgress] = useState(0);
  const [paused, setPaused] = useState(false);
  useEffect(() => {
    if (!downloading || paused) return;
    const timer = window.setInterval(
      () =>
        setProgress((p) => {
          if (p >= 100) {
            setDownloading(false);
            setDownloaded(true);
            return 100;
          }
          return p + 4;
        }),
      80,
    );
    return () => window.clearInterval(timer);
  }, [downloading, paused]);
  return (
    <div className="page-scroll">
      <PageHeader title="模型" subtitle="管理存储在这台 Mac 上的 MLX 模型">
        <div className="header-actions">
          <Button icon="folder">导入文件夹</Button>
          <Button
            primary
            icon="download"
            onClick={() => {
              setProgress(0);
              setDownloading(true);
            }}
          >
            从 Hugging Face 下载
          </Button>
        </div>
      </PageHeader>
      {downloading && (
        <div className="download-card">
          <div>
            <div className="model-cube">
              <Icon name="download" size={19} />
            </div>
            <span>
              <strong>Qwen3-8B-4bit</strong>
              <small>
                {paused ? "下载已暂停" : "18.6 MB/s · 剩余约 2 分 14 秒"} ·{" "}
                {(progress * 0.049).toFixed(1)} / 4.9 GB
              </small>
            </span>
            <b>{progress}%</b>
          </div>
          <div className="progress">
            <i style={{ width: `${progress}%` }} />
          </div>
          <div className="download-actions">
            <Button icon={paused ? "play" : "pause"} onClick={() => setPaused(!paused)}>
              {paused ? "继续" : "暂停"}
            </Button>
            <button onClick={() => setDownloading(false)}>取消</button>
          </div>
        </div>
      )}
      <section className="model-section">
        <div className="section-title">
          <h2>
            已安装 <span>{downloaded ? "3" : "2"}</span>
          </h2>
          <small>占用 {downloaded ? "9.1" : "4.2"} GB</small>
        </div>
        <div className="model-table">
          <div className="table-head">
            <span>模型</span>
            <span>规格</span>
            <span>预计内存</span>
            <span>来源</span>
            <span>状态</span>
            <span />
          </div>
          {[
            ["Qwen3 4B MLX", "4B · 4 位", "3.1 GB", "下载", "常驻"],
            ["Llama 3.2 Vision", "3B · 4 位 · 视觉", "3.8 GB", "扫描", ""],
            ...(downloaded ? [["Qwen3 8B MLX", "8B · 4 位", "6.8 GB", "下载", ""]] : []),
          ].map((r, i) => (
            <div className="table-row" key={r[0]}>
              <span>
                <div className="model-cube">
                  <Icon name="model" size={18} />
                </div>
                <b>
                  {r[0]}
                  <small>{i === 1 ? "1.8 GB" : i === 2 ? "4.9 GB" : "2.4 GB"}</small>
                </b>
              </span>
              <span>{r[1]}</span>
              <span className="memory-cell">
                <b>{r[2]} / 16 GB</b>
                <i>
                  <em style={{ width: i === 2 ? "86%" : i === 1 ? "24%" : "20%" }} />
                </i>
              </span>
              <span>
                <i className="tag">{r[3]}</i>
              </span>
              <span>
                {r[4] ? (
                  <i className="ready-tag">
                    <span />
                    常驻
                  </i>
                ) : (
                  <button
                    className={`text-button ${i === 2 ? "memory-warning" : ""}`}
                    disabled={i === 2}
                    onClick={() => {
                      if (i === 2) return;
                      onReady();
                      go("home");
                    }}
                  >
                    {i === 2 ? "内存不足" : "加载"}
                  </button>
                )}
              </span>
              <button title="更多">
                <Icon name="more" size={17} />
              </button>
            </div>
          ))}
        </div>
      </section>
      <section className="runtime-panel">
        <div>
          <Icon name="settings" size={22} />
          <span>
            <strong>MLX 运行时</strong>
            <small>版本 0.27.1 · Apple M3 Pro · GPU 可用</small>
          </span>
        </div>
        <i>
          <span />
          运行正常
        </i>
        <button onClick={() => go("errors")}>
          查看日志 <Icon name="chevron" size={14} />
        </button>
      </section>
    </div>
  );
}

function SettingsPage() {
  const [section, setSection] = useState("通用");
  const groups = ["通用", "场景配置", "音频会话", "纪要模板", "权限"];
  return (
    <div className="settings-page">
      <aside>
        <h1>设置</h1>
        {groups.map((x) => (
          <button key={x} className={section === x ? "active" : ""} onClick={() => setSection(x)}>
            {x}
          </button>
        ))}
      </aside>
      <section>
        <PageHeader
          title={section}
          subtitle={
            section === "通用"
              ? "配置 LingoLens 的基础行为"
              : section === "场景配置"
                ? "为不同任务选择模型与生成参数"
                : `管理${section}相关选项`
          }
        />
        {section === "通用" && (
          <SettingsGroup title="语言与启动">
            <SettingRow label="默认目标语言" hint="用于划词翻译和剪贴板翻译">
              <select>
                <option>简体中文</option>
              </select>
            </SettingRow>
            <SettingRow label="划词翻译快捷键" hint="点击后按下新的组合键">
              <button className="key-recorder">⌥ D</button>
            </SettingRow>
            <SettingRow label="登录时启动" hint="在菜单栏中静默运行">
              <Toggle />
            </SettingRow>
            <SettingRow label="在 Dock 中显示" hint="默认仅显示在菜单栏">
              <Toggle on={false} />
            </SettingRow>
          </SettingsGroup>
        )}
        {section === "场景配置" && (
          <>
            {["划词翻译", "实时字幕", "会议纪要"].map((x, i) => (
              <SettingsGroup title={x} key={x}>
                <SettingRow label="使用模型" hint={i === 1 ? "字幕翻译优先低延迟" : "跟随常驻模型"}>
                  <select>
                    <option>Qwen3 4B MLX</option>
                  </select>
                </SettingRow>
                <SettingRow
                  label="温度"
                  hint={i === 2 ? "更高数值会增加表达多样性" : "保持翻译准确稳定"}
                >
                  <input type="range" defaultValue={i === 2 ? 40 : 20} />
                </SettingRow>
              </SettingsGroup>
            ))}
          </>
        )}
        {section === "音频会话" && (
          <SettingsGroup title="会话默认值">
            <SettingRow label="默认音频源" hint="新会话开始时使用">
              <select>
                <option>系统音频与麦克风</option>
              </select>
            </SettingRow>
            <SettingRow label="自动显示字幕" hint="会话开始时打开字幕浮窗">
              <Toggle />
            </SettingRow>
            <SettingRow label="自动记录会议" hint="停止后保存完整转写">
              <Toggle />
            </SettingRow>
          </SettingsGroup>
        )}
        {section === "纪要模板" && (
          <SettingsGroup title="模板">
            <div className="template-card">
              <strong>标准会议纪要</strong>
              <p>摘要、关键讨论、决策、行动项、待定问题</p>
              <Button>编辑模板</Button>
            </div>
            <div className="template-card">
              <strong>客户访谈</strong>
              <p>背景、需求、痛点、原话摘录、后续跟进</p>
              <Button>编辑模板</Button>
            </div>
            <Button primary>新建模板</Button>
          </SettingsGroup>
        )}
        {section === "权限" && (
          <SettingsGroup title="系统权限">
            {["辅助功能", "麦克风", "系统音频录制"].map((x, i) => (
              <SettingRow
                key={x}
                label={x}
                hint={i === 0 ? "读取其他应用中选中的文字" : "用于实时转写"}
              >
                <span className={i === 2 ? "permission-denied" : "permission-ok"}>
                  {i === 2 ? "未允许" : "已允许"}
                </span>
                {i === 2 && <Button>去授权</Button>}
              </SettingRow>
            ))}
          </SettingsGroup>
        )}
      </section>
    </div>
  );
}

function SettingsGroup({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="settings-group">
      <h2>{title}</h2>
      {children}
    </div>
  );
}
function SettingRow({
  label,
  hint,
  children,
}: {
  label: string;
  hint: string;
  children: React.ReactNode;
}) {
  return (
    <div className="setting-row">
      <span>
        <strong>{label}</strong>
        <small>{hint}</small>
      </span>
      <div>{children}</div>
    </div>
  );
}

function TranslateWindow() {
  const [state, setState] = useState("完成");
  const [pinned, setPinned] = useState(false);
  const [copied, setCopied] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [open, setOpen] = useState(true);
  const [streamIndex, setStreamIndex] = useState(0);
  const states = ["加载中", "翻译中", "完成", "出错", "空输入"];
  const translation = "会议已改期至下周二。";
  useEffect(() => {
    if (state !== "翻译中") return;
    setStreamIndex(0);
    const timer = window.setInterval(() => {
      setStreamIndex((value) => {
        if (value >= translation.length) {
          window.clearInterval(timer);
          window.setTimeout(() => setState("完成"), 180);
          return value;
        }
        return value + 1;
      });
    }, 85);
    return () => window.clearInterval(timer);
  }, [state]);
  return (
    <div className="floating-stage" onClick={() => !pinned && setOpen(false)}>
      <div className="source-app">
        <div className="source-toolbar" />
        <div className="fake-copy">
          <i />
          <i />
          <i />
          <i />
          <span className="selection">The meeting has been rescheduled to next Tuesday.</span>
          <i />
          <i />
          <i />
        </div>
      </div>
      {!open && (
        <button
          className="shortcut-reopen"
          onClick={(e) => {
            e.stopPropagation();
            setOpen(true);
          }}
        >
          按 ⌥D 再次打开翻译
        </button>
      )}
      {open && (
        <div
          className="translate-window"
          onClick={(e) => e.stopPropagation()}
          onKeyDown={(e) => {
            if (e.metaKey && e.key === "Enter") setState("翻译中");
            if (e.metaKey && e.key.toLowerCase() === "c") {
              setCopied(true);
              window.setTimeout(() => setCopied(false), 900);
            }
          }}
        >
          <header>
            <div className="drag-handle" />
            <span>{pinned ? "已固定" : "LingoLens 翻译"}</span>
            <button className={pinned ? "active" : ""} onClick={() => setPinned(!pinned)}>
              <Icon name="pin" size={16} />
            </button>
            <button onClick={() => setOpen(false)}>
              <Icon name="close" size={16} />
            </button>
          </header>
          {state === "空输入" ? (
            <div className="empty-translation">
              <div>
                <Icon name="translate" size={28} />
              </div>
              <strong>未取到选中的文字</strong>
              <p>请先在其他应用中选中文字，再按 ⌥D；也可以直接在下方输入。</p>
              <textarea placeholder="输入要翻译的文字…" />
              <Button primary>翻译</Button>
            </div>
          ) : (
            <>
              <div className="language-row">
                <button>
                  自动检测 <span>⌄</span>
                </button>
                <Icon name="arrow" size={16} />
                <button>
                  简体中文 <span>⌄</span>
                </button>
              </div>
              <div
                className={`source-text ${expanded ? "expanded" : ""}`}
                contentEditable={expanded}
                suppressContentEditableWarning
                onClick={() => setExpanded(true)}
              >
                The meeting has been rescheduled to next Tuesday.
                {!expanded && <button>展开并编辑</button>}
              </div>
              <div className={`translation-result ${state === "出错" ? "error" : ""}`}>
                {state === "加载中" && (
                  <div className="inline-state">
                    <div className="spinner" />
                    <span>
                      <strong>正在加载模型…</strong>
                      <small>Qwen3 4B · 首次加载可能需要几秒</small>
                    </span>
                  </div>
                )}
                {state === "翻译中" && (
                  <>
                    <p>
                      {translation.slice(0, streamIndex)}
                      <span className="typing">｜</span>
                    </p>
                    <div className="stream-line" />
                  </>
                )}
                {state === "完成" && <p>会议已改期至下周二。</p>}
                {state === "出错" && (
                  <div className="inline-state">
                    <Icon name="alert" size={23} />
                    <span>
                      <strong>翻译失败</strong>
                      <small>模型进程意外退出。</small>
                    </span>
                    <Button>重试</Button>
                  </div>
                )}
              </div>
              <footer>
                <span>
                  {state === "完成" ? "Qwen3 4B · 首字 186 ms · 28.4 tok/s" : "正在本机处理…"}
                </span>
                <button
                  onClick={() => {
                    setCopied(true);
                    window.setTimeout(() => setCopied(false), 800);
                  }}
                >
                  <Icon name={copied ? "check" : "copy"} size={15} />
                  {copied ? "已复制" : "复制"}
                </button>
                <kbd>⌘ ↵ 重译</kbd>
              </footer>
            </>
          )}
        </div>
      )}
      <div className="variant-switcher">
        <b>D · 划词翻译状态</b>
        {states.map((x) => (
          <button onClick={() => setState(x)} className={state === x ? "active" : ""} key={x}>
            {x}
          </button>
        ))}
      </div>
    </div>
  );
}

function CaptionWindow({ onStop }: { onStop: () => void }) {
  const [paused, setPaused] = useState(false);
  const [clickThrough, setClickThrough] = useState(false);
  const [font, setFont] = useState(1);
  const [opacity, setOpacity] = useState(80);
  const [position, setPosition] = useState({ x: 0, y: 0 });
  const [finalized, setFinalized] = useState(false);
  return (
    <div className="caption-stage">
      <div className="meeting-bg">
        <div className="meeting-appbar" />
        <div className="video-grid">
          <div />
          <div />
          <div />
        </div>
      </div>
      <div
        className="caption-float"
        style={{
          opacity: opacity / 100,
          transform: `translate(calc(-50% + ${position.x}px), ${position.y}px)`,
        }}
      >
        <div
          className="caption-control"
          onPointerDown={(e) => {
            if ((e.target as HTMLElement).closest("button, input")) return;
            const origin = {
              pointerX: e.clientX,
              pointerY: e.clientY,
              positionX: position.x,
              positionY: position.y,
            };
            const move = (event: PointerEvent) =>
              setPosition({
                x: origin.positionX + event.clientX - origin.pointerX,
                y: origin.positionY + event.clientY - origin.pointerY,
              });
            const up = () => {
              window.removeEventListener("pointermove", move);
              window.removeEventListener("pointerup", up);
            };
            window.addEventListener("pointermove", move);
            window.addEventListener("pointerup", up);
          }}
        >
          <span className="live-dot" /> <b>{paused ? "已暂停" : "实时字幕"}</b>
          <button onClick={() => setPaused(!paused)}>
            <Icon name={paused ? "play" : "pause"} size={15} />
            {paused ? "继续" : "暂停"}
          </button>
          <button
            className={clickThrough ? "active" : ""}
            onClick={() => setClickThrough(!clickThrough)}
          >
            点击穿透 {clickThrough ? "开" : "关"}
          </button>
          <div className="caption-size">
            {["紧凑", "标准", "大字"].map((x, i) => (
              <button className={font === i ? "active" : ""} onClick={() => setFont(i)} key={x}>
                {x}
              </button>
            ))}
          </div>
          <label>
            透明度{" "}
            <input
              type="range"
              min="50"
              max="100"
              value={opacity}
              onChange={(e) => setOpacity(Number(e.target.value))}
            />
          </label>
          <button onClick={onStop}>
            <Icon name="close" size={15} />
            关闭
          </button>
        </div>
        {clickThrough && (
          <div className="passthrough-hint">
            <Icon name="pin" size={12} /> 点击穿透
          </div>
        )}
        <div className={`caption-lines font-${font}`}>
          <div>
            <span className="speaker other">对方</span>
            <p className="original">Before we launch, I want to confirm the timeline.</p>
            <strong>正式上线前，我想确认一下时间安排。</strong>
          </div>
          <div>
            <span className="speaker me">我</span>
            <p className="original">第一阶段计划在下周三完成。</p>
            <strong>The first phase is planned for next Wednesday.</strong>
          </div>
          <div className={finalized ? "finalized" : "draft"} onClick={() => setFinalized(true)}>
            <span className="speaker other">对方</span>
            <p className="original">That works. Who will own the final review...</p>
            {finalized && <strong>没问题。最终审核将由谁负责？</strong>}
            <i>{finalized ? "已定稿" : "识别中 · 点击模拟定稿"}</i>
          </div>
        </div>
      </div>
      <div className="stage-note light">
        <b>E · 实时字幕浮窗</b>
        <span>悬停控制条 · 可调整字号与透明度</span>
      </div>
    </div>
  );
}

function ErrorGallery() {
  const errors = [
    ["模型启动失败", "模型进程未能启动。可能是模型文件损坏或运行时异常。", "查看日志", "重试"],
    ["内存不足", "当前模型需要约 12 GB 可用内存，当前仅有 6.2 GB。", "换小模型", "释放内存后重试"],
    ["权限被拒", "没有系统音频录制权限，无法转写对方的声音。", "去授权", "稍后"],
    ["运行时安装失败", "无法完成 MLX 运行时安装，请检查磁盘空间后重试。", "查看日志", "重试"],
  ];
  const [selected, setSelected] = useState(0);
  return (
    <section className="error-gallery">
      <div className="error-intro">
        <span className="eyebrow">F · 全局状态与错误</span>
        <h1>问题明确，下一步清晰。</h1>
        <p>错误不会只告诉用户“失败了”，每种状态都提供可执行的恢复操作。</p>
      </div>
      <div className="error-tabs">
        {errors.map((e, i) => (
          <button
            onClick={() => setSelected(i)}
            className={selected === i ? "active" : ""}
            key={e[0]}
          >
            <Icon name="alert" size={17} />
            {e[0]}
          </button>
        ))}
      </div>
      <div className="error-preview inline-error-preview">
        <div className="mock-context">
          <div className="context-sidebar" />
          <div className="context-lines">
            <i />
            <i />
            <i />
            <i />
          </div>
        </div>
        <div className="error-banner">
          <div className="error-symbol">
            <Icon name="alert" size={20} />
          </div>
          <div>
            <h2>{errors[selected][0]}</h2>
            <p>{errors[selected][1]} 本地数据未受影响。</p>
            <code>LOCAL_RUNTIME_{selected + 100}</code>
          </div>
          <Button>{errors[selected][2]}</Button>
          <Button primary>{errors[selected][3]}</Button>
        </div>
      </div>
      <div className="error-principles">
        <div>
          <b>1</b>
          <span>
            <strong>说明发生了什么</strong>
            <small>使用用户可以理解的语言</small>
          </span>
        </div>
        <div>
          <b>2</b>
          <span>
            <strong>数据保持安全</strong>
            <small>清楚说明本地记录未丢失</small>
          </span>
        </div>
        <div>
          <b>3</b>
          <span>
            <strong>提供恢复路径</strong>
            <small>首要操作始终可见</small>
          </span>
        </div>
      </div>
    </section>
  );
}

function ComponentLibrary() {
  const [activeSegment, setActiveSegment] = useState("标准");
  const [toggle, setToggle] = useState(true);
  return (
    <section className="component-library">
      <header>
        <div>
          <span className="eyebrow">LingoLens Design System 1.0</span>
          <h1>基础组件与设计 Token</h1>
          <p>基于 4 / 8 pt 栅格，遵循 macOS 26 系统层级与 Liquid Glass 材质。</p>
        </div>
        <span className="system-badge">SF Pro · PingFang SC · SF Symbols</span>
      </header>
      <div className="token-strip">
        {[
          ["主色", "#4F5BD5", "var(--accent)"],
          ["我", "#3787F2", "var(--speaker-me)"],
          ["对方", "#E99535", "var(--speaker-other)"],
          ["成功", "#31A66A", "var(--success)"],
          ["警示", "#E5A52E", "var(--warning)"],
          ["错误", "#E05252", "var(--danger)"],
        ].map(([name, value, color]) => (
          <div className="color-token" key={name}>
            <i style={{ background: color }} />
            <span>
              <strong>{name}</strong>
              <small>{value}</small>
            </span>
          </div>
        ))}
      </div>
      <div className="component-grid">
        <article>
          <h2>按钮</h2>
          <p>主要、次要、幽灵、危险与禁用</p>
          <div className="component-row">
            <Button primary icon="play">
              主要按钮
            </Button>
            <Button icon="download">次要按钮</Button>
            <button className="ghost-button">幽灵按钮</button>
            <Button danger>删除</Button>
            <Button disabled>禁用</Button>
          </div>
        </article>
        <article>
          <h2>输入与选择</h2>
          <p>默认、聚焦、搜索与错误状态</p>
          <div className="component-row">
            <input className="ds-input" placeholder="输入内容…" />
            <div className="search ds-search">
              <Icon name="search" size={14} />
              <input placeholder="搜索" />
            </div>
            <select className="ds-select">
              <option>简体中文</option>
            </select>
            <input className="ds-input error" defaultValue="无效路径" />
          </div>
        </article>
        <article>
          <h2>控制器</h2>
          <p>开关、分段控件与滑块</p>
          <div className="component-row">
            <Toggle on={toggle} onChange={() => setToggle(!toggle)} />
            <div className="segmented ds-segmented">
              {["紧凑", "标准", "大字"].map((x) => (
                <button
                  className={activeSegment === x ? "active" : ""}
                  onClick={() => setActiveSegment(x)}
                  key={x}
                >
                  {x}
                </button>
              ))}
            </div>
            <input type="range" defaultValue="65" />
          </div>
        </article>
        <article>
          <h2>标签与状态</h2>
          <p>语义状态与说话人身份保持一致</p>
          <div className="component-row">
            <span className="badge success">已就绪</span>
            <span className="badge warning">加载中</span>
            <span className="badge danger">错误</span>
            <span className="speaker me">我</span>
            <span className="speaker other">对方</span>
            <kbd>⌥ D</kbd>
          </div>
        </article>
        <article>
          <h2>卡片与进度</h2>
          <p>玻璃材质、进度反馈和系统阴影</p>
          <div className="mini-card">
            <div className="model-cube">
              <Icon name="model" />
            </div>
            <span>
              <strong>Qwen3 4B MLX</strong>
              <small>本地模型 · 已就绪</small>
            </span>
            <span className="badge success">常驻</span>
            <div className="progress">
              <i style={{ width: "68%" }} />
            </div>
          </div>
        </article>
        <article className="type-scale">
          <h2>字号层级</h2>
          <p>动态字体层级，适配简体中文</p>
          <div>
            <strong className="type-title">页面标题 24 / 30</strong>
            <strong className="type-heading">分组标题 15 / 20</strong>
            <span className="type-body">正文文本 13 / 18</span>
            <small>辅助文本 11 / 15</small>
          </div>
        </article>
      </div>
      <footer className="motion-spec">
        <strong>动效规范</strong>
        <span>
          <i>150ms</i> 浮窗出现 · ease-out
        </span>
        <span>
          <i>180ms</i> 状态切换 · ease-in-out
        </span>
        <span>
          <i>240ms</i> 列表滑入 · cubic-bezier(.2,.8,.2,1)
        </span>
        <span>
          <i>弹簧</i> 拖动归位 · 320 / 28
        </span>
      </footer>
    </section>
  );
}
