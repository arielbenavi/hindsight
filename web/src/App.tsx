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

  useEffect(() => {
    refetch();
  }, [refetch]);

  useEffect(() => {
    const t = setInterval(refetch, 15000);
    return () => clearInterval(t);
  }, [refetch]);

  useEffect(() => {
    let alive = true;
    const fetchHealth = async () => {
      try {
        const r = await fetch(`${API}/health`);
        if (!r.ok) return;
        const h = (await r.json()) as Health;
        if (alive) setHealth(h);
      } catch {
        // network errors handled by the items fetch's err banner
      }
    };
    fetchHealth();
    const t = setInterval(fetchHealth, 60_000);
    return () => {
      alive = false;
      clearInterval(t);
    };
  }, []);

  useEffect(() => {
    let alive = true;
    const fetchSweep = async () => {
      try {
        const r = await fetch(`${API}/sweep/status`);
        if (!r.ok) return;
        const s = (await r.json()) as SweepStatus;
        if (alive) setSweepStatus(s);
      } catch { /* ignore */ }
    };
    fetchSweep();
    const t = setInterval(fetchSweep, 60_000);
    return () => { alive = false; clearInterval(t); };
  }, []);

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
    <div className="min-h-full">
      {showHealthBanner && (
        <div className="bg-amber-100 dark:bg-amber-950 border-b border-amber-300 dark:border-amber-800 text-amber-900 dark:text-amber-200">
          <div className="max-w-2xl mx-auto px-3 py-2 flex items-start gap-2 text-sm">
            <span className="font-semibold shrink-0">⚠</span>
            <p className="flex-1">{health!.message}</p>
            <button
              onClick={() => setHealthDismissed(true)}
              className="text-amber-700 dark:text-amber-300 hover:text-amber-900 dark:hover:text-amber-100 px-1 text-lg leading-none shrink-0"
              aria-label="dismiss"
            >
              ×
            </button>
          </div>
        </div>
      )}
      <header className="sticky top-0 z-10 bg-stone-50/90 dark:bg-stone-950/90 backdrop-blur border-b border-stone-200 dark:border-stone-800">
        <div className="max-w-2xl mx-auto px-3 py-2.5 space-y-2">
          <div className="flex items-center gap-2">
            <h1 className="text-sm font-semibold text-stone-700 dark:text-stone-300">
              savefeed
            </h1>
            <span className="text-xs text-stone-400">
              {loading ? "…" : `${items.length} item${items.length === 1 ? "" : "s"}`}
            </span>
            <button
              onClick={refetch}
              className="ml-auto text-xs text-stone-500 hover:text-stone-900 dark:hover:text-stone-100 px-2 py-1 rounded hover:bg-stone-100 dark:hover:bg-stone-800"
            >
              ↻ refresh
            </button>
          </div>

          <div className="relative">
            <input
              type="search"
              value={q}
              onChange={(e) => setQ(e.target.value)}
              placeholder="search summary, transcript, on-screen text…"
              className="w-full px-3 py-2 pr-8 rounded-md border border-stone-300 dark:border-stone-700 bg-white dark:bg-stone-900 text-sm focus:outline-none focus:ring-2 focus:ring-stone-400 dark:text-stone-100"
            />
            {q && (
              <button
                type="button"
                onClick={() => setQ("")}
                aria-label="clear search"
                className="absolute right-2 top-1/2 -translate-y-1/2 text-stone-400 hover:text-stone-700 dark:hover:text-stone-200 text-lg leading-none px-1"
              >
                ×
              </button>
            )}
          </div>

          <PillRow label="cat" options={CATEGORIES} value={category} onChange={setCategory} />
          <PillRow label="src" options={SOURCES} value={source} onChange={setSource} />

          {tag && (
            <div className="flex items-center gap-1 text-xs">
              <span className="text-stone-400 mr-1 shrink-0">tag:</span>
              <button
                onClick={() => setTag("")}
                className="px-2.5 py-0.5 rounded-full whitespace-nowrap font-mono text-[11px] bg-indigo-600 text-white hover:bg-indigo-700"
                title="clear tag filter"
              >
                {tag} ×
              </button>
            </div>
          )}

          {err && (
            <p className="text-xs text-red-600 dark:text-red-400">
              api error: {err} — is uvicorn running on {API}?
            </p>
          )}
        </div>
      </header>

      {sweepStatus && <SweepBar status={sweepStatus} />}

      <main className="max-w-2xl mx-auto px-3 py-3 space-y-2.5">
        {items.map((item) => (
          <Card key={item.id} item={item} onRetry={onRetry} onTagClick={setTag} onDetail={setDetailId} />
        ))}
        {!loading && items.length === 0 && !err && (
          <p className="text-stone-400 text-sm text-center py-8">
            nothing matches these filters.
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

type PillRowProps = {
  label: string;
  options: readonly string[];
  value: string;
  onChange: (v: string) => void;
};

function PillRow({ label, options, value, onChange }: PillRowProps) {
  return (
    <div className="flex items-center gap-1 overflow-x-auto text-xs -mx-1 px-1">
      <span className="text-stone-400 mr-1 shrink-0">{label}</span>
      <Pill active={!value} onClick={() => onChange("")}>
        all
      </Pill>
      {options.map((opt) => (
        <Pill key={opt} active={opt === value} onClick={() => onChange(opt)}>
          {opt}
        </Pill>
      ))}
    </div>
  );
}

function Pill({
  active,
  onClick,
  children,
}: {
  active: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      onClick={onClick}
      className={
        "px-2.5 py-0.5 rounded-full whitespace-nowrap font-mono text-[11px] transition " +
        (active
          ? "bg-stone-900 text-stone-100 dark:bg-stone-100 dark:text-stone-900"
          : "bg-stone-100 dark:bg-stone-800 text-stone-600 dark:text-stone-300 hover:bg-stone-200 dark:hover:bg-stone-700")
      }
    >
      {children}
    </button>
  );
}

function Card({
  item,
  onRetry,
  onTagClick,
  onDetail,
}: {
  item: Item;
  onRetry: (id: number) => void;
  onTagClick: (tag: string) => void;
  onDetail: (id: number) => void;
}) {
  const failed = item.status === "failed";
  const pending = item.status === "pending";
  const preview =
    item.on_screen_text?.trim() ||
    item.key_takeaways?.slice(0, 3).map((t) => `• ${t}`).join("\n") ||
    "";

  return (
    <article className="rounded-lg bg-white dark:bg-stone-900 border border-stone-200 dark:border-stone-800 p-3 shadow-sm">
      <div className="flex items-center gap-1.5 text-xs mb-1.5 flex-wrap">
        <Chip>{labelForSource(item.source)}</Chip>
        {item.category && <Chip>{item.category}</Chip>}
        {failed && (
          <Chip className="bg-red-100 dark:bg-red-950 text-red-700 dark:text-red-300">
            failed
          </Chip>
        )}
        {pending && (
          <Chip className="bg-amber-100 dark:bg-amber-950 text-amber-800 dark:text-amber-300">
            pending
          </Chip>
        )}
        <span className="ml-auto text-stone-400 shrink-0">
          {relativeTime(item.saved_at)}
        </span>
      </div>

      {item.summary && (
        <h2 className="text-[15px] leading-snug text-stone-900 dark:text-stone-100 font-medium mb-1.5 line-clamp-4">
          {item.summary}
        </h2>
      )}

      {preview && (
        <p className="text-sm text-stone-500 dark:text-stone-400 mb-2 line-clamp-3 whitespace-pre-wrap">
          {preview}
        </p>
      )}

      {item.tags && item.tags.length > 0 && (
        <div className="flex flex-wrap gap-1 mb-2">
          {item.tags.map((t) => (
            <button
              key={t}
              onClick={() => onTagClick(t)}
              className="px-1.5 py-0.5 rounded font-mono text-[11px] bg-indigo-50 text-indigo-700 hover:bg-indigo-100 dark:bg-indigo-950 dark:text-indigo-300 dark:hover:bg-indigo-900"
              title={`filter by #${t}`}
            >
              #{t}
            </button>
          ))}
        </div>
      )}

      <div className="flex items-center gap-3 text-xs pt-1">
        {item.source_url && (
          <a
            href={item.source_url}
            target="_blank"
            rel="noopener noreferrer"
            className="text-stone-600 dark:text-stone-300 hover:text-stone-900 dark:hover:text-stone-100"
          >
            ↗ open original
          </a>
        )}
        <button
          onClick={() => onDetail(item.id)}
          className="text-stone-600 dark:text-stone-300 hover:text-stone-900 dark:hover:text-stone-100"
        >
          details →
        </button>
        {failed && (
          <button
            onClick={() => onRetry(item.id)}
            className="ml-auto text-red-600 dark:text-red-400 hover:text-red-800 dark:hover:text-red-200"
          >
            ↻ retry
          </button>
        )}
      </div>
    </article>
  );
}

function Chip({
  children,
  className = "",
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <span
      className={
        "px-2 py-0.5 rounded-full font-mono text-[11px] " +
        (className ||
          "bg-stone-100 dark:bg-stone-800 text-stone-700 dark:text-stone-300")
      }
    >
      {children}
    </span>
  );
}

function labelForSource(s: Source): string {
  return s === "ig_reel" ? "ig" : s;
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

function DetailView({
  itemId,
  onClose,
  onTagClick,
  onTagsChanged,
}: {
  itemId: number;
  onClose: () => void;
  onTagClick: (tag: string) => void;
  onTagsChanged: () => void;
}) {
  const [item, setItem] = useState<Item | null>(null);
  const [err, setErr] = useState<string | null>(null);
  const [tagInput, setTagInput] = useState("");
  const [saving, setSaving] = useState(false);
  const panelRef = useRef<HTMLDivElement>(null);

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

  return (
    <div className="fixed inset-0 z-50 flex justify-end" onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="absolute inset-0 bg-black/30" />
      <div
        ref={panelRef}
        className="relative w-full max-w-lg bg-white dark:bg-stone-900 h-full overflow-y-auto shadow-xl animate-slide-in"
      >
        <div className="sticky top-0 z-10 bg-white/90 dark:bg-stone-900/90 backdrop-blur border-b border-stone-200 dark:border-stone-800 px-4 py-3 flex items-center gap-2">
          <button
            onClick={onClose}
            className="text-stone-500 hover:text-stone-900 dark:hover:text-stone-100 text-lg"
          >
            ← back
          </button>
          <span className="ml-auto text-xs text-stone-400">#{itemId}</span>
        </div>

        {err && <p className="p-4 text-red-600 text-sm">{err}</p>}

        {item && (
          <div className="p-4 space-y-4">
            <div className="flex items-center gap-1.5 flex-wrap text-xs">
              <Chip>{labelForSource(item.source)}</Chip>
              {item.category && <Chip>{item.category}</Chip>}
              {item.kind && <Chip>{item.kind}</Chip>}
              <span className="ml-auto text-stone-400">
                {new Date(item.saved_at).toLocaleString()}
              </span>
            </div>

            {item.source_url && (
              <a
                href={item.source_url}
                target="_blank"
                rel="noopener noreferrer"
                className="text-xs text-indigo-600 dark:text-indigo-400 hover:underline break-all"
              >
                {item.source_url}
              </a>
            )}

            {item.summary && (
              <Section title="summary">
                <p className="text-[15px] leading-relaxed text-stone-900 dark:text-stone-100">
                  {item.summary}
                </p>
              </Section>
            )}

            {item.key_takeaways && item.key_takeaways.length > 0 && (
              <Section title="key takeaways">
                <ul className="list-disc list-inside space-y-1 text-sm text-stone-700 dark:text-stone-300">
                  {item.key_takeaways.map((t, i) => <li key={i}>{t}</li>)}
                </ul>
              </Section>
            )}

            {item.on_screen_text && (
              <Section title="on-screen text">
                <p className="text-sm text-stone-600 dark:text-stone-400 whitespace-pre-wrap">
                  {item.on_screen_text}
                </p>
              </Section>
            )}

            {item.transcript && (
              <Section title="transcript">
                <p className="text-sm text-stone-600 dark:text-stone-400 whitespace-pre-wrap">
                  {item.transcript}
                </p>
              </Section>
            )}

            {item.raw_text && (
              <Collapsible title="raw text">
                <p className="text-sm text-stone-500 dark:text-stone-400 whitespace-pre-wrap break-words">
                  {item.raw_text}
                </p>
              </Collapsible>
            )}

            <Section title="tags">
              <div className="flex flex-wrap gap-1 mb-2">
                {(item.tags || []).map((t) => (
                  <span key={t} className="inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded font-mono text-[11px] bg-indigo-50 text-indigo-700 dark:bg-indigo-950 dark:text-indigo-300">
                    <button onClick={() => onTagClick(t)} title={`filter by #${t}`}>#{t}</button>
                    <button onClick={() => removeTag(t)} className="ml-0.5 text-indigo-400 hover:text-red-500" title="remove">×</button>
                  </span>
                ))}
              </div>
              <form onSubmit={(e) => { e.preventDefault(); addTag(); }} className="flex gap-1">
                <input
                  type="text"
                  value={tagInput}
                  onChange={(e) => setTagInput(e.target.value)}
                  placeholder="add tag…"
                  className="flex-1 px-2 py-1 text-xs rounded border border-stone-300 dark:border-stone-700 bg-white dark:bg-stone-800 dark:text-stone-100 focus:outline-none focus:ring-1 focus:ring-stone-400"
                  disabled={saving}
                />
                <button
                  type="submit"
                  disabled={saving || !tagInput.trim()}
                  className="px-2 py-1 text-xs rounded bg-stone-200 dark:bg-stone-700 text-stone-700 dark:text-stone-300 hover:bg-stone-300 dark:hover:bg-stone-600 disabled:opacity-40"
                >
                  add
                </button>
              </form>
            </Section>
          </div>
        )}

        {!item && !err && (
          <p className="p-4 text-sm text-stone-400">loading…</p>
        )}
      </div>
    </div>
  );
}


function SweepSourceLabel({ label, source, authLink }: { label: string; source: SweepSource; authLink?: string }) {
  const ago = source.last_sweep ? relativeTime(source.last_sweep) : null;
  const res = source.last_sweep_result;
  const igStatus = (source as SweepSource_IG).session_status;
  const expired = igStatus === "not_configured" && !source.authenticated;

  const dotColor = source.authenticated
    ? "text-green-500"
    : expired
      ? "text-amber-500"
      : "text-stone-300 dark:text-stone-600";
  const dot = source.authenticated ? "●" : expired ? "●" : "○";

  return (
    <span className="flex items-center gap-1">
      <span className={dotColor}>{dot}</span>
      {source.authenticated ? (
        <span>
          {label}
          {ago && res ? (
            <span className="ml-1">— {ago}, {res.processed} new</span>
          ) : ago ? (
            <span className="ml-1">— {ago}</span>
          ) : null}
        </span>
      ) : authLink ? (
        <a href={authLink} className="text-indigo-500 hover:text-indigo-700 dark:hover:text-indigo-300">
          connect {label}
        </a>
      ) : (
        <span>{label}{expired ? " — expired" : ""}</span>
      )}
    </span>
  );
}

function SweepBar({ status }: { status: SweepStatus }) {
  return (
    <div className="max-w-2xl mx-auto px-3 pt-2">
      <div className="flex items-center gap-3 text-xs text-stone-400 flex-wrap">
        <span className="font-mono">sweeps</span>
        <SweepSourceLabel label="twitter" source={status.twitter} authLink={`${API}/auth/twitter`} />
        <SweepSourceLabel label="instagram" source={status.ig_saved} />
      </div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div>
      <h3 className="text-xs font-semibold text-stone-400 uppercase tracking-wider mb-1">{title}</h3>
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
        className="text-xs font-semibold text-stone-400 uppercase tracking-wider mb-1 hover:text-stone-600 dark:hover:text-stone-300"
      >
        {open ? "▾" : "▸"} {title}
      </button>
      {open && children}
    </div>
  );
}
