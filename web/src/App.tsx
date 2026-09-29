import { useCallback, useEffect, useRef, useState } from "react";
import { CATEGORIES, SOURCES, type Item, type Source } from "./types";

const API = (import.meta.env.VITE_API_URL as string | undefined) || "http://localhost:8000";

type Health = { ok: boolean; warn: boolean; message: string; last_5_auth_failed: number };
type SweepSource = { authenticated: boolean; last_sweep: string | null; last_sweep_result: { processed: number; skipped: number; failed: number } | null };
type SweepSource_IG = SweepSource & { session_status: string };
type SweepStatus = { twitter: SweepSource; ig_saved: SweepSource_IG };
type DryRun = {
  ig_cookies: { status: string; message: string; age_days?: number };
  twitter: { status: string; message: string };
  gemini: { status: string; message: string };
  ytdlp: { status: string; message: string };
  all_ok: boolean;
};
type Stats = {
  total: number;
  by_source: { source: string; count: number }[];
  by_category: { category: string; count: number }[];
  by_status: { status: string; count: number }[];
  timeline: { day: string; count: number }[];
};
type TopicTag = { tag: string; count: number; categories: Record<string, number> };
type ChatMsg = { role: "user" | "assistant"; text: string; sources?: number[] };
type BackfillPlatform = { status: string; cursor: string | null; ingested: number; skipped: number; failed: number; total_seen: number; started_at: string | null; last_activity: string | null; more_available: boolean; error: string | null };
type BackfillStatus = { twitter: BackfillPlatform; ig: BackfillPlatform; facebook: BackfillPlatform; tiktok: BackfillPlatform };

type Tab = "feed" | "topics" | "stats" | "chat";

const SOURCE_ICONS: Record<Source, string> = { ig_reel: "◎", tweet: "𝕏", tiktok: "♪", facebook: "f", web: "◆", note: "✎" };
const SOURCE_COLORS: Record<Source, string> = { ig_reel: "text-pink-400", tweet: "text-sky-400", tiktok: "text-cyan-400", facebook: "text-blue-400", web: "text-emerald-400", note: "text-amber-400" };

