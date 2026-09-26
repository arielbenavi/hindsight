import { useCallback, useEffect, useRef, useState } from "react";
import { CATEGORIES, SOURCES, type Item, type Source } from "./types";

const API = (import.meta.env.VITE_API_URL as string | undefined) || "http://localhost:8000";

type Health = {
  ok: boolean;
  warn: boolean;
  message: string;
  last_5_auth_failed: number;
};

type SweepSource = {
  authenticated: boolean;
  last_sweep: string | null;
  last_sweep_result: { processed: number; skipped: number; failed: number } | null;
};

type SweepSource_IG = SweepSource & { session_status: string };

type SweepStatus = {
  twitter: SweepSource;
  ig_saved: SweepSource_IG;
};

type DryRun = {
  ig_cookies: { status: string; message: string; age_days?: number };
  twitter: { status: string; message: string };
  gemini: { status: string; message: string };
  ytdlp: { status: string; message: string };
  all_ok: boolean;
};

const SOURCE_ICONS: Record<Source, string> = {
  ig_reel: "◎",
  tweet: "𝕏",
  web: "◆",
  note: "✎",
};

const SOURCE_COLORS: Record<Source, string> = {
  ig_reel: "text-pink-400",
  tweet: "text-sky-400",
  web: "text-emerald-400",
  note: "text-amber-400",
};

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
  const [showSettings, setShowSettings] = useState(false);
  const [dryRun, setDryRun] = useState<DryRun | null>(null);

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
    try {
      const r = await fetch(`${API}/items?${params.toString()}`);
      if (!r.ok) throw new Error(`HTTP ${r.status}`);
      setItems(await r.json());
    } catch (e) {
      setErr(e instanceof Error ? e.message : String(e));
    } finally {
      setLoading(false);
    }
  }, [category, source, tag, debouncedQ]);

  useEffect(() => { refetch(); }, [refetch]);
  useEffect(() => {
    const t = setInterval(refetch, 15000);
    return () => clearInterval(t);
  }, [refetch]);

  useEffect(() => {
    let alive = true;
    const go = async () => {
      try {
        const [hRes, sRes] = await Promise.all([
          fetch(`${API}/health`),
          fetch(`${API}/sweep/status`),
        ]);
        if (hRes.ok && alive) setHealth(await hRes.json());
        if (sRes.ok && alive) setSweepStatus(await sRes.json());
      } catch { /* handled by items fetch */ }
    };
    go();
    const t = setInterval(go, 60_000);
    return () => { alive = false; clearInterval(t); };
  }, []);

  const fetchDryRun = async () => {
    try {
      const r = await fetch(`${API}/sweep/dry-run`);
      if (r.ok) setDryRun(await r.json());
    } catch { /* ignore */ }
  };

  const onRetry = async (id: number) => {
    try {
      await fetch(`${API}/items/${id}/retry`, { method: "POST" });
      refetch();
    } catch (e) {
      console.error("retry failed", e);
    }
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
            <h1 className="text-base font-bold tracking-tight" style={{ color: "var(--sf-text-primary)" }}>
              savefeed
            </h1>
            <span className="text-xs font-mono" style={{ color: "var(--sf-text-muted)" }}>
              {loading ? "…" : `${items.length}`}
            </span>

            {sweepStatus && <SweepIndicators status={sweepStatus} />}

            <div className="ml-auto flex items-center gap-2">
              <button
                onClick={() => { setShowSettings(!showSettings); if (!showSettings) fetchDryRun(); }}
                className="p-1.5 rounded-full transition-colors"
                style={{ color: showSettings ? "var(--sf-accent)" : "var(--sf-text-muted)", background: showSettings ? "rgba(30,215,96,0.1)" : "transparent" }}
                title="System health"
              >
                ⚙
              </button>
              <button
                onClick={refetch}
                className="text-xs px-3 py-1.5 rounded-full font-medium transition-colors"
                style={{ background: "var(--sf-bg-elevated)", color: "var(--sf-text-secondary)" }}
              >
                ↻
              </button>
            </div>
          </div>

          <div className="relative mb-3">
            <input
              type="search"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="Search summaries, transcripts, on-screen text…"
              className="w-full px-4 py-2.5 pr-8 text-sm focus:outline-none"
              style={{
                background: "var(--sf-bg-elevated)",
                color: "var(--sf-text-primary)",
                borderRadius: "var(--sf-radius-pill)",
                border: "1px solid transparent",
              }}
              onFocus={(e) => e.currentTarget.style.borderColor = "var(--sf-border-light)"}
              onBlur={(e) => e.currentTarget.style.borderColor = "transparent"}
            />
            {q && (
              <button
                type="button"
                onClick={() => setQ("")}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-lg leading-none px-1"
                style={{ color: "var(--sf-text-muted)" }}
              >×</button>
            )}
          </div>

          <div className="flex gap-2 overflow-x-auto pb-1">
            <FilterGroup label="source" options={SOURCES} value={source} onChange={setSource} />
            <span style={{ width: 1, background: "var(--sf-border)", margin: "4px 4px" }} />
            <FilterGroup label="category" options={[...CATEGORIES]} value={category} onChange={setCategory} />
          </div>

          {tag && (
            <div className="mt-2 flex items-center gap-1">
              <button
                onClick={() => setTag("")}
                className="px-3 py-1 rounded-full font-mono text-xs transition-colors"
                style={{ background: "rgba(99,102,241,0.15)", color: "#818cf8" }}
              >
                #{tag} ×
              </button>
            </div>
          )}

          {err && (
            <p className="mt-2 text-xs" style={{ color: "var(--sf-negative)" }}>
              Connection error: {err} — is the server running?
            </p>
          )}
        </div>
      </header>

      {showSettings && <SettingsPanel dryRun={dryRun} onClose={() => setShowSettings(false)} />}

      <main className="max-w-3xl mx-auto px-4 py-4 space-y-3">
        {items.map((item) => (
          <Card key={item.id} item={item} onRetry={onRetry} onTagClick={setTag} onDetail={setDetailId} />
        ))}
        {!loading && items.length === 0 && !err && (
          <p className="text-center py-12 text-sm" style={{ color: "var(--sf-text-muted)" }}>
            Nothing matches these filters.
          </p>
        )}
      </main>

      {detailId !== null && (
        <DetailView
          itemId={detailId}
          onClose={() => setDetailId(null)}
          onTagClick={(t) => { setDetailId(null); setTag(t); }}
          onTagsChanged={refetch}
        />
      )}
    </div>
  );
}

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
    <button
      onClick={onClick}
      className="px-3 py-1 rounded-full whitespace-nowrap text-xs font-medium transition-all"
      style={{
        background: active ? "var(--sf-text-primary)" : "var(--sf-bg-elevated)",
        color: active ? "var(--sf-bg-base)" : "var(--sf-text-secondary)",
      }}
    >
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
        <span className={`text-sm ${SOURCE_COLORS[item.source]}`} title={item.source}>
          {SOURCE_ICONS[item.source]}
        </span>
        {item.category && (
          <span className="px-2 py-0.5 rounded-full font-mono" style={{ background: "var(--sf-bg-elevated)", color: "var(--sf-text-secondary)", fontSize: 11 }}>
            {item.category}
          </span>
        )}
        {failed && (
          <span className="px-2 py-0.5 rounded-full font-mono" style={{ background: "rgba(243,114,127,0.12)", color: "var(--sf-negative)", fontSize: 11 }}>
            failed
          </span>
        )}
        {pending && (
          <span className="px-2 py-0.5 rounded-full font-mono" style={{ background: "rgba(255,164,43,0.12)", color: "var(--sf-warning)", fontSize: 11 }}>
            pending
          </span>
        )}
        <span className="ml-auto font-mono" style={{ color: "var(--sf-text-muted)", fontSize: 11 }}>
          {relativeTime(item.saved_at)}
        </span>
      </div>

      {item.summary && (
        <h2 className="text-sm leading-snug font-medium mb-1.5 line-clamp-3" style={{ color: "var(--sf-text-primary)" }}>
          {item.summary}
        </h2>
      )}

      {preview && (
        <p className="text-xs mb-2 line-clamp-2 whitespace-pre-wrap leading-relaxed" style={{ color: "var(--sf-text-secondary)" }}>
          {preview}
        </p>
      )}

      {item.tags && item.tags.length > 0 && (
        <div className="flex flex-wrap gap-1 mb-2">
          {item.tags.map((t) => (
            <button
              key={t}
              onClick={(e) => { e.stopPropagation(); onTagClick(t); }}
              className="px-2 py-0.5 rounded-full font-mono transition-colors"
              style={{ background: "rgba(99,102,241,0.12)", color: "#818cf8", fontSize: 11 }}
            >
              #{t}
            </button>
          ))}
        </div>
      )}

      <div className="flex items-center gap-3 text-xs pt-1" style={{ color: "var(--sf-text-muted)" }}>
        {item.source_url && (
          <a
            href={item.source_url}
            target="_blank"
            rel="noopener noreferrer"
            className="hover:underline"
            onClick={(e) => e.stopPropagation()}
            style={{ color: "var(--sf-text-secondary)" }}
          >
            ↗ original
          </a>
        )}
        {failed && (
          <button
            onClick={(e) => { e.stopPropagation(); onRetry(item.id); }}
            className="ml-auto"
            style={{ color: "var(--sf-negative)" }}
          >
            ↻ retry
          </button>
        )}
      </div>
    </article>
  );
}