export default function App() {
  const [items, setItems] = useState<Item[]>([]);
  const [category, setCategory] = useState<string>("");
  const [source, setSource] = useState<string>("");
  const [tag, setTag] = useState<string>("");
  const [q, setQ] = useState<string>("");
  const [debouncedQ, setDebouncedQ] = useState<string>("");
  const [loading, setLoading] = useState<boolean>(false);
  const [err, setErr] = useState<string | null>(null);
  const [health, setHealth] = useState<Health | null>(null);
  const [healthDismissed, setHealthDismissed] = useState<boolean>(false);
  const [detailId, setDetailId] = useState<number | null>(null);
  const [sweepStatus, setSweepStatus] = useState<SweepStatus | null>(null);
  const [dryRun, setDryRun] = useState<DryRun | null>(null);
  const [activeTab, setActiveTab] = useState<Tab>("feed");
  const [hideFunny, setHideFunny] = useState(true);

  useEffect(() => {
    const t = setTimeout(() => setDebouncedQ(q), 250);
    return () => clearTimeout(t);
  }, [q]);

  const refetch = useCallback(async () => {
    setLoading(true);
    setErr(null);
    const params = new URLSearchParams();
    if (category) params.set("category", category);
    if (source) params.set("source", source);
    if (tag) params.set("tag", tag);
    if (debouncedQ) params.set("q", debouncedQ);
    if (hideFunny && !category) params.set("exclude_category", "funny");
    try {
      const r = await fetch(`${API}/items?${params.toString()}`);
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      setItems(await r.json());
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [category, source, tag, debouncedQ, hideFunny]);

  useEffect(() => { refetch(); }, [refetch]);
  useEffect(() => { const t = setInterval(refetch, 15000); return () => clearInterval(t); }, [refetch]);

  useEffect(() => {
    let alive = true;
    const go = async () => {
      try {
        const [hRes, sRes, dRes] = await Promise.all([
          fetch(`${API}/health`),
          fetch(`${API}/sweep/status`),
          fetch(`${API}/sweep/dry-run`),
        ]);
        if (hRes.ok && alive) setHealth(await hRes.json());
        if (sRes.ok && alive) setSweepStatus(await sRes.json());
        if (dRes.ok && alive) setDryRun(await dRes.json());
      } catch { /* handled by items fetch */ }
    };
    go();
    const t = setInterval(go, 60_000);
    return () => { alive = false; clearInterval(t); };
  }, []);

  const onRetry = async (id: number) => {
    try { await fetch(`${API}/items/${id}/retry`, { method: "POST" }); refetch(); } catch (e) { console.error("retry failed", e); }
  };

  const showHealthBanner = health?.warn && !healthDismissed;

  return (
    <div className="min-h-full" style={{ background: "var(--sf-bg-base)" }}>
      {showHealthBanner && (
        <div style={{ background: "rgba(255,164,43,0.12)", borderBottom: "1px solid rgba(255,164,43,0.25)" }}>
          <div className="max-w-3xl mx-auto px-4 py-2 flex items-start gap-2 text-sm" style={{ color: "var(--sf-warning)" }}>
            <span className="shrink-0">⚠</span>
            <p className="flex-1">{health!.message}</p>
            <button onClick={() => setHealthDismissed(true)} className="px-1 text-lg leading-none shrink-0 opacity-60 hover:opacity-100">×</button>
          </div>
        </div>
      )}

      <header className="sticky top-0 z-10" style={{ background: "var(--sf-bg-surface)", borderBottom: "1px solid var(--sf-border)" }}>
        <div className="max-w-3xl mx-auto px-4 py-3">
          <div className="flex items-center gap-3 mb-3">
            <h1 className="text-base font-bold tracking-tight" style={{ color: "var(--sf-text-primary)" }}>savefeed</h1>
            <span className="text-xs font-mono" style={{ color: "var(--sf-text-muted)" }}>{loading ? "…" : `${items.length}`}</span>
            {sweepStatus && <SweepIndicators status={sweepStatus} />}
            <div className="ml-auto flex items-center gap-2">
              <button onClick={refetch} className="text-xs px-3 py-1.5 rounded-full font-medium transition-colors" style={{ background: "var(--sf-bg-elevated)", color: "var(--sf-text-secondary)" }}>↻</button>
            </div>
          </div>

          <HealthBar dryRun={dryRun} />

          <div className="flex gap-1.5 mt-3 mb-3">
            {(["feed", "topics", "stats", "chat"] as Tab[]).map((t) => (
              <button
                key={t}
                onClick={() => setActiveTab(t)}
                className="px-3 py-1.5 rounded-full text-xs font-bold uppercase tracking-wider transition-all"
                style={{
                  background: activeTab === t ? "var(--sf-accent)" : "var(--sf-bg-elevated)",
                  color: activeTab === t ? "#000" : "var(--sf-text-secondary)",
                  letterSpacing: "1.4px",
                }}
              >
                {t}
              </button>
            ))}
          </div>

          {activeTab === "feed" && (
            <>
              <div className="relative mb-3">
                <input
                  type="search" value={q} onChange={(e) => setQ(e.target.value)}
                  placeholder="Search summaries, transcripts, on-screen text…"
                  className="w-full px-4 py-2.5 pr-8 text-sm focus:outline-none"
                  style={{ background: "var(--sf-bg-elevated)", color: "var(--sf-text-primary)", borderRadius: "var(--sf-radius-pill)", border: "1px solid transparent" }}
                  onFocus={(e) => e.currentTarget.style.borderColor = "var(--sf-border-light)"}
                  onBlur={(e) => e.currentTarget.style.borderColor = "transparent"}
                />
                {q && <button type="button" onClick={() => setQ("")} className="absolute right-3 top-1/2 -translate-y-1/2 text-lg leading-none px-1" style={{ color: "var(--sf-text-muted)" }}>×</button>}
              </div>
              <div className="flex gap-2 overflow-x-auto pb-1 items-center">
                <FilterGroup label="source" options={SOURCES} value={source} onChange={setSource} />
                <span style={{ width: 1, background: "var(--sf-border)", margin: "4px 4px" }} />
                <FilterGroup label="category" options={[...CATEGORIES]} value={category} onChange={setCategory} />
                <span style={{ width: 1, background: "var(--sf-border)", margin: "4px 4px" }} />
                <button
                  onClick={() => setHideFunny(!hideFunny)}
                  className="px-2 py-1 rounded-full text-xs font-medium transition-all whitespace-nowrap"
                  style={{
                    background: hideFunny ? "var(--sf-bg-elevated)" : "rgba(99,102,241,0.15)",
                    color: hideFunny ? "var(--sf-text-muted)" : "#818cf8",
                  }}
                  title={hideFunny ? "Memes hidden — click to show" : "Showing memes — click to hide"}
                >
                  {hideFunny ? "😶 memes off" : "😂 memes on"}
                </button>
              </div>
              {tag && (
                <div className="mt-2 flex items-center gap-1">
                  <button onClick={() => setTag("")} className="px-3 py-1 rounded-full font-mono text-xs transition-colors" style={{ background: "rgba(99,102,241,0.15)", color: "#818cf8" }}>
                    #{tag} ×
                  </button>
                </div>
              )}
            </>
          )}

          {err && <p className="mt-2 text-xs" style={{ color: "var(--sf-negative)" }}>Connection error: {err} — is the server running?</p>}
        </div>
      </header>

      {activeTab === "feed" && (
        <main className="max-w-3xl mx-auto px-4 py-4 space-y-3">
          {items.map((item) => <Card key={item.id} item={item} onRetry={onRetry} onTagClick={setTag} onDetail={setDetailId} />)}
          {!loading && items.length === 0 && !err && <p className="text-center py-12 text-sm" style={{ color: "var(--sf-text-muted)" }}>Nothing matches these filters.</p>}
        </main>
      )}

      {activeTab === "topics" && <TopicsView onTagClick={(t) => { setTag(t); setActiveTab("feed"); }} />}
      {activeTab === "stats" && <StatsView />}
      {activeTab === "chat" && <ChatView onDetail={setDetailId} />}

      {detailId !== null && (
        <DetailView itemId={detailId} onClose={() => setDetailId(null)} onTagClick={(t) => { setDetailId(null); setTag(t); setActiveTab("feed"); }} onTagsChanged={refetch} />
      )}
    </div>
  );
}

/* ─── Health Bar (always visible) ─── */

function HealthBar({ dryRun }: { dryRun: DryRun | null }) {
  const statusDot = (s: string) => s === "ok" ? "var(--sf-accent)" : s === "warn" ? "var(--sf-warning)" : "var(--sf-negative)";
  const checks = dryRun ? [
    { key: "ig_cookies", label: "IG", data: dryRun.ig_cookies },
    { key: "twitter", label: "X", data: dryRun.twitter },
    { key: "gemini", label: "Gemini", data: dryRun.gemini },
    { key: "ytdlp", label: "yt-dlp", data: dryRun.ytdlp },
  ] : null;

  return (
    <div className="flex items-center gap-3 text-xs" style={{ color: "var(--sf-text-muted)" }}>
      {checks ? checks.map((c) => (
        <span key={c.key} className="flex items-center gap-1 cursor-help" title={c.data.message}>
          <span style={{ color: statusDot(c.data.status), fontSize: 8 }}>●</span>
          <span>{c.label}</span>
        </span>
      )) : (
        <span>Loading health…</span>
      )}
      <a href={`${API}/setup`} target="_blank" rel="noopener" className="ml-auto text-xs hover:underline" style={{ color: "var(--sf-text-muted)" }}>Setup ↗</a>
    </div>
  );
}

/* ─── Topics View ─── */

function TopicsView({ onTagClick }: { onTagClick: (tag: string) => void }) {
  const [topics, setTopics] = useState<TopicTag[]>([]);
  const [showAll, setShowAll] = useState(false);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      try {
        const r = await fetch(`${API}/topics`);
        if (r.ok) setTopics(await r.json());
      } finally { setLoading(false); }
    })();
  }, []);

  if (loading) return <div className="max-w-3xl mx-auto px-4 py-8 text-center text-sm" style={{ color: "var(--sf-text-muted)" }}>Loading topics…</div>;

  const visible = showAll ? topics : topics.slice(0, 40);
  const maxCount = topics[0]?.count || 1;

  const catColor = (cats: Record<string, number>) => {
    const top = Object.entries(cats).sort((a, b) => b[1] - a[1])[0];
    if (!top) return "#818cf8";
    const m: Record<string, string> = { coding: "#34d399", quant: "#60a5fa", music: "#f472b6", "life-hack": "#fbbf24", productivity: "#a78bfa", funny: "#fb923c", other: "#94a3b8" };
    return m[top[0]] || "#818cf8";
  };

  return (
    <main className="max-w-3xl mx-auto px-4 py-6">
      <div className="mb-4 flex items-center justify-between">
        <h2 className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--sf-text-muted)", letterSpacing: "2px" }}>
          {topics.length} Topics
        </h2>
        <span className="text-xs" style={{ color: "var(--sf-text-muted)" }}>Sized by frequency, colored by dominant category</span>
      </div>
      <div className="flex flex-wrap gap-2">
        {visible.map((t) => {
          const scale = 0.6 + (t.count / maxCount) * 0.8;
          const opacity = 0.5 + (t.count / maxCount) * 0.5;
          return (
            <button
              key={t.tag}
              onClick={() => onTagClick(t.tag)}
              className="px-3 py-1.5 rounded-full font-mono transition-all hover:scale-105"
              style={{
                fontSize: `${Math.max(11, Math.min(18, 11 * scale))}px`,
                background: `${catColor(t.categories)}18`,
                color: catColor(t.categories),
                opacity,
              }}
              title={`${t.tag}: ${t.count} items`}
            >
              {t.tag} <span className="opacity-60" style={{ fontSize: 10 }}>{t.count}</span>
            </button>
          );
        })}
      </div>
      {topics.length > 40 && !showAll && (
        <button onClick={() => setShowAll(true)} className="mt-4 text-xs px-4 py-2 rounded-full" style={{ background: "var(--sf-bg-elevated)", color: "var(--sf-text-secondary)" }}>
          Show all {topics.length} topics
        </button>
      )}
    </main>
  );
}

/* ─── Stats View ─── */

function StatsView() {
  const [stats, setStats] = useState<Stats | null>(null);

  useEffect(() => {
    (async () => {
      try {
        const r = await fetch(`${API}/stats`);
        if (r.ok) setStats(await r.json());
      } catch { /* ignore */ }
    })();
  }, []);

  if (!stats) return <div className="max-w-3xl mx-auto px-4 py-8 text-center text-sm" style={{ color: "var(--sf-text-muted)" }}>Loading stats…</div>;

  const maxSource = Math.max(...stats.by_source.map((s) => s.count), 1);
  const maxCat = Math.max(...stats.by_category.map((c) => c.count), 1);
  const timeline = stats.timeline.slice().reverse();
  const maxDay = Math.max(...timeline.map((d) => d.count), 1);

  const srcColor: Record<string, string> = { ig_reel: "#f472b6", tweet: "#38bdf8", tiktok: "#22d3ee", facebook: "#60a5fa", web: "#34d399", note: "#fbbf24" };
  const catColor: Record<string, string> = { coding: "#34d399", quant: "#60a5fa", music: "#f472b6", "life-hack": "#fbbf24", productivity: "#a78bfa", funny: "#fb923c", other: "#94a3b8" };

  return (
    <main className="max-w-3xl mx-auto px-4 py-6 space-y-6">
      {/* Stat cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
        <StatCard label="Total Items" value={stats.total} />
        <StatCard label="Sources" value={stats.by_source.length} />
        <StatCard label="Categories" value={stats.by_category.length} />
        <StatCard label="Failed" value={stats.by_status.find((s) => s.status === "failed")?.count || 0} color="var(--sf-negative)" />
      </div>

      {/* By source */}
      <div>
        <h3 className="text-xs font-bold uppercase tracking-widest mb-3" style={{ color: "var(--sf-text-muted)", letterSpacing: "2px" }}>By Source</h3>
        <div className="space-y-2">
          {stats.by_source.map((s) => (
            <div key={s.source} className="flex items-center gap-2">
              <span className="text-xs font-mono w-16 text-right" style={{ color: "var(--sf-text-secondary)" }}>{s.source === "ig_reel" ? "ig" : s.source}</span>
              <div className="flex-1 h-5 rounded-full overflow-hidden" style={{ background: "var(--sf-bg-elevated)" }}>
                <div className="h-full rounded-full transition-all" style={{ width: `${(s.count / maxSource) * 100}%`, background: srcColor[s.source] || "#94a3b8" }} />
              </div>
              <span className="text-xs font-mono w-8" style={{ color: "var(--sf-text-muted)" }}>{s.count}</span>
            </div>
          ))}
        </div>
      </div>

      {/* By category */}
      <div>
        <h3 className="text-xs font-bold uppercase tracking-widest mb-3" style={{ color: "var(--sf-text-muted)", letterSpacing: "2px" }}>By Category</h3>
        <div className="space-y-2">
          {stats.by_category.map((c) => (
            <div key={c.category} className="flex items-center gap-2">
              <span className="text-xs font-mono w-20 text-right" style={{ color: "var(--sf-text-secondary)" }}>{c.category || "none"}</span>
              <div className="flex-1 h-5 rounded-full overflow-hidden" style={{ background: "var(--sf-bg-elevated)" }}>
                <div className="h-full rounded-full transition-all" style={{ width: `${(c.count / maxCat) * 100}%`, background: catColor[c.category] || "#94a3b8" }} />
              </div>
              <span className="text-xs font-mono w-8" style={{ color: "var(--sf-text-muted)" }}>{c.count}</span>
            </div>
          ))}
        </div>
      </div>

      {/* Timeline */}
      {timeline.length > 0 && (
        <div>
          <h3 className="text-xs font-bold uppercase tracking-widest mb-3" style={{ color: "var(--sf-text-muted)", letterSpacing: "2px" }}>Daily Timeline</h3>
          <div className="flex items-end gap-px h-24">
            {timeline.map((d) => (
              <div
                key={d.day}
                className="flex-1 rounded-t transition-all cursor-help"
                style={{ height: `${Math.max(4, (d.count / maxDay) * 100)}%`, background: "var(--sf-accent)", opacity: 0.7 }}
                title={`${d.day}: ${d.count} items`}
              />
            ))}
          </div>
          <div className="flex justify-between text-xs mt-1" style={{ color: "var(--sf-text-muted)" }}>
            <span>{timeline[0]?.day}</span>
            <span>{timeline[timeline.length - 1]?.day}</span>
          </div>
        </div>
      )}

      {/* Backfill */}
      <BackfillPanel />
    </main>
  );
}