function SettingsPanel({ dryRun, onClose }: { dryRun: DryRun | null; onClose: () => void }) {
  const statusIcon = (s: string) => s === "ok" ? "✓" : s === "warn" ? "⚠" : "✗";
  const statusColor = (s: string) => s === "ok" ? "var(--sf-accent)" : s === "warn" ? "var(--sf-warning)" : "var(--sf-negative)";

  return (
    <div className="max-w-3xl mx-auto px-4 py-3 animate-fade-in" style={{ borderBottom: "1px solid var(--sf-border)" }}>
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-xs font-bold uppercase tracking-widest" style={{ color: "var(--sf-text-muted)", letterSpacing: "2px" }}>System Health</h3>
        <div className="flex items-center gap-2">
          <a href={`${API}/setup`} target="_blank" rel="noopener" className="text-xs px-3 py-1 rounded-full" style={{ background: "var(--sf-bg-elevated)", color: "var(--sf-text-secondary)" }}>
            Setup Guide ↗
          </a>
          <button onClick={onClose} className="text-lg leading-none px-1" style={{ color: "var(--sf-text-muted)" }}>×</button>
        </div>
      </div>
      {dryRun ? (
        <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
          {(["ig_cookies", "twitter", "gemini", "ytdlp"] as const).map((key) => {
            const check = dryRun[key];
            return (
              <div key={key} className="rounded-lg p-3" style={{ background: "var(--sf-bg-elevated)" }}>
                <div className="flex items-center gap-1.5 mb-1">
                  <span style={{ color: statusColor(check.status), fontSize: 12 }}>{statusIcon(check.status)}</span>
                  <span className="text-xs font-medium" style={{ color: "var(--sf-text-primary)" }}>
                    {key === "ig_cookies" ? "Instagram" : key === "twitter" ? "Twitter" : key === "gemini" ? "Gemini" : "yt-dlp"}
                  </span>
                </div>
                <p className="text-xs leading-snug" style={{ color: "var(--sf-text-muted)" }}>{check.message}</p>
              </div>
            );
          })}
        </div>
      ) : (
        <p className="text-xs" style={{ color: "var(--sf-text-muted)" }}>Loading checks…</p>
      )}
    </div>
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

function DetailView({ itemId, onClose, onTagClick, onTagsChanged }: {
  itemId: number;
  onClose: () => void;
  onTagClick: (tag: string) => void;
  onTagsChanged: () => void;
}) {
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
        const data = await r.json();
        if (alive) setItem(data);
      } catch (e) {
        if (alive) setErr(e instanceof Error ? e.message : String(e));
      }
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
      await fetch(`${API}/items/${itemId}/tags`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ tags }),
      });
      setItem((prev) => prev ? { ...prev, tags } : prev);
      setTagInput("");
      onTagsChanged();
    } finally {
      setSaving(false);
    }
  };

  const addTag = async () => {
    const t = tagInput.trim().toLowerCase();
    if (!t || !item) return;
    const next = [...(item.tags || []), t].filter((v, i, a) => a.indexOf(v) === i);
    await saveTags(next);
  };

  const removeTag = async (tag: string) => {
    if (!item) return;
    await saveTags((item.tags || []).filter((t) => t !== tag));
  };

  return (
    <div className="fixed inset-0 z-50 flex justify-end" onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="absolute inset-0" style={{ background: "rgba(0,0,0,0.6)" }} />
      <div
        className="relative w-full max-w-lg h-full overflow-y-auto animate-slide-in"
        style={{ background: "var(--sf-bg-surface)", boxShadow: "var(--sf-shadow-heavy)" }}
      >
        <div className="sticky top-0 z-10 px-5 py-4 flex items-center gap-2" style={{ background: "var(--sf-bg-surface)", borderBottom: "1px solid var(--sf-border)" }}>
          <button onClick={onClose} style={{ color: "var(--sf-text-secondary)" }} className="text-sm hover:underline">
            ← back
          </button>
          <span className="ml-auto text-xs font-mono" style={{ color: "var(--sf-text-muted)" }}>#{itemId}</span>
        </div>

        {err && <p className="p-5 text-sm" style={{ color: "var(--sf-negative)" }}>{err}</p>}

        {item && (
          <div className="p-5 space-y-5">
            <div className="flex items-center gap-2 flex-wrap text-xs">
              <span className={`text-base ${SOURCE_COLORS[item.source]}`}>{SOURCE_ICONS[item.source]}</span>
              <span className="px-2 py-0.5 rounded-full font-mono" style={{ background: "var(--sf-bg-elevated)", color: "var(--sf-text-secondary)", fontSize: 11 }}>
                {item.source === "ig_reel" ? "ig" : item.source}
              </span>
              {item.category && (
                <span className="px-2 py-0.5 rounded-full font-mono" style={{ background: "var(--sf-bg-elevated)", color: "var(--sf-text-secondary)", fontSize: 11 }}>
                  {item.category}
                </span>
              )}
              {item.kind && (
                <span className="px-2 py-0.5 rounded-full font-mono" style={{ background: "var(--sf-bg-elevated)", color: "var(--sf-text-secondary)", fontSize: 11 }}>
                  {item.kind}
                </span>
              )}
              <span className="ml-auto font-mono" style={{ color: "var(--sf-text-muted)", fontSize: 11 }}>
                {new Date(item.saved_at).toLocaleString()}
              </span>
            </div>

            {item.source_url && (
              <a href={item.source_url} target="_blank" rel="noopener noreferrer" className="text-xs hover:underline break-all" style={{ color: "var(--sf-info)" }}>
                {item.source_url}
              </a>
            )}

            {item.summary && (
              <Section title="Summary">
                <p className="text-sm leading-relaxed" style={{ color: "var(--sf-text-primary)" }}>{item.summary}</p>
              </Section>
            )}

            {item.key_takeaways && item.key_takeaways.length > 0 && (
              <Section title="Key Takeaways">
                <ul className="space-y-1.5">
                  {item.key_takeaways.map((t, i) => (
                    <li key={i} className="flex gap-2 text-sm" style={{ color: "var(--sf-text-secondary)" }}>
                      <span style={{ color: "var(--sf-accent)" }}>•</span>
                      <span>{t}</span>
                    </li>
                  ))}
                </ul>
              </Section>
            )}

            {item.on_screen_text && (
              <Section title="On-screen Text">
                <p className="text-sm whitespace-pre-wrap leading-relaxed" style={{ color: "var(--sf-text-secondary)" }}>{item.on_screen_text}</p>
              </Section>
            )}

            {item.transcript && (
              <Collapsible title="Transcript">
                <p className="text-sm whitespace-pre-wrap leading-relaxed" style={{ color: "var(--sf-text-secondary)" }}>{item.transcript}</p>
              </Collapsible>
            )}

            {item.raw_text && (
              <Collapsible title="Raw Text">
                <pre className="text-xs whitespace-pre-wrap break-words p-3 rounded-lg" style={{ background: "var(--sf-bg-elevated)", color: "var(--sf-text-muted)" }}>
                  {item.raw_text}
                </pre>
              </Collapsible>
            )}

            <Section title="Tags">
              <div className="flex flex-wrap gap-1.5 mb-3">
                {(item.tags || []).length === 0 && (
                  <span className="text-xs" style={{ color: "var(--sf-text-muted)" }}>No tags yet</span>
                )}
                {(item.tags || []).map((t) => (
                  <span key={t} className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full font-mono" style={{ background: "rgba(99,102,241,0.12)", color: "#818cf8", fontSize: 11 }}>
                    <button onClick={() => onTagClick(t)}>#{t}</button>
                    <button onClick={() => removeTag(t)} className="opacity-50 hover:opacity-100 ml-0.5">×</button>
                  </span>
                ))}
              </div>
              <form onSubmit={(e) => { e.preventDefault(); addTag(); }} className="flex gap-2">
                <input
                  type="text"
                  value={tagInput}
                  onChange={(e) => setTagInput(e.target.value)}
                  placeholder="add tag…"
                  className="flex-1 px-3 py-1.5 text-xs rounded-full focus:outline-none"
                  style={{ background: "var(--sf-bg-elevated)", color: "var(--sf-text-primary)", border: "1px solid var(--sf-border)" }}
                  disabled={saving}
                />
                <button
                  type="submit"
                  disabled={saving || !tagInput.trim()}
                  className="px-3 py-1.5 text-xs rounded-full font-medium transition-colors disabled:opacity-30"
                  style={{ background: "var(--sf-bg-elevated)", color: "var(--sf-text-secondary)" }}
                >
                  add
                </button>
              </form>
            </Section>
          </div>
        )}

        {!item && !err && (
          <p className="p-5 text-sm" style={{ color: "var(--sf-text-muted)" }}>Loading…</p>
        )}
      </div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <h3 className="text-xs font-bold uppercase tracking-widest mb-2" style={{ color: "var(--sf-text-muted)", letterSpacing: "2px" }}>
        {title}
      </h3>
      {children}
    </div>
  );
}

function Collapsible({ title, children }: { title: string; children: React.ReactNode }) {
  const [open, setOpen] = useState(false);
  return (
    <div>
      <button
        onClick={() => setOpen(!open)}
        className="text-xs font-bold uppercase tracking-widest mb-2 hover:opacity-80 transition-opacity"
        style={{ color: "var(--sf-text-muted)", letterSpacing: "2px" }}
      >
        {open ? "▾" : "▸"} {title}
      </button>
      {open && <div className="animate-fade-in">{children}</div>}
    </div>
  );
}