function BackfillPanel() {
  const [bf, setBf] = useState<BackfillStatus | null>(null);
  const [acting, setActing] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const r = await fetch(`${API}/backfill/status`);
      if (r.ok) setBf(await r.json());
    } catch { /* ignore */ }
  }, []);

  useEffect(() => {
    load();
    const iv = setInterval(load, 5000);
    return () => clearInterval(iv);
  }, [load]);

  const trigger = async (platform: "twitter" | "ig") => {
    setActing(platform);
    try {
      const ep = platform === "twitter" ? "/sweep/twitter/backfill" : "/sweep/ig/backfill";
      await fetch(`${API}${ep}`, { method: "POST" });
      setTimeout(load, 1000);
    } catch { /* ignore */ }
    setActing(null);
  };

  if (!bf) return null;

  const platforms: { key: keyof BackfillStatus; label: string; color: string; canTrigger: boolean }[] = [
    { key: "twitter", label: "Twitter / X", color: "#38bdf8", canTrigger: true },
    { key: "ig", label: "Instagram", color: "#f472b6", canTrigger: true },
    { key: "facebook", label: "Facebook", color: "#60a5fa", canTrigger: false },
    { key: "tiktok", label: "TikTok", color: "#22d3ee", canTrigger: false },
  ];

  const statusIcon = (s: string) => {
    if (s === "running") return "●";
    if (s === "paused") return "◑";
    if (s === "done") return "✓";
    return "○";
  };

  const statusColor = (s: string) => {
    if (s === "running") return "var(--sf-accent)";
    if (s === "paused") return "#d97706";
    if (s === "done") return "#16a34a";
    return "var(--sf-text-muted)";
  };

  const ago = (iso: string | null) => {
    if (!iso) return "";
    const diff = (Date.now() - new Date(iso).getTime()) / 1000;
    if (diff < 60) return "just now";
    if (diff < 3600) return `${Math.floor(diff / 60)}m ago`;
    if (diff < 86400) return `${Math.floor(diff / 3600)}h ago`;
    return `${Math.floor(diff / 86400)}d ago`;
  };

  return (
    <div>
      <h3 className="text-xs font-bold uppercase tracking-widest mb-3" style={{ color: "var(--sf-text-muted)", letterSpacing: "2px" }}>Backfill</h3>
      <div className="space-y-3">
        {platforms.map(({ key, label, color, canTrigger }) => {
          const p = bf[key];
          const isIdle = p.status === "idle";
          const isRunning = p.status === "running";
          const btnLabel = isIdle ? "Start" : p.status === "paused" ? "Resume" : isRunning ? "Running…" : "Restart";

          return (
            <div key={key} className="rounded-lg p-3" style={{ background: "var(--sf-bg-surface)", border: "1px solid var(--sf-border)" }}>
              <div className="flex items-center justify-between mb-2">
                <div className="flex items-center gap-2">
                  <span style={{ color: statusColor(p.status), fontSize: "12px" }}>{statusIcon(p.status)}</span>
                  <span className="text-sm font-medium" style={{ color: "var(--sf-text-primary)" }}>{label}</span>
                  <span className="text-xs font-mono" style={{ color: statusColor(p.status) }}>{p.status}</span>
                </div>
                {canTrigger && !isRunning && (
                  <button
                    onClick={() => trigger(key as "twitter" | "ig")}
                    disabled={acting === key}
                    className="px-3 py-1 rounded-full text-xs font-bold uppercase tracking-wider"
                    style={{ background: color, color: "#000", opacity: acting === key ? 0.5 : 1, letterSpacing: "1px" }}
                  >
                    {acting === key ? "…" : btnLabel}
                  </button>
                )}
                {!canTrigger && isIdle && (
                  <a href="http://127.0.0.1:8000/setup" target="_blank" rel="noreferrer" className="text-xs" style={{ color: "var(--sf-accent)" }}>Setup →</a>
                )}
              </div>
              {!isIdle && (
                <div className="text-xs font-mono space-y-1" style={{ color: "var(--sf-text-secondary)" }}>
                  <div className="flex gap-4">
                    <span style={{ color }}>+{p.ingested} ingested</span>
                    <span>{p.skipped} skipped</span>
                    {p.failed > 0 && <span style={{ color: "var(--sf-negative)" }}>{p.failed} failed</span>}
                  </div>
                  {p.more_available && p.status !== "done" && <div style={{ color: "var(--sf-text-muted)" }}>more available…</div>}
                  {p.last_activity && <div style={{ color: "var(--sf-text-muted)" }}>last activity: {ago(p.last_activity)}</div>}
                  {p.error && <div style={{ color: "var(--sf-negative)" }}>{p.error}</div>}
                </div>
              )}
            </div>
          );
        })}
      </div>
      <p className="text-xs mt-2" style={{ color: "var(--sf-text-muted)" }}>
        FB &amp; TikTok use data exports — see <a href="http://127.0.0.1:8000/setup" target="_blank" rel="noreferrer" style={{ color: "var(--sf-accent)" }}>setup page</a> for instructions.
      </p>
    </div>
  );
}

function StatCard({ label, value, color }: { label: string; value: number; color?: string }) {
  return (
    <div className="rounded-lg p-4" style={{ background: "var(--sf-bg-surface)", border: "1px solid var(--sf-border)" }}>
      <p className="text-2xl font-bold mb-1" style={{ color: color || "var(--sf-text-primary)" }}>{value}</p>
      <p className="text-xs uppercase tracking-wider" style={{ color: "var(--sf-text-muted)", letterSpacing: "1.4px" }}>{label}</p>
    </div>
  );
}

/* ─── Chat View ─── */

function ChatView({ onDetail }: { onDetail: (id: number) => void }) {
  const [messages, setMessages] = useState<ChatMsg[]>([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [hasEmbeddings, setHasEmbeddings] = useState<boolean | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    (async () => {
      try {
        const r = await fetch(`${API}/chat/status`);
        if (r.ok) {
          const d = await r.json();
          setHasEmbeddings(d.embedded > 0);
        } else {
          setHasEmbeddings(false);
        }
      } catch { setHasEmbeddings(false); }
    })();
  }, []);

  useEffect(() => {
    scrollRef.current?.scrollTo(0, scrollRef.current.scrollHeight);
  }, [messages]);

  const send = async () => {
    const text = input.trim();
    if (!text || loading) return;
    setInput("");
    const userMsg: ChatMsg = { role: "user", text };
    setMessages((prev) => [...prev, userMsg]);
    setLoading(true);
    try {
      const r = await fetch(`${API}/chat`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: text, history: messages.slice(-10) }),
      });
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      const data = await r.json();
      setMessages((prev) => [...prev, { role: "assistant", text: data.response, sources: data.sources }]);
    } catch (e) {
      setMessages((prev) => [...prev, { role: "assistant", text: `Error: ${e instanceof Error ? e.message : String(e)}. Make sure the chat endpoint is set up and embeddings are backfilled.` }]);
    } finally {
      setLoading(false);
    }
  };

  const backfill = async () => {
    try {
      await fetch(`${API}/embed/backfill`, { method: "POST" });
      setHasEmbeddings(true);
    } catch { /* ignore */ }
  };

  return (
    <main className="max-w-3xl mx-auto px-4 py-6 flex flex-col" style={{ height: "calc(100vh - 200px)" }}>
      {hasEmbeddings === false && (
        <div className="rounded-lg p-4 mb-4 text-center" style={{ background: "var(--sf-bg-surface)", border: "1px solid var(--sf-border)" }}>
          <p className="text-sm mb-3" style={{ color: "var(--sf-text-secondary)" }}>
            Chat requires embeddings. Click below to generate them for all your saved items.
          </p>
          <button onClick={backfill} className="px-4 py-2 rounded-full text-xs font-bold uppercase tracking-wider" style={{ background: "var(--sf-accent)", color: "#000", letterSpacing: "1.4px" }}>
            Generate Embeddings
          </button>
          <p className="text-xs mt-2" style={{ color: "var(--sf-text-muted)" }}>This runs in the background using Gemini's free embedding API.</p>
        </div>
      )}

      <div ref={scrollRef} className="flex-1 overflow-y-auto space-y-3 mb-4">
        {messages.length === 0 && (
          <div className="text-center py-12">
            <p className="text-sm mb-1" style={{ color: "var(--sf-text-muted)" }}>Ask anything about your saved content</p>
            <p className="text-xs" style={{ color: "var(--sf-text-muted)" }}>e.g. "What coding tutorials have I saved?" or "Find my finance bookmarks"</p>
          </div>
        )}
        {messages.map((msg, i) => (
          <div key={i} className={`flex ${msg.role === "user" ? "justify-end" : "justify-start"}`}>
            <div
              className="rounded-xl px-4 py-2.5 max-w-[80%] text-sm"
              style={{
                background: msg.role === "user" ? "var(--sf-accent)" : "var(--sf-bg-surface)",
                color: msg.role === "user" ? "#000" : "var(--sf-text-primary)",
                border: msg.role === "assistant" ? "1px solid var(--sf-border)" : "none",
              }}
            >
              <p className="whitespace-pre-wrap">{msg.text}</p>
              {msg.sources && msg.sources.length > 0 && (
                <div className="flex gap-1 mt-2 flex-wrap">
                  {msg.sources.map((id) => (
                    <button key={id} onClick={() => onDetail(id)} className="text-xs px-2 py-0.5 rounded-full" style={{ background: "rgba(30,215,96,0.15)", color: "var(--sf-accent)" }}>
                      #{id}
                    </button>
                  ))}
                </div>
              )}
            </div>
          </div>
        ))}
        {loading && (
          <div className="flex justify-start">
            <div className="rounded-xl px-4 py-2.5 text-sm" style={{ background: "var(--sf-bg-surface)", color: "var(--sf-text-muted)", border: "1px solid var(--sf-border)" }}>
              Thinking…
            </div>
          </div>
        )}
      </div>

      <form onSubmit={(e) => { e.preventDefault(); send(); }} className="flex gap-2">
        <input
          type="text" value={input} onChange={(e) => setInput(e.target.value)}
          placeholder="Ask about your saved content…"
          className="flex-1 px-4 py-3 text-sm focus:outline-none"
          style={{ background: "var(--sf-bg-elevated)", color: "var(--sf-text-primary)", borderRadius: "var(--sf-radius-pill)", border: "1px solid var(--sf-border)" }}
          disabled={loading}
        />
        <button
          type="submit" disabled={loading || !input.trim()}
          className="px-5 py-3 rounded-full text-sm font-bold transition-all disabled:opacity-30"
          style={{ background: "var(--sf-accent)", color: "#000" }}
        >
          →
        </button>
      </form>
    </main>
  );
}

/* ─── Shared Components ─── */

function SweepIndicators({ status }: { status: SweepStatus }) {
  return (
    <div className="flex items-center gap-2 text-xs" style={{ color: "var(--sf-text-muted)" }}>
      <SweepDot label="IG" source={status.ig_saved} />
      <SweepDot label="X" source={status.twitter} />
    </div>
  );
}

function SweepDot({ label, source }: { label: string; source: SweepSource }) {
  const color = source.authenticated ? "var(--sf-accent)" : "var(--sf-text-muted)";
  const ago = source.last_sweep ? relativeTime(source.last_sweep) : null;
  return (
    <span className="flex items-center gap-1" title={ago ? `Last sweep: ${ago}` : "Not yet swept"}>
      <span style={{ color, fontSize: 8 }}>●</span>
      <span>{label}</span>
    </span>
  );
}

function FilterGroup({ label, options, value, onChange }: { label: string; options: readonly string[]; value: string; onChange: (v: string) => void }) {
  return (
    <div className="flex items-center gap-1 text-xs">
      <Pill active={!value} onClick={() => onChange("")}>all</Pill>
      {options.map((opt) => (
        <Pill key={opt} active={opt === value} onClick={() => onChange(opt)}>
          {opt === "ig_reel" ? "ig" : opt}
        </Pill>
      ))}
    </div>
  );
}

function Pill({ active, onClick, children }: { active: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button onClick={onClick} className="px-3 py-1 rounded-full whitespace-nowrap text-xs font-medium transition-all"
      style={{ background: active ? "var(--sf-text-primary)" : "var(--sf-bg-elevated)", color: active ? "var(--sf-bg-base)" : "var(--sf-text-secondary)" }}>
      {children}
    </button>
  );
}

function Card({ item, onRetry, onTagClick, onDetail }: { item: Item; onRetry: (id: number) => void; onTagClick: (tag: string) => void; onDetail: (id: number) => void }) {
  const failed = item.status === "failed";
  const pending = item.status === "pending";
  const preview = item.on_screen_text?.trim() || item.key_takeaways?.slice(0, 3).map((t) => `• ${t}`).join("\n") || "";

  return (
    <article
      className="rounded-lg p-4 transition-colors cursor-pointer group"
      style={{ background: "var(--sf-bg-surface)", border: "1px solid var(--sf-border)" }}
      onClick={() => onDetail(item.id)}
      onMouseEnter={(e) => e.currentTarget.style.background = "var(--sf-bg-hover)"}
      onMouseLeave={(e) => e.currentTarget.style.background = "var(--sf-bg-surface)"}
    >
      <div className="flex items-center gap-2 text-xs mb-2">
        <span className={`text-sm ${SOURCE_COLORS[item.source]}`} title={item.source}>{SOURCE_ICONS[item.source]}</span>
        {item.category && (
          <span className="px-2 py-0.5 rounded-full font-mono" style={{ background: item.category === "funny" ? "rgba(251,146,60,0.12)" : "var(--sf-bg-elevated)", color: item.category === "funny" ? "#fb923c" : "var(--sf-text-secondary)", fontSize: 11 }}>
            {item.category}
          </span>
        )}
        {failed && <span className="px-2 py-0.5 rounded-full font-mono" style={{ background: "rgba(243,114,127,0.12)", color: "var(--sf-negative)", fontSize: 11 }}>failed</span>}
        {pending && <span className="px-2 py-0.5 rounded-full font-mono" style={{ background: "rgba(255,164,43,0.12)", color: "var(--sf-warning)", fontSize: 11 }}>pending</span>}
        <span className="ml-auto font-mono" style={{ color: "var(--sf-text-muted)", fontSize: 11 }}>{relativeTime(item.saved_at)}</span>
      </div>
      {item.summary && <h2 className="text-sm leading-snug font-medium mb-1.5 line-clamp-3" style={{ color: "var(--sf-text-primary)" }}>{item.summary}</h2>}
      {preview && <p className="text-xs mb-2 line-clamp-2 whitespace-pre-wrap leading-relaxed" style={{ color: "var(--sf-text-secondary)" }}>{preview}</p>}
      {item.tags && item.tags.length > 0 && (
        <div className="flex flex-wrap gap-1 mb-2">
          {item.tags.map((t) => (
            <button key={t} onClick={(e) => { e.stopPropagation(); onTagClick(t); }} className="px-2 py-0.5 rounded-full font-mono transition-colors" style={{ background: "rgba(99,102,241,0.12)", color: "#818cf8", fontSize: 11 }}>#{t}</button>
          ))}
        </div>
      )}
      <div className="flex items-center gap-3 text-xs pt-1" style={{ color: "var(--sf-text-muted)" }}>
        {item.source_url && <a href={item.source_url} target="_blank" rel="noopener noreferrer" className="hover:underline" onClick={(e) => e.stopPropagation()} style={{ color: "var(--sf-text-secondary)" }}>↗ original</a>}
        {failed && <button onClick={(e) => { e.stopPropagation(); onRetry(item.id); }} className="ml-auto" style={{ color: "var(--sf-negative)" }}>↻ retry</button>}
      </div>
    </article>
  );
}

function relativeTime(iso: string): string {
  const d = new Date(iso);
  const diff = (Date.now() - d.getTime()) / 1000;
  if (diff < 60) return "now";
  if (diff < 3600) return `${Math.floor(diff / 60)}m`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h`;
  if (diff < 7 * 86400) return `${Math.floor(diff / 86400)}d`;
  return d.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

function DetailView({ itemId, onClose, onTagClick, onTagsChanged }: { itemId: number; onClose: () => void; onTagClick: (tag: string) => void; onTagsChanged: () => void }) {
  const [item, setItem] = useState<Item | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [tagInput, setTagInput] = useState("");
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    let alive = true;
    (async () => {
      try {
        const r = await fetch(`${API}/items/${itemId}`);
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        if (alive) setItem(await r.json());
      } catch (e) { if (alive) setErr(e instanceof Error ? e.message : String(e)); }
    })();
    return () => { alive = false; };
  }, [itemId]);

  useEffect(() => {
    const handler = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, [onClose]);

  const saveTags = async (tags: string[]) => {
    setSaving(true);
    try {
      await fetch(`${API}/items/${itemId}/tags`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ tags }) });
      setItem((prev) => prev ? { ...prev, tags } : prev);
      setTagInput("");
      onTagsChanged();
    } finally { setSaving(false); }
  };

  const addTag = async () => { const t = tagInput.trim().toLowerCase(); if (!t || !item) return; await saveTags([...(item.tags || []), t].filter((v, i, a) => a.indexOf(v) === i)); };
  const removeTag = async (tag: string) => { if (!item) return; await saveTags((item.tags || []).filter((t) => t !== tag)); };

  return (
    <div className="fixed inset-0 z-50 flex justify-end" onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="absolute inset-0" style={{ background: "rgba(0,0,0,0.6)" }} />
      <div className="relative w-full max-w-lg h-full overflow-y-auto animate-slide-in" style={{ background: "var(--sf-bg-surface)", boxShadow: "var(--sf-shadow-heavy)" }}>
        <div className="sticky top-0 z-10 px-5 py-4 flex items-center gap-2" style={{ background: "var(--sf-bg-surface)", borderBottom: "1px solid var(--sf-border)" }}>
          <button onClick={onClose} style={{ color: "var(--sf-text-secondary)" }} className="text-sm hover:underline">← back</button>
          <span className="ml-auto text-xs font-mono" style={{ color: "var(--sf-text-muted)" }}>#{itemId}</span>
        </div>
        {err && <p className="p-5 text-sm" style={{ color: "var(--sf-negative)" }}>{err}</p>}
        {item && (
          <div className="p-5 space-y-5">
            <div className="flex items-center gap-2 flex-wrap text-xs">
              <span className={`text-base ${SOURCE_COLORS[item.source]}`}>{SOURCE_ICONS[item.source]}</span>
              <span className="px-2 py-0.5 rounded-full font-mono" style={{ background: "var(--sf-bg-elevated)", color: "var(--sf-text-secondary)", fontSize: 11 }}>{item.source === "ig_reel" ? "ig" : item.source}</span>
              {item.category && <span className="px-2 py-0.5 rounded-full font-mono" style={{ background: "var(--sf-bg-elevated)", color: "var(--sf-text-secondary)", fontSize: 11 }}>{item.category}</span>}
              {item.kind && <span className="px-2 py-0.5 rounded-full font-mono" style={{ background: "var(--sf-bg-elevated)", color: "var(--sf-text-secondary)", fontSize: 11 }}>{item.kind}</span>}
              <span className="ml-auto font-mono" style={{ color: "var(--sf-text-muted)", fontSize: 11 }}>{new Date(item.saved_at).toLocaleString()}</span>
            </div>
            {item.source_url && <a href={item.source_url} target="_blank" rel="noopener noreferrer" className="text-xs hover:underline break-all" style={{ color: "var(--sf-info)" }}>{item.source_url}</a>}
            {item.summary && <Section title="Summary"><p className="text-sm leading-relaxed" style={{ color: "var(--sf-text-primary)" }}>{item.summary}</p></Section>}
            {item.key_takeaways && item.key_takeaways.length > 0 && (
              <Section title="Key Takeaways">
                <ul className="space-y-1.5">
                  {item.key_takeaways.map((t, i) => <li key={i} className="flex gap-2 text-sm" style={{ color: "var(--sf-text-secondary)" }}><span style={{ color: "var(--sf-accent)" }}>•</span><span>{t}</span></li>)}
                </ul>
              </Section>
            )}
            {item.on_screen_text && <Section title="On-screen Text"><p className="text-sm whitespace-pre-wrap leading-relaxed" style={{ color: "var(--sf-text-secondary)" }}>{item.on_screen_text}</p></Section>}
            {item.transcript && <Collapsible title="Transcript"><p className="text-sm whitespace-pre-wrap leading-relaxed" style={{ color: "var(--sf-text-secondary)" }}>{item.transcript}</p></Collapsible>}
            {item.raw_text && <Collapsible title="Raw Text"><pre className="text-xs whitespace-pre-wrap break-words p-3 rounded-lg" style={{ background: "var(--sf-bg-elevated)", color: "var(--sf-text-muted)" }}>{item.raw_text}</pre></Collapsible>}
            <Section title="Tags">
              <div className="flex flex-wrap gap-1.5 mb-3">
                {(item.tags || []).length === 0 && <span className="text-xs" style={{ color: "var(--sf-text-muted)" }}>No tags yet</span>}
                {(item.tags || []).map((t) => (
                  <span key={t} className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full font-mono" style={{ background: "rgba(99,102,241,0.12)", color: "#818cf8", fontSize: 11 }}>
                    <button onClick={() => onTagClick(t)}>#{t}</button>
                    <button onClick={() => removeTag(t)} className="opacity-50 hover:opacity-100 ml-0.5">×</button>
                  </span>
                ))}
              </div>
              <form onSubmit={(e) => { e.preventDefault(); addTag(); }} className="flex gap-2">
                <input type="text" value={tagInput} onChange={(e) => setTagInput(e.target.value)} placeholder="add tag…" className="flex-1 px-3 py-1.5 text-xs rounded-full focus:outline-none" style={{ background: "var(--sf-bg-elevated)", color: "var(--sf-text-primary)", border: "1px solid var(--sf-border)" }} disabled={saving} />
                <button type="submit" disabled={saving || !tagInput.trim()} className="px-3 py-1.5 text-xs rounded-full font-medium transition-colors disabled:opacity-30" style={{ background: "var(--sf-bg-elevated)", color: "var(--sf-text-secondary)" }}>add</button>
              </form>
            </Section>
          </div>
        )}
        {!item && !err && <p className="p-5 text-sm" style={{ color: "var(--sf-text-muted)" }}>Loading…</p>}
      </div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <h3 className="text-xs font-bold uppercase tracking-widest mb-2" style={{ color: "var(--sf-text-muted)", letterSpacing: "2px" }}>{title}</h3>
      {children}
    </div>
  );
}

function Collapsible({ title, children }: { title: string; children: React.ReactNode }) {
  const [open, setOpen] = useState(false);
  return (
    <div>
      <button onClick={() => setOpen(!open)} className="text-xs font-bold uppercase tracking-widest mb-2 hover:opacity-80 transition-opacity" style={{ color: "var(--sf-text-muted)", letterSpacing: "2px" }}>
        {open ? "▾" : "▸"} {title}
      </button>
      {open && <div className="animate-fade-in">{children}</div>}
    </div>
  );
}
